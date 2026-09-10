import type { Tile, Pose } from "../tile-motion";

export type Rect = { x: number; y: number; width: number; height: number };
export type ShelfLayout = {
  width: number;
  height: number;
  wordmark: Rect;
  palette: Rect;
  gate: Rect;
  file: Rect;
  image: Rect;
};
export type ShelfCell = {
  kind: "file" | "arrow" | "image";
  column: number;
  row: number;
  color: string;
  subject: boolean;
};
export type ShelfTile = { tile: Tile; rank: number; cell: ShelfCell };
export type ShelfPose = Pose & { sx: number; sy: number; color: number };

export const shelfStops = [
  { label: "Original", progress: 0.595 },
  { label: "Convert to PNG", progress: 0.84 },
  { label: "Remove background", progress: 0.999 },
] as const;

export function phase(value: number, start: number, end: number) {
  const t = Math.max(0, Math.min(1, (value - start) / (end - start)));
  return t * t * (3 - 2 * t);
}

export const introProgress = (progress: number) => Math.max(0, Math.min(1, progress / 0.36));
export const heroLift = (progress: number, height: number) => phase(progress, 0.25, 0.44) * height * 1.12;
const mix = (a: number, b: number, t: number) => a + (b - a) * t;
export const bezier = (a: number, b: number, c: number, d: number, t: number) => {
  const s = 1 - t;
  return s * s * s * a + 3 * s * s * t * b + 3 * s * t * t * c + t * t * t * d;
};

export function orangeCell(column: number, row: number): ShelfCell {
  const x = column - 7.5;
  const y = row - 8;
  const fruit = (x / 5.2) ** 2 + (y / 4.5) ** 2 < 1;
  const leafX = (column - 5.8) * 0.87 + (row - 3) * 0.5;
  const leafY = -(column - 5.8) * 0.5 + (row - 3) * 0.87;
  const leaf = (leafX / 3) ** 2 + (leafY / 1.2) ** 2 < 1;
  const stem = column === 8 && row === 4;
  const oranges = ["#ff963d", "#ff812b", "#f36a23", "#e85a1c"];
  const shade = Math.max(0, Math.min(3, Math.floor((x + y + 6) / 4)));
  return {
    kind: "image", column, row,
    color: leaf ? (leafY < 0 ? "#6f7d43" : "#566638") : stem ? "#7b613b" : fruit ? oranges[shade] : "#d6cdbd",
    subject: fruit || leaf || stem,
  };
}

export function createShelfCells(): ShelfCell[] {
  const cells: ShelfCell[] = [];
  for (let row = 6; row >= 0; row--) {
    for (let column = 0; column < 6; column++) {
      if (row < 3 && column >= 3 + row) continue;
      cells.push({ kind: "file", column, row, color: column >= 3 && row <= 3 ? "#968c7e" : "#d6cdbd", subject: false });
    }
  }
  for (let index = 0; index < 8; index++)
    cells.push({ kind: "arrow", column: index / 7, row: 0, color: "#d6cdbd", subject: false });
  for (const row of [-1, 1, -2, 2])
    cells.push({ kind: "arrow", column: 1, row, color: "#d6cdbd", subject: false });
  for (let column = 0; column < 16; column++) {
    for (let row = 0; row < 14; row++) cells.push(orangeCell(column, row));
  }
  return cells;
}

export const shelfCells = createShelfCells();

export function createShelfTiles(tiles: Tile[]): ShelfTile[] {
  const full = tiles.filter((tile) => tile.full).sort((a, b) =>
    (a.order ?? Infinity) - (b.order ?? Infinity) || b.y - a.y || b.x - a.x,
  );
  if (full.length !== shelfCells.length) throw new Error("The shelf must use the wordmark's full tile inventory");
  return full.map((tile, index) => ({
    tile,
    rank: index < 36 ? index / 35 : index < 48 ? (index - 36) / 11 : (index - 48) / 223,
    cell: shelfCells[index],
  }));
}

