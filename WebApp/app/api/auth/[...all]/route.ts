import { createAuth } from "@/app/auth/server";
import { jsonResponse } from "../../security";

export const dynamic = "force-dynamic";

async function handle(request: Request): Promise<Response> {
  try {
    const auth = await createAuth();
    if (!auth) {
      return jsonResponse({ error: "Public sign-in is not configured yet." }, 503);
    }
    return auth.handler(request);
  } catch (error) {
    console.error("Public authentication configuration error", error instanceof Error ? error.message : "unknown error");
    return jsonResponse({ error: "Public sign-in is temporarily unavailable." }, 503);
  }
}

export const GET = handle;
export const POST = handle;
