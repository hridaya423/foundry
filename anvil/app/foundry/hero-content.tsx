import DownloadLink from "./download-gate";

const commands = [
  { name: "Clipboard History", icon: <><rect x="6" y="5" width="14" height="17" rx="2" /><rect x="10" y="2" width="6" height="6" rx="1.5" /><path d="M6 17H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h3" /></> },
  { name: "Convert Image", icon: <><rect x="3" y="3" width="18" height="18" rx="2" /><circle cx="9" cy="9" r="2" /><path d="m21 15-5-5L5 21" /></> },
  { name: "Window Management", icon: <><rect x="2" y="3" width="20" height="18" rx="2" /><path d="M2 8h20M9 8v13" /></> },
];

export default function FoundryHeroContent() {
  return (
    <>
      <div className="foundry-wordmark" role="img" aria-label="Foundry" />
      <section className="foundry-copy" aria-labelledby="foundry-heading">
        <h1 id="foundry-heading">
          The app you never open.
          <br />
          Opens everything.
        </h1>
        <p>
          Launch apps, find what you copied, transform files,
          <br className="foundry-desktop-break" /> run commands. One native launcher.
        </p>
        <DownloadLink className="foundry-cta">Download</DownloadLink>
      </section>
      <section className="foundry-palette" aria-label="Foundry launcher">
        <div className="foundry-search">
          <span className="foundry-search-icon" aria-hidden="true" />
          <span className="foundry-search-placeholder">Search apps and commands</span>
        </div>
        <div className="foundry-results">
          {commands.map((command, index) => (
            <div key={command.name} id={`foundry-command-${index}`} className="foundry-row" data-selected={index === 1 || undefined}>
              <span className="foundry-command-icon" aria-hidden="true">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">{command.icon}</svg>
              </span>
              <span>{command.name}</span>
              <span className="foundry-row-kind">Command</span>
            </div>
          ))}
        </div>
      </section>
    </>
  );
}
