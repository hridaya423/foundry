import { test } from "node:test";
import assert from "node:assert/strict";
import { commands, search } from "../app/foundry/palette-commands.ts";

test("every command has an id, name, kind and a target", () => {
  for (const command of commands) {
    assert.ok(command.id && command.name && command.kind, command.id);
    assert.ok(command.href, command.id);
  }
  assert.equal(new Set(commands.map((command) => command.id)).size, commands.length);
});

test("an empty query lists every command in order", () => {
  assert.deepEqual(search("").map((result) => result.id), commands.map((command) => command.id));
});

test("a page name finds that page first", () => {
  assert.equal(search("proof")[0].id, "proof");
  assert.equal(search("clip")[0].id, "clipboard");
});

test("arithmetic answers first", () => {
  const [first] = search("24*18");
  assert.equal(first.kind, "Calculator");
  assert.equal(first.name, "432");
});

test("nothing matches nonsense", () => {
  assert.deepEqual(search("zzzz"), []);
});
