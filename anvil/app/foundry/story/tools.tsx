"use client";

import { useEffect, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import { animate, motion, useMotionValue, useMotionValueEvent, useTransform, type MotionStyle, type MotionValue } from "motion/react";
import { toolExamples, toolBeat } from "./tools-motion";
import { memoryStart } from "./memory-motion";
import { phase } from "./shelf-motion";

const noteLines = toolExamples[2].result.split("\n");

type LeavingTool = { index: number; reveal: number };
type ToolItem = (typeof toolExamples)[number];

function NotesWindow({ windowStyle, hitStyle, dimStyle, clipStyle }: { windowStyle?: MotionStyle; hitStyle?: MotionStyle; dimStyle?: MotionStyle; clipStyle?: MotionStyle }) {
  const rows = [
    { title: noteLines[0], meta: "Today · Visit the bookshop…", hit: true },
    { title: "Reading list", meta: "Tue · The new paperback…", hit: false },
    { title: "Shopping list", meta: "Mon · Coffee, eggs…", hit: false },
  ];
  return (
    <motion.div className="tool-notes-window" style={windowStyle}>
      <div className="tool-notes-chrome" aria-hidden="true">
        <i /><i /><i />
        <span className="tool-notes-search"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4"><circle cx="11" cy="11" r="6.5" /><path d="m19.5 19.5-3.6-3.6" /></svg>{toolExamples[2].input}</span>
      </div>
      <div className="tool-notes-cols">
        <ul className="tool-notes-list">
          {rows.map((row) => (
            <motion.li key={row.title} className={row.hit ? "hit" : undefined} style={row.hit ? undefined : dimStyle}>
              {row.hit && <motion.i className="tool-notes-hit" aria-hidden="true" style={hitStyle} />}
              <b>{row.title}</b><span>{row.meta}</span>
            </motion.li>
          ))}
        </ul>
        <div className="tool-notes-note">
          <h3>{noteLines[0]}</h3>
          <motion.div style={clipStyle}>{noteLines.slice(1).map((line) => <p key={line}>{line}</p>)}</motion.div>
        </div>
      </div>
    </motion.div>
  );
}

function ToolOverlay({ index, reveal, exit }: { index: number; reveal: MotionValue<number> | number; exit?: boolean }) {
  const captured = useMotionValue(typeof reveal === "number" ? reveal : 0);
  const rv = typeof reveal === "number" ? captured : reveal;
  const noteTransform = useTransform(rv, value => `translateY(${56 * (1 - value)}px) rotate(${-5 * (1 - value)}deg) scale(${.88 + .12 * value})`);
  const noteBody = useTransform(rv, value => `inset(0 0 ${100 * (1 - phase(value, .35, 1))}% 0)`);
  const noteHitOpacity = useTransform(rv, value => phase(value, .18, .5));
  const noteHitShift = useTransform(rv, value => `translateX(${-8 * (1 - phase(value, .18, .5))}px)`);
  const otherNotes = useTransform(rv, value => .75 - value * .48);
  const language = useTransform(rv, (value): string => value > .5 ? "French" : "English");
  const writingColor = useTransform(rv, value => value > .12 ? "var(--f-accent)" : "#d6cdbd");
  const writingLift = useTransform(rv, value => `translateY(${-6 * phase(value, 0, .25)}px)`);
  const delimiter = useTransform(rv, value => 1 - phase(value, .05, .25));
  const cls = exit ? " tool-out" : " tool-in";
  const id = toolExamples[index].id;
  return <>
    {index === 0 && <div className={"tool-context" + cls} data-tool={id}>{toolExamples[0].input}</div>}
    {index === 1 && <motion.div className={"tool-language" + cls} data-tool={id}>{language}</motion.div>}
    {index === 2 && <div className={"tool-notes" + cls} data-tool={id}>
      <NotesWindow windowStyle={{ transform: noteTransform }} hitStyle={{ opacity: noteHitOpacity, transform: noteHitShift }} dimStyle={{ opacity: otherNotes }} clipStyle={{ clipPath: noteBody }} />
    </div>}
    {index === 3 && <motion.div className={"tool-delimiter" + cls} data-tool={id} style={{ opacity: delimiter }}>Expand with <kbd>Space</kbd></motion.div>}
    {index === 4 && <div className={"tool-profiles" + cls} data-tool={id}><motion.span style={{ backgroundColor: writingColor, transform: writingLift }}>Writing</motion.span><span>Code</span><span>Research</span></div>}
    {index === 5 && <div className={"tool-clock-label" + cls} data-tool={id}>Unix time · UTC</div>}
  </>;
}

function ToolChoreography({ selected, leaving, reveal }: { selected: number; leaving: LeavingTool | null; reveal: MotionValue<number> }) {
  return <div className="tool-choreography" aria-hidden="true">
    <ToolOverlay index={selected} reveal={reveal} />
    {leaving && <ToolOverlay index={leaving.index} reveal={leaving.reveal} exit />}
  </div>;
}

function Surfaces({ item, exit, result }: { item: ToolItem; exit?: boolean; result?: ReactNode }) {
  return <div className={`tool-scene${exit ? " tool-out" : " tool-in"}`} data-tool={item.id} aria-hidden={exit || undefined}>
    <div className="tool-surface tool-source"><span>{item.source}</span><p>{item.input}</p></div>
    {result ?? <div className="tool-surface tool-result"><span>{item.resultLabel}</span><p>{item.result}</p></div>}
  </div>;
}

export default function ToolsStory({ progress, animated, selection, reveal, transition, previous }: { progress: MotionValue<number>; animated: boolean; selection: MotionValue<number>; reveal: MotionValue<number>; transition: MotionValue<number>; previous: MotionValue<number> }) {
  const tabs = useRef<HTMLDivElement>(null);
  const [selected, setSelected] = useState(selection.get());
  const [leaving, setLeaving] = useState<LeavingTool | null>(null);
  const leavingTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const manualBeat = useRef<number | null>(null);
  const [complete, setComplete] = useState(toolBeat(progress.get()).reveal > .99);
  const [active, setActive] = useState(progress.get() >= 2.12 && progress.get() < memoryStart);
  const opacity = useTransform(progress, value => phase(value, 1.98, 2.06) * (1 - phase(value, memoryStart, memoryStart + .06)));
  useEffect(() => {
    return () => clearTimeout(leavingTimer.current);
  }, []);
  useMotionValueEvent(reveal, "change", value => setComplete(value > .99));
  function changeSelected(next: number) {
    if (next === selected) return;
    clearTimeout(leavingTimer.current);
    setLeaving(!window.matchMedia("(prefers-reduced-motion: reduce)").matches ? { index: selected, reveal: reveal.get() } : null);
    leavingTimer.current = setTimeout(() => setLeaving(null), 340);
    setSelected(next);
  }
  useMotionValueEvent(progress, "change", value => {
    setActive(value >= 2.12 && value < memoryStart);
    const beat = toolBeat(value);
    if (manualBeat.current !== beat.selected) {
      manualBeat.current = null;
      transition.jump(beat.transition);
      previous.set(beat.selected > 0 ? beat.selected - 1 : beat.selected);
      selection.set(beat.selected);
      changeSelected(beat.selected);
      reveal.jump(beat.reveal);
      const tab = tabs.current?.querySelector<HTMLElement>(`#tool-tab-${toolExamples[beat.selected].id}`);
      if (tab && tabs.current) tabs.current.scrollTo({ left: tab.offsetLeft - (tabs.current.clientWidth - tab.offsetWidth) / 2, behavior: "instant" });
    }
  });
  function select(index: number) {
    if (index === selected) return;
    manualBeat.current = toolBeat(progress.get()).selected;
    previous.set(selected);
    changeSelected(index);
    transition.jump(0);
    animate(transition, 1, { duration: .3, ease: [0.23, 1, 0.32, 1] });
    reveal.jump(0);
    selection.set(index);
    const tab = tabs.current?.querySelector<HTMLElement>(`#tool-tab-${toolExamples[index].id}`);
    if (tab && tabs.current) tabs.current.scrollTo({ left: tab.offsetLeft - (tabs.current.clientWidth - tab.offsetWidth) / 2, behavior: "instant" });
  }
  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    const next = event.key === "ArrowDown" || event.key === "ArrowRight" ? (selected + 1) % 6 : event.key === "ArrowUp" || event.key === "ArrowLeft" ? (selected + 5) % 6 : event.key === "Home" ? 0 : event.key === "End" ? 5 : -1;
    if (next < 0) return;
    event.preventDefault();
    select(next);
    tabs.current?.querySelector<HTMLButtonElement>(`#tool-tab-${toolExamples[next].id}`)?.focus({ preventScroll: true });
  }
  const item = toolExamples[selected];
  return <motion.section id="tools" className="tools-section" aria-labelledby="tools-heading" style={{ opacity }} inert={animated && !active}>
    <header className="tools-heading"><h2 id="tools-heading">Small tasks<span>.</span><br />All here<span>.</span></h2></header>
    <div ref={tabs} className="tools-nav" role="tablist" aria-label="Explore tools" onKeyDown={onKeyDown}>
      {toolExamples.map((tool, index) => <button key={tool.id} id={`tool-tab-${tool.id}`} role="tab" aria-selected={selected === index} aria-controls="tool-panel" tabIndex={selected === index ? 0 : -1} onClick={() => select(index)}>{tool.name}</button>)}
    </div>
    <article id="tool-panel" className="tool-example" role="tabpanel" aria-labelledby={`tool-tab-${item.id}`} data-tool={item.id}>
      <div className="tool-scene-stack">
        <Surfaces key={selected} item={item} result={item.id === "notes"
          ? <div className="tool-surface tool-result tool-notes-result" role="status"><NotesWindow /></div>
          : <motion.div className="tool-surface tool-result" role="status" style={animated ? { opacity: reveal } : undefined} aria-hidden={animated && !complete}><span>{item.resultLabel}</span><p>{item.result}</p></motion.div>} />
        {leaving && <Surfaces item={toolExamples[leaving.index]} exit />}
      </div>

      <ToolChoreography selected={selected} leaving={leaving} reveal={reveal} />
      <div className="tool-action">
        <button aria-disabled={complete} onClick={event => { if (complete) return; manualBeat.current = toolBeat(progress.get()).selected; transition.jump(1); if (event.detail === 0 || !animated) reveal.jump(1); else reveal.set(1); }}>
          <span className="foundry-search-icon" aria-hidden="true" /><span className="tool-swap" key={`${selected}:${complete}`}>{complete ? "Done" : item.action}</span>
          <kbd aria-hidden="true">{complete ? "✓" : "Enter"}</kbd>
        </button>
        <p className="tool-swap" key={`detail-${selected}`}>{item.detail}</p>
      </div>
    </article>
  </motion.section>;
}
