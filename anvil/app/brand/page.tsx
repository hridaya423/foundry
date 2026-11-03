import { statSync } from "node:fs";
import { join } from "node:path";
import type { Metadata } from "next";
import { Mark } from "../foundry/mark";
import { SiteFooter, SiteHeader } from "../foundry/site-chrome";
import { color } from "../foundry/tokens";
import "../foundry/foundry.css";
import "./brand.css";

export const metadata: Metadata = {
  title: "Foundry · Brand",
  description: "The Foundry mark, colours and type, with rules for using them and a kit of the master files.",
  alternates: { canonical: "/brand" },
};

type Token = keyof typeof color;

const palette: { name: string; tokens: [Token, string][] }[] = [
  { name: "Ink", tokens: [["ink", "Ground. Every surface starts here."], ["ink-raised", "Panels and cards on ink."], ["ink-raised-2", "Fields and nested surfaces."], ["ink-raised-3", "The third and last level."], ["line", "Hairlines and borders."]] },
  { name: "Type", tokens: [["text", "Body and display type on ink."], ["muted", "Secondary type."]] },
  { name: "Orange", tokens: [["orange", "The one accent."], ["orange-light", "Lit orange tile, highlight."], ["orange-mid", "Lit orange tile, face."], ["orange-deep", "Lit orange tile, shadow."], ["orange-side", "The side of an orange tile."]] },
  { name: "Chalk", tokens: [["chalk", "Tile face in the 3D scene."], ["chalk-light", "Flat tile, highlight."], ["chalk-mid", "Flat tile, face."], ["chalk-deep", "Flat tile, shadow."], ["chalk-ink", "Type set on chalk."], ["chalk-ink-muted", "Secondary type on chalk."]] },
];

const faces = [
  { name: "Geist 400", role: "Display and body", className: "brand-type-400", sample: "The app you never open." },
  { name: "Geist 500", role: "Interface and labels", className: "brand-type-500", sample: "Search apps, files and commands" },
  { name: "Geist 600", role: "The wordmark only", className: "brand-type-600", sample: "foundry" },
  { name: "Geist Mono", role: "Code and file names", className: "brand-type-mono", sample: "docs/brand/tokens.json" },
];

const minor = Array.from({ length: 29 }, (_, i) => -10 + i * 5).filter((v) => v % 10).map((v) => `M${v} -10V130M-10 ${v}H130`).join("");
const major = Array.from({ length: 15 }, (_, i) => -10 + i * 10).map((v) => `M${v} -10V130M-10 ${v}H130`).join("");

function Mark16() {
  return (
    <svg className="brand-mark-16" viewBox="0 0 16 16" shapeRendering="crispEdges" aria-hidden="true">
      <path fill="currentColor" d="M1 1H7V4H5V15H1Z" />
      <path fill="currentColor" d="M9 1H15V9H11V4H9Z" />
      <path fill="currentColor" d="M11 10H15V15H11Z" />
      <rect fill="var(--f-orange)" x="6" y="6" width="4" height="8" />
    </svg>
  );
}

function Construction() {
  return (
    <div className="brand-construction">
      <svg viewBox="-30 -30 180 180" aria-hidden="true">
        <path className="brand-grid-minor" d={minor} />
        <path className="brand-grid-major" d={major} />
        <path className="brand-grid-frame" d="M0 0H120V120H0Z" />
      </svg>
      <Mark />
      <svg viewBox="-30 -30 180 180" aria-hidden="true">
        <path className="brand-grid-note" d="M40 113V129M50 113V129M40 126H50M20 20L2.93 2.93M10 20A10 10 0 0 1 20 10" />
        <circle className="brand-grid-dot" cx="20" cy="20" r="1" />
        <text x="45" y="138" textAnchor="middle">10</text>
        <text x="-1" y="1" textAnchor="end">r 10</text>
      </svg>
    </div>
  );
}

const kitSize = Math.round(statSync(join(process.cwd(), "public/brand/foundry-brand.zip")).size / 1024);

