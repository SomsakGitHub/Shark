import { createRemoteJWKSet, jwtVerify, SignJWT } from 'jose';
import type { Env, AuthUser } from './types';

const appleJWKS = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));

interface AppleIdTokenPayload {
  sub: string;
  email?: string | null;
  email_verified?: boolean;
  is_private_email?: boolean;
}

export async function verifyAppleIdentityToken(
  identityToken: string,
  env: Env,
): Promise<AppleIdTokenPayload> {
  const { payload } = await jwtVerify(identityToken, appleJWKS, {
    issuer: 'https://appleid.apple.com',
    audience: env.APP_BUNDLE_ID,
    algorithms: ['RS256'],
  });
  if (typeof payload.sub !== 'string' || payload.sub.length === 0) {
    throw new Error('missing sub claim');
  }
  return {
    sub: payload.sub,
    email: typeof payload.email === 'string' ? payload.email : null,
  };
}

const secret = (env: Env) => new TextEncoder().encode(env.AUTH_SECRET);

export async function signAppToken(env: Env, user: AuthUser): Promise<string> {
  return new SignJWT({ username: user.username, avatar_url: user.avatar_url })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(user.id)
    .setIssuedAt()
    .setExpirationTime('30d')
    .sign(secret(env));
}

export async function verifyAppToken(token: string, env: Env): Promise<AuthUser | null> {
  try {
    const { payload } = await jwtVerify(token, secret(env), { algorithms: ['HS256'] });
    if (typeof payload.sub !== 'string') return null;
    return {
      id: payload.sub,
      username: typeof payload.username === 'string' ? payload.username : '',
      avatar_url: typeof payload.avatar_url === 'string' ? payload.avatar_url : null,
      email: null,
    };
  } catch {
    return null;
  }
}
