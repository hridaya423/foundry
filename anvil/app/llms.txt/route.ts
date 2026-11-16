import { formatFigure, proofFigures, readLatest } from "../proof";
import { authorName, foundryDownloadUrl, foundryVersion, hubUrl, repoUrl, siteDescription, sitePages, siteUrl } from "../site";

export const dynamic = "force-static";

const pages = {
  "/": ["Home", "What Foundry does, with measured numbers and a download link."],
  "/methodology": ["Methodology", "How the memory and panel open times were measured, and their limits."],
  "/proof": ["Proof", "Every number Foundry quotes, with the machine, version, date and source file."],
  "/faq": ["FAQ", "Short answers on Raycast, Spotlight and Alfred, Script Commands, snippets, privacy, updates and size."],
  "/changelog": ["Changelog", "What changed in each release, newest first."],
  "/privacy": ["Privacy", "Every request Foundry sends off the Mac, and how to avoid each one."],
  "/brand": ["Brand", "The mark, colours and type, with a kit of the master files."],
} satisfies Record<(typeof sitePages)[number], [string, string]>;

const benchmarkUrl = `${repoUrl.replace("github.com", "raw.githubusercontent.com")}/main/docs/benchmarks/latest.json`;

export function GET() {
  const latest = readLatest();
  const text = `# Foundry

> ${siteDescription}

- Free and open source under the MIT licence.
- Needs an Apple silicon Mac with macOS 14 or later. Release builds are arm64 only.
- Latest version: ${foundryVersion}.
- Made by ${authorName} (${hubUrl}).

## Measured figures

Each figure names its version and machine. Captured ${latest.capturedAt}.

${proofFigures(latest).map((figure) => `- ${formatFigure(figure)}: ${figure.label} (${figure.version}; ${figure.machine}).`).join("\n")}

## Pages

${sitePages.map((path) => `- [${pages[path][0]}](${new URL(path, siteUrl).href}): ${pages[path][1]}`).join("\n")}

## Download and source

- [Foundry.dmg](${foundryDownloadUrl}): the latest release, signed with a Developer ID and notarized by Apple.
- [Source on GitHub](${repoUrl}): the Swift app and this website.
- [Benchmark data](${benchmarkUrl}): every figure with its version, machine, date and raw record.
`;
  return new Response(text, { headers: { "content-type": "text/plain; charset=utf-8" } });
}
