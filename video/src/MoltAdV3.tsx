import React from "react";
import { AbsoluteFill, Audio, Img, Sequence, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Desktop } from "./MacScreen";
import { MacGrid } from "./MacGrid";
import { BEZEL, GRAY, H, INK, Molt, RIM, SF, W, clamp, ease } from "./MoltAd";

// Version 3: Molt wakes up in the dark, then the music comes in and every feature lands on it
// (1080 × 1920, 30 fps).
//
// The song is "Wind Garden", which moves in bars of 1.5792 s with hits on the 1st, 4th and 7th
// eighth of each bar (a 3 + 3 + 2 feel). Its first downbeat is 0.376 s in. Everything after the
// intro is placed with `hit(bar, eighth)`.

/** The frame the music starts on; before it, Molt wakes up in silence. */
const MUSIC = 205;
const BAR = 1.5792, FIRST = 0.376;
const hit = (bar: number, eighth = 0) => MUSIC + Math.round(30 * (FIRST + BAR * bar + (BAR / 8) * eighth));
const SONG_END = 62.6;
export const V3_DURATION = MUSIC + Math.round(30 * SONG_END);

type Beat = { at: number; w: number; h: number; radius: number; content: string; title?: string; sub?: string };
const FULL = { w: 720, h: 208, radius: 30 };
const CARD = { w: 611, radius: 28 };
const MINI = { w: 470, h: 230, radius: 46 };
const shot = (bar: number, content: string, title: string, sub = "", eighth = 0): Beat => ({ at: hit(bar, eighth), ...FULL, content, title, sub });

const WIDGETS = "21 widgets, your way.";
const WIDGETS_SUB = "Shortcuts, focus, music, GitHub and more.";
const BEATS: Beat[] = [
  { at: 0, ...MINI, content: "intro" },
  shot(3, "v2/home", "Your Mac, at a glance.", "Music, calendar and Mac health."),
  shot(4, "v2/play", "A pet that needs you.", "Feed it, play with it, pat it."),
  shot(10, "v2/molting", "Better with friends.", "See who's online and what they're up to."),
  shot(12, "v2/hangout", "Hang out together.", "Wave, dance and earn points."),
  { at: hit(13), ...MINI, content: "work", title: "Watches your agents.", sub: "Claude Code, Codex and more." },
  shot(14, "v2/agents", "Every agent, live.", "What's running, and a Stop button."),
  { at: hit(15), ...CARD, h: 136, content: "ad/approval", title: "Approve from the notch.", sub: "Allow, deny, or always allow." },
  { at: hit(16), ...CARD, h: 224, content: "ad/diff", title: "See every edit first." },
  { at: hit(17), ...CARD, h: 216, content: "ad/question", title: "Answer in a click." },
  { at: hit(18), ...CARD, h: 90, content: "ad/finished", title: "Know when it's done." },
  shot(19, "ad/usage", "No surprise limits.", "Claude and Codex, with a forecast."),
  shot(20, "ad/github", "Your GitHub, too.", "Streak, pull requests and checks."),
  shot(21, "v2/wedit", "Build your Hub.", "Drag, resize and add."),
  shot(22, "v2/w1", WIDGETS, WIDGETS_SUB, 0),
  shot(22, "v2/w2", WIDGETS, WIDGETS_SUB, 3),
  shot(22, "v2/w3", WIDGETS, WIDGETS_SUB, 6),
  shot(30, "v2/chat", "Chat with any model.", "On your Mac, or with your own key."),
  shot(32, "v2/lens", "Ask about your screen.", "Errors, text, images and QR codes."),
  shot(34, "v2/settings", "Tuned to you.", "Colors, accents, hover and more."),
  { at: hit(35), ...MINI, content: "wave" },
];

/** Stretches where the Mac makes way for something else. */
const STAGES = { moods: [hit(5), hit(7)], outfits: [hit(7), hit(9)], colors: [hit(9), hit(10)] } as const;
const GRID = [hit(23), hit(30)] as const;
const OFF_MAC: (readonly [number, number])[] = [[hit(5), hit(10)], GRID];
const END = hit(36);

