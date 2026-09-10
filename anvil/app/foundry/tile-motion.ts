import { CatmullRomCurve3, CubicBezierCurve3, CurvePath, LineCurve3, Vector3 } from "three";

export type Tile = {
  id: string;
  full: boolean;
  row: number;
  column: number;
  width: number;
  height: number;
  x: number;
  y: number;
  order?: number;
  polygons: number[][][];
};
export type Layout = { paletteX: number; paletteY: number };
export type Pose = { x: number; y: number; z: number; rx: number; ry: number; rz: number };
export type FlightPath = {
  points: Vector3[];
  length: number;
  travelEnd: number;
  entries: { points: Vector3[]; length: number; delay: number; endDistance: number; flightOffset?: number }[];
};
const clamp = (value: number) => Math.max(0, Math.min(1, value));
const smooth = (value: number) => {
  const t = clamp(value);
  return t * t * (3 - 2 * t);
};
const mix = (a: number, b: number, t: number) => a + (b - a) * t;

function hinge(tile: Tile, angle: number) {
  return new Vector3(
    tile.x,
    tile.y + 1.7 * Math.sin(angle) - tile.height / 2 * (1 - Math.cos(angle)),
    tile.height / 2 * Math.sin(angle) + 1.7 * (1 - Math.cos(angle)),
  );
}

export function createFlightPath(layout: Layout, tiles: Tile[]): FlightPath {
  const dx = layout.paletteX - 966;
  const dy = layout.paletteY - 572;
  const curve = new CatmullRomCurve3([
    new Vector3(1240 + dx, 490 + dy, 30),
    new Vector3(1255 + dx, 520 + dy, 34),
    new Vector3(1110 + dx, 538 + dy, 38),
    new Vector3(940 + dx, 542 + dy, 41),
    new Vector3(875 + dx, 613 + dy, 45),
    new Vector3(860 + dx, 690 + dy, 50),
    new Vector3(925 + dx, 754 + dy, 55),
  ], false, "centripetal");
  const points = curve.getSpacedPoints(320);
  const length = curve.getLength();
  const moving = tiles.filter((tile) => tile.order !== undefined).sort((a, b) => a.order! - b.order!);
  const flying = moving.filter((tile) => tile.row >= 10);
  const tangent = curve.getTangent(0);
  const entries: FlightPath["entries"] = moving.map((tile) => {
    const clearance = new Vector3(tile.x, tile.y + tile.height + 10, 22);
    const entry = new CurvePath<Vector3>();
    const start = hinge(tile, 0.35);
    const direction = clearance.clone().sub(start).normalize();
    entry.add(new LineCurve3(start, clearance));
    entry.add(new CubicBezierCurve3(
      clearance,
      clearance.clone().addScaledVector(direction, 30).add(new Vector3((tile.x - 962) * 0.5, 0, 0)),
      points[0].clone().addScaledVector(tangent, -42),
      points[0],
    ));
    const entryLength = entry.getLength();
    const across = (tile.x - 962) / 228;
    const influence = Math.max(0, 1 - ((tile.x - 1090) / 145) ** 2);
    const endDistance = tile.row === 9 ? 24 + 76 * smooth(across) : 3 + 6 * influence;
    const delay = [0.7, 0.62, 0.55, 0][tile.row - 8] + (8 - tile.column) * 0.008;
    return { points: entry.getSpacedPoints(100), length: entryLength, delay, endDistance };
  });
  const longest = Math.max(...flying.map((tile) => entries[tile.order!].length));
  flying.forEach((tile, index) => {
    entries[tile.order!].flightOffset = longest - entries[tile.order!].length + index * 42;
  });
  return { points, length, entries, travelEnd: 22 + longest + length };
}

export function tilePose(tile: Tile, progress: number, path: FlightPath): Pose {
  const origin = { x: tile.x, y: tile.y, z: 0, rx: 0, ry: 0, rz: 0 };
  if (tile.order === undefined || progress <= 0) return origin;
  const entry = path.entries[tile.order];
  const distance = entry.flightOffset === undefined
    ? entry.endDistance * smooth((clamp(progress / 0.94) - entry.delay) / (1 - entry.delay))
    : Math.max(0, smooth(progress / 0.94) * path.travelEnd - entry.flightOffset);
  if (distance <= 12) {
    const angle = 0.35 * smooth(distance / 12);
    const point = hinge(tile, angle);
    return { x: point.x, y: point.y, z: point.z, rx: -angle, ry: 0, rz: 0 };
  }
  const raw = distance - 12;
  const travel = raw < 20 ? raw * raw / 40 : raw - 10;
  const released = travel >= entry.length;
  const samples = released ? path.points : entry.points;
  const fraction = released ? (travel - entry.length) / path.length : travel / entry.length;
  const index = clamp(fraction) * (samples.length - 1);
  const low = Math.floor(index);
  const high = Math.min(samples.length - 1, low + 1);
  const t = index - low;
  const flow = released ? clamp(fraction) : 0;
  const bend = Math.sin(flow * Math.PI) ** 2;
  return {
    x: mix(samples[low].x, samples[high].x, t),
    y: mix(samples[low].y, samples[high].y, t),
    z: mix(samples[low].z, samples[high].z, t),
    rx: released ? -0.7 + 0.35 * smooth(flow) - 0.55 * bend : -0.35 - 0.35 * smooth(fraction) - 0.4 * Math.sin(fraction * Math.PI) ** 2,
    ry: released ? Math.sin(flow * Math.PI * 2) * 0.14 * bend : 0,
    rz: released ? Math.sin(flow * Math.PI * 2) * 0.22 * bend : 0,
  };
}
