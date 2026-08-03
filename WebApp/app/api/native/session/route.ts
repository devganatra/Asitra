import { jsonResponse } from "../../security";
import { createNativeSession, revokeNativeSession } from "../security";

const MAX_REQUEST_BYTES = 12_000;

export async function POST(request: Request) {
  if (request.headers.get("content-type")?.split(";")[0] !== "application/json") {
    return jsonResponse({ error: "JSON is required." }, 415);
  }
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (contentLength > MAX_REQUEST_BYTES) {
    return jsonResponse({ error: "Sign-in request is too large." }, 413);
  }

  try {
    const bodyText = await request.text();
    if (new TextEncoder().encode(bodyText).byteLength > MAX_REQUEST_BYTES) {
      return jsonResponse({ error: "Sign-in request is too large." }, 413);
    }
    const body = JSON.parse(bodyText) as { identityToken?: unknown };
    if (typeof body.identityToken !== "string" || !body.identityToken) {
      return jsonResponse({ error: "Apple identity token is required." }, 400);
    }
    const session = await createNativeSession(body.identityToken);
    return jsonResponse(session, 201);
  } catch (error) {
    console.error("Native Apple sign-in error", error);
    return jsonResponse({ error: "Apple sign-in could not be verified." }, 401);
  }
}

export async function DELETE(request: Request) {
  if (!(await revokeNativeSession(request))) {
    return jsonResponse({ error: "Asitra AI sign-in is required." }, 401);
  }
  return new Response(null, {
    status: 204,
    headers: { "cache-control": "no-store", "x-content-type-options": "nosniff" },
  });
}
