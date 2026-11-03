import { mkdir } from "node:fs/promises";
import { join, resolve } from "node:path";
import { openPage, root } from "./page.mjs";

const args = process.argv.slice(2);
const draft = args.includes("--draft");
const query = args.find((a) => a.startsWith("--q="))?.slice(4) || "";
const outDir = resolve(root, args.find((a) => a.startsWith("--out="))?.slice(6) || "qa/shots");
const times = args.filter((a) => !a.startsWith("--")).flatMap((a) => {
  if (a.includes(":")) {
    const [s, e, step] = a.split(":").map(Number);
    const out = [];
    for (let t = s; t <= e + 1e-9; t += step) out.push(+t.toFixed(4));
    return out;
  }
  return [Number(a)];
});
await mkdir(outDir, { recursive: true });

const { page, close } = await openPage({ query, draft });
for (const t of times) {
  const ms = await page.evaluate((time) => {
    const a = performance.now();
    window.__renderAt(time);
    window.__renderer?.getContext().finish?.();
    return performance.now() - a;
  }, t);
  const file = join(outDir, `t${t.toFixed(3).padStart(7, "0")}.png`);
  await page.screenshot({ path: file, type: "png" });
  console.log(`${t.toFixed(3)}s ${ms.toFixed(0)} ms -> ${file}`);
}
await close();
