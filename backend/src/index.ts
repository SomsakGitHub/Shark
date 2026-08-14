import { Hono } from 'hono';
import type { MiddlewareHandler } from 'hono';
import { cors } from 'hono/cors';
import { verifyAppleIdentityToken, signAppToken, verifyAppToken } from './auth';
import { getDb, upsertUserByAppleSub, getUserById, updateUserProfile } from './db';
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

const optionalAuth: MiddlewareHandler<AppEnv> = async (c, next) => {
  const auth = c.req.header('Authorization');
  if (auth && auth.startsWith('Bearer ')) {
    const user = await verifyAppToken(auth.slice(7), c.env);
    if (user) c.set('user', user);
  }
  await next();
};

const meOf = (c: Parameters<MiddlewareHandler<AppEnv>>[0]) =>
  (c.get('user') as AuthUser | undefined)?.id ?? '';

const MAX_VIDEO_BYTES = 100 * 1024 * 1024;
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;

const contentLength = (c: Parameters<MiddlewareHandler<AppEnv>>[0]): number | null => {
  const raw = c.req.header('Content-Length');
  if (!raw) return null;
  const n = Number(raw);
  return Number.isFinite(n) ? n : null;
};

function enforceMaxBytes(body: ReadableStream<Uint8Array>, maxBytes: number): ReadableStream<Uint8Array> {
  const reader = body.getReader();
  let sent = 0;
  return new ReadableStream<Uint8Array>({
    async pull(controller) {
      const { done, value } = await reader.read();
      if (done) {
        controller.close();
        return;
      }
      sent += value.byteLength;
      if (sent > maxBytes) {
        await reader.cancel();
        controller.error(new Error('body too large'));
        return;
      }
      controller.enqueue(value);
    },
    cancel() {
      reader.cancel();
    },
  });
}

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
  const db = getDb(c.env);
  const fresh = await getUserById(db, user.id);
  if (!fresh) return c.json({ error: 'user not found' }, 401);
  return c.json({ user: fresh });
});

app.patch('/api/me', requireAuth, async (c) => {
  const me = c.get('user');
  const body = await c.req.json<{ username?: string; bio?: string }>();
  const username = (body.username ?? '').trim();
  const bio = (body.bio ?? '').trim();
  if (!/^[a-zA-Z0-9_.]{3,24}$/.test(username)) {
    return c.json({ error: 'username must be 3-24 characters using letters, numbers, _ or .' }, 400);
  }
  if (bio.length > 160) {
    return c.json({ error: 'bio must be 160 characters or fewer' }, 400);
  }
  const db = getDb(c.env);
  try {
    const updated = await updateUserProfile(db, me.id, { username, bio });
    return c.json({ user: updated });
  } catch (err) {
    if ((err as { code?: string }).code === '23505') {
      return c.json({ error: 'username already taken' }, 409);
    }
    throw err;
  }
});

