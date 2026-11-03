import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dir = join(root, "docs", "benchmarks");
const read = (name) => readFileSync(join(dir, name), "utf8");
const json = (name) => JSON.parse(read(name));
const launcher = (data, name) => data.launchers.find((item) => item.name === name);
const dateOf = (name, data) => (data?.capturedAt ?? name).slice(0, 10);
const hundredths = (value) => Math.round(value * 100) / 100;
const tenths = (value) => (Math.round(value * 10) / 10).toFixed(1);
const range = (values) => {
  const low = Math.min(...values);
  const high = Math.max(...values);
  return low === high ? tenths(low) : `${tenths(low)} to ${tenths(high)}`;
};
const mac = (data) => `MacBook Pro, ${data.hardware}, macOS ${data.macOS}, ${data.systemAtStart.powerSource === "AC Power" ? "AC power" : "battery power"}`;

const pair = (name) => ["forward", "reverse"].map((order) => {
  const file = `2026-09-29-foundry-1.1-${name}-mbp-${order}.json`;
  return { file, data: json(file) };
});

const raycast = pair("raycast-2.5.3");
const tinycast = pair("tinycast-0.11.3");
const search = json("2026-10-08-foundry-1.2-search-latency.json");
const searchFile = "2026-10-08-foundry-1.2-search-latency.json";
const report12 = "2026-10-08-foundry-1.2-report.md";
const figures = [];
const add = (figure) => figures.push({ ...figure, source: figure.source.startsWith("Package.swift") ? figure.source : `docs/benchmarks/${figure.source}` });

{
  const foundry = tinycast.map(({ data }) => launcher(data, "Foundry").panelLatencyMilliseconds);
  const other = tinycast.map(({ data }) => launcher(data, "Tinycast").panelLatencyMilliseconds.p50);
  const p50 = Math.max(...foundry.map((item) => item.p50));
  const p95 = Math.max(...foundry.map((item) => item.p95));
  const worst = tinycast[foundry.findIndex((item) => item.p50 === p50)];
  add({
    id: "open-latency",
    value: hundredths(p50),
    unit: "ms",
    label: `Hotkey to panel on screen, p50, with p95 ${tenths(p95)} ms, on ${worst.data.hardware}`,
    sentence: `The panel is on screen ${tenths(p50)} ms after the hotkey at p50 and ${tenths(p95)} ms at p95. Each is the worse of two order-swapped runs of 30. Tinycast 0.11.3 took ${range(other)} ms at p50 in the same runs. This is a staged build that keeps the panel mapped, run on battery. It has not been re-run on 1.2.0.`,
    machine: mac(worst.data),
    version: `Foundry ${launcher(worst.data, "Foundry").version}`,
    date: dateOf(worst.file, worst.data),
    source: worst.file,
  });
}

{
  const foundry = raycast.map(({ data }) => launcher(data, "Foundry").panelLatencyMilliseconds);
  const other = raycast.map(({ data }) => launcher(data, "Raycast").panelLatencyMilliseconds.p50);
  const p50 = Math.max(...foundry.map((item) => item.p50));
  const p95 = Math.max(...foundry.map((item) => item.p95));
  const worst = raycast[foundry.findIndex((item) => item.p50 === p50)];
  add({
    id: "open-latency-release-build",
    value: hundredths(p50),
    unit: "ms",
    label: `Hotkey to panel on screen, p50, with p95 ${tenths(p95)} ms, earlier 1.1.0 build`,
    sentence: `The earlier 1.1.0 build took ${range(foundry.map((item) => item.p50))} ms at p50 to show the panel. Raycast 2.5.3 took ${range(other)} ms in the same runs. Raycast opens faster than that build did. The staged build above keeps the panel mapped, which the Tinycast report credits for the change.`,
    machine: mac(worst.data),
    version: `Foundry ${launcher(worst.data, "Foundry").version}`,
    date: dateOf(worst.file, worst.data),
    source: worst.file,
  });
}

