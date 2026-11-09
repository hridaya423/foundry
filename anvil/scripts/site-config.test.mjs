import { test } from "node:test";
import assert from "node:assert/strict";
import nextConfig from "../next.config.ts";
import { GET } from "../app/changelog/feed.xml/route.ts";
import { releases } from "../app/changelog.ts";

test("the server does not announce itself and sends the security headers", async () => {
  assert.equal(nextConfig.poweredByHeader, false);
  const [{ source, headers }] = await nextConfig.headers();
  assert.equal(source, "/:path*");
  const sent = Object.fromEntries(headers.map(({ key, value }) => [key, value]));
  assert.equal(sent["X-Content-Type-Options"], "nosniff");
  assert.equal(sent["X-Frame-Options"], "DENY");
  assert.match(sent["Referrer-Policy"], /strict-origin/);
  assert.match(sent["Strict-Transport-Security"], /max-age=\d+/);
  assert.match(sent["Content-Security-Policy"], /frame-ancestors 'none'/);
});

test("the home page stays static: the QA inspector is a rewrite to its own route", async () => {
  const { beforeFiles: [rule] } = await nextConfig.rewrites();
  assert.deepEqual(rule, { source: "/", has: [{ type: "query", key: "inspect", value: "1" }], destination: "/qa-inspect" });
});

test("every Atom entry summarises its release with the release intro", async () => {
  const feed = await GET().text();
  for (const { version, intro } of releases()) {
    const entry = feed.split("<entry>").find((chunk) => chunk.includes(`#v${version}</id>`));
    assert.ok(entry, `${version} missing from the feed`);
    const summary = entry.match(/<summary>([\s\S]*)<\/summary>/)[1];
    assert.ok(summary.length > 40, `${version} summary is a stub: ${summary}`);
    assert.equal(summary, intro[0].replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"));
  }
});
