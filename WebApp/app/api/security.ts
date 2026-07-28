import { env } from "cloudflare:workers";
import { getChatGPTUser } from "../chatgpt-auth";

export async function authenticatedUserKey(): Promise<string | null> {
  const user = await getChatGPTUser();
  if (!user) return null;
  const normalized = user.email.trim().toLowerCase();
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(normalized));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function database(): D1Database {
  if (!env.DB) throw new Error("Secure storage is unavailable.");
  return env.DB;
}

export function uploads(): R2Bucket {
  if (!env.UPLOADS) throw new Error("Secure attachment storage is unavailable.");
  return env.UPLOADS;
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