export default function BrandPage() {
  return <main className="foundry-preview brand">
    <SiteHeader />
    <section className="brand-intro">
      <h1 id="content">The mark, the colours and the&nbsp;type.</h1>
      <p>Everything on this page comes from <code>docs/brand</code>. The kit holds the master files.</p>
      <div className="brand-download">
        <a className="foundry-cta" href="/brand/foundry-brand.zip" download>Download the brand kit</a>
        <span>ZIP, {kitSize} KB. Four marks, the grid, the lockup, the app icon, tokens and notes.</span>
      </div>
    </section>

    <section className="brand-section" aria-labelledby="brand-mark">
      <header>
        <h2 id="brand-mark">Mark</h2>
        <p>Split Mould. Three chalk pieces hold one orange cast. Every straight edge sits on a 5 unit grid.</p>
      </header>
      <div className="brand-mark-figures">
        <figure>
          <div className="brand-panel brand-master"><Mark /></div>
          <figcaption>Master, chalk on ink.</figcaption>
        </figure>
        <figure>
          <div className="brand-panel"><Construction /></div>
          <figcaption>Construction on a 120 unit square.</figcaption>
        </figure>
        <figure className="brand-wide">
          <div className="brand-panel brand-lockup"><span><Mark />foundry</span></div>
          <figcaption>Lockup. The word sits one cast width from the mark.</figcaption>
        </figure>
        <dl className="brand-specs">
          <div><dt>Grid</dt><dd>5 units</dd></div>
          <div><dt>Channel</dt><dd>10 units</dd></div>
          <div><dt>Corner radius</dt><dd>10 units</dd></div>
          <div><dt>Cast</dt><dd>20 by 60 units</dd></div>
        </dl>
      </div>
    </section>

    <section className="brand-section" aria-labelledby="brand-colour">
      <header>
        <h2 id="brand-colour">Colour</h2>
        <p>Orange closes a sentence, marks the selected thing, or is the cast in the mark. It never decorates.</p>
      </header>
      <div className="brand-palette">
        {palette.map(({ name, tokens }) => <div key={name} className="brand-group">
          <h3>{name}</h3>
          <ul>
            {tokens.map(([token, role]) => <li key={token}>
              <i style={{ background: color[token] }} />
              <code>{token}</code>
              <code className="brand-hex">{color[token]}</code>
              <span>{role}</span>
            </li>)}
          </ul>
        </div>)}
      </div>
    </section>

    <section className="brand-section" aria-labelledby="brand-type">
      <header>
        <h2 id="brand-type">Type</h2>
        <p>Geist for everything the site says. Geist Mono for code and file names.</p>
      </header>
      <ul className="brand-type">
        {faces.map(({ name, role, className, sample }) => <li key={name}>
          <div><strong>{name}</strong><span>{role}</span></div>
          <p className={className}>{sample}</p>
        </li>)}
      </ul>
    </section>

    <section className="brand-section" aria-labelledby="brand-use">
      <header>
        <h2 id="brand-use">Use</h2>
        <p>Chalk on ink by default. The cast is the only orange in the mark.</p>
      </header>
      <div className="brand-rules">
        <h3>Do</h3>
        <ul>
          <li>
            <div className="brand-panel brand-sizes">
              <span><Mark16 /><small>16 px</small></span>
              <span><Mark /><small>24 px</small></span>
              <span><Mark /><small>32 px</small></span>
            </div>
            <p>Use the 16 px master at 16 px. Nothing smaller.</p>
          </li>
          <li>
            <div className="brand-panel"><span className="brand-clear"><Mark /></span></div>
            <p>Keep one cast width clear on every side.</p>
          </li>
          <li>
            <div className="brand-panel brand-on-chalk"><Mark /></div>
            <p>Use the mono mark where colour is not available.</p>
          </li>
        </ul>
        <h3>Don&rsquo;t</h3>
        <ul>
          <li>
            <div className="brand-panel brand-recolour"><Mark /></div>
            <p>Recolour the cast.</p>
          </li>
          <li>
            <div className="brand-panel brand-on-photo"><Mark /></div>
            <p>Place it on a photo.</p>
          </li>
          <li>
            <div className="brand-panel brand-rotated"><Mark /></div>
            <p>Rotate it, stretch it or outline it.</p>
          </li>
        </ul>
      </div>
    </section>
    <SiteFooter />
  </main>;
}
