import { tileText } from "./story/tile-glyphs";

export const methodologyFigure = tileText("81%");
const figureTop = 132;
const left = Math.min(...methodologyFigure.points.map((point) => point.x));
const top = Math.min(...methodologyFigure.points.map((point) => point.y));

export const figureCells = methodologyFigure.points.map((point) => ({ column: point.x - left, row: point.y - top }));

export function methodologyFigureTargets(width: number) {
  const cell = width < 900 ? 9 : 14;
  const x = Math.max(width * .06, (width - 760) / 2);
  return figureCells.map(({ column, row }) => ({ x: x + (column + .5) * cell, y: figureTop + (row + .5) * cell, size: cell * .9 }));
}