app.put('/api/me/avatar', requireAuth, async (c) => {
  const user = c.get('user');
  const contentType = c.req.header('Content-Type') ?? '';
  if (!/^image\//.test(contentType)) return c.json({ error: 'must upload an image' }, 415);
  const declared = contentLength(c);
  if (declared != null && declared > MAX_IMAGE_BYTES) {
    return c.json({ error: 'image too large (max 5 MB)' }, 413);
  }
  const body = c.req.raw.body;
  if (!body) return c.json({ error: 'empty body' }, 400);
  const key = `avatar-${user.id}`;
  try {
    await c.env.VIDEOS.put(key, enforceMaxBytes(body, MAX_IMAGE_BYTES), { httpMetadata: { contentType } });
  } catch {
    return c.json({ error: 'image too large (max 5 MB)' }, 413);
  }
  const avatarUrl = `/api/avatar/${user.id}`;
  const db = getDb(c.env);
  await db`update users set avatar_url = ${avatarUrl} where id = ${user.id}`;
  return c.json({ avatarUrl });
});

app.get('/api/avatar/:id', async (c) => {
  const id = c.req.param('id');
  const obj = await c.env.VIDEOS.get(`avatar-${id}`);
  if (!obj) return c.notFound();
  const headers = new Headers();
  headers.set('Content-Type', obj.httpMetadata?.contentType ?? 'image/jpeg');
  headers.set('Cache-Control', 'public, max-age=31536000, immutable');
  headers.set('Content-Length', obj.size.toString());
  return new Response(obj.body, { status: 200, headers });
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

const fetchFeed = async (db: ReturnType<typeof getDb>, me: string, limit: number, cursor: string | null | undefined, followingOnly: boolean) => {
  const followingWhere = followingOnly
    ? `v.user_id in (select f.followee_id from follows f where f.follower_id = $1)`
    : null;
  const likedExpr =
    'exists(select 1 from likes l where l.video_id = v.id and l.user_id = nullif($1, \'\')::uuid)';
  const base = `
    select
      v.id, v.key, v.caption, v.created_at,
      u.id as user_id, u.username, u.avatar_url,
      (select count(*)::int from likes l where l.video_id = v.id) as like_count,
      (select count(*)::int from comments cm where cm.video_id = v.id) as comment_count,
      ${likedExpr} as liked_by_me
    from videos v
    join users u on u.id = v.user_id
  `;
  const where = followingWhere ?? 'true';

  let rows: Record<string, unknown>[];
  if (cursor) {
    const [at, id] = cursor.split(',');
    rows = (await db(
      `${base} where ${where} and (v.created_at, v.id) < ($2::timestamptz, $3::uuid) order by v.created_at desc, v.id desc limit $4`,
      [me || null, at, id, limit],
    )) as unknown as Record<string, unknown>[];
  } else {
    rows = (await db(
      `${base} where ${where} order by v.created_at desc, v.id desc limit $2`,
      [me || null, limit],
    )) as unknown as Record<string, unknown>[];
  }

  const videos = rows.map(mapVideo);
  const nextCursor =
    videos.length === limit
      ? `${(videos[videos.length - 1].createdAt as Date).toISOString()},${videos[videos.length - 1].id}`
      : null;
  return { videos, nextCursor };
};

app.get('/api/videos', optionalAuth, async (c) => {
  const me = meOf(c);
  const limit = Math.min(Math.max(Number(c.req.query('limit') ?? 10), 1), 50);
  const cursor = c.req.query('cursor');
  return c.json(await fetchFeed(getDb(c.env), me, limit, cursor, false));
});

app.get('/api/videos/following', requireAuth, async (c) => {
  const me = c.get('user').id;
  const limit = Math.min(Math.max(Number(c.req.query('limit') ?? 10), 1), 50);
  const cursor = c.req.query('cursor');
  return c.json(await fetchFeed(getDb(c.env), me, limit, cursor, true));
});

app.get('/api/videos/:id', optionalAuth, async (c) => {
  const me = meOf(c);
  const videoId = c.req.param('id');
  const db = getDb(c.env);
  const rows = await db`
    select
      v.id, v.key, v.caption, v.created_at,
      u.id as user_id, u.username, u.avatar_url,
      (select count(*)::int from likes l where l.video_id = v.id) as like_count,
      (select count(*)::int from comments cm where cm.video_id = v.id) as comment_count,
      exists(select 1 from likes l where l.video_id = v.id and l.user_id = nullif(${me}, '')::uuid) as liked_by_me
    from videos v
    join users u on u.id = v.user_id
    where v.id = ${videoId}
  ` as unknown as Record<string, unknown>[];
  if (rows.length === 0) return c.notFound();
  return c.json({ video: mapVideo(rows[0]) });
});

const mapUserSummary = (r: Record<string, unknown>) => ({
  id: r.id,
  username: r.username,
  avatar_url: r.avatar_url,
  followerCount: Number(r.follower_count ?? 0),
  followedByMe: Boolean(r.followed_by_me),
});

app.get('/api/search', optionalAuth, async (c) => {
  const me = meOf(c);
  const q = (c.req.query('q') ?? '').trim();
  if (!q) return c.json({ users: [], videos: [] });
  const db = getDb(c.env);
  const pattern = `%${q}%`;
  const meParam = me ? [me] : [];
  const followedByMeExpr = me
    ? `exists(select 1 from follows f where f.follower_id = $2 and f.followee_id = u.id)`
    : 'false';
  const userRows = (await db(`
    select u.id, u.username, u.avatar_url,
      (select count(*)::int from follows f where f.followee_id = u.id) as follower_count,
      ${followedByMeExpr} as followed_by_me
    from users u
    where ${me ? `u.id <> $2 and ` : ''}u.username ilike $1
    order by follower_count desc
    limit 20
  `, [pattern, ...meParam])) as unknown as Record<string, unknown>[];
  const likedByMeExpr = me
    ? `exists(select 1 from likes l where l.video_id = v.id and l.user_id = $2)`
    : 'false';
  const videoRows = (await db(`
    select v.id, v.key, v.caption, v.created_at,
      u.id as user_id, u.username, u.avatar_url,
      (select count(*)::int from likes l where l.video_id = v.id) as like_count,
      (select count(*)::int from comments cm where cm.video_id = v.id) as comment_count,
      ${likedByMeExpr} as liked_by_me
    from videos v join users u on u.id = v.user_id
    where v.caption ilike $1
    order by v.created_at desc
    limit 20
  `, [pattern, ...meParam])) as unknown as Record<string, unknown>[];
  return c.json({ users: userRows.map(mapUserSummary), videos: videoRows.map(mapVideo) });
});

app.get('/api/explore', optionalAuth, async (c) => {
  const me = meOf(c);
  const db = getDb(c.env);
  const meParam = me ? [me] : [];
  const userWhere = me
    ? `u.id <> $1 and not exists(select 1 from follows f where f.follower_id = $1 and f.followee_id = u.id)`
    : 'true';
  const userRows = (await db(`
    select u.id, u.username, u.avatar_url,
      (select count(*)::int from follows f where f.followee_id = u.id) as follower_count,
      false as followed_by_me
    from users u
    where ${userWhere}
    order by follower_count desc, u.created_at desc
    limit 10
  `, meParam)) as unknown as Record<string, unknown>[];
  const likedByMeExpr = me
    ? `exists(select 1 from likes l where l.video_id = v.id and l.user_id = $1)`
    : 'false';
  const videoRows = (await db(`
    select v.id, v.key, v.caption, v.created_at,
      u.id as user_id, u.username, u.avatar_url,
      (select count(*)::int from likes l where l.video_id = v.id) as like_count,
      (select count(*)::int from comments cm where cm.video_id = v.id) as comment_count,
      ${likedByMeExpr} as liked_by_me
    from videos v join users u on u.id = v.user_id
    order by v.created_at desc
    limit 20
  `, meParam)) as unknown as Record<string, unknown>[];
  return c.json({ users: userRows.map(mapUserSummary), videos: videoRows.map(mapVideo) });
});

app.put('/api/upload/:key', requireAuth, async (c) => {
  const user = c.get('user');
  const key = c.req.param('key');
  const contentType = c.req.header('Content-Type') ?? 'video/mp4';
  if (!/^video\//.test(contentType)) return c.json({ error: 'must upload video content' }, 415);
  const declared = contentLength(c);
  if (declared != null && declared > MAX_VIDEO_BYTES) {
    return c.json({ error: 'video too large (max 100 MB)' }, 413);
  }
  const fullKey = `${user.id}-${key}`;
  const body = c.req.raw.body;
  if (!body) return c.json({ error: 'empty body' }, 400);
  try {
    await c.env.VIDEOS.put(fullKey, enforceMaxBytes(body, MAX_VIDEO_BYTES), { httpMetadata: { contentType } });
  } catch {
    return c.json({ error: 'video too large (max 100 MB)' }, 413);
  }
  return c.json({ key: fullKey });
});

app.post('/api/videos', requireAuth, async (c) => {
  const user = c.get('user');
  const body = await c.req.json<{ key?: string; caption?: string }>();
  if (!body.key) return c.json({ error: 'key required' }, 400);
  const db = getDb(c.env);
  const me = await getUserById(db, user.id);
  if (!me) return c.json({ error: 'user not found' }, 401);
  const rows = await db`
    insert into videos (user_id, key, caption)
    values (${user.id}, ${body.key}, ${body.caption ?? ''})
    returning id, key, caption, created_at,
      ${user.id} as user_id, ${me.username} as username, ${me.avatar_url} as avatar_url,
      0 as like_count, 0 as comment_count, false as liked_by_me
  ` as unknown as Record<string, unknown>[];
  return c.json({ video: mapVideo(rows[0]) }, 201);
});

app.get('/api/file/:key', async (c) => {
  const key = c.req.param('key');
  if (!key) return c.notFound();

  const rangeHeader = c.req.header('Range');
  let r2Range: R2Range | undefined;
  let start = 0;
  let end = start;

  if (rangeHeader) {
    const match = rangeHeader.match(/^bytes=(\d*)-(\d*)$/);
    if (match && (match[1] !== '' || match[2] !== '')) {
      const head = await c.env.VIDEOS.head(key);
      const total = head?.size ?? 0;
      if (match[1] === '') {
        const suffix = Number(match[2]);
        start = Math.max(0, total - suffix);
        end = total - 1;
      } else {
        start = Number(match[1]);
        end = match[2] === '' ? total - 1 : Math.min(Number(match[2]), total - 1);
      }
      if (start > end || start >= total) {
        return new Response(null, {
          status: 416,
          headers: { 'Content-Range': `bytes */${total}` },
        });
      }
      r2Range = { offset: start, length: end - start + 1 };
    }
  }

  const obj = r2Range
    ? await c.env.VIDEOS.get(key, { range: r2Range })
    : await c.env.VIDEOS.get(key);
  if (!obj) return c.notFound();

  const headers = new Headers();
  headers.set('Content-Type', obj.httpMetadata?.contentType ?? 'video/mp4');
  headers.set('Accept-Ranges', 'bytes');
  headers.set('Cache-Control', 'public, max-age=31536000, immutable');
  if (r2Range) {
    headers.set('Content-Range', `bytes ${start}-${end}/${obj.size}`);
    headers.set('Content-Length', (end - start + 1).toString());
    return new Response(obj.body, { status: 206, headers });
  }
  headers.set('Content-Length', obj.size.toString());
  return new Response(obj.body, { status: 200, headers });
});

app.put('/api/thumbnail/:key', requireAuth, async (c) => {
  const key = c.req.param('key');
  const contentType = c.req.header('Content-Type') ?? 'image/jpeg';
  if (!/^image\//.test(contentType)) return c.json({ error: 'must upload image content' }, 415);
  const declared = contentLength(c);
  if (declared != null && declared > MAX_IMAGE_BYTES) {
    return c.json({ error: 'image too large (max 5 MB)' }, 413);
  }
  const body = c.req.raw.body;
  if (!body) return c.json({ error: 'empty body' }, 400);
  try {
    await c.env.VIDEOS.put(`${key}.jpg`, enforceMaxBytes(body, MAX_IMAGE_BYTES), { httpMetadata: { contentType } });
  } catch {
    return c.json({ error: 'image too large (max 5 MB)' }, 413);
  }
  return c.json({ key });
});

app.get('/api/thumb/:key', async (c) => {
  const key = c.req.param('key');
  const obj = await c.env.VIDEOS.get(`${key}.jpg`);
  if (!obj) return c.notFound();
  const headers = new Headers();
  headers.set('Content-Type', obj.httpMetadata?.contentType ?? 'image/jpeg');
  headers.set('Cache-Control', 'public, max-age=31536000, immutable');
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

app.post('/api/videos/:id/comments', requireAuth, async (c) => {  const me = c.get('user');
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

app.delete('/api/videos/:id/comments/:commentId', requireAuth, async (c) => {
  const me = c.get('user').id;
  const videoId = c.req.param('id');
  const commentId = c.req.param('commentId');
  const db = getDb(c.env);
  const rows = (await db`
    select user_id from comments where id = ${commentId} and video_id = ${videoId}
  `) as unknown as { user_id: string }[];
  if (rows.length === 0) return c.notFound();
  if (rows[0].user_id !== me) return c.json({ error: 'not your comment' }, 403);
  await db`delete from comments where id = ${commentId}`;
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
  return c.json({ comments });
});

app.delete('/api/videos/:id', requireAuth, async (c) => {
  const me = c.get('user').id;
  const videoId = c.req.param('id');
  const db = getDb(c.env);
  const rows = (await db`
    select key, user_id from videos where id = ${videoId}
  `) as unknown as { key: string; user_id: string }[];
  if (rows.length === 0) return c.notFound();
  if (rows[0].user_id !== me) return c.json({ error: 'not your video' }, 403);
  const videoKey = rows[0].key;
  await db`delete from videos where id = ${videoId}`;
  await Promise.all([
    c.env.VIDEOS.delete(videoKey),
    c.env.VIDEOS.delete(`${videoKey}.jpg`),
  ]);
  return c.json({ deleted: true });
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

app.get('/api/users/:id', optionalAuth, async (c) => {
  const me = meOf(c);
  const userId = c.req.param('id');
  const db = getDb(c.env);
  const profile = await getUserById(db, userId);
  if (!profile) return c.notFound();
  const videoRows = await db`
    select v.id, v.key, v.caption, v.created_at,
      u.id as user_id, u.username, u.avatar_url,
      (select count(*)::int from likes l where l.video_id = v.id) as like_count,
      (select count(*)::int from comments cm where cm.video_id = v.id) as comment_count,
      exists(select 1 from likes l where l.video_id = v.id and l.user_id = nullif(${me}, '')::uuid) as liked_by_me
    from videos v join users u on u.id = v.user_id
    where v.user_id = ${userId}
    order by v.created_at desc
  ` as unknown as Record<string, unknown>[];
  const counts = await db`
    select
      (select count(*)::int from videos v where v.user_id = ${userId}) as video_count,
      (select count(*)::int from follows f where f.followee_id = ${userId}) as follower_count,
      (select count(*)::int from follows f where f.follower_id = ${userId}) as following_count,
      exists(select 1 from follows f where f.follower_id = nullif(${me}, '')::uuid and f.followee_id = ${userId}) as followed_by_me
  ` as unknown as Record<string, unknown>[];
  return c.json({
    user: profile,
    counts: {
      videoCount: Number(counts[0].video_count),
      followerCount: Number(counts[0].follower_count),
      followingCount: Number(counts[0].following_count),
      followedByMe: Boolean(counts[0].followed_by_me),
    },
    videos: videoRows.map(mapVideo),
  });
});

app.get('/api/users/:id/followers', requireAuth, async (c) => {
  const me = c.get('user').id;
  const userId = c.req.param('id');
  const db = getDb(c.env);
  const rows = (await db`
    select u.id, u.username, u.avatar_url,
      (select count(*)::int from follows f where f.followee_id = u.id) as follower_count,
      exists(select 1 from follows f where f.follower_id = ${me} and f.followee_id = u.id) as followed_by_me
    from follows fo
    join users u on u.id = fo.follower_id
    where fo.followee_id = ${userId}
    order by fo.created_at desc
    limit 50
  `) as unknown as Record<string, unknown>[];
  return c.json({ users: rows.map(mapUserSummary) });
});

app.get('/api/users/:id/following', requireAuth, async (c) => {
  const me = c.get('user').id;
  const userId = c.req.param('id');
  const db = getDb(c.env);
  const rows = (await db`
    select u.id, u.username, u.avatar_url,
      (select count(*)::int from follows f where f.followee_id = u.id) as follower_count,
      exists(select 1 from follows f where f.follower_id = ${me} and f.followee_id = u.id) as followed_by_me
    from follows fo
    join users u on u.id = fo.followee_id
    where fo.follower_id = ${userId}
    order by fo.created_at desc
    limit 50
  `) as unknown as Record<string, unknown>[];
  return c.json({ users: rows.map(mapUserSummary) });
});

const escapeHtml = (value: string) =>
  value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');

app.get('/v/:id', async (c) => {
  const videoId = c.req.param('id');
  const db = getDb(c.env);
  const rows = (await db`
    select v.id, v.key, v.caption, u.username
    from videos v join users u on u.id = v.user_id
    where v.id = ${videoId}
  `) as unknown as Record<string, unknown>[];
  if (rows.length === 0) return c.notFound();
  const video = rows[0];
  const origin = new URL(c.req.url).origin;
  const webUrl = `${origin}/v/${video.id}`;
  const deepLink = `shark://video/${video.id}`;
  const caption = typeof video.caption === 'string' ? escapeHtml(video.caption) : '';

  return c.html(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta property="og:title" content="@${video.username} on Shark">
<meta property="og:description" content="Watch this video on Shark">
<title>@${video.username} on Shark</title>
<style>
  body { margin:0; background:#000; color:#fff; font-family:-apple-system,system-ui,sans-serif; display:flex; flex-direction:column; align-items:center; min-height:100vh; }
  .wrap { width:100%; max-width:420px; padding:16px; box-sizing:border-box; }
  video { width:100%; aspect-ratio:9/16; background:#111; border-radius:16px; }
  .meta { margin-top:12px; }
  .user { font-weight:700; font-size:16px; }
  .caption { color:#bbb; font-size:14px; margin-top:4px; }
  .actions { display:flex; gap:12px; margin-top:16px; }
  .btn { flex:1; text-align:center; padding:12px; border-radius:999px; font-weight:600; font-size:15px; }
  .open { background:#fff; color:#000; text-decoration:none; }
  .copy { background:#222; color:#fff; border:none; cursor:pointer; }
</style>
</head>
<body>
<div class="wrap">
  <video src="/api/file/${video.key}" controls autoplay muted loop playsinline></video>
  <div class="meta">
    <div class="user">@${video.username}</div>
    ${caption ? `<div class="caption">${caption}</div>` : ''}
  </div>
  <div class="actions">
    <a class="btn open" href="${deepLink}">Open in Shark</a>
    <button class="btn copy" onclick="copyLink()">Copy Link</button>
  </div>
</div>
<script>
async function copyLink() {
  try {
    await navigator.clipboard.writeText("${webUrl}");
    document.querySelector('.copy').textContent = 'Copied!';
  } catch (e) {}
}
</script>
</body>
</html>`);
});

app.onError((err, c) => {
  console.error(err);
  return c.json({ error: 'internal server error' }, 500);
});

export default app;
