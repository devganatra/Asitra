import { authProviderAvailability } from "@/app/auth/server";
import { jsonResponse } from "../../security";

export const dynamic = "force-dynamic";

export async function GET(): Promise<Response> {
  return jsonResponse(authProviderAvailability());
}
