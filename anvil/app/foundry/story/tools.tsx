"use client";

import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import { animate, motion, useMotionValueEvent, useTransform, type MotionValue } from "motion/react";
import { toolExamples, toolBeat, toolsEnd, toolsEnter, toolsStop } from "./tools-motion";
import { phase } from "./shelf-motion";

const overlayLabels: Partial<Record<(typeof toolExamples)[number]["id"], [before: string | null, after: string]>> = {
  calculator: [null, toolExamples[0].input],
  translation: ["English", "French"],
  ai: ["Draft", "Writing profile · sample response"],
  video: ["Video link", "Saved file"],
  developer: ["Unix time · UTC", "Date, 00:00 UTC"],
};

function ToolLabel({ index, complete, exit }: { index: number; complete: boolean; exit?: boolean }) {
  const { id } = toolExamples[index];
  const label = overlayLabels[id]?.[complete ? 1 : 0];
  if (!label) return null;
  return <div className={`tool-label ${exit ? "tool-out" : "tool-in"}`} data-tool={id}>{label}</div>;
}

export default function ToolsStory({ progress, animated, selection, reveal, transition, previous }: { progress: MotionValue<number>; animated: boolean; selection: MotionValue<number>; reveal: MotionValue<number>; transition: MotionValue<number>; previous: MotionValue<number> }) {
  const tabs = useRef<HTMLDivElement>(null);
  const [selected, setSelected] = useState(selection.get());
  const [leaving, setLeaving] = useState<number | null>(null);
  const leavingTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const manualBeat = useRef<number | null>(null);
  const [complete, setComplete] = useState(toolBeat(progress.get()).reveal > .99);
  const [active, setActive] = useState(progress.get() >= toolsEnter + .12 && progress.get() < toolsEnd);
  const opacity = useTransform(progress, value => phase(value, toolsEnter, toolsEnter + .08) * (1 - phase(value, toolsEnd, toolsEnd + .06)));
  useEffect(() => () => clearTimeout(leavingTimer.current), []);
  useMotionValueEvent(reveal, "change", value => setComplete(value > .99));
  function changeSelected(next: number) {
    if (next === selected) return;
    clearTimeout(leavingTimer.current);
    setLeaving(window.matchMedia("(prefers-reduced-motion: reduce)").matches ? null : selected);
    leavingTimer.current = setTimeout(() => setLeaving(null), 200);
    setSelected(next);
  }
  function centerTab(index: number) {
    const tab = tabs.current?.querySelector<HTMLElement>(`#tool-tab-${toolExamples[index].id}`);
    if (tab && tabs.current) tabs.current.scrollTo({ left: tab.offsetLeft - (tabs.current.clientWidth - tab.offsetWidth) / 2, behavior: "instant" });
  }
  useEffect(() => centerTab(selection.get()), [selection]);
  useMotionValueEvent(progress, "change", value => {
    setActive(value >= toolsEnter + .12 && value < toolsEnd);
    const beat = toolBeat(value);
    if (manualBeat.current !== beat.selected) {
      manualBeat.current = null;
      transition.jump(beat.transition);
      previous.set(beat.selected > 0 ? beat.selected - 1 : beat.selected);
      selection.set(beat.selected);
      changeSelected(beat.selected);
      reveal.jump(beat.reveal);
      centerTab(beat.selected);
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
    centerTab(index);
  }
  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    const count = toolExamples.length;
    const next = event.key === "ArrowDown" || event.key === "ArrowRight" ? (selected + 1) % count : event.key === "ArrowUp" || event.key === "ArrowLeft" ? (selected + count - 1) % count : event.key === "Home" ? 0 : event.key === "End" ? count - 1 : -1;
    if (next < 0) return;
    event.preventDefault();
    select(next);
    tabs.current?.querySelector<HTMLButtonElement>(`#tool-tab-${toolExamples[next].id}`)?.focus({ preventScroll: true });
  }
  const item = toolExamples[selected];
  return <motion.section id="tools" className="tools-section" aria-labelledby="tools-heading" style={{ opacity }} data-stop={toolsStop} data-active={!animated || active}>
    <header className="tools-heading"><h2 id="tools-heading">Small tasks.<br />All here.</h2></header>
    <div ref={tabs} className="tools-nav" role="tablist" aria-label="Explore tools" onKeyDown={onKeyDown}>
      {toolExamples.map((tool, index) => <button key={tool.id} id={`tool-tab-${tool.id}`} role="tab" aria-selected={selected === index} aria-controls="tool-panel" tabIndex={selected === index ? 0 : -1} onClick={() => select(index)}>{tool.name}</button>)}
    </div>
    <article id="tool-panel" className="tool-example" role="tabpanel" aria-labelledby={`tool-tab-${item.id}`} data-tool={item.id}>
      <div className="tool-surface tool-source"><span>{item.source}</span><p>{item.input}</p></div>
      <motion.div className="tool-surface tool-result" role="status" style={animated ? { opacity: reveal } : undefined} aria-hidden={animated && !complete}><span>{item.resultLabel}</span><p>{item.result}</p></motion.div>
      <div className="tool-choreography" aria-hidden="true">
        <ToolLabel key={`${selected}:${complete}`} index={selected} complete={complete} />
        {leaving !== null && <ToolLabel key={`out-${leaving}`} index={leaving} complete exit />}
      </div>
      <div className="tool-action">
        <button aria-disabled={complete} onClick={event => { if (complete) return; manualBeat.current = toolBeat(progress.get()).selected; transition.jump(1); if (event.detail === 0 || !animated) reveal.jump(1); else reveal.set(1); }}>
          <span className="foundry-search-icon" aria-hidden="true" /><span>{item.action}</span>
          <kbd aria-hidden="true">Enter</kbd>
        </button>
        <p>{item.detail}</p>
      </div>
    </article>
  </motion.section>;
}
