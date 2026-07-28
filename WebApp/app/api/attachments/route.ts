import { authenticatedUserKey, database, isTrustedMutation, jsonResponse, uploads } from "../security";

const MAX_ATTACHMENT_BYTES = 1_500_000;
const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);

export async function POST(request: Request) {
  if (!isTrustedMutation(request)) return jsonResponse({ error: "Untrusted request." }, 403);
  const userId = await authenticatedUserKey();
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);
  const contentType = request.headers.get("content-type")?.split(";")[0].toLowerCase() ?? "";
  if (!ALLOWED_TYPES.has(contentType)) return jsonResponse({ error: "Unsupported image type." }, 415);
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (contentLength > MAX_ATTACHMENT_BYTES) return jsonResponse({ error: "Image is too large." }, 413);

  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.byteLength === 0 || bytes.byteLength > MAX_ATTACHMENT_BYTES || !hasValidSignature(bytes, contentType)) {
    return jsonResponse({ error: "The image content is invalid." }, 400);
  }

  const id = crypto.randomUUID();
  const objectKey = `${userId}/${id}`;
  await uploads().put(objectKey, bytes, {
    httpMetadata: { contentType },
    customMetadata: { owner: userId },
  });
  try {
    await database()
      .prepare(
        "INSERT INTO attachments (id, user_id, object_key, content_type, byte_size, created_at) VALUES (?, ?, ?, ?, ?, ?)",
      )
      .bind(id, userId, objectKey, contentType, bytes.byteLength, new Date().toISOString())
      .run();
  } catch (error) {
    await uploads().delete(objectKey);
    throw error;
  }

  return jsonResponse({ id, url: `/api/attachments/${id}` }, 201);
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
  return false;
}
