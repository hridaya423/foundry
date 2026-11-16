import type { Metadata } from "next";
import { Fragment } from "react";
import { SiteFooter, SiteHeader } from "../foundry/site-chrome";
import { releases } from "../changelog";
import { pageSocial } from "../seo";
import "../foundry/foundry.css";
import "./changelog.css";

export const metadata: Metadata = {
  title: "Foundry · Changelog",
  description: "What changed in each Foundry release, newest first, with a download link for each published version.",
  alternates: { canonical: "/changelog", types: { "application/atom+xml": "/changelog/feed.xml" } },
  ...pageSocial("Foundry · Changelog", "What changed in each Foundry release, newest first, with a download link for each published version.", "/changelog"),
};

const dateFormat = new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" });

function Inline({ text }: { text: string }) {
  return text.split(/(\*\*[^*]+\*\*|`[^`]+`)/).map((part, index) => {
    if (part.startsWith("**")) return <strong key={index}>{part.slice(2, -2)}</strong>;
    if (part.startsWith("`")) return <code key={index}>{part.slice(1, -1)}</code>;
    return <Fragment key={index}>{part}</Fragment>;
  });
}

export default function ChangelogPage() {
  const all = releases();
  return <main className="foundry-preview changelog">
    <SiteHeader />
    <h1 id="content">Changelog</h1>
    <p className="changelog-lede">What changed in each release, newest first. <a href="/changelog/feed.xml">Atom feed</a></p>
    {all.map(({ version, date, download, shippedIn, intro, sections }, index) => <section key={version} aria-labelledby={`v${version}`}>
      <h2 id={`v${version}`}>Foundry {version}{index === 0 && <span className="changelog-latest">Latest</span>}</h2>
      <p className="changelog-meta"><time dateTime={date}>{dateFormat.format(new Date(date))}</time> · {download ? <a href={download}>Download Foundry.dmg</a> : <>No separate download. These changes shipped in <a href={`#v${shippedIn}`}>Foundry {shippedIn}</a>.</>}</p>
      {intro?.map((text) => <p key={text}><Inline text={text} /></p>)}
      {sections.map(({ title, items, paragraphs, table }) => <Fragment key={title}>
        <h3>{title}</h3>
        {paragraphs?.map((text) => <p key={text}><Inline text={text} /></p>)}
        {table && <div className="changelog-table"><table><thead><tr>{table[0].map((cell, column) => cell ? <th key={column} scope="col">{cell}</th> : <td key={column} />)}</tr></thead><tbody>{table.slice(1).map((row) => <tr key={row[0]}>{row.map((cell, column) => column ? <td key={column}>{cell}</td> : <th key={column} scope="row">{cell}</th>)}</tr>)}</tbody></table></div>}
        {items.length > 0 && <ul>{items.map((text) => <li key={text}><Inline text={text} /></li>)}</ul>}
      </Fragment>)}
    </section>)}
    <SiteFooter />
  </main>;
}
