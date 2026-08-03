"use client";

import {
  Activity,
  ArrowRight,
  BarChart3,
  BookOpen,
  Brain,
  CalendarDays,
  Camera,
  Check,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  CircleDollarSign,
  Clock3,
  Download,
  FileText,
  Film,
  HeartPulse,
  Home,
  ListChecks,
  Lock,
  Menu,
  Mic,
  Moon,
  MoreHorizontal,
  Plus,
  RotateCcw,
  Search,
  Send,
  Settings,
  ShieldCheck,
  Sparkles,
  Target,
  Upload,
  Users,
  WalletCards,
  X,
  Zap,
} from "lucide-react";
import { SAKHYA_AI_CONTRACT, type SakhyaAIContract } from "./ai-contract";
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
import { validatePersistedState } from "./state-schema";

type Section = "today" | "lists" | "track" | "money" | "balance" | "settings";
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
};

type ListItem = {
  id: string;
  text: string;
  done: boolean;
  due?: string;
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
};

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
  entries: Entry[];
  lists: LifeList[];
  trackers: Tracker[];
  monthlyBudget: number;
  savingsTarget: number;
  savingsCurrent: number;
  moneyEntries: MoneyEntry[];
  balanceSheetItems: BalanceSheetItem[];
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
const currency = new Intl.NumberFormat("de-DE", { style: "currency", currency: "EUR" });
const weekdayOnly = new Intl.DateTimeFormat("en", { weekday: "short" });
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

