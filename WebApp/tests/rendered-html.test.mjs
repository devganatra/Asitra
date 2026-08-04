import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

const port = 31_000 + (process.pid % 1_000);
const origin = `http://localhost:${port}`;
const persistencePath = join(tmpdir(), `asitra-integration-${process.pid}`);
const signedOutHeaders = { "oai-authenticated-user-email": " " };
const releaseManifest = JSON.parse(
  await readFile(new URL("../../release.json", import.meta.url), "utf8"),
);
const releaseVersion = releaseManifest.version;
const escapedReleaseVersion = releaseVersion.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
let server;
let serverOutput = "";

function captureServerOutput(chunk) {
  serverOutput = `${serverOutput}${chunk}`.slice(-12_000);
}

function stoppedServerError() {
  const diagnostic = serverOutput.trim();
  return new Error(
    `Local security test server stopped unexpectedly (exit ${server?.exitCode ?? "unknown"}, signal ${server?.signalCode ?? "none"}).${diagnostic ? `\n${diagnostic}` : ""}`,
  );
}

function serverStopped() {
  return !server || server.exitCode !== null || server.signalCode !== null;
}

async function startServer() {
  if (!serverStopped()) return;

  server = spawn(
    process.execPath,
    [
      "node_modules/wrangler/bin/wrangler.js",
      "dev",
      "--config",
      "dist/server/wrangler.json",
      "--port",
      String(port),
      "--persist-to",
      persistencePath,
      "--log-level",
      "debug",
      "--var",
      "BETTER_AUTH_SECRET:integration-test-secret-at-least-32-bytes-long",
      "--var",
      `ASITRA_PUBLIC_URL:${origin}`,
      "--var",
      "GOOGLE_CLIENT_ID:integration-test.apps.googleusercontent.com",
      "--var",
      "GOOGLE_CLIENT_SECRET:integration-test-google-secret",
    ],
    { cwd: new URL("..", import.meta.url), stdio: ["ignore", "pipe", "pipe"] },
  );
  server.stdout.on("data", captureServerOutput);
  server.stderr.on("data", captureServerOutput);

  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (serverStopped()) throw stoppedServerError();
    try {
      const response = await fetch(origin, { redirect: "manual" });
      if (response.status > 0) return;
    } catch {
      // Wrangler is still starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error("Local security test server did not become ready.");
}

async function integrationFetch(path, init) {
  let response;
  let lastError;
  for (let attempt = 0; attempt < 4; attempt += 1) {
    await startServer();
    try {
      response = await fetch(`${origin}${path}`, init);
      if (response.status !== 500) return response;
      await response.arrayBuffer();
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 80));
  }
  if (serverStopped()) throw stoppedServerError();
  if (response) return response;
  throw lastError;
}

async function render() {
  return integrationFetch("/", {
    headers: {
      accept: "text/html",
      "oai-authenticated-user-email": "security-test@example.com",
    },
  });
}

test.before(async () => {
  const migration = spawnSync(
    process.execPath,
    [
      "node_modules/wrangler/bin/wrangler.js",
      "d1",
      "migrations",
      "apply",
      "DB",
      "--local",
      "--persist-to",
      persistencePath,
      "--config",
      "dist/server/wrangler.json",
    ],
    { cwd: new URL("..", import.meta.url), encoding: "utf8" },
  );
  if (migration.status !== 0) {
    throw new Error(`Local D1 migrations failed:\n${migration.stdout}\n${migration.stderr}`);
  }
  await startServer();
});

test.after(() => {
  server?.kill("SIGTERM");
});

test("smoke: serves the signed-out app shell and current release", async () => {
  const signedOut = await integrationFetch("/", {
    redirect: "manual",
    headers: signedOutHeaders,
  });
  assert.equal(signedOut.status, 307);
  assert.equal(new URL(signedOut.headers.get("location")).pathname, "/login");

  const login = await integrationFetch("/login", { headers: signedOutHeaders });
  assert.equal(login.status, 200);
  const loginHTML = await login.text();
  assert.match(loginHTML, /Welcome to Asitra/);
  assert.match(loginHTML, /Continue with Google/);
  assert.match(loginHTML, new RegExp(`Release ${escapedReleaseVersion}`));

  const health = await integrationFetch("/api/health");
  assert.equal(health.status, 200);
  assert.deepEqual(await health.json(), {
    status: "ok",
    service: "asitra-web",
    version: releaseVersion,
  });
});

