import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (name) => readFileSync(new URL(`../../docs/brand/mark/${name}`, import.meta.url), "utf8");
const straightCoordinates = (svg) => [...svg.matchAll(/\b[MHVL]\s*(-?\d+(?:\.\d+)?)/g)].map((m) => Number(m[1]))
  .concat([...svg.matchAll(/\b(?:x|y|width|height)="(-?\d+(?:\.\d+)?)"/g)].map((m) => Number(m[1])));

test("the master sits on a 120 unit square", () => {
  assert.match(read("mark.svg"), /viewBox="0 0 120 120"/);
});

test("every straight edge of the master snaps to the half-tile grid", () => {
  for (const value of straightCoordinates(read("mark.svg"))) assert.equal(value % 5, 0, `${value} is off grid`);
});

test("the 16 px glyph sits on whole pixels", () => {
  const svg = read("mark-16.svg");
  assert.match(svg, /viewBox="0 0 16 16"/);
  for (const value of straightCoordinates(svg)) assert.ok(Number.isInteger(value), `${value} is not a whole pixel`);
});

test("orange appears on exactly one element, the cast", () => {
  for (const name of ["mark.svg", "mark-16.svg"]) {
    const fills = [...read(name).matchAll(/fill="(#[0-9a-f]{6})"/g)].map((m) => m[1]);
    assert.equal(fills.filter((fill) => fill === "#fa6428").length, 1, name);
  }
});

test("monochrome masters use currentColor only", () => {
  for (const name of ["mark-mono.svg", "mark-16-mono.svg"]) {
    const fills = [...read(name).matchAll(/fill="([^"]+)"/g)].map((m) => m[1]);
    assert.ok(fills.length > 0 && fills.every((fill) => fill === "currentColor"), name);
  }
});
