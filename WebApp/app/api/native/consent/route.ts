import { database, jsonResponse } from "../../security";
import { authenticatedNativeUser } from "../security";
import { PRIVACY_POLICY_VERSION } from "../../account/consent/route";

export async function GET(request: Request) {
  const userId = await authenticatedNativeUser(request);
  if (!userId) return jsonResponse({ error: "Asitra sign-in is required." }, 401);
  const row = await database().prepare(
    "SELECT granted, policy_version AS policyVersion, updated_at AS updatedAt FROM user_consents WHERE user_id = ? AND purpose = 'ai_analysis'",
  ).bind(userId).first<{ granted: number; policyVersion: string; updatedAt: string }>();
  return jsonResponse({ purpose: "ai_analysis", granted: Boolean(row?.granted), policyVersion: row?.policyVersion ?? PRIVACY_POLICY_VERSION, updatedAt: row?.updatedAt ?? null });
}

export async function PUT(request: Request) {
  const userId = await authenticatedNativeUser(request);
  if (!userId) return jsonResponse({ error: "Asitra sign-in is required." }, 401);
  let body: { granted?: unknown };
  try { body = await request.json(); } catch { return jsonResponse({ error: "Invalid consent request." }, 400); }
  if (typeof body.granted !== "boolean") return jsonResponse({ error: "Invalid consent choice." }, 400);
  const updatedAt = new Date().toISOString();
  await database().prepare(
    `INSERT INTO user_consents (user_id, purpose, granted, policy_version, updated_at) VALUES (?, 'ai_analysis', ?, ?, ?)
     ON CONFLICT(user_id, purpose) DO UPDATE SET granted = excluded.granted,
       policy_version = excluded.policy_version, updated_at = excluded.updated_at`,
  ).bind(userId, body.granted ? 1 : 0, PRIVACY_POLICY_VERSION, updatedAt).run();
  return jsonResponse({ purpose: "ai_analysis", granted: body.granted, policyVersion: PRIVACY_POLICY_VERSION, updatedAt });
}
