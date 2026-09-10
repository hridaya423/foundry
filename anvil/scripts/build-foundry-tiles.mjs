import { Shape } from "three";
import clipping from "polygon-clipping";
import { mkdirSync, writeFileSync } from "node:fs";

const contours = [];
function outline(name, draw, holes = []) {
  const shape = new Shape();
  draw(shape);
  const rings = [
    shape,
    ...holes.map((drawHole) => {
      const hole = new Shape();
      drawHole(hole);
      return hole;
    }),
  ].map((path) => {
    const points = path.getPoints(64).map((p) => [p.x, p.y]);
    points.push(points[0]);
    return points;
  });
  contours.push({ name, rings });
}
outline("f", (p) =>
  p
    .moveTo(61, 181)
    .lineTo(96, 181)
    .lineTo(96, 156)
    .bezierCurveTo(96, 111, 126, 94, 176, 94)
    .lineTo(228, 94)
    .lineTo(228, 151)
    .lineTo(195, 151)
    .bezierCurveTo(171, 151, 168, 159, 168, 181)
    .lineTo(228, 181)
    .lineTo(228, 238)
    .lineTo(168, 238)
    .lineTo(168, 411)
    .lineTo(96, 411)
    .lineTo(96, 238)
    .lineTo(61, 238)
    .closePath(),
);
outline(
  "o",
  (p) =>
    p
      .moveTo(345, 177)
      .bezierCurveTo(418, 177, 464, 218, 464, 295)
      .bezierCurveTo(464, 372, 418, 416, 345, 416)
      .bezierCurveTo(270, 416, 226, 372, 226, 295)
      .bezierCurveTo(226, 218, 270, 177, 345, 177)
      .closePath(),
  [
    (p) =>
      p
        .moveTo(345, 234)
        .bezierCurveTo(313, 234, 298, 252, 298, 295)
        .bezierCurveTo(298, 342, 313, 363, 345, 363)
        .bezierCurveTo(378, 363, 393, 342, 393, 295)
        .bezierCurveTo(393, 252, 378, 234, 345, 234)
        .closePath(),
  ],
);
outline("u", (p) =>
  p
    .moveTo(482, 183)
    .lineTo(550, 183)
    .lineTo(550, 316)
    .bezierCurveTo(550, 338, 555, 348, 585, 348)
    .bezierCurveTo(615, 348, 629, 332, 629, 312)
    .lineTo(629, 183)
    .lineTo(699, 183)
    .lineTo(699, 411)
    .lineTo(629, 411)
    .lineTo(629, 384)
    .bezierCurveTo(610, 405, 585, 416, 559, 416)
    .bezierCurveTo(505, 416, 482, 386, 482, 335)
    .closePath(),
);
outline("n", (p) =>
  p
    .moveTo(728, 183)
    .lineTo(797, 183)
    .lineTo(797, 207)
    .bezierCurveTo(816, 187, 840, 177, 865, 177)
    .bezierCurveTo(920, 177, 944, 209, 944, 260)
    .lineTo(944, 411)
    .lineTo(874, 411)
    .lineTo(874, 282)
    .bezierCurveTo(874, 256, 865, 234, 840, 234)
    .bezierCurveTo(810, 234, 797, 261, 797, 284)
    .lineTo(797, 411)
    .lineTo(728, 411)
    .closePath(),
);
outline(
  "d",
  (p) =>
    p
      .moveTo(1119, 94)
      .lineTo(1190, 94)
      .lineTo(1190, 411)
      .lineTo(1119, 411)
      .lineTo(1119, 388)
      .bezierCurveTo(1101, 407, 1082, 416, 1054, 416)
      .bezierCurveTo(994, 416, 962, 373, 962, 297)
      .bezierCurveTo(962, 223, 994, 178, 1054, 178)
      .bezierCurveTo(1080, 178, 1104, 189, 1119, 208)
      .closePath(),
  [
    (p) =>
      p
        .moveTo(1080, 242)
        .bezierCurveTo(1055, 242, 1046, 261, 1046, 297)
        .bezierCurveTo(1046, 334, 1055, 350, 1080, 350)
        .bezierCurveTo(1103, 350, 1119, 332, 1119, 297)
        .bezierCurveTo(1119, 261, 1103, 242, 1080, 242)
        .closePath(),
  ],
);
outline("r", (p) =>
  p
    .moveTo(1215, 183)
    .lineTo(1299, 183)
    .lineTo(1299, 217)
    .bezierCurveTo(1316, 189, 1339, 178, 1371, 183)
    .lineTo(1371, 264)
    .lineTo(1344, 264)
    .bezierCurveTo(1314, 264, 1299, 280, 1299, 309)
    .lineTo(1299, 411)
    .lineTo(1215, 411)
    .closePath(),
);
outline("y", (p) =>
  p
    .moveTo(1380, 183)
    .lineTo(1456, 183)
    .lineTo(1504, 319)
    .lineTo(1549, 183)
    .lineTo(1620, 183)
    .lineTo(1552, 406)
    .bezierCurveTo(1536, 466, 1509, 496, 1457, 496)
    .lineTo(1400, 496)
    .lineTo(1400, 438)
    .lineTo(1432, 438)
    .bezierCurveTo(1450, 438, 1459, 427, 1464, 410)
    .closePath(),
);
function divide(stops, counts) {
  return stops.flatMap((start, index) =>
    index === stops.length - 1
      ? [start]
      : Array.from(
          { length: counts[index] },
          (_, step) =>
            start + ((stops[index + 1] - start) * step) / counts[index],
        ),
  );
}
const grids = {
  f: {
    x: divide([61, 96, 168, 228], [1, 3, 2]),
    y: divide([94, 151, 181, 238, 411], [2, 1, 2, 7]),
  },
  o: {
    x: divide([226, 298, 393, 464], [3, 4, 3]),
    y: divide([177, 234, 363, 416], [2, 5, 2]),
  },
  u: { x: divide([482, 550, 629, 699], [3, 3, 3]), y: divide([177, 416], [9]) },
  n: { x: divide([728, 797, 874, 944], [3, 3, 3]), y: divide([177, 416], [9]) },
  d: {
    x: divide([962, 1046, 1119, 1190], [3, 3, 3]),
    y: divide([94, 310, 390, 416], [8, 3, 1]),
  },
  r: { x: divide([1215, 1299, 1371], [3, 3]), y: divide([178, 411], [9]) },
  y: {
    x: divide([1380, 1400, 1456, 1549, 1620], [1, 2, 4, 3]),
    y: divide([183, 410, 438, 496], [8, 1, 2]),
  },
};
function simplify(points) {
  const first = points[0];
  const last = points.at(-1);
  const dx = last[0] - first[0];
  const dy = last[1] - first[1];
  let furthest = 0;
  let distance = 0.08;
  for (let i = 1; i < points.length - 1; i++) {
    const t = dx * dx + dy * dy === 0 ? 0 : Math.max(0, Math.min(1,
      ((points[i][0] - first[0]) * dx + (points[i][1] - first[1]) * dy) / (dx * dx + dy * dy),
    ));
    const deviation = Math.hypot(points[i][0] - first[0] - t * dx, points[i][1] - first[1] - t * dy);
    if (deviation > distance) {
      distance = deviation;
      furthest = i;
    }
  }
  return furthest ? [...simplify(points.slice(0, furthest + 1)).slice(0, -1), ...simplify(points.slice(furthest))] : [first, last];
}
const tiles = [];
for (const { name, rings } of contours) {
  const grid = grids[name];
  for (let row = 0; row < grid.y.length - 1; row++) {
    const y = grid.y[row];
    const height = grid.y[row + 1] - y;
    for (let column = 0; column < grid.x.length - 1; column++) {
      const x = grid.x[column];
      const width = grid.x[column + 1] - x;
      const cut = clipping.intersection(
        [rings],
        [
          [
            [
              [x + 0.2, y + 0.2],
              [x + width - 0.2, y + 0.2],
              [x + width - 0.2, y + height - 0.2],
              [x + 0.2, y + height - 0.2],
              [x + 0.2, y + 0.2],
            ],
          ],
        ],
      );
      for (const [part, polygon] of cut.entries()) {
        const area = Math.abs(
          polygon[0].reduce((sum, p, i, ps) => {
            const q = ps[(i + 1) % ps.length];
            return sum + p[0] * q[1] - q[0] * p[1];
          }, 0) / 2,
        );
        if (area < 0.1) continue;
        tiles.push({
          id: `${name}-${row}-${column}-${part}`,
          letter: name,
          row,
          column,
          x: x + width / 2,
          y: y + height / 2,
          width,
          height,
          area,
          full: area > (width - 0.4) * (height - 0.4) - 0.5,
          polygons: polygon.map((ring) =>
            simplify(ring).map((p) => p.map((v) => +v.toFixed(3))),
          ),
        });
      }
    }
  }
}
const moving = tiles
  .filter((tile) => tile.letter === "d" && tile.row >= 8 && tile.area > 150)
  .sort((a, b) => b.row - a.row || b.column - a.column);
moving.forEach((tile, order) => (tile.order = order));
mkdirSync("public/assets/foundry", { recursive: true });
writeFileSync("public/assets/foundry/tile-layout.json", JSON.stringify(tiles));
const paths = tiles
  .map(
    (t) =>
      `<path d="${t.polygons.map((r) => "M" + r.map((p) => p.join(",")).join("L") + "Z").join("")}"/>`,
  )
  .join("");
writeFileSync(
  "public/assets/foundry/tiled-wordmark.svg",
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1672 510"><defs><linearGradient id="chalk" x2="0" y2="1"><stop stop-color="#d4c9b7"/><stop offset="1" stop-color="#c2b6a3"/></linearGradient></defs><g fill="url(#chalk)">${paths}</g></svg>`,
);
console.log(
  `${tiles.length} tiles; ${moving.length} moving; ${tiles.filter((t) => t.full).length} full tiles`,
);
