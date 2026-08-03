import { authenticatedUserKey, consumeRateLimit, database, isTrustedMutation, jsonResponse } from "../security";

const MAX_BODY_BYTES = 64_000;

type SharedList = {
  id: string;
  name: string;
  shared: true;
  members: number;
  color: string;
  items: Array<{ id: string; text: string; done: boolean; due?: string }>;
};

export async function GET(request: Request) {
  const userId = await authenticatedUserKey(request);
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);
  if (!(await consumeRateLimit(userId, "shared-list-write", 90))) return jsonResponse({ error: "Too many list updates. Try again shortly." }, 429);
  const result = await database()
    .prepare(
      `SELECT l.id, l.owner_id AS ownerId, l.list_json AS listJson, l.version,
              (SELECT COUNT(*) FROM shared_list_members m2 WHERE m2.list_id = l.id) AS members
       FROM shared_lists l
       INNER JOIN shared_list_members m ON m.list_id = l.id
       WHERE m.user_id = ?
       ORDER BY l.updated_at DESC`,
    )
    .bind(userId)
    .all<{ id: string; ownerId: string; listJson: string; version: number; members: number }>();
  return jsonResponse({
    lists: result.results.map((row) => ({
      list: { ...validateList(JSON.parse(row.listJson)), shared: true, members: row.members },
      version: row.version,
      owner: row.ownerId === userId,
    })),
  });
}

export async function POST(request: Request) {
  if (!isTrustedMutation(request)) return jsonResponse({ error: "Untrusted request." }, 403);
  const userId = await authenticatedUserKey(request);
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);
  if (!(await consumeRateLimit(userId, "shared-list-delete", 30))) return jsonResponse({ error: "Too many list changes. Try again shortly." }, 429);
  const body = await readBody(request);
  if (!body) return jsonResponse({ error: "Invalid sharing request." }, 400);
  const action = body.action;

  if (action === "join") {
    const code = typeof body.code === "string" ? body.code.trim().toUpperCase() : "";
    if (!/^[A-Z2-9]{20}$/.test(code)) return jsonResponse({ error: "Invalid invite code." }, 400);
    const tokenHash = await sha256(code);
    const db = database();
    const invite = await db
      .prepare("SELECT list_id AS listId, expires_at AS expiresAt FROM shared_list_invites WHERE token_hash = ?")
      .bind(tokenHash)
      .first<{ listId: string; expiresAt: string }>();
    if (!invite || Date.parse(invite.expiresAt) <= Date.now()) {
      return jsonResponse({ error: "This invite is invalid or expired." }, 404);
    }
    await db.batch([
      db.prepare("INSERT OR IGNORE INTO shared_list_members (list_id, user_id, role) VALUES (?, ?, 'member')").bind(invite.listId, userId),
      db.prepare("DELETE FROM shared_list_invites WHERE token_hash = ?").bind(tokenHash),
    ]);
    return sharedListResponse(invite.listId, userId);
  }

  if (action === "share" || action === "invite") {
    let list: SharedList;
    try { list = validateList(body.list); } catch { return jsonResponse({ error: "Invalid shared list." }, 400); }
    const db = database();
    const existing = await db.prepare("SELECT owner_id AS ownerId FROM shared_lists WHERE id = ?").bind(list.id).first<{ ownerId: string }>();
    if (existing && existing.ownerId !== userId) return jsonResponse({ error: "Only the owner can invite people." }, 403);
    const now = new Date().toISOString();
    await db.batch([
      db.prepare(
        `INSERT INTO shared_lists (id, owner_id, list_json, version, updated_at) VALUES (?, ?, ?, 1, ?)
         ON CONFLICT(id) DO UPDATE SET list_json = excluded.list_json, version = version + 1, updated_at = excluded.updated_at
         WHERE owner_id = excluded.owner_id`,
      ).bind(list.id, userId, JSON.stringify(list), now),
      db.prepare("INSERT OR IGNORE INTO shared_list_members (list_id, user_id, role) VALUES (?, ?, 'owner')").bind(list.id, userId),
    ]);
    const code = randomCode();
    await db
      .prepare("INSERT INTO shared_list_invites (token_hash, list_id, expires_at, created_at) VALUES (?, ?, ?, ?)")
      .bind(await sha256(code), list.id, new Date(Date.now() + 7 * 86_400_000).toISOString(), now)
      .run();
    const response = await sharedListResponse(list.id, userId);
    const payload = (await response.json()) as Record<string, unknown>;
    return jsonResponse({ ...payload, inviteCode: code });
  }

  if (action === "update") {
    let list: SharedList;
    try { list = validateList(body.list); } catch { return jsonResponse({ error: "Invalid shared list." }, 400); }
    const version = Number(body.version);
    if (!Number.isInteger(version) || version < 1) return jsonResponse({ error: "A valid list version is required." }, 428);
    const db = database();
    const member = await db.prepare("SELECT role FROM shared_list_members WHERE list_id = ? AND user_id = ?").bind(list.id, userId).first();
    if (!member) return jsonResponse({ error: "You do not have access to this list." }, 403);
    const result = await db
      .prepare("UPDATE shared_lists SET list_json = ?, version = version + 1, updated_at = ? WHERE id = ? AND version = ?")
      .bind(JSON.stringify(list), new Date().toISOString(), list.id, version)
      .run();
    if (Number(result.meta.changes ?? 0) === 0) return jsonResponse({ error: "This list changed elsewhere. Reload before editing.", code: "LIST_CONFLICT" }, 409);
    return sharedListResponse(list.id, userId);
  }

  return jsonResponse({ error: "Unknown sharing action." }, 400);
}