test("smoke: keeps private state and assistant endpoints protected", async () => {
  const state = await integrationFetch("/api/state", {
    redirect: "manual",
    headers: signedOutHeaders,
  });
  assert.equal(state.status, 401);

  const assistant = await integrationFetch("/api/assistant", {
    method: "POST",
    headers: {
      ...signedOutHeaders,
      "content-type": "application/json",
      origin,
      "x-asitra-request": "1",
    },
    body: JSON.stringify({
      messages: [{ role: "user", text: "Tell me about today" }],
      consent: true,
    }),
  });
  assert.equal(assistant.status, 401);
});

test("smoke: saves and reads a synthetic account workspace", async () => {
  const accountHeaders = {
    "oai-authenticated-user-email": `smoke-${process.pid}@example.com`,
  };
  const state = {
    onboardingCompleted: true,
    entries: [
      {
        id: `smoke-entry-${process.pid}`,
        title: "Morning walk",
        kind: "movement",
        timestamp: "2026-08-04T07:30:00.000Z",
        minutes: 30,
        source: "automated smoke test",
      },
    ],
    lists: [
      {
        id: `smoke-list-${process.pid}`,
        name: "Today",
        shared: false,
        members: 1,
        color: "#37624d",
        items: [
          {
            id: `smoke-task-${process.pid}`,
            text: "Pack walking shoes",
            done: false,
            important: true,
            urgent: false,
            boardColumnId: "todo",
          },
        ],
      },
    ],
    trackers: [],
    monthlyBudget: 900,
    savingsTarget: 2_000,
    savingsCurrent: 300,
    moneyEntries: [],
    balanceSheetItems: [],
  };

  const saved = await integrationFetch("/api/state", {
    method: "PUT",
    headers: {
      ...accountHeaders,
      "content-type": "application/json",
      origin,
      "x-asitra-request": "1",
      "if-match": "0",
    },
    body: JSON.stringify(state),
  });
  assert.equal(saved.status, 200);
  assert.equal((await saved.json()).version, 1);

  const restored = await integrationFetch("/api/state", { headers: accountHeaders });
  assert.equal(restored.status, 200);
  const restoredBody = await restored.json();
  assert.equal(restoredBody.version, 1);
  assert.equal(restoredBody.state.entries[0].title, "Morning walk");
  assert.equal(restoredBody.state.lists[0].items[0].text, "Pack walking shoes");
  assert.equal(restoredBody.state.monthlyBudget, 900);
});

test("smoke: serves public trust pages and the shared AI contract", async () => {
  const [about, privacy, terms, assistantConfig] = await Promise.all([
    integrationFetch("/about"),
    integrationFetch("/privacy"),
    integrationFetch("/terms"),
    integrationFetch("/api/assistant/config"),
  ]);
  assert.equal(about.status, 200);
  assert.equal(privacy.status, 200);
  assert.equal(terms.status, 200);
  assert.equal(assistantConfig.status, 200);
  assert.deepEqual(await assistantConfig.json(), {
    version: 1,
    profile: "Everyday",
    label: "Terra",
    model: "gpt-5.6-terra",
    provider: "openai",
  });
});

test("server-renders the Asitra everyday app", async () => {
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
  assert.match(html, /<title>Asitra — Your everyday assistant<\/title>/i);
  assert.match(html, /Preparing your day/);
  assert.match(html, /Loading your private account workspace/);
  assert.doesNotMatch(html, /codex-preview|react-loading-skeleton/i);
});

