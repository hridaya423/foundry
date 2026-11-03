import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { cssFrom, moduleFrom } from "./build-tokens.mjs";

test("every colour becomes a --f custom property", () => {
  const css = cssFrom({ color: { ink: "#0f0d0c", orange: "#fa6428" }, tile: {}, motion: {} });
  assert.match(css, /--f-ink: #0f0d0c;/);
  assert.match(css, /--f-orange: #fa6428;/);
});

test("tile and motion tokens are emitted with their group prefix", () => {
  const css = cssFrom({ color: {}, tile: { radius: "18%" }, motion: { "ease-out": "cubic-bezier(0.23, 1, 0.32, 1)" } });
  assert.match(css, /--f-tile-radius: 18%;/);
  assert.match(css, /--f-ease-out: cubic-bezier\(0\.23, 1, 0\.32, 1\);/);
});

test("a colour that is not #rrggbb is rejected", () => {
  assert.throws(() => cssFrom({ color: { ink: "black" }, tile: {}, motion: {} }), /ink/);
});

test("the committed tokens.css matches docs/brand/tokens.json", () => {
  const tokens = JSON.parse(readFileSync(new URL("../../docs/brand/tokens.json", import.meta.url)));
  assert.equal(readFileSync(new URL("../app/foundry/tokens.css", import.meta.url), "utf8"), cssFrom(tokens));
});

test("the committed tokens.ts matches docs/brand/tokens.json", () => {
  const tokens = JSON.parse(readFileSync(new URL("../../docs/brand/tokens.json", import.meta.url)));
  assert.equal(readFileSync(new URL("../app/foundry/tokens.ts", import.meta.url), "utf8"), moduleFrom(tokens));
});
