import React, { useLayoutEffect } from "react";
import { useThree } from "@react-three/fiber";
import { continueRender } from "remotion";

/**
 * Paints the 3D canvas after every update. While rendering, ThreeCanvas only paints when the
 * frame number changes, so a model or texture that finishes loading later (or a screen swapped
 * between frames) would be missing from the captured frame. Put it last inside the canvas; once
 * `ready`, it releases the delayRender `handle` after the first paint that includes everything.
 */
export const Painter: React.FC<{ ready: boolean; handle: number }> = ({ ready, handle }) => {
  const { advance } = useThree();
  useLayoutEffect(() => {
    advance(performance.now());
    if (ready) continueRender(handle);
  });
  return null;
};
