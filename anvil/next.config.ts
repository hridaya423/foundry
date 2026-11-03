import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  allowedDevOrigins: ["127.0.0.1", "localhost"],
  env: { FOUNDRY_VERSION: readFileSync(join(process.cwd(), "..", "VERSION"), "utf8").trim() },
};

export default nextConfig;
