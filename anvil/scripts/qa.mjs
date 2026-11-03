import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export function routesFrom(config) {
  return config.routes.flatMap((route) => config.widths.flatMap((width) => {
    const height = config.heights[width];
    return route.stops ? route.stops.map((stop) => ({ path: route.path, width, height, stop })) : [{ path: route.path, width, height }];
  }));
}

export function shotName({ path, width, stop }) {
  const slug = path === "/" ? "home" : path.replace(/^\//, "").replaceAll("/", "-");
  return stop === undefined ? `${slug}-${String(width).padStart(4, "0")}.png` : `${slug}-${width}-at${stop.toFixed(3)}.png`;
}

function urlFor(base, { path, stop }) {
  const url = new URL(path, base);
  if (stop !== undefined) {
    url.searchParams.set("inspect", "1");
    url.searchParams.set("at", String(stop));
  }
  return url.href;
}

async function settle(page) {
  await page.evaluate(() => document.fonts.ready);
  await page.waitForFunction(() => {
    const shell = document.querySelector(".story-shell");
    return !shell || shell.dataset.scene === "ready" || shell.dataset.scene === "still";
  }, null, { timeout: 15000 }).catch(() => {});
  await page.addStyleTag({ content: ".shelf-inspector{display:none!important}" });
  await page.waitForTimeout(1200);
}

async function capture(base, out, config) {
  const { chromium } = await import("playwright");
  const { default: AxeBuilder } = await import("@axe-core/playwright");
  const browser = await chromium.launch();
  const report = [];
  const axed = new Set();
  for (const shot of routesFrom(config)) {
    const context = await browser.newContext({ viewport: { width: shot.width, height: shot.height }, deviceScaleFactor: shot.width < 900 ? 2 : 1 });
    const page = await context.newPage();
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    const response = await page.goto(urlFor(base, shot), { waitUntil: "networkidle" });
    await settle(page);
    const name = shotName(shot);
    await page.screenshot({ path: join(out, name), fullPage: shot.stop === undefined });
    const facts = await page.evaluate(() => ({
      scene: document.querySelector(".story-shell")?.dataset.scene ?? null,
      font: getComputedStyle(document.querySelector("h1") ?? document.body).fontFamily,
      geist: document.fonts.check("16px Geist"),
      overflow: document.documentElement.scrollWidth - innerWidth,
      clipped: [...document.querySelectorAll("a, button")].filter((element) => !element.closest(".clipboard-deck, .tools-nav")).filter((element) => { const box = element.getBoundingClientRect(); return box.width && (box.right > innerWidth + 1 || box.left < -1); }).map((element) => element.textContent.trim().slice(0, 24)),
    }));
    const key = `${shot.path}@${shot.width}`;
    let violations = null;
    if (!axed.has(key)) {
      axed.add(key);
      const result = await new AxeBuilder({ page }).analyze();
      violations = result.violations.map((v) => ({ id: v.id, impact: v.impact, nodes: v.nodes.length, help: v.help }));
      writeFileSync(join(out, `axe-${name.replace(".png", ".json")}`), JSON.stringify(result.violations, null, 2));
    }
    report.push({ name, status: response?.status(), errors, violations, ...facts });
    await context.close();
  }
  await browser.close();
  return report;
}

async function audit(base, out, config) {
  const { chromium } = await import("playwright");
  const { launch } = await import("chrome-launcher");
  const { default: lighthouse } = await import("lighthouse");
  const scores = {};
  for (const route of config.routes) {
    const chrome = await launch({ chromePath: chromium.executablePath(), chromeFlags: ["--headless=new"] });
    const result = await lighthouse(new URL(route.path, base).href, { port: chrome.port, output: "json", logLevel: "error" });
    await chrome.kill();
    const slug = shotName({ path: route.path, width: 0 }).replace(/-0000\.png$/, "");
    writeFileSync(join(out, `lh-${slug}.json`), result.report);
    const lhr = result.lhr;
    scores[route.path] = {
      ...Object.fromEntries(Object.entries(lhr.categories).map(([id, c]) => [id, Math.round(c.score * 100)])),
      lcp: lhr.audits["largest-contentful-paint"].numericValue,
      cls: lhr.audits["cumulative-layout-shift"].numericValue,
      bytes: lhr.audits["total-byte-weight"].numericValue,
    };
  }
  return scores;
}

async function trace(base, out) {
  const { chromium } = await import("playwright");
  const gpu = process.env.QA_GPU === "1";
  const browser = await chromium.launch(gpu ? { headless: false, args: ["--enable-gpu", "--ignore-gpu-blocklist"] } : {});
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await page.addInitScript(() => {
    window.__longTasks = [];
    new PerformanceObserver((list) => { for (const entry of list.getEntries()) window.__longTasks.push({ start: Math.round(entry.startTime), duration: Math.round(entry.duration) }); }).observe({ type: "longtask", buffered: true });
  });
  const frames = [];
  const started = Date.now();
  await page.goto(base, { waitUntil: "commit" });
  for (let index = 0; Date.now() - started < 4000; index++) {
    const name = `trace-${String(index).padStart(3, "0")}.png`;
    await page.screenshot({ path: join(out, name), clip: { x: 0, y: 0, width: 1440, height: 520 } }).catch(() => {});
    const state = await page.evaluate(() => {
      const shell = document.querySelector(".story-shell");
      const svg = document.querySelector(".foundry-wordmark");
      return { scene: shell?.dataset.scene ?? null, svgOpacity: svg ? getComputedStyle(svg).opacity : null, fonts: document.fonts.status };
    }).catch(() => ({}));
    frames.push({ name, ms: Date.now() - started, ...state });
    await page.waitForTimeout(50);
  }
  const longTasks = await page.evaluate(() => window.__longTasks);
  await browser.close();
  return { frames, longTasks, longest: Math.max(0, ...longTasks.map((task) => task.duration)), blocking: longTasks.reduce((sum, task) => sum + task.duration - 50, 0) };
}

function contactSheet(out, report) {
  const cells = report.map(({ name }) => `<figure><img src="${name}" loading="lazy"><figcaption>${name}</figcaption></figure>`).join("");
  writeFileSync(join(out, "contact-sheet.html"), `<!doctype html><meta charset="utf-8"><title>QA</title><style>body{background:#111;color:#ddd;font:13px system-ui;display:grid;grid-template-columns:repeat(auto-fill,minmax(360px,1fr));gap:16px;padding:16px}img{width:100%;border:1px solid #333}</style>${cells}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const base = process.env.QA_BASE ?? "http://localhost:3123";
  const out = resolve(process.env.QA_OUT ?? `../docs/qa/${new Date().toISOString().slice(0, 10)}-website`);
  mkdirSync(out, { recursive: true });
  const config = JSON.parse(readFileSync(new URL("./qa-routes.json", import.meta.url)));
  const mode = process.argv[2] ?? "all";
  if (mode === "--trace") {
    const result = await trace(base, out);
    writeFileSync(join(out, "trace.json"), JSON.stringify(result, null, 2));
    console.log(`longest task ${result.longest} ms, blocking ${result.blocking} ms`);
  } else {
    const report = await capture(base, out, config);
    contactSheet(out, report);
    writeFileSync(join(out, "report.json"), JSON.stringify(report, null, 2));
    if (mode !== "--shots") writeFileSync(join(out, "lighthouse.json"), JSON.stringify(await audit(base, out, config), null, 2));
  }
  console.log(`wrote ${out}`);
}
