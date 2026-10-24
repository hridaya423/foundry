import ShelfStory from "./foundry/story/story";
import "./foundry/foundry.css";
import "./foundry/story/story.css";
import "./foundry/story/clipboard.css";
import "./foundry/story/tools.css";
import "./foundry/story/memory.css";
import "./foundry/story/download.css";
import { storyEnd } from "./foundry/story/download-motion";
import { foundryDownloadUrl, siteDescription, siteUrl } from "./site";

const structuredData = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: "Foundry",
  description: siteDescription,
  url: siteUrl.href,
  applicationCategory: "UtilitiesApplication",
  operatingSystem: "macOS 14 or later",
  softwareVersion: "1.1",
  downloadUrl: foundryDownloadUrl,
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
};

export default async function Home({ searchParams }: {
  searchParams: Promise<{ inspect?: string; at?: string }>;
}) {
  const params = await searchParams;
  const at = Number(params.at ?? 0);
  return <>
    <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }} />
    <ShelfStory inspect={params.inspect === "1"} initialProgress={Number.isFinite(at) ? Math.max(0, Math.min(storyEnd, at)) : 0} />
  </>;
}
