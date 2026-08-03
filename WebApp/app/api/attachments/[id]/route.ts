import { authenticatedUserKey, consumeRateLimit, database, jsonResponse, uploads } from "../../security";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const userId = await authenticatedUserKey(request);
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);
  if (!(await consumeRateLimit(userId, "attachment-read", 600))) return jsonResponse({ error: "Download limit reached." }, 429);
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) return jsonResponse({ error: "Not found." }, 404);

  const attachment = await database()
    .prepare(
      "SELECT object_key AS objectKey, content_type AS contentType, file_name AS fileName FROM attachments WHERE id = ? AND user_id = ?",
    )
    .bind(id, userId)
    .first<{ objectKey: string; contentType: string; fileName: string | null }>();
  if (!attachment) return jsonResponse({ error: "Not found." }, 404);

  const object = await uploads().get(attachment.objectKey);
  if (!object) return jsonResponse({ error: "Not found." }, 404);
  return new Response(object.body, {
    headers: {
      "cache-control": "private, no-store, max-age=0",
      "content-type": attachment.contentType,
      "content-disposition": `inline; filename="${safeDownloadName(attachment.fileName)}"`,
      "x-content-type-options": "nosniff",
    },
  });
}

function safeDownloadName(value: string | null) {
  return (value ?? "asitra-attachment").replace(/["\\\r\n]/g, "_").slice(0, 120);
}
