import { authenticatedUserKey, database, isTrustedMutation, jsonResponse, uploads } from "../security";
import { validatePersistedState } from "../../state-schema";

const MAX_STATE_BYTES = 2_000_000;

export async function GET() {
  const userId = await authenticatedUserKey();
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);

  const row = await database()
    .prepare("SELECT state_json AS stateJson, version, updated_at AS updatedAt FROM user_states WHERE user_id = ?")
    .bind(userId)
    .first<{ stateJson: string; version: number; updatedAt: string }>();
  if (!row) return new Response(null, { status: 204, headers: { "cache-control": "no-store" } });

  return jsonResponse({
    state: validatePersistedState(JSON.parse(row.stateJson)),
    version: row.version,
    updatedAt: row.updatedAt,
  });
}

export async function PUT(request: Request) {
  if (!isTrustedMutation(request)) return jsonResponse({ error: "Untrusted request." }, 403);
  const userId = await authenticatedUserKey();
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (contentLength > MAX_STATE_BYTES) return jsonResponse({ error: "State is too large." }, 413);
  const expectedVersion = Number(request.headers.get("if-match"));
  if (!Number.isInteger(expectedVersion) || expectedVersion < 0) {
    return jsonResponse({ error: "A valid state version is required." }, 428);
  }

  let state: ReturnType<typeof validatePersistedState>;
  try {
    const body = await request.text();
    if (new TextEncoder().encode(body).byteLength > MAX_STATE_BYTES) {
      return jsonResponse({ error: "State is too large." }, 413);
    }
    state = validatePersistedState(JSON.parse(body));
  } catch {
    return jsonResponse({ error: "Invalid Sakhya state." }, 400);
  }

  const updatedAt = new Date().toISOString();
  const db = database();
  let nextVersion: number;
  if (expectedVersion === 0) {
    const result = await db
      .prepare(
        "INSERT OR IGNORE INTO user_states (user_id, state_json, version, updated_at) VALUES (?, ?, 1, ?)",
      )
      .bind(userId, JSON.stringify(state), updatedAt)
      .run();
    if (Number(result.meta.changes ?? 0) === 0) {
      return jsonResponse({ error: "Your data changed on another device. Reload before saving.", code: "STATE_CONFLICT" }, 409);
    }
    nextVersion = 1;
  } else {
    const result = await db
      .prepare(
        `UPDATE user_states SET state_json = ?, version = version + 1, updated_at = ?
         WHERE user_id = ? AND version = ?`,
      )
      .bind(JSON.stringify(state), updatedAt, userId, expectedVersion)
      .run();
    if (Number(result.meta.changes ?? 0) === 0) {
      return jsonResponse({ error: "Your data changed on another device. Reload before saving.", code: "STATE_CONFLICT" }, 409);
    }
    nextVersion = expectedVersion + 1;
  }
  await cleanAbandonedUploads(userId, state);
  return jsonResponse({ ok: true, version: nextVersion, updatedAt });
}

export async function DELETE(request: Request) {
  if (!isTrustedMutation(request)) return jsonResponse({ error: "Untrusted request." }, 403);
  const userId = await authenticatedUserKey();
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);
  if (request.headers.get("x-sakhya-confirm-delete") !== "DELETE MY ACCOUNT") {
    return jsonResponse({ error: "Account deletion confirmation is required." }, 400);
  }

  const db = database();
  const rows = await db
    .prepare("SELECT object_key AS objectKey FROM attachments WHERE user_id = ?")
    .bind(userId)
    .all<{ objectKey: string }>();
  const ownedLists = await db
    .prepare("SELECT id FROM shared_lists WHERE owner_id = ?")
    .bind(userId)
    .all<{ id: string }>();
  await Promise.all(rows.results.map((row) => uploads().delete(row.objectKey)));
  for (const list of ownedLists.results) {
    await db.batch([
      db.prepare("DELETE FROM shared_list_invites WHERE list_id = ?").bind(list.id),
      db.prepare("DELETE FROM shared_list_members WHERE list_id = ?").bind(list.id),
      db.prepare("DELETE FROM shared_lists WHERE id = ?").bind(list.id),
    ]);
  }
  await db.batch([
    db.prepare("DELETE FROM attachments WHERE user_id = ?").bind(userId),
    db.prepare("DELETE FROM request_usage WHERE user_id = ?").bind(userId),
    db.prepare("DELETE FROM native_ai_usage WHERE user_id = ?").bind(userId),
    db.prepare("DELETE FROM native_sessions WHERE user_id = ?").bind(userId),
    db.prepare("DELETE FROM shared_list_members WHERE user_id = ?").bind(userId),
    db.prepare("DELETE FROM user_states WHERE user_id = ?").bind(userId),
  ]);
  return jsonResponse({ ok: true });
}

async function cleanAbandonedUploads(
  userId: string,
  state: ReturnType<typeof validatePersistedState>,
) {
  const referenced = new Set(
    state.entries
      .map((entry) => entry.photo?.match(/^\/api\/attachments\/([0-9a-f-]{36})$/i)?.[1])
      .filter((id): id is string => Boolean(id)),
  );
  const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1_000).toISOString();
  const db = database();
  const rows = await db
    .prepare(
      "SELECT id, object_key AS objectKey FROM attachments WHERE user_id = ? AND created_at < ?",
    )
    .bind(userId, cutoff)
    .all<{ id: string; objectKey: string }>();
  const abandoned = rows.results.filter((row) => !referenced.has(row.id));
  await Promise.all(abandoned.map((row) => uploads().delete(row.objectKey)));
  if (abandoned.length) {
    const placeholders = abandoned.map(() => "?").join(",");
    await db
      .prepare(`DELETE FROM attachments WHERE user_id = ? AND id IN (${placeholders})`)
      .bind(userId, ...abandoned.map((row) => row.id))
      .run();
  }
}
