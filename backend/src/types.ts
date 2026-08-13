export interface Env {
  DATABASE_URL: string;
  AUTH_SECRET: string;
  APP_BUNDLE_ID: string;
  VIDEOS: R2Bucket;
}

export interface AuthUser {
  id: string;
  username: string;
  avatar_url: string | null;
  email: string | null;
}
