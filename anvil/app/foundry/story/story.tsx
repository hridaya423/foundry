"use client";

import { useEffect, useRef, useState, type CSSProperties, type FocusEvent, type MouseEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { animate, motion, useMotionValue, useMotionValueEvent, useScroll, useSpring, useTransform, type MotionStyle } from "motion/react";
import FoundryHeroContent from "../hero-content";
import { GitHubLink } from "../site-chrome";
import { Mark } from "../mark";
import { PaletteButton } from "../palette";
import { foundryDownloadUrl } from "../../site";
import ShelfCanvas from "./story-canvas";
import ClipboardStory from "./clipboard";
import { clipboardFocus } from "./clipboard-motion";
import ToolsStory from "./tools";
import MemoryStory from "./memory";
import DownloadStory from "./download";
import { toolBeat } from "./tools-motion";
import { downloadStart, storyEnd } from "./download-motion";
import { phase, shelfCells, shelfStops } from "./shelf-motion";
import { methodologyFigureTargets } from "../methodology-figure";
import { hashForProgress, stopForHash } from "./story-hash";
import { easeInOut } from "../tokens";

const scrollSpring = { stiffness: 400, damping: 50, mass: 1 };
const zoneAt = (value: number) => value < 0.34 ? "hero" : value > downloadStart ? "closing" : value > 1.08 ? "after" : value > 0.51 ? "shelf" : "transition";

export default function ShelfStory({ inspect, initialProgress, appSize }: { inspect: boolean; initialProgress: number; appSize: string }) {
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
  const copyOpacity = useTransform(progress, (value) => 1 - phase(value, 0.28, 0.36));
  const logoOpacity = useTransform(progress, (value) => phase(value, 0.4, 0.5) * (1 - phase(value, downloadStart, downloadStart + .08)));
  const headingOpacity = useTransform(progress, (value) => phase(value, 0.35, 0.41));
  const headingTransform = useTransform(progress, (value) => `translateY(${24 * (1 - phase(value, 0.35, 0.41))}px)`);
  const shelfOpacity = useTransform(progress, (value) => 1 - phase(value, 1, 1.035));
  const shelfTransform = useTransform(progress, (value) => `translateY(${-24 * phase(value, 1, 1.12)}px)`);
  const resultOpacity = useTransform(progress, (value) => phase(value, 0.79, 0.825));
  const fileOpacity = useTransform(progress, (value) => phase(value, 0.565, 0.595));

  useMotionValueEvent(progress, "change", (value) => {
    setStep(value < 0.615 ? 0 : value < 0.875 ? 1 : 2);
    setZone(zoneAt(value));
    if (!animated || inspect) return;
    const hash = hashForProgress(value);
    if (hash !== location.hash) history.replaceState(history.state, "", hash || location.pathname + location.search);
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
    const returning = history.state?.foundryProgress ?? stopForHash(location.hash);
    if (typeof returning !== "number") return;
    history.replaceState({ ...history.state, foundryProgress: undefined }, "");
    scrollToProgress(returning);
    smooth.jump(returning);
    clipboardSelection.jump(clipboardFocus(returning));
  });

  useEffect(() => {
    if (!animated) return;
    const follow = () => {
      const stop = stopForHash(location.hash);
      if (stop === null) return;
      scrollToProgress(stop);
      smooth.jump(stop);
      clipboardSelection.jump(clipboardFocus(stop));
    };
    addEventListener("hashchange", follow);
    return () => removeEventListener("hashchange", follow);
  });

  function readMethodology(event: MouseEvent<HTMLAnchorElement>) {
    if (!animated || departing || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    setDeparting(true);
    history.replaceState({ ...history.state, foundryProgress: progress.get() }, "");
    animate(departure, 1, { duration: .7, ease: easeInOut }).then(() => {
      holdFigure();
      document.documentElement.dataset.arriving = "tiles";
      router.push("/methodology");
    });
  }

  function holdFigure() {
    const hold = document.createElement("div");
    hold.style.cssText = "position:fixed;inset:0;z-index:50;pointer-events:none";
    hold.setAttribute("aria-hidden", "true");
    for (const { x, y, size } of methodologyFigureTargets(innerWidth)) {
      const tile = document.createElement("i");
      tile.style.cssText = `position:absolute;left:${x - size / 2}px;top:${y - size / 2}px;width:${size}px;height:${size}px;border-radius:18%;background:linear-gradient(160deg,var(--f-orange-light),var(--f-orange-mid) 55%,var(--f-orange-deep));box-shadow:inset 0 1px 0 #ffffff59,inset 0 -1px 0 #0000002e,0 1px 2px #00000080`;
      hold.append(tile);
    }
    document.body.append(hold);
    const release = () => { watch.disconnect(); requestAnimationFrame(() => hold.remove()); };
    const watch = new MutationObserver(() => { if (document.querySelector(".methodology-figure")) release(); });
    watch.observe(document.body, { childList: true, subtree: true });
    setTimeout(release, 3000);
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
      <nav className="foundry-nav story-nav" aria-label="Main navigation" data-quiet={quiet ? zone : undefined}>
        {animated && (
          <motion.a className="foundry-logo" href="/" style={{ opacity: logoOpacity }} tabIndex={quiet ? -1 : 0} aria-hidden={quiet} data-hidden={quiet} onClick={(event) => { event.preventDefault(); goTo(0); }}>
            <Mark />foundry
          </motion.a>
        )}
        <div className="foundry-links">
          <PaletteButton />
          <a href={foundryDownloadUrl}>Download</a>
          <GitHubLink />
        </div>
      </nav>
      <div ref={track} id="content" className="story-track">
        <div className="story-stage">
          <motion.div className="foundry-stage story-hero" style={{ transform: heroTransform, "--story-copy-opacity": copyOpacity } as MotionStyle} data-stop="0" data-active={!animated || zone === "hero"}>
            <FoundryHeroContent onOpen={(target) => animated ? goTo(target.progress) : document.querySelector(target.section)?.scrollIntoView()} />
          </motion.div>
          <ShelfCanvas progress={progress} departure={departure} clipboardBelt={clipboardSelection} toolSelection={toolSelection} toolReveal={toolReveal} toolTransition={toolTransition} toolPrevious={toolPrevious} onModeChange={setAnimated} />
          <motion.section style={{ opacity: shelfOpacity, transform: shelfTransform }} className="story-shelf" id="file-shelf" aria-labelledby="shelf-heading" data-stop={shelfStops[1].progress} data-active={!animated || zone === "shelf"}>
            <motion.header className="shelf-heading" style={{ opacity: headingOpacity, transform: headingTransform }}>
              <h2 id="shelf-heading">Convert files<br />without opening another&nbsp;app.</h2>
              <p>Change formats. Remove backgrounds.</p>
            </motion.header>
            <div className="shelf-file-anchor" role="img" aria-label="Original HEIC file">
              <motion.span className="shelf-file-label" style={{ opacity: fileOpacity }}>HEIC</motion.span>
            </div>
            <div className="shelf-image-anchor" role="img" aria-hidden={step === 0} aria-label={step === 2 ? "An orange and leaf made of colored tiles. The white background has been removed." : "An orange and leaf made of colored tiles on a white tiled background, with PNG beneath it."}>
              <motion.span className="shelf-mold" style={{ opacity: fileOpacity }} aria-hidden="true" />
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
          <DownloadStory progress={progress} animated={animated} appSize={appSize} />
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
