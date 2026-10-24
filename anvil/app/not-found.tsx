import type { Metadata } from "next";
import Link from "next/link";
import { SiteFooter, SiteHeader } from "./foundry/site-chrome";
import { tileText } from "./foundry/story/tile-glyphs";
import "./foundry/foundry.css";
import "./not-found.css";

export const metadata: Metadata = { title: "Foundry · Page not found" };

const figure = tileText("404");
const left = Math.min(...figure.points.map((point) => point.x));
const top = Math.min(...figure.points.map((point) => point.y));

export default function NotFound() {
  return <main className="foundry-preview not-found">
    <SiteHeader />
    <div className="not-found-tiles" role="img" aria-label="404" style={{ gridTemplateColumns: `repeat(${figure.width}, 1fr)` }}>
      {figure.points.map((point) => <i key={`${point.x}:${point.y}`} style={{ gridColumn: point.x - left + 1, gridRow: point.y - top + 1 }} />)}
    </div>
    <h1 id="content">This page is not here.</h1>
    <p>The link may be old, or the page moved.</p>
    <Link className="foundry-cta" href="/">Back to Foundry</Link>
    <SiteFooter />
  </main>;
}
