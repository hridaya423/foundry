"use client";

import { useState } from "react";
import Link from "next/link";
import { motion, useMotionValueEvent, useTransform, type MotionValue } from "motion/react";
import { arrowCells, downloadStart } from "./download-motion";
import { phase } from "./shelf-motion";

export default function DownloadStory({ progress, animated }: { progress: MotionValue<number>; animated: boolean }) {
  const [active, setActive] = useState(progress.get() >= downloadStart + .17);
  useMotionValueEvent(progress, "change", (value) => setActive(value >= downloadStart + .17));
  const opacity = useTransform(progress, (value) => phase(value, downloadStart + .12, downloadStart + .17));
  return <motion.section className="download-section" aria-labelledby="download-heading" inert={animated && !active} style={{ opacity }}>
    <h2 id="download-heading"><span>Your next</span><span>command <span className="download-heading-end">starts here<span className="download-period">.</span></span></span></h2>
    <div className="download-still-arrow" aria-hidden="true">{arrowCells.map(([x, y]) => <span key={`${x}:${y}`} style={{ gridColumn: x + 3, gridRow: y + 4 }} />)}</div>
    <div className="download-action">
      <a className="foundry-cta" href="https://github.com/hridaya423/foundry/releases/download/v1.0.0/Foundry-1.0.0-build-3.zip">Download Foundry</a>
      <p>For Mac. macOS 14 or later.</p>
    </div>
    <footer className="download-footer">
      <Link className="download-wordmark" href="/" aria-label="Foundry, back to top">foundry</Link>
      <nav aria-label="Foundry links"><a href="https://github.com/hridaya423/foundry">GitHub</a><a href="https://github.com/hridaya423/foundry/releases/tag/v1.0.0">Release notes</a></nav>
    </footer>
  </motion.section>;
}
