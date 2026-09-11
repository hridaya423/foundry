"use client";

import { useRef, useState } from "react";
import Link from "next/link";
import { motion, useMotionValue, useMotionValueEvent, useScroll, useSpring, useTransform, type MotionStyle } from "motion/react";
import FoundryHeroContent from "../hero-content";
import ShelfCanvas from "./story-canvas";
import ClipboardStory from "./clipboard";
import { clipboardFocus } from "./clipboard-motion";
import MediaStory from "./media";
import ToolsStory from "./tools";
import MemoryStory from "./memory";
import DownloadStory from "./download";
import { toolBeat } from "./tools-motion";
import { storyEnd } from "./download-motion";
import { phase, shelfCells, shelfStops } from "./shelf-motion";

export default function ShelfStory({ inspect, initialProgress }: { inspect: boolean; initialProgress: number }) {
  const track = useRef<HTMLDivElement>(null);
  const root = useRef<HTMLElement>(null);
  const { scrollYProgress } = useScroll({ target: track, trackContentSize: true, offset: ["start start", "end end"] });
  const storyProgress = useTransform(scrollYProgress, (value) => value * storyEnd);
  const smooth = useSpring(storyProgress, { stiffness: 100, damping: 20, mass: 1 });
  const manual = useMotionValue(initialProgress);
  const progress = inspect ? manual : smooth;
  const clipboardSelection = useSpring(clipboardFocus(initialProgress), { stiffness: 100, damping: 20, mass: 1 });
  const toolTransition = useMotionValue(toolBeat(initialProgress).transition);
  const toolSelection = useMotionValue(toolBeat(initialProgress).selected);
  const toolPrevious = useMotionValue(Math.max(0, toolBeat(initialProgress).selected - 1));
  const toolReveal = useSpring(toolBeat(initialProgress).reveal, { stiffness: 500, damping: 30 });
  const mediaPortrait = useSpring(0, { stiffness: 500, damping: 30 });
  const [animated, setAnimated] = useState(false);
  const [position, setPosition] = useState(initialProgress);
  const [step, setStep] = useState(initialProgress < 0.615 ? 0 : initialProgress < 0.875 ? 1 : 2);
  const [zone, setZone] = useState(initialProgress < 0.34 ? "hero" : initialProgress > 1.08 ? "clipboard" : initialProgress > 0.51 ? "shelf" : "transition");
  const [stillStep, setStillStep] = useState(1);
  const heroTransform = useTransform(progress, (value) => `translateY(${-112 * phase(value, 0.25, 0.44)}%)`);
  const copyOpacity = useTransform(progress, (value) => 1 - phase(value, 0.25, 0.34));
  const headingOpacity = useTransform(progress, (value) => phase(value, 0.46, 0.54));
  const headingTransform = useTransform(progress, (value) => `translateY(${24 * (1 - phase(value, 0.46, 0.54))}px)`);
  const shelfOpacity = useTransform(progress, (value) => 1 - phase(value, 1, 1.07));
  const shelfTransform = useTransform(progress, (value) => `translateY(${-24 * phase(value, 1, 1.12)}px)`);
  const resultOpacity = useTransform(progress, (value) => phase(value, 0.79, 0.825));
  const fileOpacity = useTransform(progress, (value) => phase(value, 0.565, 0.595));

  useMotionValueEvent(progress, "change", (value) => {
    setStep(value < 0.615 ? 0 : value < 0.875 ? 1 : 2);
    setZone(value < 0.34 ? "hero" : value > 1.08 ? "clipboard" : value > 0.51 ? "shelf" : "transition");
  });

  function goTo(value: number, reveal = false) {
    if (inspect) {
      manual.set(value);
      setPosition(value);
      return;
    }
    const element = track.current;
    if (!element) return;
    if (root.current?.dataset.scene !== "ready") {
      if (reveal) root.current?.querySelector("#file-shelf")?.scrollIntoView({ block: "start", behavior: "instant" });
      return;
    }
    const top = element.getBoundingClientRect().top + window.scrollY;
    window.scrollTo({ top: top + value / storyEnd * (element.offsetHeight - window.innerHeight), behavior: "instant" });
  }

  return (
    <main ref={root} className="foundry-preview story-shell" data-still-step={stillStep}>
      <div ref={track} className="story-track">
        <div className="story-stage">
          <motion.div className="foundry-stage story-hero" style={{ transform: heroTransform, "--story-copy-opacity": copyOpacity } as MotionStyle} inert={animated && zone !== "hero"}>
            <FoundryHeroContent illustration />
          </motion.div>
          <ShelfCanvas progress={progress} clipboardFocus={clipboardSelection} mediaPortrait={mediaPortrait} toolSelection={toolSelection} toolReveal={toolReveal} toolTransition={toolTransition} toolPrevious={toolPrevious} onModeChange={setAnimated} />
          <motion.section style={{ opacity: shelfOpacity, transform: shelfTransform }} className="story-shelf" id="file-shelf" aria-labelledby="shelf-heading" inert={animated && zone !== "shelf"}>
            <motion.header className="shelf-heading" style={{ opacity: headingOpacity, transform: headingTransform }}>
              <h2 id="shelf-heading">Convert files<br />without opening another app<span>.</span></h2>
              <p>Change formats. Remove backgrounds.</p>
            </motion.header>
            <div className="shelf-file-anchor" role="img" aria-label="Original HEIC file">
              <motion.span className="shelf-file-label" style={{ opacity: fileOpacity }}>HEIC</motion.span>
            </div>
            <div className="shelf-image-anchor" role="img" aria-hidden={step === 0} aria-label={step === 2 ? "An orange and leaf made of colored tiles. The white background has been removed." : "An orange and leaf made of colored tiles on a white tiled background, with PNG beneath it."}>
              <motion.div className="shelf-output" style={{ opacity: resultOpacity }}>
                <span>PNG</span>
              </motion.div>
            </div>
            <div className="shelf-still" aria-label="File conversion demonstration">
              <div className="shelf-still-file" aria-hidden="true"><span>HEIC</span></div>
              <div className="shelf-still-image" role="img" aria-label="A mandarin orange and leaf made entirely of colored tiles">
                {shelfCells.filter((cell) => cell.kind === "image").map((cell) => (
                  <span key={`${cell.column}-${cell.row}`} data-subject={cell.subject} style={{ backgroundColor: cell.color, gridColumn: cell.column + 1, gridRow: cell.row + 1 }} />
                ))}
              </div>
              <p>PNG{stillStep === 2 ? " · Background removed" : ""}</p>
            </div>
            <motion.nav className="shelf-actions" aria-label="File Shelf demonstration stages" style={{ opacity: headingOpacity }}>
              {shelfStops.map((stop, index) => (
                <button key={stop.label} aria-pressed={(animated ? step : stillStep) === index} onClick={() => { setStillStep(index); goTo(stop.progress); }}>
                  {stop.label}
                </button>
              ))}
            </motion.nav>
          </motion.section>
          <ClipboardStory progress={progress} focus={clipboardSelection} animated={animated} />
          <MediaStory progress={progress} portrait={mediaPortrait} animated={animated} />
          <ToolsStory progress={progress} animated={animated} selection={toolSelection} reveal={toolReveal} transition={toolTransition} previous={toolPrevious} />
          <MemoryStory progress={progress} animated={animated} />
          <DownloadStory progress={progress} animated={animated} />
        </div>
      </div>
      {inspect && (
        <label className="shelf-inspector">
          Choreography
          <input aria-label="Choreography progress" type="range" min="0" max={storyEnd} step="0.001" value={position} onChange={(event) => { const value = Number(event.target.value); setPosition(value); manual.set(value); }} />
          <output>{position.toFixed(3)}</output>
          <Link href="/">Back to home</Link>
        </label>
      )}
    </main>
  );
}
