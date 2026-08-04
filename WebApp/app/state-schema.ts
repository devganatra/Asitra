const ENTRY_KINDS = new Set([
  "work",
  "expense",
  "movement",
  "food",
  "sleep",
  "mindset",
  "book",
  "movie",
  "list",
  "journal",
  "note",
]);
const TRACKER_FAMILIES = new Set(["Health", "Habits", "Learning & Media", "Mindset"]);
const MONEY_ENTRY_KINDS = new Set(["income", "saving", "investment"]);
const BALANCE_SHEET_CATEGORIES = new Set([
  "cash",
  "investments",
  "property",
  "otherAsset",
  "creditCard",
  "loan",
  "otherLiability",
]);
const TASK_PLAN_MODES = new Set(["anytime", "exact", "window"]);
const ENTRY_STATUSES = new Set(["planned", "inProgress", "completed"]);
const ATTACHMENT_PATH = /^\/api\/attachments\/[0-9a-f-]{36}$/i;
const LEGACY_IMAGE = /^data:image\/(?:jpeg|png|webp);base64,/i;

type ValidationOptions = {
  allowLegacyDataImages?: boolean;
};

export function validatePersistedState(value: unknown, options: ValidationOptions = {}) {
  const source = record(value, "backup");
  const entries = array(source.entries, "entries", 5_000).map((item, index) => {
    const entry = record(item, `entries[${index}]`);
    const kind = shortString(entry.kind, "entry category", 32);
    if (!ENTRY_KINDS.has(kind)) throw new Error("Unknown entry category.");
    const timestamp = shortString(entry.timestamp, "entry date", 64);
    if (!Number.isFinite(Date.parse(timestamp))) throw new Error("An entry has an invalid date.");
    const endTimestamp = optionalString(entry.endTimestamp, "entry end date", 64);
    if (endTimestamp && (!Number.isFinite(Date.parse(endTimestamp)) || Date.parse(endTimestamp) < Date.parse(timestamp))) {
      throw new Error("An entry has an invalid time range.");
    }
    const status = optionalString(entry.status, "entry status", 32);
    if (status && !ENTRY_STATUSES.has(status)) throw new Error("An entry has an invalid status.");
    const photo = optionalString(entry.photo, "attachment", 2_100_000);
    if (
      photo &&
      !ATTACHMENT_PATH.test(photo) &&
      !(options.allowLegacyDataImages && LEGACY_IMAGE.test(photo))
    ) {
      throw new Error("An entry contains an unsupported attachment.");
    }
    return {
      id: identifier(entry.id),
      title: shortString(entry.title, "entry title", 500),
      kind,
      timestamp,
      amount: optionalFiniteNumber(entry.amount, 0, 1_000_000_000),
      minutes: optionalFiniteNumber(entry.minutes, 0, 525_600),
      note: optionalString(entry.note, "entry note", 10_000),
      source: optionalString(entry.source, "entry source", 200),
      photo,
      tripId: entry.tripId == null ? undefined : identifier(entry.tripId),
      listId: entry.listId == null ? undefined : identifier(entry.listId),
      endTimestamp,
      completed: optionalBoolean(entry.completed, "entry completion"),
      status,
    };
  });

  const lists = array(source.lists, "lists", 250).map((item, index) => {
    const list = record(item, `lists[${index}]`);
    return {
      id: identifier(list.id),
      name: shortString(list.name, "list name", 200),
      shared: Boolean(list.shared),
      members: finiteNumber(list.members, "member count", 1, 1_000),
      color: safeColor(list.color),
      items: array(list.items, "list items", 1_000).map((rawItem) => {
        const listItem = record(rawItem, "list item");
        const planMode = optionalString(listItem.planMode, "task plan mode", 16);
        if (planMode && !TASK_PLAN_MODES.has(planMode)) throw new Error("Unknown task plan mode.");
        const plannedDate = optionalString(listItem.plannedDate, "task planned date", 10);
        if (plannedDate && !/^\d{4}-\d{2}-\d{2}$/.test(plannedDate)) throw new Error("A task has an invalid planned date.");
        const startTime = optionalString(listItem.startTime, "task start time", 5);
        const endTime = optionalString(listItem.endTime, "task end time", 5);
        if (startTime && !/^([01]\d|2[0-3]):[0-5]\d$/.test(startTime)) throw new Error("A task has an invalid start time.");
        if (endTime && !/^([01]\d|2[0-3]):[0-5]\d$/.test(endTime)) throw new Error("A task has an invalid end time.");
        return {
          id: identifier(listItem.id),
          text: shortString(listItem.text, "list item", 1_000),
          done: Boolean(listItem.done),
          due: optionalString(listItem.due, "due date", 200),
          plannedDate,
          planMode,
          startTime,
          endTime,
          durationMinutes: optionalFiniteNumber(listItem.durationMinutes, 1, 10_080),
        };
      }),
    };
  });

  const trackers = array(source.trackers, "trackers", 250).map((item) => {
    const tracker = record(item, "tracker");
    const family = shortString(tracker.family, "tracker family", 64);
    if (!TRACKER_FAMILIES.has(family)) throw new Error("Unknown tracker family.");
    return {
      id: identifier(tracker.id),
      family,
      name: shortString(tracker.name, "tracker name", 200),
      icon: shortString(tracker.icon, "tracker icon", 64),
      target: optionalFiniteNumber(tracker.target, 0, 100_000),
    };
  });

  const moneyEntries = optionalArray(source.moneyEntries, "money entries", 5_000).map((item) => {
    const entry = record(item, "money entry");
    const kind = shortString(entry.kind, "money entry type", 32);
    if (!MONEY_ENTRY_KINDS.has(kind)) throw new Error("Unknown money entry type.");
    const date = shortString(entry.date, "money entry date", 64);
    if (!Number.isFinite(Date.parse(date))) throw new Error("A money entry has an invalid date.");
    return {
      id: identifier(entry.id),
      kind,
      amount: finiteNumber(entry.amount, "money entry amount", 0, 1_000_000_000),
      date,
      note: optionalString(entry.note, "money entry note", 1_000),
    };
  });

  const balanceSheetItems = optionalArray(source.balanceSheetItems, "balance sheet items", 1_000).map((item) => {
    const balanceItem = record(item, "balance sheet item");
    const category = shortString(balanceItem.category, "balance sheet category", 32);
    if (!BALANCE_SHEET_CATEGORIES.has(category)) throw new Error("Unknown balance sheet category.");
    const updatedAt = shortString(balanceItem.updatedAt, "balance update date", 64);
    if (!Number.isFinite(Date.parse(updatedAt))) throw new Error("A balance has an invalid update date.");
    return {
      id: identifier(balanceItem.id),
      name: shortString(balanceItem.name, "balance name", 200),
      balance: finiteNumber(balanceItem.balance, "balance", 0, 1_000_000_000),
      category,
      updatedAt,
    };
  });

  const trips = optionalArray(source.trips, "trips", 250).map((item, index) => {
    const trip = record(item, `trips[${index}]`);
    const startDate = shortString(trip.startDate, "trip start date", 64);
    const endDate = shortString(trip.endDate, "trip end date", 64);
    const createdAt = shortString(trip.createdAt, "trip creation date", 64);
    const startTime = Date.parse(startDate);
    const endTime = Date.parse(endDate);
    if (!Number.isFinite(startTime) || !Number.isFinite(endTime) || endTime < startTime) {
      throw new Error("A trip has an invalid date range.");
    }
    if (!Number.isFinite(Date.parse(createdAt))) throw new Error("A trip has an invalid creation date.");
    return {
      id: identifier(trip.id),
      name: shortString(trip.name, "trip name", 200),
      destination: shortString(trip.destination, "trip destination", 200),
      budget: finiteNumber(trip.budget, "trip budget", 0.01, 1_000_000_000),
      startDate,
      endDate,
      createdAt,
    };
  });

  return {
    onboardingCompleted:
      source.onboardingCompleted === undefined ? true : Boolean(source.onboardingCompleted),
    entries,
    lists,
    trackers,
    priorityDay: optionalString(source.priorityDay, "priority day", 10) ?? "",
    todayPriorityIds: optionalArray(source.todayPriorityIds, "today priorities", 3).map(identifier),
    monthlyBudget: finiteNumber(source.monthlyBudget, "monthly budget", 0, 1_000_000_000),
    moneyCycleStartDay: integer(
      source.moneyCycleStartDay === undefined ? 1 : source.moneyCycleStartDay,
      "money cycle start day",
      1,
      31,
    ),
    savingsTarget: finiteNumber(source.savingsTarget, "savings target", 0, 1_000_000_000),
    savingsCurrent: finiteNumber(source.savingsCurrent, "savings amount", 0, 1_000_000_000),
    moneyEntries,
    balanceSheetItems,
    trips,
  };
}