test("rejects unauthenticated state access", async () => {
  const response = await integrationFetch("/api/state", {
    redirect: "manual",
    headers: signedOutHeaders,
  });
  assert.equal(response.status, 401);
  assert.match(response.headers.get("cache-control") ?? "", /no-store/);
  assert.equal(response.headers.get("x-content-type-options"), "nosniff");
});

test("shows independent public sign-in without exposing provider secrets", async () => {
  const signedOut = await integrationFetch("/", { redirect: "manual", headers: signedOutHeaders });
  assert.equal(signedOut.status, 307);
  assert.equal(new URL(signedOut.headers.get("location")).pathname, "/login");

  const login = await integrationFetch("/login", { headers: signedOutHeaders });
  assert.equal(login.status, 200);
  const loginHTML = await login.text();
  assert.match(loginHTML, /Welcome to Asitra/);
  assert.match(loginHTML, new RegExp(`Release ${escapedReleaseVersion}`));
  assert.match(loginHTML, new RegExp(`name="asitra-release" content="${escapedReleaseVersion}"`));

  const providers = await integrationFetch("/api/auth/providers");
  assert.equal(providers.status, 200);
  const body = await providers.json();
  assert.deepEqual(body, { configured: true, google: true, apple: false });
  assert.doesNotMatch(JSON.stringify(body), /secret|key/i);

  const oauth = await integrationFetch("/api/auth/sign-in/social", {
    method: "POST",
    headers: { "content-type": "application/json", origin },
    body: JSON.stringify({ provider: "google", callbackURL: "/" }),
  });
  assert.equal(oauth.status, 200);
  const oauthBody = await oauth.json();
  assert.match(oauthBody.url, /^https:\/\/accounts\.google\.com\//);
  assert.doesNotMatch(JSON.stringify(oauthBody), /integration-test-google-secret/);
});

test("publishes one traceable release number", async () => {
  const response = await integrationFetch("/api/health");
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    status: "ok",
    service: "asitra-web",
    version: releaseVersion,
  });

  const [releaseSource, healthSource, clientSource, loginSource] = await Promise.all([
    readFile(new URL("../app/release.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/api/health/route.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/AsitraWebApp.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/login/LoginPage.tsx", import.meta.url), "utf8"),
  ]);
  assert.match(releaseSource, new RegExp(`ASITRA_RELEASE = "${escapedReleaseVersion}"`));
  assert.match(healthSource, /version: ASITRA_RELEASE/);
  assert.match(clientSource, /ASITRA_RELEASE_LABEL/);
  assert.match(loginSource, /ASITRA_RELEASE_LABEL/);
});

test("publishes public trust, privacy, and terms pages", async () => {
  const [aboutResponse, privacyResponse, termsResponse] = await Promise.all([
    integrationFetch("/about"),
    integrationFetch("/privacy"),
    integrationFetch("/terms"),
  ]);
  assert.equal(aboutResponse.status, 200);
  assert.equal(privacyResponse.status, 200);
  assert.equal(termsResponse.status, 200);
  const [about, privacy, terms] = await Promise.all([
    aboutResponse.text(),
    privacyResponse.text(),
    termsResponse.text(),
  ]);
  assert.match(about, /Your everyday assistant, built around your life/);
  assert.match(about, /does not collect your provider password/i);
  assert.match(privacy, /Your life data stays under your control/);
  assert.match(privacy, /Cloudflare D1/);
  assert.match(privacy, /withdraw AI consent/i);
  assert.match(terms, /Clear terms for using Asitra/);
  assert.match(terms, /not a medical provider, financial adviser/i);
});

