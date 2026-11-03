import { test } from "node:test";
import assert from "node:assert/strict";
import { footerLinks, sitePages } from "../app/site.ts";

test("every footer link is a sitemap page or an external https url", () => {
  for (const { href } of footerLinks) {
    if (href.startsWith("/")) assert.ok(sitePages.includes(href), `${href} missing from sitePages`);
    else assert.match(href, /^https:\/\//);
  }
});

test("every internal page has a route folder", async () => {
  const { existsSync } = await import("node:fs");
  for (const path of sitePages) {
    const file = path === "/" ? "app/page.tsx" : `app${path}/page.tsx`;
    assert.ok(existsSync(new URL(`../${file}`, import.meta.url)), `${file} missing`);
  }
});
