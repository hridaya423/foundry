"use client";

import { useEffect, useRef } from "react";
import type { MotionValue } from "motion/react";
import type { Tile } from "../tile-motion";
import type { Rect, ShelfLayout } from "./shelf-motion";

export default function ShelfCanvas({ progress, clipboardFocus, mediaPortrait, toolSelection, toolReveal, toolTransition, toolPrevious, onModeChange }: { progress: MotionValue<number>; clipboardFocus: MotionValue<number>; mediaPortrait: MotionValue<number>; toolSelection: MotionValue<number>; toolReveal: MotionValue<number>; toolTransition: MotionValue<number>; toolPrevious: MotionValue<number>; onModeChange: (animated: boolean) => void }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const stage = canvas.parentElement!;
    const root = stage.closest<HTMLElement>(".story-shell")!;
    const hero = stage.querySelector<HTMLElement>(".story-hero")!;
    const shelf = stage.querySelector<HTMLElement>(".story-shelf")!;
    const compact = window.matchMedia("(max-width: 899px) and (max-height: 740px), (min-aspect-ratio: 2/1)");
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
    let scene: ReturnType<(typeof import("./shelf-scene"))["createShelfScene"]> | undefined;
    let disposed = false;
    let initializing = false;
    let visible = true;
    let frame = 0;

    function rect(selector: string, parent: HTMLElement = stage): Rect {
      const element = stage.querySelector<HTMLElement>(selector)!;
      const box = element.getBoundingClientRect();
      const origin = parent.getBoundingClientRect();
      return { x: box.x - origin.x, y: box.y - origin.y, width: box.width, height: box.height };
    }
    function resize() {
      if (!scene) return;
      const box = stage.getBoundingClientRect();
      const layout: ShelfLayout = {
        width: box.width, height: box.height,
        wordmark: rect(".foundry-wordmark", hero),
        palette: rect(".foundry-palette", hero),
        gate: rect("#foundry-command-1", hero),
        file: rect(".shelf-file-anchor", shelf),
        image: rect(".shelf-image-anchor", shelf),
      };
      scene.resize(layout);
      schedule();
    }
    function draw() {
      frame = 0;
      if (scene && visible && !document.hidden && !reduced.matches && !compact.matches) scene.render(progress.get(), clipboardFocus.get(), mediaPortrait.get(), toolSelection.get(), toolReveal.get(), toolTransition.get(), toolPrevious.get());
    }
    function schedule() {
      if (!frame && !disposed) frame = requestAnimationFrame(draw);
    }
    function stop() {
      cancelAnimationFrame(frame);
      frame = 0;
      scene?.dispose();
      scene = undefined;
      root.dataset.scene = "still";
      if (!disposed) onModeChange(false);
    }
    async function initialize() {
      if (reduced.matches || compact.matches) { stop(); return; }
      if (scene || initializing) return;
      initializing = true;
      try {
        const [module, response] = await Promise.all([
          import("./shelf-scene"), fetch("/assets/foundry/tile-layout.json"),
        ]);
        if (!response.ok) throw new Error("Wordmark tiles unavailable");
        const tiles: Tile[] = await response.json();
        if (disposed || reduced.matches || compact.matches) return;
        scene = module.createShelfScene(canvas!, tiles);
        root.dataset.scene = "ready";
        onModeChange(true);
        resize();
        draw();
      } catch {
        stop();
      } finally {
        initializing = false;
      }
    }
    function lost(event: Event) {
      event.preventDefault();
      stop();
    }
    const observer = new ResizeObserver(resize);
    observer.observe(stage);
    const intersection = new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; if (visible) schedule(); });
    intersection.observe(stage);
    const unsubscribe = progress.on("change", schedule);
    const unsubscribeFocus = clipboardFocus.on("change", schedule);
    const unsubscribeTool = toolSelection.on("change", schedule);
    const unsubscribeTransition = toolTransition.on("change", schedule);
    const unsubscribePrevious = toolPrevious.on("change", schedule);
    const unsubscribeReveal = toolReveal.on("change", schedule);
    const unsubscribePortrait = mediaPortrait.on("change", schedule);
    reduced.addEventListener("change", initialize);
    compact.addEventListener("change", initialize);
    document.addEventListener("visibilitychange", schedule);
    canvas.addEventListener("webglcontextlost", lost);
    void document.fonts.ready.then(() => { if (!disposed) void initialize(); });
    return () => {
      disposed = true;
      stop();
      observer.disconnect();
      intersection.disconnect();
      unsubscribe();
      unsubscribeFocus();
      unsubscribePortrait();
      unsubscribeTool();
      unsubscribeReveal();
      unsubscribeTransition();
      unsubscribePrevious();
      reduced.removeEventListener("change", initialize);
      compact.removeEventListener("change", initialize);
      document.removeEventListener("visibilitychange", schedule);
      canvas.removeEventListener("webglcontextlost", lost);
    };
  }, [progress, clipboardFocus, mediaPortrait, toolSelection, toolReveal, toolTransition, toolPrevious, onModeChange]);
  return <canvas ref={ref} className="shelf-canvas" aria-hidden="true" />;
}
