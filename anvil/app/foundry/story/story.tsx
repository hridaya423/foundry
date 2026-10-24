"use client";

import { useEffect, useRef, useState, type CSSProperties, type FocusEvent, type MouseEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { animate, motion, useMotionValue, useMotionValueEvent, useScroll, useSpring, useTransform, type MotionStyle } from "motion/react";
import FoundryHeroContent from "../hero-content";
import DownloadLink from "../download-gate";
import ShelfCanvas from "./story-canvas";
import ClipboardStory from "./clipboard";
import { clipboardFocus } from "./clipboard-motion";
import ToolsStory from "./tools";
import MemoryStory from "./memory";
import DownloadStory from "./download";
import { toolBeat } from "./tools-motion";
import { downloadStart, storyEnd } from "./download-motion";
import { phase, shelfCells, shelfStops } from "./shelf-motion";

const scrollSpring = { stiffness: 400, damping: 50, mass: 1 };
const zoneAt = (value: number) => value < 0.34 ? "hero" : value > downloadStart ? "closing" : value > 1.08 ? "after" : value > 0.51 ? "shelf" : "transition";

export default function ShelfStory({ inspect, initialProgress }: { inspect: boolean; initialProgress: number }) {
  const track = useRef<HTMLDivElement>(null);
  const root = useRef<HTMLElement>(null);
  const { scrollYProgress } = useScroll({ target: track, trackContentSize: true, offset: ["start start", "end end"] });
  const storyProgress = useTransform(scrollYProgress, (value) => value * storyEnd);
  const smooth = useSpring(storyProgress, scrollSpring);
  const manual = useMotionValue(initialProgress);
  const progress = inspect ? manual : smooth;
  const clipboardSelection = useSpring(clipboardFocus(initialProgress), scrollSpring);
  const toolTransition = useMotionValue(toolBeat(initialProgress).transition);
  const toolSelection = useMotionValue(toolBeat(initialProgress).selected);
  const toolPrevious = useMotionValue(Math.max(0, toolBeat(initialProgress).selected - 1));
  const toolReveal = useSpring(toolBeat(initialProgress).reveal, { stiffness: 500, damping: 30 });
  const [animated, setAnimated] = useState(false);
  const [position, setPosition] = useState(initialProgress);
  const [step, setStep] = useState(initialProgress < 0.615 ? 0 : initialProgress < 0.875 ? 1 : 2);
  const [zone, setZone] = useState(zoneAt(initialProgress));
  const [stillStep, setStillStep] = useState(1);
  const router = useRouter();
  const departure = useMotionValue(0);
  const [departing, setDeparting] = useState(false);
  const restored = useRef(false);
  const heroTransform = useTransform(progress, (value) => `translateY(${-112 * phase(value, 0.25, 0.44)}%)`);
  const copyOpacity = useTransform(progress, (value) => 1 - phase(value, 0.3, 0.42));
  const logoOpacity = useTransform(progress, (value) => phase(value, 0.4, 0.5) * (1 - phase(value, downloadStart, downloadStart + .08)));
  const headingOpacity = useTransform(progress, (value) => phase(value, 0.38, 0.48));
  const headingTransform = useTransform(progress, (value) => `translateY(${24 * (1 - phase(value, 0.38, 0.48))}px)`);
  const shelfOpacity = useTransform(progress, (value) => 1 - phase(value, 1, 1.07));
  const shelfTransform = useTransform(progress, (value) => `translateY(${-24 * phase(value, 1, 1.12)}px)`);
  const resultOpacity = useTransform(progress, (value) => phase(value, 0.79, 0.825));
  const fileOpacity = useTransform(progress, (value) => phase(value, 0.565, 0.595));

  useMotionValueEvent(progress, "change", (value) => {
    setStep(value < 0.615 ? 0 : value < 0.875 ? 1 : 2);
    setZone(zoneAt(value));
  });

  const quiet = zone === "hero" || zone === "closing";

  function goTo(value: number) {
    if (inspect) {
      manual.set(value);
      setPosition(value);
      return;
    }
    scrollToProgress(value);
  }

  function scrollToProgress(value: number) {
    const element = track.current;
    if (!element || root.current?.dataset.scene !== "ready") return;
    const top = element.getBoundingClientRect().top + window.scrollY;
    window.scrollTo({ top: top + value / storyEnd * (element.offsetHeight - window.innerHeight), behavior: "instant" });
  }

  useEffect(() => {
    delete document.documentElement.dataset.arriving;
    router.prefetch("/methodology");
  }, [router]);

  useEffect(() => {
    if (!animated || restored.current) return;
    restored.current = true;
    const returning = history.state?.foundryProgress;
    if (typeof returning !== "number") return;
    history.replaceState({ ...history.state, foundryProgress: undefined }, "");
    scrollToProgress(returning);
    smooth.jump(returning);
    clipboardSelection.jump(clipboardFocus(returning));
  });

  function readMethodology(event: MouseEvent<HTMLAnchorElement>) {
    if (!animated || departing || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    setDeparting(true);
    history.replaceState({ ...history.state, foundryProgress: progress.get() }, "");
    animate(departure, 1, { duration: .7, ease: [.65, 0, .35, 1] }).then(() => {
      document.documentElement.dataset.arriving = "tiles";
      router.push("/methodology");
    });
  }

  function revealFocused(event: FocusEvent<HTMLElement>) {
    if (!animated) return;
    const section = (event.target as HTMLElement).closest<HTMLElement>("[data-stop]");
    if (!section || section.dataset.active === "true") return;
    goTo(Number(section.dataset.stop));
    smooth.jump(Number(section.dataset.stop));
  }

  return (
    <main ref={root} className="foundry-preview story-shell" data-still-step={stillStep} onFocusCapture={revealFocused} data-departing={departing || undefined} style={{ "--story-length": storyEnd } as CSSProperties}>
      <nav className="foundry-nav story-nav" aria-label="Main navigation" data-quiet={animated && quiet ? zone : undefined}>
        {animated && (
          <motion.a className="foundry-logo" href="/" style={{ opacity: logoOpacity }} tabIndex={quiet ? -1 : 0} aria-hidden={quiet} data-hidden={quiet} onClick={(event) => { event.preventDefault(); goTo(0); }}>
            foundry
          </motion.a>
        )}
        <div className="foundry-links">
          <DownloadLink>Download</DownloadLink>
          <a href="https://github.com/hridaya423/foundry" aria-label="Foundry on GitHub"><svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z" /></svg></a>
        </div>
      </nav>
      <div ref={track} id="content" className="story-track">
        <div className="story-stage">
          <motion.div className="foundry-stage story-hero" style={{ transform: heroTransform, "--story-copy-opacity": copyOpacity } as MotionStyle} data-stop="0" data-active={!animated || zone === "hero"}>
            <FoundryHeroContent />
          </motion.div>
          <ShelfCanvas progress={progress} departure={departure} clipboardBelt={clipboardSelection} toolSelection={toolSelection} toolReveal={toolReveal} toolTransition={toolTransition} toolPrevious={toolPrevious} onModeChange={setAnimated} />
          <motion.section style={{ opacity: shelfOpacity, transform: shelfTransform }} className="story-shelf" id="file-shelf" aria-labelledby="shelf-heading" data-stop={shelfStops[1].progress} data-active={!animated || zone === "shelf"}>
            <motion.header className="shelf-heading" style={{ opacity: headingOpacity, transform: headingTransform }}>
              <h2 id="shelf-heading">Convert files<br />without opening another app.</h2>
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
            <motion.nav className="shelf-actions" aria-label="File conversion stages" style={{ opacity: headingOpacity }}>
              {shelfStops.map((stop, index) => (
                <button key={stop.label} aria-pressed={(animated ? step : stillStep) === index} onClick={() => { setStillStep(index); goTo(stop.progress); }}>
                  {stop.label}
                </button>
              ))}
            </motion.nav>
          </motion.section>
          <ClipboardStory progress={progress} focus={clipboardSelection} animated={animated} />
          <ToolsStory progress={progress} animated={animated} selection={toolSelection} reveal={toolReveal} transition={toolTransition} previous={toolPrevious} />
          <MemoryStory progress={progress} animated={animated} onReadMethodology={readMethodology} />
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
