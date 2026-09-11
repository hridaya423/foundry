"use client";

import { useRef, useState, type KeyboardEvent } from "react";
import Link from "next/link";

const commands = ["Clipboard History", "Window Management", "AI Chat"];
const downloadUrl = "https://github.com/hridaya423/foundry/releases/download/v1.0.0/Foundry-1.0.0-build-3.zip";

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

export default function FoundryHeroContent({ illustration = false }: { illustration?: boolean }) {
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
            <a href={downloadUrl}>Download</a>
            <a href="https://github.com/hridaya423/foundry" aria-label="Foundry on GitHub"><svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z" /></svg></a>
          </div>
        </nav>
        <div className="foundry-wordmark" role="img" aria-label="Foundry" />
        <section className="foundry-copy" aria-labelledby="foundry-heading">
          <h1 id="foundry-heading">
            The app you never open<span>.</span>
            <br />
            Opens everything<span>.</span>
          </h1>
          <p>
            Launch apps, find what you copied, transform files,
            <br className="foundry-desktop-break" /> run commands. One native launcher.
          </p>
          <a className="foundry-cta" href={downloadUrl}>Download</a>
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
