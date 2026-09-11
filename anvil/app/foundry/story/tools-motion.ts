import { tileText } from "./tile-glyphs";
import { bezier, phase, type ShelfLayout, type ShelfPose } from "./shelf-motion";

export const toolsStart = 2.14;
export const storyEnd = 3.46;
export const toolBeatLength = .22;

export function toolBeat(progress: number) {
  const position = Math.max(0, (progress - toolsStart) / toolBeatLength);
  const selected = Math.min(5, Math.floor(position));
  return { selected, reveal: phase(position - selected, .22, .68), transition: phase(position - selected, 0, .045 / toolBeatLength) };
}
export const toolExamples = [
  { id: "calculator", name: "Calculator", source: "Expression", input: "24 × 18", result: String(24 * 18), resultLabel: "Result", action: "Calculate", detail: "Calculate without leaving the launcher." },
  { id: "translation", name: "Translation", source: "English", input: "Hello, world.", result: "Bonjour, le monde.", resultLabel: "French", action: "Translate to French", detail: "A prepared translation from English to French." },
  { id: "notes", name: "Apple Notes", source: "Search Apple Notes", input: "Weekend ideas", result: "Weekend ideas\nVisit the bookshop.\nTake the long way home.", resultLabel: "Sample note preview", action: "Find the note", detail: "Search a note’s title and content, then open it in Apple Notes." },
  { id: "snippets", name: "Snippets", source: "Saved keyword", input: ";thanks", result: "Thanks for your time.\nI’ll send the details\ntomorrow.", resultLabel: "Saved text", action: "Expand with Space", detail: "Type a saved keyword, then Space, to expand it." },
  { id: "ai", name: "AI profiles", source: "Draft", input: "I will send you the\nfirst draft tomorrow.", result: "I’ll send the draft\ntomorrow.", resultLabel: "Writing profile · sample response", action: "Use Writing profile", detail: "Choose a configured provider and model. This response is a prepared example." },
  { id: "developer", name: "Developer tools", source: "Unix timestamp", input: "1704067200", result: "2024-01-01\n00:00 UTC", resultLabel: "Date & time", action: "Convert timestamp", detail: "Turn a Unix timestamp into a readable date." },
] as const;

type ToolPoint = { x: number; y: number; size: number; accent: number };
type ToolTarget = ToolPoint & { start: ToolPoint; order: number; cursor?: number };
const snippetLines = toolExamples[3].result.split("\n");
const snippetLength = snippetLines.reduce((sum, line) => sum + line.length, 0);
const compositions = toolExamples.map(item => [tileText(item.input), tileText(item.result)]);

