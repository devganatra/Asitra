import { jsonResponse } from "../security";
import { ASITRA_RELEASE } from "../../release";

export async function GET() {
  return jsonResponse({ status: "ok", service: "asitra-web", version: ASITRA_RELEASE });
}
