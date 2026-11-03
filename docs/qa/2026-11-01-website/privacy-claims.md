# Privacy claims

Every sentence on `/privacy` maps to a row here. Paths are relative to the repo root. Line numbers are from the working tree on 2026-11-01.

Method: searched `Sources/` for `URLSession`, `URLRequest`, `NWConnection`, `NWListener`, `WKWebView`, `https?://`, `URL(string:`, `Process()`, `brew`, `yt-dlp`, `uv`, `NSWorkspace.shared.open`, `SecItem`, `sqlite3`, and for updater, telemetry and crash-reporting names. Also read `Package.swift`, `Supporting/Foundry.entitlements` and the Info.plist template in `scripts/build-app.sh`.

## Sent off the Mac

| # | Claim on the page | Evidence |
| --- | --- | --- |
| 1 | Currency conversion sends the two currency codes to Frankfurter (`api.frankfurter.dev`). The amount is not sent. | `Sources/Foundry/Features/Calculator/CalculatorProvider.swift:131-136` builds the URL with only `base` and `quotes`. `:143` sends it. |
| 2 | It happens when the search text reads as a currency conversion, before you press Return. | `CalculatorProvider.swift:15` runs `convertCurrency` on every query. `:159-165` is the pattern that gates it; `:127` returns early when it does not match. |
| 3 | Weather sends the city name to Open-Meteo, then the coordinates it returns. | `Sources/Foundry/Features/Widgets/WidgetDataServices.swift:9` (geocoding, city name), `:19-20` (forecast, latitude and longitude), `:40` (request). |
| 4 | Stock sends the ticker to Yahoo Finance (`query1.finance.yahoo.com`). | `WidgetDataServices.swift:92` (URL with ticker), `:101` (request). |
| 5 | Weather and Stock do nothing until you enter a city or a ticker. | Defaults are empty: `Sources/Foundry/Features/Widgets/WidgetCatalog.swift:156-160`. `Sources/Foundry/UI/WidgetBoardState.swift:60-63` hides the widget without a value. `:251-256` starts the network task only when one is shown. Weather and Stock are not in the default widget list (`WidgetCatalog.swift:157`). |
| 6 | They refresh every 10 minutes, or every 20 or 30 minutes on Low Power Mode or a hot Mac. | `Sources/Foundry/Features/Widgets/FoundryPollingPolicy.swift:14,22,29`; used at `WidgetBoardState.swift:262`. |
| 7 | Quicklink results fetch the site's own `/favicon.ico`. | `Sources/Foundry/Features/Quicklinks/Quicklinks.swift:198-201` builds `<origin>/favicon.ico`; `:234` attaches it to the result. `Sources/Foundry/UI/CommandIconRepository.swift:65-82` fetches it. `Sources/Foundry/UI/PanelSession.swift:21-23` prefetches for the results about to show. |
| 8 | It is on by default and Settings can turn it off. | Default `true`: `Sources/Foundry/Configuration/ConfigService.swift:31,106`. Toggle labelled "Site icons": `Sources/Foundry/UI/Settings/QuicklinksSettingsPane.swift:23-24`. Check at `Quicklinks.swift:234`. |
| 9 | Foundry keeps fetched icons in a disk cache of up to 32 MB. | `CommandIconRepository.swift:21`. |
| 10 | A pasted YouTube link loads its thumbnail from YouTube (`i.ytimg.com`). | `Sources/Foundry/Features/Media/MediaDownloadProvider.swift:42` and `:104-123`. Rendered by `AsyncImage` at `Sources/Foundry/UI/PanelRowViews.swift:204-205`. |
| 11 | The Downloads list loads each site's icon from DuckDuckGo and sends the site's host name. | `Sources/Foundry/UI/MediaDownloadsView.swift:570-573` (`icons.duckduckgo.com/ip3/<host>.ico`), `:525-526` (use). |
| 12 | Downloading a direct file link fetches it from the address you pasted. | `Sources/Foundry/Features/Media/MediaDownloadService.swift:117-119`. |
| 13 | Downloading any other media link runs yt-dlp, which contacts that site. | `MediaDownloadService.swift:122-127` (YouTube), `:144-149` (other). Hosts that trigger the provider: `MediaDownloadProvider.swift:129-133`. |
| 14 | If yt-dlp is missing, Foundry installs it with Homebrew when you start a download. | `MediaDownloadService.swift:267-274` runs `brew install yt-dlp`. Called from `:124`, `:139`, `:146` with no confirmation step in between. |
| 15 | The hosted Cobalt service is not used. | Only used when `cobaltIsConfigured`: `MediaDownloadService.swift:260-265`, which needs `FOUNDRY_COBALT_AUTHORIZATION` or a non-default `FOUNDRY_COBALT_ENDPOINT` (`:68-72`). Dropped from the page as a user-visible item; it is an environment variable. |
| 16 | Conversion tools install with Homebrew after you approve a setup sheet. | Plan: `Sources/FoundryServices/ConversionService.swift:191-218` (`brew install` commands, disclosure text). Sheet text: `Sources/Foundry/UI/FileConversionView+Actions.swift:276`. Install runs only from `Sources/Foundry/UI/FileConversionState.swift:210-218` (`installToolAndConvert`) and `:240` (`installTool`), both guarded by `dependencySetup`. |
| 17 | Background removal downloads a 223 MB model from Hugging Face after you choose Set Up BEN2. | `Sources/Foundry/Features/Images/BEN2BackgroundRemovalService.swift:75` ("only after explicit Set Up BEN2"), `:77-81` (disclosure), `:245` (download), `:381` (URL `huggingface.co/PramaLLC/BEN2/...`). |
| 18 | Setup also runs uv, which fetches Python 3.13 and three pinned packages. | `BEN2BackgroundRemovalService.swift:117-143` (`uv venv --python 3.13`, `uv pip install` with hashes). The page does not name the hosts, because the code does not fix them. |
| 19 | The image itself is processed on the Mac. | The worker imports only `argparse`, `hashlib`, `os`, `numpy`, `onnxruntime`, `PIL`: `Sources/Foundry/Resources/BackgroundRemoval/background_removal_worker.py:1-7`. It is run locally at `BEN2BackgroundRemovalService.swift:177-178`. |
| 20 | AI with Apple Intelligence runs on the device. It is the default. | Default profile: `Sources/Foundry/Configuration/ConfigService.swift:260-261`. Profile: `Sources/Foundry/Features/AI/AIProviderProfiles.swift:103-113`. `requiresNetwork` is false only for it: `:27-29`. |
| 21 | Other AI providers are off until you add one. Ollama is off by default and points at `127.0.0.1`. | `AIProviderProfiles.swift:115-127` (`enabled: false`, endpoint `http://127.0.0.1:11434`). Other providers exist only as presets you add: `:152-212`. |
| 22 | With a provider you add, Foundry sends your prompt, the earlier messages in that chat, and the model's tool results to the provider's endpoint, with your key. | Request body: `Sources/Foundry/Features/AI/AIProviderTransports.swift:12-18`. Messages are the system line, the context and the prompt: `Sources/Foundry/Features/AI/AIAgentRuntime.swift:122-128`. Routing: `Sources/Foundry/Features/AI/AITransports.swift:15-45`. Endpoint is the profile's endpoint only: `AIProviderProfiles.swift:152-212`. |
| 23 | Hosts for the built-in presets: OpenAI, Anthropic, Google, OpenRouter, Groq, Mistral, Together, xAI, DeepSeek, Fireworks, Perplexity, Cerebras, Deep Infra, Hugging Face. | `AIProviderProfiles.swift:153-192`. The page says "the provider you choose" and does not list them. |
| 24 | The AI can look up the current time, frontmost app and computer name, and that result goes to the provider. | Tool: `AIAgentRuntime.swift:332`. Content: `:297-305`. Result is appended to the transcript: `:144-149`. |
| 25 | AI web search sends the search query to Brave Search, then DuckDuckGo if Brave returns nothing, and fetches the top result pages. It runs for every provider, including Apple Intelligence. | Brave `Sources/Foundry/Features/AI/WebSearch.swift:81-90`, DuckDuckGo `:22-27`, result pages `:54-58`. Tool exposed to remote providers: `AIAgentRuntime.swift:334-336,346-349`. Apple path: `:477,540-565`. No setting disables it: no config key matches `webSearch`. |
| 26 | The query is what the model writes, or your whole request when it uses a keyword such as "latest", "news", "price" or "weather". | `AIAgentRuntime.swift:313-317` (keywords), `:516` (request used as the query), `:541` (fallback to `[request]`). |
| 27 | Signing in with a ChatGPT subscription talks to OpenAI (`auth.openai.com`, `chatgpt.com`). It is off until you set it up. | `Sources/Foundry/Features/AI/CodexOAuth.swift:358-360`. Disabled by default: `AIProviderProfiles.swift:208-211` (`defaultEnabled: false`). |
| 28 | While you sign in, Foundry listens on a local port for the callback. | `CodexOAuth.swift:234` (`NWListener`), `:500` (`http://localhost:<port>/auth/callback`), `:327` (only `localhost` and `127.0.0.1` hosts accepted). |
| 29 | API keys and sign-in tokens are stored in the macOS Keychain, not in the config file. | `AIProviderProfiles.swift:302-306` (service `com.hridya.foundry.ai`), `:321-326` (`SecItemAdd`, `AfterFirstUnlockThisDeviceOnly`), `:343-344`. `CodexOAuth.swift:483,552` use the same store. `AIProviderProfile` has no key field (`AIProviderProfiles.swift:64-74`) and `Sources/Foundry/Configuration/` contains no `apiKey`. |
| 30 | Typing `ai`, `ask`, `plan` or `ollama` followed by text in the search box starts your AI request without pressing Return, on Apple Intelligence or your Ollama host. | `Sources/Foundry/Features/AI/AIProvider.swift:19-21,31-34,73-82`; registered at `Sources/Foundry/Commands/Search/CommandRegistry.swift:37`. Backends are only Apple or Ollama here. |

