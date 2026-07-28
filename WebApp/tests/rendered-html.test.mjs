import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";


async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the Sakhya everyday app", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>Sakhya — Your everyday system<\/title>/i);
  assert.match(html, /Make today feel lighter/);
  assert.match(html, /What happened\?/);
  assert.match(html, /Ask Sakhya/);
  assert.match(html, /Saved locally/);
  assert.doesNotMatch(html, /codex-preview|react-loading-skeleton/i);
});

test("ships the product source without starter artifacts", async () => {
  const [css, page, layout, packageJson] = await Promise.all([
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
  ]);

  assert.match(page, /localStorage/);
  assert.match(page, /toggleListening/);
  assert.match(page, /sendMessage/);
  assert.match(page, /exportData/);
  assert.match(page, /Today/);
  assert.match(page, /Lists/);
  assert.match(page, /Track/);
  assert.match(page, /Money/);
  assert.match(page, /Balance/);
  assert.match(layout, /Sakhya — Your everyday system/);
  assert.match(layout, /og\.png/);
  assert.match(css, /@media \(max-width:\s*720px\)/);
  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.doesNotMatch(packageJson, /react-loading-skeleton/);
  assert.doesNotMatch(page, /_sites-preview|codex-preview/);

});
