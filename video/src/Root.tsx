import { Composition } from "remotion";
import { MoltRelease, DURATION } from "./MoltRelease";
import { MoltAd, AD_DURATION } from "./MoltAd";
import { MoltAdV2, V2_DURATION } from "./MoltAdV2";
import { MoltAdV3, V3_DURATION } from "./MoltAdV3";
import { MoltAdV4 } from "./MoltAdV4";
import { HeroScreen, ScreenStill } from "./MacScreen";
import { Teaser, TEASER_DURATION } from "./Teaser";
import { HeroMac } from "./HeroMac";
import { GRID, GRID_CHANGES, GRID_STEPS, HERO_A, HERO_A_SCREENS, HERO_B, HERO_B_SCREENS, V4_DURATION } from "./V4Timing";
import { MacGrid, STEPS_128 } from "./MacGrid";
import { H, W } from "./MoltAd";
import { Mockup092 } from "./Mockups092";

export const Root = () => (
  <>
    <Composition id="MoltRelease" component={MoltRelease} durationInFrames={DURATION} fps={30} width={1080} height={1920} />
    <Composition id="MoltAd" component={MoltAd} durationInFrames={AD_DURATION} fps={30} width={1080} height={1920} />
    <Composition id="MoltAdV2" component={MoltAdV2} durationInFrames={V2_DURATION} fps={30} width={1080} height={1920} />
    <Composition id="MoltAdV3" component={MoltAdV3} durationInFrames={V3_DURATION} fps={30} width={1080} height={1920} />
    <Composition id="MoltAdV4" component={MoltAdV4} durationInFrames={V4_DURATION} fps={30} width={1080} height={1920} />
    <Composition id="Teaser" component={Teaser} durationInFrames={TEASER_DURATION} fps={30} width={1080} height={1920} />
    {/* Version 4's 3D shots, rendered on their own with --gl=angle and played back in the trailer. */}
    <Composition
      id="V4HeroA" component={HeroMac} durationInFrames={HERO_A[1] - HERO_A[0]} fps={30} width={1080} height={1920}
      defaultProps={{ model: "m5" as const, orbit: [-0.75, 0.6] as [number, number], screens: HERO_A_SCREENS.map((s) => ({ at: s.at - HERO_A[0], screen: s.screen })) }}
    />
    <Composition
      id="V4HeroB" component={HeroMac} durationInFrames={HERO_B[1] - HERO_B[0]} fps={30} width={1080} height={1920}
      defaultProps={{
        // This laptop's lid leans far back, so the camera stays low to face its display.
        model: "laptop" as const, orbit: [0.7, -0.55] as [number, number], pitch: [0.14, 0.04] as [number, number], drop: 0.12, screens: HERO_B_SCREENS.map((s) => ({ at: s.at - HERO_B[0], screen: s.screen })) }}
    />
    <Composition
      id="V4Grid" component={MacGrid} durationInFrames={GRID[1] - GRID[0]} fps={30} width={1080} height={1920}
      defaultProps={{
        from: 0, to: GRID[1] - GRID[0], steps: STEPS_128, stepTimes: GRID_STEPS.map((f) => f - GRID[0]),
        hits: GRID_CHANGES.map((f) => f - GRID[0]), fast: [] as number[], title: false,
      }}
    />
    {/* The displays of the two hero Macs in version 4, at each model's screen shape. */}
    <Composition id="HeroScreenM5" component={HeroScreen} durationInFrames={1} fps={30} width={1808} height={1104} defaultProps={{ screen: "work" }} />
    <Composition id="HeroScreenLaptop" component={HeroScreen} durationInFrames={1} fps={30} width={1760} height={1104} defaultProps={{ screen: "wedit" }} />
    {/* The screens of the 3D Macs; `render-screens.mjs` renders each design as a still. */}
    <Composition id="MacScreen" component={ScreenStill} durationInFrames={1} fps={30} width={W} height={H} defaultProps={{ index: 0 }} />
    {/* Mockups of 0.9.2; `render-mockups.mjs` renders each one as a still at 2x. */}
    <Composition id="Mockup092" component={Mockup092} durationInFrames={1} fps={30} width={W} height={H} defaultProps={{ id: "01-home" }} />
  </>
);
