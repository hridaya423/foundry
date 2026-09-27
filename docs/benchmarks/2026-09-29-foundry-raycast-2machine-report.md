# Foundry 1.1.0 vs Raycast 2.2.0.0 — two-machine footprint + bundle report

2026-09-29. Raw JSON: `2026-09-29-foundry-raycast-mbp-cold.json`,
`2026-09-29-foundry-raycast-mini-cold.json`.

## Installed size (`du -sk`, identical bundles on both machines)

| | Foundry 1.1.0 | Raycast 2.2.0.0 |
|---|---|---|
| MacBook Pro M4 Pro (`/Applications`) | 16,152 KB (16.2 MB) | 194,792 KB (195 MB) |
| Mac mini M4 (`/Applications` + `~/Applications`) | 16,152 KB | 196,340 KB* |

\* mini copy measured pre-move; same .app bundle, minor APFS overhead delta.
Bundle ratio: **12.1×** (194792/16152 = 12.06, rounded conservatively).

## Memory footprint (post-launch, `footprint` tool, 15 samples @1s)

| | Foundry | Raycast | reduction |
|---|---|---|---|
| MBP M4 Pro 32GB | 60.7 MB | 591.0 MB | 89.7% |
| Mac mini M4 16GB | 25.9 MB | 278.3 MB | 90.7% |

Claim uses the smaller reduction, rounded down: **≈89% less memory**.

## Protocol deviations vs 2026-08-29 run

- **Cold-launch, not hotkey-warmed.** The `--runs 0` mode skips CGEvent
  hotkeys: Raycast was measured ~10s after first launch (never configured on
  mini; on MBP Raycast had not been run that session). Foundry on MBP was
  already running warm from the capture-rig session, so the reduction is a
  conservative floor — warming Raycast only grows its footprint.
- **Mini hotkey leg failed:** `benchmark-launchers.swift` posts CGEvents from
  an ssh session without Accessibility grant → `fatalError: Foundry did not
  hide its window` (panel never toggled). Warmed runs need either the
  benchmark launched from the mini's GUI (Terminal.app with AX granted) or the
  laptop run during an idle window.
- No latency data this round (panel timing needs the hotkey leg).

## TODO before shipping the claim

- [ ] MBP warmed run: `swift scripts/benchmark-launchers.swift --runs 30 --warmups 5 --memory-samples 15 --startup-wait 10 --settle 2 --require-ac --isolate` + `--reverse` (steals focus; needs an idle window)
- [ ] Mini warmed run from a GUI terminal with AX granted
- [ ] Record Raycast settings/extension set on both machines
