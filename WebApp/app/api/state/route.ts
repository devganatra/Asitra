import { authenticatedUserKey, database, isTrustedMutation, jsonResponse } from "../security";
import { validatePersistedState } from "../../state-schema";

const MAX_STATE_BYTES = 2_000_000;

export async function GET() {
  const userId = await authenticatedUserKey();
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);

  const row = await database()
    .prepare("SELECT state_json AS stateJson, updated_at AS updatedAt FROM user_states WHERE user_id = ?")
    .bind(userId)
    .first<{ stateJson: string; updatedAt: string }>();
  if (!row) return new Response(null, { status: 204, headers: { "cache-control": "no-store" } });

  return jsonResponse({
    state: validatePersistedState(JSON.parse(row.stateJson)),
    updatedAt: row.updatedAt,
  });
}

export async function PUT(request: Request) {
  if (!isTrustedMutation(request)) return jsonResponse({ error: "Untrusted request." }, 403);
  const userId = await authenticatedUserKey();
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (contentLength > MAX_STATE_BYTES) return jsonResponse({ error: "State is too large." }, 413);

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
  await database()
    .prepare(
      `INSERT INTO user_states (user_id, state_json, version, updated_at)
       VALUES (?, ?, 1, ?)
       ON CONFLICT(user_id) DO UPDATE SET
         state_json = excluded.state_json,
         version = excluded.version,
         updated_at = excluded.updated_at`,
    )
    .bind(userId, JSON.stringify(state), updatedAt)
    .run();
  return jsonResponse({ ok: true, updatedAt });
}
