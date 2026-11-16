import Link from "next/link";
import type { Metadata } from "next";
import { Fragment } from "react";
import { SiteFooter, SiteHeader } from "../foundry/site-chrome";
import { appSizeLabel } from "../proof";
import { pageSocial } from "../seo";
import { repoUrl, siteUrl } from "../site";
import "../foundry/foundry.css";
import "../privacy/privacy.css";

const description = "Short answers about Foundry, a free Mac launcher: how it compares with Raycast, Spotlight and Alfred, Script Commands, snippets, privacy, updates and size.";

export const metadata: Metadata = {
  title: "Foundry · FAQ",
  description,
  alternates: { canonical: "/faq" },
  ...pageSocial("Foundry · FAQ", description, "/faq"),
};

const size = appSizeLabel();

const groups = [
  {
    title: "The basics",
    questions: [
      {
        question: "What is Foundry?",
        answer: "Foundry is a free, open-source alternative to Raycast and Spotlight for Apple silicon Macs on macOS 14 or later. Press ⌘ Space and type, and it finds the app, the file or the thing you copied an hour ago. It also does the job in the same bar: it converts a HEIC to PNG, tiles a window, expands a snippet or answers a question.",
      },
      {
        question: "Is Foundry free and open source?",
        answer: `Yes. Foundry is free, and its [source](${repoUrl}) is on GitHub under the MIT licence. The DMG is signed with a Developer ID and notarized by Apple. There is no Foundry account.`,
      },
      {
        question: "Does Foundry run on Intel Macs?",
        answer: "No. Foundry needs an Apple silicon Mac with macOS 14 or later. Release builds are arm64 only, so there is no Intel download.",
      },
      {
        question: "How big is Foundry?",
        answer: `Foundry is ${size}, measured on disk after unpacking the release zip. In the September runs, Tinycast 0.11.3 was 13.6 MB and Raycast 2.5.3 was 224 MB. \`Package.swift\` declares no third-party Swift packages.`,
      },
    ],
  },
  {
    title: "Foundry and other launchers",
    questions: [
      {
        question: "How does Foundry compare with Raycast?",
        answer: `Foundry 1.1.0 used 115.2 MB of warmed memory against 620.2 MB for Raycast 2.5.3, 81% less, in the worse of two runs on an Apple M4 Pro MacBook Pro. On disk, Foundry is ${size} and Raycast 2.5.3 was 224 MB. Raycast opened faster: about 18 ms to show its panel, against about 100 ms for the earlier Foundry 1.1.0 release build. The [methodology page](/methodology) explains each test.`,
      },
      {
        question: "How does Foundry compare with Spotlight?",
        answer: "Foundry can take ⌘ Space from Spotlight: if you choose Take ⌘ Space in setup, Foundry moves Spotlight off the shortcut. Its file search uses Spotlight, so type `f` and a file name, and add `kind:pdf` or `kind:image` to narrow it. The same bar also holds clipboard history, snippets, window layouts, file conversion and AI.",
      },
      {
        question: "How does Foundry compare with Alfred?",
        answer: "The Foundry repository has no benchmark against Alfred, so this site makes no speed or memory claim about it. Setup offers to import your Alfred snippets, with their names and keywords. If Alfred holds ⌘ Space and you give that shortcut to Foundry, setup moves Alfred to ⌥ Space.",
      },
      {
        question: "Does Foundry run Raycast extensions?",
        answer: "No. Foundry runs Script Commands in the Raycast format: executable files with an `@raycast.title` line. It does not run extensions from the Raycast Store. Put scripts in `~/.config/foundry/scripts` or a folder you add in Settings, under Scripts, and Foundry asks you to trust the folder before its first run.",
      },
      {
        question: "How do I import snippets from Raycast or Alfred?",
        answer: "Setup finds Alfred snippets on your Mac and offers to import them. For Raycast, choose a snippets JSON export in setup, or run Import Snippets in Foundry at any time. Export Snippets saves your Foundry snippets as Raycast-compatible JSON.",
      },
    ],
  },
  {
    title: "Privacy and updates",
    questions: [
      {
        question: "What data leaves my Mac?",
        answer: "Foundry contacts no server run by Foundry, and it has no account, no analytics and no crash reporting. Some features call other services, such as currency rates, weather, AI providers and the update check. The [privacy page](/privacy) lists each one, what it sends and how to avoid it. Clipboard history, settings and snippets stay on your Mac.",
      },
      {
        question: "How does Foundry update?",
        answer: "From 1.4.0, Foundry asks GitHub for the newest release the first time you open the launcher after Foundry starts, then at most once a day. When a newer version exists, Home shows a notice, and Download opens the release page in your browser. Nothing downloads by itself, and you can turn the check off in Settings, under About. Earlier versions do not check, so get the newest DMG from this site.",
      },
    ],
  },
];

const markup = /(`[^`]+`|\[[^\]]+\]\([^)]+\))/;

function Answer({ text }: { text: string }) {
  return text.split(markup).map((part, index) => {
    if (part.startsWith("`")) return <code key={index}>{part.slice(1, -1)}</code>;
    const link = part.match(/^\[([^\]]+)\]\(([^)]+)\)$/);
    if (link) return link[2].startsWith("/") ? <Link key={index} href={link[2]}>{link[1]}</Link> : <a key={index} href={link[2]}>{link[1]}</a>;
    return <Fragment key={index}>{part}</Fragment>;
  });
}

const structuredData = {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "@id": `${new URL("/faq", siteUrl).href}#faq`,
  mainEntity: groups.flatMap(({ questions }) => questions).map(({ question, answer }) => ({
    "@type": "Question",
    name: question,
    acceptedAnswer: { "@type": "Answer", text: answer.replace(/\[([^\]]+)\]\([^)]+\)/g, "$1").replaceAll("`", "") },
  })),
};

export default function FaqPage() {
  return <>
    <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, "\\u003c") }} />
    <main className="foundry-preview privacy">
      <SiteHeader />
      <h1 id="content">Questions and answers</h1>
      <p>Short answers about Foundry. Each number names the version and the machine it comes from, and the <Link href="/proof">proof page</Link> links the raw files.</p>
      {groups.map(({ title, questions }) => <Fragment key={title}>
        <h2>{title}</h2>
        {questions.map(({ question, answer }) => <section key={question} className="privacy-item">
          <h3>{question}</h3>
          <p><Answer text={answer} /></p>
        </section>)}
      </Fragment>)}
      <SiteFooter />
    </main>
  </>;
}
