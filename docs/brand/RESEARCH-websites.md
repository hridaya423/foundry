# Research: product site craft, trust, and launcher positioning

Date: 2026-11-01. Researcher: Sonnet 5.5 (`claude-sonnet-5-5`). No code was changed.

## Method and limits

- Read: `app/page.tsx`, `foundry/foundry.css`, `foundry/story/story.tsx`, `foundry/hero-content.tsx`, `methodology/page.tsx`, `layout.tsx`, `site.ts`, `site-chrome.tsx`, `download-gate.tsx`, `not-found.tsx`, plus `README.md`, `docs/distribution.md`, `docs/HANDOFF.md`, `docs/benchmarks/*` in the repo.
- Fetched live pages by static fetch and `curl` of the `<head>`. This shows copy, structure, links and meta tags. It does **not** show scroll choreography, easing, type scale, cursor behaviour or sound. Where a section below says "not observable", that is why. I did not invent those details.
- `linear.app` and `ghostty.org` return client-rendered shells to a static fetch (Linear's body is the literal text "Loading…"). Linear's copy and changelog layout are therefore unverified.
- `zed.dev`, `raycast.com` and `resend.com` were partly blocked in the fetch tool; I used `curl` for those. Resend's page was only available as a markdown rendering.
- I found no sourced evidence of sound, custom cursors, state-changing favicons, or easter eggs on the reference sites. Section 2 says so rather than guessing.
- Aggregator and review sites (alternativeto, pikvue and similar) are marked "third-party, unverified".

## 0. What Foundry's site is today (facts from the repo)

| Area | Fact | Source |
|---|---|---|
| Ground and accent | `--f-bg #0f0d0c`, text `#eee7dd`, muted `#bdb4aa`, accent `#fa6428`, line `#484039` | `app/foundry/foundry.css:5-10` |
| Hero | "The app you never open. Opens everything." with a live launcher, Download CTA, hint "⌘ Space from anywhere" | `foundry/hero-content.tsx` |
| Sections | hero, file shelf, clipboard belt, tools, memory (81%), download, then `/methodology` | `foundry/story/story.tsx` |
| Reduced motion | CSS drops the sticky stage and all transitions; a stills path (`shelf-still`, `animated=false`) exists | `foundry.css:326-340`, `story.tsx:155-172` |
| Download | Modal "Before you open it": "This build isn't notarized"; steps use **⌥+Space** | `foundry/download-gate.tsx` |
| Footer | Wordmark, GitHub, "Release notes" (links to GitHub releases/latest). No licence, privacy, brand or changelog page | `foundry/site-chrome.tsx` |
| 404 | Tile-built "404", "This page is not here." | `app/not-found.tsx` |
| Head | `title`, `description`, `og`, `twitter: summary_large_image`, `opengraph-image.png`, `favicon.ico`. No `icons` set, no `themeColor`, no `colorScheme` | `app/layout.tsx` |
| Claims | "81% lower warmed memory use" vs Raycast 2.5.3, labelled Provisional, one M4 Pro, two order-swapped runs, worst leg; full method page | `memory.tsx`, `methodology/page.tsx` |

Inconsistencies found in the repo:

1. **Hotkey.** Hero and closing say ⌘ Space. The download modal says ⌥+Space. README says ⌘Space is the default and Raycast or Alfred get moved to ⌥Space (`README.md`).
2. **Notarization.** Modal says the build is not notarized. `docs/distribution.md` says the release workflow notarizes when secrets are set. `docs/HANDOFF.md:11` says signing and notarization are out of scope by the user's choice. The site must say whichever is true for the file that `releases/latest/download/Foundry.dmg` serves.
3. **Version.** `download.tsx` and the JSON-LD say v1.1. README links `docs/release-notes/1.2.0.md`.
4. **Memory claim vs your own Tinycast run.** `docs/benchmarks/2026-09-29-foundry-1.1-tinycast-0.11.3-mbp-report.md` records Tinycast at about 40.5 MB warmed against Foundry's 60.5 to 120.0 MB, and Foundry at 17.5 to 19.1 ms hotkey-to-panel against Tinycast's 64.7 to 66.7 ms. The report itself says "should not be spun into a memory claim". The site is safe on "vs Raycast". It must not imply Foundry is the lightest native launcher.

---

## 1. The sites, and why they work

Format per site: hero, product proof, proof of claims, download pattern, notable detail. "Not observable" means a static fetch cannot show it.

### Raycast (the incumbent) — https://www.raycast.com
- **Hero:** "Your shortcut to everything." Subhead "A collection of powerful productivity tools all within an extendable launcher. Fast, ergonomic and reliable." No download button in the hero; the closing block says "Take the short way. Download and use Raycast for free." (fetch of https://www.raycast.com)
- **Shows the product:** An on-screen keyboard graphic under "It's not about saving time. It's about feeling like you're never wasting it." Four one-word claims: Fast ("Think in milliseconds."), Ergonomic ("Keyboard First."), Personal, Reliable ("99.8% crash-free rate.").
- **Proof:** Named testimonials (about 30), 37k Slack members, 90k X followers, extension cards with real third-party icons. The only hard product number is 99.8% crash-free. "Think in milliseconds" has no number behind it.
- **Footer:** Very large. Includes Changelog, "Raycast vs Alfred", Manifesto, Press Kit, Trust Center, Community Stories. Source: same fetch.
- **Changelog:** Per-version pages with date, one banner image, emoji-labelled New / Improvements / Fixes, bold area names, casual "we" tone, tabs per platform, pagination. No RSS link seen. Latest seen: v2.10, 28 October 2026. https://www.raycast.com/changelog
- **Architecture, in their own words:** "Raycast v1 was, at its core, a native macOS app built with Swift on top of AppKit", and v2 "doubled down" on web technologies with a stack of TypeScript, Swift, C#, Rust, Node and React. https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast (via curl). This supports a factual, non-hostile "no web view in the launcher" claim. It does **not** support calling Raycast "Electron"; Raycast does not say that and Foundry's own methodology avoids it.
- **Take:** Great at breadth and community proof. Weak at proving speed with a number. That is Foundry's opening.

### Linear — https://linear.app
- **Verified:** `theme-color #08090a`, dynamic OG image endpoint `linear.app/api/og/main?title=Linear&v=4`, SVG favicon with version query. Source: `curl` of the head.
- **Not verified:** Hero copy, scroll choreography, changelog layout. The static fetch returned "Loading…". A secondary source says entries have a headline, a short paragraph and an image or video, with dates and no version numbers (https://frill.co/blog/changelog-format, third-party, unverified).
- **Take:** A near-black ground (#08090a) is the same family as Foundry's #0f0d0c. Dynamic OG per page is checkable and cheap.

### Zed — https://zed.dev
- **Hero:** "Your last next editor". Subhead "a minimal code editor crafted for speed and collaboration with humans and AI". Two CTAs: "Download now" and "Clone source", each with a single-letter keyboard hint (D, C). "Available for macOS, Linux, and Windows". Three blurbs: Fast / Agentic / Collaborative. (fetch of https://zed.dev)
- **Proof:** Qualitative. "Written from scratch in Rust to efficiently leverage multiple CPU cores and your GPU." No benchmark numbers on the home page. Developer quotes ("My god it is so fast").
- **Open source framing:** A first-class CTA, "Clone source", beside Download. Footer links CLA, GitHub, Discussions.
- **Brand page:** https://zed.dev/brand states names and capitalisation rules, three allowed logo colours (hex given), copy-SVG buttons. Footer has Press, Brand, Releases, Roadmap, Compare, Status.
- **Releases:** "Keep up with the weekly Zed releases", Stable and Preview channels, per-platform entries. https://zed.dev/releases
- **Take:** Keyboard hints on buttons and a brand page are small, copyable moves.

### Cursor — https://cursor.com
- **Hero:** One line, no subhead. "Download for macOS" first, "Get started" second, "Request a demo" third. Interactive product demos sit on a solid brand background. Footer language selector. (fetch of https://cursor.com)
- **Meta:** Light and dark favicons selected by `prefers-color-scheme`, `theme-color` per scheme (`curl` head).
- **Take:** The download button names the OS. Foundry's says only "Download".

### Things — https://culturedcode.com/things/
- **Hero:** The name as H1, "award-winning personal task manager", one action: "Watch Introduction Video". Sections: "Simply Powerful", "Get Things, Get Done", "What People Are Saying", "Read All About It".
- **Proof:** Two Apple Design Awards, named press (Wirecutter, WIRED, MacStories).
- **Pricing:** No price in the card; "view in your currency" link; "Download Free Trial" is an alternative to buying.
- **Tone:** Short declarative sentences, second person. Source: fetch of the page.
- **Take:** Restraint. One video, no feature grid in the hero.

### Arc and Dia — https://arc.net, https://www.diabrowser.com
- **Arc (now a farewell page):** "A farewell to Arc", "Arc is sunsetting on December 22, 2026". Warm, personal copy. Ends with a founder sign-off from Josh and a team block of signatures. Dedicated OG image `arc.net/farewell/og.png`, light-scheme `theme-color #3139FB`. (fetch and `curl` head)
- **Dia:** "More than a browser. A better workday." "Download Dia for free" with the line "Available for macOS and Windows". A privacy section shown as real toggles (Block trackers, Memory, Share content data set On/Off). Footer has both "Release Notes" and "Changelog", plus Trust Center. https://www.diabrowser.com
- **Take:** Human sign-off. A privacy claim shown as UI controls, not a paragraph.

### Screen Studio — https://screen.studio
- **Hero:** "Beautiful screen recordings, in minutes." "Download for Mac" plus "Email me a link" ("Get a link you can open once back on your Mac"). Small print "macOS 13.1 or later recommended".
- **Proof:** Specific numbers: "6.5× upscale", "over 5,000 macOS screenshots", "Projects up to 20 GB", autosave "every two seconds". Pricing is a single plan with the line "Every Screen Studio feature is available in every plan."
- **Footer:** "Some features depend on your Mac and your version of macOS." and the individual's name in the copyright. Source: fetch of the page.
- **Take:** Install friction handled with an email-me-a-link path. Honest small print. Real numbers.

### Cap — https://cap.so
- **Hero:** "The open source screen recorder for everyone." Nav has a GitHub button with a live star count (24.2k). Primary "Download free for macOS", text link "Switching from Loom? Import your library." Banner linking a deep-dive post on a rebuild.
- **Open source framing:** "every line of code is on GitHub", self-hosting offered, and paid tiers explained plainly. Footer line: "The open source alternative to Loom."
- **Meta:** Dynamic OG image (`cap.so/api/og?title=…`). Source: fetch and `curl` head.
- **Take:** Open source stated in the H1, with the star count as proof.

### Vercel — https://vercel.com
- **Hero:** One H1, three bullets, "Deploy now" and "Talk to sales". A real command, `vercel deploy --temporary`, appears on the page. A no-login path ("Deploy without logging in").
- **Agent-readable site:** The 404 body is "Page not found … The requested Vercel resource does not exist or is not publicly accessible" plus links to `llms.txt`, docs sitemap and REST API, and it returns a real HTTP 404. The page ends with a brand assets section. Source: `curl` of https://vercel.com/this-page-does-not-exist-xyz, fetch of https://vercel.com.
- **Meta:** `color-scheme: dark light`, per-scheme `theme-color`.

### Family — https://family.co
- **Hero:** "Your favorite crypto wallet." Download on iOS, Watch the Video. Value cards: Easy, Secure, Fast, Powerful, Fun. Footer: Audit Report, Changelog, Press Kit, GitHub. (fetch of https://family.co)
- **Interaction design:** The page text shows static phone mockups labelled Send, Receive, Swap, plus "seamless animations between states". I could not retrieve Benji Taylor's interaction write-up. A newsletter critique describes it as a long post on many interaction details and also criticises one number animation as stopping abruptly (https://studio21design.substack.com/p/august-2024-bitcoin-design-monthly, third-party). Treat the details of Family's motion as unverified.
- **Take:** Audit Report and Press Kit in the footer. Everything else needs a first-hand visit.

### Also checked
- **Superhuman:** Hero is an AI product carousel. No latency number and no keyboard copy in the fetched text, so the "100ms" claim I was asked to look at is not on the current home page. https://superhuman.com
- **Warp:** "trusted by 800k+ devs", a live-labelled block-character figure ("fig. 1 — the factory", "8 × 28 · live"), jump links per section. https://www.warp.dev
- **Craft:** "Start for free. No credit card required." Light and dark favicons by `prefers-color-scheme`. https://www.craft.do
- **Notion Calendar:** Subhead "All of your commitments, now in one place."; footer closes with a McLuhan quote. https://www.notion.com/product/calendar
- **Resend:** `color-scheme: dark`, `theme-color #000000`; serves `.md` versions of pages to agents. https://resend.com

---

## 2. Detail patterns that separate 100% from 80%

Each item says whether it is **verified** on a named site or a **recommendation**.

| Pattern | Evidence | What to do |
|---|---|---|
| **Favicon follows the scheme** | Verified: Zed (`favicon_black_*` vs `favicon_white_*` by media query), Cursor, Craft. https://zed.dev, https://cursor.com, https://www.craft.do | Foundry has only `favicon.ico`. |
| **Favicon that changes state** | No verified example found. | Not worth building. Skip. |
| **`theme-color` and `color-scheme`** | Verified: Linear `#08090a`, Resend `#000000` + `color-scheme: dark`, Vercel `dark light`. | Foundry is dark-only. Declare it. |
| **Keyboard affordances on the page** | Verified: Zed puts single-letter hints on the two CTAs. https://zed.dev. Raycast shows ⌘K in its comparison page. | Add D (download) and G (GitHub) hints. |
| **Real command on the page** | Verified: Vercel shows `vercel deploy --temporary`; Sol shows `brew install --cask sol`. | Show `open -a Foundry --convert` or the build line. |
| **Number with its method** | Verified: Shottr "17ms to grab a screenshot, and ~165ms to show it to you". https://shottr.cc. Ghostty says detailed benchmarks are "planned". https://ghostty.org/docs/about | Foundry's methodology page is already ahead of most. |
| **Dynamic OG image per page** | Verified: Linear, Cap, Arc farewell. | Foundry has one static OG. |
| **Human sign-off** | Verified: Arc farewell ends with a founder name and team signatures; Shottr is written in first person ("I'm too lazy for spam"). | Foundry has no maker's note. |
| **Honest limits on the page** | Verified: Ghostty "not trying to claim that Ghostty is the best"; Screen Studio "Some features depend on your Mac". | Foundry's methodology page already does this. Extend it. |
| **Release notes** | Verified: Raycast banner + sections, per-platform tabs. Zed weekly stable/preview. Dia has both release notes and changelog. | Foundry sends visitors to GitHub. |
| **Comparison page** | Verified: Raycast's vs-Alfred is feature-by-feature with a closing table and ends in testimonials. https://www.raycast.com/raycast-vs-alfred. The tone is one-sided; nothing shows Alfred winning. | Do it with Foundry's honest-loss rule. |
| **Brand/press page** | Verified: Zed (names, capitalisation, three logo colours, SVG copy). Raycast and Family list Press Kit in the footer. | Foundry has none. |
| **404** | Verified: Raycast returns a real 404 with a generic title; Vercel returns a 404 with agent links; **Linear returned HTTP 200 with "Loading…" for a nonexistent path (soft 404)**. Warp returns 404 with "Page not found \| Warp". | Foundry's tile 404 is already distinctive. Check status code. |
| **Cursor, hover language** | Not observable. | Foundry's CSS: underline-draw on links, fill-sweep on CTA, `:active` scale 0.97, hover guarded by `(hover: hover) and (pointer: fine)`. That is already good practice. |
| **Sound** | No verified example. | Stay silent. |
| **Scroll-linked vs time-based** | Not observable on others. | Foundry is scroll-linked with a spring (`stiffness 400, damping 50`). |
| **Free framing for open source** | Verified: Alfred "free to download and use forever, with no strings attached" and a paid Powerpack (https://www.alfredapp.com). Shottr pay-what-you-want with $0 allowed. Cap: free tier plus license plus Pro. Rectangle: Pro built on the open app. | Foundry is free; say it once, plainly. |

---

## 3. Trust and proof for an indie open-source macOS app

- **Gatekeeper reality.** Apple removed the Control-click override in Sequoia; the path is System Settings → Privacy & Security → Open Anyway (https://appleinsider.com/inside/macos-sequoia/tips/whats-changed-in-runtime-protection-for-macos-sequoia). One August 2026 guide says the Tahoe dialog no longer shows Open Anyway, only Move to Trash and Done (https://nektony.com/how-to/remove-non-notarized-apps-mac, single source). **Foundry's modal step 2 to 3 depends on this. Test it on macOS 26 and 27 before shipping.**
- **What others do.**
  - Tinycast (closest rival): "the DMG is self-signed" and tells users to run `xattr -dr com.apple.quarantine "/Applications/Tinycast.app"`; no notarization claim; Homebrew path first. https://github.com/abue-ammar/tinycast
  - Ice: GPL-3.0 named twice, `brew install --cask jordanbaird-ice`, no signing or permission text in the README. https://github.com/jordanbaird/Ice
  - Rectangle: no notarization text; Accessibility reset steps; settings path `~/Library/Preferences/com.knollsoft.Rectangle.plist`; "uses Sparkle for updates". https://github.com/rxhanson/Rectangle
  - Sol: "Download the latest release from GitHub, or install via the command line" and `brew install --cask sol`. https://sol.ospfranco.com
  - AlDente: a consent popup before download ("Before you download: please read and confirm") with licence and privacy checkboxes. https://apphousekitchen.com
- **Privacy statements that read as calm.** Shottr: "Telemetry does not contain any personal or identifiable information… never sold to the third parties… can turn off telemetry in Preferences", and says Google Analytics was removed in v1.5.1. https://shottr.cc. The specificity is what makes it credible.
- **Candour about limits.** Ghostty: faster in some benchmarks, slower in others, "it's not a full-time job for any of us". https://ghostty.org/docs/about
- **Size as a claim.** Shottr: "a tiny (2.3mb dmg) native app optimized for Apple Silicon", download button shows "v1.9.3, 2.4mb" (and the two figures disagree on the page, which is a small credibility leak).
- **Social proof for indie apps.** CleanShot: "Trusted by 250,000+ users", 4.9 rating, logos, ISO 27001 badge. https://cleanshot.com. Not applicable to Foundry; do not imitate.
- **Foundry already has** a method page with raw records and a reproduction runner. It is stronger than anything above except Ghostty's tone.

---

## 4. Launcher-specific positioning

| Product | What its site says | Source |
|---|---|---|
| Raycast | "Fast. Ergonomic. Reliable." "Think in milliseconds." "99.8% crash-free rate." Free tier plus Pro, "1650+ extensions" on the vs-Alfred page, Windows and iOS. | https://www.raycast.com, https://www.raycast.com/raycast-vs-alfred |
| Alfred | "Alfred 5 for Mac". Core is free forever; Powerpack is the paid workflow engine; "without lifting your fingers off the keyboard". No speed number. Alfred 6 teased. | https://www.alfredapp.com |
| Spotlight (Apple) | Tahoe added actions, Quick Keys, and clipboard history with 30 minute, 8 hour or 7 day windows. This is the free baseline Foundry's clipboard belt competes with. | https://appleinsider.com/inside/macos-tahoe/tips/spotlight-got-a-huge-upgrade-in-macos-tahoe-heres-how-to-use-it (third-party coverage) |
| Sol | "Sol is an open-source macOS launcher", "Free, focused on simplicity and speed." No native/memory claim. Never mentions Raycast or Alfred. | https://sol.ospfranco.com |
| Tinycast | "A tiny, fully native macOS launcher… under 100 MB of RAM." SwiftUI and AppKit, "no Electron and no telemetry", AGPL-3.0, runs Raycast extensions, macOS 26+ only. GitHub is the main page. | https://github.com/abue-ammar/tinycast |
| Vicinae | Linux Raycast-style launcher. Not a macOS competitor. | https://docs.vicinae.com |

**What Foundry can own, and what it cannot.**

- Cannot own: "native", "open source", "no Electron", "free". Tinycast says all four. Sol says open source and free. Do not present them as differences.
- Cannot own: lowest memory. Your own benchmark says Tinycast is lighter (~40.5 MB vs 60.5 to 120.0 MB).
- **Can own, with receipts in `docs/benchmarks`:**
  1. **Latency.** 17.5 to 19.1 ms hotkey-to-panel vs Tinycast 64.7 to 66.7 ms, and an 18 ms class figure against Raycast (report says "Raycast's ~18 ms class"). Raycast's own page states "milliseconds" with no number. Check the Raycast figure against `2026-08-29-foundry-raycast-v2-report.md` before quoting it.
  2. **81% less warmed memory than Raycast 2.5.3**, with the worst-leg rule and a published method.
  3. **Broader OS support.** macOS 14+ vs Tinycast's macOS 26+. Verified in the Tinycast README and Foundry's README.
  4. **Built-in conversion engine** (file shelf, background removal, OCR). No launcher in the table above lists this.
  5. **Raycast migration:** Raycast Quicklinks import, Script Commands and Snippets JSON import (`README.md`). Tinycast runs Raycast extensions, which Foundry does not claim. Do not compete there.
  6. **Hotkey takeover that moves Raycast/Alfred to ⌥Space** (`README.md`). Few sites mention a polite coexistence.
  7. **One person.** Sol's and Shottr's sites are personal; Foundry's has no maker voice.

---

## 5. Ranked improvements (25)

Ranked by trust risk first, then payoff per hour. Each is checkable.

1. **download** Fix the hotkey mismatch: hero/closing say ⌘ Space, the modal says ⌥+Space. Make both match the default in `README.md`.
2. **download** Run the modal's Gatekeeper steps on macOS 26 and 27 and rewrite them to match what the dialog actually shows; the Tahoe report in section 3 says Open Anyway may be absent from the dialog.
3. **download** Make the notarization sentence true: reconcile `download-gate.tsx` ("isn't notarized") with `docs/distribution.md` and `docs/HANDOFF.md:11`, and show the state of the exact DMG served by `releases/latest`.
4. **proof** Lead with latency: add "17 ms to open" with p50, p95, machine and a link to the benchmark, in the Shottr "17ms to grab, ~165ms to show" register.
5. **proof** Add a Tinycast row to the methodology page (latency win, memory loss) and state it plainly; this is the Ghostty candour pattern and it protects the 81% claim from the obvious rebuttal.
6. **download** Put version, DMG size, macOS 14+, licence name and SHA-256 next to the button (Shottr shows "v1.9.3, 2.4mb").
7. **proof** Add a one-line privacy statement that lists exactly what leaves the machine (Frankfurter rates, yt-dlp via Homebrew, optional AI providers) as Shottr does for telemetry; confirm each against the code first.
8. **chrome** Expand the footer: Licence, Methodology, Release notes (own page), Privacy, Brand, Source, Report an issue (compare Raycast and Zed footers).
9. **chrome** Build `/changelog` from `docs/release-notes/*.md` with date, one image, grouped bullets, and an Atom feed (Raycast format, https://www.raycast.com/changelog).
10. **brand** Ship `icons` with light and dark SVG favicons by media query, plus `theme-color #0f0d0c` and `color-scheme: dark` (Zed, Cursor, Resend heads).
11. **brand** Give `/methodology` and the 404 their own OG images, and `curl` the home page to confirm `twitter:image` is present.
12. **accessibility** Fix the download dialog: it focuses the dialog on open but does not trap focus, mark the background inert, or return focus to the trigger on close (`download-gate.tsx`).
13. **hero** Add keyboard hints to the CTAs (D to download, G for GitHub) as Zed does, and make `/` focus the demo launcher.
14. **hero** Wire the in-app `confetti` command (listed in `README.md`) to the hero launcher: type `confetti` and tiles burst. One reward for attention.
15. **performance** Measure LCP and CLS on 4x-throttled mobile and set a budget; keep server-rendered copy, since Linear's shell shows "Loading…" to non-JS fetchers.
16. **performance** Pause the three.js render loop when the canvas is offscreen or the tab is hidden, and defer WebGL init until after the wordmark and headline paint.
17. **story** Sync URL hash to the active section (`#shelf`, `#clipboard`, `#tools`, `#memory`, `#download`) so shared links land correctly; today only `?at=` exists in `app/page.tsx`.
18. **accessibility** With `prefers-reduced-motion: reduce`, read the whole page in order and confirm every claim still appears (the stills path exists, check shelf, tools, memory).
19. **accessibility** Test 900 to 1100 px width and 200% zoom: `.foundry-copy h1` is `white-space: nowrap` at `4.15vw` and the stage uses `min-height: 56.28vw`.
20. **chrome** Verify the 404 returns HTTP 404 (Linear's nonexistent path returned 200), and add Methodology, Download and GitHub links to the 404 page.
21. **brand** Add `/brand`: wordmark SVG, tile mark, palette (`#0f0d0c #eee7dd #fa6428`), Geist, name capitalisation, usage rules (Zed brand page).
22. **brand** Add a short maker's note, first person, with the "one person" claim and a name (Arc sign-off, Shottr voice).
23. **proof** Add a copy button on the methodology reproduction command and link the raw JSON records beside the table.
24. **hero** Add `/vs/raycast`: feature by feature, one line each, with a "Where Raycast is better" block (extensions, AI, Windows and iOS), so the page does not read as the one-sided Raycast-vs-Alfred page.
25. **proof** Generate the version string in the download story and JSON-LD from `VERSION` so it cannot drift from the release (today `v1.1` vs release notes `1.2.0`).

## Sources not cited above

- https://iboysoft.com/tips/allow-apps-to-run-sequoia.html (Open Anyway steps, third-party)
- https://alternativeto.net/software/tinycast/ (third-party listing)
