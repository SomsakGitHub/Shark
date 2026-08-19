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
  { file: 'cat_funny.mp4', thumb: 'cat_funny.jpg', caption: 'แมวตลกทำหน้าไม่เข้ากับ Situation 555 #cat #funny #แมวตลก' },
  { file: 'cat_3d.mp4', thumb: 'cat_3d.jpg', caption: 'น้องแมว 3D สุดน่ารัก ขยับได้เหมือนจริงมาก #cat3d #cute #แมว' },
  { file: 'cat_sleepy.mp4', thumb: 'cat_sleepy.jpg', caption: 'น้องแมวหลับปุ๋ย น่ารักจนอยากงีบตาม #sleepycat #relax #แมวหลับ' },
  { file: 'dog_funny.mp4', thumb: 'dog_funny.jpg', caption: 'สุนัขตลกทำท่าทางฮาๆ ดูแล้วหัวเราะแน่นอน #dog #funny #หมาตลก' },
  { file: 'dog_brown.mp4', thumb: 'dog_brown.jpg', caption: 'น้องหมาสีน้ำตาลสุด Cute มองกล้องแบบตะลึง #dog #cute #หมา' },
  { file: 'puppy_beach.mp4', thumb: 'puppy_beach.jpg', caption: 'ลูกหมาวิ่งเล่นที่ชายหาด สนุกสุดเหวี่ยง! #puppy #beach #ลูกหมา' },
  { file: 'puppy_play.mp4', thumb: 'puppy_play.jpg', caption: 'ลูกหมาเล่นของเล่น ดูแล้วใจละลาย #puppy #playful #ลูกหมาเล่น' },
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

  console.log('uploading videos...');
  const videos = [];
  for (let i = 0; i < VIDEOS.length; i++) {
    const v = VIDEOS[i];
    const user = users[i % users.length];
    videos.push(await uploadVideo(user.token, user, v.file));
  }

  console.log('seeding interactions...');
  const [u1, u2, u3] = users;

  // each user likes a few random videos
  for (const user of users) {
    const randomVideos = videos
      .sort(() => Math.random() - 0.5)
      .slice(0, Math.min(3, videos.length));
    for (const v of randomVideos) {
      await db`insert into likes (user_id, video_id) values (${user.id}, ${v.id}) on conflict do nothing`;
    }
  }

  // a few comments
  const commentTexts = [
    'ฮาาก 555',
    'น่ารักมากกก',
    'ดูแล้วใจละลาย',
    'ขำหนักมาก',
    'น้องๆ โคตรน่ารัก',
    'ต้องแชร์ต่อเลย',
    'ดูไม่เบื่อเลย',
    'SO CUTE!!!',
    '55555555',
    'อยากได้บ้างอ่ะ',
  ];
  for (const v of videos.slice(0, 5)) {
    const user = users[Math.floor(Math.random() * users.length)];
    const text = commentTexts[Math.floor(Math.random() * commentTexts.length)];
    await db`insert into comments (video_id, user_id, text) values (${v.id}, ${user.id}, ${text})`;
  }

  // follow relationships
  await db`insert into follows (follower_id, followee_id) values (${u2.id}, ${u1.id}) on conflict do nothing`;
  await db`insert into follows (follower_id, followee_id) values (${u3.id}, ${u1.id}) on conflict do nothing`;
  await db`insert into follows (follower_id, followee_id) values (${u1.id}, ${u2.id}) on conflict do nothing`;

  console.log('\nDone. Users:');
  for (const u of users) console.log(`  @${u.username} (${u.id})`);
  console.log('\nFeed URL: ' + BASE_URL + '/api/videos');
}

seed().catch((err) => {
  console.error(err);
  process.exit(1);
});
