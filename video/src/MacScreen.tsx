import React from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";
import { H, MenuBar, Molt, W } from "./MoltAd";

// What's on the Mac's display, minus the notch: a wallpaper, the menu bar and the Dock.

/** Wallpapers for the many-Macs scene; "photo" is the one from the real desktop. */
export const WALLPAPERS: Record<string, string> = {
  photo: "",
  dusk: "radial-gradient(120% 90% at 20% 10%, #f6b48f 0%, transparent 55%), radial-gradient(110% 90% at 85% 80%, #6d4fb3 0%, transparent 60%), linear-gradient(160deg, #2c3d7a, #8a5fa8 55%, #f09a7a)",
  sea: "radial-gradient(100% 80% at 80% 15%, #b8f0ff 0%, transparent 55%), linear-gradient(165deg, #6fc6f2, #2f6fd0 55%, #18306e)",
  mint: "radial-gradient(100% 80% at 25% 20%, #ffffff 0%, transparent 55%), linear-gradient(165deg, #d9fbe9, #8fe0bb 50%, #3fae78)",
  sunset: "radial-gradient(100% 80% at 70% 20%, #ffe3a3 0%, transparent 55%), linear-gradient(165deg, #ffc27d, #ff7468 45%, #8a3b9c)",
  graphite: "radial-gradient(90% 70% at 30% 20%, #6b707c 0%, transparent 60%), linear-gradient(165deg, #3e424b, #17181c)",
  rose: "radial-gradient(100% 80% at 30% 15%, #fff1f6 0%, transparent 55%), linear-gradient(165deg, #ffd3e3, #f39cc2 50%, #a8559a)",
  lilac: "radial-gradient(100% 80% at 75% 20%, #f3eaff 0%, transparent 55%), linear-gradient(165deg, #d8c8ff, #9f86e8 50%, #5546b8)",
};

const DOCK = ["Finder", "Safari", "Messages", "Mail", "Maps", "Photos", "FaceTime", "Notes", "Reminders", "Music", "AppStore", "Terminal", "SystemSettings", "Molt"];

export const Dock: React.FC = () => {
  const size = 62;
  return (
    <div style={{ position: "absolute", bottom: 8, left: "50%", transform: "translateX(-50%)", display: "flex", alignItems: "flex-end", gap: 6 }}>
      <div
        style={{
          position: "absolute", inset: "-8px -10px -6px", borderRadius: 26,
          background: "rgba(246,244,250,0.42)", boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.55), 0 10px 30px rgba(0,0,0,0.12)",
        }}
      />
      {DOCK.map((app, i) => (
        <div key={app} style={{ position: "relative", width: size, height: size + 8 }}>
          <Img src={staticFile(`v3/dock/${app}.png`)} style={{ width: size, height: size, display: "block" }} />
          {i === 0 || app === "Molt" || app === "Safari" ? (
            <div style={{ position: "absolute", bottom: 0, left: "50%", width: 4, height: 4, marginLeft: -2, borderRadius: 2, background: "rgba(29,29,31,0.6)" }} />
          ) : null}
        </div>
      ))}
    </div>
  );
};

/** Wallpaper, menu bar and Dock; the notch goes in `children`. */
export const Desktop: React.FC<{ wallpaper?: string; children?: React.ReactNode }> = ({ wallpaper = "photo", children }) => (
  <div style={{ position: "absolute", inset: 0, overflow: "hidden", background: "#c9b6e4" }}>
    {wallpaper === "photo" ? (
      <Img src={staticFile("ad/wallpaper.png")} style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover", objectPosition: "50% 20%" }} />
    ) : (
      <div style={{ position: "absolute", inset: 0, background: WALLPAPERS[wallpaper] }} />
    )}
    <MenuBar />
    <Dock />
    {children}
  </div>
);

// MARK: Screens for the 3D Macs

/** One screen for the many-Macs scene: a wallpaper and an open notch. */
export type ScreenDesign = { wallpaper: string; panel?: string; creature?: string };

