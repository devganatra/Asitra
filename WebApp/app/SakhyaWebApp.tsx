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
import { ChangeEvent, FormEvent, useEffect, useMemo, useRef, useState } from "react";
import { validatePersistedState } from "./state-schema";

type Section = "today" | "lists" | "track" | "money" | "balance" | "settings";
type EntryKind =
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

type PersistedState = {
  entries: Entry[];
  lists: LifeList[];
  trackers: Tracker[];
  monthlyBudget: number;
  savingsTarget: number;
  savingsCurrent: number;
};

const LEGACY_STORAGE_KEY = "sakhya-web-v1";
const MAX_BACKUP_BYTES = 2_000_000;
const ALLOWED_IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
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

function parseCapture(text: string): Omit<Entry, "id" | "timestamp"> {
  const lower = text.toLowerCase();
  const amountMatch = text.match(/(?:€|eur\s*)\s?(\d+(?:[.,]\d{1,2})?)|(\d+(?:[.,]\d{1,2})?)\s?(?:€|eur)/i);
  const durationMatch = lower.match(/(\d+)\s*(?:h|hr|hrs|hour|hours)/);
  const minuteMatch = lower.match(/(\d+)\s*(?:m|min|mins|minute|minutes)/);
  const minutes = durationMatch
    ? Number(durationMatch[1]) * 60 + (minuteMatch ? Number(minuteMatch[1]) : 0)
    : minuteMatch
      ? Number(minuteMatch[1])
      : undefined;
  let kind: EntryKind = "note";
  if (amountMatch || /(spent|bought|paid|expense|cost)/.test(lower)) kind = "expense";
  else if (/(walk|run|gym|workout|yoga|cycle|swim)/.test(lower)) kind = "movement";
  else if (/(slept|sleep|nap)/.test(lower)) kind = "sleep";
  else if (/(breakfast|lunch|dinner|ate|meal|food)/.test(lower)) kind = "food";
  else if (/(read|book|novel)/.test(lower)) kind = "book";
  else if (/(watch|movie|film|documentary|series)/.test(lower)) kind = "movie";
  else if (/(feel|felt|mood|grateful|mindset)/.test(lower)) kind = "mindset";
  else if (/(journal|reflect|reflection)/.test(lower)) kind = "journal";
  else if (/(work|meeting|focus|client)/.test(lower)) kind = "work";
  else if (/(buy|grocery|remind|todo|to-do)/.test(lower)) kind = "list";
  const amountValue = amountMatch?.[1] ?? amountMatch?.[2];
  return {
    title: text.trim(),
    kind,
    minutes,
    amount: amountValue ? Number(amountValue.replace(",", ".")) : undefined,
  };
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
  const [chatInput, setChatInput] = useState("");
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [assistantThinking, setAssistantThinking] = useState(false);
  const [notice, setNotice] = useState<string>();
  const recognitionRef = useRef<SpeechRecognitionLike | null>(null);
  const saveQueueRef = useRef<Promise<void>>(Promise.resolve());

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
        setHydrated(true);
        return;
      }
      if (response.ok) {
        const payload = (await response.json()) as { state: unknown };
        setState(validatePersistedState(payload.state) as PersistedState);
        setHydrated(true);
        return;
      }
      throw new Error("Secure storage is unavailable.");
    } catch {
      setNotice("Secure storage could not be reached. No existing browser data was changed.");
      setHydrated(true);
    }
  }

  async function saveState(nextState: PersistedState) {
    const validated = validatePersistedState(nextState);
    const response = await fetch("/api/state", {
      method: "PUT",
      credentials: "same-origin",
      headers: {
        "content-type": "application/json",
        "x-sakhya-request": "1",
      },
      body: JSON.stringify(validated),
    });
    if (!response.ok) throw new Error("Secure storage rejected the update.");
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
    if (!hydrated) return;
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
  const weekActivity = weekEntries
    .filter((entry) => entry.kind === "movement")
    .reduce((sum, entry) => sum + (entry.minutes ?? 0), 0);
  const weekWork = weekEntries
    .filter((entry) => entry.kind === "work")
    .reduce((sum, entry) => sum + (entry.minutes ?? 0), 0);
  const weekPersonal = weekEntries
    .filter((entry) => ["movement", "mindset", "book", "movie", "journal"].includes(entry.kind))
    .reduce((sum, entry) => sum + (entry.minutes ?? 30), 0);
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
    const entry: Entry = {
      id: uid(),
      timestamp: new Date().toISOString(),
      ...parsed,
      photo: capturePhoto,
    };
    setState((current) => {
      const next = { ...current, entries: [entry, ...current.entries] };
      if (parsed.kind === "list") {
        const listIndex = next.lists.findIndex((list) => list.name === "Personal reminders");
        if (listIndex >= 0) {
          next.lists = next.lists.map((list, index) =>
            index === listIndex
              ? {
                  ...list,
                  items: [{ id: uid(), text: capture, done: false }, ...list.items],
                }
              : list,
          );
        }
      }
      return next;
    });
    setCapture("");
    setCapturePhoto(undefined);
    setSelectedDate(new Date());
    setNotice(
      parsed.kind === "list"
        ? "Added to your timeline and Personal reminders."
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
    setState((current) => ({
      ...current,
      lists: current.lists.map((list) =>
        list.id === listId
          ? {
              ...list,
              items: list.items.map((item) =>
                item.id === itemId ? { ...item, done: !item.done } : item,
              ),
            }
          : list,
      ),
    }));
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
    setState((current) => ({
      ...current,
      entries: [entry, ...current.entries],
      lists: current.lists.map((list) =>
        list.id === selectedList.id
          ? {
              ...list,
              items: [{ id: uid(), text: newListItem.trim(), done: false }, ...list.items],
            }
          : list,
      ),
    }));
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

  function toggleListSharing() {
    if (!selectedList) return;
    setState((current) => ({
      ...current,
      lists: current.lists.map((list) =>
        list.id === selectedList.id
          ? { ...list, shared: !list.shared, members: list.shared ? 1 : 2 }
          : list,
      ),
    }));
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

  function addExpense() {
    const title = window.prompt("What did you spend on?");
    if (!title?.trim()) return;
    const rawAmount = window.prompt("Amount in EUR");
    const amount = Number(rawAmount?.replace(",", "."));
    if (!Number.isFinite(amount) || amount <= 0) return;
    setState((current) => ({
      ...current,
      entries: [
        { id: uid(), title: title.trim(), kind: "expense", amount, timestamp: new Date().toISOString() },
        ...current.entries,
      ],
    }));
  }

  async function sendMessage(text = chatInput) {
    const question = text.trim();
    if (!question || assistantThinking) return;
    const userMessage: ChatMessage = { id: uid(), role: "user", text: question };
    const conversation = [...messages, userMessage].slice(-12);
    setMessages((current) => [...current, userMessage]);
    setChatInput("");
    setAssistantThinking(true);

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
        }),
      });
      const result = (await response.json()) as {
        answer?: string;
        code?: string;
        error?: string;
      };
      if (!response.ok || !result.answer) {
        if (result.code === "AI_NOT_CONFIGURED") {
          setNotice("Terra needs an OpenAI API key. Showing Sakhya’s local insight instead.");
        } else {
          setNotice(result.error ?? "Sakhya AI is temporarily unavailable.");
        }
        throw new Error(result.error ?? "AI unavailable");
      }
      setMessages((current) => [
        ...current,
        { id: uid(), role: "assistant", text: result.answer! },
      ]);
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
      answer = `You have spent ${currency.format(monthSpent)} this month, leaving ${currency.format(Math.max(state.monthlyBudget - monthSpent, 0))} in your plan.`;
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
    setAssistantOpen(true);
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
            action={<button className="primary-button" onClick={addNewList}><Plus size={17} /> New list</button>}
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
                  <button className="secondary-button" onClick={toggleListSharing}>
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
      const categoryGroups = [
        { label: "Everyday", value: monthEntries.filter((e) => e.amount && e.amount < 40).reduce((s, e) => s + (e.amount ?? 0), 0), color: "#df9966" },
        { label: "Living", value: monthEntries.filter((e) => e.amount && e.amount >= 40).reduce((s, e) => s + (e.amount ?? 0), 0), color: "#7d8d79" },
        { label: "Leisure", value: monthEntries.filter((e) => /dinner|movie|coffee/i.test(e.title)).reduce((s, e) => s + (e.amount ?? 0), 0), color: "#8482a0" },
      ];
      return (
        <div className="page-shell">
          <PageHeader
            eyebrow="Money, made understandable"
            title="Your month"
            description="Know what is safe to spend, save toward something meaningful, and plan trips without finance jargon."
            action={<button className="primary-button" onClick={addExpense}><Plus size={17} /> Add expense</button>}
          />
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
              <button
                className="secondary-button full"
                onClick={() => setState((current) => ({ ...current, savingsCurrent: current.savingsCurrent + 50 }))}
              >
                <Plus size={16} /> Add €50 contribution
              </button>
            </section>
            <section className="panel trip-panel">
              <div className="trip-visual"><span>SEPT 12–15</span><strong>Lisbon</strong></div>
              <div><span className="eyebrow">Trip plan</span><h2>€420 left</h2><p>€280 spent from €700</p></div>
              <button className="icon-button"><ArrowRight size={18} /></button>
            </section>
          </div>
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
            </section>
            <section className="panel settings-page-card">
              <div className="section-heading">
                <div><span className="eyebrow">Apple environment</span><h2>Connected capabilities</h2></div>
                <Activity size={20} />
              </div>
              <div className="capability-row"><span>Calendar and Reminders</span><strong>Native app</strong></div>
                  <div className="capability-row"><span>Health and wearables</span><strong>Native app</strong></div>
                  <div className="capability-row"><span>Screen Time</span><strong>Native app</strong></div>
                  <div className="capability-row"><span>Sakhya AI</span><strong>Terra · All devices</strong></div>
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
              <button onClick={() => setNotice("Focus block completed and recorded.")}><Check size={17} /> Complete</button>
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
                onClick={() => { setSection(item.id); setMobileMenu(false); }}
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
          <button className="search-button"><Search size={17} /><span>Search your life</span><kbd>⌘ K</kbd></button>
          <button className="avatar">DG</button>
        </header>
        {mainContent}
      </main>
      <button className="assistant-fab" onClick={() => openAssistant()}>
        <Sparkles size={18} /><span>Ask Sakhya</span>
      </button>
      {notice && (
        <div className="toast">
          <CheckCircle2 size={18} />
          <span>{notice}</span>
          <button onClick={() => setNotice(undefined)}><X size={15} /></button>
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
                  <strong>Everyday · Terra</strong>
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
                  <p><i /><i /><i /><small>Terra is thinking</small></p>
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
            <div className="privacy-line"><Lock size={13} /> Your key stays on the server. AI requests are not stored by Sakhya.</div>
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
            <label>Note<textarea value={editingEntry.note ?? ""} onChange={(event) => setEditingEntry({ ...editingEntry, note: event.target.value })} rows={3} /></label>
            <button className="primary-button" disabled={!editingEntry.title.trim()}>Save changes</button>
          </form>
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
