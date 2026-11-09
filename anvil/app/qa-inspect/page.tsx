import type { Metadata } from "next";
import ShelfStory from "../foundry/story/story";
import "../foundry/foundry.css";
import "../foundry/story/story.css";
import "../foundry/story/clipboard.css";
import "../foundry/story/tools.css";
import "../foundry/story/memory.css";
import "../foundry/story/download.css";
import { storyEnd } from "../foundry/story/download-motion";
import { formatFigure, proofFigures } from "../proof";

export const metadata: Metadata = { robots: { index: false } };

export default async function Inspect({ searchParams }: {
  searchParams: Promise<{ at?: string }>;
}) {
  const at = Number((await searchParams).at ?? 0);
  return <ShelfStory appSize={formatFigure(proofFigures().find((figure) => figure.id === "app-size")!)} inspect initialProgress={Number.isFinite(at) ? Math.max(0, Math.min(storyEnd, at)) : 0} />;
}
