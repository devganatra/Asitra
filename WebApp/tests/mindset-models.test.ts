import assert from "node:assert/strict";
import test from "node:test";
import {
  finitePriorityView,
  initialPriorityIds,
  isInsideMoneyCycle,
  moneyCycleRange,
  personalFinancePerspectives,
  postponeDate,
  validateTaskPlan,
} from "../app/mindset-models";

const lists = [
  {
    id: "personal",
    name: "Personal",
    items: [
      { id: "one", text: "Focus block", done: false },
      { id: "two", text: "Lunch with Alex", done: false },
      { id: "three", text: "Read", done: false },
      { id: "four", text: "Book dentist", done: false },
      { id: "done", text: "Already finished", done: true },
    ],
  },
];

test("keeps at most three active commitments and leaves the rest for later", () => {
  const initial = initialPriorityIds(lists);
  assert.deepEqual(initial, ["one", "two", "three"]);
  const view = finitePriorityView(lists, [...initial, "four"]);
  assert.deepEqual(view.chosen.map((item) => item.id), ["one", "two", "three"]);
  assert.deepEqual(view.later.map((item) => item.id), ["four"]);
});

test("shows budget, cash flow, allocation and net worth from one ledger", () => {
  const result = personalFinancePerspectives({
    monthlyBudget: 2_000,
    income: 3_200,
    spent: 1_500,
    saved: 700,
    invested: 600,
    assets: 84_000,
    liabilities: 14_000,
  });
  assert.equal(result.budgetRemaining, 500);
  assert.equal(result.netCashMovement, 1_100);
  assert.equal(result.surplusAfterSpending, 1_700);
  assert.equal(result.unassigned, 400);
  assert.equal(result.netWorth, 70_000);
  assert.equal(result.isFullyAssigned, false);

  const edited = personalFinancePerspectives({
    monthlyBudget: 2_000,
    income: 3_200,
    spent: 1_400,
    saved: 700,
    invested: 600,
    assets: 84_000,
    liabilities: 14_000,
  });
  assert.equal(edited.budgetRemaining, 600);
  assert.equal(edited.netCashMovement, 1_200);
  assert.equal(edited.unassigned, 500);
});

test("validates exact blocks and flexible windows, then postpones the whole plan", () => {
  assert.deepEqual(validateTaskPlan({ mode: "exact", startTime: "13:00", endTime: "15:00" }), { valid: true });
  assert.equal(validateTaskPlan({ mode: "exact", startTime: "15:00", endTime: "13:00" }).valid, false);
  assert.equal(validateTaskPlan({ mode: "window", startTime: "13:00", endTime: "17:00", durationMinutes: 90 }).valid, true);
  assert.equal(validateTaskPlan({ mode: "window", startTime: "13:00", endTime: "14:00", durationMinutes: 90 }).valid, false);
  assert.equal(postponeDate("2026-08-31"), "2026-09-01");
});

test("builds salary-aligned monthly cycles and clamps short months", () => {
  const salaryCycle = moneyCycleRange(new Date(2026, 7, 4, 12), 25);
  assert.deepEqual(
    [salaryCycle.start.getFullYear(), salaryCycle.start.getMonth(), salaryCycle.start.getDate()],
    [2026, 6, 25],
  );
  assert.deepEqual(
    [salaryCycle.end.getFullYear(), salaryCycle.end.getMonth(), salaryCycle.end.getDate()],
    [2026, 7, 25],
  );
  assert.equal(isInsideMoneyCycle(new Date(2026, 6, 25, 0), salaryCycle), true);
  assert.equal(isInsideMoneyCycle(new Date(2026, 7, 25, 0), salaryCycle), false);

  const monthEndCycle = moneyCycleRange(new Date(2026, 2, 15, 12), 31);
  assert.deepEqual(
    [monthEndCycle.start.getMonth(), monthEndCycle.start.getDate()],
    [1, 28],
  );
  assert.deepEqual(
    [monthEndCycle.end.getMonth(), monthEndCycle.end.getDate()],
    [2, 31],
  );
});