export async function DELETE(request: Request) {
  if (!isTrustedMutation(request)) return jsonResponse({ error: "Untrusted request." }, 403);
  const userId = await authenticatedUserKey(request);
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);
  const listId = new URL(request.url).searchParams.get("id") ?? "";
  if (!/^[a-zA-Z0-9-]{1,128}$/.test(listId)) return jsonResponse({ error: "Invalid list." }, 400);
  const db = database();
  const list = await db.prepare("SELECT owner_id AS ownerId FROM shared_lists WHERE id = ?").bind(listId).first<{ ownerId: string }>();
  if (!list) return jsonResponse({ error: "Shared list not found." }, 404);
  if (list.ownerId === userId) {
    await db.batch([
      db.prepare("DELETE FROM shared_list_invites WHERE list_id = ?").bind(listId),
      db.prepare("DELETE FROM shared_list_members WHERE list_id = ?").bind(listId),
      db.prepare("DELETE FROM shared_lists WHERE id = ?").bind(listId),
    ]);
  } else {
    await db.prepare("DELETE FROM shared_list_members WHERE list_id = ? AND user_id = ?").bind(listId, userId).run();
  }
  return jsonResponse({ ok: true });
}

async function sharedListResponse(listId: string, userId: string) {
  const row = await database()
    .prepare(
      `SELECT l.owner_id AS ownerId, l.list_json AS listJson, l.version,
              (SELECT COUNT(*) FROM shared_list_members WHERE list_id = l.id) AS members
       FROM shared_lists l WHERE l.id = ?`,
    )
    .bind(listId)
    .first<{ ownerId: string; listJson: string; version: number; members: number }>();
  if (!row) return jsonResponse({ error: "Shared list not found." }, 404);
  return jsonResponse({ list: { ...validateList(JSON.parse(row.listJson)), shared: true, members: row.members }, version: row.version, owner: row.ownerId === userId });
}

async function readBody(request: Request): Promise<Record<string, unknown> | null> {
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_BODY_BYTES) return null;
  try {
    const value = JSON.parse(text);
    return value && typeof value === "object" && !Array.isArray(value) ? value : null;
  } catch {
    return null;
  }
}

function validateList(value: unknown): SharedList {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid list.");
  const source = value as Record<string, unknown>;
  const id = validText(source.id, 128, /^[a-zA-Z0-9-]+$/);
  const name = validText(source.name, 200);
  const color = validText(source.color, 32, /^#[0-9a-f]{6}$/i);
  if (!Array.isArray(source.items) || source.items.length > 1_000) throw new Error("Invalid list items.");
  const items = source.items.map((value) => {
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid list item.");
    const item = value as Record<string, unknown>;
    const due = item.due == null ? undefined : validText(item.due, 200);
    return { id: validText(item.id, 128, /^[a-zA-Z0-9-]+$/), text: validText(item.text, 1_000), done: Boolean(item.done), due };
  });
  return { id, name, shared: true, members: 1, color, items };
}

function validText(value: unknown, max: number, pattern?: RegExp) {
  if (typeof value !== "string" || !value.trim() || value.length > max || (pattern && !pattern.test(value))) throw new Error("Invalid text.");
  return value.trim();
}

function randomCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(20));
  return Array.from(bytes, (byte) => alphabet[byte % alphabet.length]).join("");
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}
