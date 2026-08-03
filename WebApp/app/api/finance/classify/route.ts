import {
  authenticatedUserKey,
  consumeRateLimit,
  isTrustedMutation,
  jsonResponse,
} from "../../security";
import {
  AIConfigurationError,
  assertSakhyaAIConfigured,
  classifyFinanceWithSakhyaAI,
  publicSakhyaAIContract,
} from "../../assistant/service";

const MAX_TEXT_LENGTH = 1_000;

export async function POST(request: Request) {
  if (!isTrustedMutation(request)) return jsonResponse({ error: "Untrusted request." }, 403);
  const userId = await authenticatedUserKey();
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);

  let text: string;
  let timezone: string;
  try {
    const body = (await request.json()) as Record<string, unknown>;
    if (body.consent !== true) return jsonResponse({ error: "AI data consent is required.", code: "AI_CONSENT_REQUIRED" }, 403);
    text = typeof body.text === "string" ? body.text.trim() : "";
    timezone = typeof body.timezone === "string" ? body.timezone.slice(0, 100) : "UTC";
    if (!text || text.length > MAX_TEXT_LENGTH) throw new Error("Invalid input.");
  } catch {
    return jsonResponse({ error: "Enter one short financial statement." }, 400);
  }

  try {
    assertSakhyaAIConfigured();
    if (!(await consumeRateLimit(userId, "finance-ai", 30))) {
      return jsonResponse({ error: "Your hourly AI limit has been reached.", code: "AI_RATE_LIMIT" }, 429);
    }
    const result = await classifyFinanceWithSakhyaAI({
      userIdentifier: userId,
      text,
      today: new Date().toISOString(),
      timezone,
    });
    const contract = publicSakhyaAIContract();
    return jsonResponse({ ...result, label: contract.label, profile: contract.profile });
  } catch (error) {
    if (error instanceof AIConfigurationError) {
      return jsonResponse({ error: error.message, code: "AI_NOT_CONFIGURED" }, 503);
    }
    console.error("Finance classification error", error);
    return jsonResponse({ error: "Sakhya could not classify that safely. Use the guided form instead." }, 502);
  }
}
