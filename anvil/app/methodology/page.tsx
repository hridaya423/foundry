import type { CSSProperties } from "react";
import Link from "next/link";
import type { Metadata } from "next";
import { SiteFooter, SiteHeader } from "../foundry/site-chrome";
import { figureCells, methodologyFigure } from "../foundry/methodology-figure";
import { pageSocial } from "../seo";
import "../foundry/foundry.css";
import "./methodology.css";

const reports = "https://github.com/hridaya423/foundry/blob/main/docs/benchmarks/";
const report = `${reports}2026-09-29-foundry-1.1-raycast-2.5.3-mbp-report.md`;
const tinycastReport = `${reports}2026-09-29-foundry-1.1-tinycast-0.11.3-mbp-report.md`;

export const metadata: Metadata = {
  title: "Foundry · How we measured memory",
  description: "How the 81% lower warmed memory figure for Foundry 1.1 against Raycast 2.5.3 was measured, and what it does not cover.",
  alternates: { canonical: "/methodology" },
  ...pageSocial("Foundry · How we measured memory", "How the 81% lower warmed memory figure for Foundry 1.1 against Raycast 2.5.3 was measured, and what it does not cover.", "/methodology"),
};

export default function MethodologyPage() {
  return <main className="foundry-preview methodology">
    <SiteHeader />
    <div className="methodology-figure" role="img" aria-label="81%" style={{ "--columns": methodologyFigure.width, "--rows": methodologyFigure.height } as CSSProperties}>
      {figureCells.map(({ column, row }) => <i key={`${column}:${row}`} style={{ "--column": column, "--row": row } as CSSProperties} />)}
    </div>
    <h1 id="content">How we measured 81% less&nbsp;memory.</h1>
    <p className="methodology-status">Provisional · Measured 29 September 2026 · Foundry 1.1.0, Raycast 2.5.3 and Tinycast 0.11.3</p>
    <p>The home page says that Foundry uses 81% less warmed memory than Raycast. This page explains that number and its limits.</p>
    <h2>What we measured</h2>
    <p>Warmed memory is the memory an app uses after it has opened and hidden its window many times. The runner reads the Summary Footprint that the macOS <code>footprint</code> tool reports. The raw records also keep RSS as a check. We do not use RSS for the claim, because a sum of RSS counts shared memory more than once.</p>
    <p>Each run had 5 warmup opens and 30 measured opens. After a 2 second pause, the runner took 15 memory samples, one each second, with the window hidden. We report the median of the 15 samples.</p>
    <div className="methodology-table" role="region" aria-label="Warmed memory, Foundry and Raycast" tabIndex={0}><table><caption>Warmed memory, median of 15 samples</caption><thead><tr><th>Run order</th><th>Foundry 1.1.0</th><th>Raycast 2.5.3</th><th>Reduction</th></tr></thead><tbody><tr><th>Foundry first</th><td>59.3 MB</td><td>591.3 MB</td><td>90.0%</td></tr><tr><th>Raycast first</th><td>115.2 MB</td><td>620.2 MB</td><td>81.4%</td></tr></tbody></table></div>
    <p>We ran the test two times, in opposite orders. The home page uses the worse result, 81.4%, rounded down to 81%.</p>
    <h2>What counts as each app</h2>
    <p>For Foundry, the runner counts the app and all of its child processes. For Raycast, it counts the app, its child processes, and three WebKit services that start after Raycast opens. macOS does not link those services to Raycast, so the runner finds them as new processes that were not there before Raycast started.</p>
    <h2>The machine</h2>
    <p>MacBook Pro with Apple M4 Pro, macOS 27.0, on AC power. The runner closed each launcher before it measured the other one.</p>
    <h2>Where Foundry loses to Tinycast</h2>
    <p>We ran the same runner against Tinycast 0.11.3 on the same machine, in both orders. Foundry shows its panel about 3.4 to 3.8 times faster. Tinycast uses less memory. Foundry used 1.5 to 3.0 times as much.</p>
    <div className="methodology-table" role="region" aria-label="Time from hotkey to panel on screen, median of 30 opens" tabIndex={0}><table><caption>Time from hotkey to panel on screen, median of 30 opens</caption><thead><tr><th>Run order</th><th>Foundry 1.1.0</th><th>Tinycast 0.11.3</th></tr></thead><tbody><tr><th>Foundry first</th><td>17.5 ms</td><td>66.7 ms</td></tr><tr><th>Tinycast first</th><td>19.1 ms</td><td>64.7 ms</td></tr></tbody></table></div>
    <div className="methodology-table" role="region" aria-label="Warmed memory, Foundry and Tinycast" tabIndex={0}><table><caption>Warmed memory, median of 15 samples</caption><thead><tr><th>Run order</th><th>Foundry 1.1.0</th><th>Tinycast 0.11.3</th></tr></thead><tbody><tr><th>Foundry first</th><td>120.0 MB</td><td>40.4 MB</td></tr><tr><th>Tinycast first</th><td>60.5 MB</td><td>40.6 MB</td></tr></tbody></table></div>
    <p>Tinycast is also smaller on disk: 13.6 MB against 16.5 MB for Foundry 1.1.0. This run was on battery power. The Foundry build was a staged build that keeps its panel mapped. The earlier 1.1.0 build in the Raycast run took about 100 ms to show the panel, and Raycast took about 18 ms. We have not re-run either test on 1.2.0. The <a href={tinycastReport}>Tinycast report</a> has the commands and raw records.</p>
    <h2>Limits</h2>
    <p>Each result is one machine and two runs. We did not record the Raycast settings and extensions. The Raycast install was in daily use. The Raycast memory test makes no claim about how fast either app opens.</p>
    <h2>Reproduce it</h2>
    <p>The runner is <code>scripts/benchmark-launchers.swift</code> in the <a href="https://github.com/hridaya423/foundry">Foundry source</a>. Use 30 runs, 5 warmups, 15 memory samples, and the isolate option. The <a href={report}>full report</a> lists the commands and links the raw records. The <Link href="/proof">proof page</Link> lists every figure we quote with its source file.</p>
    <SiteFooter />
  </main>;
}
