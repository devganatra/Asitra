"use client";

import {
  Activity,
  ArrowRight,
  BarChart3,
  BookOpen,
  Brain,
  CalendarDays,
  CalendarClock,
  Camera,
  Check,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  CircleDollarSign,
  Clock3,
  Columns3,
  Download,
  FileText,
  Film,
  Flag,
  Grid2X2,
  HeartPulse,
  Home,
  Inbox,
  ListChecks,
  Lock,
  LogOut,
  MapPin,
  Menu,
  Mic,
  Moon,
  MoreHorizontal,
  Pencil,
  Plus,
  RotateCcw,
  Search,
  Send,
  Settings,
  ShieldCheck,
  Sparkles,
  Target,
  Trash2,
  Upload,
  Users,
  WalletCards,
  X,
  Zap,
} from "lucide-react";
import { ASITRA_RELEASE_LABEL } from "./release";
import { ASITRA_AI_CONTRACT, type AsitraAIContract } from "./ai-contract";
import { ChangeEvent, FormEvent, useEffect, useMemo, useRef, useState } from "react";
import {
  extractPdfText,
  ImportedMoneyTransaction,
  isMoneyRecordCommand,
  parseMoneyInstruction,
  parseStatementText,
  type ParsedMoneyInstruction,
} from "./money-import";
import { type EntryKind, parseCapture } from "./capture-parser";
import { entryCapabilities, finitePriorityView, initialPriorityIds, isInsideMoneyCycle, moneyCycleRange, personalFinancePerspectives, postponeDate, taskBoardColumn, taskPriorityQuadrant, tripBudgetSummary, validateTaskPlan } from "./mindset-models";
import { validatePersistedState } from "./state-schema";

type Section = "today" | "tasks" | "lists" | "track" | "money" | "balance" | "settings";
type TrackerFamily = "Health" | "Habits" | "Learning & Media" | "Mindset";

type Entry = {
  id: string;
  title: string;
  kind: EntryKind;
  timestamp: string;
  amount?: number;
  minutes?: number;
  note?: string;
  source?: string;
  photo?: string;
  tripId?: string;
  listId?: string;
  endTimestamp?: string;
  completed?: boolean;
  status?: "planned" | "inProgress" | "completed";
};

type ListItem = {
  id: string;
  text: string;
  done: boolean;
  due?: string;
  plannedDate?: string;
  planMode?: "anytime" | "exact" | "window";
  startTime?: string;
  endTime?: string;
  durationMinutes?: number;
  important?: boolean;
  urgent?: boolean;
  boardColumnId?: string;
};

type TaskColumn = {
  id: string;
  name: string;
};

type LifeList = {
  id: string;
  name: string;
  shared: boolean;
  members: number;
  color: string;
  items: ListItem[];
};

type Tracker = {
  id: string;
  family: TrackerFamily;
  name: string;
  icon: string;
  target?: number;
};

type ChatMessage = {
  id: string;
  role: "assistant" | "user";
  text: string;
};

type MoneyEntry = {
  id: string;
  kind: "income" | "saving" | "investment";
  amount: number;
  date: string;
  note?: string;
};

type MoneyDraft = {
  kind: "expense" | MoneyEntry["kind"] | "asset" | "liability";
  amount: string;
  date: string;
  note: string;
  balanceCategory: BalanceSheetCategory;
  existingBalanceID?: string;
  tripId?: string;
};

type TripBudgetPlan = {
  id: string;
  name: string;
  destination: string;
  budget: number;
  startDate: string;
  endDate: string;
  createdAt: string;
};

type TripDraft = {
  id?: string;
  name: string;
  destination: string;
  budget: string;
  startDate: string;
  endDate: string;
  createdAt?: string;
};

type TaskEditorDraft = {
  listId: string;
  itemId: string;
  text: string;
  plannedDate: string;
  planMode: "anytime" | "exact" | "window";
  startTime: string;
  endTime: string;
  durationMinutes: string;
  important: boolean;
  urgent: boolean;
  boardColumnId: string;
};

type EditingMoneyRecord =
  | { source: "expense"; id: string }
  | { source: "money"; id: string }
  | { source: "balance"; id: string };

type BalanceSheetCategory =
  | "cash"
  | "investments"
  | "property"
  | "otherAsset"
  | "creditCard"
  | "loan"
  | "otherLiability";

type BalanceSheetItem = {
  id: string;
  name: string;
  balance: number;
  category: BalanceSheetCategory;
  updatedAt: string;
};

type PersistedState = {
  onboardingCompleted: boolean;
  entries: Entry[];
  lists: LifeList[];
  trackers: Tracker[];
  taskColumns: TaskColumn[];
  priorityDay: string;
  todayPriorityIds: string[];
  monthlyBudget: number;
  moneyCycleStartDay: number;
  savingsTarget: number;
  savingsCurrent: number;
  moneyEntries: MoneyEntry[];
  balanceSheetItems: BalanceSheetItem[];
  trips: TripBudgetPlan[];
};

const LEGACY_STORAGE_KEY = "sakhya-web-v1";
const MAX_BACKUP_BYTES = 2_000_000;
const ALLOWED_IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const EMPTY_MONEY_DRAFT: MoneyDraft = {
  kind: "expense",
  amount: "",
  date: new Date().toISOString().slice(0, 10),
  note: "",
  balanceCategory: "cash",
};

const EMPTY_TASK_DRAFT: TaskEditorDraft = {
  listId: "",
  itemId: "",
  text: "",
  plannedDate: localDateKey(),
  planMode: "anytime",
  startTime: "09:00",
  endTime: "10:00",
  durationMinutes: "60",
  important: false,
  urgent: false,
  boardColumnId: "todo",
};
const DEFAULT_TASK_COLUMNS: TaskColumn[] = [
  { id: "todo", name: "To do" },
  { id: "in-progress", name: "In progress" },
  { id: "done", name: "Done" },
];
const emptyState: PersistedState = {
  onboardingCompleted: false,
  entries: [],
  lists: [],
  trackers: [],
  taskColumns: DEFAULT_TASK_COLUMNS,
  priorityDay: "",
  todayPriorityIds: [],
  monthlyBudget: 0,
  moneyCycleStartDay: 1,
  savingsTarget: 0,
  savingsCurrent: 0,
  moneyEntries: [],
  balanceSheetItems: [],
  trips: [],
};
const currency = new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR" });
const longDate = new Intl.DateTimeFormat("en", {
  weekday: "long",
  day: "numeric",
  month: "long",
});
const timeOnly = new Intl.DateTimeFormat("en", { hour: "2-digit", minute: "2-digit" });

function atDayOffset(days: number, hour: number, minute = 0) {
  const date = new Date();
  date.setDate(date.getDate() + days);
  date.setHours(hour, minute, 0, 0);
  return date.toISOString();
}

function localDateKey(date = new Date()) {
  const offset = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 10);
}

