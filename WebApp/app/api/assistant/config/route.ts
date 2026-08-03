import { jsonResponse } from "../../security";
import { publicSakhyaAIContract } from "../service";

export async function GET() {
  return jsonResponse(publicSakhyaAIContract());
}
