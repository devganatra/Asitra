import { authenticatedUserKey, consumeRateLimit, database, isTrustedMutation, jsonResponse } from "../../security";
import { validatePersistedState } from "../../../state-schema";

export async function GET(request: Request) {
  const userId = await authenticatedUserKey(request);
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);
  const rows = await database().prepare(
    "SELECT id, version, created_at AS createdAt FROM state_revisions WHERE user_id = ? ORDER BY created_at DESC LIMIT 20",
  ).bind(userId).all();
  return jsonResponse({ revisions: rows.results });
}

export async function POST(request: Request) {
  if (!isTrustedMutation(request)) return jsonResponse({ error: "Untrusted request." }, 403);
  const userId = await authenticatedUserKey(request);
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);
  if (!(await consumeRateLimit(userId, "account-recovery", 10, 24 * 60))) {
    return jsonResponse({ error: "Daily recovery limit reached." }, 429);
  }
  let body: { revisionId?: unknown; expectedVersion?: unknown; confirmation?: unknown };
  try { body = await request.json(); } catch { return jsonResponse({ error: "Invalid recovery request." }, 400); }
  if (typeof body.revisionId !== "string" || body.confirmation !== "RESTORE BACKUP" || !Number.isInteger(body.expectedVersion)) {
    return jsonResponse({ error: "Recovery confirmation and current version are required." }, 400);
  }
  const db = database();
  const revision = await db.prepare(
    "SELECT state_json AS stateJson FROM state_revisions WHERE id = ? AND user_id = ?",
  ).bind(body.revisionId, userId).first<{ stateJson: string }>();
  if (!revision) return jsonResponse({ error: "Recovery point not found." }, 404);
  const state = validatePersistedState(JSON.parse(revision.stateJson));
  const current = await db.prepare(
    "SELECT state_json AS stateJson, version FROM user_states WHERE user_id = ? AND version = ?",
  ).bind(userId, body.expectedVersion).first<{ stateJson: string; version: number }>();
  if (!current) return jsonResponse({ error: "Your data changed. Reload before restoring.", code: "STATE_CONFLICT" }, 409);
  const now = new Date().toISOString();
  const results = await db.batch([
    db.prepare("INSERT INTO state_revisions (id, user_id, state_json, version, created_at) VALUES (?, ?, ?, ?, ?)")
      .bind(crypto.randomUUID(), userId, current.stateJson, current.version, now),
    db.prepare("UPDATE user_states SET state_json = ?, version = version + 1, updated_at = ? WHERE user_id = ? AND version = ?")
      .bind(JSON.stringify(state), now, userId, body.expectedVersion),
  ]);
  if (Number(results[1].meta.changes ?? 0) === 0) return jsonResponse({ error: "Your data changed. Reload before restoring.", code: "STATE_CONFLICT" }, 409);
  await db.prepare(
    `DELETE FROM state_revisions WHERE user_id = ? AND id IN (
       SELECT id FROM state_revisions WHERE user_id = ? ORDER BY created_at DESC LIMIT -1 OFFSET 20
     )`,
  ).bind(userId, userId).run();
  return jsonResponse({ ok: true, state, version: Number(body.expectedVersion) + 1 });
}
