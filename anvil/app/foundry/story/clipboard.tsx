"use client";

import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import Image from "next/image";
import { motion, useMotionValue, useMotionValueEvent, useTransform, type MotionValue } from "motion/react";
import { clipboardCardPose, clipboardFocus, clipboardItems, searchClipboard, type ClipboardItem as ClipboardEntry } from "./clipboard-motion";
import { phase } from "./shelf-motion";

function ClipboardCard({ item, focus, width, height, selected, onSelect }: {
  item: ClipboardEntry;
  focus: MotionValue<number>;
  width: MotionValue<number>;
  height: MotionValue<number>;
  selected: boolean;
  onSelect: (instant: boolean) => void;
}) {
  const index = clipboardItems.indexOf(item);
  const [imageFailed, setImageFailed] = useState(false);
  const pose = useTransform(() => clipboardCardPose(index - focus.get(), width.get(), height.get()));
  const transform = useTransform(pose, (p) => `translate3d(${p.x}px, ${p.y}px, 0) translate(-50%, -50%) perspective(1000px) rotateY(${p.depth}deg) rotateZ(${p.rotate}deg) scale(${p.scale})`);
  const filter = useTransform(pose, (p) => `blur(${p.blur}px)`);
  const opacity = useTransform(pose, (p) => p.opacity);
  const zIndex = useTransform(focus, (value) => 10 - Math.round(Math.abs(index - value)));
  return (
    <motion.button
      className="clipboard-card"
      data-id={item.id}
      data-image-failed={imageFailed || undefined}
      data-kind={item.kind}
      data-selected={selected}
      style={{ transform, filter, opacity, zIndex }}
      aria-label={imageFailed ? `Retry ${item.title} image` : `Select ${item.title}`}
      aria-pressed={selected}
      tabIndex={selected ? 0 : -1}
      onClick={(event) => { if (imageFailed) setImageFailed(false); onSelect(event.detail === 0); }}
    >
      {item.kind === "image" && !imageFailed ? (
        <Image src={item.value} alt="Sunset over a rugged coast, an illustrative clipboard image" fill sizes="(max-width: 899px) 72vw, 330px" onError={() => setImageFailed(true)} />
      ) : (
        <>
          <span className="clipboard-card-kind">{item.kind === "image" ? "Image unavailable" : item.kind}</span>
          {item.kind === "color" && <span className="clipboard-swatch" style={{ background: item.value }} />}
          <span className="clipboard-card-title">{item.title}</span>
          {imageFailed && <span className="clipboard-card-domain">Retry image</span>}
          {item.kind === "link" && <span className="clipboard-card-domain">youtube.com</span>}
        </>
      )}
    </motion.button>
  );
}

