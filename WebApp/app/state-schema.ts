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
      photo,
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
        return {
          id: identifier(listItem.id),
          text: shortString(listItem.text, "list item", 1_000),
          done: Boolean(listItem.done),
          due: optionalString(listItem.due, "due date", 200),
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

  return {
    entries,
    lists,
    trackers,
    monthlyBudget: finiteNumber(source.monthlyBudget, "monthly budget", 0, 1_000_000_000),
    savingsTarget: finiteNumber(source.savingsTarget, "savings target", 0, 1_000_000_000),
    savingsCurrent: finiteNumber(source.savingsCurrent, "savings amount", 0, 1_000_000_000),
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

function optionalFiniteNumber(value: unknown, minimum: number, maximum: number): number | undefined {
  if (value == null) return undefined;
  return finiteNumber(value, "number", minimum, maximum);
}

function safeColor(value: unknown): string {
  const color = shortString(value, "list color", 32);
  if (!/^#[0-9a-f]{6}$/i.test(color)) throw new Error("A list color is invalid.");
  return color;
}
