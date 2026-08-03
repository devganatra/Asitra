import { env } from "cloudflare:workers";
import { accountKeyForEmail } from "../account-identity";

export async function authenticatedUserKey(request: Request): Promise<string | null> {
  return accountKeyForEmail(request.headers.get("oai-authenticated-user-email") ?? "");
}

export function database(): D1Database {
  if (!env.DB) throw new Error("Secure storage is unavailable.");
  return env.DB;
}

export function uploads(): R2Bucket {
  if (!env.UPLOADS) throw new Error("Secure attachment storage is unavailable.");
  return env.UPLOADS;
}

export async function consumeRateLimit(
  userId: string,
  scope: string,
  limit: number,
  windowMinutes = 60,
): Promise<boolean> {
  const windowMs = windowMinutes * 60_000;
  const windowStart = new Date(Math.floor(Date.now() / windowMs) * windowMs).toISOString();
  const result = await database()
    .prepare(
      `INSERT INTO request_usage (user_id, scope, window_start, request_count)
       VALUES (?, ?, ?, 1)
       ON CONFLICT(user_id, scope, window_start) DO UPDATE SET
         request_count = request_count + 1
       WHERE request_count < ?`,
    )
    .bind(userId, scope, windowStart, limit)
    .run();
  return Number(result.meta.changes ?? 0) > 0;
}

export function isTrustedMutation(request: Request): boolean {
  const url = new URL(request.url);
  const origin = request.headers.get("origin");
  const fetchSite = request.headers.get("sec-fetch-site");
  return (
    origin === url.origin &&
    request.headers.get("x-sakhya-request") === "1" &&
    (!fetchSite || fetchSite === "same-origin")
  );
}

export function jsonResponse(value: unknown, status = 200): Response {
  return Response.json(value, {
    status,
    headers: {
      "cache-control": "no-store, max-age=0",
      "x-content-type-options": "nosniff",
    },
  });
}