// The intro, in frames: asleep, groggy, eyes open, a look left and right, a wave; then the camera
// pulls back while the lights come up, and the music starts as it settles.
const WAKE = { tired: 80, open: 112, left: 118, right: 140, wave: 162 };
const PAN = [168, 214] as const;

const beatAt = (frame: number) => {
  let i = 0;
  for (let j = 0; j < BEATS.length; j++) if (frame >= BEATS[j].at) i = j;
  return i;
};

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

/** Where the camera looks: a point on the screen, where it sits in the frame, and the zoom. */
const camera = (frame: number) => {
  const dark = { x: W / 2, y: 118, cy: 960, s: interpolate(frame, [0, PAN[0]], [2.25, 2.4], clamp) };
  const wide = { x: W / 2, y: H * 0.55, cy: 1040, s: 0.58 };
  const close = { x: W / 2, y: 0, cy: 880, s: 1.45 };
  const out = interpolate(frame, [PAN[0], PAN[1]], [0, 1], { ...clamp, easing: ease });
  const push = interpolate(frame, [hit(2), hit(3)], [0, 1], { ...clamp, easing: ease });
  const back = interpolate(frame, [hit(35), hit(35) + 36], [0, 1], { ...clamp, easing: ease });
  const mix = (p: typeof wide, q: typeof wide, t: number) => ({
    x: lerp(p.x, q.x, t), y: lerp(p.y, q.y, t), cy: lerp(p.cy, q.cy, t),
    // Zoom evenly: interpolate the scale on a log curve.
    s: Math.exp(lerp(Math.log(p.s), Math.log(q.s), t)),
  });
  if (frame < PAN[1]) return mix(dark, wide, out);
  if (frame < hit(35)) return mix(wide, close, push);
  return mix(close, wide, back);
};

/** 0 in the dark intro, 1 once the lights are up. */
const lightsAt = (frame: number) => interpolate(frame, [PAN[0] + 4, PAN[1]], [0, 1], { ...clamp, easing: ease });

// MARK: Text

const Title: React.FC<{ title: string; sub?: string; at: number; until: number; top?: number; gradient?: boolean }> = ({ title, sub, at, until, top = 330, gradient }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (frame < at || frame >= until) return null;
  const show = spring({ frame: frame - at, fps, config: { damping: 200, mass: 0.6 } });
  const second = spring({ frame: frame - at - 6, fps, config: { damping: 200, mass: 0.6 } });
  const out = interpolate(frame, [until - 6, until], [1, 0], clamp);
  return (
    <div style={{ position: "absolute", top, left: 50, right: 50, textAlign: "center", fontFamily: SF, opacity: out }}>
      <div
        style={{
          fontSize: 86, fontWeight: 700, letterSpacing: -2.2, lineHeight: 1.05, color: INK,
          opacity: show, transform: `translateY(${(1 - show) * 30}px)`, filter: `blur(${(1 - show) * 8}px)`,
          ...(gradient ? { background: "linear-gradient(90deg, #3fb871, #5DCC8C 40%, #7fd3e6)", WebkitBackgroundClip: "text", color: "transparent" } : {}),
        }}
      >
        {title}
      </div>
      {sub ? (
        <div style={{ marginTop: 22, fontSize: 40, fontWeight: 500, letterSpacing: -0.4, color: GRAY, opacity: second, transform: `translateY(${(1 - second) * 20}px)` }}>
          {sub}
        </div>
      ) : null}
    </div>
  );
};