export default function ClipboardStory({ progress, focus, animated }: {
  progress: MotionValue<number>;
  focus: MotionValue<number>;
  animated: boolean;
}) {
  const deck = useRef<HTMLDivElement>(null);
  const interacting = useRef(false);
  const copyRequest = useRef(0);
  const width = useMotionValue(1280);
  const height = useMotionValue(720);
  const [selected, setSelected] = useState(() => progress.get() > 1 ? Math.round(focus.get()) : 1);
  const [query, setQuery] = useState("");
  const [copyState, setCopyState] = useState<"idle" | "copying" | "copied" | "failed">("idle");
  const [active, setActive] = useState(progress.get() >= 1.2 && progress.get() < 1.57);
  const matches = searchClipboard(query);
  const item = matches.find((entry) => entry === clipboardItems[selected]) ?? matches[0];
  const position = matches.indexOf(item);
  const opacity = useTransform(progress, (value) => phase(value, 1.07, 1.16) * (1 - phase(value, 1.56, 1.62)));
  const controlsOpacity = useTransform(progress, (value) => phase(value, 1.195, 1.23));
  const transform = useTransform(progress, (value) => `translateY(calc(${60 * (1 - phase(value, 1.05, 1.17))}px - ${18 * phase(value, 1.56, 1.62)}%))`);

  useEffect(() => {
    const element = deck.current!;
    const observer = new ResizeObserver(([entry]) => {
      width.set(entry.contentRect.width);
      height.set(entry.contentRect.height);
    });
    observer.observe(element);
    return () => observer.disconnect();
  }, [width, height]);

  useMotionValueEvent(progress, "change", (value) => {
    setActive(value >= 1.2 && value < 1.57);
    if (!animated) return;
    if (!interacting.current && !query) {
      const next = clipboardFocus(value);
      focus.set(next);
      const index = Math.round(next);
      if (index !== selected) { copyRequest.current++; setCopyState("idle"); }
      setSelected(index);
    }
  });

  function select(next: ClipboardEntry, instant = false) {
    const index = clipboardItems.indexOf(next);
    setSelected(index);
    copyRequest.current++;
    setCopyState("idle");
    if (instant || !animated) focus.jump(index);
    else focus.set(index);
  }

  function search(value: string) {
    setQuery(value);
    copyRequest.current++;
    setCopyState("idle");
    const first = searchClipboard(value)[0];
    if (first) select(first, true);
  }

  function move(direction: number, instant = false) {
    const next = matches[position + direction];
    if (next) select(next, instant);
  }

  function onKeyDown(event: KeyboardEvent<HTMLElement>) {
    const input = event.target instanceof HTMLInputElement;
    const direction = event.key === "ArrowDown" || (!input && event.key === "ArrowRight") ? 1 : event.key === "ArrowUp" || (!input && event.key === "ArrowLeft") ? -1 : 0;
    if (direction) {
      event.preventDefault();
      const next = matches[position + direction];
      if (next) {
        select(next, true);
        if ((event.target as HTMLElement).closest(".clipboard-card"))
          deck.current?.querySelector<HTMLButtonElement>(`[data-id="${next.id}"]`)?.focus({ preventScroll: true });
      }
    }
    if (event.key === "Escape" && query) {
      event.preventDefault();
      search("");
    }
  }

  async function copy() {
    if (!item || copyState === "copying") return;
    const request = ++copyRequest.current;
    setCopyState("copying");
    try {
      if (item.kind === "image") {
        const png = fetch(item.value).then(async (response) => {
          if (!response.ok) throw new Error("Image unavailable");
          const bitmap = await createImageBitmap(await response.blob());
          const canvas = document.createElement("canvas");
          canvas.width = bitmap.width;
          canvas.height = bitmap.height;
          const context = canvas.getContext("2d");
          if (!context) { bitmap.close(); throw new Error("Image copy unavailable"); }
          context.drawImage(bitmap, 0, 0);
          bitmap.close();
          return new Promise<Blob>((resolve, reject) => canvas.toBlob((blob) => blob ? resolve(blob) : reject(new Error("Image copy unavailable")), "image/png"));
        });
        await navigator.clipboard.write([new ClipboardItem({ "image/png": png })]);
      } else await navigator.clipboard.writeText(item.value);
      if (request === copyRequest.current) setCopyState("copied");
    } catch {
      if (request === copyRequest.current) setCopyState("failed");
    }
  }

  return (
    <motion.section
      className="clipboard-section"
      id="clipboard"
      aria-labelledby="clipboard-heading"
      inert={animated && !active}
      style={{ opacity, transform }}
      onFocusCapture={() => { interacting.current = true; }}
      onBlurCapture={(event) => { if (!event.currentTarget.contains(event.relatedTarget)) interacting.current = false; }}
      onKeyDown={onKeyDown}
    >
      <header className="clipboard-heading">
        <h2 id="clipboard-heading">That thing<br />you copied<span>.</span></h2>
        <p>Find it again in clipboard history.</p>
      </header>
      <div className="clipboard-deck" ref={deck} aria-label="Sample clipboard history">
        {matches.map((entry) => (
          <ClipboardCard key={entry.id} item={entry} focus={focus} width={width} height={height} selected={entry === item} onSelect={(instant) => select(entry, instant)} />
        ))}
      </div>
      {item && (
        <motion.div className="clipboard-detail" style={{ opacity: controlsOpacity }}>
          <div className="clipboard-detail-title"><span>{item.title}</span><time>{item.time}</time></div>
          {item.kind === "text" && <p className="clipboard-value">{item.value}</p>}
          {item.kind === "link" && <a className="clipboard-value" href={item.value}>{item.value}</a>}
          {item.kind === "color" && <p className="clipboard-value">{item.value}</p>}
          <div className="clipboard-browse" aria-label="Browse clipboard history">
            <button aria-label="Previous clipboard item" disabled={position <= 0} onClick={(event) => move(-1, event.detail === 0)}>Previous</button>
            <span>{position + 1} / {matches.length}</span>
            <button aria-label="Next clipboard item" disabled={position >= matches.length - 1} onClick={(event) => move(1, event.detail === 0)}>Next</button>
          </div>
        </motion.div>
      )}
      <motion.div className="clipboard-search-area" style={{ opacity: controlsOpacity }}>
        <label htmlFor="clipboard-search">Try the sample clipboard</label>
        <div className="clipboard-search-field">
          <span className="foundry-search-icon" aria-hidden="true" />
          <input id="clipboard-search" type="search" placeholder="Search clipboard" value={query} onChange={(event) => search(event.target.value)} autoComplete="off" aria-controls="clipboard-match-status" />
        </div>
        <div className="clipboard-search-footer">
          <p id="clipboard-match-status" role="status">
            {copyState === "failed" ? <>Copy wasn’t available. {item?.kind === "image" ? <a href={item.value} download="Coast.jpg">Save the image instead.</a> : "Select and copy the text shown here."}</> : copyState === "copied" ? "Copied to your clipboard." : query ? `${matches.length} ${matches.length === 1 ? "match" : "matches"}` : "Text, images, links, colors."}
          </p>
          <button onClick={copy} disabled={!item} aria-disabled={copyState === "copying"}>{copyState === "copying" ? "Copying…" : copyState === "copied" ? "Copied" : "Copy item"}</button>
        </div>

      </motion.div>
      {!matches.length && <div className="clipboard-empty"><p>No matches for “{query}”.</p><button onClick={() => search("")}>Clear search</button></div>}
    </motion.section>
  );
}
