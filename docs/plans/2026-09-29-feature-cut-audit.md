# Feature-cut audit (P5)

Per the plan: every surface gets a value/cost assessment and a recommendation.
Nothing is removed without approval. "Cost" covers maintenance surface,
search-result noise, permissions required, and bundle/memory weight.

| Surface | Value | Cost | Recommendation |
| --- | --- | --- | --- |
| App search + running apps | Core launcher function | Low — cached catalog, 2 s shared snapshot | Keep |
| Calculator (math, units, currency, equations) | High-frequency utility | Low — parser + 5-min rate cache | Keep |
| Clipboard history | Signature feature vs Spotlight | Medium — SQLite store, image files, pasteboard polling | Keep |
| Snippets + expansion | High-value, differentiator | Medium — accessibility event tap when enabled | Keep |
| Quicklinks + import | Raycast parity | Low | Keep |
| File search (`f `, `kind:`, recents) | Spotlight parity | Medium — `mdfind` streaming, disabled-Spotlight path handled | Keep |
| Quick AI | Differentiator | High — provider transports, streaming, threads | Keep |
| AI chat threads/search | Part of Quick AI | Medium | Keep (fold under Quick AI) |
| Script commands | Power-user parity | Medium — sandbox execution, output modes | Keep |
| Apple Shortcuts | Parity | Medium — `shortcuts` CLI calls are slow (~10 s cold) | Keep — cached off keystroke path |
| Media downloads (yt-dlp) | Real utility | High — external binary dependency, network policy | Keep — gated, error-explained |
| Camera preview | Novelty | Low code, but low value and a permission prompt | Hide by default; command stays, opt-in via providerEnabled |
| File Shelf + conversion | Useful, Raycast lacks it | Medium — drag/drop, ffmpeg/ImageMagick deps | Keep — deps fail with setup copy |
| Developer tools | Utility belt | Low — pure compute | Keep |
| Emoji picker | High-frequency | Low — static TSV | Keep |
| Translator | Utility | Medium — macOS Translation availability varies | Keep — states handled |
| Browser search/tabs | Parity | Medium — per-browser reads, Firefox connector fragile | Keep; Firefox stays opt-in (done P1) |
| Apple Notes | Parity | Medium — AppleScript latency | Keep — cached off keystroke path |
| Window management (34 placements) | Rectangle-grade parity | Low — pure AX calls | Keep |
| System commands | Utility | Low | Keep |
| Rebuild App | Dev tool | Zero user value in release | Debug builds only (done P1) |
| Widgets (14 legacy kinds) | Dashboard strip | — | Already resolved to 4 core kinds |
| Agent monitor shelf | Niche — only for agent users | Medium — socket polling | Keep — idle-disabled when no sessions |
| Menubar panel | Premium surface | Low | Keep |

## Resolved cuts already applied
- Rebuild App: debug-only.
- Firefox connector: opt-in.
- 14 legacy widget kinds: collapsed to the four core widgets.

## Proposed new cuts
- Camera preview hidden by default (command remains; enable via command settings).
  **Declined by user 2026-09-29** — Camera stays visible in root search.

## Nothing else recommended for removal
Every other surface either has parity value vs Raycast/TinyCast, is a stated
differentiator (Clipboard, Snippets, File Shelf, Quick AI), or is already
cheap and off the hot path.
