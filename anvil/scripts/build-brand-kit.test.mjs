import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { fileURLToPath } from "node:url";
import { buildKit, sources } from "./build-brand-kit.mjs";

const expected = ["BRAND.md", "icon-1024.png", "mark-16-mono.svg", "mark-16.svg", "mark-grid.svg", "mark-mono.svg", "mark.svg", "tokens.json", "wordmark-lockup.svg"];
const list = (zip) => execFileSync("unzip", ["-Z1", zip], { encoding: "utf8" }).trim().split("\n").sort();

const published = fileURLToPath(new URL("../public/brand/foundry-brand.zip", import.meta.url));
const entry = (zip, name) => execFileSync("unzip", ["-p", zip, name], { maxBuffer: 1 << 26 });

function assertHoldsSources(zip) {
  for (const source of sources) assert.ok(entry(zip, basename(source)).equals(readFileSync(source)), `${basename(source)} differs from its source`);
}

test("the kit holds exactly the brand files, flat", () => {
  const zip = join(mkdtempSync(join(tmpdir(), "brand-kit-")), "kit.zip");
  buildKit(zip);
  assert.deepEqual(list(zip), expected);
});

test("a freshly built kit holds the current source bytes", () => {
  const zip = join(mkdtempSync(join(tmpdir(), "brand-kit-")), "kit.zip");
  buildKit(zip);
  assertHoldsSources(zip);
});

test("the published kit holds exactly the brand files, as they are in the source", () => {
  assert.deepEqual(list(published), expected);
  assertHoldsSources(published);
});