test("isolates records and R2 attachments, exports data, creates recovery points, and deletes everything", async () => {
  const ownerEmail = `owner-${process.pid}@example.com`;
  const otherEmail = `other-${process.pid}@example.com`;
  const ownerHeaders = { "oai-authenticated-user-email": ownerEmail };
  const state = {
    onboardingCompleted: true,
    entries: [], lists: [], trackers: [],
    monthlyBudget: 900, savingsTarget: 2000, savingsCurrent: 300,
    moneyEntries: [], balanceSheetItems: [],
  };
  const saved = await integrationFetch("/api/state", {
    method: "PUT",
    headers: { ...ownerHeaders, "content-type": "application/json", origin, "x-asitra-request": "1", "if-match": "0" },
    body: JSON.stringify(state),
  });
  assert.equal(saved.status, 200);
  assert.equal((await saved.json()).version, 1);

  const otherState = await integrationFetch("/api/state", { headers: { "oai-authenticated-user-email": otherEmail } });
  assert.equal(otherState.status, 204);

  const secondSave = await integrationFetch("/api/state", {
    method: "PUT",
    headers: { ...ownerHeaders, "content-type": "application/json", origin, "x-asitra-request": "1", "if-match": "1" },
    body: JSON.stringify({ ...state, monthlyBudget: 950 }),
  });
  assert.equal(secondSave.status, 200);
  const recovery = await integrationFetch("/api/account/recovery", { headers: ownerHeaders });
  assert.equal(recovery.status, 200);
  assert.equal((await recovery.json()).revisions.length, 1);

  const image = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const uploaded = await integrationFetch("/api/attachments", {
    method: "POST",
    headers: { ...ownerHeaders, "content-type": "image/png", origin, "x-asitra-request": "1", "x-asitra-filename": "private.png" },
    body: image,
  });
  assert.equal(uploaded.status, 201);
  const attachment = await uploaded.json();
  assert.match(attachment.url, /^\/api\/attachments\/[0-9a-f-]{36}$/i);
  assert.equal((await integrationFetch(attachment.url, { headers: ownerHeaders })).status, 200);
  assert.equal((await integrationFetch(attachment.url, { headers: { "oai-authenticated-user-email": otherEmail } })).status, 404);

  const exported = await integrationFetch("/api/account/export", { headers: ownerHeaders });
  assert.equal(exported.status, 200);
  assert.match(exported.headers.get("content-disposition") ?? "", /asitra-data-/);
  const exportBody = await exported.json();
  assert.equal(exportBody.state.monthlyBudget, 950);
  assert.equal(exportBody.attachments.length, 1);

  const deleted = await integrationFetch("/api/state", {
    method: "DELETE",
    headers: { ...ownerHeaders, origin, "x-asitra-request": "1", "x-asitra-confirm-delete": "DELETE MY ACCOUNT" },
  });
  assert.equal(deleted.status, 200);
  assert.equal((await integrationFetch(attachment.url, { headers: ownerHeaders })).status, 404);
  assert.equal((await integrationFetch("/api/state", { headers: ownerHeaders })).status, 204);
});

