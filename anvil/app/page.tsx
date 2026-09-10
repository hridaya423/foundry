import type { Metadata } from "next";
import ShelfStory from "./foundry/story/story";
import "./foundry/foundry.css";
import "./foundry/story/story.css";
import "./foundry/story/clipboard.css";
import "./foundry/story/media.css";
import "./foundry/story/tools.css";
import "./foundry/story/memory.css";
import "./foundry/story/download.css";
import { storyEnd } from "./foundry/story/download-motion";

export const metadata: Metadata = {
  title: "Foundry — Less switching. More doing.",
  description: "Convert images, find what you copied and keep videos with Foundry.",
};

export default async function Home({ searchParams }: {
  searchParams: Promise<{ inspect?: string; at?: string }>;
}) {
  const params = await searchParams;
  const at = Number(params.at ?? 0);
  return <ShelfStory inspect={params.inspect === "1"} initialProgress={Number.isFinite(at) ? Math.max(0, Math.min(storyEnd, at)) : 0} />;
}
