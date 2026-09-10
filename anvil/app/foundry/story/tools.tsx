"use client";

import { useRef, useState, type KeyboardEvent } from "react";
import { motion, useMotionValueEvent, useTransform, type MotionValue } from "motion/react";
import { toolExamples, toolBeat } from "./tools-motion";
import { memoryStart } from "./memory-motion";
import { phase } from "./shelf-motion";

const noteLines = toolExamples[2].result.split("\n");

function ToolChoreography({ selected, reveal }: { selected: number; reveal: MotionValue<number> }) {
  const noteTransform = useTransform(reveal, value => `translateY(${56 * (1 - value)}px) rotate(${-5 * (1 - value)}deg) scale(${.88 + .12 * value})`);
  const noteBody = useTransform(reveal, value => `inset(0 0 ${100 * (1 - phase(value, .35, 1))}% 0)`);
  const leftNote = useTransform(reveal, value => `translate(${-18 - 30 * value}px, ${10 + 8 * value}px) rotate(${-8 - 4 * value}deg) scale(${1 - .14 * value})`);
  const rightNote = useTransform(reveal, value => `translate(${18 + 30 * value}px, ${-6 + 8 * value}px) rotate(${7 + 5 * value}deg) scale(${1 - .14 * value})`);
  const otherNotes = useTransform(reveal, value => .75 - value * .48);
  const language = useTransform(reveal, (value): string => value > .5 ? "French" : "English");
  const writingColor = useTransform(reveal, value => value > .12 ? "var(--f-accent)" : "#d6cdbd");
  const writingLift = useTransform(reveal, value => `translateY(${-6 * phase(value, 0, .25)}px)`);
  const delimiter = useTransform(reveal, value => 1 - phase(value, .05, .25));
  return <div className="tool-choreography" aria-hidden="true">
    {selected === 0 && <div className="tool-context">{toolExamples[0].input}</div>}
    {selected === 1 && <motion.div className="tool-language">{language}</motion.div>}
    {selected === 2 && <div className="tool-notes">
      <motion.div className="tool-paper tool-paper-back" style={{ transform: leftNote, opacity: otherNotes }}><h3>Reading list</h3><span /><span /><span /></motion.div>
      <motion.div className="tool-paper tool-paper-back" style={{ transform: rightNote, opacity: otherNotes }}><h3>Shopping list</h3><span /><span /></motion.div>
      <motion.div className="tool-paper tool-paper-match" style={{ transform: noteTransform }}><span className="tool-note-label">Apple Notes</span><h3>{noteLines[0]}</h3><motion.div style={{ clipPath: noteBody }}>{noteLines.slice(1).map(line => <p key={line}>{line}</p>)}</motion.div></motion.div>
    </div>}
    {selected === 3 && <motion.div className="tool-delimiter" style={{ opacity: delimiter }}>Expand with <kbd>Space</kbd></motion.div>}
    {selected === 4 && <div className="tool-profiles"><motion.span style={{ backgroundColor: writingColor, transform: writingLift }}>Writing</motion.span><span>Code</span><span>Research</span></div>}
    {selected === 5 && <div className="tool-clock-label">Unix time · UTC</div>}
  </div>;
}

export default function ToolsStory({ progress, animated, selection, reveal, transition }: { progress: MotionValue<number>; animated: boolean; selection: MotionValue<number>; reveal: MotionValue<number>; transition: MotionValue<number> }) {
  const tabs = useRef<HTMLDivElement>(null);
  const [selected, setSelected] = useState(selection.get());
  const manualBeat = useRef<number | null>(null);
  const [complete, setComplete] = useState(toolBeat(progress.get()).reveal > .99);
  const [active, setActive] = useState(progress.get() >= 2.12 && progress.get() < memoryStart);
  const opacity = useTransform(progress, value => phase(value, 1.98, 2.06) * (1 - phase(value, memoryStart, memoryStart + .06)));
  useMotionValueEvent(reveal, "change", value => setComplete(value > .99));
  useMotionValueEvent(progress, "change", value => {
    setActive(value >= 2.12 && value < memoryStart);
    const beat = toolBeat(value);
    if (manualBeat.current !== beat.selected) {
      manualBeat.current = null;
      transition.jump(beat.transition);
      selection.set(beat.selected);
      setSelected(beat.selected);
      reveal.jump(beat.reveal);
      const tab = tabs.current?.querySelector<HTMLElement>(`#tool-tab-${toolExamples[beat.selected].id}`);
      if (tab && tabs.current) tabs.current.scrollTo({ left: tab.offsetLeft - (tabs.current.clientWidth - tab.offsetWidth) / 2, behavior: "instant" });
    }
  });
  function select(index: number) {
    manualBeat.current = toolBeat(progress.get()).selected;
    setSelected(index);
    transition.jump(1);
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
      <div className="tool-surface tool-source"><span>{item.source}</span><p>{item.input}</p></div>
      <motion.div className="tool-surface tool-result" role="status" style={animated ? { opacity: reveal } : undefined} aria-hidden={animated && !complete}><span>{item.resultLabel}</span><p>{item.result}</p></motion.div>

      <ToolChoreography selected={selected} reveal={reveal} />
      <div className="tool-action">
        <button aria-disabled={complete} onClick={event => { if (complete) return; manualBeat.current = toolBeat(progress.get()).selected; transition.jump(1); if (event.detail === 0 || !animated) reveal.jump(1); else reveal.set(1); }}>
          <span className="foundry-search-icon" aria-hidden="true" />{complete ? "Done" : item.action}
          <kbd aria-hidden="true">{complete ? "✓" : "Enter"}</kbd>
        </button>
        <p>{item.detail}</p>
      </div>
    </article>
  </motion.section>;
}
