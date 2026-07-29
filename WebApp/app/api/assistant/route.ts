import { env } from "cloudflare:workers";
import {
  authenticatedUserKey,
  database,
  isTrustedMutation,
  jsonResponse,
} from "../security";
import { validatePersistedState } from "../../state-schema";

const MAX_REQUEST_BYTES = 32_000;
const MAX_MESSAGES = 12;
const MAX_MESSAGE_LENGTH = 2_000;

const MODEL_PROFILES = {
  "gpt-5.6-luna": { effort: "none", label: "Quick" },
  "gpt-5.6-terra": { effort: "low", label: "Everyday" },
  "gpt-5.6-sol": { effort: "high", label: "Deep" },
} as const;

type ModelId = keyof typeof MODEL_PROFILES;
type AssistantMessage = { role: "assistant" | "user"; text: string };

type OpenAIResponse = {
  error?: { message?: string };
  output?: Array<{
    type?: string;
    content?: Array<{ type?: string; text?: string }>;
  }>;
};

export async function POST(request: Request) {
  if (!isTrustedMutation(request)) {
    return jsonResponse({ error: "Untrusted request." }, 403);
  }

  const userId = await authenticatedUserKey();
  if (!userId) return jsonResponse({ error: "Authentication required." }, 401);

  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (contentLength > MAX_REQUEST_BYTES) {
    return jsonResponse({ error: "Assistant request is too large." }, 413);
  }

  let model: ModelId;
  let messages: AssistantMessage[];
  try {
    const bodyText = await request.text();
    if (new TextEncoder().encode(bodyText).byteLength > MAX_REQUEST_BYTES) {
      return jsonResponse({ error: "Assistant request is too large." }, 413);
    }
    const body = JSON.parse(bodyText) as { model?: unknown; messages?: unknown };
    if (typeof body.model !== "string" || !(body.model in MODEL_PROFILES)) {
      return jsonResponse({ error: "Unsupported AI model." }, 400);
    }
    model = body.model as ModelId;
    messages = validateMessages(body.messages);
  } catch {
    return jsonResponse({ error: "Invalid assistant request." }, 400);
  }

  const apiKey = (env as unknown as { OPENAI_API_KEY?: string }).OPENAI_API_KEY;
  if (!apiKey) {
    return jsonResponse(
      {
        error: "Terra is ready but the OpenAI API key has not been connected.",
        code: "AI_NOT_CONFIGURED",
      },
      503,
    );
  }

  const row = await database()
    .prepare("SELECT state_json AS stateJson FROM user_states WHERE user_id = ?")
    .bind(userId)
    .first<{ stateJson: string }>();

  const state = row ? validatePersistedState(JSON.parse(row.stateJson)) : null;
  const profile = MODEL_PROFILES[model];
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model,
      reasoning: { effort: profile.effort },
      store: false,
      max_output_tokens: 1_200,
      instructions: [
        "You are Sakhya, a calm, practical everyday assistant.",
        "Answer from the supplied Sakhya data only. Never invent events, amounts, health values, or completed actions.",
        "Use exact dates, counts, and amounts when they help. Clearly say when the data is insufficient.",
        "Separate observation from suggestion. Do not diagnose health conditions or give definitive financial advice.",
        "Keep the first answer concise and useful. Offer one sensible next step when appropriate.",
        "You cannot directly change records, calendars, reminders, or lists in this chat.",
      ].join(" "),
      input: buildInput(messages, state),
    }),
    signal: AbortSignal.timeout(30_000),
  });

  const result = (await response.json()) as OpenAIResponse;
  if (!response.ok) {
    console.error("OpenAI Responses API error", response.status, result.error?.message);
    return jsonResponse({ error: "Sakhya AI is temporarily unavailable." }, 502);
  }

  const answer = extractOutputText(result);
  if (!answer) {
    return jsonResponse({ error: "Sakhya AI returned an empty answer." }, 502);
  }

  return jsonResponse({
    answer,
    model,
    profile: profile.label,
  });
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
      text.trim().length === 0 ||
      text.length > MAX_MESSAGE_LENGTH
    ) {
      throw new Error("Invalid message.");
    }
    return { role, text: text.trim() };
  });
}

function buildInput(
  messages: AssistantMessage[],
  state: ReturnType<typeof validatePersistedState> | null,
) {
  const now = new Date();
  const cutoff = new Date(now);
  cutoff.setDate(cutoff.getDate() - 90);

  const context = state
    ? {
        generatedAt: now.toISOString(),
        entries: state.entries
          .filter((entry) => new Date(entry.timestamp) >= cutoff)
          .slice(0, 250)
          .map((entry) => ({
            id: entry.id,
            title: entry.title,
            kind: entry.kind,
            timestamp: entry.timestamp,
            amount: entry.amount,
            minutes: entry.minutes,
            note: entry.note,
          })),
        lists: state.lists.slice(0, 50).map((list) => ({
          ...list,
          items: list.items.slice(0, 200),
        })),
        trackers: state.trackers,
        money: {
          monthlyBudget: state.monthlyBudget,
          savingsTarget: state.savingsTarget,
          savingsCurrent: state.savingsCurrent,
          currency: "EUR",
        },
      }
    : { generatedAt: now.toISOString(), entries: [], lists: [], trackers: [] };

  const conversation = messages
    .map((message) => `${message.role === "user" ? "User" : "Sakhya"}: ${message.text}`)
    .join("\n");

  return `Sakhya data snapshot:\n${JSON.stringify(context)}\n\nConversation:\n${conversation}`;
}

function extractOutputText(response: OpenAIResponse): string {
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