test("rejects unauthenticated assistant access", async () => {
  const response = await integrationFetch("/api/assistant", {
    method: "POST",
    headers: {
      ...signedOutHeaders,
      "content-type": "application/json",
      origin,
      "x-asitra-request": "1",
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
  const unauthenticated = await integrationFetch("/api/shared-lists", {
    headers: signedOutHeaders,
  });
  assert.equal(unauthenticated.status, 401);

  const untrusted = await integrationFetch("/api/shared-lists", {
    method: "POST",
    headers: { ...signedOutHeaders, "content-type": "application/json" },
    body: JSON.stringify({ action: "join", code: "AAAAAAAAAAAAAAAAAAAA" }),
  });
  assert.equal(untrusted.status, 403);
});

test("requires explicit consent before AI receives account context", async () => {
  const response = await integrationFetch("/api/assistant", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      origin,
      "oai-authenticated-user-email": "security-test@example.com",
      "x-asitra-request": "1",
    },
    body: JSON.stringify({
      messages: [{ role: "user", text: "Tell me about today" }],
    }),
  });
  assert.equal(response.status, 403);
  assert.equal((await response.json()).code, "AI_CONSENT_REQUIRED");
});

test("keeps the model service disabled when its server secret is absent", async () => {
  const consent = await integrationFetch("/api/account/consent", {
    method: "PUT",
    headers: {
      "content-type": "application/json",
      origin,
      "oai-authenticated-user-email": "security-test@example.com",
      "x-asitra-request": "1",
    },
    body: JSON.stringify({ purpose: "ai_analysis", granted: true }),
  });
  assert.equal(consent.status, 200);
  const response = await integrationFetch("/api/assistant", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      origin,
      "oai-authenticated-user-email": "security-test@example.com",
      "x-asitra-request": "1",
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
  const response = await integrationFetch("/api/assistant/config", { cache: "no-store" });
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
    readFile(new URL("../app/AsitraWebApp.tsx", import.meta.url), "utf8"),
    readFile(new URL("../../AppleMobileApp/Models/AssistantService.swift", import.meta.url), "utf8"),
    readFile(new URL("../../AppleMobileApp/Models/AsitraAIAccount.swift", import.meta.url), "utf8"),
  ]);

  assert.match(service, /model: ASITRA_AI_CONTRACT\.model/);
  assert.match(webRoute, /answerWithAsitraAI/);
  assert.match(nativeRoute, /answerWithAsitraAI/);
  assert.match(webClient, /fetch\("\/api\/assistant\/config"/);
  assert.match(appleAccount, /api\/assistant\/config/);
  assert.match(appleClient, /AsitraAssistantResponse/);
  assert.doesNotMatch(`${appleClient}\n${appleAccount}`, /gpt-5\.6-/);
});

test("uses one finance classifier and one entry point across web and Apple", async () => {
  const [service, webRoute, nativeRoute, webClient, appleClient] = await Promise.all([
    readFile(new URL("../app/api/assistant/service.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/api/finance/classify/route.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/api/native/finance/classify/route.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/AsitraWebApp.tsx", import.meta.url), "utf8"),
    readFile(new URL("../../AppleMobileApp/Views/ExpensesView.swift", import.meta.url), "utf8"),
  ]);
  assert.match(service, /classifyFinanceWithAsitraAI/);
  assert.match(webRoute, /classifyFinanceWithAsitraAI/);
  assert.match(nativeRoute, /classifyFinanceWithAsitraAI/);
  assert.match(webClient, /Add money activity/);
  assert.match(appleClient, /Add money activity/);
  assert.doesNotMatch(webClient, />Add income</);
  assert.doesNotMatch(webClient, />Add investment</);
});

test("ships the secured product source without starter artifacts", async () => {
  const [css, page, client, layout, worker, packageJson, stateRoute] = await Promise.all([
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/AsitraWebApp.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../worker/index.ts", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
    readFile(new URL("../app/api/state/route.ts", import.meta.url), "utf8"),
  ]);

  assert.match(page, /betterAuthSession/);
  assert.match(page, /redirect\("\/login"\)/);
  assert.match(page, /chatGPTSignOutPath/);
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
  assert.match(client, /Account menu for/);
  assert.match(client, /End this Asitra session on this browser/);
  assert.match(client, /fetch\(logoutPath, \{[\s\S]*?"content-type": "application\/json"[\s\S]*?body: JSON\.stringify\(\{\}\)/);
  assert.match(client, /if \(!response\?\.ok\)[\s\S]*?session is still active/);
  assert.match(client, /window\.location\.replace\("\/login"\)/);
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
  assert.match(client, /Tell Asitra/);
  assert.match(client, /submitMoneyDraft/);
  assert.match(client, /commitStatementImport/);
  assert.match(client, /Balance/);
  assert.match(worker, /content-security-policy/);
  assert.match(layout, /Asitra — Your everyday assistant/);
  assert.match(layout, /og\.png/);
  assert.match(css, /@media \(max-width:\s*720px\)/);
  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.doesNotMatch(packageJson, /react-loading-skeleton/);
  assert.doesNotMatch(client, /_sites-preview|codex-preview/);

});

test("protects the native assistant behind a signed session", async () => {
  const nativeRoute = await readFile(new URL("../app/api/native/assistant/route.ts", import.meta.url), "utf8");
  assert.match(nativeRoute, /authenticatedNativeUser\(request\)/);
  assert.match(nativeRoute, /if \(!userId\).*401/s);
});
