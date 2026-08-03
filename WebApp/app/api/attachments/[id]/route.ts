import { authenticatedUserKey, database, jsonResponse, uploads } from "../../security";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const userId = await authenticatedUserKey(request);
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) return jsonResponse({ error: "Not found." }, 404);

  const attachment = await database()
    .prepare(
      "SELECT object_key AS objectKey, content_type AS contentType FROM attachments WHERE id = ? AND user_id = ?",
    )
    .bind(id, userId)
    .first<{ objectKey: string; contentType: string }>();
  if (!attachment) return jsonResponse({ error: "Not found." }, 404);

  const object = await uploads().get(attachment.objectKey);
  if (!object) return jsonResponse({ error: "Not found." }, 404);
  return new Response(object.body, {
    headers: {
      "cache-control": "private, no-store, max-age=0",
      "content-type": attachment.contentType,
      "content-disposition": "inline",
      "x-content-type-options": "nosniff",
    },
  });
}
