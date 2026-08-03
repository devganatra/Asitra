import { authenticatedUserKey, database, isTrustedMutation, jsonResponse } from "../../security";

export const PRIVACY_POLICY_VERSION = "2026-08-03";
const ALLOWED_PURPOSES = new Set(["ai_analysis"]);

export async function GET(request: Request) {
  const userId = await authenticatedUserKey(request);
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);
  const rows = await database()
    .prepare("SELECT purpose, granted, policy_version AS policyVersion, updated_at AS updatedAt FROM user_consents WHERE user_id = ?")
    .bind(userId)
    .all<{ purpose: string; granted: number; policyVersion: string; updatedAt: string }>();
  return jsonResponse({
    policyVersion: PRIVACY_POLICY_VERSION,
    consents: rows.results.map((row) => ({ ...row, granted: Boolean(row.granted) })),
  });
}

export async function PUT(request: Request) {
  if (!isTrustedMutation(request)) return jsonResponse({ error: "Untrusted request." }, 403);
  const userId = await authenticatedUserKey(request);
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);
  let body: { purpose?: unknown; granted?: unknown };
  try { body = await request.json(); } catch { return jsonResponse({ error: "Invalid consent request." }, 400); }
  if (typeof body.purpose !== "string" || !ALLOWED_PURPOSES.has(body.purpose) || typeof body.granted !== "boolean") {
    return jsonResponse({ error: "Invalid consent choice." }, 400);
  }
  const updatedAt = new Date().toISOString();
  await database().prepare(
    `INSERT INTO user_consents (user_id, purpose, granted, policy_version, updated_at) VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(user_id, purpose) DO UPDATE SET granted = excluded.granted,
       policy_version = excluded.policy_version, updated_at = excluded.updated_at`,
  ).bind(userId, body.purpose, body.granted ? 1 : 0, PRIVACY_POLICY_VERSION, updatedAt).run();
  return jsonResponse({ purpose: body.purpose, granted: body.granted, policyVersion: PRIVACY_POLICY_VERSION, updatedAt });
}
