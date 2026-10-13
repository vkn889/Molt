// Renders a composition without the odd broken frame headless Chrome sometimes captures (a frame
// before an image paints, or a tiled or blank frame from the compositor).
//
// Every frame is rendered twice. Wherever the two passes disagree, the frame is rendered again
// until two renders agree, and the neighbour check in check-frames.py runs on the result.
// Then the frames and the audio are encoded together.
//
// Usage: node render-safe.mjs <composition> <out.mp4> [--gl=angle] [--audio=none]
import { bundle } from "@remotion/bundler";
import { openBrowser, renderFrames, renderMedia, renderStill, selectComposition } from "@remotion/renderer";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const [id, out, ...flags] = process.argv.slice(2);
const gl = flags.find((f) => f.startsWith("--gl="))?.slice(5) ?? null;
const withAudio = !flags.includes("--audio=none");
const work = fs.mkdtempSync(path.join(os.tmpdir(), `render-${id}-`));
const chromiumOptions = gl ? { gl } : {};
// Your installed Chrome, as in remotion.config.ts.
const browserExecutable = process.env.REMOTION_CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const common = { chromiumOptions, browserExecutable };

const serveUrl = await bundle({ entryPoint: path.resolve("src/index.ts") });
const composition = await selectComposition({ serveUrl, id, ...common });
const n = composition.durationInFrames;
const name = (dir, i) => path.join(dir, `${String(i).padStart(5, "0")}.png`);

const pass = async (dir) => {
  fs.mkdirSync(dir, { recursive: true });
  await renderFrames({
    serveUrl, composition, ...common, imageFormat: "png", outputDir: dir,
    onStart: () => {}, onFrameUpdate: () => {},
  });
  // Name the frames 00000.png, 00001.png, … in order.
  const files = fs.readdirSync(dir).filter((f) => f.endsWith(".png"))
    .sort((x, y) => Number(x.match(/(\d+)\.png$/)[1]) - Number(y.match(/(\d+)\.png$/)[1]));
  if (files.length !== n) throw new Error(`Expected ${n} frames in ${dir}, got ${files.length}`);
  files.forEach((f, i) => fs.renameSync(path.join(dir, f), path.join(dir, `_${i}`)));
  files.forEach((_, i) => fs.renameSync(path.join(dir, `_${i}`), name(dir, i)));
};

let browser = null;
const still = async (i, file) => {
  browser ??= await openBrowser("chrome", { ...common, chromiumOptions });
  await renderStill({ serveUrl, composition, ...common, puppeteerInstance: browser, frame: i, output: file, imageFormat: "png", overwrite: true });
};

// Compares two PNGs at a reduced size; returns the mean absolute difference (0–255).
const differ = (a, b) => {
  const r = execFileSync("python3", ["-I", path.resolve("compare-frames.py"), a, b]).toString().trim();
  return Number(r);
};

console.log(`${id}: ${n} frames into ${work}`);
await pass(path.join(work, "a"));
await pass(path.join(work, "b"));
const final = path.join(work, "a");

// Frames the two passes disagree on.
const listed = execFileSync("python3", ["-I", path.resolve("compare-frames.py"), "--dirs", path.join(work, "a"), path.join(work, "b")]).toString().trim();
let bad = listed ? listed.split(",").map(Number) : [];
console.log(`passes disagree on ${bad.length} frames${bad.length ? `: ${bad.join(", ")}` : ""}`);

// Neighbour check on the first pass too, for a glitch both passes happened to share.
const check = () => {
  const r = execFileSync("python3", ["-I", path.resolve("check-frames.py"), "--dir", final, "--list"]).toString().trim();
  return r ? r.split(",").map(Number) : [];
};
bad = [...new Set([...bad, ...check()])];

for (let round = 0; bad.length && round < 6; round++) {
  const still1 = path.join(work, "r1.png"), still2 = path.join(work, "r2.png");
  const left = [];
  for (const i of bad) {
    await still(i, still1);
    await still(i, still2);
    if (differ(still1, still2) < 0.5) fs.copyFileSync(still1, name(final, i));
    else left.push(i);
  }
  bad = [...new Set([...left, ...check()])];
  console.log(`round ${round + 1}: ${bad.length} frames left${bad.length ? `: ${bad.join(", ")}` : ""}`);
}
if (bad.length) throw new Error(`Frames still failing the checks: ${bad.join(", ")}`);

let audio = null;
if (withAudio) {
  audio = path.join(work, "audio.wav");
  await renderMedia({ serveUrl, composition, ...common, codec: "wav", outputLocation: audio });
}
execFileSync("ffmpeg", [
  "-v", "error", "-y", "-framerate", String(composition.fps), "-i", path.join(final, "%05d.png"),
  ...(audio ? ["-i", audio] : []),
  "-vf", "scale=out_color_matrix=bt709:out_range=tv,format=yuv420p", "-c:v", "libx264", "-crf", process.env.CRF ?? "16", "-preset", "slow",
  "-color_range", "tv", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
  ...(audio ? ["-c:a", "aac", "-b:a", "192k"] : []), "-movflags", "+faststart", out,
], { stdio: "inherit" });
await browser?.close({ silent: true });
fs.rmSync(work, { recursive: true, force: true });
console.log(`wrote ${out}`);
