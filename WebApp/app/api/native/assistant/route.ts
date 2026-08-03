import { jsonResponse } from "../../security";
import {
  AIConfigurationError,
  answerWithSakhyaAI,
  publicSakhyaAIContract,
  type AssistantMessage,
  type GroundedMetric,
  type SakhyaAssistantContext,
} from "../../assistant/service";
import { authenticatedNativeUser, consumeNativeAIRateLimit } from "../security";

const MAX_REQUEST_BYTES = 64_000;
const MAX_MESSAGES = 12;
const MAX_MESSAGE_LENGTH = 2_000;

export async function POST(request: Request) {
  const userId = await authenticatedNativeUser(request);
  if (!userId) return jsonResponse({ error: "Sakhya AI sign-in is required." }, 401);
  if (!(await consumeNativeAIRateLimit(userId))) {
    return jsonResponse({ error: "The hourly AI limit has been reached. Try again shortly." }, 429);
  }
  if (request.headers.get("content-type")?.split(";")[0] !== "application/json") {
    return jsonResponse({ error: "JSON is required." }, 415);
  }
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (contentLength > MAX_REQUEST_BYTES) {
    return jsonResponse({ error: "Assistant request is too large." }, 413);
  }

  try {
    const bodyText = await request.text();
    if (new TextEncoder().encode(bodyText).byteLength > MAX_REQUEST_BYTES) {
      return jsonResponse({ error: "Assistant request is too large." }, 413);
    }
    const body = JSON.parse(bodyText) as { messages?: unknown; context?: unknown };
    const messages = validateMessages(body.messages);
    const context = validateContext(body.context);
    const result = await answerWithSakhyaAI({
      userIdentifier: userId,
      messages,
      context,
    });
    const contract = publicSakhyaAIContract();
    return jsonResponse({
      answer: result.answer,
      model: result.model,
      provider: result.provider,
      label: contract.label,
      profile: contract.profile,
      contractVersion: contract.version,
    });
  } catch (error) {
    if (error instanceof AIConfigurationError) {
      return jsonResponse({ error: error.message, code: "AI_NOT_CONFIGURED" }, 503);
    }
    console.error("Native assistant error", error);
    return jsonResponse({ error: "Sakhya AI is temporarily unavailable." }, 502);
  }
}

function validateMessages(value: unknown): AssistantMessage[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_MESSAGES) {
    throw new Error("Invalid messages.");
  }
  return value.map((item) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw new Error("Invalid message.");
    }
    const role = (item as Record<string, unknown>).role;
    const text = (item as Record<string, unknown>).text;
    if (
      (role !== "assistant" && role !== "user") ||
      typeof text !== "string" ||
      !text.trim() ||
      text.length > MAX_MESSAGE_LENGTH
    ) {
      throw new Error("Invalid message.");
    }
    return { role, text: text.trim() };
  });
}

function validateContext(value: unknown): SakhyaAssistantContext {
  const source = record(value);
  const generatedAt = shortString(source.generatedAt, 64);
  if (!Number.isFinite(Date.parse(generatedAt))) throw new Error("Invalid context date.");
  return {
    generatedAt,
    timezone: optionalString(source.timezone, 100),
    verifiedMetrics: array(source.verifiedMetrics, 64).map(validateMetric),
    entries: array(source.entries, 250).map((item) => boundedRecord(item, 16)),
    lists: array(source.lists, 50).map((item) => boundedRecord(item, 16)),
    trackers: array(source.trackers, 250).map((item) => boundedRecord(item, 16)),
    money: source.money == null ? undefined : boundedRecord(source.money, 16),
    agenda: source.agenda == null ? undefined : array(source.agenda, 100).map((item) => shortString(item, 500)),
  };
}

function validateMetric(value: unknown): GroundedMetric {
  const metric = record(value);
  const rawValue = metric.value;
  if (
    (typeof rawValue !== "number" || !Number.isFinite(rawValue)) &&
    (typeof rawValue !== "string" || rawValue.length > 500)
  ) {
    throw new Error("Invalid grounded metric.");
  }
  return {
    name: shortString(metric.name, 100),
    value: rawValue,
    unit: optionalString(metric.unit, 50),
    period: optionalString(metric.period, 100),
    source: shortString(metric.source, 200),
  };
}

function boundedRecord(value: unknown, maximumKeys: number): Record<string, unknown> {
  const valueRecord = record(value);
  if (Object.keys(valueRecord).length > maximumKeys) throw new Error("Context record is too large.");
  JSON.stringify(valueRecord, (_key, nested) => {
    if (typeof nested === "string" && nested.length > 2_000) {
      throw new Error("Context string is too large.");
    }
    return nested;
  });
  return valueRecord;
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Invalid context object.");
  }
  return value as Record<string, unknown>;
}

function array(value: unknown, maximum: number): unknown[] {
  if (!Array.isArray(value) || value.length > maximum) throw new Error("Invalid context array.");
  return value;
}

function shortString(value: unknown, maximum: number): string {
  if (typeof value !== "string" || !value || value.length > maximum) {
    throw new Error("Invalid context string.");
  }
  return value;
}

function optionalString(value: unknown, maximum: number): string | undefined {
  if (value == null) return undefined;
  return shortString(value, maximum);
}
