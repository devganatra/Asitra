export type PrioritizableList = {
  id: string;
  name: string;
  items: Array<{
    id: string;
    text: string;
    done: boolean;
    due?: string;
    plannedDate?: string;
    planMode?: "anytime" | "exact" | "window";
    startTime?: string;
    endTime?: string;
    durationMinutes?: number;
  }>;
};

export type ChosenCommitment = {
  id: string;
  text: string;
  done: boolean;
  due?: string;
  plannedDate?: string;
  planMode?: "anytime" | "exact" | "window";
  startTime?: string;
  endTime?: string;
  durationMinutes?: number;
  listId: string;
  listName: string;
};

export function finitePriorityView(
  lists: PrioritizableList[],
  chosenIds: string[],
  limit = 3,
) {
  const open = lists.flatMap((list) =>
    list.items
      .filter((item) => !item.done)
      .map((item) => ({ ...item, listId: list.id, listName: list.name })),
  );
  const uniqueChosenIds = [...new Set(chosenIds)].slice(0, limit);
  const chosen = uniqueChosenIds
    .map((id) => open.find((item) => item.id === id))
    .filter((item): item is ChosenCommitment => Boolean(item));
  const later = open.filter((item) => !uniqueChosenIds.includes(item.id));
  return { chosen, later };
}

export function initialPriorityIds(lists: PrioritizableList[], limit = 3) {
  return lists
    .flatMap((list) => list.items)
    .filter((item) => !item.done)
    .slice(0, limit)
    .map((item) => item.id);
}

export type TaskPlan = {
  mode: "anytime" | "exact" | "window";
  startTime?: string;
  endTime?: string;
  durationMinutes?: number;
};

export function validateTaskPlan(plan: TaskPlan) {
  if (plan.mode === "anytime") return { valid: true as const };
  if (!plan.startTime || !plan.endTime || plan.endTime <= plan.startTime) {
    return { valid: false as const, message: "Choose an end time after the start time." };
  }
  if (plan.mode === "window" && (!plan.durationMinutes || plan.durationMinutes <= 0)) {
    return { valid: false as const, message: "Add a realistic duration for this time window." };
  }
  const [startHour, startMinute] = plan.startTime.split(":").map(Number);
  const [endHour, endMinute] = plan.endTime.split(":").map(Number);
  const windowMinutes = endHour * 60 + endMinute - startHour * 60 - startMinute;
  if (plan.mode === "window" && (plan.durationMinutes ?? 0) > windowMinutes) {
    return { valid: false as const, message: "The estimated duration must fit inside the selected window." };
  }
  return { valid: true as const };
}

export function postponeDate(dateKey: string, days = 1) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateKey);
  if (!match) throw new Error("Invalid task date.");
  const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]) + days, 12, 0, 0);
  const year = String(date.getFullYear()).padStart(4, "0");
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export type TaskPriorityQuadrant = "do" | "plan" | "simplify" | "later";

export function taskPriorityQuadrant(task: { important?: boolean; urgent?: boolean }): TaskPriorityQuadrant {
  if (task.important && task.urgent) return "do";
  if (task.important) return "plan";
  if (task.urgent) return "simplify";
  return "later";
}

export function taskBoardColumn(
  task: { done: boolean; boardColumnId?: string },
  availableColumnIds: string[],
) {
  if (task.done && availableColumnIds.includes("done")) return "done";
  if (task.boardColumnId && availableColumnIds.includes(task.boardColumnId)) return task.boardColumnId;
  return availableColumnIds[0] ?? "todo";
}

export type MoneyCycleRange = {
  start: Date;
  end: Date;
};

export function normalizeMoneyCycleStartDay(value: number): number {
  if (!Number.isFinite(value)) return 1;
  return Math.min(Math.max(Math.trunc(value), 1), 31);
}

function cycleDate(year: number, month: number, startDay: number): Date {
  const lastDay = new Date(year, month + 1, 0).getDate();
  return new Date(year, month, Math.min(normalizeMoneyCycleStartDay(startDay), lastDay));
}

export function moneyCycleRange(reference: Date, startDay: number, offset = 0): MoneyCycleRange {
  const normalizedDay = normalizeMoneyCycleStartDay(startDay);
  let currentStart = cycleDate(reference.getFullYear(), reference.getMonth(), normalizedDay);
  if (reference < currentStart) {
    currentStart = cycleDate(reference.getFullYear(), reference.getMonth() - 1, normalizedDay);
  }
  const start = cycleDate(currentStart.getFullYear(), currentStart.getMonth() + offset, normalizedDay);
  const end = cycleDate(start.getFullYear(), start.getMonth() + 1, normalizedDay);
  return { start, end };
}

export function isInsideMoneyCycle(value: string | Date, range: MoneyCycleRange): boolean {
  const date = typeof value === "string" ? new Date(value) : value;
  return Number.isFinite(date.getTime()) && date >= range.start && date < range.end;
}

export function personalFinancePerspectives(input: {
  monthlyBudget: number;
  income: number;
  spent: number;
  saved: number;
  invested: number;
  assets: number;
  liabilities: number;
}) {
  const budgetRemaining = input.monthlyBudget - input.spent;
  const surplusAfterSpending = input.income - input.spent;
  const unassigned = surplusAfterSpending - input.saved - input.invested;
  const netCashMovement = input.income - input.spent - input.invested;
  const netWorth = input.assets - input.liabilities;
  return {
    budgetRemaining,
    surplusAfterSpending,
    unassigned,
    netCashMovement,
    netWorth,
    isFullyAssigned: Math.abs(unassigned) < 0.01,
  };
}

export type TripBudget = {
  id: string;
  budget: number;
};

export type TripExpense = {
  tripId?: string;
  amount?: number;
};

export function tripBudgetSummary(trip: TripBudget, expenses: TripExpense[]) {
  const linkedExpenses = expenses.filter(
    (expense) => expense.tripId === trip.id && typeof expense.amount === "number",
  );
  const spent = linkedExpenses.reduce((sum, expense) => sum + (expense.amount ?? 0), 0);
  const difference = trip.budget - spent;
  return {
    spent,
    remaining: Math.max(difference, 0),
    over: Math.max(-difference, 0),
    progress: trip.budget <= 0 ? 0 : Math.min((spent / trip.budget) * 100, 100),
    expenseCount: linkedExpenses.length,
  };
}

export type EntryCapabilities = {
  editable: true;
  deletable: true;
  schedulable: true;
  completable: boolean;
  usesAmount: boolean;
  usesDuration: boolean;
  usesStatus: boolean;
  canLinkTrip: boolean;
};

export function entryCapabilities(kind: string): EntryCapabilities {
  return {
    editable: true,
    deletable: true,
    schedulable: true,
    completable: kind === "list",
    usesAmount: kind === "expense",
    usesDuration: ["work", "movement", "sleep", "book", "movie"].includes(kind),
    usesStatus: kind === "book" || kind === "movie",
    canLinkTrip: kind === "expense",
  };
}
