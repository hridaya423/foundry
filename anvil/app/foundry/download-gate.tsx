"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";

export const foundryDownloadUrl =
  "https://github.com/hridaya423/foundry/releases/latest/download/Foundry.dmg";

export default function DownloadLink({ className, children }: { className?: string; children: ReactNode }) {
  const [open, setOpen] = useState(false);
  const dialog = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    dialog.current?.focus();
    const onKey = (e: globalThis.KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    document.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [open]);

  return (
    <>
      <a href={foundryDownloadUrl} className={className} onClick={() => setOpen(true)}>
        {children}
      </a>
      {open &&
        createPortal(
          <div className="dl-backdrop" onClick={() => setOpen(false)}>
            <div
              className="dl-modal"
              role="dialog"
              aria-modal="true"
              aria-labelledby="dl-title"
              ref={dialog}
              tabIndex={-1}
              onClick={(e) => e.stopPropagation()}
            >
              <button className="dl-close" onClick={() => setOpen(false)} aria-label="Close">
                ×
              </button>
              <h2 id="dl-title">While that downloads…</h2>
              <p>
                Foundry isn’t notarized with Apple yet, so the first launch needs one manual
                approval — takes ten seconds:
              </p>
              <ol className="dl-steps">
                <li>Open the DMG and drag Foundry to Applications.</li>
                <li>Open Foundry — macOS will warn it can’t verify the developer.</li>
                <li>
                  <strong>System Settings → Privacy &amp; Security</strong>, scroll to{" "}
                  <strong>Security</strong>, click <strong>Open Anyway</strong>.
                </li>
                <li>
                  Confirm <strong>Open</strong>, then press <kbd>⌥</kbd>+<kbd>Space</kbd> anywhere.
                </li>
              </ol>
              <button className="foundry-cta dl-ok" onClick={() => setOpen(false)} autoFocus>
                Got it
              </button>
              <a className="dl-restart" href={foundryDownloadUrl}>
                Download didn’t start? Get it again
              </a>
            </div>
          </div>,
          document.body
        )}
    </>
  );
}
