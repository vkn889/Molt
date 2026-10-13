// Renders the screens of the 3D Macs as stills: the grid's 32 designs into public/v3/screens, and
// the hero Macs' displays for version 4 into public/v4/screens. Each still is rendered until two
// renders agree, so a texture never carries a half-painted frame.
import { bundle } from "@remotion/bundler";
import { openBrowser, renderStill, selectComposition } from "@remotion/renderer";
import { execFileSync } from "node:child_process";
import { mkdirSync, renameSync, rmSync } from "node:fs";
import path from "node:path";

const browserExecutable = process.env.REMOTION_CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const serveUrl = await bundle({ entryPoint: path.resolve("src/index.ts") });
const puppeteerInstance = await openBrowser("chrome", { browserExecutable });

const HERO = ["work", "agents", "approval", "diff", "question", "finished", "wedit", "w1", "w2", "w3", "w4", "w5", "w6", "w7", "w8"];
const only = process.argv[2]; // "hero" renders just the hero Macs' displays
const all = [
  ...Array.from({ length: 32 }, (_, index) => ({ id: "MacScreen", inputProps: { index }, output: `public/v3/screens/${String(index).padStart(2, "0")}.jpg` })),
  ...HERO.map((screen) => ({ id: "HeroScreenM5", inputProps: { screen }, output: `public/v4/screens/m5-${screen}.jpg` })),
  ...HERO.map((screen) => ({ id: "HeroScreenLaptop", inputProps: { screen }, output: `public/v4/screens/laptop-${screen}.jpg` })),
];
const jobs = only === "hero" ? all.filter((j) => j.id.startsWith("Hero")) : all;
mkdirSync("public/v3/screens", { recursive: true });
mkdirSync("public/v4/screens", { recursive: true });

const render = async ({ id, inputProps }, output) => {
  const composition = await selectComposition({ serveUrl, id, inputProps, browserExecutable, puppeteerInstance });
  await renderStill({ serveUrl, composition, inputProps, output, imageFormat: "jpeg", jpegQuality: 92, browserExecutable, puppeteerInstance, overwrite: true });
};
const differ = (a, b) => Number(execFileSync("python3", ["-I", path.resolve("compare-frames.py"), a, b]).toString());

for (const job of jobs) {
  const a = `${job.output}.a.jpg`, b = `${job.output}.b.jpg`;
  let tries = 0;
  for (;;) {
    await render(job, a);
    await render(job, b);
    // JPEG noise stays well under this; a missing image or panel doesn't.
    if (differ(a, b) < 0.5) break;
    if (++tries > 5) throw new Error(`${job.output} won't render the same twice`);
  }
  renameSync(a, job.output);
  rmSync(b);
  console.log(job.output);
}
await puppeteerInstance.close({ silent: true });
