import { authenticatedUserKey, consumeRateLimit, database, isTrustedMutation, jsonResponse, uploads } from "../security";

const USER_STORAGE_QUOTA = 250_000_000;
const TYPE_LIMITS = new Map([
  ["image/jpeg", 5_000_000],
  ["image/png", 5_000_000],
  ["image/webp", 5_000_000],
  ["application/pdf", 10_000_000],
  ["audio/mpeg", 20_000_000],
  ["audio/mp4", 20_000_000],
  ["audio/wav", 20_000_000],
  ["audio/webm", 20_000_000],
]);

export async function POST(request: Request) {
  if (!isTrustedMutation(request)) return jsonResponse({ error: "Untrusted request." }, 403);
  const userId = await authenticatedUserKey(request);
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);
  if (!(await consumeRateLimit(userId, "attachment-upload", 30))) {
    return jsonResponse({ error: "Upload limit reached. Please wait before trying again." }, 429);
  }
  const contentType = request.headers.get("content-type")?.split(";")[0].toLowerCase() ?? "";
  const maxBytes = TYPE_LIMITS.get(contentType);
  if (!maxBytes) return jsonResponse({ error: "Unsupported attachment type." }, 415);
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (contentLength > maxBytes) return jsonResponse({ error: "Attachment is too large." }, 413);

  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength === 0 || bytes.byteLength > maxBytes || !hasValidSignature(bytes, contentType)) {
    return jsonResponse({ error: "The attachment content is invalid." }, 400);
  }

  const usage = await database().prepare(
    "SELECT COALESCE(SUM(byte_size), 0) AS usedBytes FROM attachments WHERE user_id = ?",
  ).bind(userId).first<{ usedBytes: number }>();
  if (Number(usage?.usedBytes ?? 0) + bytes.byteLength > USER_STORAGE_QUOTA) {
    return jsonResponse({ error: "Your private attachment storage is full. Export or remove files before uploading more." }, 413);
  }

  const id = crypto.randomUUID();
  const objectKey = `${userId}/${id}`;
  const kind = attachmentKind(contentType);
  const fileName = safeFileName(request.headers.get("x-asitra-filename"), id, contentType);
  await uploads().put(objectKey, bytes, {
    httpMetadata: { contentType },
    customMetadata: { owner: userId, kind, fileName },
  });
  try {
    await database()
      .prepare(
        "INSERT INTO attachments (id, user_id, object_key, content_type, byte_size, kind, file_name, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      )
      .bind(id, userId, objectKey, contentType, bytes.byteLength, kind, fileName, new Date().toISOString())
      .run();
  } catch (error) {
    await uploads().delete(objectKey);
    throw error;
  }

  return jsonResponse({ id, url: `/api/attachments/${id}`, kind, fileName, byteSize: bytes.byteLength }, 201);
}

function hasValidSignature(bytes: Uint8Array, contentType: string): boolean {
  if (contentType === "image/jpeg") return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  if (contentType === "image/png") {
    return [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((value, index) => bytes[index] === value);
  }
  if (contentType === "image/webp") {
    return (
      String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" &&
      String.fromCharCode(...bytes.slice(8, 12)) === "WEBP"
    );
  }
  if (contentType === "application/pdf") return String.fromCharCode(...bytes.slice(0, 5)) === "%PDF-";
  if (contentType === "audio/mpeg") {
    return String.fromCharCode(...bytes.slice(0, 3)) === "ID3" || (bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0);
  }
  if (contentType === "audio/mp4") return String.fromCharCode(...bytes.slice(4, 8)) === "ftyp";
  if (contentType === "audio/wav") {
    return String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" && String.fromCharCode(...bytes.slice(8, 12)) === "WAVE";
  }
  if (contentType === "audio/webm") return bytes[0] === 0x1a && bytes[1] === 0x45 && bytes[2] === 0xdf && bytes[3] === 0xa3;
  return false;
}

function attachmentKind(contentType: string) {
  if (contentType === "application/pdf") return "pdf";
  if (contentType.startsWith("audio/")) return "voice";
  return "image";
}

function safeFileName(value: string | null, id: string, contentType: string) {
  const extension = contentType === "application/pdf" ? "pdf" : contentType.split("/")[1]?.replace("jpeg", "jpg") ?? "bin";
  if (!value) return `${id}.${extension}`;
  let decoded = value;
  try { decoded = decodeURIComponent(value); } catch { /* Use the raw header when malformed. */ }
  const cleaned = decoded.replace(/[^a-zA-Z0-9._ -]/g, "_").trim().slice(0, 120);
  return cleaned || `${id}.${extension}`;
}