const MINI = { w: 470, h: 230 };
const PANEL_W = 720;

export const StaticNotch: React.FC<{ design: ScreenDesign }> = ({ design }) => {
  const card = design.panel?.match(/approval|diff|question|finished/);
  const w = design.panel ? (card ? 611 : PANEL_W) : MINI.w;
  return (
    <div
      style={{
        position: "absolute", top: 0, left: "50%", width: w, transform: "translateX(-50%)", background: "#000", overflow: "hidden",
        borderBottomLeftRadius: design.panel ? 30 : 46, borderBottomRightRadius: design.panel ? 30 : 46,
        height: design.panel ? undefined : MINI.h, boxShadow: "0 18px 50px rgba(0,0,0,0.35)",
      }}
    >
      {design.panel ? (
        <Img src={staticFile(`${design.panel}.png`)} style={{ width: w, display: "block" }} />
      ) : (
        <div style={{ position: "absolute", left: "50%", top: -42, transform: "translateX(-50%)" }}>
          <Molt loop={design.creature ?? "wave"} frames={30} size={350} at={8} />
        </div>
      )}
    </div>
  );
};


const PANELS = ["v2/w1", "v2/w2", "v2/w3", "v2/w4", "v2/w5", "v2/w6", "v2/w7", "v2/w8", "v2/home", "v2/play", "v2/molting", "v2/hangout", "v2/agents", "v2/settings", "ad/usage", "ad/github"];
const CREATURES = ["fit-pumpkin", "fit-headphones", "fit-hardhat", "fit-halo", "fit-beanie", "fit-shades", "fit-santa", "fit-hat", "fit-bunny", "fit-flower", "fit-cape", "fit-backpack", "pal-ocean", "pal-sunset", "pal-violet", "love"];
const WALLS = Object.keys(WALLPAPERS);

/** Every screen design, alternating a Hub layout and a dressed-up Molt, each on its own wallpaper. */
export const DESIGNS: ScreenDesign[] = PANELS.flatMap((panel, i) => [
  { wallpaper: WALLS[(i * 3) % WALLS.length], panel },
  { wallpaper: WALLS[(i * 3 + 5) % WALLS.length], creature: CREATURES[i] },
]);

/** A full display for one 3D Mac, rendered as a still and used as its screen texture. */
export const ScreenStill: React.FC<{ index: number }> = ({ index }) => {
  const design = DESIGNS[index % DESIGNS.length];
  return (
    <AbsoluteFill style={{ width: W, height: H }}>
      <Desktop wallpaper={design.wallpaper}>
        {/* Bigger than life, so it still reads when 32 Macs share the frame. */}
        <div style={{ position: "absolute", inset: 0, transform: "scale(1.75)", transformOrigin: "50% 0" }}>
          <StaticNotch design={design} />
        </div>
      </Desktop>
    </AbsoluteFill>
  );
};

// MARK: Screens for the hero Macs in version 4

const HERO: Record<string, ScreenDesign> = {
  work: { wallpaper: "photo", creature: "work-claude" },
  agents: { wallpaper: "photo", panel: "v2/agents" },
  ...Object.fromEntries(["approval", "diff", "question", "finished"].map((s) => [s, { wallpaper: "photo", panel: `ad/${s}` }])),
  ...Object.fromEntries(["wedit", "w1", "w2", "w3", "w4", "w5", "w6", "w7", "w8"].map((s) => [s, { wallpaper: "photo", panel: `v2/${s}` }])),
};
export const HERO_SCREENS = Object.keys(HERO);

/** The display of a hero Mac, sized to that model's screen, with the notch a little larger than life. */
export const HeroScreen: React.FC<{ screen: string }> = ({ screen }) => (
  <AbsoluteFill>
    <Desktop wallpaper={HERO[screen].wallpaper}>
      <div style={{ position: "absolute", inset: 0, transform: "scale(1.6)", transformOrigin: "50% 0" }}>
        <StaticNotch design={HERO[screen]} />
      </div>
    </Desktop>
  </AbsoluteFill>
);
