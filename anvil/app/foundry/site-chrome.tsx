import Link from "next/link";
import DownloadLink from "./download-gate";

export function SiteHeader() {
  return <header className="site-header">
    <Link className="foundry-logo" href="/">foundry</Link>
    <DownloadLink>Download</DownloadLink>
  </header>;
}

export function SiteFooter() {
  return <footer className="site-footer">
    <Link className="site-footer-wordmark" href="/">foundry</Link>
    <nav aria-label="Foundry links"><a href="https://github.com/hridaya423/foundry">GitHub</a><a href="https://github.com/hridaya423/foundry/releases/latest">Release notes</a></nav>
  </footer>;
}
