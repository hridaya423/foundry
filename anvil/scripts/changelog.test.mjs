import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { parseReleaseNotes, releases } from "../app/changelog.ts";

const notesDirectory = new URL("../../docs/release-notes/", import.meta.url);

test("parses a version, sections and items", () => {
  assert.deepEqual(parseReleaseNotes("# Foundry 1.2.0\n\n## Brand\n- a\n- b"), {
    version: "1.2.0",
    sections: [{ title: "Brand", items: ["a", "b"] }],
  });
});

test("keeps intro paragraphs, section paragraphs and tables", () => {
  const notes = parseReleaseNotes("# Foundry 1.0.0\n\nHello.\n\n## Speed\n\nNote.\n\n| | a | b |\n| --- | --- | --- |\n| row | 1 | 2 |\n\n- x");
  assert.deepEqual(notes, {
    version: "1.0.0",
    intro: ["Hello."],
    sections: [{ title: "Speed", items: ["x"], paragraphs: ["Note."], table: [["", "a", "b"], ["row", "1", "2"]] }],
  });
});

test("unknown markdown throws with its line number", () => {
  assert.throws(() => parseReleaseNotes("# Foundry 1.2.0\n\n## Brand\n- a\n> quote"), /line 5/);
  assert.throws(() => parseReleaseNotes("# Foundry 1.2.0\n\n### Deep\n- a"), /line 3/);
  assert.throws(() => parseReleaseNotes("# Foundry 1.2.0\n\n## Brand\n  - nested"), /line 4/);
});

test("every release note file parses and has a date", () => {
  const files = readdirSync(notesDirectory).filter((name) => name.endsWith(".md"));
  assert.ok(files.length > 0);
  for (const name of files) {
    const notes = parseReleaseNotes(readFileSync(new URL(name, notesDirectory), "utf8"));
    assert.equal(`${notes.version}.md`, name);
  }
  const all = releases();
  assert.equal(all.length, files.length);
  for (const { version, date } of all) assert.match(date, /^\d{4}-\d{2}-\d{2}$/, `${version} has no date`);
});

test("releases are newest first", () => {
  const versions = releases().map((release) => release.version);
  const sorted = [...versions].sort((a, b) => b.localeCompare(a, undefined, { numeric: true }));
  assert.deepEqual(versions, sorted);
});

test("the sitemap dates every page with the newest release date", async () => {
  const { default: sitemap } = await import("../app/sitemap.ts");
  const { latestReleaseDate } = await import("../app/changelog.ts");
  assert.equal(latestReleaseDate(), releases()[0].date);
  for (const { lastModified } of sitemap()) assert.equal(lastModified, latestReleaseDate());
});
