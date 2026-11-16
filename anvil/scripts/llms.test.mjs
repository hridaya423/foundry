import { test } from "node:test";
import assert from "node:assert/strict";

process.env.FOUNDRY_VERSION = "9.9.9";
const { GET } = await import("../app/llms.txt/route.ts");
const { foundryDownloadUrl, repoUrl, sitePages, siteUrl } = await import("../app/site.ts");
const { proofFigures } = await import("../app/proof.ts");

test("llms.txt is plain text in the llmstxt.org shape", async () => {
  const response = GET();
  assert.equal(response.headers.get("content-type"), "text/plain; charset=utf-8");
  const text = await response.text();
  assert.match(text, /^# Foundry\n\n> \S.*\n\n/);
  assert.match(text, /^- Latest version: 9\.9\.9\.$/m);
});

test("llms.txt links every page, the source, the DMG and the raw benchmark file", async () => {
  const text = await GET().text();
  for (const path of sitePages) assert.ok(text.includes(`](${new URL(path, siteUrl).href}): `), `${path} missing`);
  for (const url of [repoUrl, foundryDownloadUrl, "https://raw.githubusercontent.com/hridaya423/foundry/main/docs/benchmarks/latest.json"]) {
    assert.ok(text.includes(`](${url})`), `${url} missing`);
  }
});

test("llms.txt quotes every benchmark figure with its version and machine", async () => {
  const text = await GET().text();
  for (const { label, version, machine } of proofFigures()) assert.ok(text.includes(`${label} (${version}; ${machine}).`), label);
});
