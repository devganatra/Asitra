import { jsonResponse } from "../../../security";
import {
  AIConfigurationError,
  classifyFinanceWithSakhyaAI,
  publicSakhyaAIContract,
} from "../../../assistant/service";
import { authenticatedNativeUser, consumeNativeAIRateLimit } from "../../security";

export async function POST(request: Request) {
  const userId = await authenticatedNativeUser(request);
  if (!userId) return jsonResponse({ error: "Sakhya AI sign-in is required." }, 401);
  if (!(await consumeNativeAIRateLimit(userId))) return jsonResponse({ error: "The hourly AI limit has been reached." }, 429);
  try {
    const body = (await request.json()) as Record<string, unknown>;
    const text = typeof body.text === "string" ? body.text.trim() : "";
    const timezone = typeof body.timezone === "string" ? body.timezone.slice(0, 100) : "UTC";
    if (!text || text.length > 1_000) return jsonResponse({ error: "Enter one short financial statement." }, 400);
    const result = await classifyFinanceWithSakhyaAI({
      userIdentifier: userId,
      text,
      today: new Date().toISOString(),
      timezone,
    });
    const contract = publicSakhyaAIContract();
    return jsonResponse({ ...result, label: contract.label, profile: contract.profile });
  } catch (error) {
    if (error instanceof AIConfigurationError) return jsonResponse({ error: error.message, code: "AI_NOT_CONFIGURED" }, 503);
    console.error("Native finance classification error", error);
    return jsonResponse({ error: "Sakhya could not classify that safely. Use Guided instead." }, 502);
  }
}
