import { jsonResponse } from "../security";

export async function GET() {
  return jsonResponse({ status: "ok", service: "asitra-web", version: "0.2.0-beta.1" });
}
