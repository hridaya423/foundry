"use client";

import { useState, type MouseEvent } from "react";
import { motion, useMotionValueEvent, useTransform, type MotionValue } from "motion/react";
import { downloadStart } from "./download-motion";
import { memorySettled, memoryValues } from "./memory-motion";
import { phase } from "./shelf-motion";
import { Tiles } from "../launcher";

export default function MemoryStory({ progress, animated, onReadMethodology }: { progress: MotionValue<number>; animated: boolean; onReadMethodology: (event: MouseEvent<HTMLAnchorElement>) => void }) {
  const isActive = (value: number) => value >= memorySettled - .06 && value < downloadStart;
  const [active, setActive] = useState(isActive(progress.get()));
  useMotionValueEvent(progress, "change", (value) => setActive(isActive(value)));
  const opacity = useTransform(progress, (value) => phase(value, memorySettled - .04, memorySettled + .02) * (1 - phase(value, downloadStart - .03, downloadStart + .01)));
  return (
    <motion.section id="memory" className="memory-section" aria-labelledby="memory-heading" data-stop={memorySettled + .1} data-active={!animated || active} style={{ opacity }}>
      <h2 id="memory-heading">{animated ? <span className="memory-percent">81<span>%</span></span> : <Tiles text="81%" />}<span className="memory-takeaway">lower warmed memory use.</span></h2>
      <p className="memory-comparison">Foundry {memoryValues[0]} MB <span>vs</span> Raycast 2.5.3 {memoryValues[1]} MB</p>
      <div className="memory-context">
        <p>Measured 29 Sep 2026 on one M4 Pro.<br />The worse of two order-swapped runs.</p>
        <a href="/methodology" onClick={onReadMethodology}>Read methodology</a>
      </div>
    </motion.section>
  );
}
