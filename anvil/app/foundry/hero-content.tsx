import Image from "next/image";
import Launcher, { type LauncherTarget } from "./launcher";
import { foundryDownloadUrl } from "../site";

export default function FoundryHeroContent({ onOpen }: { onOpen?: (target: LauncherTarget) => void }) {
  return (
    <>
      <Image className="foundry-wordmark" src="/assets/foundry/tiled-wordmark.svg" alt="Foundry" width={1672} height={510} preload fetchPriority="high" loading="eager" unoptimized />
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
        <div className="foundry-actions">
          <a href={foundryDownloadUrl} className="foundry-cta">Download</a>
          <span className="foundry-hotkey"><kbd>⌘</kbd><kbd>Space</kbd> from anywhere</span>
        </div>
      </section>
      <Launcher onOpen={onOpen} />
    </>
  );
}
