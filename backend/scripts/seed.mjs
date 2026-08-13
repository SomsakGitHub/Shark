import { readFileSync, readdirSync } from 'node:fs';
import { neon } from '@neondatabase/serverless';
import { SignJWT } from 'jose';

const BASE_URL = process.env.SHARK_API_URL ?? 'https://shark-api.js6ctz7gtj.workers.dev';

const vars = readFileSync(new URL('../.dev.vars', import.meta.url), 'utf8');
const getVar = (name) => vars.match(new RegExp(`${name}="([^"]*)"`))?.[1] ?? '';

const DATABASE_URL = process.env.DATABASE_URL ?? getVar('DATABASE_URL');
const AUTH_SECRET = process.env.AUTH_SECRET ?? getVar('AUTH_SECRET');

if (!DATABASE_URL || !AUTH_SECRET) {
  console.error('DATABASE_URL and AUTH_SECRET are required (set in .dev.vars or env)');
  process.exit(1);
}

const db = neon(DATABASE_URL);
const secret = new TextEncoder().encode(AUTH_SECRET);

const DEMO_USERS = [
  { appleSub: 'demo-user-shark-life', username: 'shark_life' },
  { appleSub: 'demo-user-kawaii', username: 'kawaii_meow' },
  { appleSub: 'demo-user-runner', username: 'mountain_runner' },
];

const VIDEOS = [
  { file: 'flower.mp4', thumb: 'flower.jpg', caption: 'ชมความงามของธรรมชาติระหว่างทางขึ้นเขา #flower #nature' },
  { file: 'bbb10s.mp4', thumb: 'bbb10s.jpg', caption: 'บิ๊กบั๊กบันนี่กลับมาแล้ว #animation #fun' },
];

async function createUser(user) {
  const rows = await db`
    insert into users (apple_sub, username)
    values (${user.appleSub}, ${user.username})
    on conflict (apple_sub) do update set username = excluded.username
    returning id, username
  `;
  return rows[0];
}

async function makeToken(userId, username) {
  return new SignJWT({ username, avatar_url: null })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(userId)
    .setIssuedAt()
    .setExpirationTime('30d')
    .sign(secret);
}

async function uploadVideo(token, user, file) {
  const data = readFileSync(new URL(`../samples/${file}`, import.meta.url));
  const localKey = `${crypto.randomUUID()}.mp4`;

  const uploadRes = await fetch(`${BASE_URL}/api/upload/${localKey}`, {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'video/mp4',
    },
    body: data,
  });
  if (!uploadRes.ok) throw new Error(`upload failed: ${uploadRes.status} ${await uploadRes.text()}`);
  const { key } = await uploadRes.json();

  const config = VIDEOS.find((v) => v.file === file);
  const thumbData = readFileSync(new URL(`../samples/${config.thumb}`, import.meta.url));
  await fetch(`${BASE_URL}/api/thumbnail/${key}`, {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'image/jpeg',
    },
    body: thumbData,
  });

  const createRes = await fetch(`${BASE_URL}/api/videos`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ key, caption: config.caption }),
  });
  if (!createRes.ok) throw new Error(`create failed: ${createRes.status} ${await createRes.text()}`);
  const { video } = await createRes.json();
  console.log(`uploaded: ${user.username} -> ${file} (${video.id})`);
  return video;
}

async function seed() {
  console.log('cleaning previous demo data...');
  const demoSubs = DEMO_USERS.map((u) => u.appleSub);
  await db`
    delete from likes where video_id in (
      select v.id from videos v join users u on u.id = v.user_id where u.apple_sub = any(${demoSubs})
    )
  `;
  await db`
    delete from comments where video_id in (
      select v.id from videos v join users u on u.id = v.user_id where u.apple_sub = any(${demoSubs})
    )
  `;
  await db`
    delete from videos where user_id in (select id from users where apple_sub = any(${demoSubs}))
  `;
  await db`delete from follows where follower_id in (select id from users where apple_sub = any(${demoSubs})) or followee_id in (select id from users where apple_sub = any(${demoSubs}))`;

  console.log('creating demo users...');
  const users = [];
  for (const u of DEMO_USERS) {
    const user = await createUser(u);
    users.push({ ...user, token: await makeToken(user.id, user.username) });
  }

  const [u1, u2, u3] = users;
  const videos = [];
  videos.push(await uploadVideo(u1.token, u1, 'flower.mp4'));
  videos.push(await uploadVideo(u2.token, u2, 'bbb10s.mp4'));

  console.log('seeding interactions...');
  const [v1, v2] = videos;
  await db`insert into likes (user_id, video_id) values (${u2.id}, ${v1.id})`;
  await db`insert into likes (user_id, video_id) values (${u3.id}, ${v1.id})`;
  await db`insert into likes (user_id, video_id) values (${u1.id}, ${v2.id})`;
  await db`insert into likes (user_id, video_id) values (${u3.id}, ${v2.id})`;

  await db`
    insert into comments (video_id, user_id, text) values
    (${v1.id}, ${u2.id}, 'สวยมากอยากไปบ้าง'),
    (${v1.id}, ${u3.id}, 'เก็บไว้เป็นเส้นทางวิ่งดีๆ นี่แหละ'),
    (${v2.id}, ${u1.id}, 'น่ารักมาก 555'),
    (${v2.id}, ${u3.id}, 'เอาไปอัดวิดีโอออนไลน์อีกแล้ว')
  `;

  await db`
    insert into follows (follower_id, followee_id) values
    (${u2.id}, ${u1.id}),
    (${u3.id}, ${u1.id}),
    (${u1.id}, ${u2.id})
  `;

  console.log('\nDone. Users:');
  for (const u of users) console.log(`  @${u.username} (${u.id})`);
  console.log('\nFeed URL: ' + BASE_URL + '/api/videos');
}

seed().catch((err) => {
  console.error(err);
  process.exit(1);
});
