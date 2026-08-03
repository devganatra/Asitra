import assert from "node:assert/strict";
import test from "node:test";
import {
  isMoneyRecordCommand,
  parseMoneyInstruction,
  parseStatementText,
} from "../app/money-import";

const now = new Date("2026-07-29T12:00:00.000Z");

test("understands typed Sakhya expense and income instructions", () => {
  const expense = parseMoneyInstruction("Spent €24.50 on groceries yesterday", now);
  assert.equal(expense?.kind, "expense");
  assert.equal(expense?.amount, 24.5);
  assert.equal(expense?.date.slice(0, 10), "2026-07-28");

  const income = parseMoneyInstruction("Received salary 3.200,00 EUR today", now);
  assert.equal(income?.kind, "income");
  assert.equal(income?.amount, 3200);
});

test("does not turn a money question into a new transaction", () => {
  assert.equal(isMoneyRecordCommand("How much did I spend, €24 or €42?"), false);
  assert.equal(isMoneyRecordCommand("I spent €24 on groceries"), true);
});

test("classifies balance snapshots separately from cash-flow transactions", () => {
  const asset = parseMoneyInstruction("My savings account balance is €8,400", now);
  assert.equal(asset?.kind, "asset");
  assert.equal(asset?.balanceCategory, "cash");
  assert.equal(asset?.amount, 8400);

  const debt = parseMoneyInstruction("I owe €1,250 on my credit card", now);
  assert.equal(debt?.kind, "liability");
  assert.equal(debt?.balanceCategory, "creditCard");

  const investment = parseMoneyInstruction("I invested €500 in an ETF today", now);
  assert.equal(investment?.kind, "investment");
  assert.equal(investment?.balanceCategory, undefined);
});

test("extracts debit and credit transactions from common statement text", () => {
  const parsed = parseStatementText(
    [
      "01.07.2026 Supermarket Heinsberg -42,18 EUR",
      "02.07.2026 Employer salary +3.200,00 EUR",
      "Closing balance 4.120,22 EUR",
    ].join("\n"),
    now,
  );

  assert.equal(parsed.length, 2);
  assert.deepEqual(
    parsed.map(({ kind, amount }) => ({ kind, amount })),
    [
      { kind: "expense", amount: 42.18 },
      { kind: "income", amount: 3200 },
    ],
  );
  assert.match(parsed[0].title, /Supermarket Heinsberg/);
});

test("deduplicates repeated statement lines and rejects balance summaries", () => {
  const parsed = parseStatementText(
    [
      "03.07.2026 Monthly train pass 59,00 EUR",
      "03.07.2026 Monthly train pass 59,00 EUR",
      "Available balance 03.07.2026 999,00 EUR",
    ].join("\n"),
    now,
  );
  assert.equal(parsed.length, 1);
  assert.equal(parsed[0].kind, "expense");
});
