import { Hono } from 'hono';
import type { MiddlewareHandler } from 'hono';
import { cors } from 'hono/cors';
import { verifyAppleIdentityToken, signAppToken, verifyAppToken } from './auth';
import { getDb, upsertUserByAppleSub, getUserById } from './db';
import type { Env, AuthUser } from './types';

type AppEnv = { Bindings: Env; Variables: { user: AuthUser } };

const app = new Hono<AppEnv>();

app.use('/api/*', cors());

const requireAuth: MiddlewareHandler<AppEnv> = async (c, next) => {
  const auth = c.req.header('Authorization');
  if (!auth || !auth.startsWith('Bearer ')) return c.json({ error: 'unauthorized' }, 401);
  const user = await verifyAppToken(auth.slice(7), c.env);
  if (!user) return c.json({ error: 'invalid token' }, 401);
  c.set('user', user);
  await next();
};

app.get('/api/health', (c) => c.json({ ok: true }));

app.post('/api/auth/apple', async (c) => {
  const body = await c.req.json<{ identityToken?: string; name?: string }>();
  if (!body.identityToken) return c.json({ error: 'identityToken required' }, 400);
  try {
    const payload = await verifyAppleIdentityToken(body.identityToken, c.env);
    const db = getDb(c.env);
    const user = await upsertUserByAppleSub(db, payload.sub, payload.email ?? null, body.name ?? null);
    const authUser: AuthUser = {
      id: user.id,
      username: user.username,
      avatar_url: user.avatar_url,
      email: user.email,
    };
    const token = await signAppToken(c.env, authUser);
    return c.json({ token, user: authUser });
  } catch {
    return c.json({ error: 'invalid apple identity token' }, 401);
  }
});

app.get('/api/me', requireAuth, async (c) => {
  const user = c.get('user');
  return c.json({ user });
});

const mapVideo = (row: Record<string, unknown>) => ({
  id: row.id,
  key: row.key,
  caption: row.caption,
  createdAt: row.created_at,
  user: {
    id: row.user_id,
    username: row.username,
    avatar_url: row.avatar_url,
  },
  likeCount: Number(row.like_count ?? 0),
  commentCount: Number(row.comment_count ?? 0),
  likedByMe: Boolean(row.liked_by_me),
});

app.get('/api/videos', requireAuth, async (c) => {
  const me = c.get('user').id;
  const limit = Math.min(Math.max(Number(c.req.query('limit') ?? 10), 1), 50);
  const cursor = c.req.query('cursor');
  const db = getDb(c.env);

  let rows: Record<string, unknown>[];
  if (cursor) {
    const [at, id] = cursor.split(',');
    rows = await db`
      select
        v.id, v.key, v.caption, v.created_at,
        u.id as user_id, u.username, u.avatar_url,
        (select count(*)::int from likes l where l.video_id = v.id) as like_count,
        (select count(*)::int from comments cm where cm.video_id = v.id) as comment_count,
        exists(select 1 from likes l where l.video_id = v.id and l.user_id = ${me}) as liked_by_me
      from videos v
      join users u on u.id = v.user_id
      where (v.created_at, v.id) < (${at}::timestamptz, ${id}::uuid)
      order by v.created_at desc, v.id desc
      limit ${limit}
    ` as unknown as Record<string, unknown>[];
  } else {
    rows = await db`
      select
        v.id, v.key, v.caption, v.created_at,
        u.id as user_id, u.username, u.avatar_url,
        (select count(*)::int from likes l where l.video_id = v.id) as like_count,
        (select count(*)::int from comments cm where cm.video_id = v.id) as comment_count,
        exists(select 1 from likes l where l.video_id = v.id and l.user_id = ${me}) as liked_by_me
      from videos v
      join users u on u.id = v.user_id
      order by v.created_at desc, v.id desc
      limit ${limit}
    ` as unknown as Record<string, unknown>[];
  }

  const videos = rows.map(mapVideo);
  const nextCursor =
    videos.length === limit
      ? `${(videos[videos.length - 1].createdAt as Date).toISOString()},${videos[videos.length - 1].id}`
      : null;
  return c.json({ videos, nextCursor });
});

