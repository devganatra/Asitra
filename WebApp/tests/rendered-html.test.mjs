import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import test from "node:test";

const port = 31_000 + (process.pid % 1_000);
const origin = `http://localhost:${port}`;
const signedOutHeaders = { "oai-authenticated-user-email": " " };
let server;

async function render() {
  return fetch(origin, {
    headers: {
      accept: "text/html",
      "oai-authenticated-user-email": "security-test@example.com",
    },
  });
}

test.before(async () => {
  server = spawn(
    process.execPath,
    [
      "node_modules/wrangler/bin/wrangler.js",
      "dev",
      "--config",
      "dist/server/wrangler.json",
      "--port",
      String(port),
    ],
    { cwd: new URL("..", import.meta.url), stdio: "ignore" },
  );

  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (server.exitCode !== null) throw new Error("Local security test server stopped unexpectedly.");
    try {
      const response = await fetch(origin, { redirect: "manual" });
      if (response.status > 0) return;
    } catch {
      // Wrangler is still starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error("Local security test server did not become ready.");
});

test.after(() => {
  server?.kill("SIGTERM");
});

test("server-renders the Sakhya everyday app", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);
  assert.match(response.headers.get("content-security-policy") ?? "", /frame-ancestors 'none'/);
  assert.equal(response.headers.get("x-content-type-options"), "nosniff");
  assert.equal(response.headers.get("x-frame-options"), "DENY");
  assert.equal(response.headers.get("referrer-policy"), "no-referrer");
  assert.match(response.headers.get("permissions-policy") ?? "", /payment=\(\)/);
  assert.match(response.headers.get("cache-control") ?? "", /no-store/);

  const html = await response.text();
  assert.match(html, /<title>Sakhya — Your everyday system<\/title>/i);
  assert.match(html, /Preparing your day/);
  assert.match(html, /Loading your private account workspace/);
  assert.doesNotMatch(html, /codex-preview|react-loading-skeleton/i);
});

test("rejects unauthenticated state access", async () => {
  const response = await fetch(`${origin}/api/state`, {
    redirect: "manual",
    headers: signedOutHeaders,
  });
  assert.equal(response.status, 401);
  assert.match(response.headers.get("cache-control") ?? "", /no-store/);
  assert.equal(response.headers.get("x-content-type-options"), "nosniff");
});

test("rejects unauthenticated assistant access", async () => {
  const response = await fetch(`${origin}/api/assistant`, {
    method: "POST",
    headers: {
      ...signedOutHeaders,
      "content-type": "application/json",
      origin,
      "x-sakhya-request": "1",
    },
    body: JSON.stringify({
      messages: [{ role: "user", text: "Tell me about today" }],
      consent: true,
    }),
  });
  assert.equal(response.status, 401);
  assert.match(response.headers.get("cache-control") ?? "", /no-store/);
});

test("protects shared lists behind authentication and same-origin mutations", async () => {
  const unauthenticated = await fetch(`${origin}/api/shared-lists`, {
    headers: signedOutHeaders,
  });
  assert.equal(unauthenticated.status, 401);

  const untrusted = await fetch(`${origin}/api/shared-lists`, {
    method: "POST",
    headers: { ...signedOutHeaders, "content-type": "application/json" },
    body: JSON.stringify({ action: "join", code: "AAAAAAAAAAAAAAAAAAAA" }),
  });
  assert.equal(untrusted.status, 403);
});

test("requires explicit consent before AI receives account context", async () => {
  const response = await fetch(`${origin}/api/assistant`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      origin,
      "oai-authenticated-user-email": "security-test@example.com",
      "x-sakhya-request": "1",
    },
    body: JSON.stringify({
      messages: [{ role: "user", text: "Tell me about today" }],
    }),
  });
  assert.equal(response.status, 403);
  assert.equal((await response.json()).code, "AI_CONSENT_REQUIRED");
});

test("keeps the model service disabled when its server secret is absent", async () => {
  const response = await fetch(`${origin}/api/assistant`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      origin,
      "oai-authenticated-user-email": "security-test@example.com",
      "x-sakhya-request": "1",
    },
    body: JSON.stringify({
      messages: [{ role: "user", text: "Tell me about today" }],
      consent: true,
    }),
  });
  assert.equal(response.status, 503);
  assert.equal((await response.json()).code, "AI_NOT_CONFIGURED");
});

test("publishes one safe AI contract for every client", async () => {
  const response = await fetch(`${origin}/api/assistant/config`, { cache: "no-store" });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    version: 1,
    profile: "Everyday",
    label: "Terra",
    model: "gpt-5.6-terra",
    provider: "openai",
  });
});

