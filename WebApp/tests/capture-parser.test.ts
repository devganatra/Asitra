import assert from "node:assert/strict";
import test from "node:test";
import { parseCapture } from "../app/capture-parser";

const now = new Date(2026, 7, 3, 11, 44);

test("uses explicit reminder and list intent before content keywords", () => {
  const snackReminder = parseCapture("Remind me to buy water and trail snacks tomorrow", now);
  assert.equal(snackReminder.kind, "list");
  assert.deepEqual(snackReminder.list, {
    target: "reminders",
    text: "buy water and trail snacks",
    due: "Tomorrow",
  });

  const travelIdea = parseCapture("Add Neckar river walk to my travel ideas list", now);
  assert.equal(travelIdea.kind, "list");
  assert.equal(travelIdea.list?.target, "travel");
  assert.equal(travelIdea.list?.text, "Neckar river walk");

  const savedIdea = parseCapture("Save Heidelberg Castle illumination to my travel ideas", now);
  assert.equal(savedIdea.kind, "list");
  assert.equal(savedIdea.list?.target, "travel");
  assert.equal(savedIdea.list?.text, "Heidelberg Castle illumination");

  const shopping = parseCapture("Add sunscreen to my shopping list", now);
  assert.equal(shopping.kind, "list");
  assert.equal(shopping.list?.target, "groceries");
  assert.equal(shopping.list?.text, "sunscreen");

  const wanted = parseCapture("I want to buy hiking socks", now);
  assert.equal(wanted.kind, "list");
  assert.equal(wanted.list?.target, "groceries");
  assert.equal(wanted.list?.text, "hiking socks");
});

test("uses whole words and classifies Heidelberg fitness notes correctly", () => {
  assert.equal(parseCapture("Mood: energized and grateful after the mountain view", now).kind, "mindset");
  assert.equal(parseCapture("Walked up the Philosophenweg for 120 minutes", now).kind, "movement");
  assert.equal(parseCapture("Hiked Königstuhl for 3 hours", now).kind, "movement");
  assert.equal(parseCapture("Journal: the climb was demanding", now).kind, "journal");
});

test("turns relative natural-language times into entry timestamps", () => {
  const breakfast = parseCapture("Today at 07:30 I ate breakfast", now);
  assert.equal(breakfast.kind, "food");
  assert.equal(new Date(breakfast.timestamp).getDate(), 3);
  assert.equal(new Date(breakfast.timestamp).getHours(), 7);
  assert.equal(new Date(breakfast.timestamp).getMinutes(), 30);

  const meeting = parseCapture("Tomorrow at 16 I have a meeting", now);
  assert.equal(meeting.kind, "work");
  assert.equal(new Date(meeting.timestamp).getDate(), 4);
  assert.equal(new Date(meeting.timestamp).getHours(), 16);
  assert.equal(new Date(meeting.timestamp).getMinutes(), 0);
});

test("extracts money and duration without confusing unrelated words", () => {
  const expense = parseCapture("Ate lunch and spent €24", now);
  assert.equal(expense.kind, "expense");
  assert.equal(expense.amount, 24);

  const movement = parseCapture("Walked for 2 hours 15 minutes", now);
  assert.equal(movement.minutes, 135);
});
