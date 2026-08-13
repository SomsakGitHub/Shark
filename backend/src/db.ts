import { neon } from '@neondatabase/serverless';
import type { Env, AuthUser } from './types';

export type Sql = ReturnType<typeof neon>;

export function getDb(env: Env): Sql {
  return neon(env.DATABASE_URL);
}

export interface UserRow {
  id: string;
  username: string;
  email: string | null;
  avatar_url: string | null;
}

export async function upsertUserByAppleSub(
  db: Sql,
  appleSub: string,
  email: string | null,
  appleName: string | null,
): Promise<UserRow> {
  const username = appleName || `shark_${appleSub.slice(-6)}`;
  const rows = (await db`
    insert into users (apple_sub, email, username)
    values (${appleSub}, ${email}, ${username})
    on conflict (apple_sub) do update set email = excluded.email
    returning id, username, email, avatar_url
  `) as unknown as UserRow[];
  return rows[0];
}

export async function getUserById(db: Sql, userId: string): Promise<UserRow | null> {
  const rows = (await db`select id, username, email, avatar_url from users where id = ${userId}`) as unknown as UserRow[];
  return rows[0] ?? null;
}

export async function assertUserIsAuth(db: Sql, user: AuthUser): Promise<void> {
  const rows = (await db`select id from users where id = ${user.id}`) as unknown as { id: string }[];
  if (rows.length === 0) throw new Error('user not found');
}
