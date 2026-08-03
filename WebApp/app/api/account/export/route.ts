import { authenticatedUserKey, consumeRateLimit, database, jsonResponse } from "../../security";
import { validatePersistedState } from "../../../state-schema";

export async function GET(request: Request) {
  const userId = await authenticatedUserKey(request);
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);
  if (!(await consumeRateLimit(userId, "account-export", 10, 24 * 60))) {
    return jsonResponse({ error: "Daily export limit reached." }, 429);
  }
  const db = database();
  const [state, attachments, consents, shared] = await Promise.all([
    db.prepare("SELECT state_json AS stateJson, version, updated_at AS updatedAt FROM user_states WHERE user_id = ?").bind(userId).first<{ stateJson: string; version: number; updatedAt: string }>(),
    db.prepare("SELECT id, content_type AS contentType, byte_size AS byteSize, kind, file_name AS fileName, created_at AS createdAt FROM attachments WHERE user_id = ? ORDER BY created_at").bind(userId).all(),
    db.prepare("SELECT purpose, granted, policy_version AS policyVersion, updated_at AS updatedAt FROM user_consents WHERE user_id = ?").bind(userId).all(),
    db.prepare(
      `SELECT l.id, l.list_json AS listJson, l.version, l.updated_at AS updatedAt, m.role
       FROM shared_lists l INNER JOIN shared_list_members m ON m.list_id = l.id WHERE m.user_id = ?`,
    ).bind(userId).all<{ id: string; listJson: string; version: number; updatedAt: string; role: string }>(),
  ]);
  const exportedAt = new Date().toISOString();
  return Response.json({
    format: "asitra-account-export",
    formatVersion: 1,
    exportedAt,
    state: state ? validatePersistedState(JSON.parse(state.stateJson)) : null,
    stateVersion: state?.version ?? 0,
    stateUpdatedAt: state?.updatedAt ?? null,
    attachments: attachments.results.map((item) => ({ ...item, downloadURL: `/api/attachments/${String(item.id)}` })),
    consents: consents.results.map((item) => ({ ...item, granted: Boolean(item.granted) })),
    sharedLists: shared.results.map((item) => ({ ...item, list: JSON.parse(item.listJson), listJson: undefined })),
  }, {
    headers: {
      "cache-control": "private, no-store, max-age=0",
      "content-disposition": `attachment; filename="asitra-data-${exportedAt.slice(0, 10)}.json"`,
      "x-content-type-options": "nosniff",
    },
  });
}
