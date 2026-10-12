# Search latency (2026-10-12, post-overhaul)

Driver: `SearchLatencyBenchmarkTests` — in-process, default registry,
90 ms keystroke cadence, first round discarded. Run with:

```sh
FOUNDRY_BENCH_OUT=out.json FOUNDRY_BENCH_ROUNDS=4 \
  swift test --filter SearchLatencyBenchmarkTests
```

Machine: Mac Studio-class Apple Silicon, macOS 27 SDK, release-config
binary under test via the debug test host.

| Metric | n | p50 | p95 | max | Budget (p95) |
| --- | --- | --- | --- | --- | --- |
| `search.immediate` | 132 | 16.92 ms | 22.96 ms | 30.90 ms | ≤ 16 ms |
| `search.complete` | 132 | 17.36 ms | 24.14 ms | 31.80 ms | ≤ 60 ms |

Readings vs the 2026-10-08 baseline (immediate p50/p95 16.8/35.6 ms):
p95 improved 35.6 → 22.96 ms after the Phase 3/4 work (provider-owned
actions, cache invalidation, coordinator debounce). The immediate tier
still misses the 16 ms p95 budget — the callback includes coordinator
dispatch, not just engine scoring, and the workload test runs the full
provider set including the live Spotlight index. The gap is the next
profiling target (`search.immediate` signpost points at provider tail
latency, not scoring).

Wall-clock hotkey→pixel (`drive-signposts.swift --bench`) was not run in
this session — it drives the real panel on the user's display and needs
Accessibility; the in-process numbers plus `panel.firstFrame` signposts
are the repeatable CI-safe signal.

Idle CPU/memory: not re-measured this session; the audit baseline
(open ≈ 7–8 %, closed ≈ 0.3 %, settled ≈ 179 MB) predates the Phase 3
event-driven clipboard store and index changes. Re-measure with
`sample`/`top` before the next release cut.
