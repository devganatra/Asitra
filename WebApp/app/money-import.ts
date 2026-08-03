export type ImportedMoneyTransaction = {
  id: string;
  kind: "expense" | "income";
  title: string;
  amount: number;
  date: string;
  selected: boolean;
};

export type ParsedMoneyInstruction = {
  kind: "expense" | "income" | "saving" | "investment" | "asset" | "liability";
  title: string;
  amount: number;
  date: string;
  balanceCategory?: "cash" | "investments" | "property" | "otherAsset" | "creditCard" | "loan" | "otherLiability";
  confidence: "high" | "medium";
};

const DATE_PATTERN = /\b(\d{1,2})[./-](\d{1,2})(?:[./-](\d{2,4}))?\b/;
const AMOUNT_PATTERN =
  /([+-]?\s*(?:\d{1,3}(?:[.\s]\d{3})*|\d+)[,.]\d{2})\s*(?:€|EUR)?\s*([+-])?/gi;

function isoDate(year: number, month: number, day: number) {
  const date = new Date(year, month - 1, day, 12, 0, 0, 0);
  if (
    date.getFullYear() !== year ||
    date.getMonth() !== month - 1 ||
    date.getDate() !== day
  ) {
    return undefined;
  }
  return date.toISOString();
}

function parseStatementDate(match: RegExpMatchArray, now: Date) {
  let year = match[3] ? Number(match[3]) : now.getFullYear();
  if (year < 100) year += year < 70 ? 2000 : 1900;
  const month = Number(match[2]);
  const day = Number(match[1]);
  if (!match[3] && month > now.getMonth() + 2) year -= 1;
  return isoDate(year, month, day);
}

function parseLocalizedAmount(raw: string) {
  const compact = raw.replace(/\s/g, "");
  const lastComma = compact.lastIndexOf(",");
  const lastDot = compact.lastIndexOf(".");
  const decimalIndex = Math.max(lastComma, lastDot);
  const integer = compact.slice(0, decimalIndex).replace(/[.,]/g, "");
  const decimal = compact.slice(decimalIndex + 1);
  return Number(`${integer}.${decimal}`);
}

function transactionTitle(line: string, dateText: string, amountText: string) {
  return (
    line
      .replace(dateText, "")
      .replace(amountText, "")
      .replace(/\b(?:EUR|€)\b/gi, "")
      .replace(/\s{2,}/g, " ")
      .replace(/^[\s|:;,-]+|[\s|:;,-]+$/g, "")
      .trim() || "Statement transaction"
  ).slice(0, 160);
}

export function parseStatementText(text: string, now = new Date()): ImportedMoneyTransaction[] {
  const transactions: ImportedMoneyTransaction[] = [];
  const seen = new Set<string>();
  const lines = text
    .split(/\r?\n/)
    .map((line) => line.replace(/\s+/g, " ").trim())
    .filter(Boolean);

  for (const line of lines) {
    if (/\b(opening|closing|available|new)\s+balance\b/i.test(line)) continue;
    const dateMatch = line.match(DATE_PATTERN);
    if (!dateMatch) continue;
    const date = parseStatementDate(dateMatch, now);
    if (!date) continue;

    const amounts = [...line.matchAll(AMOUNT_PATTERN)];
    const amountMatch = amounts.at(-1);
    if (!amountMatch) continue;
    const amount = Math.abs(parseLocalizedAmount(amountMatch[1]));
    if (!Number.isFinite(amount) || amount <= 0 || amount > 1_000_000_000) continue;

    const rawAmount = amountMatch[0];
    const signedText = `${amountMatch[1]}${amountMatch[2] ?? ""}`.replace(/\s/g, "");
    const explicitlyPositive = signedText.startsWith("+") || /\bcredit\b/i.test(line);
    const explicitlyNegative = signedText.startsWith("-") || signedText.endsWith("-");
    const kind: ImportedMoneyTransaction["kind"] =
      explicitlyPositive && !explicitlyNegative ? "income" : "expense";
    const title = transactionTitle(line, dateMatch[0], rawAmount);
    const fingerprint = `${date.slice(0, 10)}|${kind}|${amount.toFixed(2)}|${title.toLowerCase()}`;
    if (seen.has(fingerprint)) continue;
    seen.add(fingerprint);
    transactions.push({
      id: crypto.randomUUID(),
      kind,
      title,
      amount,
      date,
      selected: true,
    });
  }

  return transactions.slice(0, 500);
}

