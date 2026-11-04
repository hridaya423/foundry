import type { MetadataRoute } from "next";
import { siteLastModified, sitePages, siteUrl } from "./site";

export default function sitemap(): MetadataRoute.Sitemap {
  return sitePages.map((path) => ({ url: new URL(path, siteUrl).href, lastModified: siteLastModified }));
}
