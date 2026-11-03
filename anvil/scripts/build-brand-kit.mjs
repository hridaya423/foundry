import { execFileSync } from "node:child_process";
import { mkdirSync, rmSync } from "node:fs";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";

const repo = (path) => fileURLToPath(new URL(`../../${path}`, import.meta.url));
const mark = ["mark.svg", "mark-mono.svg", "mark-16.svg", "mark-16-mono.svg", "mark-grid.svg", "wordmark-lockup.svg"].map((name) => `docs/brand/mark/${name}`);
const sources = [...mark, "Supporting/icon-1024.png", "docs/brand/tokens.json", "docs/brand/BRAND.md"].map(repo);

export function buildKit(out = repo("anvil/public/brand/foundry-brand.zip")) {
  mkdirSync(dirname(out), { recursive: true });
  rmSync(out, { force: true });
  execFileSync("zip", ["-j", "-X", "-q", out, ...sources]);
  return out;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) console.log(buildKit());
