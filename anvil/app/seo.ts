import type { Metadata } from "next";
import { authorName, hubUrl } from "./site";

export const author = { name: authorName, url: hubUrl };

export function pageSocial(title: string, description: string, path: string): Pick<Metadata, "openGraph" | "twitter"> {
  return {
    openGraph: { type: "website", siteName: "Foundry", title, description, url: path, images: ["/opengraph-image.png"] },
    twitter: { card: "summary_large_image", title, description, images: ["/opengraph-image.png"] },
  };
}
