import { tileText } from "./tile-glyphs";
import { bezier, phase, type ShelfLayout, type ShelfPose } from "./shelf-motion";

export const toolsEnter = 1.58;
const toolsStart = toolsEnter + .16;
const toolBeatLength = .22;

export function toolBeat(progress: number) {
  const position = Math.max(0, (progress - toolsStart) / toolBeatLength);
  const selected = Math.min(toolExamples.length - 1, Math.floor(position));
  return { selected, reveal: phase(position - selected, .22, .68), transition: phase(position - selected, 0, .045 / toolBeatLength) };
}
export const toolExamples = [
  { id: "calculator", name: "Calculator", source: "Expression", input: "24 × 18", result: String(24 * 18), resultLabel: "Result", action: "Calculate", detail: "Calculate without leaving the launcher." },
  { id: "translation", name: "Translation", source: "English", input: "Hello", result: "Bonjour", resultLabel: "French", action: "Translate to French", detail: "A prepared translation from English to French." },
  { id: "snippets", name: "Snippets", source: "Saved keyword", input: ";thx", result: "Thank you.", resultLabel: "Saved text", action: "Expand snippet", detail: "Type a saved keyword, then Space, to expand it." },
  { id: "ai", name: "AI profiles", source: "Draft", input: "u free tmrw", result: "Free\ntomorrow?", resultLabel: "Writing profile · sample response", action: "Rewrite with Writing profile", detail: "Choose a configured provider and model. This response is a prepared example." },
  { id: "video", name: "Video download", source: "Video link", input: "Link", result: "MP4", resultLabel: "Saved file", action: "Download video", detail: "Paste a supported video link to save it to your Mac." },
  { id: "developer", name: "Developer tools", source: "Unix timestamp", input: "1704067200", result: "2024-01-01", resultLabel: "Date, 00:00 UTC", action: "Convert timestamp", detail: "Turn a Unix timestamp into a readable date." },
] as const;
export const toolsEnd = toolsStart + toolExamples.length * toolBeatLength;
export const toolsStop = toolsStart + toolBeatLength * .8;

type ToolPoint = { x: number; y: number; size: number; accent: number };
type ToolTarget = ToolPoint & { start: ToolPoint; order: number; cursor?: number };
const snippetLines = toolExamples[2].result.split("\n");
const snippetLength = snippetLines.reduce((sum, line) => sum + line.length, 0);
const compositions = toolExamples.map(item => [tileText(item.input), tileText(item.result)]);

export function toolTargets(width: number, height: number, selected: number): ToolTarget[] {
  const mobile = width < 900;
  const center = width * (mobile ? .5 : .655);
  const baseline = height * (mobile ? .49 : .45);
  const available = width * (mobile ? .84 : .54);
  const id = toolExamples[selected].id;
  function textPoints(text: ReturnType<typeof tileText>, y: number, maxHeight: number, accent: number): ToolPoint[] {
    const cell = Math.min(available / text.width, height * maxHeight / text.height, width * (mobile ? .028 : .018));
    return text.points.map(point => ({ x: center + point.x * cell, y: y + point.y * cell, size: cell * .86, accent }));
  }
  const input = textPoints(compositions[selected][0], baseline, .20, 0);
  let output = textPoints(compositions[selected][1], baseline, id === "calculator" || id === "video" ? .28 : .23, 1);
  if (id === "developer") {
    output = textPoints(compositions[selected][1], height * .69, .1, 1);
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
  if (id === "snippets") {
    const startX = Math.max(...input.map(point => point.x)) + input[0].size * 2;
    const endX = Math.max(...output.map(point => point.x)) + output[0].size * 2;
    for (let row = -2; row <= 2; row++) targets.push({ x: endX, y: baseline + row * output[0].size, size: output[0].size * .6, accent: 1, start: { x: startX, y: baseline + row * input[0].size, size: input[0].size * .6, accent: 1 }, order: 0, cursor: row });
  }
  return targets;
}

export const toolTileCount = Math.max(...toolExamples.map((_, selected) => toolTargets(1280, 720, selected).length));

export function writeToolsTilePose(out: ShelfPose, index: number, progress: number, layout: ShelfLayout, selected: number, reveal: number, targets: ToolTarget[], previous: ToolTarget[] = targets, transition = 1) {
  if (progress <= toolsEnter) return;
  const point = targets[index];
  const from = previous[index];
  const enter = phase(progress, toolsEnter, toolsEnter + .16);
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
  const id = toolExamples[selected].id;
  let t = reveal;
  let x = point.start.x + (point.x - point.start.x) * t;
  let y = point.start.y + (point.y - point.start.y) * t;
  let z = 0;
  let ry = 0;
  let rz = 0;
  if (id === "calculator" || id === "video") {
    x = bezier(point.start.x, center, center, point.x, t);
    y = bezier(point.start.y, height * .48, height * .34, point.y, t);
    z = Math.sin(t * Math.PI) * 24;
    rz = Math.sin(t * Math.PI * 2) * .12;
  } else if (id === "translation" || id === "ai") {
    const column = (point.x / width - (width < 900 ? .08 : .385)) / (width < 900 ? .84 : .54);
    t = phase(reveal, column * .76, column * .76 + .24);
    x = point.start.x + (point.x - point.start.x) * t;
    y = point.start.y + (point.y - point.start.y) * t;
    ry = Math.sin(t * Math.PI) * Math.PI / 2;
    z = Math.sin(t * Math.PI) * 12;
  } else if (id === "snippets") {
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
      const cursorY = height * (width < 900 ? .49 : .45) + (row - (snippetLines.length - 1) / 2) * cell * 10 + point.cursor * cell * .86;
      x += (cursorX - x) * follow;
      y += (cursorY - y) * follow;
    }
  } else if (id === "developer") {
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
  out.x = x;
  out.y = y;
  out.z = z + 40 * (1 - enter);
  out.rx = -.12;
  out.ry = ry;
  out.rz = rz;
  out.sx = out.sy = scale * enter;
  out.color = (from?.accent ?? point.start.accent) * (1 - change) + (point.start.accent + (point.accent - point.start.accent) * t) * change;
}