export function toolTargets(width: number, height: number, selected: number): ToolTarget[] {
  const mobile = width < 900;
  const center = width * (mobile ? .5 : .655);
  const baseline = height * (mobile ? .49 : .45);
  const available = width * (mobile ? .84 : .54);
  function textPoints(text: ReturnType<typeof tileText>, y: number, maxHeight: number, accent: number): ToolPoint[] {
    const cell = Math.min(available / text.width, height * maxHeight / text.height, width * (mobile ? .028 : .018));
    return text.points.map(point => ({ x: center + point.x * cell, y: y + point.y * cell, size: cell * .86, accent }));
  }
  if (selected === 4) {
    const sourceLines = toolExamples[4].input.split("\n").map(line => line.split(" "));
    const resultLines = toolExamples[4].result.split("\n").map(line => line.split(" "));
    const cell = Math.min(available / compositions[4][0].width, height * .18 / 17);
    function words(lines: string[][]) {
      return lines.flatMap((line, row) => {
        const length = line.join(" ").length;
        let cursor = 0;
        return line.map(word => {
          const text = tileText(word);
          const x = center + (cursor * 6 + (word.length * 6 - 1) / 2 - (length * 6 - 1) / 2) * cell;
          cursor += word.length + 1;
          return { word, points: text.points.map(point => ({ x: x + point.x * cell, y: baseline + (row * 10 - 5 + point.y) * cell, size: cell * .86, accent: 0 })) };
        });
      });
    }
    const source = words(sourceLines);
    const result = words(resultLines);
    return source.flatMap(entry => {
      const destination = result.find(next => next.word === (entry.word === "I" ? "I’ll" : entry.word));
      const count = Math.max(entry.points.length, destination?.points.length ?? 0);
      return Array.from({ length: count }, (_, index) => {
        const start = entry.points[index] ?? { ...entry.points[0], size: 0 };
        const end = destination?.points[index] ?? { ...start, size: 0 };
        return { ...end, accent: destination ? .65 : 1, start, order: 0 };
      });
    });
  }
  let input = textPoints(compositions[selected][0], baseline, .20, 0);
  let output = textPoints(compositions[selected][1], baseline, selected === 0 ? .28 : .23, 1);
  if (selected === 2) {
    input = textPoints(compositions[selected][0], height * (mobile ? .36 : .29), .075, 0);
    output = input.map(point => ({ ...point, y: point.y - height * .015, accent: 1 }));
  }
  if (selected === 5) {
    output = textPoints(compositions[selected][1], height * .68, .095, 1);
    const radius = Math.min(available * .21, height * .145);
    const cy = height * .43;
    const marks = Array.from({ length: 60 }, (_, index) => {
      const angle = index / 60 * Math.PI * 2 - Math.PI / 2;
      return { x: center + Math.cos(angle) * radius, y: cy + Math.sin(angle) * radius, size: radius * (index % 5 === 0 ? .085 : .035), accent: index % 15 === 0 ? 1 : 0 };
    });
    const hands = Array.from({ length: 14 }, (_, index) => ({ x: center + (index < 8 ? -1 : 2), y: cy - (index < 8 ? index : index - 8) * radius * .085, size: radius * .05, accent: 1 }));
    output = [...marks, ...hands, ...output];
  }
  const count = Math.max(input.length, output.length);
  const targets: ToolTarget[] = Array.from({ length: count }, (_, index) => {
    const start = input[index] ?? { ...input[index % input.length], size: 0 };
    const end = output[index] ?? { x: center, y: baseline, size: 0, accent: 1 };
    return { ...end, start, order: index / count };
  });
  if (selected === 3) {
    const startX = Math.max(...input.map(point => point.x)) + input[0].size * 2;
    const endX = Math.max(...output.filter(point => point.y > baseline + output[0].size / .86 * 5).map(point => point.x)) + output[0].size * 2;
    const endY = baseline + output[0].size / .86 * 10;
    for (let row = -2; row <= 2; row++) targets.push({ x: endX, y: endY + row * output[0].size, size: output[0].size * .6, accent: 1, start: { x: startX, y: baseline + row * input[0].size, size: input[0].size * .6, accent: 1 }, order: 0, cursor: row });
  }
  return targets;
}

export const toolTileCount = Math.max(...toolExamples.map((_, selected) => toolTargets(1280, 720, selected).length));