/** The headline for whatever the notch is showing; a run of beats with the same title shares one. */
const MacTitle: React.FC = () => {
  const frame = useCurrentFrame();
  const i = beatAt(frame);
  const beat = BEATS[i];
  if (!beat.title) return null;
  let first = i;
  while (first > 0 && BEATS[first - 1].title === beat.title) first--;
  let last = i;
  while (last < BEATS.length - 1 && BEATS[last + 1].title === beat.title) last++;
  let until = BEATS[last + 1]?.at ?? END;
  for (const [from] of OFF_MAC) if (BEATS[first].at < from && until > from) until = from;
  return <Title title={beat.title} sub={beat.sub} at={BEATS[first].at} until={until} />;
};

// MARK: The Mac

const Content: React.FC<{ beat: Beat; local: number }> = ({ beat, local }) => {
  const creature = (node: React.ReactNode) => (
    <div style={{ position: "absolute", left: "50%", top: -42, transform: "translateX(-50%)" }}>{node}</div>
  );
  switch (beat.content) {
    case "intro": {
      const fade = interpolate(local, [0, 24], [0, 1], clamp);
      const molt = (loop: string, frames: number, at: number) => (
        <div style={{ opacity: fade }}>{creature(<Molt loop={loop} frames={frames} size={350} at={at} />)}</div>
      );
      if (local < WAKE.tired) return molt("sleep", 90, local + 20);
      if (local < WAKE.open) return molt("tired", 60, local - WAKE.tired);
      if (local < WAKE.left) return molt("look", 240, 60);
      if (local < WAKE.right) return molt("look", 240, 186 + (local - WAKE.left));
      if (local < WAKE.wave) return molt("look", 240, 207 + Math.min(20, local - WAKE.right));
      return molt("wave", 60, local - WAKE.wave);
    }
    case "wave":
      return creature(<Molt loop="wave" frames={60} size={350} />);
    case "work":
      return creature(local < 36 ? <Molt loop="work-claude" frames={60} size={350} /> : <Molt loop="alert" frames={60} size={350} at={local - 36} />);
    default:
      return (
        <Img
          src={staticFile(`${beat.content}.png`)}
          style={{ position: "absolute", top: 0, left: "50%", width: beat.w, transform: "translateX(-50%)", display: "block" }}
        />
      );
  }
};

const Island: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const i = beatAt(frame);
  const beat = BEATS[i], prev = BEATS[Math.max(0, i - 1)];
  const local = frame - beat.at;
  const grow = spring({ frame: local, fps, config: { damping: 20, stiffness: 170, mass: 0.7 } });
  const w = interpolate(grow, [0, 1], [prev.w, beat.w]);
  const h = interpolate(grow, [0, 1], [prev.h, beat.h]);
  const r = interpolate(grow, [0, 1], [prev.radius, beat.radius]);
  // The new screen fades in over the old one, which stays solid underneath, so it never dips to
  // black. A see-through creature fades the old screen out as it comes in.
  const fadeIn = interpolate(local, [0, 4], [0, 1], clamp);
  const creatureIn = !beat.content.includes("/");
  return (
    <div
      style={{
        position: "absolute", top: 0, left: "50%", width: w, height: h, transform: "translateX(-50%)",
        background: "#000", borderBottomLeftRadius: r, borderBottomRightRadius: r, overflow: "hidden",
        boxShadow: h > 60 ? "0 18px 50px rgba(0,0,0,0.35)" : "none",
      }}
    >
      {i > 0 && local < 4 ? (
        <div style={{ opacity: creatureIn ? 1 - fadeIn : 1 }}>
          <Content beat={prev} local={frame - prev.at} />
        </div>
      ) : null}
      <div style={{ opacity: i === 0 ? 1 : fadeIn }}>
        <Content beat={beat} local={local} />
      </div>
    </div>
  );
};

