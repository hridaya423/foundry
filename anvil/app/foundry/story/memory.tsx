"use client";

import { useState } from "react";
import { motion, useMotionValueEvent, useTransform, type MotionValue } from "motion/react";
import { downloadStart } from "./download-motion";
import { memoryStart, memoryValues } from "./memory-motion";
import { phase } from "./shelf-motion";

export default function MemoryStory({ progress, animated }: { progress: MotionValue<number>; animated: boolean }) {
  const [active, setActive] = useState(progress.get() >= memoryStart + 0.12 && progress.get() < downloadStart + .04);
  useMotionValueEvent(progress, "change", (value) => setActive(value >= memoryStart + 0.12 && value < downloadStart + .04));
  const opacity = useTransform(progress, (value) => phase(value, memoryStart + 0.08, memoryStart + 0.18) * (1 - phase(value, downloadStart, downloadStart + .04)));
  return (
    <motion.section className="memory-section" aria-labelledby="memory-heading" inert={animated && !active} style={{ opacity }}>
      <h2 id="memory-heading"><span className="memory-percent">68.9<span>%</span></span><span className="memory-takeaway">lower warmed memory use.</span></h2>
      <div className="memory-comparison">
        <div className="memory-product" data-product="0">
          <p className="memory-display"><span className="memory-value">{memoryValues[0]}</span><span className="memory-unit">MB</span></p>
          <h3>Foundry</h3>
        </div>
        <p className="memory-versus">vs {memoryValues[1]} MB <span>· Raycast 2.1.2.0</span></p>
      </div>
      <div className="memory-context">
        <p>Provisional · Warmed memory · One M4 Pro<br />Two order-swapped runs. Midpoint values.</p>
        <a href="/methodology">Read methodology</a>
      </div>
    </motion.section>
  );
}
