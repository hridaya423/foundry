import { readFileSync } from "node:fs";
import { join } from "node:path";

export type Figure = {
  id: string;
  value: number;
  unit: string;
  label: string;
  sentence: string;
  machine: string;
  version: string;
  date: string;
  source: string;
};

export type Latest = { capturedAt: string; figures: Figure[] };

const stripIds = ["open-latency", "memory-vs-raycast", "app-size", "dependencies"];

export function readLatest(): Latest {
  return JSON.parse(readFileSync(join(process.cwd(), "..", "docs", "benchmarks", "latest.json"), "utf8"));
}

export function proofFigures(latest: Latest = readLatest()) {
  for (const figure of latest.figures) if (!figure.source) throw new Error(`Figure ${figure.id} has no source`);
  return latest.figures;
}

export function formatFigure({ value, unit }: Pick<Figure, "value" | "unit">) {
  if (unit === "%") return new Intl.NumberFormat("en-US", { style: "percent", maximumFractionDigits: 0 }).format(value / 100);
  return `${new Intl.NumberFormat("en-US", { maximumSignificantDigits: 3 }).format(value)} ${unit}`;
}

export function stripFigures() {
  const figures = proofFigures();
  return stripIds.map((id) => {
    const figure = figures.find((item) => item.id === id);
    if (!figure) throw new Error(`Figure ${id} is missing from latest.json`);
    return figure;
  });
}
