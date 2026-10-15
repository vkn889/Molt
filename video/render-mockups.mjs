// Renders the 0.9.2 mockups in src/Mockups092.tsx as 2x PNGs, each until two renders agree.
// Usage: node render-mockups.mjs <out-dir> [id …]
import { bundle } from "@remotion/bundler";
import { openBrowser, renderStill, selectComposition } from "@remotion/renderer";
import { execFileSync } from "node:child_process";
import { mkdirSync, renameSync, rmSync } from "node:fs";
import path from "node:path";

const [out = "out/mockups-0.9.2", ...only] = process.argv.slice(2);
const IDS = ["01-home", "02-type-to-jump", "03-focus", "04-focus-closed", "05-drop-on-molt", "06-hub-widgets", "07-add-widget", "08-menu-bar", "09-low-battery", "10-agent-needs-you", "11-settings-notch"];
const browserExecutable = process.env.REMOTION_CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const serveUrl = await bundle({ entryPoint: path.resolve("src/index.ts") });
const puppeteerInstance = await openBrowser("chrome", { browserExecutable });
mkdirSync(out, { recursive: true });
const differ = (a, b) => Number(execFileSync("python3", ["-I", path.resolve("compare-frames.py"), a, b]).toString());

for (const id of only.length ? only : IDS) {
  const inputProps = { id };
  const composition = await selectComposition({ serveUrl, id: "Mockup092", inputProps, browserExecutable, puppeteerInstance });
  const render = (output) => renderStill({ serveUrl, composition, inputProps, output, imageFormat: "png", scale: 2, browserExecutable, puppeteerInstance, overwrite: true });
  const file = path.join(out, `${id}.png`), a = `${file}.a.png`, b = `${file}.b.png`;
  for (let tries = 0; ; tries++) {
    await render(a);
    await render(b);
    if (differ(a, b) < 0.5) break;
    if (tries > 5) throw new Error(`${id} won't render the same twice`);
  }
  renameSync(a, file);
  rmSync(b);
  console.log(file);
}
await puppeteerInstance.close({ silent: true });
