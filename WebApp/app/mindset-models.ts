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