{
  const legs = raycast.map(({ file, data }) => {
    const foundry = launcher(data, "Foundry").warmedFootprintMegabytes.p50;
    const other = launcher(data, "Raycast").warmedFootprintMegabytes.p50;
    return { file, data, foundry, other, reduction: 100 * (1 - foundry / other) };
  });
  const worst = legs.reduce((a, b) => (b.reduction < a.reduction ? b : a));
  const best = legs.reduce((a, b) => (b.reduction > a.reduction ? b : a));
  add({
    id: "memory-vs-raycast",
    value: Math.round(worst.reduction * 10) / 10,
    unit: "%",
    label: "Less warmed memory vs Raycast 2.5.3",
    sentence: `Foundry used ${tenths(worst.foundry)} MB and Raycast ${tenths(worst.other)} MB in the worse of two order-swapped runs. The better run was ${tenths(best.reduction)}% less. Each number is the median of 15 footprint samples, on AC power.`,
    machine: mac(worst.data),
    version: `Foundry ${launcher(worst.data, "Foundry").version}, Raycast ${launcher(worst.data, "Raycast").version}`,
    date: dateOf(worst.file, worst.data),
    source: worst.file,
  });
}

{
  const foundry = tinycast.map(({ data }) => launcher(data, "Foundry").warmedFootprintMegabytes.p50);
  const other = tinycast.map(({ data }) => launcher(data, "Tinycast").warmedFootprintMegabytes.p50);
  const worst = tinycast[foundry.indexOf(Math.max(...foundry))];
  add({
    id: "memory-vs-tinycast",
    value: hundredths(Math.max(...foundry)),
    unit: "MB",
    label: "Warmed memory vs Tinycast 0.11.3, worse run. Tinycast uses less",
    sentence: `Tinycast is lighter. It used ${range(other)} MB. Foundry used ${range(foundry)} MB, depending on run order. Each number is the median of 15 footprint samples, on battery.`,
    machine: mac(worst.data),
    version: `Foundry ${launcher(worst.data, "Foundry").version}, Tinycast ${launcher(worst.data, "Tinycast").version}`,
    date: dateOf(worst.file, worst.data),
    source: worst.file,
  });
}

{
  const table = read(report12).match(/App bundle size \| ([\d,]+) KB \| \*\*([\d,]+) KB\*\*/);
  if (!table) throw new Error(`App bundle size row not found in ${report12}`);
  const [before, after] = table.slice(1).map((text) => Number(text.replaceAll(",", "")));
  const others = [launcher(raycast[0].data, "Raycast"), launcher(tinycast[0].data, "Tinycast")];
  add({
    id: "app-size",
    value: after / 1000,
    unit: "MB",
    label: "App size on disk",
    sentence: `The 1.2.0 app is ${after.toLocaleString("en-US")} KB on disk. It was ${before.toLocaleString("en-US")} KB in 1.1 before symbols were stripped. In the September runs Tinycast 0.11.3 was ${tenths(others[1].bundleKilobytes / 1000)} MB and Raycast 2.5.3 was ${Math.round(others[0].bundleKilobytes / 1000)} MB. The 1.2 size comes from a report table. No raw record exists for it.`,
    machine: "Not machine dependent",
    version: `Foundry ${readFileSync(join(root, "VERSION"), "utf8").trim()}`,
    date: "2026-10-08",
    source: report12,
  });
}

add({
  id: "search-latency",
  value: search["search.immediate"].p50,
  unit: "ms",
  label: `Keystroke to results, p50, with p95 ${tenths(search["search.immediate"].p95)} ms, inside the app`,
  sentence: `Results are ready ${tenths(search["search.immediate"].p50)} ms after a keystroke at p50 and ${tenths(search["search.immediate"].p95)} ms at p95, over ${search["search.immediate"].n} samples. This is engine time in a test. It leaves out drawing and window server time. The 2026-10-12 report lists lower numbers from another machine and has no raw record, so they are not used.`,
  machine: "Apple M4, in-process test",
  version: "Foundry 1.2.0",
  date: dateOf(searchFile),
  source: searchFile,
});

{
  const manifest = readFileSync(join(root, "Package.swift"), "utf8");
  const count = manifest.match(/\.package\(/g)?.length ?? 0;
  const date = execFileSync("git", ["log", "-1", "--format=%cs", "--", "Package.swift"], { cwd: root, encoding: "utf8" }).trim();
  add({
    id: "dependencies",
    value: count,
    unit: "dependencies",
    label: "Third-party Swift packages",
    sentence: `Package.swift declares ${count} third-party Swift packages. Experimental background removal installs pinned Python wheels when it runs. Its NOTICE.txt lists them.`,
    machine: "Not machine dependent",
    version: `Foundry ${readFileSync(join(root, "VERSION"), "utf8").trim()}`,
    date,
    source: "Package.swift",
  });
}

const capturedAt = figures.filter((item) => item.source.startsWith("docs/benchmarks/")).map((item) => item.date).sort().at(-1);
writeFileSync(join(dir, "latest.json"), `${JSON.stringify({ capturedAt, figures }, null, 2)}\n`);
