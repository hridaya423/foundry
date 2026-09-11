"use client";

import { useRef, useState, type KeyboardEvent } from "react";
import Image from "next/image";
import { motion, useMotionValueEvent, useTransform, type MotionValue } from "motion/react";
import { mediaItems, type MediaItem } from "./media-motion";
import { phase } from "./shelf-motion";

function MediaCard({ item, slot, selected, animated, instant, active }: {
  item: MediaItem;
  slot: number;
  selected: boolean;
  animated: boolean;
  instant: boolean;
  active: boolean;
}) {
  const [failed, setFailed] = useState(false);
  return (
    <motion.figure
      className="media-card"
      data-portrait={item.portrait}
      data-selected={selected}
      data-slot={slot}
      initial={false}
      animate={{ opacity: selected ? 1 : 0.7, filter: selected ? "blur(0px)" : "blur(1.5px)", transform: `translate(-50%, -50%) translateX(calc(${slot} * var(--media-offset))) perspective(1200px) rotateY(${-slot * 10}deg) rotateZ(${slot * 3}deg) scale(${selected ? 1 : item.portrait ? 0.94 : 0.5})` }}
      transition={!animated || instant ? { duration: 0 } : { type: "spring", stiffness: 500, damping: 30 }}
      style={{ zIndex: selected ? 3 : 1 }}
    >
      <div className="media-poster">
        <Image src={`/assets/foundry/story/media/${item.poster}`} alt={item.portrait ? `${item.creator}, a cropped film excerpt` : "The neural network diagram from 3Blue1Brown’s video"} fill sizes="(max-width: 899px) 88vw, 50vw" />
        {item.video && selected && active && animated && !failed && <video src={`/assets/foundry/story/media/${item.video}`} poster={`/assets/foundry/story/media/${item.poster}`} autoPlay loop playsInline muted preload="none" onError={() => setFailed(true)} aria-label={`${item.creator}, silent cropped excerpt`} />}
        <span className="media-platform" aria-hidden="true" style={{ maskImage: `url(/assets/foundry/story/media/${item.id}.svg)` }} />
      </div>
    </motion.figure>
  );
}

export default function MediaStory({ progress, portrait, animated }: { progress: MotionValue<number>; portrait: MotionValue<number>; animated: boolean }) {
  const tabs = useRef<HTMLDivElement>(null);
  const [selected, setSelected] = useState(1);
  const [instant, setInstant] = useState(false);
  const [active, setActive] = useState(progress.get() >= 1.7 && progress.get() < 2);
  const item = mediaItems[selected];
  const opacity = useTransform(progress, (value) => phase(value, 1.56, 1.62) * (1 - phase(value, 1.92, 2.02)));
  const transform = useTransform(progress, (value) => `translateY(${32 * (1 - phase(value, 1.56, 1.62))}px)`);
  const fileOpacity = useTransform(progress, (value) => phase(value, 1.7, 1.77) * (1 - phase(value, 1.9, 1.96)));

  useMotionValueEvent(progress, "change", (value) => {
    setActive(value >= 1.7 && value < 2);
  });

  function select(index: number, keyboard = false) {
    const target = mediaItems[index].portrait ? 1 : 0;
    if (keyboard || !animated) portrait.jump(target);
    else portrait.set(target);
    setSelected(index);
    setInstant(keyboard);
  }

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    const order = [1, 0, 2];
    const position = order.indexOf(selected);
    const next = event.key === "ArrowRight" ? order[(position + 1) % 3] : event.key === "ArrowLeft" ? order[(position + 2) % 3] : event.key === "Home" ? order[0] : event.key === "End" ? order[2] : -1;
    if (next < 0) return;
    event.preventDefault();
    select(next, true);
    tabs.current?.querySelector<HTMLButtonElement>(`#media-tab-${mediaItems[next].id}`)?.focus();
  }

  return (
    <motion.section className="media-section" id="media" aria-labelledby="media-heading" inert={animated && !active} style={{ opacity, transform }}>
      <header className="media-heading"><h2 id="media-heading">Worth watching<span>.</span><br />Worth keeping<span>.</span></h2></header>
      <div className="media-tabs" role="tablist" aria-label="Media source" ref={tabs} onKeyDown={onKeyDown}>
        {[1, 0, 2].map((index) => {
          const source = mediaItems[index];
          return <button key={source.id} id={`media-tab-${source.id}`} role="tab" aria-selected={selected === index} aria-controls="media-panel" tabIndex={selected === index ? 0 : -1} onClick={(event) => select(index, event.detail === 0)}><span className="media-tab-icon" aria-hidden="true" style={{ maskImage: `url(/assets/foundry/story/media/${source.id}.svg)` }} />{source.label}</button>;
        })}
      </div>
      <div className="media-deck" id="media-panel" role="tabpanel" aria-labelledby={`media-tab-${item.id}`}>
        {mediaItems.map((entry, index) => {
          const distance = (index - selected + 3) % 3;
          return <MediaCard key={entry.id} item={entry} selected={index === selected} slot={distance === 2 ? -1 : distance} animated={animated} instant={instant} active={active} />;
        })}
      </div>
      <div className="media-detail">
        <h3>{item.title}</h3>
        <p><a href={item.source} target="_blank" rel="noreferrer">{item.creator}</a></p>
      </div>
      <motion.div className="media-output" style={{ opacity: fileOpacity }} aria-label={`Example output: ${item.filename}`}>
        <span className="media-still-file" aria-hidden="true"><i /><b>MP4</b></span>
      </motion.div>
      <div className="media-actions">
        <div className="media-command"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m10 13 4-4m-6 7-1 1a4 4 0 0 1-6-6l4-4a4 4 0 0 1 6 0m2 1 1-1a4 4 0 0 1 6 6l-4 4a4 4 0 0 1-6 0" /></svg><span>Paste a link in Foundry</span><span className="media-format">MP4</span></div>
        <p>Paste a supported video link to save it to your Mac.</p>
      </div>
    </motion.section>
  );
}
