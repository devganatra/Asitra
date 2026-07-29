import { env } from "cloudflare:workers";
import { database } from "../security";

const DEFAULT_APPLE_AUDIENCE = "com.devganatra.sakhya";
const SESSION_LIFETIME_SECONDS = 60 * 60 * 24 * 30;
const MAX_REQUESTS_PER_HOUR = 60;

type AppleTokenHeader = { alg?: string; kid?: string };
type AppleTokenClaims = {
  iss?: string;
  aud?: string | string[];
  exp?: number;
  iat?: number;
  sub?: string;
};
type AppleJWK = JsonWebKey & { kid?: string; alg?: string };
type AppleKeysResponse = { keys?: AppleJWK[] };
type NativeEnvironment = { APPLE_SIGN_IN_AUDIENCE?: string };

export async function createNativeSession(identityToken: string) {
  const claims = await verifyAppleIdentityToken(identityToken);
  const userId = await sha256Hex(`apple:${claims.sub}`);
  const tokenBytes = crypto.getRandomValues(new Uint8Array(32));
  const sessionToken = base64URL(tokenBytes);
  const tokenHash = await sha256Hex(sessionToken);
  const now = new Date();
  const expiresAt = new Date(now.getTime() + SESSION_LIFETIME_SECONDS * 1_000);

  await database()
    .prepare(
      `INSERT INTO native_sessions (token_hash, user_id, created_at, expires_at, last_used_at)
       VALUES (?, ?, ?, ?, ?)`,
    )
    .bind(tokenHash, userId, now.toISOString(), expiresAt.toISOString(), now.toISOString())
    .run();

  return { sessionToken, expiresAt: expiresAt.toISOString() };
}

export async function authenticatedNativeUser(request: Request): Promise<string | null> {
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) return null;
  const token = authorization.slice("Bearer ".length).trim();
  if (!token || token.length > 256) return null;
  const tokenHash = await sha256Hex(token);
  const row = await database()
    .prepare(
      `SELECT user_id AS userId, expires_at AS expiresAt
       FROM native_sessions WHERE token_hash = ?`,
    )
    .bind(tokenHash)
    .first<{ userId: string; expiresAt: string }>();
  if (!row) return null;
  if (Date.parse(row.expiresAt) <= Date.now()) {
    await database().prepare("DELETE FROM native_sessions WHERE token_hash = ?").bind(tokenHash).run();
    return null;
  }
  await database()
    .prepare("UPDATE native_sessions SET last_used_at = ? WHERE token_hash = ?")
    .bind(new Date().toISOString(), tokenHash)
    .run();
  return row.userId;
}

export async function revokeNativeSession(request: Request): Promise<boolean> {
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) return false;
  const token = authorization.slice("Bearer ".length).trim();
  if (!token || token.length > 256) return false;
  const tokenHash = await sha256Hex(token);
  await database().prepare("DELETE FROM native_sessions WHERE token_hash = ?").bind(tokenHash).run();
  return true;
}

export async function consumeNativeAIRateLimit(userId: string): Promise<boolean> {
  const now = new Date();
  now.setMinutes(0, 0, 0);
  const windowStart = now.toISOString();
  const row = await database()
    .prepare(
      `INSERT INTO native_ai_usage (user_id, window_start, request_count)
       VALUES (?, ?, 1)
       ON CONFLICT(user_id, window_start)
       DO UPDATE SET request_count = request_count + 1
       RETURNING request_count AS requestCount`,
    )
    .bind(userId, windowStart)
    .first<{ requestCount: number }>();
  return (row?.requestCount ?? MAX_REQUESTS_PER_HOUR + 1) <= MAX_REQUESTS_PER_HOUR;
}

async function verifyAppleIdentityToken(identityToken: string): Promise<AppleTokenClaims> {
  if (identityToken.length > 8_192) throw new Error("Apple identity token is too large.");
  const parts = identityToken.split(".");
  if (parts.length !== 3) throw new Error("Invalid Apple identity token.");

  const header = JSON.parse(decodeBase64URLText(parts[0])) as AppleTokenHeader;
  const claims = JSON.parse(decodeBase64URLText(parts[1])) as AppleTokenClaims;
  if (header.alg !== "RS256" || !header.kid) throw new Error("Unsupported Apple identity token.");

  const keysResponse = await fetch("https://appleid.apple.com/auth/keys", {
    signal: AbortSignal.timeout(10_000),
  });
  if (!keysResponse.ok) throw new Error("Apple sign-in keys are unavailable.");
  const keys = (await keysResponse.json()) as AppleKeysResponse;
  const jwk = keys.keys?.find((candidate) => candidate.kid === header.kid);
  if (!jwk) throw new Error("Apple identity key is unknown.");
  const key = await crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const verified = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    decodeBase64URL(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
  );
  if (!verified) throw new Error("Apple identity token signature is invalid.");

  const configuration = env as unknown as NativeEnvironment;
  const audience = configuration.APPLE_SIGN_IN_AUDIENCE?.trim() || DEFAULT_APPLE_AUDIENCE;
  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  const nowSeconds = Math.floor(Date.now() / 1_000);
  if (
    claims.iss !== "https://appleid.apple.com" ||
    !audiences.includes(audience) ||
    !claims.sub ||
    !claims.exp ||
    claims.exp <= nowSeconds ||
    (claims.iat != null && claims.iat > nowSeconds + 300)
  ) {
    throw new Error("Apple identity token claims are invalid.");
  }
  return claims;
}

function decodeBase64URLText(value: string): string {
  return new TextDecoder().decode(decodeBase64URL(value));
}

function decodeBase64URL(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function base64URL(value: Uint8Array): string {
  let binary = "";
  value.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}
