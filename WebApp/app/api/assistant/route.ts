import {
  authenticatedUserKey,
  database,
  isTrustedMutation,
  jsonResponse,
} from "../security";
import { validatePersistedState } from "../../state-schema";
import {
  AIConfigurationError,
  answerWithSakhyaAI,
  assertSakhyaAIConfigured,
  type AssistantMessage,
  type GroundedMetric,
} from "./service";

const MAX_REQUEST_BYTES = 32_000;
const MAX_MESSAGES = 12;
const MAX_MESSAGE_LENGTH = 2_000;

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

  let messages: AssistantMessage[];
  try {
    const bodyText = await request.text();
    if (new TextEncoder().encode(bodyText).byteLength > MAX_REQUEST_BYTES) {
      return jsonResponse({ error: "Assistant request is too large." }, 413);
    }
    const body = JSON.parse(bodyText) as { messages?: unknown };
    messages = validateMessages(body.messages);
  } catch {
    return jsonResponse({ error: "Invalid assistant request." }, 400);
  }

  try {
    assertSakhyaAIConfigured();
  } catch (error) {
    if (error instanceof AIConfigurationError) {
      return jsonResponse({ error: error.message, code: "AI_NOT_CONFIGURED" }, 503);
    }
    throw error;
  }

  const row = await database()
    .prepare("SELECT state_json AS stateJson FROM user_states WHERE user_id = ?")
    .bind(userId)
    .first<{ stateJson: string }>();

  const state = row ? validatePersistedState(JSON.parse(row.stateJson)) : null;
  try {
    const result = await answerWithSakhyaAI({
      userIdentifier: userId,
      messages,
      context: buildContext(state),
    });
    return jsonResponse({
      answer: result.answer,
      model: result.model,
      provider: result.provider,
      profile: "Everyday",
    });
  } catch (error) {
    if (error instanceof AIConfigurationError) {
      return jsonResponse({ error: error.message, code: "AI_NOT_CONFIGURED" }, 503);
    }
    console.error("Sakhya assistant error", error);
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
      text.trim().length === 0 ||
      text.length > MAX_MESSAGE_LENGTH
    ) {
      throw new Error("Invalid message.");
    }
    return { role, text: text.trim() };
  });
}

function buildContext(state: ReturnType<typeof validatePersistedState> | null) {
  const now = new Date();
  const cutoff = new Date(now);
  cutoff.setDate(cutoff.getDate() - 90);

  return state
    ? {
        generatedAt: now.toISOString(),
        timezone: "account-local",
        verifiedMetrics: buildVerifiedMetrics(state, now),
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
            source: entry.source,
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
          ...buildMoneyOverview(state, now),
        },
      }
    : {
        generatedAt: now.toISOString(),
        verifiedMetrics: [],
        entries: [],
        lists: [],
        trackers: [],
      };
}

function buildVerifiedMetrics(
  state: ReturnType<typeof validatePersistedState>,
  now: Date,
): GroundedMetric[] {
  const weekStart = new Date(now);
  weekStart.setDate(weekStart.getDate() - 6);
  weekStart.setHours(0, 0, 0, 0);
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const weekEntries = state.entries.filter((entry) => new Date(entry.timestamp) >= weekStart);
  const monthEntries = state.entries.filter((entry) => new Date(entry.timestamp) >= monthStart);
  const money = buildMoneyOverview(state, now);
  const sumMinutes = (kind: string) =>
    weekEntries
      .filter((entry) => entry.kind === kind)
      .reduce((sum, entry) => sum + (entry.minutes ?? 0), 0);
  const sourceFor = (kind: string) => {
    const sources = new Set(
      weekEntries
        .filter((entry) => entry.kind === kind && entry.source)
        .map((entry) => entry.source!),
    );
    return sources.size ? Array.from(sources).sort().join(", ") : "Sakhya timeline";
  };
  return [
    {
      name: "movement",
      value: sumMinutes("movement"),
      unit: "minutes",
      period: "last 7 days",
      source: sourceFor("movement"),
    },
    {
      name: "sleep",
      value: sumMinutes("sleep"),
      unit: "minutes",
      period: "last 7 days",
      source: sourceFor("sleep"),
    },
    {
      name: "work",
      value: sumMinutes("work"),
      unit: "minutes",
      period: "last 7 days",
      source: "Sakhya timeline",
    },
    {
      name: "spending",
      value: monthEntries
        .filter((entry) => entry.kind === "expense")
        .reduce((sum, entry) => sum + (entry.amount ?? 0), 0),
      unit: "EUR",
      period: "current month",
      source: sourceFor("expense"),
    },
    {
      name: "income",
      value: money.income,
      unit: "EUR",
      period: "current month",
      source: "Sakhya money records",
    },
    {
      name: "saved",
      value: money.saved,
      unit: "EUR",
      period: "current month",
      source: "Sakhya money records",
    },
    {
      name: "invested",
      value: money.invested,
      unit: "EUR",
      period: "current month",
      source: "Sakhya money records",
    },
    {
      name: "net worth",
      value: money.netWorth,
      unit: "EUR",
      period: "latest balances",
      source: "Sakhya balance sheet",
    },
  ];
}

function buildMoneyOverview(
  state: ReturnType<typeof validatePersistedState>,
  now: Date,
) {
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const currentMoneyEntries = state.moneyEntries.filter(
    (entry) => new Date(entry.date) >= monthStart && new Date(entry.date) <= now,
  );
  const totalFor = (kind: string) =>
    currentMoneyEntries
      .filter((entry) => entry.kind === kind)
      .reduce((sum, entry) => sum + entry.amount, 0);
  const assetCategories = new Set(["cash", "investments", "property", "otherAsset"]);
  const assets = state.balanceSheetItems
    .filter((item) => assetCategories.has(item.category))
    .reduce((sum, item) => sum + item.balance, 0);
  const liabilities = state.balanceSheetItems
    .filter((item) => !assetCategories.has(item.category))
    .reduce((sum, item) => sum + item.balance, 0);
  const spending = state.entries
    .filter((entry) => entry.kind === "expense" && new Date(entry.timestamp) >= monthStart)
    .reduce((sum, entry) => sum + (entry.amount ?? 0), 0);
  const income = totalFor("income");
  const saved = totalFor("saving");
  const invested = totalFor("investment");
  return {
    income,
    spending,
    saved,
    invested,
    assets,
    liabilities,
    netWorth: assets - liabilities,
    unallocatedSurplus: income - spending - saved - invested,
    balanceSheetItems: state.balanceSheetItems,
  };
}
