# Foundry product-polish coverage

Status: in progress. This log records what was actually inspected or tested; an unchecked integration is not implied to work.

## Audit environment

- Build: local staged `build/Foundry.app`, version 1.0.0.
- macOS: 26.5.1 (25F80), Apple M4 Pro, built-in Liquid Retina XDR display at 3456 × 2234.
- Appearance: Dark (restored after a controlled Light appearance pass).
- Accessibility: Reduce Transparency and Reduce Motion were not enabled during the initial capture. Their settings need explicit verification in Package 1.
- Evidence: Home, search, Settings, Home widget configuration, Notes launch, Snippets populated and no-match states, and Downloads empty, invalid, mixed-input, and failed-populated states were inspected through computer use. Escape was verified from Settings and Downloads. A rebuilt Light-mode pass typed into the launcher search field confirmed the query remains readable against the light surface; Home, Settings, Downloads, Clipboard, Snippets, Developer Tools, and File Shelf were also readable, then Dark was restored. The current staged release exposes the Downloads composer, destination folder, Change control, capability menu, recovery actions, and empty-state folder action. The hosted Cobalt endpoint was checked directly and returned `error.api.auth.jwt.missing`; it is now reported unavailable by default and supported non-YouTube links fall back to yt-dlp.

## Draft disposition

| File | Disposition | Reason |
| --- | --- | --- |
| `Sources/Foundry/Application/AppDelegate.swift` | Retain | Reopen now calls the existing panel-show path and was exercised successfully. |
| `Sources/Foundry/Shell/ShellController.swift` | Retain | Exposes the existing panel-show method without adding a new lifecycle path. |
| `Sources/Foundry/Features/Media/MediaDownloadModels.swift` | Revise | Saved URLs are the right data boundary, but manager completion must prove they cannot be overwritten by later progress. |
| `Sources/Foundry/Features/Media/MediaDownloadService.swift` | Revise | Per-download destination snapshot and structured outputs are correct; add regression coverage and preserve injected test destinations. |
| `Sources/Foundry/UI/MediaDownloadsView.swift` | Revise | The reading order is improved, but completion needs real populated-state, keyboard, missing-file, and accessibility review. |

## Feature coverage

| Surface | Entry | Primary action | Recovery state | Audit status |
| --- | --- | --- | --- | --- |
| Launcher search | Global hotkey | Open selected result | Empty results, cancellation | Home/search, Return navigation, and Escape from feature modes inspected; broader keyboard pass pending |
| Actions | Command-K | Execute selected action | Escape returns to result | Pending |
| Settings | Settings command or Command-comma | Persist setting | Save failure message | General, Appearance, Home widget settings, Escape navigation, and the controlled Light appearance pass inspected live; persistence and save-failure paths remain unverified |
| Downloads | Downloads command or media URL | Download and reveal file | Cancel, retry, missing output | Empty, invalid, mixed-input, and populated failure states inspected; hosted Cobalt authorization is surfaced honestly and yt-dlp handles the default multi-site path; completed-file reveal, cancel, and missing-output paths remain unverified |
| Clipboard history | Clipboard History command | Copy or direct paste item | Pause, empty, no matches | Targeted regression tests passed; populated dark-mode pass confirmed card actions and Pause. Text previews and normal saving were restored at the user's request. |
| Snippets | Snippets command | Save, copy, or insert snippet | No matches, duplicate keywords, persistence failure | Populated and no-match states inspected live; Insert uses staged direct paste and persistence is covered by regression tests; end-to-end target paste remains unverified |
| File Shelf | File Shelf command or drag/drop | Stage and act on files | Missing file, empty shelf | Empty state inspected live; state and background-removal regression coverage passed |
| File conversion | Convert File command or File Shelf | Convert and reveal output | Unsupported type, tool setup, cancel | 11 conversion and 6 artifact-safety tests passed; live pass blocked by desktop automation |
| Background removal | File Shelf image action | Remove background | Model setup, cancel, partial failure | 15 tests passed; live pass blocked by desktop automation |
| Translator | Translate command | Translate and copy | Unavailable resource, stale result | 12 tests passed; live pass blocked by desktop automation |
| Developer tools | Developer Tools command | Transform and copy | Invalid input | Base64 and invalid timestamp regressions passed; visual pass pending |
| Calculator | Search expression | Copy calculation | Invalid expression, currency failure | Pending |
| Quick AI | Tab from search or Ask AI | Submit and persist response | Configuration, stop, retry | AI and chat-persistence suites passed; configured live provider unavailable |
| Agents | Agents command or Home card | Open agent session | Empty, stale, disconnected session | Agent monitor and integration suites passed; live integration pass blocked by desktop automation |
| Browser | Browser query | Open matching browser record | Browser unavailable, no matches | Browser-provider suite passed; live browser-data pass blocked by desktop automation |
| Apple Notes | Notes query | Open or copy note action | Permission or service failure | Notes application opened from the live result; note search and copy/open actions remain unverified |
| Camera | Camera command | Start and stop preview | Permission denied, no device | Camera suite passed; no permission prompt was requested for QA |
| Widgets | Home and Settings | View/manage widget | Loading, stale, offline data | Home widget configuration inspected live; loading, stale, offline, and restart persistence paths remain unverified |
| Emoji and symbols | Emoji command | Copy selected symbol | No matches, keyboard navigation | Full automated suite passed; live pass blocked by desktop automation |
| Window management | Window layout/system commands | Apply layout | Permission or display limitation | Window and layout suites passed; live action withheld to avoid moving user windows |
| System commands | System command search | Run a safe utility | Action failure | System command suite passed; destructive commands excluded from ordinary QA |
