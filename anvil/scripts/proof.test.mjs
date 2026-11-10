import { test } from "node:test";
import assert from "node:assert/strict";
import { formatFigure, proofFigures, stripFigures } from "../app/proof.ts";

const figure = (id, source = "docs/benchmarks/x.json") => ({ id, value: 1, unit: "ms", label: id, sentence: id, machine: "m", version: "v", date: "2026-01-01", source });

test("formatFigure keeps three significant digits", () => {
  assert.equal(formatFigure({ value: 115.2, unit: "MB" }), "115 MB");
  assert.equal(formatFigure({ value: 8.1, unit: "MB" }), "8.1 MB");
  assert.equal(formatFigure({ value: 19.11, unit: "ms" }), "19.1 ms");
  assert.equal(formatFigure({ value: 620.2, unit: "MB" }), "620 MB");
});

test("formatFigure writes percent and counts without a gap or fraction", () => {
  assert.equal(formatFigure({ value: 81.4, unit: "%" }), "81%");
  assert.equal(formatFigure({ value: 0, unit: "dependencies" }), "0 dependencies");
});

test("proofFigures throws when a figure has no source", () => {
  assert.throws(() => proofFigures({ capturedAt: "", figures: [figure("a"), figure("b", "")] }), /b/);
  assert.equal(proofFigures({ capturedAt: "", figures: [figure("a")] }).length, 1);
});

test("stripFigures returns latency, memory, size, dependencies in order, all sourced", () => {
  const figures = stripFigures();
  assert.deepEqual(figures.map(({ id }) => id), ["open-latency", "memory-vs-raycast", "app-size", "dependencies"]);
  for (const item of figures) assert.ok(item.source);
  assert.match(figures[0].label, /p50/);
  assert.match(figures[0].label, /p95/);
  assert.match(figures[0].label, /M4 Pro/);
  assert.match(figures[1].label, /vs Raycast 2\.5\.3/);
});

test("every figure source exists in the repository", async () => {
  const { existsSync } = await import("node:fs");
  for (const { id, source } of proofFigures()) assert.ok(existsSync(new URL(`../../${source}`, import.meta.url)), `${id}: ${source} missing`);
});

test("the app size beside the current version names the version it was measured on", async () => {
  const { appSizeLabel } = await import("../app/proof.ts");
  const figure = proofFigures().find(({ id }) => id === "app-size");
  assert.equal(appSizeLabel(), `${formatFigure(figure)} in ${figure.version.replace(/^Foundry /, "")}`);
  assert.match(appSizeLabel(), / in \d+\.\d+\.\d+$/);
});
