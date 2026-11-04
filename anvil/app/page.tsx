import ShelfStory from "./foundry/story/story";
import "./foundry/foundry.css";
import "./foundry/story/story.css";
import "./foundry/story/clipboard.css";
import "./foundry/story/tools.css";
import "./foundry/story/memory.css";
import "./foundry/story/download.css";
import { storyEnd } from "./foundry/story/download-motion";
import { authorName, caseStudyUrl, foundryDownloadUrl, foundryVersion, hubUrl, repoUrl, siteDescription, siteUrl } from "./site";
import { formatFigure, proofFigures } from "./proof";

const hubPage = { "@type": "WebPage", "@id": caseStudyUrl, url: caseStudyUrl, name: "Foundry case study" };
const person = { "@type": "Person", "@id": `${hubUrl}/#person`, name: authorName, url: hubUrl };

const structuredData = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "SoftwareApplication",
      "@id": `${siteUrl.href}#software`,
      name: "Foundry",
      description: siteDescription,
      url: siteUrl.href,
      applicationCategory: "UtilitiesApplication",
      operatingSystem: "macOS 14 or later",
      softwareVersion: foundryVersion,
      downloadUrl: foundryDownloadUrl,
      license: `${repoUrl}/blob/main/LICENSE`,
      isAccessibleForFree: true,
      offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
      author: person,
      sameAs: [repoUrl, caseStudyUrl],
      subjectOf: hubPage,
    },
    {
      "@type": "SoftwareSourceCode",
      "@id": `${repoUrl}#source`,
      name: "Foundry source code",
      codeRepository: repoUrl,
      programmingLanguage: "Swift",
      author: person,
      about: { "@id": `${siteUrl.href}#software` },
    },
    {
      "@type": "WebSite",
      "@id": `${siteUrl.href}#website`,
      name: "Foundry",
      url: siteUrl.href,
      description: siteDescription,
      inLanguage: "en",
      author: person,
    },
  ],
};

export default async function Home({ searchParams }: {
  searchParams: Promise<{ inspect?: string; at?: string }>;
}) {
  const params = await searchParams;
  const at = Number(params.at ?? 0);
  return <>
    <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, "\\u003c") }} />
    <ShelfStory appSize={formatFigure(proofFigures().find((figure) => figure.id === "app-size")!)} inspect={params.inspect === "1"} initialProgress={Number.isFinite(at) ? Math.max(0, Math.min(storyEnd, at)) : 0} />
  </>;
}
