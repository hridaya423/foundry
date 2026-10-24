"use client";

import { useState } from "react";
import { motion, useMotionValueEvent, useTransform, type MotionValue } from "motion/react";
import { arrowCells, downloadSettled, downloadStart, storyEnd } from "./download-motion";
import DownloadLink from "../download-gate";
import { SiteFooter } from "../site-chrome";
import { phase } from "./shelf-motion";

export default function DownloadStory({ progress, animated }: { progress: MotionValue<number>; animated: boolean }) {
  const [active, setActive] = useState(progress.get() >= downloadSettled);
  useMotionValueEvent(progress, "change", (value) => setActive(value >= downloadSettled));
  const opacity = useTransform(progress, (value) => phase(value, downloadStart + .12, downloadSettled));
  return <motion.section className="download-section" aria-labelledby="download-heading" data-stop={storyEnd} data-active={!animated || active} style={{ opacity }}>
    <h2 id="download-heading"><span>Your next</span><span>command <span className="download-heading-end">starts here<span className="download-period">.</span></span></span></h2>
    <div className="download-still-arrow" aria-hidden="true">{arrowCells.map(([x, y]) => <span key={`${x}:${y}`} style={{ gridColumn: x + 3, gridRow: y + 4 }} />)}</div>
    <div className="download-action">
      <DownloadLink className="foundry-cta">Download Foundry</DownloadLink>
      <p>v1.1 · macOS 14+ · Open source</p>
    </div>
    <SiteFooter />
  </motion.section>;
}
