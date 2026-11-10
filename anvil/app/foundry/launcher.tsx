"use client";

import { useEffect, useId, useState, type CSSProperties, type KeyboardEvent, type ReactNode } from "react";
import { AnimatePresence, MotionConfig, motion } from "motion/react";
import { shelfCells, shelfStops } from "./story/shelf-motion";
import { tileText } from "./story/tile-glyphs";
import { toolStop } from "./story/tools-motion";
import { clipboardItems } from "./story/clipboard-motion";
import { calculate } from "./calculate";
import "./launcher.css";

export type LauncherTarget = { progress: number; section: string };

const icon = (paths: ReactNode) => <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths}</svg>;

const icons: Record<string, ReactNode> = {
  clipboard: icon(<><rect x="6" y="5" width="13" height="16" rx="2" /><path d="M9 5V4a1 1 0 0 1 1-1h5a1 1 0 0 1 1 1v1M9.5 10h6M9.5 13.5h6M9.5 17h3.5" /></>),
  convert: icon(<><rect x="3.5" y="3.5" width="17" height="17" rx="3" /><circle cx="9" cy="9" r="1.8" /><path d="m20.5 15-5-5-11 10.5" /></>),
  calculator: icon(<><rect x="5" y="3" width="14" height="18" rx="2.5" /><path d="M8.5 7h7M8.5 11.5h.01M12 11.5h.01M15.5 11.5h.01M8.5 15h.01M12 15h.01M15.5 15v2.5M8.5 18h.01M12 18h.01" /></>),
  translation: icon(<><path d="M4 5h9M8.5 3v2M6 5c.6 3.4 2.8 6 6 7.5M11 5c-.8 3.8-3.4 6.8-7 8.5" /><path d="m12 21 4.5-10 4.5 10M13.6 17.5h5.8" /></>),
  snippets: icon(<path d="M8 7 3.5 12 8 17M16 7l4.5 5-4.5 5M13.5 5l-3 14" />),
  ai: icon(<><path d="M12 3.5 13.8 9l5.7 1.8-5.7 1.9L12 18.5l-1.8-5.8-5.7-1.9L10.2 9z" /><path d="M18.5 3v3M17 4.5h3" /></>),
  video: icon(<path d="M12 4v11M7.5 10.5 12 15l4.5-4.5M5 19.5h14" />),
  developer: icon(<path d="m7 8-4 4 4 4M17 8l4 4-4 4" />),
  link: icon(<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1" />),
};

const commands = [
  { id: "clipboard", name: "Clipboard History", keywords: "copy paste history clip", target: { progress: 1.3, section: "#clipboard" } },
  { id: "convert", name: "Convert Image", keywords: "png heic jpg webp image file background photo", target: { progress: shelfStops[1].progress, section: "#file-shelf" } },
  { id: "calculator", name: "Calculator", keywords: "math sum calc", target: { progress: toolStop(0), section: "#tools" } },
  { id: "translation", name: "Translate", keywords: "translation language french hello", target: { progress: toolStop(1), section: "#tools" } },
  { id: "snippets", name: "Snippets", keywords: "text expand keyword thx", target: { progress: toolStop(2), section: "#tools" } },
  { id: "video", name: "Download Video", keywords: "youtube link mp4 save video", target: { progress: toolStop(4), section: "#tools" } },
];
const calculatorIndex = 2;
const demo = ["clip", "24*18", "hello", "png"];
const image = shelfCells.filter((cell) => cell.kind === "image");
const imageSize = { columns: Math.max(...image.map((cell) => cell.column)) + 1, rows: Math.max(...image.map((cell) => cell.row)) + 1 };

export function toolIcon(id: string) {
  return icons[id];
}

export function Key({ children }: { children: ReactNode }) {
  return <kbd className="launcher-key">{children}</kbd>;
}

export function Tiles({ text }: { text: string }) {
  const glyph = tileText(text);
  const left = Math.min(...glyph.points.map((point) => point.x)), top = Math.min(...glyph.points.map((point) => point.y));
  const rows = Math.max(...glyph.points.map((point) => point.y)) - top + 1;
  return (
    <div className="launcher-tiles" role="img" aria-label={text} style={{ "--columns": glyph.width, "--rows": rows } as CSSProperties}>
      {glyph.points.map((point) => <i key={`${point.x}:${point.y}`} style={{ "--x": point.x - left, "--y": point.y - top } as CSSProperties} />)}
    </div>
  );
}

function Preview({ id, expression, answer }: { id: string; expression: string; answer: string | null }) {
  if (id === "calculator") return (
    <div className="launcher-preview-calc">
      <p className="launcher-preview-label">{(answer === null ? "24*18" : expression).replace(/\*/g, " × ")}</p>
      <Tiles text={answer ?? "432"} />
    </div>
  );
  if (id === "clipboard") return (
    <ul className="launcher-clips">
      {[clipboardItems[4], clipboardItems[2], clipboardItems[3]].map((item, index) => (
        <li key={item.id} style={{ "--i": index } as CSSProperties}>
          {item.kind === "color" ? <span className="launcher-swatch" style={{ background: item.value }} /> : <span className="launcher-clip-icon">{item.kind === "link" ? icons.link : icons.snippets}</span>}
          <span><strong>{item.title}</strong>{item.app} · {item.time}</span>
        </li>
      ))}
    </ul>
  );
  if (id === "convert") return (
    <div className="launcher-preview-convert">
      <div className="launcher-orange" style={{ "--columns": imageSize.columns, "--rows": imageSize.rows } as CSSProperties} aria-label="An orange made of tiles" role="img">
        {image.map((cell) => <i key={`${cell.column}:${cell.row}`} data-background={!cell.subject || undefined} style={{ "--x": cell.column, "--y": cell.row, background: cell.color } as CSSProperties} />)}
      </div>
      <p className="launcher-chips"><span>HEIC</span>{icon(<path d="M5 12h14M13 6l6 6-6 6" />)}<span data-accent>PNG</span></p>
    </div>
  );
  if (id === "translation") return (
    <div className="launcher-preview-pair">
      <p><span className="launcher-preview-label">English</span>Hello</p>
      <p><span className="launcher-preview-label">French</span><strong>Bonjour</strong></p>
    </div>
  );
  if (id === "snippets") return (
    <div className="launcher-preview-pair">
      <p><span className="launcher-preview-label">Keyword</span><code>;thx</code></p>
      <p><span className="launcher-preview-label">Expands to</span><strong>Thank you.</strong></p>
    </div>
  );
  return (
    <div className="launcher-preview-video">
      <p className="launcher-preview-label">youtube.com/watch?v=aircAruvnKk</p>
      <div className="launcher-progress"><i /></div>
      <p><strong>MP4</strong> · Saved to Downloads</p>
    </div>
  );
}

export default function Launcher({ onOpen }: { onOpen?: (target: LauncherTarget) => void }) {
  const [query, setQuery] = useState("");
  const [typed, setTyped] = useState("");
  const [engaged, setEngaged] = useState(false);
  const [focused, setFocused] = useState(false);
  const [pressed, setPressed] = useState(false);
  const [selected, setSelected] = useState(1);
  const [pick, setPick] = useState(0);
  const [copied, setCopied] = useState(false);
  const id = useId();
  const current = engaged ? query : typed;
  const text = current.trim().toLowerCase();
  const answer = calculate(current);
  const matches = commands.map((command) => !text || answer !== null || `${command.name} ${command.keywords}`.toLowerCase().includes(text));
  const visible = commands.flatMap((_, index) => matches[index] ? [index] : []);
  const active = !text ? selected : answer !== null ? calculatorIndex : visible[Math.min(pick, visible.length - 1)] ?? -1;
  const shown = active < 0 ? null : commands[active];
  const rowId = (index: number) => index === 1 ? "foundry-command-1" : `${id}-${index}`;

  useEffect(() => {
    if (engaged || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    let cancelled = false;
    const timers: number[] = [];
    const wait = (ms: number) => new Promise<void>((resolve) => { timers.push(window.setTimeout(resolve, ms)); });
    const away = () => scrollY > 40 || document.hidden;
    async function play() {
      await wait(1800);
      for (let round = 0; !cancelled; round++) {
        while (!cancelled && away()) { setTyped(""); await wait(500); }
        const word = demo[round % demo.length];
        for (let length = 1; length <= word.length && !cancelled && !away(); length++) { setTyped(word.slice(0, length)); await wait(75 + Math.random() * 70); }
        await wait(520); setPressed(true); await wait(170); setPressed(false);
        await wait(2300);
        for (let length = word.length - 1; length >= 0 && !cancelled; length--) { setTyped(word.slice(0, length)); await wait(26); }
        await wait(1100);
      }
    }
    play();
    return () => { cancelled = true; timers.forEach(clearTimeout); setTyped(""); };
  }, [engaged]);

  function search(value: string) {
    setQuery(value);
    setPick(0);
    setCopied(false);
  }

  function release() {
    if (!query && !focused) setEngaged(false);
  }

  function run(index = active) {
    if (answer !== null) {
      navigator.clipboard?.writeText(answer).then(() => setCopied(true), () => {});
      return;
    }
    if (index >= 0) onOpen?.(commands[index].target);
  }

  function point(index: number) {
    if (!engaged || !matches[index]) return;
    if (text) setPick(visible.indexOf(index)); else setSelected(index);
  }

  function key(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      const step = event.key === "ArrowDown" ? 1 : -1;
      if (text) setPick((Math.min(pick, visible.length - 1) + step + visible.length) % visible.length);
      else setSelected((selected + step + commands.length) % commands.length);
    } else if (event.key === "Enter") {
      event.preventDefault();
      run();
    } else if (event.key === "Escape" && query) {
      search("");
    }
  }

  return (
    <MotionConfig reducedMotion="user">
    <section
      className="foundry-palette launcher"
      aria-label="Try Foundry"
      data-demo={!engaged || undefined}
      onPointerEnter={() => setEngaged(true)}
      onPointerLeave={release}
    >
      <div className="launcher-search">
        <span className="launcher-search-icon">{icon(<><circle cx="11" cy="11" r="6.5" /><path d="m16 16 4 4" /></>)}</span>
        <input
          type="text"
          value={query}
          onChange={(event) => search(event.target.value)}
          onKeyDown={key}
          onFocus={() => { setFocused(true); setEngaged(true); }}
          onBlur={() => { setFocused(false); if (!query) setEngaged(false); }}
          placeholder={engaged ? "Try 24*18, hello or png" : typed ? "" : "Search commands..."}
          aria-label="Search Foundry commands"
          role="combobox"
          aria-expanded="true"
          aria-controls={`${id}-results`}
          aria-activedescendant={active >= 0 ? rowId(active) : undefined}
          autoComplete="off"
          spellCheck={false}
        />
        {!engaged && typed && <span className="launcher-ghost" aria-hidden="true">{typed}<i /></span>}
      </div>
      <div className="launcher-main">
        <div className="launcher-results" role="listbox" id={`${id}-results`} aria-label="Commands">
          {commands.map((command, index) => (
            <div
              key={command.id}
              id={rowId(index)}
              className="launcher-row"
              role="option"
              aria-selected={index === active}
              aria-disabled={!matches[index] || undefined}
              data-dim={!matches[index] || undefined}
              onPointerMove={() => point(index)}
              onClick={() => matches[index] && run(index)}
            >
              {index === active && <motion.span layoutId={`${id}-selection`} className="launcher-selection" transition={{ duration: .12, ease: [0.23, 1, 0.32, 1] }} />}
              <span className="launcher-icon">{icons[command.id]}</span>
              <span className="launcher-name">{command.name}</span>
              {index === active && <span className="launcher-enter" data-pressed={pressed || undefined} aria-hidden="true"><Key>↵</Key></span>}
            </div>
          ))}
        </div>
        <div className="launcher-preview" aria-live="polite">
          <AnimatePresence mode="popLayout" initial={false}>
            <motion.div
              key={shown ? `${shown.id}:${shown.id === "calculator" ? answer : ""}` : "none"}
              className="launcher-preview-body"
              initial={{ opacity: 0, y: 10, filter: "blur(4px)" }}
              animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
              exit={{ opacity: 0, y: -8, filter: "blur(4px)" }}
              transition={{ duration: .32, ease: [0.23, 1, 0.32, 1] }}
            >
              {shown ? <Preview id={shown.id} expression={current.trim()} answer={answer} /> : <p className="launcher-preview-label">No commands match “{current.trim()}”.</p>}
            </motion.div>
          </AnimatePresence>
          {answer !== null && engaged && <p className="launcher-copy"><Key>↵</Key>{copied ? "Copied" : "Copy answer"}</p>}
        </div>
      </div>
    </section>
    </MotionConfig>
  );
}
