import { test } from "node:test";
import assert from "node:assert/strict";
import { hashForProgress, stopForHash } from "../app/foundry/story/story-hash.ts";
import { toolsStop } from "../app/foundry/story/tools-motion.ts";
import { storyEnd } from "../app/foundry/story/download-motion.ts";

test("a section hash lands on that section's stop", () => {
  assert.equal(stopForHash("#tools"), toolsStop);
  assert.equal(stopForHash("#download"), storyEnd);
  assert.equal(stopForHash("#nope"), null);
});

test("the hash follows the section in view and clears at the hero", () => {
  assert.equal(hashForProgress(0), "");
  assert.equal(hashForProgress(stopForHash("#clipboard")), "#clipboard");
  for (const hash of ["#file-shelf", "#clipboard", "#tools", "#memory", "#download"]) assert.equal(hashForProgress(stopForHash(hash)), hash);
});
