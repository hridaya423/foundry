import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export function cssFrom({ color, tile, motion }) {
  const lines = Object.entries(color).map(([name, value]) => {
    if (!/^#[0-9a-f]{6}$/.test(value)) throw new Error(`Colour token ${name} must be #rrggbb, got ${value}`);
    return `  --f-${name}: ${value};`;
  });
  lines.push(...Object.entries(tile).map(([name, value]) => `  --f-tile-${name}: ${value};`));
  lines.push(...Object.entries(motion).map(([name, value]) => `  --f-${name}: ${value};`));
  return `:root {\n${lines.join("\n")}\n}\n`;
}

export function moduleFrom({ color }) {
  return `export const color = ${JSON.stringify(color, null, 2)} as const;\n`;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const tokens = JSON.parse(readFileSync(new URL("../../docs/brand/tokens.json", import.meta.url)));
  writeFileSync(new URL("../app/foundry/tokens.css", import.meta.url), cssFrom(tokens));
  writeFileSync(new URL("../app/foundry/tokens.ts", import.meta.url), moduleFrom(tokens));
}
