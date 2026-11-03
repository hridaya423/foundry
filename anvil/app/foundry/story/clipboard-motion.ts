import { phase, type ShelfLayout, type ShelfPose } from "./shelf-motion";

export const clipboardItems = [
  { id: "meeting", kind: "text", title: "Meet at 10", value: "Meet at 10. Bring the first draft.", time: "10:14", app: "Messages" },
  { id: "coast", kind: "image", title: "Coast.jpg", value: "/assets/foundry/story/coast.jpg", time: "10:16", app: "Photos" },
  { id: "orange", kind: "color", title: "#FA6428", value: "#FA6428", time: "10:18", app: "Figma" },
  { id: "neural-network", kind: "link", title: "But what is a neural network?", value: "https://www.youtube.com/watch?v=aircAruvnKk", time: "10:21", app: "Safari" },
  { id: "draft", kind: "text", title: "Build something great.", value: "Build something great. Keep the details simple.", time: "10:24", app: "Notes" },
] as const;
export type ClipboardItem = (typeof clipboardItems)[number];

export function searchClipboard(query: string) {
  const needle = query.trim().toLowerCase();
  return clipboardItems.filter((item) => `${item.title} ${item.value} ${item.kind} ${item.app}`.toLowerCase().includes(needle));
}

export function clipboardFocus(progress: number) {
  return 4 * phase(progress, 1.2, 1.5);
}

const beltLength = clipboardItems.length;

function beltSpacing(mobile: boolean) {
  return mobile ? .79 : .3;
}

function beltPush(progress: number) {
  return 1.2 * phase(progress, 1.5, 1.58) ** 2;
}

function beltDrop(progress: number) {
  const rise = phase(progress, 1, 1.1);
  return .5 * (1 - rise * rise * (3 - 2 * rise));
}

function ribbonY(x: number, mobile: boolean) {
  return mobile ? .65 + .028 * Math.sin(x * Math.PI * 1.3) : .64 + .12 * Math.sin((x - .12) * Math.PI * 1.25);
}

function ribbonSlope(x: number, mobile: boolean) {
  return mobile ? .028 * Math.PI * 1.3 * Math.cos(x * Math.PI * 1.3) : .12 * Math.PI * 1.25 * Math.cos((x - .12) * Math.PI * 1.25);
}

function settle(t: number) {
  const back = 1.1;
  return 1 + (back + 1) * (t - 1) ** 3 + back * (t - 1) ** 2;
}

export function clipboardCardPose(index: number, belt: number, progress: number, width: number, height: number) {
  const mobile = width < 900;
  const wrapped = ((index - belt + beltLength / 2) % beltLength + beltLength) % beltLength - beltLength / 2;
  const distance = Math.min(1, Math.abs(wrapped));
  const x = (mobile ? .5 : .26) + wrapped * beltSpacing(mobile) - beltPush(progress);
  const order = Math.max(0, Math.round(wrapped) + 1);
  const land = phase(progress, 1.01 + order * .035, 1.11 + order * .035);
  const tile = width * (mobile ? .021 : .024);
  return {
    x: x * width,
    y: (ribbonY(x, mobile) + beltDrop(progress)) * height - tile * .55 - (1 - distance) * 10 - (1 - settle(land)) * height * .14,
    rotate: Math.atan2(height * ribbonSlope(x, mobile), width) * 180 / Math.PI,
    scale: 1 - distance * .08,
    opacity: Math.min(1, land * 3) * (1 - distance * .25),
    wrapped,
  };
}

function ribbonTravel(index: number, progress: number, belt: number, mobile: boolean) {
  const elapsed = Math.max(0, progress - 1);
  const head = progress <= 1 ? (progress - .875) * 14 : 1.75 + .3752 * (1 - Math.exp(-elapsed / .04)) + belt * beltSpacing(mobile) + beltPush(progress);
  return Math.max(0, head - index * 1.4 / 48);
}

export function writeClipboardTilePose(out: ShelfPose, ribbonIndex: number, progress: number, layout: ShelfLayout, belt: number) {
  if (progress <= .875) return;
  if (ribbonIndex < 0) {
    if (out.y > layout.height) return;
    const leave = phase(progress, 1, 1.06);
    out.y += layout.height * .04 * leave;
    out.sx *= 1 - leave;
    out.sy *= 1 - leave;
    return;
  }
  const mobile = layout.width < 900;
  const travel = ribbonTravel(ribbonIndex, progress, belt, mobile);
  const x = 1.2 - travel % 1.4;
  const size = layout.width * (mobile ? .021 : .024);
  const join = phase(travel, 0, .24);
  const exit = 1 - .4 * phase(progress, 1.5, 1.58);
  out.x += (x * layout.width - out.x) * join;
  out.y += ((ribbonY(x, mobile) + beltDrop(progress)) * layout.height - out.y) * join;
  out.z = -8 * Math.sin(join * Math.PI);
  out.rx = -.2 * join;
  out.ry = 0;
  out.rz = Math.atan2(layout.height * ribbonSlope(x, mobile), layout.width) * join;
  out.sx = (out.sx + (size / 24 - out.sx) * join) * exit;
  out.sy = (out.sy + (size / 24 - out.sy) * join) * exit;
}