const MacBook: React.FC = () => {
  const frame = useCurrentFrame();
  const cam = camera(frame);
  const lights = lightsAt(frame);
  const lidW = W + 2 * BEZEL, lidH = H + 2 * BEZEL;
  return (
    <AbsoluteFill>
      <div
        style={{
          position: "absolute", left: 540 - (cam.x + BEZEL) * cam.s, top: cam.cy - (cam.y + BEZEL) * cam.s,
          width: lidW, transformOrigin: "0 0", transform: `scale(${cam.s})`,
        }}
      >
        <div
          style={{
            position: "relative", width: lidW, height: lidH, borderRadius: 44, background: `rgb(${Math.round(11 * lights)},${Math.round(11 * lights)},${Math.round(13 * lights)})`,
            boxShadow: `0 0 0 ${RIM}px rgba(185,187,192,${lights}), 0 0 0 ${RIM + 1}px rgba(141,143,149,${lights}), 0 60px 120px rgba(0,0,0,${0.18 * lights})`,
          }}
        >
          <div style={{ position: "absolute", left: BEZEL, top: BEZEL, width: W, height: H, borderRadius: 16, overflow: "hidden" }}>
            <Desktop>
              {/* The display is off until the lights come up; only Molt glows. */}
              <div style={{ position: "absolute", inset: 0, background: "#000", opacity: 1 - lights }} />
              <Island />
            </Desktop>
          </div>
        </div>
        <div style={{ position: "relative", width: lidW + 150, marginLeft: -75, height: 40, opacity: lights }}>
          <div
            style={{
              position: "absolute", inset: 0, borderRadius: "6px 6px 40px 40px / 6px 6px 30px 30px",
              background: "linear-gradient(#e3e4e8, #c4c6cb 45%, #9c9ea4)", boxShadow: "0 40px 60px rgba(0,0,0,0.16)",
            }}
          />
          <div style={{ position: "absolute", top: 0, left: "50%", width: 300, height: 13, marginLeft: -150, borderRadius: "0 0 14px 14px", background: "linear-gradient(#a7a9ae, #c8cacf)" }} />
        </div>
      </div>
    </AbsoluteFill>
  );
};

// MARK: White stage

type Item = { loop: string; frames: number; word?: string };

/** Shows each item from its own frame on, popping in as it lands. */
const Cycle: React.FC<{ from: number; to: number; times: number[]; items: Item[]; title: string; sub: string }> = ({ from, to, times, items, title, sub }) => {
  const frame = useCurrentFrame();
  if (frame < from || frame >= to) return null;
  let step = 0;
  for (let k = 0; k < times.length; k++) if (frame >= times[k]) step = k;
  const item = items[step % items.length];
  const pop = interpolate(frame - times[step], [0, 2, 5], [0.93, 1.03, 1], clamp);
  return (
    <AbsoluteFill style={{ background: "#fff" }}>
      <Title title={title} sub={sub} at={from} until={to + 1} />
      <div style={{ position: "absolute", top: 640, left: 0, right: 0, display: "flex", justifyContent: "center", transform: `scale(${pop})` }}>
        <Molt loop={item.loop} frames={item.frames} size={900} />
      </div>
      {item.word ? (
        <div style={{ position: "absolute", top: 1560, left: 0, right: 0, textAlign: "center", fontFamily: SF, fontSize: 46, fontWeight: 600, color: "#3fb871", letterSpacing: -0.5 }}>
          {item.word}
        </div>
      ) : null}
    </AbsoluteFill>
  );
};

const onHits = (bars: number[]) => bars.flatMap((bar) => [hit(bar, 0), hit(bar, 3), hit(bar, 6)]);
const onEighths = (bars: number[]) => bars.flatMap((bar) => [0, 1, 2, 3, 4, 5, 6, 7].map((e) => hit(bar, e)));

const MOODS: Item[] = [
  { loop: "eat", frames: 60, word: "Snack time" },
  { loop: "love", frames: 60, word: "Loved" },
  { loop: "happy", frames: 60, word: "Happy" },
  { loop: "pat", frames: 45, word: "Petted" },
  { loop: "celebrate", frames: 90, word: "Party" },
  { loop: "sleep", frames: 90, word: "Sleepy" },
];
const FITS: Item[] = ["pumpkin", "headphones", "hardhat", "halo", "beanie", "shades", "santa", "hat", "bunny", "flower", "cape", "backpack", "pumpkin", "halo", "santa", "shades"].map((f) => ({
  loop: `fit-${f}`, frames: 30,
}));
const COLORS: Item[] = [
  { loop: "pal-ocean", frames: 30, word: "Ocean" },
  { loop: "pal-sunset", frames: 30, word: "Sunset" },
  { loop: "pal-violet", frames: 30, word: "Violet" },
];