export function parseMoneyInstruction(
  text: string,
  now = new Date(),
): ParsedMoneyInstruction | undefined {
  const amountMatch = text.match(
    /(?:€|eur\s*)\s?((?:\d{1,3}(?:[.\s]\d{3})*|\d+)(?:[.,]\d{1,3})?)|((?:\d{1,3}(?:[.\s]\d{3})*|\d+)(?:[.,]\d{1,3})?)\s?(?:€|eur)/i,
  );
  const rawAmount = amountMatch?.[1] ?? amountMatch?.[2];
  if (!rawAmount) return undefined;
  const compactAmount = rawAmount.replace(/\s/g, "");
  const amount = /[.,]\d{3}$/.test(compactAmount) && !/[.,].*[.,]/.test(compactAmount)
    ? Number(compactAmount.replace(/[.,]/g, ""))
    : /[.,].*[.,]/.test(compactAmount)
      ? parseLocalizedAmount(compactAmount)
      : Number(compactAmount.replace(",", "."));
  if (!Number.isFinite(amount) || amount <= 0 || amount > 1_000_000_000) return undefined;

  const lower = text.toLowerCase();
  let kind: ParsedMoneyInstruction["kind"];
  let balanceCategory: ParsedMoneyInstruction["balanceCategory"];
  const isBalanceSnapshot = /\b(balance|worth|owe|owed|debt|loan|mortgage|credit card|bank account|account has|portfolio is|portfolio worth)\b/.test(lower);
  if (isBalanceSnapshot && /\b(owe|owed|debt|loan|mortgage|credit card)\b/.test(lower)) {
    kind = "liability";
    balanceCategory = /credit card/.test(lower) ? "creditCard" : /\b(loan|mortgage)\b/.test(lower) ? "loan" : "otherLiability";
  } else if (isBalanceSnapshot && /\b(property|house|home)\b/.test(lower)) {
    kind = "asset";
    balanceCategory = "property";
  } else if (isBalanceSnapshot && /\b(portfolio|brokerage|investment account|shares|stocks|etf)\b/.test(lower)) {
    kind = "asset";
    balanceCategory = "investments";
  } else if (isBalanceSnapshot) {
    kind = "asset";
    balanceCategory = /\b(bank|account|cash|wallet)\b/.test(lower) ? "cash" : "otherAsset";
  } else if (/\b(invest|invested|investment)\b/.test(lower)) kind = "investment";
  else if (/\b(save|saved|saving)\b/.test(lower)) kind = "saving";
  else if (/\b(income|salary|earned|received|refund|paid me)\b/.test(lower)) kind = "income";
  else if (/\b(spent|bought|paid|expense|cost|purchase|add|record|log)\b/.test(lower)) {
    kind = "expense";
  } else {
    return undefined;
  }

  const date = new Date(now);
  if (/\byesterday\b/.test(lower)) date.setDate(date.getDate() - 1);
  else if (/\btomorrow\b/.test(lower)) date.setDate(date.getDate() + 1);
  const explicitDate = text.match(DATE_PATTERN);
  const parsedDate = explicitDate ? parseStatementDate(explicitDate, now) : undefined;

  return {
    kind,
    title: text.trim().slice(0, 500),
    amount,
    date: parsedDate ?? date.toISOString(),
    balanceCategory,
    confidence: "high",
  };
}

export function isMoneyRecordCommand(text: string) {
  const trimmed = text.trim();
  if (!trimmed || trimmed.endsWith("?") || /^(?:how|what|when|where|why|did|do|can|could|tell)\b/i.test(trimmed)) {
    return false;
  }
  return /\b(?:add|record|log|spent|bought|paid|received|earned|saved|invested)\b/i.test(trimmed);
}

export async function extractPdfText(file: File) {
  if (file.type !== "application/pdf" || file.size > 10_000_000) {
    throw new Error("Choose a PDF under 10 MB.");
  }
  const pdfjs = await import("pdfjs-dist/legacy/build/pdf.mjs");
  pdfjs.GlobalWorkerOptions.workerSrc = new URL(
    "pdfjs-dist/legacy/build/pdf.worker.min.mjs",
    import.meta.url,
  ).toString();
  const document = await pdfjs.getDocument({ data: new Uint8Array(await file.arrayBuffer()) }).promise;
  const pages: string[] = [];
  for (let pageNumber = 1; pageNumber <= document.numPages; pageNumber += 1) {
    const page = await document.getPage(pageNumber);
    const content = await page.getTextContent();
    const lines = new Map<number, string[]>();
    for (const rawItem of content.items) {
      if (!("str" in rawItem) || !rawItem.str.trim()) continue;
      const y = Math.round(rawItem.transform[5] / 3) * 3;
      lines.set(y, [...(lines.get(y) ?? []), rawItem.str.trim()]);
    }
    pages.push(
      [...lines.entries()]
        .sort(([first], [second]) => second - first)
        .map(([, items]) => items.join(" "))
        .join("\n"),
    );
  }
  await document.destroy();
  return pages.join("\n");
}
