import type { Metadata } from "next";
import { SiteFooter, SiteHeader } from "../foundry/site-chrome";
import { pageSocial } from "../seo";
import "../foundry/foundry.css";
import "./privacy.css";

const source = "https://github.com/hridaya423/foundry";
const licence = "https://github.com/hridaya423/foundry/blob/main/LICENSE";

export const metadata: Metadata = {
  title: "Foundry · Privacy",
  description: "What Foundry sends off your Mac, to whom, and how to avoid it. Everything else stays on your Mac.",
  alternates: { canonical: "/privacy" },
  ...pageSocial("Foundry · Privacy", "What Foundry sends off your Mac, to whom, and how to avoid it. Everything else stays on your Mac.", "/privacy"),
};

export default function PrivacyPage() {
  return <main className="foundry-preview privacy">
    <SiteHeader />
    <h1 id="content">Privacy</h1>
    <p className="privacy-status">Last updated <time dateTime="2026-11-01">1 November 2026</time></p>
    <p>Foundry keeps your data on your Mac. The app contacts no server run by Foundry. A few features call other services, and this page lists each one.</p>

    <h2>What leaves your Mac</h2>
    <p>Your IP address reaches every service below. Each item says what else is sent, when, and how to avoid it.</p>

    <section className="privacy-item">
      <h3>Currency rates</h3>
      <p>Foundry asks Frankfurter (<code>api.frankfurter.dev</code>) for exchange rates. It sends the two currency codes, not the amount. This happens when your search text reads as a conversion, such as <code>100 usd to eur</code>. It starts as you type, before you press Return.</p>
      <p className="privacy-avoid"><strong>To avoid it:</strong> do not type currency conversions.</p>
    </section>

    <section className="privacy-item">
      <h3>Weather</h3>
      <p>Foundry sends the city name to Open-Meteo, then the coordinates it gets back. Weather is off until you add the widget and enter a city. It then repeats every 10 minutes, and less often on Low Power Mode or a hot Mac.</p>
      <p className="privacy-avoid"><strong>To avoid it:</strong> remove the Weather widget.</p>
    </section>

    <section className="privacy-item">
      <h3>Stock quotes</h3>
      <p>Foundry sends the ticker to Yahoo Finance. Stock is off until you add the widget and enter a ticker. It repeats on the same schedule as Weather.</p>
      <p className="privacy-avoid"><strong>To avoid it:</strong> remove the Stock widget.</p>
    </section>

    <section className="privacy-item">
      <h3>Quicklink icons</h3>
      <p>Foundry asks each quicklink&rsquo;s site for its icon, at <code>/favicon.ico</code>. This is on by default. It happens when a quicklink such as Search Google appears in results. Fetched icons stay in a cache of up to 32 MB.</p>
      <p className="privacy-avoid"><strong>To avoid it:</strong> turn off Site icons in Settings, under Quicklinks.</p>
    </section>

    <section className="privacy-item">
      <h3>Media downloads</h3>
      <p>A direct file link is fetched from the address you paste. Any other link goes to yt-dlp, which contacts that site. If yt-dlp is missing, Foundry installs it with Homebrew when you start the download.</p>
      <p>A pasted YouTube link loads its thumbnail from YouTube. The Downloads list loads each site&rsquo;s icon from DuckDuckGo and sends the site&rsquo;s host name.</p>
      <p className="privacy-avoid"><strong>To avoid it:</strong> do not use media downloads.</p>
    </section>

    <section className="privacy-item">
      <h3>Conversion tools</h3>
      <p>Some file conversions need tools from Homebrew. Foundry shows what it will install and installs only after you approve.</p>
      <p className="privacy-avoid"><strong>To avoid it:</strong> decline the setup prompt.</p>
    </section>

    <section className="privacy-item">
      <h3>Background removal</h3>
      <p>When you choose Set Up BEN2, Foundry downloads a 223 MB model from Hugging Face. It also runs uv, which fetches Python 3.13 and three packages. Your images are processed on your Mac.</p>
      <p className="privacy-avoid"><strong>To avoid it:</strong> do not set up BEN2.</p>
    </section>

    <section className="privacy-item">
      <h3>AI providers</h3>
      <p>Apple Intelligence runs on your Mac and is the default. If you add another provider, Foundry sends your prompt, the earlier messages in that chat and any tool results to that provider, with the API key you saved. Ollama is off until you turn it on, and it points at your own Mac by default.</p>
      <p>In the search box, <code>ai</code>, <code>ask</code> and <code>plan</code> use Apple Intelligence. <code>ollama</code> uses your Ollama host. These start while you type, before you press Return.</p>
      <p className="privacy-avoid"><strong>To avoid it:</strong> do not add a provider, and keep to Apple Intelligence.</p>
    </section>

    <section className="privacy-item">
      <h3>AI web search</h3>
      <p>When a question needs current facts, the AI searches the web. Foundry sends the query to Brave Search, or to DuckDuckGo if Brave returns nothing, and then loads the top result pages. This applies to every provider, including Apple Intelligence.</p>
      <p>The model writes the query. If your question contains words such as latest, news, price or weather, your whole question can be the query. The AI can also look up the time, your frontmost app and your computer name. With a remote provider, that result goes to the provider.</p>
      <p className="privacy-avoid"><strong>To avoid it:</strong> do not use the AI features. Foundry has no setting that turns off web search.</p>
    </section>

    <section className="privacy-item">
      <h3>ChatGPT sign-in</h3>
      <p>If you sign in with a ChatGPT subscription, Foundry talks to OpenAI at <code>auth.openai.com</code> and <code>chatgpt.com</code>. It is off until you set it up. While you sign in, Foundry listens on a local port for the callback.</p>
      <p className="privacy-avoid"><strong>To avoid it:</strong> do not sign in with ChatGPT.</p>
    </section>

    <h2>What never leaves your Mac</h2>
    <ul>
      <li><strong>Clipboard history.</strong> It is a SQLite file at <code>~/.local/share/foundry/clipboard.sqlite</code>, with images beside it. It is on by default and keeps up to 1,000 items, 1 GB and 90 days. You can change all three. It skips items that apps mark as concealed, transient or password, and apps you exclude. No feature sends it anywhere.</li>
      <li><strong>Settings, snippets and AI chats.</strong> They are files in <code>~/.config/foundry</code>.</li>
      <li><strong>Usage ranking.</strong> It is <code>~/.local/share/foundry/usage.json</code>. It keeps open counts, times and a hash of what you typed, not the text.</li>
      <li><strong>API keys and sign-in tokens.</strong> They are in the macOS Keychain, not in the settings file.</li>
      <li><strong>Diagnostics.</strong> Foundry writes its logs to the macOS system log on your Mac and sends nothing.</li>
    </ul>

    <h2>What Foundry does not have</h2>
    <ul>
      <li>No Foundry account.</li>
      <li>No analytics.</li>
      <li>No crash reporting.</li>
      <li>No update check.</li>
    </ul>

    <h2>Licence</h2>
    <p>Foundry is open source under the <a href={licence}>MIT licence</a>. The <a href={source}>source</a> is on GitHub, so you can check every claim on this page.</p>
    <SiteFooter />
  </main>;
}
