"use client";

import { useRef, useState, type KeyboardEvent } from "react";
import Link from "next/link";

const commands = ["Clipboard History", "Window Management", "AI Chat"];

function CommandIcon({ index }: { index: number }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      aria-hidden="true"
    >
      {index === 0 ? (
        <>
          <rect x="6" y="5" width="14" height="17" rx="2" />
          <rect x="10" y="2" width="6" height="6" rx="1.5" />
          <path d="M6 17H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h3" />
        </>
      ) : index === 1 ? (
        <>
          <rect x="2" y="3" width="20" height="18" rx="2" />
          <path d="M2 8h20M9 8v13" />
        </>
      ) : (
        <path d="M5 3h14a3 3 0 0 1 3 3v10a3 3 0 0 1-3 3h-8l-6 4v-4a3 3 0 0 1-3-3V6a3 3 0 0 1 3-3Z" />
      )}
    </svg>
  );
}

export default function FoundryHeroContent({ onExplore, illustration = false }: { onExplore?: () => void; illustration?: boolean }) {
  const search = useRef<HTMLInputElement>(null);
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState(1);
  const filtered = commands
    .map((name, index) => ({ name, index }))
    .filter((command) =>
      command.name.toLowerCase().includes(query.toLowerCase()),
    );
  const active =
    filtered.find((command) => command.index === selected) ?? filtered[0];
  function explore() {
    if (onExplore) {
      onExplore();
      return;
    }
    const input = search.current;
    if (!input) return;
    const box = input.getBoundingClientRect();
    input.focus({ preventScroll: true });
    if (box.bottom > window.innerHeight || box.top < 0)
      input.scrollIntoView({ block: "center" });
  }
  function onKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "Escape") {
      setQuery("");
      return;
    }
    if (!active) return;
    const index = filtered.findIndex(
      (command) => command.index === active.index,
    );
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      setSelected(
        filtered[
          (index + (event.key === "ArrowDown" ? 1 : -1) + filtered.length) %
            filtered.length
        ].index,
      );
    }
    if (event.key === "Enter") {
      event.preventDefault();
      setSelected(active.index);
    }
  }
  return (
    <>
        <nav className="foundry-nav" aria-label="Main navigation">
          <Link className="foundry-logo" href="/">
            foundry
          </Link>
          <div className="foundry-links">
            <button onClick={explore}>Explore</button>
            <a href="https://github.com/hridaya423/foundry">GitHub</a>
          </div>
        </nav>
        <div className="foundry-wordmark" role="img" aria-label="Foundry" />
        <section className="foundry-copy" aria-labelledby="foundry-heading">
          <h1 id="foundry-heading">
            Less switching<span>.</span>
            <br />
            More doing<span>.</span>
          </h1>
          <p>
            Apps, clipboard, AI and everyday
            <br className="foundry-desktop-break" /> tools in one native
            launcher.
          </p>
          <button className="foundry-cta" onClick={explore}>
            Explore Foundry <span aria-hidden="true">⟶</span>
          </button>
        </section>
        <section className="foundry-palette" aria-label={illustration ? "Foundry launcher" : "Try Foundry commands"} data-illustration={illustration || undefined}>
          <div className="foundry-search">
            <span className="foundry-search-icon" aria-hidden="true" />
            {illustration ? <span className="foundry-search-placeholder">Search apps and commands</span> : <input
              ref={search}
              aria-label="Search apps and commands"
              role="combobox"
              aria-autocomplete="list"
              aria-expanded="true"
              aria-controls="foundry-results"
              aria-activedescendant={
                active ? `foundry-command-${active.index}` : undefined
              }
              placeholder="Search apps and commands"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              onKeyDown={onKeyDown}
            />}
          </div>
          <div
            id="foundry-results"
            role={illustration ? undefined : "listbox"}
            aria-label={illustration ? undefined : "Commands"}
            className="foundry-results"
          >
            {filtered.map((command) => (
              <div
                key={command.index}
                id={`foundry-command-${command.index}`}
                role={illustration ? undefined : "option"}
                aria-selected={illustration ? undefined : active?.index === command.index}
                data-selected={illustration && command.index === 1 || undefined}
                className="foundry-row"
                onMouseDown={illustration ? undefined : (event) => event.preventDefault()}
                onClick={illustration ? undefined : () => {
                  setSelected(command.index);
                  search.current?.focus({ preventScroll: true });
                }}
              >
                <span className="foundry-command-icon" aria-hidden="true">
                  <CommandIcon index={command.index} />
                </span>
                <span>{command.name}</span>
              </div>
            ))}
            {!filtered.length && (
              <p className="foundry-empty" role="status">
                No matching commands.
              </p>
            )}
          </div>
        </section>
    </>
  );
}
