import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { NextConfig } from "next";

const securityHeaders = [
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=(), payment=(), usb=()" },
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains" },
  { key: "Content-Security-Policy", value: "frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'" },
];

const nextConfig: NextConfig = {
  allowedDevOrigins: ["127.0.0.1", "localhost"],
  env: { FOUNDRY_VERSION: readFileSync(join(process.cwd(), "..", "VERSION"), "utf8").trim() },
  poweredByHeader: false,
  headers: async () => [{ source: "/:path*", headers: securityHeaders }],
  rewrites: async () => ({ beforeFiles: [{ source: "/", has: [{ type: "query", key: "inspect", value: "1" }], destination: "/qa-inspect" }], afterFiles: [], fallback: [] }),
};

export default nextConfig;
