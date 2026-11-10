import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { routesFrom, shotName } from "./qa.mjs";

const config = JSON.parse(readFileSync(new URL("./qa-routes.json", import.meta.url)));

test("story route expands into one capture per stop and width", () => {
  const captures = routesFrom(config).filter((capture) => capture.path === "/");
  assert.equal(captures.length, 6 * config.widths.length);
  assert.deepEqual(captures[0], { path: "/", width: 1440, height: 900, stop: 0, status: 200 });
});

test("the missing page is expected to answer 404", () => {
  assert.deepEqual(new Set(routesFrom(config).filter((capture) => capture.path === "/missing-page").map((capture) => capture.status)), new Set([404]));
});

test("plain routes capture once per width with no stop", () => {
  const captures = routesFrom(config).filter((capture) => capture.path === "/methodology");
  assert.deepEqual(captures.map((capture) => capture.width), config.widths);
  assert.equal(captures[0].stop, undefined);
});

test("shot names are stable and sortable", () => {
  assert.equal(shotName({ path: "/", width: 1440, stop: 1.3 }), "home-1440-at1.300.png");
  assert.equal(shotName({ path: "/missing-page", width: 390 }), "missing-page-0390.png");
});
