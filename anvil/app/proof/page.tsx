import Link from "next/link";
import type { Metadata } from "next";
import { SiteFooter, SiteHeader } from "../foundry/site-chrome";
import { formatFigure, proofFigures } from "../proof";
import { repoUrl } from "../site";
import "../foundry/foundry.css";
import "./proof.css";

export const metadata: Metadata = {
  title: "Foundry · Proof",
  description: "Every number Foundry quotes, with the machine, version, date and benchmark file it comes from. Where Foundry loses is listed too.",
  alternates: { canonical: "/proof" },
};

const measured = new Set(["open-latency", "memory-vs-raycast", "memory-vs-tinycast"]);

export default function ProofPage() {
  return <main className="foundry-preview proof">
    <SiteHeader />
    <h1 id="content">Every number, with its&nbsp;source.</h1>
    <p className="proof-intro">Each figure comes from a file in the Foundry repository. Each row names the machine, the version and the date, and links the file. Where Foundry loses, the row says so. The <Link href="/methodology">methodology page</Link> explains how we measured.</p>
    <ol className="proof-list">
      {proofFigures().map((figure) => {
        const [number, ...unit] = formatFigure(figure).split(" ");
        return <li key={figure.id} className="proof-row">
          <p className="proof-number"><span>{number}</span>{unit.length > 0 && <span className="proof-unit"> {unit.join(" ")}</span>}</p>
          <h2>{figure.label}</h2>
          <p>{figure.sentence}</p>
          <dl>
            <div><dt>Machine</dt><dd>{figure.machine}</dd></div>
            <div><dt>Version</dt><dd>{figure.version}</dd></div>
            <div><dt>Date</dt><dd>{figure.date}</dd></div>
          </dl>
          <p className="proof-links"><a href={`${repoUrl}/blob/main/${figure.source}`}>{figure.source}</a>{measured.has(figure.id) && <Link href="/methodology">How we measured</Link>}</p>
        </li>;
      })}
    </ol>
    <SiteFooter />
  </main>;
}
