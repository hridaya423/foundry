import { releases } from "../../changelog";
import { siteUrl } from "../../site";

export const dynamic = "force-static";

const escape = (text: string) => text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

export function GET() {
  const all = releases();
  const page = new URL("/changelog", siteUrl).href;
  const entries = all.map(({ version, date, sections }) => `  <entry>
    <id>${page}#v${version}</id>
    <title>Foundry ${version}</title>
    <link href="${page}#v${version}" />
    <updated>${date}T00:00:00Z</updated>
    <summary>${escape(sections.map((section) => section.title).join(", "))}</summary>
  </entry>`);
  const feed = `<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>${page}</id>
  <title>Foundry changelog</title>
  <link href="${page}" />
  <link rel="self" type="application/atom+xml" href="${new URL("/changelog/feed.xml", siteUrl).href}" />
  <updated>${all[0].date}T00:00:00Z</updated>
  <author><name>Foundry</name></author>
${entries.join("\n")}
</feed>
`;
  return new Response(feed, { headers: { "content-type": "application/atom+xml; charset=utf-8" } });
}
