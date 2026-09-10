# Foundry and Raycast 2.1.2.0 benchmark report

## Verdict

The AC rerun completed on one Apple M4 Pro. Each launcher ran alone, and the Raycast samples included its main process, backend, two in-bundle XPC services, and three WebKit XPC services that appeared after Raycast launch. The result supports a one-machine comparison, not a universal or final film claim.

- Foundry's installed bundle was 13,892 KB versus Raycast's 192,956 KB, a 13.89x size ratio.
- Foundry's median warmed `footprint` value was 162.3 MB with Foundry first and 164.5 MB with Raycast first. Raycast measured 531.6 MB and 520.7 MB in those orders, so Foundry was 69.5% and 68.4% lower. The midpoint of the reductions was 68.9%.
- Both runs started and ended on `AC Power`. A second representative Mac and a record of Raycast's settings, enabled extensions, and indexing state remain before public comparison or film approval.

Do not claim that Foundry opens faster. The panel detector records Core Graphics window registration, not the first composited frame. The timing distributions still contain samples below one display frame, so they are diagnostic only.

## Test system

| Field | Value |
| --- | --- |
| Hardware | MacBook Pro `Mac16,7` |
| Processor | Apple M4 Pro, 14 cores |
| Memory | 48 GB |
| macOS | 26.5.1, build `25F80` |
| Power | AC Power |
| Foundry | 1.0 |
| Raycast | 2.1.2.0 |
| Date | 2026-08-29 |

Raycast v2 was installed at `/Applications/Raycast.app` and retained the configured `Command-47` global shortcut. The official technical description is [A Technical Deep Dive Into the New Raycast](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast), and the release is recorded in the [Raycast 2.0 changelog](https://www.raycast.com/changelog/macos-beta/2-0).

## Method

Each order used:

- 5 warmup panel cycles
- 30 measured panel cycles
- A 2-second settle after the panel sweep
- 15 one-second memory samples after the settle
- The panel hidden during memory collection
- `du -sk` for installed bundle disk usage
- `footprint` for the selected process set and `ps` RSS as a secondary diagnostic

The runner used `--require-ac` and `--isolate`. It stopped each launcher before measuring the next one. The forward run measured Foundry before Raycast. The reverse run measured Raycast before Foundry.

The memory sampler reads `pid`, `ppid`, RSS, elapsed time, and command from `ps`. It selects bundle processes, follows their descendants, and, only for Raycast, adds WebKit XPC processes that were absent from the pre-launch process baseline. The selected process set must remain stable for 100 ms, and each selected process must be at least 5 seconds old. This captures Raycast's `Raycast Backend` and the detached WebKit services observed during the Raycast run. Because launchd manages those services outside the app's process tree, the records identify them by their new PID during the Raycast run rather than by an OS-reported ownership link. The raw records include every selected PID, its command, ownership, age, RSS, and the memory sample timestamp.

Run the same protocol with:

```sh
swift scripts/benchmark-launchers.swift --runs 30 --warmups 5 --memory-samples 15 --startup-wait 10 --settle 2 --memory-interval 1 --require-ac --isolate
swift scripts/benchmark-launchers.swift --reverse --runs 30 --warmups 5 --memory-samples 15 --startup-wait 10 --settle 2 --memory-interval 1 --require-ac --isolate
```

The primary memory metric is the grouped `Summary Footprint` emitted by macOS `footprint` for the selected process IDs. RSS remains in the raw records as a secondary diagnostic because summing process RSS counts shared pages more than once. The benchmark does not compare the vendor's rough v2 memory estimate with these results because the workload and metric are different.

## Results

### Installed bundle

| Product | Version | Disk usage | Relative size |
| --- | --- | ---: | ---: |
| Foundry | 1.0 | 13,892 KB | 1.00x |
| Raycast | 2.1.2.0 | 192,956 KB | 13.89x |

### Post-sweep warmed footprint

| Order | Foundry p50 | Foundry p95 | Raycast p50 | Raycast p95 | Foundry reduction at p50 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Foundry first | 162.3 MB | 163.1 MB | 531.6 MB | 660.0 MB | 69.5% |
| Raycast first | 164.5 MB | 165.2 MB | 520.7 MB | 651.2 MB | 68.4% |

The midpoint of the two p50 medians is 163.4 MB for Foundry and 526.1 MB for Raycast. The midpoint of the two reductions is 68.9%. This midpoint is a summary of two runs, not a third measurement. The two order medians differed by 2.2 MB for Foundry and 10.9 MB for Raycast.

RSS p50 was 239.4 MB and 241.8 MB for Foundry, versus 1,185.2 MB and 1,172.1 MB for Raycast. Keep this secondary diagnostic separate from the primary footprint claim.

### Window registration timing

| Order | Foundry p50 | Foundry p95 | Raycast p50 | Raycast p95 |
| --- | ---: | ---: | ---: | ---: |
| Foundry first | 29.7 ms | 37.8 ms | 16.2 ms | 21.3 ms |
| Raycast first | 28.1 ms | 37.0 ms | 21.3 ms | 29.0 ms |

These values are diagnostic only. The ordering changes the result, and Core Graphics can list a window before the viewer receives its first composited frame. Use a photodiode, a high-frame-rate external camera, or equivalent first-frame signposts for a viewer-facing latency comparison.

## Claim gate

The AC and process-isolation conditions passed for these two runs. Keep the comparative plates provisional until the remaining conditions hold:

- The result reproduces on a second representative Mac.
- The exact Raycast version, settings, enabled extensions, and indexing state are recorded.
- The detached WebKit process association is validated or disclosed as a run-level attribution.
- The same workflow and dataset are used for every product.
- The launch page publishes both raw JSON files and this methodology.
- Legal review approves naming Raycast.

If the v2 rerun or the second machine fails the gate, use the architecture plate: **"Built to answer fast: staged search, cancellation, and bounded work."**

## Raw data

- `docs/benchmarks/2026-08-29-foundry-raycast-v2-forward.json`
- `docs/benchmarks/2026-08-29-foundry-raycast-v2-reverse.json`