function sourcePose(out: ShelfPose, tile: Tile, source: Pose, progress: number, layout: ShelfLayout) {
  const scale = layout.wordmark.width / 1672;
  out.x = layout.wordmark.x + source.x * scale;
  out.y = layout.wordmark.y + source.y * scale - heroLift(progress, layout.height);
  out.z = source.z * scale;
  out.rx = source.rx;
  out.ry = source.ry;
  out.rz = source.rz;
  out.sx = tile.width * scale / 24;
  out.sy = tile.height * scale / 24;
  out.color = 0;
}

function gatePassage(out: ShelfPose, travel: number, progress: number, layout: ShelfLayout, x: number, y: number, size: number) {
  if (travel === 0) return;
  const gate = layout.gate;
  const gy = gate.y + gate.height / 2 - heroLift(progress, layout.height);
  const inX = gate.x - gate.height * 0.35;
  const outX = Math.min(gate.x + gate.width * 0.78, layout.width * 0.84);
  const flightSize = Math.min(gate.height * 0.22, 18);
  const release = phase(travel, 0, 0.28);
  const z = mix(out.z, Math.sin(travel * Math.PI) * 22, release);
  const rx = mix(out.rx, -Math.sin(travel * Math.PI) * 0.65, release);
  const ry = mix(out.ry, Math.sin(travel * Math.PI * 2) * 0.2, release);
  const rz = mix(out.rz, Math.sin(travel * Math.PI * 2) * 0.12, release);
  if (travel < 0.28) {
    out.x = bezier(out.x, out.x, inX - 35, inX, release);
    out.y = bezier(out.y, out.y + 35, gy - 10, gy, release);
    out.sx = mix(out.sx, flightSize / 24, release);
    out.sy = mix(out.sy, flightSize / 24, release);
  } else if (travel < 0.5) {
    out.x = mix(inX, outX, (travel - 0.28) / 0.22);
    out.y = gy;
    out.sx = out.sy = flightSize / 24;
  } else {
    const t = phase(travel, 0.5, 1);
    out.x = bezier(outX, outX - layout.width * 0.22, x + layout.width * 0.12, x, t);
    out.y = bezier(gy, gy + layout.height * 0.26, y + layout.height * 0.12, y, t);
    out.sx = out.sy = mix(flightSize, size * 0.95, t) / 24;
  }
  out.z = z;
  out.rx = rx;
  out.ry = ry;
  out.rz = rz;
  out.color = phase(travel, 0.6, 1);
}

function connectionPoint(layout: ShelfLayout, t: number) {
  const { file, image } = layout;
  const stacked = image.x < file.x + file.width;
  const startX = file.x + file.width + 24;
  const startY = file.y + file.height * 0.58;
  const endX = stacked ? image.x + image.width * 0.75 : image.x - 36;
  const endY = stacked ? image.y - 24 : image.y + image.height * 0.52;
  const bend = stacked ? -45 : 68;
  const x1 = mix(startX, endX, 0.32);
  const x2 = mix(startX, endX, 0.74);
  const y1 = startY + bend;
  const y2 = endY + bend;
  const s = 1 - t;
  return {
    x: bezier(startX, x1, x2, endX, t),
    y: bezier(startY, y1, y2, endY, t),
    angle: Math.atan2(
      3 * s * s * (y1 - startY) + 6 * s * t * (y2 - y1) + 3 * t * t * (endY - y2),
      3 * s * s * (x1 - startX) + 6 * s * t * (x2 - x1) + 3 * t * t * (endX - x2),
    ),
  };
}

