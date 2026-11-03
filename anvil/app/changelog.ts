import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

export type ReleaseSection = { title: string; items: string[]; paragraphs?: string[]; table?: string[][] };
export type ReleaseNotes = { version: string; intro?: string[]; sections: ReleaseSection[] };
export type Release = ReleaseNotes & { date: string };

const releaseDates: Record<string, string> = {
  "1.1.0": "2026-09-25",
  "1.2.0": "2026-10-08",
};

export function parseReleaseNotes(markdown: string): ReleaseNotes {
  const notes = { version: "", sections: [] } as ReleaseNotes;
  let section: ReleaseSection | undefined;
  markdown.split("\n").forEach((line, index) => {
    const fail = () => { throw new Error(`Unsupported release notes markdown on line ${index + 1}: ${line}`); };
    if (!line.trim()) return;
    const title = line.match(/^# Foundry (\d+\.\d+\.\d+)$/);
    if (title) { notes.version = title[1]; return; }
    const heading = line.match(/^## (.+)$/);
    if (heading) { notes.sections.push(section = { title: heading[1], items: [] }); return; }
    const bullet = line.match(/^- (.+)$/);
    if (bullet) return section ? void section.items.push(bullet[1]) : fail();
    if (/^\|.*\|$/.test(line)) {
      if (!section) return fail();
      if (/^[|\s:-]+$/.test(line)) return;
      (section.table ??= []).push(line.split("|").slice(1, -1).map((cell) => cell.trim()));
      return;
    }
    if (/^(\s|#|>|[-*+] |\d+\. |\|)/.test(line)) return fail();
    if (section) (section.paragraphs ??= []).push(line);
    else (notes.intro ??= []).push(line);
  });
  return notes;
}

export function releases(): Release[] {
  const directory = join(process.cwd(), "../docs/release-notes");
  return readdirSync(directory)
    .filter((name) => name.endsWith(".md"))
    .map((name) => parseReleaseNotes(readFileSync(join(directory, name), "utf8")))
    .map((notes) => ({ ...notes, date: releaseDates[notes.version] }))
    .sort((a, b) => b.version.localeCompare(a.version, undefined, { numeric: true }));
}
