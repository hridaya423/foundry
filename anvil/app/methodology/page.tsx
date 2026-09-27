import type { Metadata } from "next";
import Link from "next/link";
import "../foundry/foundry.css";
import "./methodology.css";

export const metadata: Metadata = { title: "Foundry · Memory methodology", robots: { index: false, follow: false } };

export default function MethodologyPage() {
  return <main className="foundry-preview memory-methodology">
    <Link href="/#memory-heading">← Back to home</Link>
    <h1>Memory footprint methodology</h1>
    <p className="methodology-status">Provisional comparison · updated 29 September 2026</p>
    <p>Current comparison (29 September 2026): two order-swapped warmed runs on one MacBook Pro, Apple M4 Pro, macOS 27.0, on AC power. Foundry 1.1.0 vs Raycast 2.5.3.0. The launch film uses these numbers: 13.8× smaller installed size and ≈81% less warmed memory (the smaller of the two order-swapped reductions, rounded down). Earlier comparison (29 August 2026): Mac16,7, 48 GB RAM, macOS 26.5.1, Foundry 1.0 vs Raycast 2.1.2.0.</p>
    <h2>What the numbers mean</h2>
    <p>The story shows the worse of the two order-swapped legs — 115.2 MB for Foundry and 620.2 MB for Raycast — matching the conservative ≈81% headline. These are summaries of two runs, not additional measurements or a live meter.</p>
    <div className="methodology-table"><table><caption>Warmed footprint, median (p50), 29 September 2026 · Foundry 1.1.0 vs Raycast 2.5.3.0</caption><thead><tr><th>Run order</th><th>Foundry</th><th>Raycast</th><th>Reduction</th></tr></thead><tbody><tr><th>Foundry first</th><td>59.3 MB</td><td>591.3 MB</td><td>90.0%</td></tr><tr><th>Raycast first</th><td>115.2 MB</td><td>620.2 MB</td><td>81.4%</td></tr></tbody></table></div>
    <div className="methodology-table"><table><caption>Warmed footprint, median (p50), 29 August 2026 · Foundry 1.0 vs Raycast 2.1.2.0</caption><thead><tr><th>Run order</th><th>Foundry</th><th>Raycast</th></tr></thead><tbody><tr><th>Foundry first</th><td>162.3 MB</td><td>531.6 MB</td></tr><tr><th>Raycast first</th><td>164.5 MB</td><td>520.7 MB</td></tr></tbody></table></div>
    <div className="methodology-table"><table><caption>Installed size, <code>du -sk</code> (29 September 2026)</caption><thead><tr><th>Machine</th><th>Foundry 1.1</th><th>Raycast 2.2.0.0</th><th>Ratio</th></tr></thead><tbody><tr><th>MacBook Pro M4 Pro</th><td>16.2 MB</td><td>195 MB</td><td>12.1×</td></tr><tr><th>Mac mini M4</th><td>16.2 MB</td><td>196 MB</td><td>12.1×</td></tr></tbody></table></div>
    <p>Post-launch spot check (cold, no panel cycles): Foundry 60.7 MB vs Raycast 591.0 MB on the M4 Pro, and 25.9 MB vs 278.3 MB on the M4 mini — a larger gap than the warmed claim, not used as the headline number.</p>
    <h2>Tinycast comparison · 29 September 2026</h2>
    <p>Same MacBook Pro, same runner, Foundry 1.1.0 vs Tinycast 0.11.3 — measured on battery, not AC. Tinycast is the lighter, smaller app; Foundry is faster to summon. Both directions below are reported as measured, not selected.</p>
    <div className="methodology-table"><table><caption>Panel show, hotkey → on-screen window, p50 of 30 · Foundry 1.1.0 vs Tinycast 0.11.3</caption><thead><tr><th>Run order</th><th>Foundry</th><th>Tinycast</th><th>Foundry advantage</th></tr></thead><tbody><tr><th>Foundry first</th><td>17.5 ms</td><td>66.7 ms</td><td>3.8×</td></tr><tr><th>Tinycast first</th><td>19.1 ms</td><td>64.7 ms</td><td>3.4×</td></tr></tbody></table></div>
    <div className="methodology-table"><table><caption>Warmed footprint + installed size · Foundry 1.1.0 vs Tinycast 0.11.3</caption><thead><tr><th>Run order</th><th>Foundry footprint</th><th>Tinycast footprint</th></tr></thead><tbody><tr><th>Foundry first</th><td>120.0 MB</td><td>40.4 MB</td></tr><tr><th>Tinycast first</th><td>60.5 MB</td><td>40.6 MB</td></tr><tr><th>Installed size</th><td>16.5 MB</td><td>13.6 MB</td></tr></tbody></table></div>
    <p>The 17–19 ms Foundry number follows a show-path change in this build: the panel stays mapped (alpha 0) instead of ordering out on hide, removing ~80–90 ms of window-server surface creation per open. The same metric pipeline measured the prior build at ~110 ms — see the Tinycast report for the decomposition.</p>
    <h2>Protocol</h2>
    <p>Each run used five warmup panel cycles and 30 measured panel cycles, followed by a two-second settle and 15 memory samples at one-second intervals with the panel hidden. The runner required AC power and stopped each launcher before measuring the other.</p>
    <p>The primary metric was macOS <code>footprint</code> grouped Summary Footprint for the selected processes. RSS is retained in the raw records as a secondary diagnostic; summing RSS can count shared pages more than once.</p>
    <p>The process set included bundle processes and their descendants. For Raycast it also included three detached WebKit XPC services that appeared after launch. Those services were associated by new PID relative to a pre-launch baseline, not an OS-reported ownership link. Selected processes had to be at least five seconds old, with the process set stable for 100 milliseconds.</p>
    <h2>Limits and publication status</h2>
    <p>This comparison does not establish a universal memory advantage or faster opening. Window-registration timing in the raw records is diagnostic only; it does not measure the first composited frame.</p>
    <p>Installed size for Raycast 2.5.3.0 is 224 MB (224,088 KB) vs 16.2 MB for Foundry 1.1.0. Still required before the provisional label comes off: order-swapped warmed runs on the Mac mini (needs an Accessibility-granted terminal, because remote sessions cannot post the hotkey), recorded Raycast settings and extensions, and legal review for naming Raycast before public comparative use.</p>
    <h2>Source records</h2>
    <ul><li><a href="/assets/foundry/story/memory/report.md">Full original report and reproduction commands</a></li><li><a href="/assets/foundry/story/memory/forward.json">Foundry-first raw JSON</a></li><li><a href="/assets/foundry/story/memory/reverse.json">Raycast-first raw JSON</a></li></ul>
  </main>;
}
