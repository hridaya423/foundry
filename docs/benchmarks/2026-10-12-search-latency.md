# Search latency (2026-10-12, post-overhaul)

Driver: `SearchLatencyBenchmarkTests` — in-process, default registry,
90 ms keystroke cadence, first round discarded. Run with:

```sh
FOUNDRY_BENCH_OUT=out.json FOUNDRY_BENCH_ROUNDS=8 \
  swift test --filter SearchLatencyBenchmarkTests
```

`FOUNDRY_BENCH_PROFILE=1` additionally reports `phase.wall` (the registry's
immediate-phase wall clock, no coordinator dispatch) and per-provider
timings.

Machine: Mac Studio-class Apple Silicon, macOS 27 SDK, release-config
binary under test via the debug test host.

## Final numbers (commit `6cb007c`, 8 rounds, n=264)

| Metric | p50 | p95 | max | Budget (p95) |
| --- | --- | --- | --- | --- |
| `search.immediate` | 4.65 ms | **12.11 ms** | 17.73 ms | ≤ 16 ms ✓ |
| `search.complete` | 5.06 ms | 12.71 ms | 18.70 ms | ≤ 60 ms ✓ |
| `phase.wall` (profile pass) | 3.85 ms | 10.05 ms | 12.29 ms | — |

Provider tail after the optimization pass (p95, profile mode):
`foundry.apps` 5.41 ms (was ~15+), `foundry.system` 5.12 ms,
`foundry.windows` 2.94 ms, `foundry.builtin` 2.52 ms; all other providers
under 2 ms.

The keystroke→callback figure includes main-actor scheduling, so ambient
machine load moves the tail: under sustained load-avg ≈ 11 the same code
measured p95 28–64 ms while `phase.wall` stayed ≈ 10 ms — scheduling
contention, not provider cost. The 12.11 ms run was taken at load-avg ≈ 5–8.

## What changed since the 22.96 ms run

- `NSWorkspace.runningApplications` no longer sits on the keystroke path —
  `RunningAppsSnapshot` serves the last good set and refreshes in the
  background (was an 8–16 ms spike on TTL expiry).
- Every catalog provider precomputes normalized title/subtitle/aliases +
  a character mask once; `probableMatch` rejects impossible candidates in
  one instruction before any DP runs. `SearchScoring` splits to
  `Substring`s (no per-candidate `String` copies).
- The app catalog scans in up-to-4 cooperative-pool chunks, reassembled in
  catalog order (deterministic).
- Deferred-phase providers run at `.utility` priority, so stale
  still-running work from a cancelled search can't preempt the next
  keystroke's immediate phase. The coordinator releases its in-flight flag
  when the immediate phase drains and bounds coalescing to a single
  16 ms window from the search start.

vs the 2026-10-08 baseline: immediate p95 35.6 → **12.11 ms** (3×).

## Idle CPU / clipboard memory (bench instance `com.hridya.foundry.bench`)

| Measurement | Result | Method |
| --- | --- | --- |
| Idle CPU, panel closed | **0.0 % across 5×5 s `top` samples** | second instance, adhoc-resigned bundle |
| Idle RSS, panel closed | 292 MB | `top` `mem` column |
| Clipboard, 1,000 entries | **+1.34 MB RSS**, 383 KB SQLite on disk | `ClipboardMemoryBenchmarkTests` (env-gated) |

Idle CPU with the panel open still needs a live-GUI sample (reopen event
shows the panel); the only periodic work it enables is the clipboard
0.7 s `Timer` (tolerance 0.2, back-off to 5 s after 60 s idle) — the
always-on pasteboard poll was removed in the overhaul.

Wall-clock hotkey→pixel (`drive-signposts.swift --bench`) was not run in
this session — it drives the real panel on the user's display and needs
Accessibility; the in-process numbers plus `panel.firstFrame` signposts
are the repeatable CI-safe signal.
