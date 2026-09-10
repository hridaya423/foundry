import { clipboardRibbonPoint } from "./clipboard-motion";
import { phase, type ShelfLayout, type ShelfPose } from "./shelf-motion";

export const mediaEnd = 1.9;
export const mediaItems = [
  { id: "instagram", label: "Instagram", title: "Developers, developers, developers.", creator: "History Photographed", source: "https://www.instagram.com/reel/DVuZVQiFPU4/?hl=en", poster: "history-photographed.jpg", video: "history-photographed.mp4", portrait: true, filename: "Developers.mp4" },
  { id: "youtube", label: "YouTube", title: "But what is a neural network?", creator: "3Blue1Brown", source: "https://www.youtube.com/watch?v=aircAruvnKk", poster: "neural-network.jpg", video: null, portrait: false, filename: "Neural networks.mp4" },
  { id: "x", label: "X", title: "Always be real.", creator: "A24", source: "https://www.youtube.com/watch?v=GGJSRFWALTI", poster: "holmes.jpg", video: "holmes.mp4", portrait: true, filename: "You Can See Everything.mp4" },
] as const;
export type MediaItem = (typeof mediaItems)[number];

export function writeMediaTilePose(out: ShelfPose, ribbonIndex: number, progress: number, layout: ShelfLayout, portrait: number) {
  if (progress <= 1.45 || ribbonIndex < 0) return;
  const { width, height } = layout;
  const mobile = width < 900;
  const arrive = phase(progress, 1.45, 1.73);
  const elapsed = Math.min(.25, progress - 1.45);
  const flowProgress = progress < 1.7 ? 1.45 + elapsed - elapsed * elapsed / .25 : 1.45 - (progress - 1.7);
  const point = clipboardRibbonPoint(ribbonIndex < 42 ? ribbonIndex * (1 + arrive / 7) : ribbonIndex, width, height, 1, flowProgress);
  const x = point.x / width;
  const bend = Math.sin((x + .2) * Math.PI / 1.04) * (1 - phase(x, .68, .8));
  const targetY = height * ((mobile ? .64 : .81) + (mobile ? .025 : .02) * bend * (1 - portrait * .2));
  out.x = point.x;
  out.y += (targetY - out.y) * arrive;
  out.z *= 1 - arrive;
  out.rx += (-.2 - out.rx) * arrive;
  out.ry *= 1 - arrive;
  out.rz += (Math.atan2(height * (mobile ? .025 : .02) * Math.PI / 1.04 * Math.cos((x + .2) * Math.PI / 1.04) * (1 - phase(x, .68, .8)), width) - out.rz) * arrive;
  const absorb = 1 - phase(x, mobile ? .74 : .78, mobile ? .79 : .82) * arrive;
  out.sx = out.sy = (point.size + (width * (mobile ? .021 : .016) - point.size) * arrive) / 24 * absorb;
  if (ribbonIndex >= 42) {
    const arrow = phase(progress, 1.64, 1.78);
    const cell = ribbonIndex - 42;
    const step = width * (mobile ? .027 : .021);
    const column = cell < 3 ? cell : 5 - cell;
    const direction = cell < 3 ? -1 : 1;
    const tipX = width * (mobile ? .81 : .84);
    const tipY = height * (mobile ? .64 : .81);
    out.x += (tipX - (cell === 5 ? 1.2 : column) * step - out.x) * arrow;
    out.y += (tipY + direction * column * step - out.y) * arrow;
    out.sx += (step * .8 / 24 - out.sx) * arrow;
    out.sy = out.sx;
    out.rz *= 1 - arrow;
  }
}