function localTimeKey(date: Date) {
  return `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
}

function datetimeLocalValue(value: string) {
  const date = new Date(value);
  return new Date(date.getTime() - date.getTimezoneOffset() * 60_000).toISOString().slice(0, 16);
}

function dateKeyAtOffset(days: number) {
  const date = new Date();
  date.setDate(date.getDate() + days);
  return localDateKey(date);
}

function shiftTimestamp(value: string, days: number) {
  const date = new Date(value);
  date.setDate(date.getDate() + days);
  return date.toISOString();
}

function ordinalDay(day: number) {
  const remainder100 = day % 100;
  if (remainder100 >= 11 && remainder100 <= 13) return `${day}th`;
  if (day % 10 === 1) return `${day}st`;
  if (day % 10 === 2) return `${day}nd`;
  if (day % 10 === 3) return `${day}rd`;
  return `${day}th`;
}

function moneyCycleLabel(start: Date, end: Date) {
  const inclusiveEnd = new Date(end);
  inclusiveEnd.setDate(inclusiveEnd.getDate() - 1);
  const short = new Intl.DateTimeFormat("en", { day: "numeric", month: "short" });
  const startLabel = short.format(start);
  const endLabel = short.format(inclusiveEnd);
  return start.getFullYear() === inclusiveEnd.getFullYear()
    ? `${startLabel} – ${endLabel} ${inclusiveEnd.getFullYear()}`
    : `${startLabel} ${start.getFullYear()} – ${endLabel} ${inclusiveEnd.getFullYear()}`;
}

function taskTimeLabel(item: ListItem) {
  if (item.planMode === "exact" && item.startTime && item.endTime) return `${item.startTime}–${item.endTime}`;
  if (item.planMode === "window" && item.startTime && item.endTime) {
    return `${item.startTime}–${item.endTime}${item.durationMinutes ? ` · ${minutesLabel(item.durationMinutes)}` : ""}`;
  }
  return "Anytime";
}

function taskTimestamp(item: Pick<ListItem, "plannedDate" | "startTime">) {
  const date = item.plannedDate || localDateKey();
  const time = item.startTime || "12:00";
  const value = new Date(`${date}T${time}:00`);
  return Number.isFinite(value.getTime()) ? value.toISOString() : new Date().toISOString();
}

const seedState: PersistedState = {
  onboardingCompleted: true,
  entries: [
    { id: "e1", title: "Morning walk by the river", kind: "movement", timestamp: atDayOffset(0, 7, 35), minutes: 32, source: "WHOOP" },
    { id: "e2", title: "Deep work · product strategy", kind: "work", timestamp: atDayOffset(0, 9, 10), minutes: 95 },
    { id: "e3", title: "Coffee and groceries", kind: "expense", timestamp: atDayOffset(0, 11, 42), amount: 28.4 },
    { id: "e4", title: "Lunch · lentil bowl", kind: "food", timestamp: atDayOffset(0, 12, 35) },
    { id: "e5", title: "Read Atomic Habits", kind: "book", timestamp: atDayOffset(-1, 21, 5), minutes: 24 },
    { id: "e6", title: "Felt calm after an evening without screens", kind: "mindset", timestamp: atDayOffset(-1, 21, 40) },
    { id: "e7", title: "Dinner with friends", kind: "expense", timestamp: atDayOffset(-2, 19, 15), amount: 46.2, tripId: "trip1" },
    { id: "e8", title: "Strength training", kind: "movement", timestamp: atDayOffset(-2, 17, 50), minutes: 48, source: "WHOOP" },
    { id: "e9", title: "Slept well", kind: "sleep", timestamp: atDayOffset(-3, 7, 0), minutes: 448, source: "WHOOP" },
    { id: "e10", title: "Train to Heidelberg", kind: "expense", timestamp: atDayOffset(-4, 8, 5), amount: 59, tripId: "trip1" },
  ],
  lists: [
    {
      id: "l1",
      name: "Home groceries",
      shared: true,
      members: 2,
      color: "#e6955c",
      items: [
        { id: "li1", text: "Oat milk", done: false, urgent: true, boardColumnId: "todo" },
        { id: "li2", text: "Tomatoes", done: false, important: true, urgent: true, boardColumnId: "in-progress", plannedDate: dateKeyAtOffset(0), planMode: "window", startTime: "17:00", endTime: "19:00", durationMinutes: 20 },
        { id: "li3", text: "Coffee beans", done: true, boardColumnId: "done" },
        { id: "li4", text: "Dishwasher tablets", done: false, boardColumnId: "todo" },
      ],
    },
    {
      id: "l2",
      name: "Personal reminders",
      shared: false,
      members: 1,
      color: "#6f8f7b",
      items: [
        { id: "li5", text: "Book dentist appointment", done: false, important: true, urgent: true, boardColumnId: "todo", due: "Today", plannedDate: dateKeyAtOffset(0), planMode: "exact", startTime: "09:00", endTime: "09:30", durationMinutes: 30 },
        { id: "li6", text: "Return library book", done: false, important: true, boardColumnId: "todo", due: "Friday" },
      ],
    },
    {
      id: "l3",
      name: "Weekend trip",
      shared: true,
      members: 3,
      color: "#7b83a6",
      items: [
        { id: "li7", text: "Choose hiking route", done: true, boardColumnId: "done" },
        { id: "li8", text: "Reserve dinner", done: false, important: true, boardColumnId: "in-progress", plannedDate: dateKeyAtOffset(0), planMode: "window", startTime: "12:00", endTime: "16:00", durationMinutes: 15 },
      ],
    },
  ],
  trackers: [
    { id: "t1", family: "Health", name: "Movement", icon: "activity", target: 5 },
    { id: "t2", family: "Health", name: "Sleep", icon: "moon", target: 7 },
    { id: "t3", family: "Habits", name: "Evening reset", icon: "zap", target: 5 },
    { id: "t4", family: "Learning & Media", name: "Reading", icon: "book", target: 4 },
    { id: "t5", family: "Mindset", name: "Mood check-in", icon: "brain", target: 5 },
  ],
  taskColumns: DEFAULT_TASK_COLUMNS,
  priorityDay: localDateKey(),
  todayPriorityIds: ["li5", "li8", "li2"],
  monthlyBudget: 1200,
  moneyCycleStartDay: 25,
  savingsTarget: 3000,
  savingsCurrent: 1840,
  moneyEntries: [
    { id: "m1", kind: "income", amount: 2500, date: atDayOffset(-5, 9), note: "Monthly income" },
    { id: "m2", kind: "saving", amount: 300, date: atDayOffset(-4, 10), note: "Future freedom" },
    { id: "m3", kind: "investment", amount: 200, date: atDayOffset(-3, 10), note: "Monthly investment" },
  ],
  balanceSheetItems: [
    { id: "b1", name: "Main bank", balance: 7200, category: "cash", updatedAt: atDayOffset(0, 8) },
    { id: "b2", name: "Investment account", balance: 12400, category: "investments", updatedAt: atDayOffset(0, 8) },
    { id: "b3", name: "Credit card", balance: 450, category: "creditCard", updatedAt: atDayOffset(0, 8) },
  ],
  trips: [
    {
      id: "trip1",
      name: "Heidelberg weekend",
      destination: "Heidelberg, Germany",
      budget: 320,
      startDate: atDayOffset(-4, 0),
      endDate: atDayOffset(1, 0),
      createdAt: atDayOffset(-12, 10),
    },
  ],
};

function prioritiesForToday(state: PersistedState): PersistedState {
  const today = localDateKey();
  if (state.priorityDay === today) return state;
  return {
    ...state,
    priorityDay: today,
    todayPriorityIds: initialPriorityIds(state.lists),
  };
}

const navItems: { id: Section; label: string; icon: typeof Home }[] = [
  { id: "today", label: "Today", icon: Home },
  { id: "tasks", label: "Tasks", icon: Columns3 },
  { id: "lists", label: "Lists", icon: ListChecks },
  { id: "track", label: "Track", icon: Activity },
  { id: "money", label: "Money", icon: WalletCards },
  { id: "balance", label: "Balance", icon: BarChart3 },
  { id: "settings", label: "Settings", icon: Settings },
];

const kindMeta: Record<EntryKind, { label: string; color: string; icon: typeof Home }> = {
  work: { label: "Work", color: "#6f83a8", icon: Target },
  expense: { label: "Expense", color: "#d9864d", icon: CircleDollarSign },
  movement: { label: "Movement", color: "#5e9673", icon: Activity },
  food: { label: "Food", color: "#b27a73", icon: HeartPulse },
  sleep: { label: "Sleep", color: "#7c79a4", icon: Moon },
  mindset: { label: "Mindset", color: "#9b7295", icon: Brain },
  book: { label: "Reading", color: "#93734c", icon: BookOpen },
  movie: { label: "Watching", color: "#707e9a", icon: Film },
  list: { label: "List", color: "#668b91", icon: ListChecks },
  journal: { label: "Journal", color: "#9b7295", icon: BookOpen },
  note: { label: "Note", color: "#7a7f7b", icon: MoreHorizontal },
};

function uid() {
  return Math.random().toString(36).slice(2) + Date.now().toString(36);
}

function sameDay(iso: string, date: Date) {
  const value = new Date(iso);
  return (
    value.getFullYear() === date.getFullYear() &&
    value.getMonth() === date.getMonth() &&
    value.getDate() === date.getDate()
  );
}

function minutesLabel(minutes?: number) {
  if (!minutes) return "";
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  if (!hours) return `${rest} min`;
  return rest ? `${hours}h ${rest}m` : `${hours}h`;
}

function isAssetCategory(category: BalanceSheetCategory) {
  return ["cash", "investments", "property", "otherAsset"].includes(category);
}

function balanceCategoryLabel(category: BalanceSheetCategory) {
  const labels: Record<BalanceSheetCategory, string> = {
    cash: "Cash & bank",
    investments: "Investments",
    property: "Property & valuables",
    otherAsset: "Other asset",
    creditCard: "Credit card",
    loan: "Loan",
    otherLiability: "Other debt",
  };
  return labels[category];
}

function trackerIcon(name: string) {
  if (name === "moon") return Moon;
  if (name === "book") return BookOpen;
  if (name === "brain") return Brain;
  if (name === "zap") return Zap;
  return Activity;
}

interface SpeechRecognitionEventLike {
  results: { [index: number]: { [index: number]: { transcript: string } } };
}

interface SpeechRecognitionLike {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  onresult: ((event: SpeechRecognitionEventLike) => void) | null;
  onend: (() => void) | null;
  start(): void;
  stop(): void;
}

type SpeechRecognitionConstructor = new () => SpeechRecognitionLike;

const onboardingSteps = [
  {
    icon: Sparkles,
    eyebrow: "Your everyday assistant",
    title: "Capture life in one place",
    body: "Type or talk naturally from Today. Asitra turns each moment into the right timeline entry, list item, tracker or money record.",
    example: "Try: “Walked 30 minutes and spent €8 on lunch.”",
  },
  {
    icon: ListChecks,
    eyebrow: "Organized automatically",
    title: "One entry, useful everywhere",
    body: "Timeline remembers when it happened. Lists hold what is still open. Track shows progress. Money turns the same records into clear financial views.",
    example: "You do not need to enter the same information twice.",
  },
  {
    icon: Sparkles,
    eyebrow: "Contextual intelligence",
    title: "Ask Asitra about your life",
    body: "Use the floating Ask Asitra button for summaries and patterns based only on the information relevant to your question.",
    example: "AI analysis stays optional and asks for your permission.",
  },
  {
    icon: ShieldCheck,
    eyebrow: "Private by default",
    title: "This workspace belongs to you",
    body: "Your timeline, journal, trackers, money and private lists are stored separately for your signed-in account. Only a list you explicitly share can involve someone else.",
    example: "Export or delete your account data anytime in Settings.",
  },
];

export default function AsitraWebApp({ userName, logoutPath }: { userName: string; logoutPath: string }) {
  const [section, setSection] = useState<Section>("today");
  const [state, setState] = useState<PersistedState>(emptyState);
  const [hydrated, setHydrated] = useState(false);
  const [selectedDate, setSelectedDate] = useState(() => new Date());
  const [capture, setCapture] = useState("");
  const [capturePhoto, setCapturePhoto] = useState<string>();
  const [isListening, setIsListening] = useState(false);
  const [mobileMenu, setMobileMenu] = useState(false);
  const [assistantOpen, setAssistantOpen] = useState(false);
  const [editingEntry, setEditingEntry] = useState<Entry>();
  const [selectedListId, setSelectedListId] = useState("l1");
  const [newListItem, setNewListItem] = useState("");
  const [trackerFamily, setTrackerFamily] = useState<TrackerFamily>("Health");
  const [moneyView, setMoneyView] = useState<"budget" | "cashflow" | "allocation" | "networth">("budget");
  const [moneyCycleOffset, setMoneyCycleOffset] = useState(0);
  const [priorityChooserOpen, setPriorityChooserOpen] = useState(false);
  const [taskEditor, setTaskEditor] = useState<TaskEditorDraft>();
  const [taskView, setTaskView] = useState<"matrix" | "board">("matrix");
  const [taskDump, setTaskDump] = useState("");
  const [taskDumpImportant, setTaskDumpImportant] = useState(false);
  const [taskDumpUrgent, setTaskDumpUrgent] = useState(false);
  const [columnEditor, setColumnEditor] = useState<TaskColumn>();
  const [draggedTask, setDraggedTask] = useState<{ listId: string; itemId: string }>();
  const [dayClosed, setDayClosed] = useState(false);
  const [reflection, setReflection] = useState("");
  const [chatInput, setChatInput] = useState("");
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [assistantThinking, setAssistantThinking] = useState(false);
  const [moneyEntryOpen, setMoneyEntryOpen] = useState(false);
  const [editingMoneyRecord, setEditingMoneyRecord] = useState<EditingMoneyRecord>();
  const [moneyEntryMode, setMoneyEntryMode] = useState<"type" | "pdf" | "asitra">("asitra");
  const [moneyDraft, setMoneyDraft] = useState<MoneyDraft>(EMPTY_MONEY_DRAFT);
  const [tripDraft, setTripDraft] = useState<TripDraft>();
  const [moneyInstruction, setMoneyInstruction] = useState("");
  const [moneyReview, setMoneyReview] = useState<ParsedMoneyInstruction>();
  const [moneyClassifying, setMoneyClassifying] = useState(false);
  const [importedTransactions, setImportedTransactions] = useState<ImportedMoneyTransaction[]>([]);
  const [importFileName, setImportFileName] = useState("");
  const [importReading, setImportReading] = useState(false);
  const [notice, setNotice] = useState<string>();
  const [searchOpen, setSearchOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");
  const [policyOpen, setPolicyOpen] = useState(false);
  const [recoveryOpen, setRecoveryOpen] = useState(false);
  const [recoveryPoints, setRecoveryPoints] = useState<Array<{ id: string; version: number; createdAt: string }>>([]);
  const [deleteAccountOpen, setDeleteAccountOpen] = useState(false);
  const [deleteConfirmation, setDeleteConfirmation] = useState("");
  const [aiConsent, setAIConsent] = useState(false);
  const [aiContract, setAIContract] = useState<AsitraAIContract>(ASITRA_AI_CONTRACT);
  const [sharingOpen, setSharingOpen] = useState(false);
  const [inviteCode, setInviteCode] = useState("");
  const [joinCode, setJoinCode] = useState("");
  const [sharingOwner, setSharingOwner] = useState(false);
  const [onboardingOpen, setOnboardingOpen] = useState(false);
  const [onboardingStep, setOnboardingStep] = useState(0);
  const [accountMenuOpen, setAccountMenuOpen] = useState(false);
  const recognitionRef = useRef<SpeechRecognitionLike | null>(null);
  const saveQueueRef = useRef<Promise<void>>(Promise.resolve());
  const stateVersionRef = useRef(0);
  const accountDeletedRef = useRef(false);
  const sharedListMetaRef = useRef<Record<string, { version: number; owner: boolean }>>({});

  async function loadState() {
    try {
      const response = await fetch("/api/state", { cache: "no-store", credentials: "same-origin" });
      if (response.status === 204) {
        const legacy = window.localStorage.getItem(LEGACY_STORAGE_KEY);
        if (legacy) {
          const parsed = validatePersistedState(JSON.parse(legacy), {
            allowLegacyDataImages: true,
          }) as PersistedState;
          const migrated = await migrateLegacyPhotos(parsed);
          await saveState(migrated);
          setState(prioritiesForToday(migrated));
          const removeLegacyCopy = window.confirm(
            "Your browser data is now saved securely to your account. Remove the old plaintext browser copy? Choose Cancel to keep it.",
          );
          if (removeLegacyCopy) {
            window.localStorage.removeItem(LEGACY_STORAGE_KEY);
            setNotice("Your browser data was moved into secure account storage, and the old copy was removed.");
          } else {
            setNotice("Your secure account copy is ready. The old browser copy was kept as requested.");
          }
        } else {
          setState(prioritiesForToday(emptyState));
          setOnboardingOpen(true);
        }
        await loadSharedLists();
        setHydrated(true);
        return;
      }
      if (response.ok) {
        const payload = (await response.json()) as { state: unknown; version: number };
        stateVersionRef.current = payload.version;
        const savedState = validatePersistedState(payload.state) as PersistedState;
        setState(prioritiesForToday(savedState));
        setOnboardingOpen(!savedState.onboardingCompleted);
        await loadSharedLists();
        setHydrated(true);
        return;
      }
      throw new Error("Secure storage is unavailable.");
    } catch {
      setNotice("Secure storage could not be reached. No existing browser data was changed.");
      setHydrated(true);
    }
  }

  async function loadSharedLists() {
    const response = await fetch("/api/shared-lists", { cache: "no-store", credentials: "same-origin" });
    if (!response.ok) return;
    const payload = (await response.json()) as { lists?: Array<{ list: LifeList; version: number; owner: boolean }> };
    const shared = payload.lists ?? [];
    sharedListMetaRef.current = Object.fromEntries(shared.map((item) => [item.list.id, { version: item.version, owner: item.owner }]));
    setState((current) => ({
      ...current,
      lists: [
        ...current.lists.filter((list) => !shared.some((item) => item.list.id === list.id)),
        ...shared.map((item) => item.list),
      ],
    }));
  }

  async function saveState(nextState: PersistedState) {
    const validated = validatePersistedState(nextState);
    const response = await fetch("/api/state", {
      method: "PUT",
      credentials: "same-origin",
      headers: {
        "content-type": "application/json",
        "x-asitra-request": "1",
        "if-match": String(stateVersionRef.current),
      },
      body: JSON.stringify(validated),
    });
    const result = (await response.json()) as { version?: number; code?: string; error?: string };
    if (!response.ok) {
      if (result.code === "STATE_CONFLICT") {
        throw new Error("Your data changed on another device. Reload Asitra before editing again.");
      }
      throw new Error(result.error ?? "Secure storage rejected the update.");
    }
    if (typeof result.version === "number") stateVersionRef.current = result.version;
  }

  async function migrateLegacyPhotos(legacy: PersistedState): Promise<PersistedState> {
    const entries = await Promise.all(
      legacy.entries.map(async (entry) => {
        if (!entry.photo?.startsWith("data:")) return entry;
        const blob = await (await fetch(entry.photo)).blob();
        return { ...entry, photo: await uploadImage(blob) };
      }),
    );
    return { ...legacy, entries };
  }

  useEffect(() => {
    // The state update happens after the authenticated network request resolves.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void loadState();
    // Loading is intentionally limited to the initial authenticated mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    void fetch("/api/assistant/config", { cache: "no-store" })
      .then(async (response) => {
        if (response.ok) setAIContract((await response.json()) as AsitraAIContract);
      })
      .catch(() => undefined);
    void fetch("/api/account/consent", { cache: "no-store", credentials: "same-origin" })
      .then(async (response) => {
        if (!response.ok) return;
        const payload = (await response.json()) as { consents?: Array<{ purpose: string; granted: boolean }> };
        setAIConsent(payload.consents?.some((item) => item.purpose === "ai_analysis" && item.granted) ?? false);
      })
      .catch(() => undefined);
  }, []);

  async function updateAIConsent(granted: boolean) {
    const response = await fetch("/api/account/consent", {
      method: "PUT",
      credentials: "same-origin",
      headers: { "content-type": "application/json", "x-asitra-request": "1" },
      body: JSON.stringify({ purpose: "ai_analysis", granted }),
    });
    if (!response.ok) {
      setNotice("Your AI privacy choice could not be saved. It remains off.");
      setAIConsent(false);
      return;
    }
    setAIConsent(granted);
    setNotice(granted ? "AI analysis is enabled for this account." : "AI analysis is off. Asitra will use local insights only.");
  }

  async function logOut() {
    if (!logoutPath.startsWith("/api/auth/")) {
      window.location.assign(logoutPath);
      return;
    }
    const response = await fetch(logoutPath, {
      method: "POST",
      credentials: "same-origin",
      cache: "no-store",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({}),
    }).catch(() => null);
    if (!response?.ok) {
      setNotice("Log out could not be completed. Your session is still active.");
      return;
    }
    window.location.replace("/login");
  }

  useEffect(() => {
    if (!hydrated || accountDeletedRef.current) return;
    const timeout = window.setTimeout(() => {
      saveQueueRef.current = saveQueueRef.current
        .catch(() => undefined)
        .then(() => saveState(state));
      void saveQueueRef.current.catch(() => {
        setNotice("Your changes are kept on screen, but secure storage could not be reached.");
      });
    }, 350);
    return () => window.clearTimeout(timeout);
  }, [hydrated, state]);

  const dayEntries = useMemo(
    () =>
      state.entries
        .filter((entry) => sameDay(entry.timestamp, selectedDate))
        .sort((a, b) => b.timestamp.localeCompare(a.timestamp)),
    [selectedDate, state.entries],
  );
  const weekStart = useMemo(() => {
    const date = new Date();
    date.setDate(date.getDate() - 6);
    date.setHours(0, 0, 0, 0);
    return date;
  }, []);
  const weekEntries = useMemo(
    () => state.entries.filter((entry) => new Date(entry.timestamp) >= weekStart),
    [state.entries, weekStart],
  );
  const activeMoneyCycle = useMemo(
    () => moneyCycleRange(new Date(), state.moneyCycleStartDay, moneyCycleOffset),
    [moneyCycleOffset, state.moneyCycleStartDay],
  );
  const activeMoneyCycleLabel = moneyCycleLabel(activeMoneyCycle.start, activeMoneyCycle.end);
  const monthEntries = useMemo(
    () => state.entries.filter((entry) => isInsideMoneyCycle(entry.timestamp, activeMoneyCycle)),
    [activeMoneyCycle, state.entries],
  );
  const monthSpent = monthEntries.reduce((sum, entry) => sum + (entry.amount ?? 0), 0);
  const monthMoneyEntries = useMemo(
    () => state.moneyEntries.filter((entry) => isInsideMoneyCycle(entry.date, activeMoneyCycle)),
    [activeMoneyCycle, state.moneyEntries],
  );
  const monthIncome = monthMoneyEntries
    .filter((entry) => entry.kind === "income")
    .reduce((sum, entry) => sum + entry.amount, 0);
  const monthSaved = monthMoneyEntries
    .filter((entry) => entry.kind === "saving")
    .reduce((sum, entry) => sum + entry.amount, 0);
  const monthInvested = monthMoneyEntries
    .filter((entry) => entry.kind === "investment")
    .reduce((sum, entry) => sum + entry.amount, 0);
  const assets = state.balanceSheetItems.filter((item) => isAssetCategory(item.category));
  const liabilities = state.balanceSheetItems.filter((item) => !isAssetCategory(item.category));
  const totalAssets = assets.reduce((sum, item) => sum + item.balance, 0);
  const totalLiabilities = liabilities.reduce((sum, item) => sum + item.balance, 0);
  const financeViews = personalFinancePerspectives({
    monthlyBudget: state.monthlyBudget,
    income: monthIncome,
    spent: monthSpent,
    saved: monthSaved,
    invested: monthInvested,
    assets: totalAssets,
    liabilities: totalLiabilities,
  });
  const netWorth = financeViews.netWorth;
  const moneyActivities = [
    ...state.entries
      .filter((entry) => entry.kind === "expense" && typeof entry.amount === "number")
      .map((entry) => ({ id: entry.id, title: entry.title, kind: "Expense", amount: entry.amount ?? 0, date: entry.timestamp, record: { source: "expense", id: entry.id } as EditingMoneyRecord })),
    ...state.moneyEntries.map((entry) => ({ id: entry.id, title: entry.note || entry.kind, kind: entry.kind[0].toUpperCase() + entry.kind.slice(1), amount: entry.amount, date: entry.date, record: { source: "money", id: entry.id } as EditingMoneyRecord })),
    ...state.balanceSheetItems.map((item) => ({ id: item.id, title: item.name, kind: balanceCategoryLabel(item.category), amount: item.balance, date: item.updatedAt, record: { source: "balance", id: item.id } as EditingMoneyRecord })),
  ].sort((first, second) => second.date.localeCompare(first.date));
  const weekActivity = weekEntries
    .filter((entry) => entry.kind === "movement")
    .reduce((sum, entry) => sum + (entry.minutes ?? 0), 0);
  const weekWork = weekEntries
    .filter((entry) => entry.kind === "work")
    .reduce((sum, entry) => sum + (entry.minutes ?? 0), 0);
  const weekPersonal = weekEntries
    .filter((entry) => ["movement", "mindset", "book", "movie", "journal"].includes(entry.kind))
    .reduce((sum, entry) => sum + (entry.minutes ?? 0), 0);
  const openItems = state.lists.reduce(
    (sum, list) => sum + list.items.filter((item) => !item.done).length,
    0,
  );
  const { chosen: todayCommitments, later: laterCommitments } = finitePriorityView(
    state.lists,
    state.todayPriorityIds,
  );
  const userFirstName = userName
    .replace(/@.*$/, "")
    .split(/[\s._-]+/)
    .filter(Boolean)[0]
    ?.replace(/^./, (letter) => letter.toUpperCase()) || "there";
  const accountInitials = userName
    .replace(/@.*$/, "")
    .split(/[\s._-]+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("") || "S";
  const balanceScore = Math.max(
    32,
    Math.min(96, 70 + Math.round((weekPersonal - weekWork * 0.45) / 18)),
  );
  const selectedList = state.lists.find((list) => list.id === selectedListId) ?? state.lists[0];
  const taskColumns = state.taskColumns.length ? state.taskColumns : DEFAULT_TASK_COLUMNS;
  const allTasks = state.lists.flatMap((list) => list.items.map((item) => ({
    item,
    listId: list.id,
    listName: list.name,
    listColor: list.color,
  })));
  const openTasks = allTasks.filter(({ item }) => !item.done);
  const suggested = capture.trim() ? parseCapture(capture) : undefined;
  const editingCapabilities = editingEntry ? entryCapabilities(editingEntry.kind) : undefined;
  const todayInsight =
    dayEntries.length === 0
      ? "Start with one honest entry. The rest of your day will organize itself."
      : weekWork > weekPersonal * 1.8
        ? "Your week is leaning toward work. Protect one personal block this evening."
        : "Your week has a healthy rhythm. Keep the next action small and clear.";
  const normalizedSearch = searchQuery.trim().toLowerCase();
  const searchResults = normalizedSearch
    ? [
        ...state.entries
          .filter((entry) => `${entry.title} ${entry.note ?? ""}`.toLowerCase().includes(normalizedSearch))
          .slice(0, 12)
          .map((entry) => ({ id: entry.id, label: entry.title, detail: `${kindMeta[entry.kind].label} · ${longDate.format(new Date(entry.timestamp))}`, section: "today" as Section, date: entry.timestamp })),
        ...state.lists
          .flatMap((list) => list.items.map((item) => ({ list, item })))
          .filter(({ list, item }) => `${list.name} ${item.text}`.toLowerCase().includes(normalizedSearch))
          .slice(0, 12)
          .map(({ list, item }) => ({ id: item.id, label: item.text, detail: list.name, section: "lists" as Section, listId: list.id })),
      ].slice(0, 16)
    : [];

  if (!hydrated) {
    return (
      <div className="app-frame">
        <main>
          <div className="page-shell">
            <section className="hero">
              <span className="eyebrow">Asitra</span>
              <h1>Preparing your day…</h1>
              <p>Loading your private account workspace.</p>
            </section>
          </div>
        </main>
      </div>
    );
  }

  function addCapture(event?: FormEvent) {
    event?.preventDefault();
    if (!capture.trim()) return;
    const parsed = parseCapture(capture);
    const { list: listIntent, ...entryData } = parsed;
    const entry: Entry = {
      id: uid(),
      ...entryData,
      photo: capturePhoto,
    };
    const targetList = listIntent
      ? state.lists.find((list) => {
          const name = list.name.toLowerCase();
          if (listIntent.target === "groceries") return /grocer|shopping/.test(name);
          if (listIntent.target === "travel") return /travel|trip/.test(name);
          return name === "personal reminders" || /reminder/.test(name);
        })
      : undefined;
    const createdList: LifeList | undefined = listIntent && !targetList
      ? {
          id: uid(),
          name: listIntent.target === "groceries" ? "Shopping" : listIntent.target === "travel" ? "Travel ideas" : "Personal reminders",
          shared: false,
          members: 1,
          color: listIntent.target === "travel" ? "#7b83a6" : "#6f8f7b",
          items: [],
        }
      : undefined;
    const destination = targetList ?? createdList;
    const updatedDestination = destination && listIntent
      ? {
          ...destination,
          items: [{
            id: entry.id,
            text: listIntent.text,
            done: false,
            due: listIntent.due,
            plannedDate: listIntent.due ? localDateKey(new Date(entry.timestamp)) : undefined,
            planMode: "anytime" as const,
            important: /\bimportant\b/i.test(capture) && !/\bnot important\b/i.test(capture),
            urgent: /\burgent\b/i.test(capture) && !/\bnot urgent\b/i.test(capture),
            boardColumnId: "todo",
          }, ...destination.items],
        }
      : undefined;
    const canonicalEntry: Entry = updatedDestination
      ? { ...entry, listId: updatedDestination.id, completed: false }
      : entry;
    setState((current) => {
      if (!updatedDestination) return { ...current, entries: [canonicalEntry, ...current.entries] };
      const exists = current.lists.some((list) => list.id === updatedDestination.id);
      return {
        ...current,
        entries: [canonicalEntry, ...current.entries],
        lists: exists
          ? current.lists.map((list) => list.id === updatedDestination.id ? updatedDestination : list)
          : [...current.lists, updatedDestination],
      };
    });
    if (updatedDestination?.shared) void updateSharedList(updatedDestination);
    setCapture("");
    setCapturePhoto(undefined);
    setSelectedDate(new Date(entry.timestamp));
    setNotice(
      listIntent && updatedDestination
        ? `Added to your timeline and ${updatedDestination.name}.`
        : `Added to your timeline as ${kindMeta[parsed.kind].label}.`,
    );
  }

  function toggleListening(target: "capture" | "chat") {
    if (isListening) {
      recognitionRef.current?.stop();
      setIsListening(false);
      return;
    }
    const SpeechRecognition =
      (window as Window & { SpeechRecognition?: SpeechRecognitionConstructor }).SpeechRecognition ??
      (window as Window & { webkitSpeechRecognition?: SpeechRecognitionConstructor })
        .webkitSpeechRecognition;
    if (!SpeechRecognition) {
      setNotice("Voice dictation is not supported by this browser. You can still type naturally.");
      return;
    }
    const recognition = new SpeechRecognition();
    recognition.continuous = false;
    recognition.interimResults = true;
    recognition.lang = navigator.language || "en-US";
    recognition.onresult = (event) => {
      const transcript = event.results[0][0].transcript;
      if (target === "capture") setCapture(transcript);
      else setChatInput(transcript);
    };
    recognition.onend = () => setIsListening(false);
    recognitionRef.current = recognition;
    setIsListening(true);
    recognition.start();
  }

  async function attachPhoto(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    event.target.value = "";
    if (file.size > 1_500_000 || !ALLOWED_IMAGE_TYPES.has(file.type)) {
      setNotice("Choose a JPEG, PNG, or WebP image under 1.5 MB.");
      return;
    }
    try {
      setCapturePhoto(await uploadImage(file));
    } catch {
      setNotice("The image could not be validated and stored securely.");
    }
  }

  async function uploadImage(file: Blob): Promise<string> {
    const response = await fetch("/api/attachments", {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "content-type": file.type,
        "x-asitra-request": "1",
      },
      body: file,
    });
    if (!response.ok) throw new Error("Upload failed.");
    const result = (await response.json()) as { url?: string };
    if (!result.url || !/^\/api\/attachments\/[0-9a-f-]{36}$/i.test(result.url)) {
      throw new Error("Upload returned an invalid attachment.");
    }
    return result.url;
  }

  function changeDay(direction: number) {
    const next = new Date(selectedDate);
    next.setDate(next.getDate() + direction);
    setSelectedDate(next);
  }

  function toggleListItem(listId: string, itemId: string) {
    const list = state.lists.find((candidate) => candidate.id === listId);
    if (!list) return;
    const willBeDone = !list.items.find((item) => item.id === itemId)?.done;
    const updated = {
      ...list,
      items: list.items.map((item) => item.id === itemId
        ? { ...item, done: !item.done, boardColumnId: !item.done ? "done" : "todo" }
        : item),
    };
    setState((current) => ({
      ...current,
      lists: current.lists.map((item) => item.id === listId ? updated : item),
      entries: current.entries.map((entry) => entry.id === itemId ? { ...entry, completed: willBeDone } : entry),
      todayPriorityIds: willBeDone ? current.todayPriorityIds.filter((id) => id !== itemId) : current.todayPriorityIds,
    }));
    if (updated.shared) void updateSharedList(updated);
  }

  function movePriorityToLater(itemId: string) {
    setState((current) => ({
      ...current,
      todayPriorityIds: current.todayPriorityIds.filter((id) => id !== itemId),
    }));
  }

  function bringPriorityIntoToday(itemId: string) {
    if (state.todayPriorityIds.length >= 3) {
      setNotice("Choose one thing to move to Later before bringing in something new.");
      return;
    }
    setState((current) => ({
      ...current,
      todayPriorityIds: [...current.todayPriorityIds.filter((id) => id !== itemId), itemId].slice(0, 3),
      lists: current.lists.map((list) => ({
        ...list,
        items: list.items.map((item) => item.id === itemId
          ? { ...item, plannedDate: localDateKey(), due: "Today", planMode: item.planMode ?? "anytime" }
          : item),
      })),
      entries: current.entries.map((entry) => entry.id === itemId
        ? { ...entry, timestamp: taskTimestamp({ plannedDate: localDateKey(), startTime: entry.timestamp ? localTimeKey(new Date(entry.timestamp)) : undefined }), completed: false }
        : entry),
    }));
  }

  function openTaskEditor(listId: string, item: ListItem) {
    setTaskEditor({
      ...EMPTY_TASK_DRAFT,
      listId,
      itemId: item.id,
      text: item.text,
      plannedDate: item.plannedDate ?? localDateKey(),
      planMode: item.planMode ?? "anytime",
      startTime: item.startTime ?? "09:00",
      endTime: item.endTime ?? "10:00",
      durationMinutes: item.durationMinutes ? String(item.durationMinutes) : "60",
      important: Boolean(item.important),
      urgent: Boolean(item.urgent),
      boardColumnId: item.done ? "done" : item.boardColumnId ?? "todo",
    });
  }

  function saveTaskEditor(event: FormEvent) {
    event.preventDefault();
    if (!taskEditor?.text.trim()) return;
    const duration = Number(taskEditor.durationMinutes);
    const validation = validateTaskPlan({
      mode: taskEditor.planMode,
      startTime: taskEditor.startTime,
      endTime: taskEditor.endTime,
      durationMinutes: Number.isFinite(duration) ? duration : undefined,
    });
    if (!validation.valid) {
      setNotice(validation.message);
      return;
    }
    const nextItem: ListItem = {
      id: taskEditor.itemId,
      text: taskEditor.text.trim(),
      done: taskEditor.boardColumnId === "done",
      due: taskEditor.plannedDate === localDateKey() ? "Today" : taskEditor.plannedDate === dateKeyAtOffset(1) ? "Tomorrow" : taskEditor.plannedDate,
      plannedDate: taskEditor.plannedDate,
      planMode: taskEditor.planMode,
      startTime: taskEditor.planMode === "anytime" ? undefined : taskEditor.startTime,
      endTime: taskEditor.planMode === "anytime" ? undefined : taskEditor.endTime,
      durationMinutes: taskEditor.planMode === "window" ? duration : taskEditor.planMode === "exact"
        ? Math.max(1, Math.round((new Date(`2000-01-01T${taskEditor.endTime}:00`).getTime() - new Date(`2000-01-01T${taskEditor.startTime}:00`).getTime()) / 60_000))
        : undefined,
      important: taskEditor.important,
      urgent: taskEditor.urgent,
      boardColumnId: taskEditor.boardColumnId,
    };
    const sourceList = state.lists.find((list) => list.id === taskEditor.listId);
    const updatedSharedList = sourceList
      ? { ...sourceList, items: sourceList.items.map((item) => item.id === nextItem.id ? { ...item, ...nextItem } : item) }
      : undefined;
    setState((current) => ({
      ...current,
      lists: current.lists.map((list) => list.id === taskEditor.listId && updatedSharedList ? updatedSharedList : list),
      entries: current.entries.map((entry) => entry.id === nextItem.id
        ? {
            ...entry,
            title: nextItem.text,
            timestamp: taskTimestamp(nextItem),
            endTimestamp: nextItem.planMode === "anytime" || !nextItem.endTime ? undefined : new Date(`${nextItem.plannedDate}T${nextItem.endTime}:00`).toISOString(),
            minutes: nextItem.durationMinutes,
            completed: sourceList?.items.find((item) => item.id === nextItem.id)?.done ?? false,
            listId: taskEditor.listId,
          }
        : entry),
      todayPriorityIds: nextItem.plannedDate === localDateKey() && !nextItem.done
        ? current.todayPriorityIds
        : current.todayPriorityIds.filter((id) => id !== nextItem.id),
    }));
    if (updatedSharedList?.shared) void updateSharedList(updatedSharedList);
    setTaskEditor(undefined);
    setNotice("Task updated everywhere it appears.");
  }

  function addTaskDump(event: FormEvent) {
    event.preventDefault();
    const text = taskDump.trim();
    if (!text) return;
    const itemId = uid();
    const destination = state.lists.find((list) => /task|reminder/i.test(list.name)) ?? state.lists[0];
    const createdList: LifeList | undefined = destination ? undefined : {
      id: uid(),
      name: "Tasks",
      shared: false,
      members: 1,
      color: "#6f8f7b",
      items: [],
    };
    const target = destination ?? createdList!;
    const nextItem: ListItem = {
      id: itemId,
      text,
      done: false,
      important: taskDumpImportant,
      urgent: taskDumpUrgent,
      boardColumnId: "todo",
      planMode: "anytime",
    };
    const updated = { ...target, items: [nextItem, ...target.items] };
    setState((current) => ({
      ...current,
      entries: [{ id: itemId, title: text, kind: "list", timestamp: new Date().toISOString() }, ...current.entries],
      lists: current.lists.some((list) => list.id === updated.id)
        ? current.lists.map((list) => list.id === updated.id ? updated : list)
        : [...current.lists, updated],
    }));
    if (updated.shared) void updateSharedList(updated);
    setTaskDump("");
    setTaskDumpImportant(false);
    setTaskDumpUrgent(false);
    setNotice("Task added to your inbox, matrix and board.");
  }

  function moveTaskToColumn(listId: string, itemId: string, boardColumnId: string) {
    if (!taskColumns.some((column) => column.id === boardColumnId)) return;
    const list = state.lists.find((candidate) => candidate.id === listId);
    if (!list) return;
    const done = boardColumnId === "done";
    const updated = {
      ...list,
      items: list.items.map((item) => item.id === itemId ? { ...item, boardColumnId, done } : item),
    };
    setState((current) => ({
      ...current,
      lists: current.lists.map((candidate) => candidate.id === listId ? updated : candidate),
      todayPriorityIds: done ? current.todayPriorityIds.filter((id) => id !== itemId) : current.todayPriorityIds,
    }));
    if (updated.shared) void updateSharedList(updated);
  }

  function setTaskPriority(listId: string, itemId: string, priority: "important" | "urgent") {
    const list = state.lists.find((candidate) => candidate.id === listId);
    if (!list) return;
    const updated = {
      ...list,
      items: list.items.map((item) => item.id === itemId
        ? { ...item, [priority]: !item[priority] }
        : item),
    };
    setState((current) => ({
      ...current,
      lists: current.lists.map((candidate) => candidate.id === listId ? updated : candidate),
    }));
    if (updated.shared) void updateSharedList(updated);
  }

  function saveTaskColumn(event: FormEvent) {
    event.preventDefault();
    if (!columnEditor?.name.trim()) return;
    const name = columnEditor.name.trim();
    setState((current) => ({
      ...current,
      taskColumns: columnEditor.id
        ? current.taskColumns.map((column) => column.id === columnEditor.id ? { ...column, name } : column)
        : [...current.taskColumns, { id: uid(), name }],
    }));
    setColumnEditor(undefined);
    setNotice(columnEditor.id ? "Column renamed." : "Column added to your task board.");
  }

  function deleteTask(listId: string, itemId: string) {
    if (!window.confirm("Delete this task from Today, its list, and the timeline?")) return;
    const list = state.lists.find((candidate) => candidate.id === listId);
    const updated = list ? { ...list, items: list.items.filter((item) => item.id !== itemId) } : undefined;
    setState((current) => ({
      ...current,
      lists: current.lists.map((candidate) => candidate.id === listId && updated ? updated : candidate),
      entries: current.entries.filter((entry) => entry.id !== itemId),
      todayPriorityIds: current.todayPriorityIds.filter((id) => id !== itemId),
    }));
    if (updated?.shared) void updateSharedList(updated);
    setTaskEditor(undefined);
    setNotice("Task deleted.");
  }

  function postponeTask(listId: string, item: ListItem, days = 1) {
    const plannedDate = postponeDate(item.plannedDate ?? localDateKey(), days);
    const nextItem = { ...item, plannedDate, due: days === 1 ? "Tomorrow" : plannedDate };
    const list = state.lists.find((candidate) => candidate.id === listId);
    const updated = list ? { ...list, items: list.items.map((candidate) => candidate.id === item.id ? nextItem : candidate) } : undefined;
    setState((current) => ({
      ...current,
      lists: current.lists.map((candidate) => candidate.id === listId && updated ? updated : candidate),
      entries: current.entries.map((entry) => entry.id === item.id
        ? { ...entry, timestamp: taskTimestamp(nextItem), endTimestamp: entry.endTimestamp ? shiftTimestamp(entry.endTimestamp, days) : undefined }
        : entry),
      todayPriorityIds: current.todayPriorityIds.filter((id) => id !== item.id),
    }));
    if (updated?.shared) void updateSharedList(updated);
    setNotice(`Moved “${item.text}” to ${days === 1 ? "tomorrow" : plannedDate}.`);
  }

  function saveReflection(event: FormEvent) {
    event.preventDefault();
    const note = reflection.trim();
    if (!note) return;
    setState((current) => ({
      ...current,
      entries: [
        {
          id: uid(),
          title: note,
          kind: "journal",
          timestamp: new Date().toISOString(),
          source: "Daily reflection",
        },
        ...current.entries,
      ],
    }));
    setReflection("");
    setNotice("Reflection saved to your timeline and Notes.");
  }

  function addListItem(event: FormEvent) {
    event.preventDefault();
    if (!newListItem.trim() || !selectedList) return;
    const itemId = uid();
    const entry: Entry = {
      id: itemId,
      title: newListItem.trim(),
      kind: "list",
      timestamp: new Date().toISOString(),
      listId: selectedList.id,
      completed: false,
    };
    const updated = {
      ...selectedList,
      items: [{ id: itemId, text: newListItem.trim(), done: false, important: false, urgent: false, boardColumnId: "todo" }, ...selectedList.items],
    };
    setState((current) => ({ ...current, entries: [entry, ...current.entries], lists: current.lists.map((list) => list.id === selectedList.id ? updated : list) }));
    if (updated.shared) void updateSharedList(updated);
    setNewListItem("");
  }

  function addNewList() {
    const name = window.prompt("Name your list");
    if (!name?.trim()) return;
    const list: LifeList = {
      id: uid(),
      name: name.trim(),
      shared: false,
      members: 1,
      color: "#6f8f7b",
      items: [],
    };
    setState((current) => ({ ...current, lists: [...current.lists, list] }));
    setSelectedListId(list.id);
  }

  async function toggleListSharing() {
    if (!selectedList) return;
    const existingMeta = sharedListMetaRef.current[selectedList.id];
    if (selectedList.shared && existingMeta && !existingMeta.owner) {
      setInviteCode("MEMBER");
      setSharingOwner(false);
      setSharingOpen(true);
      return;
    }
    const action = selectedList.shared ? "invite" : "share";
    const response = await fetch("/api/shared-lists", {
      method: "POST",
      credentials: "same-origin",
      headers: { "content-type": "application/json", "x-asitra-request": "1" },
      body: JSON.stringify({ action, list: { ...selectedList, shared: true } }),
    });
    const result = (await response.json()) as { list?: LifeList; version?: number; owner?: boolean; inviteCode?: string; error?: string };
    if (!response.ok || !result.list || typeof result.version !== "number") {
      setNotice(result.error ?? "Sharing could not be enabled.");
      return;
    }
    sharedListMetaRef.current[result.list.id] = { version: result.version, owner: Boolean(result.owner) };
    setState((current) => ({ ...current, lists: current.lists.map((list) => list.id === result.list!.id ? result.list! : list) }));
    setInviteCode(result.inviteCode ?? "");
    setSharingOwner(Boolean(result.owner));
    setSharingOpen(true);
  }

  async function updateSharedList(list: LifeList) {
    const meta = sharedListMetaRef.current[list.id];
    if (!meta) return;
    const response = await fetch("/api/shared-lists", {
      method: "POST",
      credentials: "same-origin",
      headers: { "content-type": "application/json", "x-asitra-request": "1" },
      body: JSON.stringify({ action: "update", list, version: meta.version }),
    });
    const result = (await response.json()) as { list?: LifeList; version?: number; owner?: boolean; code?: string; error?: string };
    if (!response.ok || !result.list || typeof result.version !== "number") {
      setNotice(result.code === "LIST_CONFLICT" ? "This shared list changed elsewhere. Reload before editing it again." : result.error ?? "The shared list could not sync.");
      return;
    }
    sharedListMetaRef.current[list.id] = { version: result.version, owner: Boolean(result.owner) };
    setState((current) => ({ ...current, lists: current.lists.map((item) => item.id === list.id ? result.list! : item) }));
  }

  async function joinSharedList() {
    const response = await fetch("/api/shared-lists", {
      method: "POST",
      credentials: "same-origin",
      headers: { "content-type": "application/json", "x-asitra-request": "1" },
      body: JSON.stringify({ action: "join", code: joinCode }),
    });
    const result = (await response.json()) as { list?: LifeList; version?: number; owner?: boolean; error?: string };
    if (!response.ok || !result.list || typeof result.version !== "number") {
      setNotice(result.error ?? "The invite could not be joined.");
      return;
    }
    sharedListMetaRef.current[result.list.id] = { version: result.version, owner: Boolean(result.owner) };
    setState((current) => ({ ...current, lists: [...current.lists.filter((list) => list.id !== result.list!.id), result.list!] }));
    setSelectedListId(result.list.id);
    setJoinCode("");
    setSharingOpen(false);
    setNotice(`Joined “${result.list.name}”.`);
  }

  async function stopSharing() {
    if (!selectedList) return;
    const owner = sharedListMetaRef.current[selectedList.id]?.owner;
    if (!window.confirm(owner ? "Stop sharing this list? Other members will lose access." : "Leave this shared list?")) return;
    const response = await fetch(`/api/shared-lists?id=${encodeURIComponent(selectedList.id)}`, {
      method: "DELETE",
      credentials: "same-origin",
      headers: { "x-asitra-request": "1" },
    });
    if (!response.ok) { setNotice("Sharing could not be stopped."); return; }
    delete sharedListMetaRef.current[selectedList.id];
    setState((current) => ({
      ...current,
      lists: owner
        ? current.lists.map((list) => list.id === selectedList.id ? { ...list, shared: false, members: 1 } : list)
        : current.lists.filter((list) => list.id !== selectedList.id),
    }));
    setSharingOpen(false);
    setNotice(owner ? "The list is private again." : "You left the shared list.");
  }

  function addTracker() {
    const name = window.prompt(`What would you like to track in ${trackerFamily}?`);
    if (!name?.trim()) return;
    setState((current) => ({
      ...current,
      trackers: [
        ...current.trackers,
        { id: uid(), family: trackerFamily, name: name.trim(), icon: "activity", target: 5 },
      ],
    }));
  }

  function trackerCount(tracker: Tracker) {
    if (tracker.name.toLowerCase().includes("movement"))
      return weekEntries.filter((entry) => entry.kind === "movement").length;
    if (tracker.name.toLowerCase().includes("sleep"))
      return weekEntries.filter((entry) => entry.kind === "sleep").length;
    if (tracker.family === "Learning & Media")
      return weekEntries.filter((entry) => ["book", "movie"].includes(entry.kind)).length;
    if (tracker.family === "Mindset")
      return weekEntries.filter((entry) => ["mindset", "journal"].includes(entry.kind)).length;
    return weekEntries.filter((entry) => entry.kind === "note").length;
  }

  function checkIn(tracker: Tracker) {
    const kind: EntryKind =
      tracker.family === "Health"
        ? tracker.name.toLowerCase().includes("sleep")
          ? "sleep"
          : "movement"
        : tracker.family === "Learning & Media"
          ? "book"
          : tracker.family === "Mindset"
            ? "mindset"
            : "note";
    setState((current) => ({
      ...current,
      entries: [
        {
          id: uid(),
          title: tracker.name,
          kind,
          timestamp: new Date().toISOString(),
          minutes: kind === "movement" ? 30 : undefined,
        },
        ...current.entries,
      ],
    }));
    setNotice(`${tracker.name} check-in added to the timeline.`);
  }

  function openMoneyEntry(kind: MoneyDraft["kind"] = "expense", mode: typeof moneyEntryMode = "asitra", tripId?: string) {
    setEditingMoneyRecord(undefined);
    setMoneyDraft({ ...EMPTY_MONEY_DRAFT, kind, balanceCategory: kind === "liability" ? "creditCard" : "cash", date: localDateKey(), tripId: kind === "expense" ? tripId : undefined });
    setMoneyEntryMode(mode);
    setMoneyInstruction("");
    setMoneyReview(undefined);
    setImportedTransactions([]);
    setImportFileName("");
    setMoneyEntryOpen(true);
  }

  function storeMoneyRecord(kind: MoneyDraft["kind"], amount: number, date: string, note: string, balanceCategory?: BalanceSheetCategory, existingBalanceID?: string, tripId?: string) {
    if (kind === "asset" || kind === "liability") {
      const category = balanceCategory ?? (kind === "asset" ? "cash" : "otherLiability");
      const next: BalanceSheetItem = {
        id: existingBalanceID ?? uid(),
        name: note || (kind === "asset" ? "Asset" : "Debt"),
        balance: amount,
        category,
        updatedAt: date,
      };
      setState((current) => ({
        ...current,
        balanceSheetItems: existingBalanceID
          ? current.balanceSheetItems.map((item) => item.id === existingBalanceID ? next : item)
          : [...current.balanceSheetItems, next],
      }));
      return;
    }
    setState((current) => ({
      ...current,
      entries:
        kind === "expense"
          ? [
              {
                id: uid(),
                title: note || "Expense",
                kind: "expense",
                amount,
                timestamp: date,
                source: "Money",
                tripId,
              },
              ...current.entries,
            ]
          : current.entries,
      savingsCurrent: kind === "saving" ? current.savingsCurrent + amount : current.savingsCurrent,
      moneyEntries:
        kind === "expense"
          ? current.moneyEntries
          : [...current.moneyEntries, { id: uid(), kind, amount, date, note: note || undefined }],
    }));
  }

  function submitMoneyDraft(event: FormEvent) {
    event.preventDefault();
    const amount = Number(moneyDraft.amount.replace(",", "."));
    if (!Number.isFinite(amount) || amount <= 0) {
      setNotice("Enter an amount greater than zero.");
      return;
    }
    const date = new Date(`${moneyDraft.date}T12:00:00`);
    if (!Number.isFinite(date.getTime())) {
      setNotice("Choose a valid date.");
      return;
    }
    if (!editingMoneyRecord) {
      storeMoneyRecord(moneyDraft.kind, amount, date.toISOString(), moneyDraft.note.trim(), moneyDraft.balanceCategory, moneyDraft.existingBalanceID, moneyDraft.tripId);
    } else {
      const record = editingMoneyRecord;
      setState((current) => {
        const previousMoney = record.source === "money" ? current.moneyEntries.find((item) => item.id === record.id) : undefined;
        const previousSaving = previousMoney?.kind === "saving" ? previousMoney.amount : 0;
        const nextSaving = moneyDraft.kind === "saving" ? amount : 0;
        const entries = current.entries.filter((entry) => !(record.source === "expense" && entry.id === record.id));
        const moneyEntries = current.moneyEntries.filter((entry) => !(record.source === "money" && entry.id === record.id));
        const balanceSheetItems = current.balanceSheetItems.filter((item) => !(record.source === "balance" && item.id === record.id));
        if (moneyDraft.kind === "expense") {
          entries.unshift({ id: record.id, title: moneyDraft.note.trim() || "Expense", kind: "expense", amount, timestamp: date.toISOString(), source: "Money", tripId: moneyDraft.tripId });
        } else if (moneyDraft.kind === "asset" || moneyDraft.kind === "liability") {
          balanceSheetItems.push({ id: record.id, name: moneyDraft.note.trim() || (moneyDraft.kind === "asset" ? "Asset" : "Debt"), balance: amount, category: moneyDraft.balanceCategory, updatedAt: date.toISOString() });
        } else {
          moneyEntries.push({ id: record.id, kind: moneyDraft.kind, amount, date: date.toISOString(), note: moneyDraft.note.trim() || undefined });
        }
        return {
          ...current,
          entries,
          moneyEntries,
          balanceSheetItems,
          savingsCurrent: Math.max(0, current.savingsCurrent - previousSaving + nextSaving),
        };
      });
    }
    setMoneyEntryOpen(false);
    setEditingMoneyRecord(undefined);
    setNotice(editingMoneyRecord ? "Money activity updated across every perspective." : `${moneyDraft.kind === "expense" ? "Expense" : "Money entry"} added for ${moneyDraft.date}.`);
  }

  function editMoneyActivity(record: EditingMoneyRecord) {
    setEditingMoneyRecord(record);
    if (record.source === "expense") {
      const entry = state.entries.find((item) => item.id === record.id);
      if (!entry) return;
      setMoneyDraft({ kind: "expense", amount: String(entry.amount ?? ""), date: localDateKey(new Date(entry.timestamp)), note: entry.title, balanceCategory: "cash", tripId: entry.tripId });
    } else if (record.source === "money") {
      const entry = state.moneyEntries.find((item) => item.id === record.id);
      if (!entry) return;
      setMoneyDraft({ kind: entry.kind, amount: String(entry.amount), date: localDateKey(new Date(entry.date)), note: entry.note ?? "", balanceCategory: "cash" });
    } else {
      const item = state.balanceSheetItems.find((entry) => entry.id === record.id);
      if (!item) return;
      setMoneyDraft({ kind: isAssetCategory(item.category) ? "asset" : "liability", amount: String(item.balance), date: localDateKey(new Date(item.updatedAt)), note: item.name, balanceCategory: item.category, existingBalanceID: item.id });
    }
    setMoneyEntryMode("type");
    setMoneyReview(undefined);
    setMoneyEntryOpen(true);
  }

  function deleteMoneyActivity(record: EditingMoneyRecord) {
    if (!window.confirm("Delete this money activity? Every money perspective will update immediately.")) return;
    setState((current) => {
      const saving = record.source === "money"
        ? current.moneyEntries.find((item) => item.id === record.id && item.kind === "saving")?.amount ?? 0
        : 0;
      return {
        ...current,
        entries: record.source === "expense" ? current.entries.filter((entry) => entry.id !== record.id) : current.entries,
        moneyEntries: record.source === "money" ? current.moneyEntries.filter((entry) => entry.id !== record.id) : current.moneyEntries,
        balanceSheetItems: record.source === "balance" ? current.balanceSheetItems.filter((item) => item.id !== record.id) : current.balanceSheetItems,
        savingsCurrent: Math.max(0, current.savingsCurrent - saving),
      };
    });
    setMoneyEntryOpen(false);
    setEditingMoneyRecord(undefined);
    setNotice("Money activity deleted and all perspectives recalculated.");
  }

  function newTrip() {
    setTripDraft({
      name: "",
      destination: "",
      budget: "",
      startDate: localDateKey(),
      endDate: dateKeyAtOffset(3),
    });
  }

  function editTrip(trip: TripBudgetPlan) {
    setTripDraft({
      id: trip.id,
      name: trip.name,
      destination: trip.destination,
      budget: String(trip.budget),
      startDate: localDateKey(new Date(trip.startDate)),
      endDate: localDateKey(new Date(trip.endDate)),
      createdAt: trip.createdAt,
    });
  }

  function submitTrip(event: FormEvent) {
    event.preventDefault();
    if (!tripDraft) return;
    const budget = Number(tripDraft.budget.replace(",", "."));
    const startDate = new Date(`${tripDraft.startDate}T12:00:00`);
    const endDate = new Date(`${tripDraft.endDate}T12:00:00`);
    if (!tripDraft.name.trim() || !tripDraft.destination.trim()) {
      setNotice("Add a trip name and destination.");
      return;
    }
    if (!Number.isFinite(budget) || budget <= 0) {
      setNotice("Enter a trip budget greater than zero.");
      return;
    }
    if (!Number.isFinite(startDate.getTime()) || !Number.isFinite(endDate.getTime()) || endDate < startDate) {
      setNotice("Choose an end date on or after the start date.");
      return;
    }
    const trip: TripBudgetPlan = {
      id: tripDraft.id ?? uid(),
      name: tripDraft.name.trim(),
      destination: tripDraft.destination.trim(),
      budget,
      startDate: startDate.toISOString(),
      endDate: endDate.toISOString(),
      createdAt: tripDraft.createdAt ?? new Date().toISOString(),
    };
    setState((current) => ({
      ...current,
      trips: current.trips.some((item) => item.id === trip.id)
        ? current.trips.map((item) => item.id === trip.id ? trip : item)
        : [...current.trips, trip],
    }));
    setTripDraft(undefined);
    setNotice(tripDraft.id ? "Trip plan updated. Linked expense totals were recalculated." : "Trip plan created. Add expenses from the trip card or the money entry form.");
  }

  function deleteTrip(trip: TripBudgetPlan) {
    if (!window.confirm(`Delete ${trip.name}? Its expenses will stay in Money but will no longer be linked to this trip.`)) return;
    setState((current) => ({
      ...current,
      trips: current.trips.filter((item) => item.id !== trip.id),
      entries: current.entries.map((entry) => entry.tripId === trip.id ? { ...entry, tripId: undefined } : entry),
    }));
    setTripDraft(undefined);
    setNotice("Trip plan deleted. Its expense records remain in your money ledger.");
  }

  function changeMoneyCycleStartDay(value: string) {
    const day = Number(value);
    if (!Number.isInteger(day) || day < 1 || day > 31) return;
    setState((current) => ({ ...current, moneyCycleStartDay: day }));
    setMoneyCycleOffset(0);
    setNotice(`Your money cycle now starts on the ${ordinalDay(day)} of each month.`);
  }

  async function submitMoneyInstruction(event: FormEvent) {
    event.preventDefault();
    const local = parseMoneyInstruction(moneyInstruction);
    if (local) {
      setMoneyReview(local);
      return;
    }
    if (!aiConsent) {
      setNotice("That entry is ambiguous. Enable AI data sharing in Asitra AI, or use the guided form.");
      return;
    }
    setMoneyClassifying(true);
    try {
      const response = await fetch("/api/finance/classify", {
        method: "POST",
        credentials: "same-origin",
        headers: { "content-type": "application/json", "x-asitra-request": "1" },
        body: JSON.stringify({ text: moneyInstruction, consent: true, timezone: Intl.DateTimeFormat().resolvedOptions().timeZone }),
      });
      const body = await response.json() as { classification?: ParsedMoneyInstruction; error?: string };
      if (!response.ok || !body.classification) throw new Error(body.error || "Asitra could not classify that entry.");
      setMoneyReview(body.classification);
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "Asitra could not classify that entry.");
    } finally {
      setMoneyClassifying(false);
    }
  }

  function confirmMoneyReview() {
    if (!moneyReview) return;
    storeMoneyRecord(moneyReview.kind, moneyReview.amount, moneyReview.date, moneyReview.title, moneyReview.balanceCategory);
    setMoneyEntryOpen(false);
    setNotice(`${currency.format(moneyReview.amount)} recorded once and reflected across your money views.`);
  }

  async function readStatementPdf(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;
    setImportReading(true);
    setImportedTransactions([]);
    setImportFileName(file.name);
    try {
      const text = await extractPdfText(file);
      const transactions = parseStatementText(text);
      setImportedTransactions(transactions);
      if (!transactions.length) {
        setNotice("No dated transactions with amounts were detected. Try a text-based bank PDF.");
      }
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "The PDF could not be read.");
    } finally {
      setImportReading(false);
    }
  }

  function commitStatementImport() {
    const selected = importedTransactions.filter((transaction) => transaction.selected);
    if (!selected.length) {
      setNotice("Select at least one transaction to import.");
      return;
    }
    setState((current) => {
      const existing = new Set([
        ...current.entries
          .filter((entry) => entry.kind === "expense" && entry.amount)
          .map((entry) => `${entry.timestamp.slice(0, 10)}|expense|${entry.amount!.toFixed(2)}|${entry.title.toLowerCase()}`),
        ...current.moneyEntries
          .filter((entry) => entry.kind === "income")
          .map((entry) => `${entry.date.slice(0, 10)}|income|${entry.amount.toFixed(2)}|${(entry.note ?? "").toLowerCase()}`),
      ]);
      const fresh = selected.filter(
        (transaction) =>
          !existing.has(
            `${transaction.date.slice(0, 10)}|${transaction.kind}|${transaction.amount.toFixed(2)}|${transaction.title.toLowerCase()}`,
          ),
      );
      return {
        ...current,
        entries: [
          ...fresh
            .filter((transaction) => transaction.kind === "expense")
            .map<Entry>((transaction) => ({
              id: uid(),
              title: transaction.title,
              kind: "expense",
              amount: transaction.amount,
              timestamp: transaction.date,
              source: "PDF statement",
            })),
          ...current.entries,
        ],
        moneyEntries: [
          ...current.moneyEntries,
          ...fresh
            .filter((transaction) => transaction.kind === "income")
            .map<MoneyEntry>((transaction) => ({
              id: uid(),
              kind: "income",
              amount: transaction.amount,
              date: transaction.date,
              note: transaction.title,
            })),
        ],
      };
    });
    setMoneyEntryOpen(false);
    setNotice(`${selected.length} statement ${selected.length === 1 ? "entry" : "entries"} imported. Existing matches were skipped.`);
  }

  function editBalanceSheetItem(existing?: BalanceSheetItem, asset = true) {
    if (existing) {
      editMoneyActivity({ source: "balance", id: existing.id });
      return;
    }
    setEditingMoneyRecord(undefined);
    const kind: MoneyDraft["kind"] = existing ? (isAssetCategory(existing.category) ? "asset" : "liability") : (asset ? "asset" : "liability");
    setMoneyDraft({
      kind,
      amount: existing ? String(existing.balance) : "",
      date: new Date().toISOString().slice(0, 10),
      note: existing?.name ?? "",
      balanceCategory: existing?.category ?? (asset ? "cash" : "creditCard"),
      existingBalanceID: existing?.id,
    });
    setMoneyEntryMode("type");
    setMoneyReview(undefined);
    setMoneyEntryOpen(true);
  }

  async function sendMessage(text = chatInput) {
    const question = text.trim();
    if (!question || assistantThinking) return;
    const userMessage: ChatMessage = { id: uid(), role: "user", text: question };
    const conversation = [...messages, userMessage].slice(-12);
    setMessages((current) => [...current, userMessage]);
    setChatInput("");
    setAssistantThinking(true);

    const requestedMoneyEntry = isMoneyRecordCommand(question)
      ? parseMoneyInstruction(question)
      : undefined;
    if (requestedMoneyEntry) {
      storeMoneyRecord(
        requestedMoneyEntry.kind,
        requestedMoneyEntry.amount,
        requestedMoneyEntry.date,
        requestedMoneyEntry.title,
      );
      setMessages((current) => [
        ...current,
        {
          id: uid(),
          role: "assistant",
          text: `Done — I recorded ${currency.format(requestedMoneyEntry.amount)} as ${requestedMoneyEntry.kind} on ${new Date(requestedMoneyEntry.date).toLocaleDateString()}. You can see it in Money and on the timeline when it is an expense.`,
        },
      ]);
      setAssistantThinking(false);
      return;
    }

    try {
      const response = await fetch("/api/assistant", {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "content-type": "application/json",
          "x-asitra-request": "1",
        },
        body: JSON.stringify({
          messages: conversation.map(({ role, text }) => ({ role, text })),
          consent: aiConsent,
        }),
      });
      const result = (await response.json()) as {
        answer?: string;
        code?: string;
        error?: string;
        model?: string;
        label?: string;
        profile?: string;
        contractVersion?: number;
      };
      if (!response.ok || !result.answer) {
        if (result.code === "AI_CONSENT_REQUIRED") {
          setNotice(`Choose ‘Allow AI analysis’ before sending private context to ${aiContract.label}.`);
        } else if (result.code === "AI_RATE_LIMIT") {
          setNotice("Your hourly AI limit is reached. Local insights remain available.");
        } else if (result.code === "AI_NOT_CONFIGURED") {
          setNotice(`${aiContract.label} needs an OpenAI API key. Showing Asitra’s local insight instead.`);
        } else {
          setNotice(result.error ?? "Asitra AI is temporarily unavailable.");
        }
        throw new Error(result.error ?? "AI unavailable");
      }
      setMessages((current) => [
        ...current,
        { id: uid(), role: "assistant", text: result.answer! },
      ]);
      if (result.model && result.label && result.profile && result.contractVersion) {
        setAIContract({
          model: result.model,
          label: result.label,
          profile: result.profile,
          version: result.contractVersion,
        });
      }
      return;
    } catch {
      // The deterministic local answer keeps core insights available offline
      // and when the private AI service has not yet been configured.
    } finally {
      setAssistantThinking(false);
    }

    const answer = localAssistantAnswer(question);
    setMessages((current) => [
      ...current,
      { id: uid(), role: "assistant", text: answer },
    ]);
  }

  function localAssistantAnswer(question: string) {
    const lower = question.toLowerCase();
    let answer = `Across the last seven days, you recorded ${weekEntries.length} moments.`;
    if (/(today|day|schedule)/.test(lower)) {
      answer = `Today has ${dayEntries.length} recorded moments, ${openItems} open list items, and ${minutesLabel(dayEntries.filter((entry) => entry.kind === "movement").reduce((sum, entry) => sum + (entry.minutes ?? 0), 0)) || "no movement yet"}.`;
    } else if (/(spend|money|expense|budget)/.test(lower)) {
      answer = `You received ${currency.format(monthIncome)} and spent ${currency.format(monthSpent)} in your ${activeMoneyCycleLabel} cycle. Your recorded net worth is ${currency.format(netWorth)}, and ${currency.format(Math.max(state.monthlyBudget - monthSpent, 0))} remains in your spending plan.`;
    } else if (/(balance|work|personal)/.test(lower)) {
      answer = `Your seven-day balance score is ${balanceScore}/100. You logged ${minutesLabel(weekWork)} of work and about ${minutesLabel(weekPersonal)} of personal time. ${todayInsight}`;
    } else if (/(list|open|attention|task)/.test(lower)) {
      answer = `${openItems} items are open across ${state.lists.length} lists. ${selectedList?.items.filter((item) => !item.done).length ?? 0} of them are in ${selectedList?.name ?? "your selected list"}.`;
    } else if (/(movement|health|fitness|walk)/.test(lower)) {
      answer = `You logged ${minutesLabel(weekActivity) || "no activity"} of movement in the last seven days.`;
    } else if (/(pattern|insight|stand out|learn)/.test(lower)) {
      answer = todayInsight;
    }
    return answer;
  }

  function openAssistant(initialQuestion?: string) {
    setAssistantOpen(true);
    if (!messages.length) {
      setMessages([
        {
          id: uid(),
          role: "assistant",
          text:
            weekEntries.length === 0
              ? "I’m ready when you are. Add a few moments, then ask me what stands out."
              : `${weekEntries.length} moments shape your last seven days. You logged ${minutesLabel(weekActivity)} of movement and have ${openItems} open list items. What would you like to understand?`,
        },
      ]);
    }
    if (initialQuestion) setChatInput(initialQuestion);
  }

  function saveEditedEntry(event: FormEvent) {
    event.preventDefault();
    if (!editingEntry) return;
    if (editingEntry.endTimestamp && new Date(editingEntry.endTimestamp) < new Date(editingEntry.timestamp)) {
      setNotice("Choose an end time after the start time.");
      return;
    }
    const capabilities = entryCapabilities(editingEntry.kind);
    const nextEntry: Entry = {
      ...editingEntry,
      amount: capabilities.usesAmount ? editingEntry.amount : undefined,
      minutes: capabilities.usesDuration ? editingEntry.minutes : undefined,
      status: capabilities.usesStatus ? editingEntry.status ?? "planned" : undefined,
      completed: capabilities.completable ? editingEntry.completed ?? false : undefined,
      tripId: capabilities.canLinkTrip ? editingEntry.tripId : undefined,
    };
    const sourceList = state.lists.find((list) => list.items.some((item) => item.id === nextEntry.id));
    const targetList = sourceList ?? (nextEntry.kind === "list" ? selectedList : undefined);
    const synchronizedEntry: Entry = {
      ...nextEntry,
      listId: nextEntry.kind === "list" ? targetList?.id : undefined,
    };
    const updatedList = targetList
      ? {
          ...targetList,
          items: synchronizedEntry.kind === "list"
            ? (() => {
                const start = new Date(synchronizedEntry.timestamp);
                const end = synchronizedEntry.endTimestamp ? new Date(synchronizedEntry.endTimestamp) : undefined;
                const projected: ListItem = {
                  id: synchronizedEntry.id,
                  text: synchronizedEntry.title,
                  done: synchronizedEntry.completed ?? false,
                  plannedDate: localDateKey(start),
                  due: localDateKey(start) === localDateKey() ? "Today" : localDateKey(start) === dateKeyAtOffset(1) ? "Tomorrow" : localDateKey(start),
                  planMode: end ? "exact" : "anytime",
                  startTime: end ? localTimeKey(start) : undefined,
                  endTime: end ? localTimeKey(end) : undefined,
                  durationMinutes: synchronizedEntry.minutes,
                };
                return targetList.items.some((item) => item.id === synchronizedEntry.id)
                  ? targetList.items.map((item) => item.id === synchronizedEntry.id ? { ...item, ...projected } : item)
                  : [projected, ...targetList.items];
              })()
            : targetList.items.filter((item) => item.id !== synchronizedEntry.id),
        }
      : undefined;
    setState((current) => ({
      ...current,
      entries: current.entries.map((entry) =>
        entry.id === synchronizedEntry.id ? synchronizedEntry : entry,
      ),
      lists: current.lists.map((list) => list.id === updatedList?.id ? updatedList : list),
      todayPriorityIds: synchronizedEntry.kind !== "list" || synchronizedEntry.completed || localDateKey(new Date(synchronizedEntry.timestamp)) !== localDateKey()
        ? current.todayPriorityIds.filter((id) => id !== synchronizedEntry.id)
        : current.todayPriorityIds,
    }));
    if (updatedList?.shared) void updateSharedList(updatedList);
    setEditingEntry(undefined);
    setNotice("Entry updated everywhere it appears.");
  }

  function deleteEditedEntry() {
    if (!editingEntry || !window.confirm(`Delete “${editingEntry.title}”? This cannot be undone.`)) return;
    setState((current) => ({
      ...current,
      entries: current.entries.filter((entry) => entry.id !== editingEntry.id),
      lists: current.lists.map((list) => ({ ...list, items: list.items.filter((item) => item.id !== editingEntry.id) })),
      todayPriorityIds: current.todayPriorityIds.filter((id) => id !== editingEntry.id),
    }));
    const sharedList = state.lists.find((list) => list.shared && list.items.some((item) => item.id === editingEntry.id));
    if (sharedList) void updateSharedList({ ...sharedList, items: sharedList.items.filter((item) => item.id !== editingEntry.id) });
    setEditingEntry(undefined);
    setNotice("Timeline entry deleted.");
  }

  async function deleteAccount() {
    if (deleteConfirmation !== "DELETE MY ACCOUNT") return;
    const response = await fetch("/api/state", {
      method: "DELETE",
      credentials: "same-origin",
      headers: {
        "x-asitra-request": "1",
        "x-asitra-confirm-delete": deleteConfirmation,
      },
    });
    if (!response.ok) {
      setNotice("Your account could not be deleted. No data was removed.");
      return;
    }
    window.localStorage.removeItem(LEGACY_STORAGE_KEY);
    accountDeletedRef.current = true;
    setDeleteAccountOpen(false);
    setState(emptyState);
    stateVersionRef.current = 0;
    setNotice("Your Asitra account data, recovery copies and uploaded files were deleted.");
    if (logoutPath.startsWith("/api/auth/")) {
      await fetch(logoutPath, {
        method: "POST",
        credentials: "same-origin",
        cache: "no-store",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({}),
      }).catch(() => undefined);
      window.location.replace("/login");
    }
  }

  async function openRecovery() {
    const response = await fetch("/api/account/recovery", { cache: "no-store", credentials: "same-origin" });
    if (!response.ok) {
      setNotice("Recovery history could not be loaded.");
      return;
    }
    const payload = (await response.json()) as { revisions?: Array<{ id: string; version: number; createdAt: string }> };
    setRecoveryPoints(payload.revisions ?? []);
    setRecoveryOpen(true);
  }

  async function restoreRecoveryPoint(revisionId: string) {
    if (!window.confirm("Restore this recovery point? Asitra will first preserve your current workspace as another recovery point.")) return;
    const response = await fetch("/api/account/recovery", {
      method: "POST",
      credentials: "same-origin",
      headers: { "content-type": "application/json", "x-asitra-request": "1" },
      body: JSON.stringify({ revisionId, expectedVersion: stateVersionRef.current, confirmation: "RESTORE BACKUP" }),
    });
    const payload = (await response.json()) as { state?: unknown; version?: number; error?: string };
    if (!response.ok || !payload.state || typeof payload.version !== "number") {
      setNotice(payload.error ?? "That recovery point could not be restored.");
      return;
    }
    const restored = validatePersistedState(payload.state) as PersistedState;
    stateVersionRef.current = payload.version;
    setState(restored);
    setRecoveryOpen(false);
    setNotice("Your workspace was restored. The previous version remains in recovery history.");
  }

  async function exportData() {
    const response = await fetch("/api/account/export", { cache: "no-store", credentials: "same-origin" });
    if (!response.ok) {
      setNotice("Your account export could not be prepared. No data was changed.");
      return;
    }
    const blob = await response.blob();
    const href = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = href;
    anchor.download = `asitra-data-${new Date().toISOString().slice(0, 10)}.json`;
    anchor.click();
    URL.revokeObjectURL(href);
  }

  function importData(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    event.target.value = "";
    if (file.size > MAX_BACKUP_BYTES || (file.type && file.type !== "application/json")) {
      setNotice("Choose an Asitra JSON backup under 2 MB.");
      return;
    }
    const reader = new FileReader();
    reader.onload = () => {
      try {
        const imported = validatePersistedState(JSON.parse(String(reader.result)), {
          allowLegacyDataImages: false,
        }) as PersistedState;
        setState(imported);
        setNotice("Your Asitra backup was imported.");
      } catch {
        setNotice("That file is not a valid Asitra backup.");
      }
    };
    reader.readAsText(file);
  }

  function resetData() {
    if (!window.confirm("Replace your account data with the sample workspace? Export first if you want a backup.")) return;
    setState(seedState);
    setNotice("Sample workspace restored for your account.");
  }

  function finishOnboarding() {
    setState((current) => ({ ...current, onboardingCompleted: true }));
    setOnboardingOpen(false);
    setOnboardingStep(0);
  }

  const mainContent = (() => {
    if (section === "tasks") {
      const matrix = [
        { id: "do", title: "Do now", note: "Important and urgent", tone: "sage", items: openTasks.filter(({ item }) => taskPriorityQuadrant(item) === "do") },
        { id: "plan", title: "Plan", note: "Important, not urgent", tone: "blue", items: openTasks.filter(({ item }) => taskPriorityQuadrant(item) === "plan") },
        { id: "simplify", title: "Simplify", note: "Urgent, not important", tone: "warm", items: openTasks.filter(({ item }) => taskPriorityQuadrant(item) === "simplify") },
        { id: "later", title: "Later", note: "Not urgent or important", tone: "quiet", items: openTasks.filter(({ item }) => taskPriorityQuadrant(item) === "later") },
      ];
      const renderTaskCard = ({ item, listId, listName, listColor }: typeof allTasks[number], compact = false) => (
        <article
          className={`task-planning-card ${item.done ? "done" : ""} ${compact ? "compact" : ""}`}
          key={`${listId}-${item.id}`}
          draggable
          onDragStart={() => setDraggedTask({ listId, itemId: item.id })}
          onDragEnd={() => setDraggedTask(undefined)}
        >
          <div className="task-card-heading">
            <button className="task-complete-button" onClick={() => toggleListItem(listId, item.id)} aria-label={`${item.done ? "Reopen" : "Complete"} ${item.text}`}>
              {item.done && <Check size={13} />}
            </button>
            <button className="task-card-title" onClick={() => openTaskEditor(listId, item)}>
              <strong>{item.text}</strong>
              <small><i style={{ background: listColor }} /> {listName}</small>
            </button>
            <button className="task-card-edit" onClick={() => openTaskEditor(listId, item)} aria-label={`Edit ${item.text}`}><Pencil size={14} /></button>
          </div>
          <div className="task-card-controls">
            <button className={item.important ? "active important" : ""} onClick={() => setTaskPriority(listId, item.id, "important")} aria-pressed={Boolean(item.important)}><Flag size={13} /> Important</button>
            <button className={item.urgent ? "active urgent" : ""} onClick={() => setTaskPriority(listId, item.id, "urgent")} aria-pressed={Boolean(item.urgent)}><Zap size={13} /> Urgent</button>
            {!compact && (
              <select value={taskBoardColumn(item, taskColumns.map((column) => column.id))} onChange={(event) => moveTaskToColumn(listId, item.id, event.target.value)} aria-label={`Board column for ${item.text}`}>
                {taskColumns.map((column) => <option key={column.id} value={column.id}>{column.name}</option>)}
              </select>
            )}
          </div>
        </article>
      );
      return (
        <div className="page-shell task-planning-page">
          <PageHeader
            eyebrow="Clear the mind"
            title="Tasks"
            description="Put everything down first. Then decide what deserves attention and where it belongs."
          />
          <section className="task-dump-card">
            <div className="task-dump-copy"><Inbox size={20} /><div><strong>Task inbox</strong><span>Capture it now. Organize it in a second.</span></div></div>
            <form onSubmit={addTaskDump}>
              <input value={taskDump} onChange={(event) => setTaskDump(event.target.value)} placeholder="What is on your mind?" aria-label="New task" />
              <div className="task-dump-tags">
                <button type="button" className={taskDumpImportant ? "active important" : ""} onClick={() => setTaskDumpImportant((value) => !value)} aria-pressed={taskDumpImportant}><Flag size={14} /> Important</button>
                <button type="button" className={taskDumpUrgent ? "active urgent" : ""} onClick={() => setTaskDumpUrgent((value) => !value)} aria-pressed={taskDumpUrgent}><Zap size={14} /> Urgent</button>
              </div>
              <button className="primary-button" disabled={!taskDump.trim()}><Plus size={16} /> Add task</button>
            </form>
          </section>
          <div className="task-view-toolbar">
            <div className="segment-row task-view-segments" aria-label="Task view">
              <button className={taskView === "matrix" ? "active" : ""} onClick={() => setTaskView("matrix")}><Grid2X2 size={15} /> Priority matrix</button>
              <button className={taskView === "board" ? "active" : ""} onClick={() => setTaskView("board")}><Columns3 size={15} /> Board</button>
            </div>
            <span>{openTasks.length} open · {allTasks.length - openTasks.length} done</span>
          </div>
          {taskView === "matrix" ? (
            <div className="priority-matrix" aria-label="Urgent and important task matrix">
              <div className="matrix-axis matrix-axis-top"><strong>Urgent</strong><span>Not urgent</span></div>
              <div className="matrix-axis matrix-axis-side"><span>Not important</span><strong>Important</strong></div>
              {matrix.map((quadrant) => (
                <section className={`matrix-quadrant ${quadrant.tone}`} key={quadrant.id}>
                  <header><div><h2>{quadrant.title}</h2><p>{quadrant.note}</p></div><span>{quadrant.items.length}</span></header>
                  <div className="matrix-task-list">
                    {quadrant.items.map((task) => renderTaskCard(task, true))}
                    {!quadrant.items.length && <div className="matrix-empty">Nothing here. That is useful information too.</div>}
                  </div>
                </section>
              ))}
            </div>
          ) : (
            <>
              <div className="task-board-toolbar">
                <p>Drag tasks between columns, or use the column menu on each card.</p>
                <button className="secondary-button" onClick={() => setColumnEditor({ id: "", name: "" })}><Plus size={16} /> Add column</button>
              </div>
              <div className="task-board" aria-label="Task board">
                {taskColumns.map((column) => {
                  const columnTasks = allTasks.filter(({ item }) => taskBoardColumn(item, taskColumns.map((candidate) => candidate.id)) === column.id);
                  return (
                    <section
                      className="task-board-column"
                      key={column.id}
                      onDragOver={(event) => event.preventDefault()}
                      onDrop={() => {
                        if (draggedTask) moveTaskToColumn(draggedTask.listId, draggedTask.itemId, column.id);
                        setDraggedTask(undefined);
                      }}
                    >
                      <header><div><h2>{column.name}</h2><span>{columnTasks.length}</span></div><button onClick={() => setColumnEditor(column)} aria-label={`Rename ${column.name}`}><Pencil size={14} /></button></header>
                      <div className="task-board-stack">
                        {columnTasks.map((task) => renderTaskCard(task))}
                        {!columnTasks.length && <div className="board-drop-zone">Drop tasks here</div>}
                      </div>
                    </section>
                  );
                })}
              </div>
            </>
          )}
        </div>
      );
    }

    if (section === "lists") {
      return (
        <div className="page-shell">
          <PageHeader
            eyebrow="Commitments"
            title="Lists"
            description="Everything you want to remember, privately or together."
            action={<div className="header-actions"><button className="secondary-button" onClick={() => { setInviteCode(""); setSharingOwner(false); setSharingOpen(true); }}><Users size={17} /> Join list</button><button className="primary-button" onClick={addNewList}><Plus size={17} /> New list</button></div>}
          />
          <div className="lists-layout">
            <div className="list-rail">
              {state.lists.map((list) => {
                const remaining = list.items.filter((item) => !item.done).length;
                return (
                  <button
                    className={`list-card ${selectedList?.id === list.id ? "selected" : ""}`}
                    key={list.id}
                    onClick={() => setSelectedListId(list.id)}
                  >
                    <span className="list-dot" style={{ background: list.color }} />
                    <span>
                      <strong>{list.name}</strong>
                      <small>{remaining} open · {list.shared ? `${list.members} people` : "Private"}</small>
                    </span>
                    {list.shared ? <Users size={16} /> : <Lock size={15} />}
                  </button>
                );
              })}
            </div>
            {selectedList && (
              <section className="panel list-detail">
                <div className="section-heading">
                  <div>
                    <div className="eyebrow">{selectedList.shared ? "Shared list" : "Private list"}</div>
                    <h2>{selectedList.name}</h2>
                  </div>
                  <button className="secondary-button" onClick={() => void toggleListSharing()}>
                    {selectedList.shared ? <Users size={16} /> : <Lock size={16} />}
                    {selectedList.shared ? "Manage sharing" : "Share"}
                  </button>
                </div>
                <form className="inline-add" onSubmit={addListItem}>
                  <input
                    value={newListItem}
                    onChange={(event) => setNewListItem(event.target.value)}
                    placeholder="Add an item naturally…"
                  />
                  <button aria-label="Add item"><Plus size={18} /></button>
                </form>
                <div className="list-items">
                  {selectedList.items.map((item) => (
                    <div className={`check-row task-list-row ${item.done ? "done" : ""}`} key={item.id}>
                      <button className="check-box" onClick={() => toggleListItem(selectedList.id, item.id)} aria-label={`${item.done ? "Reopen" : "Complete"} ${item.text}`}>{item.done && <Check size={14} />}</button>
                      <span><strong>{item.text}</strong><small>{item.plannedDate ? `${item.plannedDate} · ${taskTimeLabel(item)}` : item.due || "Not scheduled"}</small></span>
                      <div className="task-row-actions">
                        <button onClick={() => openTaskEditor(selectedList.id, item)} aria-label={`Edit ${item.text}`}><Pencil size={15} /></button>
                        {!item.done && <button onClick={() => postponeTask(selectedList.id, item)} aria-label={`Move ${item.text} to tomorrow`}><CalendarClock size={15} /></button>}
                        <button className="delete" onClick={() => deleteTask(selectedList.id, item.id)} aria-label={`Delete ${item.text}`}><Trash2 size={15} /></button>
                      </div>
                    </div>
                  ))}
                </div>
                <div className="native-note">
                  <ShieldCheck size={17} />
                  Apple Reminders sync is available through the native Asitra app.
                </div>
              </section>
            )}
          </div>
        </div>
      );
    }

    if (section === "track") {
      const families: TrackerFamily[] = ["Health", "Habits", "Learning & Media", "Mindset"];
      const visibleTrackers = state.trackers.filter((tracker) => tracker.family === trackerFamily);
      return (
        <div className="page-shell">
          <PageHeader
            eyebrow="Personal progress"
            title="Track what matters"
            description="Health, habits, learning and mindset—without turning life into a spreadsheet."
            action={<button className="primary-button" onClick={addTracker}><Plus size={17} /> New tracker</button>}
          />
          <div className="segment-row">
            {families.map((family) => (
              <button
                key={family}
                className={trackerFamily === family ? "active" : ""}
                onClick={() => setTrackerFamily(family)}
              >
                {family}
              </button>
            ))}
          </div>
          <div className="tracker-grid">
            {visibleTrackers.map((tracker) => {
              const Icon = trackerIcon(tracker.icon);
              const count = trackerCount(tracker);
              const target = tracker.target ?? 5;
              return (
                <article className="panel tracker-card" key={tracker.id}>
                  <div className="tracker-icon"><Icon size={20} /></div>
                  <div>
                    <span className="eyebrow">{tracker.family}</span>
                    <h3>{tracker.name}</h3>
                  </div>
                  <div className="progress-line">
                    <span style={{ width: `${Math.min((count / target) * 100, 100)}%` }} />
                  </div>
                  <div className="tracker-footer">
                    <small>{count} of {target} this week</small>
                    <button onClick={() => checkIn(tracker)}><Plus size={15} /> Check in</button>
                  </div>
                </article>
              );
            })}
            {!visibleTrackers.length && (
              <div className="panel empty-panel">
                <Target size={24} />
                <h3>No tracker here yet</h3>
                <p>Create one when it will help you notice progress—not just collect data.</p>
              </div>
            )}
          </div>
          <section className="panel context-panel">
            <div>
              <span className="eyebrow">This week</span>
              <h2>Your evidence, in context</h2>
            </div>
            <div className="mini-stat"><Activity size={18} /><strong>{minutesLabel(weekActivity) || "—"}</strong><span>Movement</span></div>
            <div className="mini-stat"><BookOpen size={18} /><strong>{weekEntries.filter((e) => e.kind === "book").length}</strong><span>Reading</span></div>
            <div className="mini-stat"><Brain size={18} /><strong>{weekEntries.filter((e) => ["mindset", "journal"].includes(e.kind)).length}</strong><span>Mindset</span></div>
          </section>
        </div>
      );
    }

    if (section === "money") {
      const remaining = Math.max(financeViews.budgetRemaining, 0);
      const budgetUsage = state.monthlyBudget > 0
        ? Math.min((monthSpent / state.monthlyBudget) * 100, 100)
        : 0;
      const savingsProgress = state.savingsTarget > 0
        ? Math.min((state.savingsCurrent / state.savingsTarget) * 100, 100)
        : 0;
      const surplus = financeViews.surplusAfterSpending;
      const unallocated = financeViews.unassigned;
      const netCashMovement = financeViews.netCashMovement;
      const allocationBalanced = financeViews.isFullyAssigned;
      const categoryGroups = [
        { label: "Everyday", value: monthEntries.filter((e) => e.amount && e.amount < 40).reduce((s, e) => s + (e.amount ?? 0), 0), color: "#df9966" },
        { label: "Living", value: monthEntries.filter((e) => e.amount && e.amount >= 40).reduce((s, e) => s + (e.amount ?? 0), 0), color: "#7d8d79" },
        { label: "Leisure", value: monthEntries.filter((e) => /dinner|movie|coffee/i.test(e.title)).reduce((s, e) => s + (e.amount ?? 0), 0), color: "#8482a0" },
      ];
      return (
        <div className="page-shell">
          <PageHeader
            eyebrow="Money, made understandable"
            title="Your money"
            description="Add each money event once. Budget, cash flow, monthly allocation and net worth are four useful views of the same financial life."
            action={
              <button className="primary-button" onClick={() => openMoneyEntry()}><Plus size={17} /> Add money activity</button>
            }
          />
          <section className="money-capture-card">
            <div className="money-capture-icon"><Sparkles size={20} /></div>
            <button className="money-capture-main" onClick={() => openMoneyEntry()}>
              <strong>Tell Asitra what changed</strong>
              <span>“Paid €32 for groceries” · “Salary €3,200” · “My savings account balance is €8,400”</span>
            </button>
            <button className="money-import-shortcut" onClick={() => openMoneyEntry("expense", "pdf")}><FileText size={16} /> Import PDF</button>
          </section>
          <section className="money-cycle-card" aria-label="Money cycle">
            <div className="money-cycle-period">
              <button className="icon-button" onClick={() => setMoneyCycleOffset((value) => value - 1)} aria-label="Previous money cycle">
                <ChevronLeft size={18} />
              </button>
              <div>
                <span className="eyebrow">Monthly cycle</span>
                <strong>{activeMoneyCycleLabel}</strong>
              </div>
              <button className="icon-button" onClick={() => setMoneyCycleOffset((value) => Math.min(value + 1, 0))} disabled={moneyCycleOffset === 0} aria-label="Next money cycle">
                <ChevronRight size={18} />
              </button>
            </div>
            <label className="money-cycle-setting">
              <CalendarDays size={17} />
              <span>Cycle starts</span>
              <select value={state.moneyCycleStartDay} onChange={(event) => changeMoneyCycleStartDay(event.target.value)} aria-label="Money cycle start day">
                {Array.from({ length: 31 }, (_, index) => index + 1).map((day) => (
                  <option key={day} value={day}>{ordinalDay(day)}</option>
                ))}
              </select>
            </label>
            <p>Choose your salary day. For shorter months, Asitra uses the last valid day automatically.</p>
          </section>
          <div className="segment-row money-segments">
            <button className={moneyView === "budget" ? "active" : ""} onClick={() => setMoneyView("budget")}>Budget</button>
            <button className={moneyView === "cashflow" ? "active" : ""} onClick={() => setMoneyView("cashflow")}>Cash flow</button>
            <button className={moneyView === "allocation" ? "active" : ""} onClick={() => setMoneyView("allocation")}>Monthly allocation</button>
            <button className={moneyView === "networth" ? "active" : ""} onClick={() => setMoneyView("networth")}>Balance sheet</button>
          </div>
          {moneyView !== "budget" ? (
            <>
              {moneyView === "networth" && <section className="money-position-hero">
                <div>
                  <span className="eyebrow">Your money position</span>
                  <strong>{currency.format(netWorth)}</strong>
                  <p>{currency.format(totalAssets)} owned − {currency.format(totalLiabilities)} owed</p>
                </div>
                <div className="position-pulse">
                  <small>{activeMoneyCycleLabel}</small>
                  <strong>{netCashMovement >= 0 ? "+" : "−"}{currency.format(Math.abs(netCashMovement))}</strong>
                  <span>cash movement</span>
                </div>
              </section>}
              <div className="statement-grid focused-statement-grid">
                {moneyView === "cashflow" && <section className="panel statement-card">
                  <div className="statement-title">
                    <div><span className="eyebrow">Movement</span><h2>Cash flow</h2><p>What came in and left usable cash.</p></div>
                    <WalletCards size={20} />
                  </div>
                  <div className="statement-line"><span>Income</span><strong className="positive">+{currency.format(monthIncome)}</strong></div>
                  <div className="statement-line"><span>Everyday spending</span><strong>−{currency.format(monthSpent)}</strong></div>
                  <div className="statement-line"><span>Moved to investments</span><strong>−{currency.format(monthInvested)}</strong></div>
                  <div className="statement-line total"><span>Net cash movement</span><strong>{currency.format(netCashMovement)}</strong></div>
                  {monthSaved > 0 && <p className="statement-note">{currency.format(monthSaved)} earmarked for goals remains cash until it is transferred.</p>}
                </section>}

                {moneyView === "allocation" && <section className="panel statement-card">
                  <div className="statement-title">
                    <div><span className="eyebrow">Personal P&amp;L</span><h2>Monthly allocation</h2><p>Give every euro of surplus a purpose.</p></div>
                    <CircleDollarSign size={20} />
                  </div>
                  <div className="statement-line"><span>Income</span><strong>{currency.format(monthIncome)}</strong></div>
                  <div className="statement-line"><span>Spent on life</span><strong>−{currency.format(monthSpent)}</strong></div>
                  <div className="statement-line total"><span>Surplus after spending</span><strong>{currency.format(surplus)}</strong></div>
                  <div className="statement-line"><span>Saved</span><strong>{currency.format(monthSaved)}</strong></div>
                  <div className="statement-line"><span>Invested</span><strong>{currency.format(monthInvested)}</strong></div>
                  <div className="statement-line total"><span>{unallocated >= 0 ? "Still to assign" : "Used from reserves"}</span><strong>{currency.format(Math.abs(unallocated))}</strong></div>
                  <p className={`allocation-status ${allocationBalanced ? "balanced" : unallocated < 0 ? "over" : ""}`}>
                    {allocationBalanced
                      ? "Balanced: income is fully spent, saved or invested."
                      : unallocated > 0
                        ? "Assign the remainder to saving or investing to reach zero."
                        : "This cycle used existing cash or debt."}
                  </p>
                </section>}

                {moneyView === "networth" && <section className="panel statement-card balance-statement">
                  <div className="statement-title">
                    <div><span className="eyebrow">Personal balance sheet</span><h2>Net worth</h2><p>What you own minus what you owe.</p></div>
                    <BarChart3 size={20} />
                  </div>
                  <span className="statement-group">Assets</span>
                  {assets.map((item) => (
                    <button className="balance-item-row" key={item.id} onClick={() => editBalanceSheetItem(item)}>
                      <span><strong>{item.name}</strong><small>{balanceCategoryLabel(item.category)}</small></span>
                      <b>{currency.format(item.balance)}</b>
                    </button>
                  ))}
                  {!assets.length && <p className="statement-note">No assets recorded yet.</p>}
                  <div className="statement-line total"><span>Total assets</span><strong>{currency.format(totalAssets)}</strong></div>
                  <span className="statement-group">Liabilities</span>
                  {liabilities.map((item) => (
                    <button className="balance-item-row" key={item.id} onClick={() => editBalanceSheetItem(item)}>
                      <span><strong>{item.name}</strong><small>{balanceCategoryLabel(item.category)}</small></span>
                      <b>{currency.format(item.balance)}</b>
                    </button>
                  ))}
                  {!liabilities.length && <p className="statement-note">No debts recorded.</p>}
                  <div className="statement-line total net-worth-line"><span>Net worth</span><strong>{currency.format(netWorth)}</strong></div>
                </section>}
              </div>
              <div className="native-note wide">
                <ShieldCheck size={17} />
                Personal overview only—not formal accounting or financial advice. Saving goals are not counted again as assets unless their account balance is recorded.
              </div>
            </>
          ) : (
            <>
              <div className="money-hero">
                <div>
                  <span className="eyebrow">Available this cycle</span>
                  <strong>{currency.format(remaining)}</strong>
                  <p>{currency.format(monthSpent)} used from a {currency.format(state.monthlyBudget)} plan</p>
                </div>
                <div className="budget-ring" style={{ "--progress": `${budgetUsage * 3.6}deg` } as React.CSSProperties}>
                  <span>{Math.round(budgetUsage)}%</span>
                </div>
              </div>
              <div className="money-grid">
                <section className="panel spending-panel">
                  <div className="section-heading"><div><span className="eyebrow">Where it went</span><h2>Spending</h2></div><Search size={18} /></div>
                  {categoryGroups.map((group) => (
                    <div className="money-row" key={group.label}>
                      <span className="category-mark" style={{ background: group.color }} />
                      <span>{group.label}</span>
                      <div className="money-bar"><i style={{ width: `${Math.min((group.value / Math.max(monthSpent, 1)) * 100, 100)}%`, background: group.color }} /></div>
                      <strong>{currency.format(group.value)}</strong>
                    </div>
                  ))}
                </section>
                <section className="panel savings-panel">
                  <div className="section-heading"><div><span className="eyebrow">Saving plan</span><h2>Future freedom</h2></div><Target size={19} /></div>
                  <strong>{currency.format(state.savingsCurrent)}</strong>
                  <p>of {currency.format(state.savingsTarget)}</p>
                  <div className="progress-line large"><span style={{ width: `${savingsProgress}%` }} /></div>
                  <button className="secondary-button full" onClick={() => openMoneyEntry("saving")}>
                    <Plus size={16} /> Add contribution
                  </button>
                </section>
                <section className="panel trip-planner-panel">
                  <div className="section-heading">
                    <div><span className="eyebrow">Travel without surprises</span><h2>Trip plans</h2></div>
                    <button className="secondary-button" onClick={newTrip}><Plus size={16} /> Plan a trip</button>
                  </div>
                  <p className="trip-planner-intro">Set one total budget, then link expenses as they happen. Each expense is entered once and also stays in your main money views.</p>
                  {!state.trips.length ? (
                    <button className="trip-empty" onClick={newTrip}>
                      <span><MapPin size={21} /></span>
                      <strong>No trip planned</strong>
                      <small>Create a budget and dates before you travel.</small>
                    </button>
                  ) : (
                    <div className="trip-budget-list">
                      {state.trips.map((trip) => {
                        const summary = tripBudgetSummary(trip, state.entries);
                        const dateLabel = `${new Date(trip.startDate).toLocaleDateString("en", { day: "numeric", month: "short" })} – ${new Date(trip.endDate).toLocaleDateString("en", { day: "numeric", month: "short", year: "numeric" })}`;
                        return (
                          <article className="trip-budget-card" key={trip.id}>
                            <div className="trip-card-top">
                              <div className="trip-destination-mark"><MapPin size={18} /></div>
                              <div><span>{dateLabel}</span><h3>{trip.name}</h3><p>{trip.destination}</p></div>
                              <div className="trip-card-menu">
                                <button onClick={() => editTrip(trip)} aria-label={`Edit ${trip.name}`}><Pencil size={15} /></button>
                                <button className="delete" onClick={() => deleteTrip(trip)} aria-label={`Delete ${trip.name}`}><Trash2 size={15} /></button>
                              </div>
                            </div>
                            <div className="trip-numbers">
                              <span><small>Spent</small><strong>{currency.format(summary.spent)}</strong></span>
                              <span><small>{summary.over > 0 ? "Over" : "Left"}</small><strong className={summary.over > 0 ? "over" : ""}>{currency.format(summary.over > 0 ? summary.over : summary.remaining)}</strong></span>
                              <span><small>Plan</small><strong>{currency.format(trip.budget)}</strong></span>
                            </div>
                            <div className="trip-progress" aria-label={`${Math.round(summary.progress)} percent of trip budget used`}><i style={{ width: `${summary.progress}%` }} /></div>
                            <div className="trip-card-footer">
                              <span>{summary.expenseCount} {summary.expenseCount === 1 ? "expense" : "expenses"} linked</span>
                              <button className="primary-button" onClick={() => openMoneyEntry("expense", "type", trip.id)}><Plus size={15} /> Add trip expense</button>
                            </div>
                          </article>
                        );
                      })}
                    </div>
                  )}
                </section>
              </div>
            </>
          )}
          <section className="panel money-activity-panel">
            <div className="section-heading">
              <div><span className="eyebrow">Single source of truth</span><h2>Money activity</h2></div>
              <span className="entry-count">{moneyActivities.length} records</span>
            </div>
            <p className="money-activity-intro">Edit or delete a record here. Budget, cash flow, monthly allocation and net worth recalculate from the same activity.</p>
            <div className="money-activity-list">
              {moneyActivities.slice(0, 20).map((activity) => (
                <article key={`${activity.record.source}-${activity.id}`}>
                  <div><strong>{activity.title}</strong><span>{activity.kind} · {new Date(activity.date).toLocaleDateString()}</span></div>
                  <b>{currency.format(activity.amount)}</b>
                  <button onClick={() => editMoneyActivity(activity.record)} aria-label={`Edit ${activity.title}`}><Pencil size={15} /></button>
                  <button className="delete" onClick={() => deleteMoneyActivity(activity.record)} aria-label={`Delete ${activity.title}`}><Trash2 size={15} /></button>
                </article>
              ))}
              {!moneyActivities.length && <div className="finite-empty"><WalletCards size={23} /><strong>No money activity yet</strong><span>Add it once and every perspective will update.</span></div>}
            </div>
          </section>
        </div>
      );
    }

    if (section === "balance") {
      const workRatio = Math.min((weekWork / Math.max(weekWork + weekPersonal, 1)) * 100, 100);
      return (
        <div className="page-shell">
          <PageHeader
            eyebrow="Whole-life signal"
            title="Balance"
            description="A gentle view of where your time and energy are going—not another score to optimize."
          />
          <div className="balance-hero panel">
            <div className="score-orbit"><span>{balanceScore}</span><small>of 100</small></div>
            <div className="balance-copy">
              <span className="eyebrow">Last seven days</span>
              <h2>{balanceScore > 72 ? "Your rhythm looks sustainable." : "Your week needs a little more room."}</h2>
              <p>{todayInsight}</p>
              <button className="text-button" onClick={() => openAssistant("How is my work-life balance?")}>
                Ask Asitra about this <ArrowRight size={15} />
              </button>
            </div>
          </div>
          <div className="balance-grid">
            <section className="panel time-split">
              <div className="section-heading"><div><span className="eyebrow">Time split</span><h2>Work and life</h2></div><Clock3 size={19} /></div>
              <div className="split-bar">
                <span style={{ width: `${workRatio}%` }} />
                <i style={{ width: `${100 - workRatio}%` }} />
              </div>
              <div className="split-legend">
                <div><span className="work-dot" /><strong>{minutesLabel(weekWork) || "—"}</strong><small>Work</small></div>
                <div><span className="life-dot" /><strong>{minutesLabel(weekPersonal) || "—"}</strong><small>Personal</small></div>
              </div>
            </section>
            <section className="panel balance-signals">
              <span className="eyebrow">Signals</span>
              <h2>What supports you</h2>
              <div className="signal-row"><Activity size={18} /><span>Movement</span><strong>{minutesLabel(weekActivity) || "Not logged"}</strong></div>
              <div className="signal-row"><Moon size={18} /><span>Sleep entries</span><strong>{weekEntries.filter((e) => e.kind === "sleep").length}</strong></div>
              <div className="signal-row"><Brain size={18} /><span>Mindset check-ins</span><strong>{weekEntries.filter((e) => ["mindset", "journal"].includes(e.kind)).length}</strong></div>
            </section>
          </div>
          <div className="native-note wide">
            <ShieldCheck size={17} />
            Automatic Screen Time and Apple Health data require the native Asitra app. Web entries still contribute to your balance.
          </div>
        </div>
      );
    }

    if (section === "settings") {
      return (
        <div className="page-shell">
          <PageHeader
            eyebrow="Asitra"
            title="Settings"
            description="Manage your data and understand which capabilities are available on this device."
          />
          <div className="settings-page-grid">
            <section className="panel settings-page-card">
              <div className="section-heading">
                <div><span className="eyebrow">Data</span><h2>Your data</h2></div>
                <ShieldCheck size={20} />
              </div>
              <div className="data-summary">
                <ShieldCheck size={23} />
                <div>
                  <strong>Private account storage</strong>
                  <span>Your web data is isolated by account and protected by the private Asitra service.</span>
                </div>
              </div>
              <button className="settings-row" onClick={() => void exportData()}><Download size={18} /><span><strong>Download my data</strong><small>Export records, consent history and file manifest</small></span><ArrowRight size={16} /></button>
              <label className="settings-row"><Upload size={18} /><span><strong>Import backup</strong><small>Restore an Asitra JSON file</small></span><ArrowRight size={16} /><input type="file" accept=".json,application/json" onChange={importData} hidden /></label>
              <button className="settings-row" onClick={() => void openRecovery()}><RotateCcw size={18} /><span><strong>Recovery history</strong><small>Restore one of the last 20 saved versions</small></span><ArrowRight size={16} /></button>
              <button className="settings-row" onClick={resetData}><RotateCcw size={18} /><span><strong>Restore sample workspace</strong><small>Requires confirmation</small></span><ArrowRight size={16} /></button>
              <button className="settings-row" onClick={() => setPolicyOpen(true)}><ShieldCheck size={18} /><span><strong>Privacy and AI</strong><small>See how your journal, health and money data are used</small></span><ArrowRight size={16} /></button>
              <button className="settings-row" onClick={() => { setOnboardingStep(0); setOnboardingOpen(true); }}><Sparkles size={18} /><span><strong>Show getting-started tour</strong><small>See how capture, views and privacy work</small></span><ArrowRight size={16} /></button>
              <button className="settings-row logout-row" onClick={() => void logOut()}><LogOut size={18} /><span><strong>Log out</strong><small>End this Asitra session on this browser</small></span><ArrowRight size={16} /></button>
              <button className="settings-row danger-row" onClick={() => setDeleteAccountOpen(true)}><X size={18} /><span><strong>Delete account data</strong><small>Permanently remove records and uploaded photos</small></span><ArrowRight size={16} /></button>
            </section>
            <section className="panel settings-page-card">
              <div className="section-heading">
                <div><span className="eyebrow">Apple environment</span><h2>Connected capabilities</h2></div>
                <Activity size={20} />
              </div>
              <div className="capability-row"><span>Calendar and Reminders</span><strong>Native app</strong></div>
                  <div className="capability-row"><span>Health and wearables</span><strong>Native app</strong></div>
                  <div className="capability-row"><span>Screen Time</span><strong>Native app</strong></div>
                  <div className="capability-row"><span>Asitra AI</span><strong>{aiConsent ? "Terra allowed" : "Local only"}</strong></div>
                  <div className="capability-row"><span>Web account storage</span><strong>Connected</strong></div>
              <div className="native-note">
                <ShieldCheck size={17} />
                The interface is shared across devices. Apple-only integrations are collected by the native app and are not yet synchronized into the web store.
              </div>
            </section>
          </div>
        </div>
      );
    }

    return (
      <div className="page-shell today-page">
        <header className="finite-day-header">
          <div>
            <h1>Good {new Date().getHours() < 12 ? "morning" : new Date().getHours() < 18 ? "afternoon" : "evening"}, {userFirstName}.</h1>
            <p>Choose a day you can actually live.</p>
          </div>
          <div className="finite-date-control">
            <button className="icon-button" onClick={() => changeDay(-1)} aria-label="Previous day"><ChevronLeft size={18} /></button>
            <span><CalendarDays size={16} /> {longDate.format(selectedDate)}</span>
            <button className="icon-button" onClick={() => changeDay(1)} aria-label="Next day"><ChevronRight size={18} /></button>
          </div>
        </header>

        <div className="finite-day-layout">
          <section className="finite-commitments" aria-labelledby="today-commitments-title">
            <div className="finite-section-heading">
              <div>
                <span className="eyebrow">A realistic day</span>
                <h2 id="today-commitments-title">For today</h2>
              </div>
              <button className="later-count" onClick={() => setPriorityChooserOpen((open) => !open)}>
                Later {laterCommitments.length}
              </button>
            </div>

            <div className="commitment-list">
              {todayCommitments.map((item, index) => {
                const Icon = index === 0 ? Target : index === 1 ? HeartPulse : BookOpen;
                return (
                  <article className="commitment-row" key={item.id}>
                    <span className="commitment-icon"><Icon size={21} /></span>
                    <div>
                      <strong>{item.text}</strong>
                      <small><CalendarClock size={13} /> {item.plannedDate === localDateKey() ? "Today" : item.plannedDate || "Today"} · {taskTimeLabel(item)} · {item.listName}</small>
                    </div>
                    <div className="commitment-actions">
                      <button onClick={() => openTaskEditor(item.listId, item)} aria-label={`Edit ${item.text}`} title="Edit"><Pencil size={15} /></button>
                      <button onClick={() => postponeTask(item.listId, item)} aria-label={`Move ${item.text} to tomorrow`} title="Move to tomorrow"><CalendarClock size={15} /></button>
                      <button onClick={() => movePriorityToLater(item.id)} aria-label={`Move ${item.text} to Later`} title="Keep for later">Later</button>
                      <button className="delete" onClick={() => deleteTask(item.listId, item.id)} aria-label={`Delete ${item.text}`} title="Delete"><Trash2 size={15} /></button>
                    </div>
                    <button className="commitment-check" onClick={() => toggleListItem(item.listId, item.id)} aria-label={`Complete ${item.text}`}>
                      <Check size={17} />
                    </button>
                  </article>
                );
              })}
              {!todayCommitments.length && (
                <div className="finite-empty">
                  <CheckCircle2 size={24} />
                  <strong>Nothing is demanding your attention.</strong>
                  <span>Bring in only what genuinely matters today.</span>
                </div>
              )}
              {todayCommitments.length > 0 && Array.from({ length: 3 - todayCommitments.length }, (_, index) => (
                <button className="commitment-empty-slot" key={`priority-slot-${index}`} onClick={() => setPriorityChooserOpen(true)}>
                  <Plus size={16} /> Choose something important
                </button>
              ))}
            </div>

            <div className="tradeoff-row">
              <Sparkles size={18} />
              <span>{todayCommitments.length >= 3 ? "Something new means something else waits." : `You have room for ${3 - todayCommitments.length} more.`}</span>
              <button onClick={() => setPriorityChooserOpen((open) => !open)}>{priorityChooserOpen ? "Close" : "Choose"}</button>
            </div>

            {priorityChooserOpen && (
              <div className="later-picker">
                <div><strong>Later</strong><span>Move one out before bringing in a fourth.</span></div>
                {laterCommitments.slice(0, 6).map((item) => (
                  <button key={item.id} onClick={() => bringPriorityIntoToday(item.id)} disabled={todayCommitments.length >= 3}>
                    <span>{item.text}</span><small>{item.listName}</small><Plus size={15} />
                  </button>
                ))}
                {!laterCommitments.length && <small>Nothing is waiting.</small>}
              </div>
            )}

            <button className={`enough-button ${dayClosed ? "done" : ""}`} onClick={() => setDayClosed((closed) => !closed)}>
              <CheckCircle2 size={21} /> {dayClosed ? "Today is closed" : "This is enough for today"}
            </button>

            <form className="reflection-line" onSubmit={saveReflection}>
              <Brain size={20} />
              <label>
                <span>What did today teach you?</span>
                <input value={reflection} onChange={(event) => setReflection(event.target.value)} placeholder="A few honest words help tomorrow." />
              </label>
              <button disabled={!reflection.trim()} aria-label="Save reflection"><ArrowRight size={17} /></button>
            </form>
          </section>

          <aside className="daily-context-rail">
            <section className="context-section">
              <div className="context-title"><div><CalendarDays size={18} /><span>Coming up</span></div><small>{longDate.format(selectedDate)}</small></div>
              <div className="agenda-list">
                {dayEntries.slice().sort((a, b) => a.timestamp.localeCompare(b.timestamp)).slice(0, 4).map((entry) => (
                  <button key={entry.id} onClick={() => setEditingEntry(entry)}>
                    <time>{timeOnly.format(new Date(entry.timestamp))}</time>
                    <span style={{ background: kindMeta[entry.kind].color }} />
                    <strong>{entry.title}</strong>
                  </button>
                ))}
                {!dayEntries.length && <p>Nothing scheduled yet. Leave room on purpose.</p>}
              </div>
            </section>

            <section className="context-section money-glance">
              <div className="context-title"><div><WalletCards size={18} /><span>Money this cycle</span></div><button onClick={() => { setMoneyView("budget"); setSection("money"); }}>Open Money <ArrowRight size={14} /></button></div>
              <div className="money-glance-budget"><span>Budget remaining</span><strong>{currency.format(Math.max(financeViews.budgetRemaining, 0))}</strong></div>
              <div className="allocation-mini-grid">
                {[
                  ["Spend", monthSpent],
                  ["Save", monthSaved],
                  ["Invest", monthInvested],
                  ["Unassigned", Math.max(financeViews.unassigned, 0)],
                ].map(([label, value]) => (
                  <div key={String(label)}><span>{label}</span><strong>{monthIncome > 0 ? Math.round((Number(value) / monthIncome) * 100) : 0}%</strong></div>
                ))}
              </div>
              <div className="net-worth-line"><span>Net worth</span><strong>{currency.format(netWorth)}</strong></div>
            </section>
          </aside>
        </div>

        <form className="capture-card capture-dock" onSubmit={addCapture}>
          {suggested && (
            <div className="capture-review-strip">
              <span>Review before saving</span>
              <strong>{suggested.list ? `${suggested.list.target === "groceries" ? "Shopping" : suggested.list.target === "travel" ? "Travel ideas" : "Personal reminders"} list` : kindMeta[suggested.kind].label}</strong>
              <small>{suggested.title}</small>
              {suggested.amount ? <b>{currency.format(suggested.amount)}</b> : null}
            </div>
          )}
          <div className="capture-input-row">
            <div className="capture-tools">
              <button type="button" className={`tool-button ${isListening ? "recording" : ""}`} onClick={() => toggleListening("capture")} aria-label="Voice note"><Mic size={18} /></button>
              <label className="tool-button" aria-label="Add photo"><Camera size={18} /><input type="file" accept="image/jpeg,image/png,image/webp" onChange={attachPhoto} hidden /></label>
            </div>
            <textarea value={capture} onChange={(event) => setCapture(event.target.value)} placeholder="Tell Asitra what happened or what you need…" rows={1} />
            <button className="add-button" disabled={!capture.trim()} aria-label="Review and add"><ArrowRight size={17} /></button>
          </div>
          {capturePhoto && (
            <div className="photo-preview">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={capturePhoto} alt="Capture attachment preview" />
              <span>Photo attached</span>
              <button type="button" onClick={() => setCapturePhoto(undefined)}><X size={15} /></button>
            </div>
          )}
        </form>

        <details className="timeline-disclosure">
          <summary><span>Your day so far</span><small>{dayEntries.length} {dayEntries.length === 1 ? "moment" : "moments"}</small></summary>
          <div className="timeline">
            {dayEntries.length ? dayEntries.map((entry) => {
              const meta = kindMeta[entry.kind];
              const Icon = meta.icon;
              return (
                <article className="timeline-entry" key={entry.id}>
                  <time>{timeOnly.format(new Date(entry.timestamp))}</time>
                  <span className="timeline-node" style={{ color: meta.color }}><Icon size={17} /></span>
                  <div className="entry-card">
                    <div><span className="entry-kind" style={{ color: meta.color }}>{meta.label}</span><strong>{entry.title}</strong></div>
                    {entry.amount && <b>{currency.format(entry.amount)}</b>}
                    <button className="icon-button" onClick={() => setEditingEntry(entry)} aria-label={`Edit ${entry.title}`}><MoreHorizontal size={18} /></button>
                  </div>
                </article>
              );
            }) : <div className="empty-timeline"><Clock3 size={23} /><strong>No moments recorded yet</strong><span>Your next entry will appear here.</span></div>}
          </div>
        </details>
      </div>
    );
  })();

  return (
    <div className="app-frame">
      <aside className={`sidebar ${mobileMenu ? "open" : ""}`}>
        <div className="brand">
          <span className="brand-mark">A</span>
          <div><strong>Asitra</strong><small>Your everyday assistant</small></div>
          <button className="mobile-close" onClick={() => setMobileMenu(false)} aria-label="Close navigation"><X size={20} /></button>
        </div>
        <nav>
          {navItems.map((item) => {
            const Icon = item.icon;
            return (
              <button
                key={item.id}
                className={section === item.id ? "active" : ""}
                onClick={() => {
                  setSection(item.id);
                  if (item.id === "today") setSelectedDate(new Date());
                  setMobileMenu(false);
                }}
              >
                <Icon size={19} />
                <span>{item.label}</span>
                {item.id === "lists" && openItems > 0 && <i>{openItems}</i>}
              </button>
            );
          })}
        </nav>
        <div className="sidebar-bottom">
          <div className="sync-state"><span /><div><strong>Saved securely</strong><small>Private to your account</small></div></div>
          <span className="release-label sidebar-release">{ASITRA_RELEASE_LABEL}</span>
        </div>
      </aside>
      {mobileMenu && <button className="scrim" onClick={() => setMobileMenu(false)} aria-label="Close menu" />}
      <main>
        <header className="topbar">
          <button className="menu-button" onClick={() => setMobileMenu(true)} aria-label="Open navigation"><Menu size={21} /></button>
          <div className="mobile-brand"><span className="brand-mark small">A</span><strong>Asitra</strong></div>
          <button className="search-button" onClick={() => setSearchOpen(true)}><Search size={17} /><span>Search your life</span><kbd>⌘ K</kbd></button>
          <div className="account-menu-wrap">
            <button
              className="avatar"
              aria-label={`Account menu for ${userName}`}
              aria-haspopup="menu"
              aria-expanded={accountMenuOpen}
              title={userName}
              onClick={() => setAccountMenuOpen((open) => !open)}
            >
              {accountInitials}
            </button>
            {accountMenuOpen && (
              <>
                <button className="account-menu-backdrop" onClick={() => setAccountMenuOpen(false)} aria-label="Close account menu" />
                <div className="account-menu" role="menu">
                  <div><span>Signed in as</span><strong>{userName}</strong></div>
                  <button type="button" onClick={() => void logOut()} role="menuitem"><LogOut size={16} /> Log out</button>
                </div>
              </>
            )}
          </div>
        </header>
        {mainContent}
      </main>
      <button type="button" className="assistant-fab" aria-haspopup="dialog" aria-expanded={assistantOpen} onClick={() => openAssistant()}>
        <Sparkles size={18} /><span>Ask Asitra</span>
      </button>
      {onboardingOpen && (() => {
        const step = onboardingSteps[onboardingStep];
        const StepIcon = step.icon;
        const isLastStep = onboardingStep === onboardingSteps.length - 1;
        return (
          <div className="modal-layer onboarding-layer" role="dialog" aria-modal="true" aria-label="Welcome to Asitra">
            <div className="onboarding-card">
              <div className="onboarding-progress" aria-label={`Step ${onboardingStep + 1} of ${onboardingSteps.length}`}>
                {onboardingSteps.map((item, index) => <span key={item.title} className={index <= onboardingStep ? "active" : ""} />)}
              </div>
              <div className="onboarding-icon"><StepIcon size={27} /></div>
              <span className="eyebrow">{step.eyebrow}</span>
              <h2>{onboardingStep === 0 ? `Welcome${userName ? `, ${userName.split(/[ @]/)[0]}` : ""}` : step.title}</h2>
              {onboardingStep === 0 && <h3>{step.title}</h3>}
              <p>{step.body}</p>
              <div className="onboarding-example">{step.example}</div>
              <div className="onboarding-actions">
                {onboardingStep > 0 ? (
                  <button className="text-button" onClick={() => setOnboardingStep((current) => current - 1)}>Back</button>
                ) : (
                  <button className="text-button" onClick={finishOnboarding}>Explore myself</button>
                )}
                <button className="primary-button" onClick={() => isLastStep ? finishOnboarding() : setOnboardingStep((current) => current + 1)}>
                  {isLastStep ? "Start using Asitra" : "Continue"} <ArrowRight size={16} />
                </button>
              </div>
            </div>
          </div>
        );
      })()}
      {notice && (
        <div className="toast">
          <CheckCircle2 size={18} />
          <span>{notice}</span>
          <button onClick={() => setNotice(undefined)}><X size={15} /></button>
        </div>
      )}
      {searchOpen && (
        <div className="modal-layer" role="dialog" aria-modal="true" aria-label="Search your life">
          <button className="modal-backdrop" onClick={() => setSearchOpen(false)} aria-label="Close search" />
          <section className="search-modal">
            <div className="search-input-row"><Search size={19} /><input autoFocus value={searchQuery} onChange={(event) => setSearchQuery(event.target.value)} placeholder="Search entries and lists…" /><button className="icon-button" onClick={() => setSearchOpen(false)} aria-label="Close"><X size={18} /></button></div>
            <div className="search-results">
              {!normalizedSearch && <p>Type a word, person, place or category.</p>}
              {normalizedSearch && searchResults.length === 0 && <p>No matching records.</p>}
              {searchResults.map((result) => (
                <button key={`${result.section}-${result.id}`} onClick={() => {
                  setSection(result.section);
                  if ("date" in result && result.date) setSelectedDate(new Date(result.date));
                  if ("listId" in result && result.listId) setSelectedListId(result.listId);
                  setSearchOpen(false);
                }}><span><strong>{result.label}</strong><small>{result.detail}</small></span><ArrowRight size={16} /></button>
              ))}
            </div>
          </section>
        </div>
      )}
      {assistantOpen && (
        <div className="modal-layer assistant-layer" role="dialog" aria-modal="true" aria-label="Ask Asitra">
          <button className="modal-backdrop" onClick={() => setAssistantOpen(false)} aria-label="Close assistant" />
          <section className="assistant-sheet">
            <header>
              <div className="assistant-title"><span><Sparkles size={18} /></span><div><strong>Asitra</strong><small><i /> Private data assistant</small></div></div>
              <div className="assistant-header-actions">
                <div className="model-picker" aria-label="AI model">
                  <span>Model</span>
                  <strong>{aiConsent ? `${aiContract.profile} · ${aiContract.label}` : "Local insights"}</strong>
                </div>
                <button className="assistant-close" onClick={() => setAssistantOpen(false)} aria-label="Close assistant"><X size={19} /></button>
              </div>
            </header>
            <div className="chat-scroll">
              {messages.map((message) => (
                <div className={`message ${message.role}`} key={message.id}>
                  {message.role === "assistant" && <span><Sparkles size={15} /></span>}
                  <p>{message.text}</p>
                </div>
              ))}
              {assistantThinking && (
                <div className="message thinking">
                  <span><Sparkles size={15} /></span>
                  <p><i /><i /><i /><small>{aiContract.label} is thinking</small></p>
                </div>
              )}
              {messages.length === 1 && (
                <div className="prompt-grid">
                  {[
                    ["My day", "Tell me about today"],
                    ["Patterns", "What stands out this week?"],
                    ["Money", "How is my budget?"],
                    ["Balance", "How is my work-life balance?"],
                  ].map(([label, prompt]) => (
                    <button key={label} onClick={() => sendMessage(prompt)}><strong>{label}</strong><span>{prompt}</span></button>
                  ))}
                </div>
              )}
            </div>
            <label className="ai-consent-row">
              <input type="checkbox" checked={aiConsent} onChange={(event) => void updateAIConsent(event.target.checked)} />
              <span><strong>Allow AI analysis</strong><small>Send the question and relevant recent Asitra records to OpenAI. Turn this off to use local insights only.</small></span>
            </label>
            <div className="privacy-line"><Lock size={13} /> Your key stays on the server. Requests use no-store processing and are limited to 20 per hour.</div>
            <form className="chat-composer" onSubmit={(event) => { event.preventDefault(); sendMessage(); }}>
              <textarea
                value={chatInput}
                onChange={(event) => setChatInput(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Enter" && !event.shiftKey) {
                    event.preventDefault();
                    if (chatInput.trim() && !assistantThinking) sendMessage();
                  }
                }}
                placeholder="Ask about your day…"
                rows={1}
              />
              <button
                type="button"
                className={isListening ? "recording" : ""}
                onClick={() => toggleListening("chat")}
                aria-label={isListening ? "Stop voice input" : "Start voice input"}
              >
                <Mic size={17} />
              </button>
              <button
                type="submit"
                className="send-button"
                aria-label="Send message"
                disabled={!chatInput.trim() || assistantThinking}
              >
                <Send size={16} />
              </button>
            </form>
          </section>
        </div>
      )}
      {columnEditor && (
        <div className="modal-layer" role="dialog" aria-modal="true" aria-label={columnEditor.id ? "Rename task column" : "Add task column"}>
          <button className="modal-backdrop" onClick={() => setColumnEditor(undefined)} aria-label="Close column editor" />
          <form className="edit-modal column-editor-modal" onSubmit={saveTaskColumn}>
            <div className="section-heading"><div><span className="eyebrow">Your workflow</span><h2>{columnEditor.id ? "Rename column" : "Add a column"}</h2></div><button type="button" className="icon-button" onClick={() => setColumnEditor(undefined)} aria-label="Close"><X size={18} /></button></div>
            <label>Column name<input autoFocus value={columnEditor.name} onChange={(event) => setColumnEditor({ ...columnEditor, name: event.target.value })} placeholder="For example: Waiting" /></label>
            <p className="editor-help">A new column becomes another stage between capturing a task and finishing it.</p>
            <div className="modal-actions"><span /><button className="primary-button" disabled={!columnEditor.name.trim()}>{columnEditor.id ? "Save name" : "Add column"}</button></div>
          </form>
        </div>
      )}
      {taskEditor && (
        <div className="modal-layer" role="dialog" aria-modal="true" aria-label="Edit task">
          <button className="modal-backdrop" onClick={() => setTaskEditor(undefined)} aria-label="Close task editor" />
          <form className="edit-modal task-editor-modal" onSubmit={saveTaskEditor}>
            <div className="section-heading"><div><span className="eyebrow">One task, updated everywhere</span><h2>Edit task</h2></div><button type="button" className="icon-button" onClick={() => setTaskEditor(undefined)} aria-label="Close"><X size={18} /></button></div>
            <label>What matters?<input autoFocus value={taskEditor.text} onChange={(event) => setTaskEditor({ ...taskEditor, text: event.target.value })} /></label>
            <div className="task-editor-priority">
              <button type="button" className={taskEditor.important ? "active important" : ""} onClick={() => setTaskEditor({ ...taskEditor, important: !taskEditor.important })} aria-pressed={taskEditor.important}><Flag size={14} /> Important</button>
              <button type="button" className={taskEditor.urgent ? "active urgent" : ""} onClick={() => setTaskEditor({ ...taskEditor, urgent: !taskEditor.urgent })} aria-pressed={taskEditor.urgent}><Zap size={14} /> Urgent</button>
            </div>
            <label>Board column<select value={taskEditor.boardColumnId} onChange={(event) => setTaskEditor({ ...taskEditor, boardColumnId: event.target.value })}>{taskColumns.map((column) => <option key={column.id} value={column.id}>{column.name}</option>)}</select></label>
            <label>Planned date<input type="date" value={taskEditor.plannedDate} onChange={(event) => setTaskEditor({ ...taskEditor, plannedDate: event.target.value })} /></label>
            <label>Time planning<select value={taskEditor.planMode} onChange={(event) => setTaskEditor({ ...taskEditor, planMode: event.target.value as TaskEditorDraft["planMode"] })}><option value="anytime">Anytime that day</option><option value="exact">Exact time block</option><option value="window">Flexible time window</option></select></label>
            {taskEditor.planMode !== "anytime" && (
              <div className="money-form-row">
                <label>{taskEditor.planMode === "exact" ? "Start" : "Window starts"}<input type="time" value={taskEditor.startTime} onChange={(event) => setTaskEditor({ ...taskEditor, startTime: event.target.value })} /></label>
                <label>{taskEditor.planMode === "exact" ? "End" : "Window ends"}<input type="time" value={taskEditor.endTime} onChange={(event) => setTaskEditor({ ...taskEditor, endTime: event.target.value })} /></label>
              </div>
            )}
            {taskEditor.planMode === "window" && <label>Estimated duration in minutes<input type="number" min="1" max="10080" step="5" value={taskEditor.durationMinutes} onChange={(event) => setTaskEditor({ ...taskEditor, durationMinutes: event.target.value })} /></label>}
            <p className="editor-help">Exact blocks reserve the full start–end period. Flexible windows keep the task movable inside the window while preserving its estimated duration.</p>
            <div className="task-editor-shortcuts">
              <button type="button" onClick={() => setTaskEditor({ ...taskEditor, planMode: "window", startTime: "06:00", endTime: "12:00" })}>Morning</button>
              <button type="button" onClick={() => setTaskEditor({ ...taskEditor, planMode: "window", startTime: "12:00", endTime: "17:00" })}>Afternoon</button>
              <button type="button" onClick={() => setTaskEditor({ ...taskEditor, planMode: "window", startTime: "17:00", endTime: "22:00" })}>Evening</button>
              <button type="button" onClick={() => setTaskEditor({ ...taskEditor, planMode: "anytime" })}>Anytime</button>
            </div>
            <div className="modal-actions"><button type="button" className="danger-button" onClick={() => deleteTask(taskEditor.listId, taskEditor.itemId)}>Delete</button><div><button type="button" className="secondary-button" onClick={() => { const list = state.lists.find((item) => item.id === taskEditor.listId); const item = list?.items.find((entry) => entry.id === taskEditor.itemId); if (item) postponeTask(taskEditor.listId, item); setTaskEditor(undefined); }}>Tomorrow</button><button className="primary-button" disabled={!taskEditor.text.trim()}>Save changes</button></div></div>
          </form>
        </div>
      )}
      {editingEntry && (
        <div className="modal-layer" role="dialog" aria-modal="true" aria-label="Edit timeline entry">
          <button className="modal-backdrop" onClick={() => setEditingEntry(undefined)} aria-label="Close editor" />
          <form className="edit-modal" onSubmit={saveEditedEntry}>
            <div className="section-heading"><div><span className="eyebrow">One object · every view</span><h2>Edit entry</h2></div><button type="button" className="icon-button" onClick={() => setEditingEntry(undefined)}><X size={18} /></button></div>
            <p className="editor-help">Every entry can be edited, deleted, or placed in time. Its type adds only the fields and actions that make sense.</p>
            <label>Title<input value={editingEntry.title} onChange={(event) => setEditingEntry({ ...editingEntry, title: event.target.value })} /></label>
            <label>Category<select value={editingEntry.kind} onChange={(event) => setEditingEntry({ ...editingEntry, kind: event.target.value as EntryKind })}>{Object.entries(kindMeta).map(([kind, meta]) => <option key={kind} value={kind}>{meta.label}</option>)}</select></label>
            <div className="entry-time-editor">
              <label>Starts or happened at<input type="datetime-local" value={datetimeLocalValue(editingEntry.timestamp)} onChange={(event) => setEditingEntry({ ...editingEntry, timestamp: new Date(event.target.value).toISOString() })} /></label>
              {editingEntry.endTimestamp ? (
                <><label>Ends<input type="datetime-local" min={datetimeLocalValue(editingEntry.timestamp)} value={datetimeLocalValue(editingEntry.endTimestamp)} onChange={(event) => setEditingEntry({ ...editingEntry, endTimestamp: new Date(event.target.value).toISOString() })} /></label><button type="button" className="text-button" onClick={() => setEditingEntry({ ...editingEntry, endTimestamp: undefined })}>Use one moment</button></>
              ) : (
                <button type="button" className="secondary-button" onClick={() => setEditingEntry({ ...editingEntry, endTimestamp: new Date(new Date(editingEntry.timestamp).getTime() + Math.max(editingEntry.minutes ?? 60, 15) * 60_000).toISOString() })}><Clock3 size={15} /> Add an end time</button>
              )}
            </div>
            {editingCapabilities?.completable && <label className="entry-toggle"><input type="checkbox" checked={editingEntry.completed ?? false} onChange={(event) => setEditingEntry({ ...editingEntry, completed: event.target.checked })} /><span><strong>Completed</strong><small>This updates Today and the linked list.</small></span></label>}
            {editingCapabilities?.usesAmount && <label>Amount in EUR<input type="number" min="0" step="0.01" value={editingEntry.amount ?? ""} onChange={(event) => setEditingEntry({ ...editingEntry, amount: event.target.value ? Number(event.target.value) : undefined })} /></label>}
            {editingCapabilities?.canLinkTrip && !!state.trips.length && <label>Trip plan<select value={editingEntry.tripId ?? ""} onChange={(event) => setEditingEntry({ ...editingEntry, tripId: event.target.value || undefined })}><option value="">Not linked to a trip</option>{state.trips.map((trip) => <option key={trip.id} value={trip.id}>{trip.name} · {trip.destination}</option>)}</select></label>}
            {editingCapabilities?.usesDuration && <label>Duration in minutes<input type="number" min="0" step="1" value={editingEntry.minutes ?? ""} onChange={(event) => setEditingEntry({ ...editingEntry, minutes: event.target.value ? Number(event.target.value) : undefined })} /></label>}
            {editingCapabilities?.usesStatus && <label>Status<select value={editingEntry.status ?? "planned"} onChange={(event) => setEditingEntry({ ...editingEntry, status: event.target.value as Entry["status"] })}><option value="planned">Want to</option><option value="inProgress">In progress</option><option value="completed">Completed</option></select></label>}
            <label>Note<textarea value={editingEntry.note ?? ""} onChange={(event) => setEditingEntry({ ...editingEntry, note: event.target.value })} rows={3} /></label>
            <div className="modal-actions"><button type="button" className="danger-button" onClick={deleteEditedEntry}>Delete</button><button className="primary-button" disabled={!editingEntry.title.trim()}>Save changes</button></div>
          </form>
        </div>
      )}
      {policyOpen && (
        <div className="modal-layer" role="dialog" aria-modal="true" aria-label="Privacy and AI">
          <button className="modal-backdrop" onClick={() => setPolicyOpen(false)} aria-label="Close privacy information" />
          <section className="policy-modal">
            <div className="section-heading"><div><span className="eyebrow">Your control</span><h2>Privacy and AI</h2></div><button className="icon-button" onClick={() => setPolicyOpen(false)} aria-label="Close"><X size={18} /></button></div>
            <p>Your account records are stored privately for Asitra’s timeline, lists, trackers and money views. Pictures, PDFs and voice notes are private and require your signed-in account.</p>
            <p>AI is optional. When enabled, Asitra sends your question and a limited selection of relevant records from the last 90 days to OpenAI to answer it. Asitra requests no-store processing and never puts the API key in your browser.</p>
            <p>Health and financial information is shown for personal organization, not medical, tax, investment or accounting advice. You can export your data or permanently delete it at any time.</p>
            <p><strong>Launch policy version:</strong> 3 August 2026. Contact: ganatra.dev@gmail.com</p>
            <p><a href="/privacy">Read the complete privacy policy</a></p>
          </section>
        </div>
      )}
      {recoveryOpen && (
        <div className="modal-layer" role="dialog" aria-modal="true" aria-label="Recovery history">
          <button className="modal-backdrop" onClick={() => setRecoveryOpen(false)} aria-label="Close recovery history" />
          <section className="edit-modal recovery-modal">
            <div className="section-heading"><div><span className="eyebrow">Protected history</span><h2>Recovery points</h2></div><button className="icon-button" onClick={() => setRecoveryOpen(false)} aria-label="Close"><X size={18} /></button></div>
            <p>Asitra keeps up to 20 recent versions. Restoring never removes your current version—it becomes a new recovery point first.</p>
            <div className="recovery-list">
              {recoveryPoints.length === 0 && <p>No earlier recovery points are available yet.</p>}
              {recoveryPoints.map((point) => (
                <button key={point.id} onClick={() => void restoreRecoveryPoint(point.id)}>
                  <span><strong>{new Date(point.createdAt).toLocaleString()}</strong><small>Saved version {point.version}</small></span>
                  <RotateCcw size={17} />
                </button>
              ))}
            </div>
          </section>
        </div>
      )}
      {deleteAccountOpen && (
        <div className="modal-layer" role="dialog" aria-modal="true" aria-label="Delete account data">
          <button className="modal-backdrop" onClick={() => setDeleteAccountOpen(false)} aria-label="Cancel account deletion" />
          <section className="edit-modal">
            <div className="section-heading"><div><span className="eyebrow">Permanent action</span><h2>Delete account data</h2></div><button className="icon-button" onClick={() => setDeleteAccountOpen(false)} aria-label="Close"><X size={18} /></button></div>
            <p>This removes your timeline, lists, trackers, financial records, sessions and uploaded photos. Export a backup first if needed.</p>
            <label>Type DELETE MY ACCOUNT<input value={deleteConfirmation} onChange={(event) => setDeleteConfirmation(event.target.value)} /></label>
            <button className="danger-button" disabled={deleteConfirmation !== "DELETE MY ACCOUNT"} onClick={() => void deleteAccount()}>Permanently delete my data</button>
          </section>
        </div>
      )}
      {sharingOpen && (
        <div className="modal-layer" role="dialog" aria-modal="true" aria-label="Shared list access">
          <button className="modal-backdrop" onClick={() => setSharingOpen(false)} aria-label="Close sharing" />
          <section className="edit-modal">
            <div className="section-heading"><div><span className="eyebrow">Shared lists</span><h2>{inviteCode === "MEMBER" ? "Shared access" : inviteCode ? "Invite people" : "Join a list"}</h2></div><button className="icon-button" onClick={() => setSharingOpen(false)} aria-label="Close"><X size={18} /></button></div>
            {inviteCode === "MEMBER" ? (
              <>
                <p>You can add and complete items on this shared list. Only its owner can create invitations or stop sharing it.</p>
                <button className="danger-button" onClick={() => void stopSharing()}>Leave shared list</button>
              </>
            ) : inviteCode ? (
              <>
                <p>Send this one-time code to one person. It expires in seven days and disappears after it is used.</p>
                <div className="invite-code">{inviteCode}</div>
                <button className="secondary-button" onClick={() => void navigator.clipboard.writeText(inviteCode)}>Copy invite code</button>
                {selectedList?.shared && sharingOwner && <button className="danger-button" onClick={() => void stopSharing()}>Stop sharing</button>}
              </>
            ) : (
              <>
                <p>Paste the private invite code sent by the list owner.</p>
                <label>Invite code<input value={joinCode} onChange={(event) => setJoinCode(event.target.value.toUpperCase().replace(/[^A-Z2-9]/g, "").slice(0, 20))} /></label>
                <button className="primary-button" disabled={joinCode.length !== 20} onClick={() => void joinSharedList()}>Join shared list</button>
              </>
            )}
          </section>
        </div>
      )}
      {moneyEntryOpen && (
        <div className="modal-layer" role="dialog" aria-modal="true" aria-label="Add money">
          <button className="modal-backdrop" onClick={() => { setMoneyEntryOpen(false); setEditingMoneyRecord(undefined); }} aria-label="Close money entry" />
          <section className="money-entry-modal">
            <div className="section-heading">
              <div><span className="eyebrow">One money ledger</span><h2>{editingMoneyRecord ? "Edit money activity" : "Add money activity"}</h2></div>
              <button type="button" className="icon-button" onClick={() => { setMoneyEntryOpen(false); setEditingMoneyRecord(undefined); }} aria-label="Close"><X size={18} /></button>
            </div>
            {!editingMoneyRecord && <div className="money-entry-tabs" role="tablist" aria-label="Money entry method">
              <button className={moneyEntryMode === "asitra" ? "active" : ""} onClick={() => { setMoneyEntryMode("asitra"); setMoneyReview(undefined); }}>Tell Asitra</button>
              <button className={moneyEntryMode === "type" ? "active" : ""} onClick={() => setMoneyEntryMode("type")}>Guided</button>
              <button className={moneyEntryMode === "pdf" ? "active" : ""} onClick={() => setMoneyEntryMode("pdf")}>Statement</button>
            </div>}
            {moneyEntryMode === "type" && (
              <form className="money-entry-form" onSubmit={submitMoneyDraft}>
                <label>What changed?<select value={moneyDraft.kind} onChange={(event) => { const kind = event.target.value as MoneyDraft["kind"]; setMoneyDraft({ ...moneyDraft, kind, balanceCategory: kind === "liability" ? "creditCard" : moneyDraft.balanceCategory, tripId: kind === "expense" ? moneyDraft.tripId : undefined }); }}><option value="expense">I spent money</option><option value="income">I received money</option><option value="saving">I set money aside</option><option value="investment">I invested money</option><option value="asset">An asset balance changed</option><option value="liability">A debt balance changed</option></select></label>
                <div className="money-form-row">
                  <label>Amount (€)<input autoFocus inputMode="decimal" value={moneyDraft.amount} onChange={(event) => setMoneyDraft({ ...moneyDraft, amount: event.target.value })} placeholder="0.00" /></label>
                  <label>Date<input type="date" value={moneyDraft.date} onChange={(event) => setMoneyDraft({ ...moneyDraft, date: event.target.value })} /></label>
                </div>
                {(moneyDraft.kind === "asset" || moneyDraft.kind === "liability") && <label>Balance type<select value={moneyDraft.balanceCategory} onChange={(event) => setMoneyDraft({ ...moneyDraft, balanceCategory: event.target.value as BalanceSheetCategory })}>{moneyDraft.kind === "asset" ? <><option value="cash">Cash &amp; bank</option><option value="investments">Investments</option><option value="property">Property &amp; valuables</option><option value="otherAsset">Other asset</option></> : <><option value="creditCard">Credit card</option><option value="loan">Loan</option><option value="otherLiability">Other debt</option></>}</select></label>}
                {moneyDraft.kind === "expense" && !!state.trips.length && <label>Trip plan<select value={moneyDraft.tripId ?? ""} onChange={(event) => setMoneyDraft({ ...moneyDraft, tripId: event.target.value || undefined })}><option value="">Not linked to a trip</option>{state.trips.map((trip) => <option value={trip.id} key={trip.id}>{trip.name} · {trip.destination}</option>)}</select></label>}
                <label>{moneyDraft.kind === "income" ? "Source" : moneyDraft.kind === "asset" || moneyDraft.kind === "liability" ? "Account or balance name" : "What was it for?"}<input value={moneyDraft.note} onChange={(event) => setMoneyDraft({ ...moneyDraft, note: event.target.value })} placeholder={moneyDraft.kind === "income" ? "Salary, freelance…" : moneyDraft.kind === "asset" ? "Main bank account…" : moneyDraft.kind === "liability" ? "Credit card…" : "Groceries, rent…"} /></label>
                <div className="modal-actions">
                  {editingMoneyRecord ? <button type="button" className="danger-button" onClick={() => deleteMoneyActivity(editingMoneyRecord)}>Delete</button> : <span />}
                  <button className="primary-button" disabled={!moneyDraft.amount.trim()}>{editingMoneyRecord || moneyDraft.existingBalanceID ? "Save changes" : "Add once"}</button>
                </div>
              </form>
            )}
            {moneyEntryMode === "asitra" && (
              <form className="money-asitra-form" onSubmit={submitMoneyInstruction}>
                {!moneyReview ? <>
                  <div className="asitra-entry-prompt"><Sparkles size={18} /><div><strong>Say it your way</strong><span>Finance rules classify clear entries locally. Terra helps only when the meaning is ambiguous.</span></div></div>
                  <textarea autoFocus rows={4} value={moneyInstruction} onChange={(event) => setMoneyInstruction(event.target.value)} placeholder="Paid €24.50 for groceries yesterday, or my savings account balance is €8,400" />
                  {parseMoneyInstruction(moneyInstruction) && <div className="money-parse-preview"><CheckCircle2 size={16} /><span>Ready to review · {currency.format(parseMoneyInstruction(moneyInstruction)!.amount)} · {parseMoneyInstruction(moneyInstruction)!.kind}</span></div>}
                  <button className="primary-button" disabled={!moneyInstruction.trim() || moneyClassifying}>{moneyClassifying ? "Understanding…" : "Review entry"}</button>
                </> : <div className="money-review-card">
                  <span className="eyebrow">Check before saving</span>
                  <div className="money-review-amount">{currency.format(moneyReview.amount)}</div>
                  <div className="money-review-grid"><span>Type<strong>{moneyReview.kind}</strong></span><span>Date<strong>{new Date(moneyReview.date).toLocaleDateString()}</strong></span></div>
                  <p>{moneyReview.title}</p>
                  <small>This one record will feed every relevant money view. Asitra never lets the model calculate your totals.</small>
                  <div className="money-review-actions"><button type="button" className="secondary-button" onClick={() => setMoneyReview(undefined)}>Edit</button><button type="button" className="primary-button" onClick={confirmMoneyReview}>Confirm &amp; add once</button></div>
                </div>}
              </form>
            )}
            {moneyEntryMode === "pdf" && (
              <div className="pdf-import-panel">
                {!importedTransactions.length && (
                  <label className="pdf-dropzone">
                    <FileText size={28} />
                    <strong>{importReading ? "Reading your statement…" : "Choose a monthly statement PDF"}</strong>
                    <span>The PDF is read on this device. Review every detected row before anything is saved.</span>
                    <input type="file" accept="application/pdf,.pdf" onChange={readStatementPdf} disabled={importReading} />
                  </label>
                )}
                {!!importedTransactions.length && (
                  <>
                    <div className="pdf-review-heading"><div><strong>{importFileName}</strong><span>{importedTransactions.filter((item) => item.selected).length} of {importedTransactions.length} selected</span></div><label className="pdf-replace"><FileText size={15} /> Choose another<input type="file" accept="application/pdf,.pdf" onChange={readStatementPdf} /></label></div>
                    <div className="pdf-transaction-list">
                      {importedTransactions.map((transaction) => (
                        <label className="pdf-transaction" key={transaction.id}>
                          <input type="checkbox" checked={transaction.selected} onChange={() => setImportedTransactions((current) => current.map((item) => item.id === transaction.id ? { ...item, selected: !item.selected } : item))} />
                          <span><strong>{transaction.title}</strong><small>{new Date(transaction.date).toLocaleDateString()} · {transaction.kind}</small></span>
                          <b className={transaction.kind === "income" ? "positive" : ""}>{transaction.kind === "income" ? "+" : "−"}{currency.format(transaction.amount)}</b>
                        </label>
                      ))}
                    </div>
                    <button className="primary-button full" onClick={commitStatementImport}>Import selected entries</button>
                  </>
                )}
              </div>
            )}
          </section>
        </div>
      )}
      {tripDraft && (
        <div className="modal-layer" role="dialog" aria-modal="true" aria-label={tripDraft.id ? "Edit trip plan" : "Plan a trip"}>
          <button className="modal-backdrop" onClick={() => setTripDraft(undefined)} aria-label="Close trip planner" />
          <section className="trip-editor-modal">
            <div className="section-heading">
              <div><span className="eyebrow">One travel budget</span><h2>{tripDraft.id ? "Edit trip plan" : "Plan a trip"}</h2></div>
              <button type="button" className="icon-button" onClick={() => setTripDraft(undefined)} aria-label="Close"><X size={18} /></button>
            </div>
            <p>Choose the total once. Linked expenses will update the trip and your normal money views together.</p>
            <form className="money-entry-form" onSubmit={submitTrip}>
              <label>Trip name<input autoFocus value={tripDraft.name} onChange={(event) => setTripDraft({ ...tripDraft, name: event.target.value })} placeholder="Heidelberg weekend" /></label>
              <label>Destination<input value={tripDraft.destination} onChange={(event) => setTripDraft({ ...tripDraft, destination: event.target.value })} placeholder="Heidelberg, Germany" /></label>
              <label>Total budget (€)<input inputMode="decimal" value={tripDraft.budget} onChange={(event) => setTripDraft({ ...tripDraft, budget: event.target.value })} placeholder="350" /></label>
              <div className="money-form-row">
                <label>Starts<input type="date" value={tripDraft.startDate} onChange={(event) => setTripDraft({ ...tripDraft, startDate: event.target.value, endDate: event.target.value > tripDraft.endDate ? event.target.value : tripDraft.endDate })} /></label>
                <label>Ends<input type="date" min={tripDraft.startDate} value={tripDraft.endDate} onChange={(event) => setTripDraft({ ...tripDraft, endDate: event.target.value })} /></label>
              </div>
              <div className="modal-actions">
                {tripDraft.id ? <button type="button" className="danger-button" onClick={() => { const trip = state.trips.find((item) => item.id === tripDraft.id); if (trip) deleteTrip(trip); }}>Delete trip</button> : <span />}
                <button className="primary-button" disabled={!tripDraft.name.trim() || !tripDraft.destination.trim() || !tripDraft.budget.trim()}>{tripDraft.id ? "Save changes" : "Create trip plan"}</button>
              </div>
            </form>
          </section>
        </div>
      )}
    </div>
  );
}

function PageHeader({
  eyebrow,
  title,
  description,
  action,
}: {
  eyebrow: string;
  title: string;
  description: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="page-header">
      <div>
        <span className="eyebrow">{eyebrow}</span>
        <h1>{title}</h1>
        <p>{description}</p>
      </div>
      {action}
    </div>
  );
}