export function writePeelExitPose(out: ShelfPose, tile: Tile, source: Pose, progress: number, layout: ShelfLayout) {
  sourcePose(out, tile, source, progress, layout);
  const start = 0.255 + (tile.order ?? 0) * 0.0025;
  const travel = phase(progress, start, start + 0.24);
  gatePassage(out, travel, progress, layout, layout.file.x + layout.file.width * .45, layout.file.y + layout.file.height * .65, 8);
  const absorb = 1 - phase(travel, .9, 1);
  out.sx *= absorb;
  out.sy *= absorb;
}

export function writeShelfPose(out: ShelfPose, entry: ShelfTile, source: Pose, progress: number, layout: ShelfLayout) {
  const { tile, cell, rank } = entry;
  sourcePose(out, tile, source, progress, layout);
  if (cell.kind === "file") {
    const size = layout.file.width / 6;
    const start = tile.order !== undefined ? 0.255 + tile.order * 0.0025 : 0.405 + rank * 0.018;
    const duration = tile.order !== undefined ? 0.24 : 0.115;
    gatePassage(out, phase(progress, start, start + duration), progress, layout,
      layout.file.x + (cell.column + 0.5) * size,
      layout.file.y + (cell.row + 0.5) * size, size);
    return;
  }
  if (progress <= 0.405) return;
  const start = cell.kind === "arrow" ? 0.615 + rank * 0.025 : 0.65 + rank * 0.045;
  const travel = phase(progress, start, start + (cell.kind === "arrow" ? 0.075 : 0.12));
  if (travel === 0) {
    out.sx = out.sy = 0;
    return;
  }
  const arrowSize = Math.max(10, Math.min(18, layout.file.width * 0.11));
  const entrance = phase(travel, 0, 0.14);
  let point = connectionPoint(layout, cell.kind === "arrow" ? travel * cell.column : Math.min(1, travel / 0.42));
  out.x = point.x;
  out.y = point.y;
  out.rz = point.angle * (1 - travel) * 0.25;
  out.rx = -Math.sin(travel * Math.PI) * 0.65;
  out.ry = Math.sin(travel * Math.PI) * 0.25;
  out.z = Math.sin(travel * Math.PI) * 20;
  out.sx = out.sy = arrowSize * entrance / 24;
  out.color = phase(travel, 0.55, 1);
  if (cell.kind === "arrow") {
    if (cell.row !== 0) {
      const wing = point.angle + Math.PI + Math.sign(cell.row) * 0.7;
      out.x += Math.cos(wing) * arrowSize * 1.45 * Math.abs(cell.row) * travel;
      out.y += Math.sin(wing) * arrowSize * 1.45 * Math.abs(cell.row) * travel;
    }
    return;
  }
  const size = layout.image.width / 16;
  const tx = layout.image.x + (cell.column + 0.5) * size;
  const ty = layout.image.y + (cell.row + 0.5) * size;
  if (travel > 0.42) {
    point = connectionPoint(layout, 1);
    const t = phase(travel, 0.42, 1);
    out.x = bezier(point.x, point.x + 75, tx - 20, tx, t);
    out.y = bezier(point.y, point.y - 35, ty - 30, ty, t);
    out.sx = out.sy = mix(arrowSize, size * 0.95, t) / 24;
  }
  if (cell.subject) return;
  const sweep = (15 - cell.column + cell.row * 0.18) / 18;
  const remove = phase(progress, 0.875 + sweep * 0.025, 0.975 + sweep * 0.02);
  if (remove === 0) return;
  const exitX = layout.width * (0.6 + cell.row * 0.014);
  const exitY = layout.height + size * (4 + cell.column * 0.3);
  out.x = bezier(tx, tx + 100 + cell.row * 4, exitX + 180, exitX, remove);
  out.y = bezier(ty, ty - 25, exitY - 150, exitY, remove);
  out.z += Math.sin(remove * Math.PI) * 65;
  out.rx -= Math.sin(remove * Math.PI) * 1.1;
  out.ry += Math.sin(remove * Math.PI * 2) * 0.65;
  out.rz = Math.sin(remove * Math.PI) * 0.2;
}
