# Latency budgets (2026-10-11)

The 1.2 report measured engine-only spans in-process. A launcher lives or
dies on wall-clock, key-to-pixel numbers, so these are the budgets the
pipeline is now instrumented against.

| Metric | Signal | Budget (p95) |
| --- | --- | --- |
| Hotkey → first frame on screen | `panel.hotkeyToFront` span → `panel.firstFrame` mark | ≤ 50 ms |
| Hotkey → content committed | `panel.hotkeyToFront` → `results.committed` | ≤ 80 ms, never a blank/spinner frame when a home snapshot exists |
| Keystroke → results committed (immediate tier) | `search.keyToResults` span → `results.committed` | ≤ 16 ms |
| Keystroke → pixels | keystroke → `results.paintCommitted` | ≤ 32 ms |
| Search, complete tier | `search.complete` span | ≤ 60 ms |
| Idle CPU, panel open / closed | `sample`/`top` | < 1.5% / < 0.5% |

## How to measure

```sh
# In one shell: stream signposts while driving
log stream --predicate 'subsystem == "app.foundry.prototype"' --level debug

# In another: drive the hotkey loop (needs Accessibility for real keys)
swift scripts/drive-signposts.swift 40 --bench

# Reopen-cycle drive without Accessibility (show/hide only)
swift scripts/drive-signposts.swift 30 --reopen build/Foundry.app
```

`panel.firstFrame` fires when the CATransaction that orders the panel in
commits to the render server — the closest readable signal to first paint.
`results.paintCommitted` does the same for the commit carrying new rows.

## Notes

- `hotkey→panelOnScreen` wall time in `--bench` includes CGEvent posting and
  the driver's polling granularity; use it as a smoke check, and the
  signposts for the real numbers.
- The 2026-10-08 `search.immediate` p50/p95 (16.8/35.6 ms) remain valid as
  engine-only figures; they do not include view commit or window-server time.
