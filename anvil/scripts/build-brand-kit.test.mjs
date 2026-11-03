import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { buildKit } from "./build-brand-kit.mjs";

const expected = ["BRAND.md", "icon-1024.png", "mark-16-mono.svg", "mark-16.svg", "mark-grid.svg", "mark-mono.svg", "mark.svg", "tokens.json", "wordmark-lockup.svg"];
const list = (zip) => execFileSync("unzip", ["-Z1", zip], { encoding: "utf8" }).trim().split("\n").sort();

test("the kit holds exactly the brand files, flat", () => {
  const zip = join(mkdtempSync(join(tmpdir(), "brand-kit-")), "kit.zip");
  buildKit(zip);
  assert.deepEqual(list(zip), expected);
});

test("the published kit holds exactly the brand files", () => {
  assert.deepEqual(list(fileURLToPath(new URL("../public/brand/foundry-brand.zip", import.meta.url))), expected);
});
