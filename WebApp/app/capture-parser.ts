export type EntryKind =
  | "work"
  | "expense"
  | "movement"
  | "food"
  | "sleep"
  | "mindset"
  | "book"
  | "movie"
  | "list"
  | "journal"
  | "note";

export type ParsedCapture = {
  title: string;
  kind: EntryKind;
  timestamp: string;
  amount?: number;
  minutes?: number;
  list?: {
    target: "reminders" | "groceries" | "travel";
    text: string;
    due?: string;
  };
};

function parseMinutes(lower: string) {
  const durationMatch = lower.match(/\b(\d+)\s*(?:h|hr|hrs|hour|hours)\b/);
  const minuteMatch = lower.match(/\b(\d+)\s*(?:m|min|mins|minute|minutes)\b/);
  if (durationMatch) return Number(durationMatch[1]) * 60 + (minuteMatch ? Number(minuteMatch[1]) : 0);
  return minuteMatch ? Number(minuteMatch[1]) : undefined;
}

function parseTimestamp(lower: string, now: Date) {
  const date = new Date(now);
  const relativeDay = lower.match(/\b(today|tomorrow|yesterday)\b/)?.[1];
  if (relativeDay === "tomorrow") date.setDate(date.getDate() + 1);
  if (relativeDay === "yesterday") date.setDate(date.getDate() - 1);

  const time = lower.match(/\bat\s+([01]?\d|2[0-3])(?:(?::|\.)([0-5]\d))?\b/);
  if (time) date.setHours(Number(time[1]), Number(time[2] ?? 0), 0, 0);
  return date.toISOString();
}

function dueLabel(lower: string) {
  if (/\btomorrow\b/.test(lower)) return "Tomorrow";
  if (/\btoday\b/.test(lower)) return "Today";
  const weekday = lower.match(/\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/i)?.[1];
  return weekday ? weekday[0].toUpperCase() + weekday.slice(1).toLowerCase() : undefined;
}

function parseListIntent(text: string, lower: string): ParsedCapture["list"] | undefined {
  const isReminder = /\b(?:remind me|reminder|to[ -]?do)\b/.test(lower);
  const isBuyRequest = /^(?:please\s+)?(?:buy\b|i\s+(?:want|need)\s+to\s+buy\b)/.test(lower);
  const isListCommand =
    /^(?:please\s+)?(?:add|put|save)\b/.test(lower) &&
    /\b(?:list|grocer(?:y|ies)|shopping|travel ideas?|trip ideas?)\b/.test(lower);
  if (!isReminder && !isListCommand && !isBuyRequest) return undefined;

  const target = isBuyRequest || /\b(?:grocer(?:y|ies)|shopping)\b/.test(lower)
    ? "groceries"
    : /\b(?:travel|trip)\b/.test(lower)
      ? "travel"
      : "reminders";

  let itemText = text.trim();
  itemText = itemText.replace(/^(?:please\s+)?remind me to\s+/i, "");
  if (isBuyRequest) {
    itemText = itemText.replace(/^(?:please\s+)?i\s+(?:want|need)\s+to\s+buy\s+/i, "");
    itemText = itemText.replace(/^(?:please\s+)?buy\s+/i, "");
  }
  itemText = itemText.replace(/^(?:please\s+)?(?:add|put|save)\s+/i, "");
  itemText = itemText.replace(/\s+(?:to|on)\s+(?:my\s+)?(?:shopping|grocery|groceries|travel ideas?|trip ideas?)(?:\s+list)?\s*$/i, "");
  itemText = itemText.replace(/\s+(?:today|tomorrow)\s*$/i, "");
  itemText = itemText.replace(/\s+on\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s*$/i, "");

  return { target, text: itemText.trim() || text.trim(), due: dueLabel(lower) };
}

export function parseCapture(text: string, now = new Date()): ParsedCapture {
  const title = text.trim();
  const lower = title.toLowerCase();
  const amountMatch = title.match(/(?:€|eur\s*)\s?(\d+(?:[.,]\d{1,2})?)|(\d+(?:[.,]\d{1,2})?)\s?(?:€|eur)/i);
  const amountValue = amountMatch?.[1] ?? amountMatch?.[2];
  const list = parseListIntent(title, lower);
  const explicitJournal = /^(?:journal|reflection)\s*:/i.test(title);
  const explicitMindset = /^(?:mood|mindset|feeling)\s*:/i.test(title);
  let kind: EntryKind = "note";

  // Explicit user intent wins over words contained in the item itself.
  if (list) kind = "list";
  else if (explicitJournal) kind = "journal";
  else if (explicitMindset) kind = "mindset";
  else if (amountMatch || /\b(?:spent|bought|paid|expense|cost)\b/.test(lower)) kind = "expense";
  else if (/\b(?:walk(?:ed|ing)?|hik(?:e|ed|ing)|ran|run|running|gym|workout|yoga|cycl(?:e|ed|ing)|swim|swam|swimming|climb(?:ed|ing)?)\b/.test(lower)) kind = "movement";
  else if (/\b(?:slept|sleep|sleeping|nap|napped)\b/.test(lower)) kind = "sleep";
  else if (/\b(?:breakfast|lunch|dinner|ate|meal|food)\b/.test(lower)) kind = "food";
  else if (/\b(?:read|reading|book|novel)\b/.test(lower)) kind = "book";
  else if (/\b(?:watch|watched|watching|movie|film|documentary|series)\b/.test(lower)) kind = "movie";
  else if (/\b(?:feel|felt|mood|grateful|mindset|energized|calm|anxious|stressed)\b/.test(lower)) kind = "mindset";
  else if (/\b(?:journal|reflect|reflected|reflection)\b/.test(lower)) kind = "journal";
  else if (/\b(?:work|worked|working|meeting|focus|client)\b/.test(lower)) kind = "work";

  return {
    title,
    kind,
    timestamp: parseTimestamp(lower, now),
    minutes: parseMinutes(lower),
    amount: amountValue ? Number(amountValue.replace(",", ".")) : undefined,
    list,
  };
}
