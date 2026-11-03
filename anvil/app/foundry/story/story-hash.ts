import { downloadStart, storyEnd } from "./download-motion";
import { memorySettled, memoryStart } from "./memory-motion";
import { shelfStops } from "./shelf-motion";
import { toolsEnter, toolsStop } from "./tools-motion";

const sections = [
  { hash: "#file-shelf", start: 0.51, stop: shelfStops[1].progress },
  { hash: "#clipboard", start: 1.08, stop: 1.3 },
  { hash: "#tools", start: toolsEnter, stop: toolsStop },
  { hash: "#memory", start: memoryStart, stop: memorySettled + .1 },
  { hash: "#download", start: downloadStart, stop: storyEnd },
];

export function stopForHash(hash: string) {
  return sections.find((section) => section.hash === hash)?.stop ?? null;
}

export function hashForProgress(progress: number) {
  return sections.findLast((section) => progress >= section.start)?.hash ?? "";
}
