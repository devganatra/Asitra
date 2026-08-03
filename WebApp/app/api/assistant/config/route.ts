import { jsonResponse } from "../../security";
import { publicAsitraAIContract } from "../service";

export async function GET() {
  return jsonResponse(publicAsitraAIContract());
}