app.put('/api/upload/:key', requireAuth, async (c) => {
  const user = c.get('user');
  const key = c.req.param('key');
  const contentType = c.req.header('Content-Type') ?? 'video/mp4';
  if (!/^video\//.test(contentType)) return c.json({ error: 'must upload video content' }, 415);
  const fullKey = `u/${user.id}/${key}`;
  const body = c.req.raw.body;
  if (!body) return c.json({ error: 'empty body' }, 400);
  await c.env.VIDEOS.put(fullKey, body, { httpMetadata: { contentType } });
  return c.json({ key: fullKey });
});

app.post('/api/videos', requireAuth, async (c) => {
  const user = c.get('user');
  const body = await c.req.json<{ key?: string; caption?: string }>();
  if (!body.key) return c.json({ error: 'key required' }, 400);
  const db = getDb(c.env);
  const rows = await db`
    insert into videos (user_id, key, caption)
    values (${user.id}, ${body.key}, ${body.caption ?? ''})
    returning id, key, caption, created_at,
      ${user.id} as user_id, ${user.username} as username, ${user.avatar_url} as avatar_url,
      0 as like_count, 0 as comment_count, false as liked_by_me
  ` as unknown as Record<string, unknown>[];
  return c.json({ video: mapVideo(rows[0]) }, 201);
});

app.get('/api/file/:key', async (c) => {
  const key = c.req.param('key');
  if (!key) return c.notFound();
  const range = c.req.header('Range');
  const obj = range ? await c.env.VIDEOS.get(key, { range }) : await c.env.VIDEOS.get(key);
  if (!obj) return c.notFound();

  const headers = new Headers();
  headers.set('Content-Type', obj.httpMetadata?.contentType ?? 'video/mp4');
  headers.set('Accept-Ranges', 'bytes');
  headers.set('Cache-Control', 'public, max-age=31536000, immutable');
  if (obj.range) {
    headers.set('Content-Range', obj.range as string);
    headers.set('Content-Length', obj.size.toString());
    return new Response(obj.body, { status: 206, headers });
  }
  headers.set('Content-Length', obj.size.toString());
  return new Response(obj.body, { status: 200, headers });
});

app.post('/api/videos/:id/like', requireAuth, async (c) => {
  const me = c.get('user').id;
  const videoId = c.req.param('id');
  const db = getDb(c.env);
  const existing = (await db`select 1 from likes where user_id = ${me} and video_id = ${videoId}`) as unknown as Record<string, unknown>[];
  let liked: boolean;
  if (existing.length > 0) {
    await db`delete from likes where user_id = ${me} and video_id = ${videoId}`;
    liked = false;
  } else {
    await db`insert into likes (user_id, video_id) values (${me}, ${videoId})`;
    liked = true;
  }
  const countRows = (await db`select count(*)::int as n from likes where video_id = ${videoId}`) as unknown as { n: number }[];
  const likeCount = Number(countRows[0].n);
  return c.json({ liked, likeCount });
});

app.get('/api/videos/:id/comments', async (c) => {
  const videoId = c.req.param('id');
  const db = getDb(c.env);
  const rows = await db`
    select cm.id, cm.text, cm.created_at, u.id as user_id, u.username, u.avatar_url
    from comments cm
    join users u on u.id = cm.user_id
    where cm.video_id = ${videoId}
    order by cm.created_at asc
  ` as unknown as Record<string, unknown>[];
  const comments = rows.map((r) => ({
    id: r.id,
    text: r.text,
    createdAt: r.created_at,
    user: { id: r.user_id, username: r.username, avatar_url: r.avatar_url },
  }));
  return c.json({ comments });
});

app.post('/api/videos/:id/comments', requireAuth, async (c) => {
  const me = c.get('user');
  const videoId = c.req.param('id');
  const body = await c.req.json<{ text?: string }>();
  const text = (body.text ?? '').trim();
  if (!text) return c.json({ error: 'text required' }, 400);
  const db = getDb(c.env);
  await db`
    insert into comments (video_id, user_id, text)
    values (${videoId}, ${me.id}, ${text})
  `;
  const all = await db`
    select cm.id, cm.text, cm.created_at, u.id as user_id, u.username, u.avatar_url
    from comments cm
    join users u on u.id = cm.user_id
    where cm.video_id = ${videoId}
    order by cm.created_at asc
  ` as unknown as Record<string, unknown>[];
  const comments = all.map((r) => ({
    id: r.id,
    text: r.text,
    createdAt: r.created_at,
    user: { id: r.user_id, username: r.username, avatar_url: r.avatar_url },
  }));
  return c.json({ comments }, 201);
});

app.post('/api/users/:id/follow', requireAuth, async (c) => {
  const me = c.get('user').id;
  const followeeId = c.req.param('id');
  if (me === followeeId) return c.json({ error: 'cannot follow yourself' }, 400);
  const db = getDb(c.env);
  const existing = (await db`
    select 1 from follows where follower_id = ${me} and followee_id = ${followeeId}
  `) as unknown as Record<string, unknown>[];
  let following: boolean;
  if (existing.length > 0) {
    await db`delete from follows where follower_id = ${me} and followee_id = ${followeeId}`;
    following = false;
  } else {
    await db`insert into follows (follower_id, followee_id) values (${me}, ${followeeId})`;
    following = true;
  }
  const countRows = (await db`
    select count(*)::int as n from follows where followee_id = ${followeeId}
  `) as unknown as { n: number }[];
  const followerCount = Number(countRows[0].n);
  return c.json({ following, followerCount });
});

app.get('/api/users/:id', async (c) => {
  const userId = c.req.param('id');
  const db = getDb(c.env);
  const profile = await getUserById(db, userId);
  if (!profile) return c.notFound();
  const videoRows = await db`
    select v.id, v.key, v.caption, v.created_at,
      u.id as user_id, u.username, u.avatar_url,
      (select count(*)::int from likes l where l.video_id = v.id) as like_count,
      (select count(*)::int from comments cm where cm.video_id = v.id) as comment_count,
      false as liked_by_me
    from videos v join users u on u.id = v.user_id
    where v.user_id = ${userId}
    order by v.created_at desc
  ` as unknown as Record<string, unknown>[];
  const counts = await db`
    select
      (select count(*)::int from videos v where v.user_id = ${userId}) as video_count,
      (select count(*)::int from follows f where f.followee_id = ${userId}) as follower_count,
      (select count(*)::int from follows f where f.follower_id = ${userId}) as following_count
  ` as unknown as Record<string, unknown>[];
  return c.json({
    user: profile,
    counts: {
      videoCount: Number(counts[0].video_count),
      followerCount: Number(counts[0].follower_count),
      followingCount: Number(counts[0].following_count),
    },
    videos: videoRows.map(mapVideo),
  });
});

app.onError((err, c) => {
  console.error(err);
  return c.json({ error: 'internal server error' }, 500);
});

export default app;
