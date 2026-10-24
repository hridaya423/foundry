import type { MetadataRoute } from "next";
import { siteUrl } from "./site";

export default function sitemap(): MetadataRoute.Sitemap {
  return ["/", "/methodology"].map((path) => ({ url: new URL(path, siteUrl).href }));
}
