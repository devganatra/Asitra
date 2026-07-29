import { env } from "cloudflare:workers";

export const SAKHYA_MODEL_LABEL = "Terra";

const DEFAULT_MODEL = "gpt-5.6-terra";
const DEFAULT_OPENAI_BASE_URL = "https://api.openai.com";
const MAX_CONTEXT_CHARACTERS = 48_000;

export type AssistantMessage = {
  role: "assistant" | "user";
  text: string;
};

export type GroundedMetric = {
  name: string;
  value: number | string;
  unit?: string;
  period?: string;
  source: string;
};

export type SakhyaAssistantContext = {
  generatedAt: string;
  timezone?: string;
  verifiedMetrics: GroundedMetric[];
  entries: Array<Record<string, unknown>>;
  lists: Array<Record<string, unknown>>;
  trackers: Array<Record<string, unknown>>;
  money?: Record<string, unknown>;
  agenda?: string[];
};

type OpenAIResponse = {
  error?: { message?: string };
  output?: Array<{
    type?: string;
    content?: Array<{ type?: string; text?: string }>;
  }>;
};

type CompatibleChatResponse = {
  error?: { message?: string };
  choices?: Array<{ message?: { content?: string } }>;
};

type AIEnvironment = {
  AI_PROVIDER?: string;
  OPENAI_API_KEY?: string;
  CUSTOM_AI_API_KEY?: string;
  CUSTOM_AI_BASE_URL?: string;
  CUSTOM_AI_MODEL?: string;
};

export class AIConfigurationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AIConfigurationError";
  }
}

export function assertSakhyaAIConfigured(): { model: string; provider: string } {
  const configuration = providerConfiguration(env as unknown as AIEnvironment);
  return { model: configuration.model, provider: configuration.provider };
}

export async function answerWithSakhyaAI(input: {
  userIdentifier: string;
  messages: AssistantMessage[];
  context: SakhyaAssistantContext;
}): Promise<{ answer: string; model: string; provider: string }> {
  const configuration = providerConfiguration(env as unknown as AIEnvironment);
  const conversation = input.messages
    .map((message) => `${message.role === "user" ? "User" : "Sakhya"}: ${message.text}`)
    .join("\n");
  const serializedContext = JSON.stringify(input.context);
  if (serializedContext.length > MAX_CONTEXT_CHARACTERS) {
    throw new Error("The grounded assistant context is too large.");
  }

  const instructions = [
    "You are Sakhya, a calm and practical everyday coach.",
    "Treat verifiedMetrics as calculated facts. Never recalculate or contradict them.",
    "Use entries only as supporting context and never invent events, measurements, causal relationships, or completed actions.",
    "When describing a pattern, name the evidence and distinguish correlation from causation.",
    "Separate observations from suggestions.",
    "Health guidance is informational and must not diagnose. Financial guidance must not claim certainty.",
    "Never claim to have changed a calendar, reminder, list, payment, or record.",
    "Lead with the answer, include the material caveat, and end with at most one practical next step.",
  ].join(" ");
  const prompt = `Grounded Sakhya context:\n${serializedContext}\n\nConversation:\n${conversation}`;

  if (configuration.provider === "openai") {
    const response = await fetch(`${configuration.baseURL}/v1/responses`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${configuration.apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: configuration.model,
        reasoning: { effort: "low" },
        text: { verbosity: "low" },
        store: false,
        max_output_tokens: 1_200,
        safety_identifier: input.userIdentifier,
        instructions,
        input: prompt,
      }),
      signal: AbortSignal.timeout(30_000),
    });
    const result = (await response.json()) as OpenAIResponse;
    if (!response.ok) {
      console.error("OpenAI Responses API error", response.status, result.error?.message);
      throw new Error("The AI provider is temporarily unavailable.");
    }
    const answer = extractOpenAIOutput(result);
    if (!answer) throw new Error("The AI provider returned an empty answer.");
    return { answer, model: configuration.model, provider: configuration.provider };
  }

  const response = await fetch(`${configuration.baseURL}/v1/chat/completions`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${configuration.apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: configuration.model,
      temperature: 0.2,
      max_tokens: 1_200,
      messages: [
        { role: "system", content: instructions },
        { role: "user", content: prompt },
      ],
    }),
    signal: AbortSignal.timeout(30_000),
  });
  const result = (await response.json()) as CompatibleChatResponse;
  if (!response.ok) {
    console.error("Custom AI gateway error", response.status, result.error?.message);
    throw new Error("The custom AI provider is temporarily unavailable.");
  }
  const answer = result.choices?.[0]?.message?.content?.trim();
  if (!answer) throw new Error("The custom AI provider returned an empty answer.");
  return { answer, model: configuration.model, provider: configuration.provider };
}

function providerConfiguration(configuration: AIEnvironment) {
  const provider = configuration.AI_PROVIDER?.trim().toLowerCase() || "openai";
  if (provider === "openai") {
    if (!configuration.OPENAI_API_KEY) {
      throw new AIConfigurationError(
        "Terra is ready but the OpenAI API key has not been connected.",
      );
    }
    return {
      provider,
      apiKey: configuration.OPENAI_API_KEY,
      baseURL: DEFAULT_OPENAI_BASE_URL,
      model: DEFAULT_MODEL,
    };
  }

  if (provider !== "openai-compatible") {
    throw new AIConfigurationError("The configured AI provider is unsupported.");
  }
  if (
    !configuration.CUSTOM_AI_API_KEY ||
    !configuration.CUSTOM_AI_BASE_URL ||
    !configuration.CUSTOM_AI_MODEL
  ) {
    throw new AIConfigurationError("The custom language-model gateway is incomplete.");
  }
  const baseURL = safeHTTPSBaseURL(configuration.CUSTOM_AI_BASE_URL);
  return {
    provider,
    apiKey: configuration.CUSTOM_AI_API_KEY,
    baseURL,
    model: configuration.CUSTOM_AI_MODEL.trim(),
  };
}

function safeHTTPSBaseURL(value: string): string {
  const url = new URL(value);
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    url.search ||
    url.hash ||
    isPrivateHostname(url.hostname)
  ) {
    throw new AIConfigurationError("The custom AI gateway must be a public HTTPS origin.");
  }
  return url.toString().replace(/\/+$/, "");
}

function isPrivateHostname(hostname: string): boolean {
  const normalized = hostname.toLowerCase();
  if (
    normalized === "localhost" ||
    normalized.endsWith(".local") ||
    normalized === "::1" ||
    normalized === "0.0.0.0"
  ) {
    return true;
  }
  const ipv4 = normalized.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (!ipv4) return false;
  const octets = ipv4.slice(1).map(Number);
  return (
    octets.some((octet) => octet > 255) ||
    octets[0] === 10 ||
    octets[0] === 127 ||
    (octets[0] === 169 && octets[1] === 254) ||
    (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31) ||
    (octets[0] === 192 && octets[1] === 168)
  );
}

function extractOpenAIOutput(response: OpenAIResponse): string {
  return (
    response.output
      ?.filter((item) => item.type === "message")
      .flatMap((item) => item.content ?? [])
      .filter((item) => item.type === "output_text")
      .map((item) => item.text?.trim() ?? "")
      .filter(Boolean)
      .join("\n\n") ?? ""
  );
}