// MARK: Ending

const EndCard: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (frame < END - 6) return null;
  const local = frame - END;
  const bg = interpolate(local, [-6, 6], [0, 1], clamp);
  const icon = spring({ frame: local, fps, config: { damping: 14, stiffness: 120 } });
  const word = spring({ frame: local - Math.round(30 * BAR * 3 / 8), fps, config: { damping: 200 } });
  const line = spring({ frame: local - Math.round(30 * BAR * 6 / 8), fps, config: { damping: 200 } });
  return (
    <AbsoluteFill style={{ background: `rgba(255,255,255,${bg})`, alignItems: "center", fontFamily: SF }}>
      <div style={{ position: "absolute", top: 470, transform: `scale(${icon})` }}>
        <Molt loop="wave" frames={60} size={620} />
      </div>
      <div style={{ position: "absolute", top: 1110, display: "flex", alignItems: "center", gap: 26, opacity: word, transform: `translateY(${(1 - word) * 20}px)` }}>
        <Img src={staticFile("ad/app-icon.png")} style={{ width: 120, height: 120, borderRadius: 27 }} />
        <div style={{ fontSize: 132, fontWeight: 700, letterSpacing: -4, color: INK }}>Molt</div>
      </div>
      <div style={{ position: "absolute", top: 1300, fontSize: 42, fontWeight: 500, color: GRAY, opacity: line, letterSpacing: -0.4 }}>
        A little companion for your notch.
      </div>
      <div style={{ position: "absolute", top: 1560, fontSize: 30, fontWeight: 500, color: GRAY, opacity: line }}>
        For macOS 13 or later
      </div>
    </AbsoluteFill>
  );
};

export const MoltAdV3: React.FC = () => {
  const frame = useCurrentFrame();
  const offMac = OFF_MAC.some(([from, to]) => frame >= from && frame < to);
  const lights = lightsAt(frame);
  const v = Math.round(255 * lights);
  const fadeAt = MUSIC + Math.round(30 * 60.4);
  return (
    <AbsoluteFill style={{ background: `rgb(${v},${v},${v})` }}>
      <Sequence from={MUSIC} layout="none">
        <Audio src={staticFile("audio/music1.mp3")} volume={(f) => interpolate(f, [fadeAt - MUSIC, V3_DURATION - MUSIC - 1], [1, 0], clamp)} />
      </Sequence>
      {!offMac ? <MacBook /> : null}
      {!offMac ? <MacTitle /> : null}
      <Title title="Meet Molt." sub="A little companion that lives in your notch." at={hit(0)} until={hit(2, 6)} gradient />
      <Cycle from={STAGES.moods[0]} to={STAGES.moods[1]} times={onHits([5, 6])} items={MOODS} title="Full of feelings." sub="It knows when you care." />
      <Cycle from={STAGES.outfits[0]} to={STAGES.outfits[1]} times={onEighths([7, 8])} items={FITS} title="Dress it up." sub="Sixteen pieces to collect." />
      <Cycle from={STAGES.colors[0]} to={STAGES.colors[1]} times={onHits([9])} items={COLORS} title="Pick a color." sub="Sage, ocean, sunset or violet." />
      {frame >= GRID[0] && frame < GRID[1] ? (
        <MacGrid from={GRID[0]} to={GRID[1]} bar={30 * BAR} hits={onHits([23, 24, 25, 26, 27, 28])} fast={onEighths([29])} />
      ) : null}
      <EndCard />
    </AbsoluteFill>
  );
};