test("keeps web and Apple assistant routes on the shared model service", async () => {
  const [service, webRoute, nativeRoute, webClient, appleClient, appleAccount] = await Promise.all([
    readFile(new URL("../app/api/assistant/service.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/api/assistant/route.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/api/native/assistant/route.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/SakhyaWebApp.tsx", import.meta.url), "utf8"),
    readFile(new URL("../../AppleMobileApp/Models/AssistantService.swift", import.meta.url), "utf8"),
    readFile(new URL("../../AppleMobileApp/Models/SakhyaAIAccount.swift", import.meta.url), "utf8"),
  ]);

  assert.match(service, /model: SAKHYA_AI_CONTRACT\.model/);
  assert.match(webRoute, /answerWithSakhyaAI/);
  assert.match(nativeRoute, /answerWithSakhyaAI/);
  assert.match(webClient, /fetch\("\/api\/assistant\/config"/);
  assert.match(appleAccount, /api\/assistant\/config/);
  assert.match(appleClient, /SakhyaAssistantResponse/);
  assert.doesNotMatch(`${appleClient}\n${appleAccount}`, /gpt-5\.6-/);
});

test("uses one finance classifier and one entry point across web and Apple", async () => {
  const [service, webRoute, nativeRoute, webClient, appleClient] = await Promise.all([
    readFile(new URL("../app/api/assistant/service.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/api/finance/classify/route.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/api/native/finance/classify/route.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/SakhyaWebApp.tsx", import.meta.url), "utf8"),
    readFile(new URL("../../AppleMobileApp/Views/ExpensesView.swift", import.meta.url), "utf8"),
  ]);
  assert.match(service, /classifyFinanceWithSakhyaAI/);
  assert.match(webRoute, /classifyFinanceWithSakhyaAI/);
  assert.match(nativeRoute, /classifyFinanceWithSakhyaAI/);
  assert.match(webClient, /Add money activity/);
  assert.match(appleClient, /Add money activity/);
  assert.doesNotMatch(webClient, />Add income</);
  assert.doesNotMatch(webClient, />Add investment</);
});

test("ships the secured product source without starter artifacts", async () => {
  const [css, page, client, layout, worker, packageJson, stateRoute] = await Promise.all([
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/SakhyaWebApp.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../worker/index.ts", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
    readFile(new URL("../app/api/state/route.ts", import.meta.url), "utf8"),
  ]);

  assert.match(page, /requireChatGPTUser/);
  assert.match(client, /\/api\/state/);
  assert.match(client, /toggleListening/);
  assert.match(client, /sendMessage/);
  assert.match(client, /event\.key === "Enter" && !event\.shiftKey/);
  assert.match(client, /aria-label="Send message"/);
  assert.match(client, /"Stop voice input" : "Start voice input"/);
  assert.match(client, /aiContract\.profile.*aiContract\.label/);
  assert.match(client, /\/api\/assistant/);
  assert.match(client, /exportData/);
  assert.match(client, /validatePersistedState/);
  assert.match(client, /Remove the old plaintext browser copy/);
  assert.match(client, /Welcome/);
  assert.match(client, /This workspace belongs to you/);
  assert.match(client, /Show getting-started tour/);
  assert.match(client, /onboardingCompleted/);
  assert.match(stateRoute, /WHERE user_id = \?/);
  assert.match(client, /Today/);
  assert.match(client, /item\.id === "today".*setSelectedDate\(new Date\(\)\)/s);
  assert.match(client, /Lists/);
  assert.match(client, /Track/);
  assert.match(client, /Money/);
  assert.match(client, /Cash flow/);
  assert.match(client, /Personal P&amp;L/);
  assert.match(client, /Balance sheet/);
  assert.match(client, /unallocated/);
  assert.match(client, /Import PDF/);
  assert.match(client, /Tell Sakhya/);
  assert.match(client, /submitMoneyDraft/);
  assert.match(client, /commitStatementImport/);
  assert.match(client, /Balance/);
  assert.match(worker, /content-security-policy/);
  assert.match(layout, /Sakhya — Your everyday system/);
  assert.match(layout, /og\.png/);
  assert.match(css, /@media \(max-width:\s*720px\)/);
  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.doesNotMatch(packageJson, /react-loading-skeleton/);
  assert.doesNotMatch(client, /_sites-preview|codex-preview/);

});

test("protects the native assistant behind a signed session", async () => {
  const response = await fetch(`${origin}/api/native/assistant`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      messages: [{ role: "user", text: "How did I recover?" }],
      context: {
        generatedAt: new Date().toISOString(),
        verifiedMetrics: [],
        entries: [],
        lists: [],
        trackers: [],
      },
    }),
  });
  assert.equal(response.status, 401);
  assert.match(response.headers.get("cache-control") ?? "", /no-store/);
});
