import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, resolve } from "node:path";
import { createRequire } from "node:module";
import { readdirSync, existsSync } from "node:fs";
import { homedir } from "node:os";

export const root = resolve(new URL("..", import.meta.url).pathname);
const npx = join(homedir(), ".npm/_npx");
const pkg = readdirSync(npx).map((d) => join(npx, d, "node_modules/puppeteer-core")).find((p) => existsSync(p));
const puppeteer = createRequire(join(pkg, "package.json"))("puppeteer-core");
const chromeDir = join(homedir(), ".cache/hyperframes/chrome/chrome-headless-shell");
const build = readdirSync(chromeDir).sort().pop();
const executablePath = join(chromeDir, build, "chrome-headless-shell-mac-arm64/chrome-headless-shell");

const types = { ".html": "text/html", ".js": "text/javascript", ".mjs": "text/javascript", ".json": "application/json", ".woff2": "font/woff2", ".ttf": "font/ttf", ".jpg": "image/jpeg", ".png": "image/png", ".wav": "audio/wav" };

export async function openPage({ query = "", draft = false } = {}) {
  const server = createServer(async (req, res) => {
    try {
      const path = join(root, decodeURIComponent(new URL(req.url, "http://x").pathname));
      const body = await readFile(path.endsWith("/") ? join(path, "index.html") : path);
      res.writeHead(200, { "content-type": types[extname(path)] || "application/octet-stream" });
      res.end(body);
    } catch {
      res.writeHead(404);
      res.end();
    }
  }).listen(0, "127.0.0.1");
  await new Promise((r) => server.once("listening", r));
  const browser = await puppeteer.launch({
    executablePath,
    headless: true,
    args: ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist", "--enable-webgl", "--disable-web-security", "--window-size=1920,1080"],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 1920, height: 1080, deviceScaleFactor: 1 });
  page.on("console", (m) => (m.type() === "error" || m.type() === "warning") && console.log("[page]", m.type(), m.text()));
  page.on("pageerror", (e) => console.log("[pageerror]", e.message));
  if (draft) await page.evaluateOnNewDocument(() => (window.__DRAFT = true));
  await page.goto(`http://127.0.0.1:${server.address().port}/index.html?${query}`, { waitUntil: "load" });
  await page.waitForFunction(() => window.__ready === true, { timeout: 120000 });
  const close = async () => {
    await browser.close();
    server.close();
  };
  return { page, close };
}
