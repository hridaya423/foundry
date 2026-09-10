import type { Metadata } from "next";
import Link from "next/link";
import "../foundry/foundry.css";
import "./methodology.css";

export const metadata: Metadata = { title: "Foundry · Memory methodology", robots: { index: false, follow: false } };

export default function MethodologyPage() {
  return <main className="foundry-preview memory-methodology">
    <Link href="/#memory-heading">← Back to home</Link>
    <h1>Memory footprint methodology</h1>
    <p className="methodology-status">Provisional comparison · 29 August 2026</p>
    <p>Two order-swapped runs on one MacBook Pro (Mac16,7): Apple M4 Pro, 14 cores, 48 GB RAM, macOS 26.5.1 (25F80), on AC power. Foundry 1.0 and Raycast 2.1.2.0 ran separately.</p>
    <h2>What the numbers mean</h2>
    <p>The story shows the midpoint of two warmed median memory footprints: 163.4 MB for Foundry and 526.1 MB for Raycast. These are summaries of two runs, not additional measurements or a live meter.</p>
    <div className="methodology-table"><table><caption>Warmed footprint, median (p50)</caption><thead><tr><th>Run order</th><th>Foundry</th><th>Raycast</th></tr></thead><tbody><tr><th>Foundry first</th><td>162.3 MB</td><td>531.6 MB</td></tr><tr><th>Raycast first</th><td>164.5 MB</td><td>520.7 MB</td></tr></tbody></table></div>
    <h2>Protocol</h2>
    <p>Each run used five warmup panel cycles and 30 measured panel cycles, followed by a two-second settle and 15 memory samples at one-second intervals with the panel hidden. The runner required AC power and stopped each launcher before measuring the other.</p>
    <p>The primary metric was macOS <code>footprint</code> grouped Summary Footprint for the selected processes. RSS is retained in the raw records as a secondary diagnostic; summing RSS can count shared pages more than once.</p>
    <p>The process set included bundle processes and their descendants. For Raycast it also included three detached WebKit XPC services that appeared after launch. Those services were associated by new PID relative to a pre-launch baseline, not an OS-reported ownership link. Selected processes had to be at least five seconds old, with the process set stable for 100 milliseconds.</p>
    <h2>Limits and publication status</h2>
    <p>This comparison does not establish a universal memory advantage or faster opening. Window-registration timing in the raw records is diagnostic only; it does not measure the first composited frame.</p>
    <p>The source report requires a second representative Mac, recorded Raycast settings, extensions and indexing state, a matched workflow and dataset, validated or disclosed detached WebKit attribution, published raw results and methodology, and legal review for naming Raycast before public comparative use.</p>
    <h2>Source records</h2>
    <ul><li><a href="/assets/foundry/story/memory/report.md">Full original report and reproduction commands</a></li><li><a href="/assets/foundry/story/memory/forward.json">Foundry-first raw JSON</a></li><li><a href="/assets/foundry/story/memory/reverse.json">Raycast-first raw JSON</a></li></ul>
  </main>;
}
