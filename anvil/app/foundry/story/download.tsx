"use client";

import { useState } from "react";
import Link from "next/link";
import { motion, useMotionValueEvent, useTransform, type MotionValue } from "motion/react";
import { arrowCells, downloadSettled, downloadStart, storyEnd } from "./download-motion";
import { SiteFooter } from "../site-chrome";
import { phase } from "./shelf-motion";
import { foundryDownloadUrl, foundryVersion } from "../../site";

export default function DownloadStory({ progress, animated, appSize }: { progress: MotionValue<number>; animated: boolean; appSize: string }) {
  const [active, setActive] = useState(progress.get() >= downloadSettled);
  useMotionValueEvent(progress, "change", (value) => setActive(value >= downloadSettled));
  const opacity = useTransform(progress, (value) => phase(value, downloadStart + .04, downloadStart + .12));
  return <motion.section id="download" className="download-section" aria-labelledby="download-heading" data-stop={storyEnd} data-active={!animated || active} style={{ opacity }}>
    <h2 id="download-heading"><span>⌘ Space,</span><span>then anything<span className="download-period">.</span></span></h2>
    <div className="download-still-arrow" aria-hidden="true">{arrowCells.map(([x, y]) => <span key={`${x}:${y}`} style={{ gridColumn: x + 3, gridRow: y + 4 }} />)}</div>
    <div className="download-action">
      <a href={foundryDownloadUrl} className="foundry-cta">Download for macOS</a>
      <p>v{foundryVersion} · macOS 14+ on Apple silicon · {appSize.replaceAll(" ", "\u00a0")} · No telemetry · <Link href="/proof">Proof</Link></p>
    </div>
    <SiteFooter />
  </motion.section>;
}