const seedState: PersistedState = {
  entries: [
    { id: "e1", title: "Morning walk by the river", kind: "movement", timestamp: atDayOffset(0, 7, 35), minutes: 32, source: "WHOOP" },
    { id: "e2", title: "Deep work · product strategy", kind: "work", timestamp: atDayOffset(0, 9, 10), minutes: 95 },
    { id: "e3", title: "Coffee and groceries", kind: "expense", timestamp: atDayOffset(0, 11, 42), amount: 28.4 },
    { id: "e4", title: "Lunch · lentil bowl", kind: "food", timestamp: atDayOffset(0, 12, 35) },
    { id: "e5", title: "Read Atomic Habits", kind: "book", timestamp: atDayOffset(-1, 21, 5), minutes: 24 },
    { id: "e6", title: "Felt calm after an evening without screens", kind: "mindset", timestamp: atDayOffset(-1, 21, 40) },
    { id: "e7", title: "Dinner with friends", kind: "expense", timestamp: atDayOffset(-2, 19, 15), amount: 46.2 },
    { id: "e8", title: "Strength training", kind: "movement", timestamp: atDayOffset(-2, 17, 50), minutes: 48, source: "WHOOP" },
    { id: "e9", title: "Slept well", kind: "sleep", timestamp: atDayOffset(-3, 7, 0), minutes: 448, source: "WHOOP" },
    { id: "e10", title: "Monthly train pass", kind: "expense", timestamp: atDayOffset(-4, 8, 5), amount: 59 },
  ],
  lists: [
    {
      id: "l1",
      name: "Home groceries",
      shared: true,
      members: 2,
      color: "#e6955c",
      items: [
        { id: "li1", text: "Oat milk", done: false },
        { id: "li2", text: "Tomatoes", done: false },
        { id: "li3", text: "Coffee beans", done: true },
        { id: "li4", text: "Dishwasher tablets", done: false },
      ],
    },
    {
      id: "l2",
      name: "Personal reminders",
      shared: false,
      members: 1,
      color: "#6f8f7b",
      items: [
        { id: "li5", text: "Book dentist appointment", done: false, due: "Tomorrow" },
        { id: "li6", text: "Return library book", done: false, due: "Friday" },
      ],
    },
    {
      id: "l3",
      name: "Weekend trip",
      shared: true,
      members: 3,
      color: "#7b83a6",
      items: [
        { id: "li7", text: "Choose hiking route", done: true },
        { id: "li8", text: "Reserve dinner", done: false },
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
  monthlyBudget: 1200,
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
};

const navItems: { id: Section; label: string; icon: typeof Home }[] = [
  { id: "today", label: "Today", icon: Home },
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

export default function SakhyaWebApp() {
  const [section, setSection] = useState<Section>("today");
  const [state, setState] = useState<PersistedState>(seedState);
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
  const [moneyView, setMoneyView] = useState<"overview" | "month">("overview");
  const [chatInput, setChatInput] = useState("");
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [assistantThinking, setAssistantThinking] = useState(false);
  const [moneyEntryOpen, setMoneyEntryOpen] = useState(false);
  const [moneyEntryMode, setMoneyEntryMode] = useState<"type" | "pdf" | "sakhya">("sakhya");
  const [moneyDraft, setMoneyDraft] = useState<MoneyDraft>(EMPTY_MONEY_DRAFT);
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
  const [deleteAccountOpen, setDeleteAccountOpen] = useState(false);
  const [deleteConfirmation, setDeleteConfirmation] = useState("");
  const [aiConsent, setAIConsent] = useState(false);
  const [aiContract, setAIContract] = useState<SakhyaAIContract>(SAKHYA_AI_CONTRACT);
  const [sharingOpen, setSharingOpen] = useState(false);
  const [inviteCode, setInviteCode] = useState("");
  const [joinCode, setJoinCode] = useState("");
  const [sharingOwner, setSharingOwner] = useState(false);
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
          setState(migrated);
          const removeLegacyCopy = window.confirm(
            "Your browser data is now saved securely to your account. Remove the old plaintext browser copy? Choose Cancel to keep it.",
          );
          if (removeLegacyCopy) {
            window.localStorage.removeItem(LEGACY_STORAGE_KEY);
            setNotice("Your browser data was moved into secure account storage, and the old copy was removed.");
          } else {
            setNotice("Your secure account copy is ready. The old browser copy was kept as requested.");
          }
        }
        await loadSharedLists();
        setHydrated(true);
        return;
      }
      if (response.ok) {
        const payload = (await response.json()) as { state: unknown; version: number };
        stateVersionRef.current = payload.version;
        setState(validatePersistedState(payload.state) as PersistedState);
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
        "x-sakhya-request": "1",
        "if-match": String(stateVersionRef.current),
      },
      body: JSON.stringify(validated),
    });
    const result = (await response.json()) as { version?: number; code?: string; error?: string };
    if (!response.ok) {
      if (result.code === "STATE_CONFLICT") {
        throw new Error("Your data changed on another device. Reload Sakhya before editing again.");
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
        if (response.ok) setAIContract((await response.json()) as SakhyaAIContract);
      })
      .catch(() => undefined);
  }, []);

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

  const days = useMemo(
    () =>
      Array.from({ length: 7 }, (_, index) => {
        const date = new Date();
        date.setDate(date.getDate() + index - 3);
        return date;
      }),
    [],
  );
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
  const monthEntries = useMemo(() => {
    const now = new Date();
    return state.entries.filter((entry) => {
      const date = new Date(entry.timestamp);
      return date.getMonth() === now.getMonth() && date.getFullYear() === now.getFullYear();
    });
  }, [state.entries]);
  const monthSpent = monthEntries.reduce((sum, entry) => sum + (entry.amount ?? 0), 0);
  const monthMoneyEntries = useMemo(() => {
    const now = new Date();
    return state.moneyEntries.filter((entry) => {
      const date = new Date(entry.date);
      return date.getMonth() === now.getMonth() && date.getFullYear() === now.getFullYear();
    });
  }, [state.moneyEntries]);
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
  const netWorth = totalAssets - totalLiabilities;
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
  const balanceScore = Math.max(
    32,
    Math.min(96, 70 + Math.round((weekPersonal - weekWork * 0.45) / 18)),
  );
  const selectedList = state.lists.find((list) => list.id === selectedListId) ?? state.lists[0];
  const suggested = capture.trim() ? parseCapture(capture) : undefined;
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
              <span className="eyebrow">Sakhya</span>
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
          items: [{ id: uid(), text: listIntent.text, done: false, due: listIntent.due }, ...destination.items],
        }
      : undefined;
    setState((current) => {
      if (!updatedDestination) return { ...current, entries: [entry, ...current.entries] };
      const exists = current.lists.some((list) => list.id === updatedDestination.id);
      return {
        ...current,
        entries: [entry, ...current.entries],
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
        "x-sakhya-request": "1",
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
    const updated = { ...list, items: list.items.map((item) => item.id === itemId ? { ...item, done: !item.done } : item) };
    setState((current) => ({ ...current, lists: current.lists.map((item) => item.id === listId ? updated : item) }));
    if (updated.shared) void updateSharedList(updated);
  }

  function addListItem(event: FormEvent) {
    event.preventDefault();
    if (!newListItem.trim() || !selectedList) return;
    const entry: Entry = {
      id: uid(),
      title: newListItem.trim(),
      kind: "list",
      timestamp: new Date().toISOString(),
    };
    const updated = { ...selectedList, items: [{ id: uid(), text: newListItem.trim(), done: false }, ...selectedList.items] };
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
      headers: { "content-type": "application/json", "x-sakhya-request": "1" },
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
      headers: { "content-type": "application/json", "x-sakhya-request": "1" },
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
      headers: { "content-type": "application/json", "x-sakhya-request": "1" },
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
      headers: { "x-sakhya-request": "1" },
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

  function openMoneyEntry(kind: MoneyDraft["kind"] = "expense", mode: typeof moneyEntryMode = "sakhya") {
    setMoneyDraft({ ...EMPTY_MONEY_DRAFT, kind, balanceCategory: kind === "liability" ? "creditCard" : "cash", date: new Date().toISOString().slice(0, 10) });
    setMoneyEntryMode(mode);
    setMoneyInstruction("");
    setMoneyReview(undefined);
    setImportedTransactions([]);
    setImportFileName("");
    setMoneyEntryOpen(true);
  }

  function storeMoneyRecord(kind: MoneyDraft["kind"], amount: number, date: string, note: string, balanceCategory?: BalanceSheetCategory, existingBalanceID?: string) {
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
    storeMoneyRecord(moneyDraft.kind, amount, date.toISOString(), moneyDraft.note.trim(), moneyDraft.balanceCategory, moneyDraft.existingBalanceID);
    setMoneyEntryOpen(false);
    setNotice(`${moneyDraft.kind === "expense" ? "Expense" : "Money entry"} added for ${moneyDraft.date}.`);
  }

  async function submitMoneyInstruction(event: FormEvent) {
    event.preventDefault();
    const local = parseMoneyInstruction(moneyInstruction);
    if (local) {
      setMoneyReview(local);
      return;
    }
    if (!aiConsent) {
      setNotice("That entry is ambiguous. Enable AI data sharing in Sakhya AI, or use the guided form.");
      return;
    }
    setMoneyClassifying(true);
    try {
      const response = await fetch("/api/finance/classify", {
        method: "POST",
        credentials: "same-origin",
        headers: { "content-type": "application/json", "x-sakhya-request": "1" },
        body: JSON.stringify({ text: moneyInstruction, consent: true, timezone: Intl.DateTimeFormat().resolvedOptions().timeZone }),
      });
      const body = await response.json() as { classification?: ParsedMoneyInstruction; error?: string };
      if (!response.ok || !body.classification) throw new Error(body.error || "Sakhya could not classify that entry.");
      setMoneyReview(body.classification);
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "Sakhya could not classify that entry.");
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
          "x-sakhya-request": "1",
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
          setNotice(`${aiContract.label} needs an OpenAI API key. Showing Sakhya’s local insight instead.`);
        } else {
          setNotice(result.error ?? "Sakhya AI is temporarily unavailable.");
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
      answer = `You received ${currency.format(monthIncome)} and spent ${currency.format(monthSpent)} this month. Your recorded net worth is ${currency.format(netWorth)}, and ${currency.format(Math.max(state.monthlyBudget - monthSpent, 0))} remains in your spending plan.`;
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
    setState((current) => ({
      ...current,
      entries: current.entries.map((entry) =>
        entry.id === editingEntry.id ? editingEntry : entry,
      ),
    }));
    setEditingEntry(undefined);
  }

  function deleteEditedEntry() {
    if (!editingEntry || !window.confirm(`Delete “${editingEntry.title}”? This cannot be undone.`)) return;
    setState((current) => ({
      ...current,
      entries: current.entries.filter((entry) => entry.id !== editingEntry.id),
    }));
    setEditingEntry(undefined);
    setNotice("Timeline entry deleted.");
  }

  function completeFocusBlock() {
    setState((current) => ({
      ...current,
      entries: [
        { id: uid(), title: "Completed a protected focus block", kind: "work", timestamp: new Date().toISOString(), minutes: 60 },
        ...current.entries,
      ],
    }));
    setSelectedDate(new Date());
    setNotice("Focus block completed and recorded on your timeline.");
  }

  async function deleteAccount() {
    if (deleteConfirmation !== "DELETE MY ACCOUNT") return;
    const response = await fetch("/api/state", {
      method: "DELETE",
      credentials: "same-origin",
      headers: {
        "x-sakhya-request": "1",
        "x-sakhya-confirm-delete": deleteConfirmation,
      },
    });
    if (!response.ok) {
      setNotice("Your account could not be deleted. No data was removed.");
      return;
    }
    window.localStorage.removeItem(LEGACY_STORAGE_KEY);
    accountDeletedRef.current = true;
    setDeleteAccountOpen(false);
    setState({ ...seedState, entries: [], lists: [], trackers: [], moneyEntries: [], balanceSheetItems: [] });
    stateVersionRef.current = 0;
    setNotice("Your Sakhya account data and uploaded photos were deleted.");
  }

  function exportData() {
    const blob = new Blob([JSON.stringify(state, null, 2)], { type: "application/json" });
    const href = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = href;
    anchor.download = `sakhya-backup-${new Date().toISOString().slice(0, 10)}.json`;
    anchor.click();
    URL.revokeObjectURL(href);
  }

  function importData(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    event.target.value = "";
    if (file.size > MAX_BACKUP_BYTES || (file.type && file.type !== "application/json")) {
      setNotice("Choose a Sakhya JSON backup under 2 MB.");
      return;
    }
    const reader = new FileReader();
    reader.onload = () => {
      try {
        const imported = validatePersistedState(JSON.parse(String(reader.result)), {
          allowLegacyDataImages: false,
        }) as PersistedState;
        setState(imported);
        setNotice("Your Sakhya backup was imported.");
      } catch {
        setNotice("That file is not a valid Sakhya backup.");
      }
    };
    reader.readAsText(file);
  }

  function resetData() {
    if (!window.confirm("Replace your account data with the sample workspace? Export first if you want a backup.")) return;
    setState(seedState);
    setNotice("Sample workspace restored for your account.");
  }

  const mainContent = (() => {
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
                    <button
                      className={`check-row ${item.done ? "done" : ""}`}
                      key={item.id}
                      onClick={() => toggleListItem(selectedList.id, item.id)}
                    >
                      <span className="check-box">{item.done && <Check size={14} />}</span>
                      <span>{item.text}</span>
                      {item.due && <small>{item.due}</small>}
                    </button>
                  ))}
                </div>
                <div className="native-note">
                  <ShieldCheck size={17} />
                  Apple Reminders sync is available through the native Sakhya app.
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
      const remaining = Math.max(state.monthlyBudget - monthSpent, 0);
      const surplus = monthIncome - monthSpent;
      const unallocated = surplus - monthSaved - monthInvested;
      const netCashMovement = monthIncome - monthSpent - monthInvested;
      const allocationBalanced = Math.abs(unallocated) < 0.01;
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
            description="Add each money event once. Cash flow, monthly result and net worth are three views of the same financial life."
            action={
              <button className="primary-button" onClick={() => openMoneyEntry()}><Plus size={17} /> Add money activity</button>
            }
          />
          <section className="money-capture-card">
            <div className="money-capture-icon"><Sparkles size={20} /></div>
            <button className="money-capture-main" onClick={() => openMoneyEntry()}>
              <strong>Tell Sakhya what changed</strong>
              <span>“Paid €32 for groceries” · “Salary €3,200” · “My savings account balance is €8,400”</span>
            </button>
            <button className="money-import-shortcut" onClick={() => openMoneyEntry("expense", "pdf")}><FileText size={16} /> Import PDF</button>
          </section>
          <div className="segment-row money-segments">
            <button className={moneyView === "overview" ? "active" : ""} onClick={() => setMoneyView("overview")}>Money position</button>
            <button className={moneyView === "month" ? "active" : ""} onClick={() => setMoneyView("month")}>Spending & goals</button>
          </div>
          {moneyView === "overview" ? (
            <>
              <section className="money-position-hero">
                <div>
                  <span className="eyebrow">Your money position</span>
                  <strong>{currency.format(netWorth)}</strong>
                  <p>{currency.format(totalAssets)} owned − {currency.format(totalLiabilities)} owed</p>
                </div>
                <div className="position-pulse">
                  <small>This month</small>
                  <strong>{netCashMovement >= 0 ? "+" : "−"}{currency.format(Math.abs(netCashMovement))}</strong>
                  <span>cash movement</span>
                </div>
              </section>
              <div className="statement-grid">
                <section className="panel statement-card">
                  <div className="statement-title">
                    <div><span className="eyebrow">Movement</span><h2>Cash flow</h2><p>What came in and left usable cash.</p></div>
                    <WalletCards size={20} />
                  </div>
                  <div className="statement-line"><span>Income</span><strong className="positive">+{currency.format(monthIncome)}</strong></div>
                  <div className="statement-line"><span>Everyday spending</span><strong>−{currency.format(monthSpent)}</strong></div>
                  <div className="statement-line"><span>Moved to investments</span><strong>−{currency.format(monthInvested)}</strong></div>
                  <div className="statement-line total"><span>Net cash movement</span><strong>{currency.format(netCashMovement)}</strong></div>
                  {monthSaved > 0 && <p className="statement-note">{currency.format(monthSaved)} earmarked for goals remains cash until it is transferred.</p>}
                </section>

                <section className="panel statement-card">
                  <div className="statement-title">
                    <div><span className="eyebrow">Zero-based allocation</span><h2>Personal P&amp;L</h2><p>Give every euro of surplus a purpose.</p></div>
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
                        : "This month used existing cash or debt."}
                  </p>
                </section>

                <section className="panel statement-card balance-statement">
                  <div className="statement-title">
                    <div><span className="eyebrow">Snapshot</span><h2>Balance sheet</h2><p>What you own minus what you owe.</p></div>
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
                </section>
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
                  <span className="eyebrow">Available this month</span>
                  <strong>{currency.format(remaining)}</strong>
                  <p>{currency.format(monthSpent)} used from a {currency.format(state.monthlyBudget)} plan</p>
                </div>
                <div className="budget-ring" style={{ "--progress": `${Math.min((monthSpent / state.monthlyBudget) * 100, 100) * 3.6}deg` } as React.CSSProperties}>
                  <span>{Math.round((monthSpent / state.monthlyBudget) * 100)}%</span>
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
                  <div className="progress-line large"><span style={{ width: `${(state.savingsCurrent / state.savingsTarget) * 100}%` }} /></div>
                  <button className="secondary-button full" onClick={() => openMoneyEntry("saving")}>
                    <Plus size={16} /> Add contribution
                  </button>
                </section>
                <section className="panel trip-panel">
                  <div className="trip-visual"><span>SEPT 12–15</span><strong>Lisbon</strong></div>
                  <div><span className="eyebrow">Trip plan</span><h2>€420 left</h2><p>€280 spent from €700</p></div>
                  <button className="icon-button" onClick={() => setNotice("Trip budgets are visible here; editable trip planning is scheduled for the next beta.")} aria-label="Trip plan information"><ArrowRight size={18} /></button>
                </section>
              </div>
            </>
          )}
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
                Ask Sakhya about this <ArrowRight size={15} />
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
            Automatic Screen Time and Apple Health data require the native Sakhya app. Web entries still contribute to your balance.
          </div>
        </div>
      );
    }

    if (section === "settings") {
      return (
        <div className="page-shell">
          <PageHeader
            eyebrow="Sakhya"
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
                  <span>Your web data is isolated by account and protected by the private Sakhya service.</span>
                </div>
              </div>
              <button className="settings-row" onClick={exportData}><Download size={18} /><span><strong>Export backup</strong><small>Download all entries, lists and plans</small></span><ArrowRight size={16} /></button>
              <label className="settings-row"><Upload size={18} /><span><strong>Import backup</strong><small>Restore a Sakhya JSON file</small></span><ArrowRight size={16} /><input type="file" accept=".json,application/json" onChange={importData} hidden /></label>
              <button className="settings-row" onClick={resetData}><RotateCcw size={18} /><span><strong>Restore sample workspace</strong><small>Requires confirmation</small></span><ArrowRight size={16} /></button>
              <button className="settings-row" onClick={() => setPolicyOpen(true)}><ShieldCheck size={18} /><span><strong>Privacy and AI</strong><small>See how your journal, health and money data are used</small></span><ArrowRight size={16} /></button>
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
                  <div className="capability-row"><span>Sakhya AI</span><strong>{aiConsent ? "Terra allowed" : "Local only"}</strong></div>
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
        <div className="greeting-row">
          <div>
            <h1>Good {new Date().getHours() < 12 ? "morning" : new Date().getHours() < 18 ? "afternoon" : "evening"}</h1>
            <p>Follow the system, capture the evidence, and improve one step at a time.</p>
          </div>
        </div>
        <div className="calendar-strip panel">
          <button className="icon-button" onClick={() => changeDay(-1)} aria-label="Previous day"><ChevronLeft size={18} /></button>
          <div className="date-days">
            {days.map((date) => (
              <button
                key={date.toISOString()}
                className={sameDay(date.toISOString(), selectedDate) ? "active" : ""}
                onClick={() => setSelectedDate(date)}
              >
                <span>{weekdayOnly.format(date)}</span>
                <strong>{date.getDate()}</strong>
                {state.entries.some((entry) => sameDay(entry.timestamp, date)) && <i />}
              </button>
            ))}
          </div>
          <button className="icon-button" onClick={() => changeDay(1)} aria-label="Next day"><ChevronRight size={18} /></button>
          <button className="calendar-label"><CalendarDays size={17} /> {longDate.format(selectedDate)}</button>
        </div>
        <form className="capture-card" onSubmit={addCapture}>
          <div className="capture-top">
            <div className="capture-mark"><Sparkles size={19} /></div>
            <div>
              <strong>Capture evidence</strong>
              <small>Type or talk naturally. Sakhya organizes it before anything is saved.</small>
            </div>
          </div>
          <textarea
            value={capture}
            onChange={(event) => setCapture(event.target.value)}
            placeholder="“Walked 30 minutes”, “spent €18 on lunch”, or “remind me to call Mum”…"
            rows={2}
          />
          {capturePhoto && (
            <div className="photo-preview">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={capturePhoto} alt="Capture attachment preview" />
              <span>Photo attached locally</span>
              <button type="button" onClick={() => setCapturePhoto(undefined)}><X size={15} /></button>
            </div>
          )}
          <div className="capture-footer">
            <div className="capture-tools">
              <label className="tool-button">
                <Camera size={17} /> <span>Photo</span>
                <input type="file" accept="image/jpeg,image/png,image/webp" onChange={attachPhoto} hidden />
              </label>
              <button type="button" className={`tool-button ${isListening ? "recording" : ""}`} onClick={() => toggleListening("capture")}>
                <Mic size={17} /> <span>{isListening ? "Listening…" : "Talk"}</span>
              </button>
            </div>
            {suggested && (
              <span className="suggestion-chip" style={{ "--chip": kindMeta[suggested.kind].color } as React.CSSProperties}>
                {kindMeta[suggested.kind].label}
                {suggested.amount ? ` · ${currency.format(suggested.amount)}` : ""}
                {suggested.minutes ? ` · ${minutesLabel(suggested.minutes)}` : ""}
              </span>
            )}
            <button className="add-button" disabled={!capture.trim()}>Add <ArrowRight size={16} /></button>
          </div>
        </form>
        <div className="today-grid">
          <section className="panel now-card">
            <div className="section-heading">
              <div><span className="eyebrow">Now</span><h2>Your next useful step</h2></div>
              <span className="time-pill">{timeOnly.format(new Date())}</span>
            </div>
            <div className="focus-action">
              <span className="focus-icon"><Target size={21} /></span>
              <div><strong>Protect one focus block</strong><small>60 min · High energy</small></div>
              <button onClick={completeFocusBlock}><Check size={17} /> Complete</button>
            </div>
            <div className="next-actions">
              <div><span>13:00</span><strong>Move for 30 minutes</strong><Activity size={17} /></div>
              <div><span>20:30</span><strong>Reflect and prepare tomorrow</strong><Brain size={17} /></div>
            </div>
          </section>
          <section className="panel overview-card">
            <span className="eyebrow">Today at a glance</span>
            <div className="overview-stats">
              <div><strong>{dayEntries.length}</strong><span>Moments</span></div>
              <div><strong>{currency.format(dayEntries.reduce((s, e) => s + (e.amount ?? 0), 0))}</strong><span>Spent</span></div>
              <div><strong>{minutesLabel(dayEntries.filter((e) => e.kind === "movement").reduce((s, e) => s + (e.minutes ?? 0), 0)) || "—"}</strong><span>Movement</span></div>
            </div>
            <div className="daily-progress"><span style={{ width: `${Math.min((dayEntries.length / 7) * 100, 100)}%` }} /></div>
            <small>Evidence builds the system—one honest entry at a time.</small>
          </section>
        </div>
        <section className="timeline-section">
          <div className="section-heading">
            <div><span className="eyebrow">{sameDay(selectedDate.toISOString(), new Date()) ? "Today" : longDate.format(selectedDate)}</span><h2>Timeline</h2></div>
            <span className="entry-count">{dayEntries.length} entries</span>
          </div>
          <div className="timeline">
            {dayEntries.length ? dayEntries.map((entry) => {
              const meta = kindMeta[entry.kind];
              const Icon = meta.icon;
              return (
                <article className="timeline-entry" key={entry.id}>
                  <time>{timeOnly.format(new Date(entry.timestamp))}</time>
                  <span className="timeline-node" style={{ color: meta.color }}><Icon size={17} /></span>
                  <div className="entry-card">
                    <div>
                      <span className="entry-kind" style={{ color: meta.color }}>{meta.label}</span>
                      <strong>{entry.title}</strong>
                          {(entry.minutes || entry.note || entry.source) && (
                            <small>
                              {[minutesLabel(entry.minutes), entry.note, entry.source ? `Source: ${entry.source}` : ""]
                                .filter(Boolean)
                                .join(" · ")}
                            </small>
                          )}
                    </div>
                    {entry.photo && (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={entry.photo} alt="" />
                    )}
                    {entry.amount && <b>{currency.format(entry.amount)}</b>}
                    <button className="icon-button" onClick={() => setEditingEntry(entry)} aria-label={`Edit ${entry.title}`}><MoreHorizontal size={18} /></button>
                  </div>
                </article>
              );
            }) : (
              <div className="empty-timeline"><Clock3 size={23} /><strong>No moments recorded yet</strong><span>Your next entry will appear here.</span></div>
            )}
          </div>
        </section>
      </div>
    );
  })();

  return (
    <div className="app-frame">
      <aside className={`sidebar ${mobileMenu ? "open" : ""}`}>
        <div className="brand">
          <span className="brand-mark">S</span>
          <div><strong>Sakhya</strong><small>Your everyday system</small></div>
          <button className="mobile-close" onClick={() => setMobileMenu(false)}><X size={20} /></button>
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
        </div>
      </aside>
      {mobileMenu && <button className="scrim" onClick={() => setMobileMenu(false)} aria-label="Close menu" />}
      <main>
        <header className="topbar">
          <button className="menu-button" onClick={() => setMobileMenu(true)}><Menu size={21} /></button>
          <div className="mobile-brand"><span className="brand-mark small">S</span><strong>Sakhya</strong></div>
          <button className="search-button" onClick={() => setSearchOpen(true)}><Search size={17} /><span>Search your life</span><kbd>⌘ K</kbd></button>
          <button className="avatar">DG</button>
        </header>
        {mainContent}
      </main>
      <button type="button" className="assistant-fab" aria-haspopup="dialog" aria-expanded={assistantOpen} onClick={() => openAssistant()}>
        <Sparkles size={18} /><span>Ask Sakhya</span>
      </button>
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
        <div className="modal-layer assistant-layer" role="dialog" aria-modal="true" aria-label="Ask Sakhya">
          <button className="modal-backdrop" onClick={() => setAssistantOpen(false)} aria-label="Close assistant" />
          <section className="assistant-sheet">
            <header>
              <div className="assistant-title"><span><Sparkles size={18} /></span><div><strong>Sakhya</strong><small><i /> Private data assistant</small></div></div>
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
              <input type="checkbox" checked={aiConsent} onChange={(event) => setAIConsent(event.target.checked)} />
              <span><strong>Allow AI analysis</strong><small>Send the question and relevant recent Sakhya records to OpenAI. Turn this off to use local insights only.</small></span>
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
      {editingEntry && (
        <div className="modal-layer" role="dialog" aria-modal="true" aria-label="Edit timeline entry">
          <button className="modal-backdrop" onClick={() => setEditingEntry(undefined)} aria-label="Close editor" />
          <form className="edit-modal" onSubmit={saveEditedEntry}>
            <div className="section-heading"><div><span className="eyebrow">Timeline</span><h2>Edit entry</h2></div><button type="button" className="icon-button" onClick={() => setEditingEntry(undefined)}><X size={18} /></button></div>
            <label>What happened<input value={editingEntry.title} onChange={(event) => setEditingEntry({ ...editingEntry, title: event.target.value })} /></label>
            <label>Category<select value={editingEntry.kind} onChange={(event) => setEditingEntry({ ...editingEntry, kind: event.target.value as EntryKind })}>{Object.entries(kindMeta).map(([kind, meta]) => <option key={kind} value={kind}>{meta.label}</option>)}</select></label>
            <label>Date and time<input type="datetime-local" value={new Date(new Date(editingEntry.timestamp).getTime() - new Date(editingEntry.timestamp).getTimezoneOffset() * 60_000).toISOString().slice(0, 16)} onChange={(event) => setEditingEntry({ ...editingEntry, timestamp: new Date(event.target.value).toISOString() })} /></label>
            <label>Amount in EUR<input type="number" min="0" step="0.01" value={editingEntry.amount ?? ""} onChange={(event) => setEditingEntry({ ...editingEntry, amount: event.target.value ? Number(event.target.value) : undefined })} /></label>
            <label>Duration in minutes<input type="number" min="0" step="1" value={editingEntry.minutes ?? ""} onChange={(event) => setEditingEntry({ ...editingEntry, minutes: event.target.value ? Number(event.target.value) : undefined })} /></label>
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
            <p>Your account records are stored privately for Sakhya’s timeline, lists, trackers and money views. Uploaded photos are private and require your signed-in account.</p>
            <p>AI is optional. When enabled, Sakhya sends your question and a limited selection of relevant records from the last 90 days to OpenAI to answer it. Sakhya requests no-store processing and never puts the API key in your browser.</p>
            <p>Health and financial information is shown for personal organization, not medical, tax, investment or accounting advice. You can export your data or permanently delete it at any time.</p>
            <p><strong>Launch policy version:</strong> 3 August 2026. Contact: ganatra.dev@gmail.com</p>
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
          <button className="modal-backdrop" onClick={() => setMoneyEntryOpen(false)} aria-label="Close money entry" />
          <section className="money-entry-modal">
            <div className="section-heading">
              <div><span className="eyebrow">One money ledger</span><h2>Add money activity</h2></div>
              <button type="button" className="icon-button" onClick={() => setMoneyEntryOpen(false)} aria-label="Close"><X size={18} /></button>
            </div>
            <div className="money-entry-tabs" role="tablist" aria-label="Money entry method">
              <button className={moneyEntryMode === "sakhya" ? "active" : ""} onClick={() => { setMoneyEntryMode("sakhya"); setMoneyReview(undefined); }}>Tell Sakhya</button>
              <button className={moneyEntryMode === "type" ? "active" : ""} onClick={() => setMoneyEntryMode("type")}>Guided</button>
              <button className={moneyEntryMode === "pdf" ? "active" : ""} onClick={() => setMoneyEntryMode("pdf")}>Statement</button>
            </div>
            {moneyEntryMode === "type" && (
              <form className="money-entry-form" onSubmit={submitMoneyDraft}>
                <label>What changed?<select value={moneyDraft.kind} onChange={(event) => { const kind = event.target.value as MoneyDraft["kind"]; setMoneyDraft({ ...moneyDraft, kind, balanceCategory: kind === "liability" ? "creditCard" : moneyDraft.balanceCategory }); }}><option value="expense">I spent money</option><option value="income">I received money</option><option value="saving">I set money aside</option><option value="investment">I invested money</option><option value="asset">An asset balance changed</option><option value="liability">A debt balance changed</option></select></label>
                <div className="money-form-row">
                  <label>Amount (€)<input autoFocus inputMode="decimal" value={moneyDraft.amount} onChange={(event) => setMoneyDraft({ ...moneyDraft, amount: event.target.value })} placeholder="0.00" /></label>
                  <label>Date<input type="date" value={moneyDraft.date} onChange={(event) => setMoneyDraft({ ...moneyDraft, date: event.target.value })} /></label>
                </div>
                {(moneyDraft.kind === "asset" || moneyDraft.kind === "liability") && <label>Balance type<select value={moneyDraft.balanceCategory} onChange={(event) => setMoneyDraft({ ...moneyDraft, balanceCategory: event.target.value as BalanceSheetCategory })}>{moneyDraft.kind === "asset" ? <><option value="cash">Cash &amp; bank</option><option value="investments">Investments</option><option value="property">Property &amp; valuables</option><option value="otherAsset">Other asset</option></> : <><option value="creditCard">Credit card</option><option value="loan">Loan</option><option value="otherLiability">Other debt</option></>}</select></label>}
                <label>{moneyDraft.kind === "income" ? "Source" : moneyDraft.kind === "asset" || moneyDraft.kind === "liability" ? "Account or balance name" : "What was it for?"}<input value={moneyDraft.note} onChange={(event) => setMoneyDraft({ ...moneyDraft, note: event.target.value })} placeholder={moneyDraft.kind === "income" ? "Salary, freelance…" : moneyDraft.kind === "asset" ? "Main bank account…" : moneyDraft.kind === "liability" ? "Credit card…" : "Groceries, rent…"} /></label>
                <button className="primary-button" disabled={!moneyDraft.amount.trim()}>{moneyDraft.existingBalanceID ? "Update once" : "Add once"}</button>
              </form>
            )}
            {moneyEntryMode === "sakhya" && (
              <form className="money-sakhya-form" onSubmit={submitMoneyInstruction}>
                {!moneyReview ? <>
                  <div className="sakhya-entry-prompt"><Sparkles size={18} /><div><strong>Say it your way</strong><span>Finance rules classify clear entries locally. Terra helps only when the meaning is ambiguous.</span></div></div>
                  <textarea autoFocus rows={4} value={moneyInstruction} onChange={(event) => setMoneyInstruction(event.target.value)} placeholder="Paid €24.50 for groceries yesterday, or my savings account balance is €8,400" />
                  {parseMoneyInstruction(moneyInstruction) && <div className="money-parse-preview"><CheckCircle2 size={16} /><span>Ready to review · {currency.format(parseMoneyInstruction(moneyInstruction)!.amount)} · {parseMoneyInstruction(moneyInstruction)!.kind}</span></div>}
                  <button className="primary-button" disabled={!moneyInstruction.trim() || moneyClassifying}>{moneyClassifying ? "Understanding…" : "Review entry"}</button>
                </> : <div className="money-review-card">
                  <span className="eyebrow">Check before saving</span>
                  <div className="money-review-amount">{currency.format(moneyReview.amount)}</div>
                  <div className="money-review-grid"><span>Type<strong>{moneyReview.kind}</strong></span><span>Date<strong>{new Date(moneyReview.date).toLocaleDateString()}</strong></span></div>
                  <p>{moneyReview.title}</p>
                  <small>This one record will feed every relevant money view. Sakhya never lets the model calculate your totals.</small>
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
