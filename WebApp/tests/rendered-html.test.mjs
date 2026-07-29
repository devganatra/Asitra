import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import test from "node:test";

const port = 31_000 + (process.pid % 1_000);
const origin = `http://localhost:${port}`;
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
  const response = await fetch(`${origin}/api/state`, { redirect: "manual" });
  assert.equal(response.status, 401);
  assert.match(response.headers.get("cache-control") ?? "", /no-store/);
  assert.equal(response.headers.get("x-content-type-options"), "nosniff");
});

test("rejects unauthenticated assistant access", async () => {
  const response = await fetch(`${origin}/api/assistant`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      origin,
      "x-sakhya-request": "1",
    },
    body: JSON.stringify({
      messages: [{ role: "user", text: "Tell me about today" }],
    }),
  });
  assert.equal(response.status, 401);
  assert.match(response.headers.get("cache-control") ?? "", /no-store/);
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
    }),
  });
  assert.equal(response.status, 503);
  assert.equal((await response.json()).code, "AI_NOT_CONFIGURED");
});

test("ships the secured product source without starter artifacts", async () => {
  const [css, page, client, layout, worker, packageJson] = await Promise.all([
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/SakhyaWebApp.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../worker/index.ts", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
  ]);

  assert.match(page, /requireChatGPTUser/);
  assert.match(client, /\/api\/state/);
  assert.match(client, /toggleListening/);
  assert.match(client, /sendMessage/);
  assert.match(client, /event\.key === "Enter" && !event\.shiftKey/);
  assert.match(client, /aria-label="Send message"/);
  assert.match(client, /"Stop voice input" : "Start voice input"/);
  assert.match(client, /Everyday · Terra/);
  assert.match(client, /\/api\/assistant/);
  assert.match(client, /exportData/);
  assert.match(client, /validatePersistedState/);
  assert.match(client, /Remove the old plaintext browser copy/);
  assert.match(client, /Today/);
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