## Stays on the Mac

| # | Claim on the page | Evidence |
| --- | --- | --- |
| 31 | Clipboard history is a SQLite file at `~/.local/share/foundry/clipboard.sqlite`, with images in `clipboard-images/` beside it. | `Sources/Foundry/Features/Clipboard/ClipboardHistoryStore.swift:7-9,19-20`. |
| 32 | It is on by default and keeps up to 1,000 items, 1 GB and 90 days. You can change all three. | `Sources/Foundry/Configuration/ConfigService.swift:168-176,178-182`. Age limit applied at `Sources/Foundry/UI/ClipboardHistoryState.swift:176-187`. |
| 33 | It skips items that apps mark as concealed, transient, auto-generated or password, and apps you exclude. | `Sources/Foundry/Features/Clipboard/PasteboardClient.swift:11-18`; `ClipboardHistoryState.swift:216-225`. |
| 34 | Clipboard history has no code path that sends it anywhere. | The only network calls in `Sources/` are rows 1 to 30. None reads the clipboard store. The AI context is the chat's own messages (`AIAgentRuntime.swift:122`). |
| 35 | Settings are at `~/.config/foundry/config.json`. Snippets are at `~/.config/foundry/snippets.json`. AI chats are at `~/.config/foundry/ai-chats.json`. | `ConfigService.swift:414-417`; `Sources/Foundry/Features/Snippets/LibraryPersistence.swift:57`; `Sources/Foundry/Features/AI/AIChatStore.swift:112`. |
| 36 | Usage ranking is `~/.local/share/foundry/usage.json`. It keeps open counts, last-open times, and a hash of what you typed. It does not keep the text. | `Sources/Foundry/Commands/Search/UsageRankingStore.swift:28-31,51-54`; query keys are hashes: `:216-231`, `hash(...)` at `:233`. |
| 37 | Foundry's own diagnostics go to the macOS system log on your Mac and nowhere else. | `Sources/FoundryServices/DiagnosticsService.swift:1-2` (imports `Foundation`, `os` only), `:11-19` (`Logger`), `:25-27,29-43` (signposts). The file has no network or file code. |
| 38 | Local AI checks for Ollama and LM Studio at `127.0.0.1` during setup. | `Sources/Foundry/UI/Onboarding/OnboardingState.swift:396-404`. |