export function writeToolsTilePose(out: ShelfPose, index: number, progress: number, layout: ShelfLayout, selected: number, reveal: number, targets: ToolTarget[], previous: ToolTarget[] = targets, transition = 1) {
  if (progress <= 1.9) return;
  const point = targets[index];
  const from = previous[index];
  const enter = phase(progress, 1.92, 2.08);
  const change = previous === targets ? 1 : transition;
  if (!point) {
    if (from && change < 1) {
      out.x = from.x;
      out.y = from.y;
      out.sx = out.sy = from.size / 24 * (1 - change);
      out.rx = -.12;
      out.ry = out.rz = out.z = 0;
      out.color = from.accent;
    } else out.sx = out.sy = 0;
    return;
  }
  const { width, height } = layout;
  const center = width * (width < 900 ? .5 : .655);
  let t = reveal;
  let x = point.start.x + (point.x - point.start.x) * t;
  let y = point.start.y + (point.y - point.start.y) * t;
  let z = 0;
  let ry = 0;
  let rz = 0;
  if (selected === 0) {
    x = bezier(point.start.x, center, center, point.x, t);
    y = bezier(point.start.y, height * .48, height * .34, point.y, t);
    z = Math.sin(t * Math.PI) * 24;
    rz = Math.sin(t * Math.PI * 2) * .12;
  } else if (selected === 1) {
    const column = (point.x / width - (width < 900 ? .08 : .385)) / (width < 900 ? .84 : .54);
    t = phase(reveal, column * .76, column * .76 + .24);
    x = point.start.x + (point.x - point.start.x) * t;
    y = point.start.y + (point.y - point.start.y) * t;
    ry = Math.sin(t * Math.PI) * Math.PI / 2;
    z = Math.sin(t * Math.PI) * 12;
  } else if (selected === 3) {
    t = phase(reveal, point.order * .55, point.order * .55 + .45);
    const caret = center - width * (width < 900 ? .40 : .25);
    x = bezier(point.start.x, caret, caret, point.x, t);
    y = point.start.y + (point.y - point.start.y) * t;
    if (point.cursor !== undefined && reveal > .1 && reveal < 1) {
      const cell = targets[0].size / .86;
      let column = Math.round(phase(reveal, .225, .775) * snippetLength);
      let row = 0;
      while (row < snippetLines.length - 1 && column > snippetLines[row].length) column -= snippetLines[row++].length;
      const follow = phase(reveal, .1, .2);
      const cursorX = center + (column * 6 - (snippetLines[row].length * 6 - 1) / 2 + 1) * cell;
      const cursorY = height * (width < 900 ? .49 : .45) + (row - 1) * cell * 10 + point.cursor * cell * .86;
      x += (cursorX - x) * follow;
      y += (cursorY - y) * follow;
    }
  } else if (selected === 4) {
    const removed = point.size === 0;
    t = removed ? phase(reveal, 0, .4) : phase(reveal, .25, 1);
    const movesUp = point.start.y - point.y > height * .02;
    const lowerLine = point.start.y > height * (width < 900 ? .49 : .45);
    const slide = removed ? t : movesUp ? phase(reveal, .55, 1) : lowerLine ? phase(reveal, .60, 1) : phase(reveal, .3, .85);
    x = point.start.x + (point.x - point.start.x) * slide;
    y = point.start.y + (point.y - point.start.y) * (movesUp ? phase(reveal, .25, .6) : slide);
    z = removed ? -80 * t : 0;
  } else if (selected === 5) {
    t = phase(reveal, point.order * .20, .65 + point.order * .35);
    x = bezier(point.start.x, center, point.x, point.x, t);
    y = bezier(point.start.y, height * .32, point.y, point.y, t);
    rz = Math.sin(t * Math.PI) * .5;
  }
  const size = (point.start.size + (point.size - point.start.size) * t) / 24;
  if (change < 1) {
    x = (from?.x ?? point.start.x) + (x - (from?.x ?? point.start.x)) * change;
    y = (from?.y ?? point.start.y) + (y - (from?.y ?? point.start.y)) * change;
  }
  const scale = (from?.size ?? 0) / 24 * (1 - change) + size * change;
  if (index >= 48) {
    out.x = center;
    out.y = height * .49;
    out.sx = out.sy = 0;
  }
  out.x = bezier(out.x, out.x, x, x, phase(progress, 1.9, 1.98));
  out.y += (y - out.y) * enter;
  out.z += (z - out.z) * enter;
  out.rx += (-.12 - out.rx) * enter;
  out.ry += (ry - out.ry) * enter;
  out.rz += (rz - out.rz) * enter;
  out.sx += (scale - out.sx) * enter;
  out.sy += (scale - out.sy) * enter;
  out.color = (from?.accent ?? point.start.accent) * (1 - change) + (point.start.accent + (point.accent - point.start.accent) * t) * change;
}
