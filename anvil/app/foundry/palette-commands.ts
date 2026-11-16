import { calculate } from "./calculate";
import { foundryDownloadUrl, repoUrl } from "../site";

export type PaletteCommand = { id: string; name: string; kind: string; href: string; keywords?: string };

export const commands: PaletteCommand[] = [
  { id: "download", name: "Download Foundry", kind: "Action", href: foundryDownloadUrl, keywords: "install dmg get mac" },
  { id: "file-shelf", name: "Convert Files", kind: "Section", href: "/#file-shelf", keywords: "png heic image background shelf" },
  { id: "clipboard", name: "Clipboard History", kind: "Section", href: "/#clipboard", keywords: "copy paste clip" },
  { id: "tools", name: "Tools", kind: "Section", href: "/#tools", keywords: "calculator translate snippets ai video developer" },
  { id: "memory", name: "Memory Use", kind: "Section", href: "/#memory", keywords: "ram raycast 81" },
  { id: "proof", name: "Proof", kind: "Page", href: "/proof", keywords: "benchmarks numbers latency" },
  { id: "methodology", name: "Methodology", kind: "Page", href: "/methodology", keywords: "how measured memory" },
  { id: "faq", name: "FAQ", kind: "Page", href: "/faq", keywords: "questions raycast spotlight alfred intel updates" },
  { id: "changelog", name: "Changelog", kind: "Page", href: "/changelog", keywords: "release notes version" },
  { id: "privacy", name: "Privacy", kind: "Page", href: "/privacy", keywords: "data network telemetry" },
  { id: "brand", name: "Brand", kind: "Page", href: "/brand", keywords: "logo mark colours press kit" },
  { id: "github", name: "Source on GitHub", kind: "Link", href: repoUrl, keywords: "code repo open source" },
];

export function search(query: string): PaletteCommand[] {
  const text = query.trim().toLowerCase();
  if (!text) return commands;
  const answer = calculate(text);
  if (answer !== null) return [{ id: "answer", name: answer, kind: "Calculator", href: "" }];
  const scored = commands.flatMap((command) => {
    const name = command.name.toLowerCase();
    const score = name.startsWith(text) ? 0 : name.split(" ").some((word) => word.startsWith(text)) ? 1 : `${name} ${command.keywords ?? ""}`.includes(text) ? 2 : -1;
    return score < 0 ? [] : [{ command, score }];
  });
  return scored.sort((a, b) => a.score - b.score).map(({ command }) => command);
}