## Absent

| # | Claim on the page | Evidence |
| --- | --- | --- |
| 39 | No third-party code in the app. | `Package.swift` has no `.package(` entry (`grep -n "\.package(" Package.swift` returns nothing). Targets depend only on `FoundryDomain` and `FoundryServices`. |
| 40 | No analytics or crash reporting. | `grep -rniE "sentry\|crashlytics\|bugsnag\|posthog\|mixpanel\|amplitude\|firebase\|MetricKit\|MXMetric\|CrashReporter\|telemetry\|analytics" Sources Supporting Package.swift` returns only SF Symbol names (`sparkles`) and no code. |
| 41 | No automatic update check. | `grep -rniE "sparkle\|SUFeed\|appcast\|checkForUpdate" Sources Supporting Package.swift scripts/build-app.sh` returns nothing. The Info.plist template (`scripts/build-app.sh:139-`) has no feed key. |
| 42 | No Foundry account, and no server run by Foundry. | Every host in `Sources/` is a third party (`grep -rhoE "https?://[A-Za-z0-9.-]+" Sources`): the services in rows 1 to 28 plus quicklink search targets. No Foundry domain appears. |
| 43 | The only special entitlement is the camera. | `Supporting/Foundry.entitlements:5-6`. |

## Dropped

| Claim | Why |
| --- | --- |
| "Snippet expansion keeps no record of what you type." | Not checked line by line. Left off. |
| "Apple Translation runs offline." | The Translation framework may download language packs from Apple. The code does not show which. Left off. |
| "Browser history and tabs never leave the Mac." | `BrowserProvider` reads local files and only opens URLs. True of the code, but the page says "no code path sends it" only for the clipboard, where it matters most. Left off to keep the page short. |
| "Your IP address is hidden." | Not true. Every request in rows 1 to 28 exposes it to that service. The page says so. |
| Hosted Cobalt API as a data flow. | Unused unless configured by environment variable (row 15). |

## Surprises found in the app (report only, not changed)

1. AI web search has no off switch and also runs when the provider is on-device Apple Intelligence (row 25). The user's search terms reach Brave Search.
2. Typing `ai `, `ask `, `plan ` or `ollama ` plus text starts the AI request while typing, not on Return (row 30). With Apple Intelligence that can trigger a web search per pause in typing.
3. Currency conversion calls the network while typing, before Return (row 2).
4. A YouTube link in the search box loads its thumbnail from YouTube before you choose Download (row 10).
5. `brew install yt-dlp` runs on the first non-direct download with no confirmation (row 14), while conversion tools and BEN2 both ask first (rows 16, 17).
6. The search subtitle for direct links says "Direct link · stays on this Mac" (`MediaDownloadProvider.swift:38`). The file is still fetched from the remote host.
7. Quicklink site icons are on by default, so first launch requests `/favicon.ico` from Google, GitHub, YouTube and the other default quicklinks (rows 7, 8).
