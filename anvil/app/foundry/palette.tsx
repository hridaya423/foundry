"use client";

import { useEffect, useId, useRef, useState, type KeyboardEvent } from "react";
import { usePathname, useRouter } from "next/navigation";
import { search, type PaletteCommand } from "./palette-commands";
import "./palette.css";

const openEvent = "foundry:palette";

export function PaletteButton() {
  return <button type="button" className="palette-button" aria-keyshortcuts="Meta+K" onClick={() => dispatchEvent(new Event(openEvent))}><span className="sr-only">Open palette </span><kbd>⌘</kbd><kbd>K</kbd></button>;
}

export default function Palette() {
  const dialog = useRef<HTMLDialogElement>(null);
  const input = useRef<HTMLInputElement>(null);
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState(0);
  const [copied, setCopied] = useState(false);
  const router = useRouter();
  const pathname = usePathname();
  const id = useId();
  const results = search(query);
  const active = Math.min(selected, results.length - 1);

  useEffect(() => {
    const open = () => {
      const element = dialog.current!;
      if (element.open) { element.close(); return; }
      setQuery("");
      setSelected(0);
      setCopied(false);
      element.showModal();
      input.current?.focus();
    };
    const key = (event: globalThis.KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && (event.key === "k" || event.key === "/")) {
        event.preventDefault();
        open();
      }
    };
    addEventListener("keydown", key);
    addEventListener(openEvent, open);
    return () => {
      removeEventListener("keydown", key);
      removeEventListener(openEvent, open);
    };
  }, []);

  function run(command: PaletteCommand | undefined) {
    if (!command) return;
    if (command.kind === "Calculator") {
      navigator.clipboard?.writeText(command.name).then(() => setCopied(true), () => {});
      return;
    }
    dialog.current!.close();
    if (!command.href.startsWith("/")) location.href = command.href;
    else if (command.href.startsWith("/#") && pathname === "/") location.hash = command.href.slice(1);
    else router.push(command.href);
  }

  function key(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      const step = event.key === "ArrowDown" ? 1 : -1;
      setSelected((active + step + results.length) % results.length);
    } else if (event.key === "Enter") {
      event.preventDefault();
      run(results[active]);
    } else if (event.key === "Escape" && query) {
      event.preventDefault();
      setQuery("");
      setSelected(0);
    }
  }

  return (
    <dialog ref={dialog} className="palette" aria-label="Foundry palette" onClick={(event) => event.target === dialog.current && dialog.current.close()}>
      <input
        ref={input}
        className="palette-input"
        value={query}
        onChange={(event) => { setQuery(event.target.value); setSelected(0); setCopied(false); }}
        onKeyDown={key}
        placeholder="Search pages, sections, or type 24*18"
        aria-label="Search the Foundry site"
        role="combobox"
        aria-expanded="true"
        aria-controls={`${id}-list`}
        aria-activedescendant={results.length ? `${id}-${active}` : undefined}
        autoComplete="off"
        spellCheck={false}
      />
      <div className="palette-list" role="listbox" id={`${id}-list`} aria-label="Results">
        {results.map((command, index) => (
          <div key={command.id} id={`${id}-${index}`} role="option" aria-selected={index === active} className="palette-row" onPointerMove={() => setSelected(index)} onClick={() => run(command)}>
            <span className="palette-name">{command.name}</span>
            <span className="palette-kind">{command.kind === "Calculator" && copied ? "Copied" : command.kind}</span>
          </div>
        ))}
        {!results.length && <p className="palette-empty">No matches. Try proof, clipboard or 24*18.</p>}
      </div>
      <p className="palette-footer" aria-hidden="true"><span><kbd>↵</kbd> {results[active]?.kind === "Calculator" ? "Copy" : "Open"}</span><span><kbd>esc</kbd> {query ? "Clear" : "Close"}</span></p>
    </dialog>
  );
}