function record(value: unknown, label: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} must be an object.`);
  }
  return value as Record<string, unknown>;
}

function array(value: unknown, label: string, maximum: number): unknown[] {
  if (!Array.isArray(value) || value.length > maximum) {
    throw new Error(`${label} is invalid or too large.`);
  }
  return value;
}

function optionalArray(value: unknown, label: string, maximum: number): unknown[] {
  if (value == null) return [];
  return array(value, label, maximum);
}

function shortString(value: unknown, label: string, maximum: number): string {
  if (typeof value !== "string" || value.length === 0 || value.length > maximum) {
    throw new Error(`${label} is invalid.`);
  }
  return value;
}

function optionalString(value: unknown, label: string, maximum: number): string | undefined {
  if (value == null) return undefined;
  if (typeof value !== "string" || value.length > maximum) throw new Error(`${label} is invalid.`);
  return value;
}

function identifier(value: unknown): string {
  const id = shortString(value, "identifier", 128);
  if (!/^[a-zA-Z0-9-]+$/.test(id)) throw new Error("An identifier is invalid.");
  return id;
}

function finiteNumber(value: unknown, label: string, minimum: number, maximum: number): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < minimum || value > maximum) {
    throw new Error(`${label} is invalid.`);
  }
  return value;
}

function integer(value: unknown, label: string, minimum: number, maximum: number): number {
  const result = finiteNumber(value, label, minimum, maximum);
  if (!Number.isInteger(result)) throw new Error(`${label} is invalid.`);
  return result;
}

function optionalFiniteNumber(value: unknown, minimum: number, maximum: number): number | undefined {
  if (value == null) return undefined;
  return finiteNumber(value, "number", minimum, maximum);
}

function optionalBoolean(value: unknown, label: string): boolean | undefined {
  if (value == null) return undefined;
  if (typeof value !== "boolean") throw new Error(`${label} is invalid.`);
  return value;
}

function safeColor(value: unknown): string {
  const color = shortString(value, "list color", 32);
  if (!/^#[0-9a-f]{6}$/i.test(color)) throw new Error("A list color is invalid.");
  return color;
}
