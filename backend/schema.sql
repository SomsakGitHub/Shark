-- Shark schema for Neon Postgres
-- Apply with: psql "$DATABASE_URL" -f schema.sql  (or via scripts/migrate.mjs)

create extension if not exists pgcrypto;

create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  apple_sub text unique not null,
  email text,
  username text not null,
  avatar_url text,
  bio text,
  created_at timestamptz not null default now()
);

create table if not exists videos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  key text not null unique,
  caption text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists likes (
  user_id uuid not null references users(id) on delete cascade,
  video_id uuid not null references videos(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, video_id)
);

create table if not exists comments (
  id uuid primary key default gen_random_uuid(),
  video_id uuid not null references videos(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  text text not null,
  created_at timestamptz not null default now()
);

create table if not exists follows (
  follower_id uuid not null references users(id) on delete cascade,
  followee_id uuid not null references users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followee_id)
);

create index if not exists idx_videos_created on videos (created_at desc, id desc);
create index if not exists idx_videos_user on videos (user_id);
create index if not exists idx_likes_video on likes (video_id);
create index if not exists idx_comments_video on comments (video_id, created_at);
create index if not exists idx_comments_user on comments (user_id);
create index if not exists idx_follows_followee on follows (followee_id);
create index if not exists idx_follows_follower on follows (follower_id);
create unique index if not exists idx_users_username on users (username);
alter table users add column if not exists bio text;
