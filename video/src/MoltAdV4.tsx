import React from "react";
import { AbsoluteFill, Audio, Easing, Img, OffthreadVideo, Sequence, interpolate, random, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Desktop } from "./MacScreen";
import { BEZEL, GRAY, H, INK, Molt, RIM, SF, W, clamp, ease } from "./MoltAd";
import {
  BEAT, END, GRID, GRID_STEPS, HERO_A, HERO_A_SCREENS, HERO_B, HERO_B_SCREENS, MUSIC, V4_DURATION, hit,
} from "./V4Timing";

// Version 4: Molt wakes up in space and flies home to the notch; "It's Just a Notch, Until Molt."
// brings the music in, and every feature lands on the beat (1080 × 1920, 30 fps).
//
// The 3D shots (two hero Macs and the wall of 128) are rendered on their own and played back
// here from public/v4/clips; this composition draws everything else, titles included.

type Beat = { at: number; w: number; h: number; radius: number; content: string; title?: string; sub?: string };
const FULL = { w: 720, h: 208, radius: 30 };
const MINI = { w: 470, h: 230, radius: 46 };
const shot = (bar: number, content: string, title: string, sub = ""): Beat => ({ at: hit(bar), ...FULL, content, title, sub });

const BEATS: Beat[] = [
  { at: 0, ...MINI, content: "intro" },
  shot(2, "v2/home", "Your Mac, at a glance.", "Music, calendar and Mac health."),
  shot(3, "v2/play", "A pet that needs you.", "Feed it, play with it, pat it."),
  shot(9, "v2/molting", "Better with friends.", "See who's online and what they're up to."),
  shot(10, "v2/hangout", "Hang out together.", "Wave, dance and earn points."),
  shot(14, "ad/usage", "No surprise limits.", "Claude and Codex, with a forecast."),
  shot(15, "ad/github", "Your GitHub, too.", "Streak, pull requests and checks."),
  shot(24, "v2/chat", "Chat with any model.", "On your Mac, or with your own key."),
  shot(25, "v2/lens", "Ask about your screen.", "Errors, text, images and QR codes."),
  shot(26, "v2/settings", "Tuned to you.", "Colors, accents, hover and more."),
  { at: hit(27), ...MINI, content: "wave" },
];

/** Stretches where the Mac makes way: the white stage, and the 3D shots. */
const STAGES = { moods: [hit(4), hit(6)], outfits: [hit(6), hit(8)], colors: [hit(8), hit(9)] } as const;
const OFF_MAC: (readonly [number, number])[] = [[hit(4), hit(9)], HERO_A, [HERO_B[0], GRID[1]]];

// MARK: The intro

/** Molt in space: asleep, waking, a look around, then up and away. */
const SPACE = { tired: 70, look: 100, left: 106, right: 126, ready: 148, launch: 160, cut: 172 };
/** Home: Molt flies up into the notch in the dark, settles and waves; then the lights come up. */
const HOME = { land: 194, wave: 200 };
const PAN = [214, 262] as const;
const LINE_1 = 268;

const beatAt = (frame: number) => {
  let i = 0;
  for (let j = 0; j < BEATS.length; j++) if (frame >= BEATS[j].at) i = j;
  return i;
};

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

/** Where the camera looks: a point on the screen, where it sits in the frame, and the zoom. */
const camera = (frame: number) => {
  const dark = { x: W / 2, y: 118, cy: 960, s: interpolate(frame, [SPACE.cut, PAN[0]], [2.3, 2.4], clamp) };
  const wide = { x: W / 2, y: H * 0.55, cy: 1040, s: 0.58 };
  const close = { x: W / 2, y: 0, cy: 880, s: 1.45 };
  const out = interpolate(frame, [PAN[0], PAN[1]], [0, 1], { ...clamp, easing: ease });
  const push = interpolate(frame, [hit(1, 2), hit(2)], [0, 1], { ...clamp, easing: ease });
  const back = interpolate(frame, [hit(27), hit(27) + 36], [0, 1], { ...clamp, easing: ease });
  const mix = (p: typeof wide, q: typeof wide, t: number) => ({
    x: lerp(p.x, q.x, t), y: lerp(p.y, q.y, t), cy: lerp(p.cy, q.cy, t),
    s: Math.exp(lerp(Math.log(p.s), Math.log(q.s), t)),
  });
  if (frame < PAN[1]) return mix(dark, wide, out);
  if (frame < hit(27)) return mix(wide, close, push);
  return mix(close, wide, back);
};

/** 0 in the dark, 1 once the lights are up. */
const lightsAt = (frame: number) => interpolate(frame, [PAN[0] + 4, PAN[1]], [0, 1], { ...clamp, easing: ease });

/** Stars at fixed places, in three depths; they streak when Molt takes off. */
const STARS = Array.from({ length: 220 }, (_, i) => ({
  x: random(`x${i}`) * 1080, y: random(`y${i}`) * 1920, depth: 0.35 + 0.65 * random(`d${i}`) ** 2,
  size: 1.5 + 3 * random(`s${i}`), phase: random(`p${i}`) * Math.PI * 2,
}));

const Stars: React.FC<{ frame: number; opacity: number }> = ({ frame, opacity }) => {
  // How far the sky has moved down past us, and how fast, as Molt flies up.
  const travel = interpolate(frame, [SPACE.launch - 4, SPACE.cut + 16], [0, 1], { ...clamp, easing: Easing.in(Easing.cubic) }) * 5200;
  const speed = interpolate(frame, [SPACE.launch - 4, SPACE.cut, SPACE.cut + 16], [0, 1, 0.4], clamp);
  return (
    <AbsoluteFill style={{ opacity }}>
      {STARS.map((s, i) => {
        const y = (((s.y + frame * 0.6 * s.depth + travel * s.depth) % 1920) + 1920) % 1920;
        const streak = 1 + speed * 70 * s.depth;
        const twinkle = 0.55 + 0.45 * Math.sin(frame / 14 + s.phase);
        return (
          <div
            key={i}
            style={{
              position: "absolute", left: s.x, top: y - (streak * s.size) / 2, width: s.size, height: s.size * streak, borderRadius: s.size,
              background: "#fff", opacity: twinkle * (0.35 + 0.65 * s.depth),
            }}
          />
        );
      })}
    </AbsoluteFill>
  );
};

const Space: React.FC = () => {
  const frame = useCurrentFrame();
  if (frame >= SPACE.cut) return null;
  const fade = interpolate(frame, [0, 30], [0, 1], clamp);
  const bob = Math.sin(frame / 22) * 14;
  // A crouch, then up and out of the top of the frame.
  const crouch = interpolate(frame, [SPACE.ready, SPACE.launch], [0, 1], clamp);
  const fly = interpolate(frame, [SPACE.launch, SPACE.cut], [0, 1], { ...clamp, easing: Easing.in(Easing.cubic) });
  const sy = frame < SPACE.launch ? 1 - 0.14 * crouch : interpolate(fly, [0, 0.3, 1], [0.86, 1.25, 1.35]);
  const sx = 2 - sy;
  const loop =
    frame < SPACE.tired ? { name: "sleep", n: 90, at: frame + 20 }
    : frame < SPACE.look ? { name: "tired", n: 60, at: frame - SPACE.tired }
    : frame < SPACE.left ? { name: "look", n: 240, at: 60 }
    : frame < SPACE.right ? { name: "look", n: 240, at: 186 + (frame - SPACE.left) }
    : frame < SPACE.ready ? { name: "look", n: 240, at: 207 + Math.min(20, frame - SPACE.right) }
    : { name: "happy", n: 60, at: frame - SPACE.ready };
  return (
    <AbsoluteFill style={{ background: "#000" }}>
      <Stars frame={frame} opacity={fade} />
      <div
        style={{
          position: "absolute", left: 540 - 410, top: 960 - 410 + bob - fly * 1500, width: 820, height: 820, opacity: fade,
          transform: `scale(${sx}, ${sy})`, transformOrigin: "50% 75%",
        }}
      >
        <Molt loop={loop.name} frames={loop.n} size={820} at={loop.at} />
      </div>
    </AbsoluteFill>
  );
};

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

/** "It's Just a Notch," in the quiet, then "Until Molt." as the music comes in. */
const Opening: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const until = hit(1, 3);
  if (frame < LINE_1 || frame >= until) return null;
  const first = spring({ frame: frame - LINE_1, fps, config: { damping: 200, mass: 0.6 } });
  const second = spring({ frame: frame - hit(0), fps, config: { damping: 200, mass: 0.6 } });
  const out = interpolate(frame, [until - 6, until], [1, 0], clamp);
  const line = (show: number): React.CSSProperties => ({
    fontSize: 92, fontWeight: 700, letterSpacing: -2.4, lineHeight: 1.08,
    opacity: show, transform: `translateY(${(1 - show) * 30}px)`, filter: `blur(${(1 - show) * 8}px)`,
  });
  return (
    <div style={{ position: "absolute", top: 250, left: 40, right: 40, textAlign: "center", fontFamily: SF, opacity: out }}>
      <div style={{ ...line(first), color: INK }}>It's Just a Notch,</div>
      <div style={{ ...line(frame >= hit(0) ? second : 0), background: "linear-gradient(90deg, #3fb871, #5DCC8C 40%, #7fd3e6)", WebkitBackgroundClip: "text", color: "transparent" }}>
        Until Molt.
      </div>
    </div>
  );
};

/** The headline for whatever the notch is showing. */
const MacTitle: React.FC = () => {
  const frame = useCurrentFrame();
  const i = beatAt(frame);
  const beat = BEATS[i];
  if (!beat.title) return null;
  let until = BEATS[i + 1]?.at ?? END;
  for (const [from] of OFF_MAC) if (beat.at < from && until > from) until = from;
  return <Title title={beat.title} sub={beat.sub} at={beat.at} until={until} />;
};

/** Headlines over a 3D shot; a run of screens with the same title shares one. */
const ShotTitles: React.FC<{ screens: { at: number; title: string; sub: string }[]; to: number }> = ({ screens, to }) => {
  const frame = useCurrentFrame();
  let i = -1;
  for (let j = 0; j < screens.length; j++) if (frame >= screens[j].at) i = j;
  if (i < 0 || frame >= to) return null;
  let first = i;
  while (first > 0 && screens[first - 1].title === screens[i].title) first--;
  let last = i;
  while (last < screens.length - 1 && screens[last + 1].title === screens[i].title) last++;
  return <Title title={screens[i].title} sub={screens[i].sub} at={screens[first].at} until={screens[last + 1]?.at ?? to} top={300} />;
};

// MARK: The Mac

const Content: React.FC<{ beat: Beat; local: number; frame: number }> = ({ beat, local, frame }) => {
  const creature = (node: React.ReactNode, lift = 0) => (
    <div style={{ position: "absolute", left: "50%", top: -42 + lift, transform: "translateX(-50%)" }}>{node}</div>
  );
  switch (beat.content) {
    case "intro": {
      // Flying up from below into the notch, then a settle and a wave.
      const arrive = spring({ frame: frame - SPACE.cut, fps: 30, config: { damping: 15, stiffness: 90, mass: 0.7 } });
      const lift = (1 - arrive) * 640;
      const stretch = interpolate(frame, [SPACE.cut, SPACE.cut + 10, HOME.land], [1.3, 1.15, 1], clamp);
      const molt = (loop: string, frames: number, at: number) =>
        creature(
          <div style={{ transform: `scale(${2 - stretch}, ${stretch})`, transformOrigin: "50% 70%" }}>
            <Molt loop={loop} frames={frames} size={350} at={at} />
          </div>,
          lift,
        );
      if (frame < HOME.wave) return molt("happy", 60, frame - SPACE.cut);
      return molt("wave", 300, frame - HOME.wave);
    }
    case "wave":
      return creature(<Molt loop="wave" frames={300} size={350} at={local} />);
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
  // Coming back from a stage or a 3D shot, the screen is simply there: no transition from what
  // the notch showed before the cut away.
  const returning = OFF_MAC.some(([from]) => from > prev.at && from <= beat.at);
  const grow = returning ? 1 : spring({ frame: local, fps, config: { damping: 20, stiffness: 170, mass: 0.7 } });
  const w = interpolate(grow, [0, 1], [prev.w, beat.w]);
  const h = interpolate(grow, [0, 1], [prev.h, beat.h]);
  const r = interpolate(grow, [0, 1], [prev.radius, beat.radius]);
  // The new screen fades in over the old one, which stays solid underneath, so it never dips to
  // black. A see-through creature fades the old screen out as it comes in.
  const fadeIn = returning ? 1 : interpolate(local, [0, 4], [0, 1], clamp);
  const creatureIn = !beat.content.includes("/");
  return (
    <div
      style={{
        position: "absolute", top: 0, left: "50%", width: w, height: h, transform: "translateX(-50%)",
        background: "#000", borderBottomLeftRadius: r, borderBottomRightRadius: r,
        // Molt flies in from below the island on the way home.
        overflow: beat.content === "intro" ? "visible" : "hidden",
        boxShadow: h > 60 ? "0 18px 50px rgba(0,0,0,0.35)" : "none",
      }}
    >
      {i > 0 && local < 4 && !returning ? (
        <div style={{ opacity: creatureIn ? 1 - fadeIn : 1 }}>
          <Content beat={prev} local={frame - prev.at} frame={frame} />
        </div>
      ) : null}
      <div style={{ opacity: i === 0 ? 1 : fadeIn }}>
        <Content beat={beat} local={local} frame={frame} />
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
            {/* The display is off until the lights come up; only Molt glows. In the dark there's no
                desktop under the black at all, so none of its edges can show through. */}
            {lights > 0 ? (
              <Desktop>
                <div style={{ position: "absolute", inset: 0, background: "#000", opacity: 1 - lights }} />
                <Island />
              </Desktop>
            ) : (
              <div style={{ position: "absolute", inset: 0, background: "#000" }}>
                <Island />
              </div>
            )}
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
        {/* From its own first frame, so a loop never wraps (and jumps) mid-shot. */}
        <Molt loop={item.loop} frames={item.frames} size={900} at={frame - times[step]} />
      </div>
      {item.word ? (
        <div style={{ position: "absolute", top: 1560, left: 0, right: 0, textAlign: "center", fontFamily: SF, fontSize: 46, fontWeight: 600, color: "#3fb871", letterSpacing: -0.5 }}>
          {item.word}
        </div>
      ) : null}
    </AbsoluteFill>
  );
};

const onBeats = (bars: number[]) => bars.flatMap((bar) => [0, 1, 2, 3].map((b) => hit(bar, b)));
const onEighths = (bars: number[]) => bars.flatMap((bar) => [0, 1, 2, 3, 4, 5, 6, 7].map((e) => hit(bar, e / 2)));

const MOODS: Item[] = [
  { loop: "eat", frames: 60, word: "Snack time" },
  { loop: "love", frames: 60, word: "Loved" },
  { loop: "happy", frames: 60, word: "Happy" },
  { loop: "pat", frames: 45, word: "Petted" },
  { loop: "celebrate", frames: 90, word: "Party" },
  { loop: "worried", frames: 60, word: "Worried" },
  { loop: "sleep", frames: 90, word: "Sleepy" },
  { loop: "wave", frames: 60, word: "Hi!" },
];
const FITS: Item[] = ["pumpkin", "headphones", "hardhat", "halo", "beanie", "shades", "santa", "hat", "bunny", "flower", "cape", "backpack", "pumpkin", "halo", "santa", "shades"].map((f) => ({
  loop: `fit-${f}`, frames: 30,
}));
const COLORS: Item[] = [
  { loop: "pal-ocean", frames: 30, word: "Ocean" },
  { loop: "pal-sunset", frames: 30, word: "Sunset" },
  { loop: "pal-violet", frames: 30, word: "Violet" },
  { loop: "wave", frames: 60, word: "Sage" },
];

// MARK: The 3D shots

const Clip: React.FC<{ range: readonly [number, number]; src: string }> = ({ range, src }) => (
  <Sequence from={range[0]} durationInFrames={range[1] - range[0]} layout="none">
    <AbsoluteFill>
      <OffthreadVideo src={staticFile(src)} muted />
    </AbsoluteFill>
  </Sequence>
);

// MARK: Ending

const EndCard: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (frame < END - 6) return null;
  const local = frame - END;
  const bg = interpolate(local, [-6, 6], [0, 1], clamp);
  const icon = spring({ frame: local, fps, config: { damping: 14, stiffness: 120 } });
  const word = spring({ frame: local - Math.round(BEAT), fps, config: { damping: 200 } });
  const line = spring({ frame: local - Math.round(2 * BEAT), fps, config: { damping: 200 } });
  return (
    <AbsoluteFill style={{ background: `rgba(255,255,255,${bg})`, alignItems: "center", fontFamily: SF }}>
      <div style={{ position: "absolute", top: 470, transform: `scale(${icon})` }}>
        <Molt loop="wave" frames={300} size={620} at={Math.max(0, local)} />
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

export const MoltAdV4: React.FC = () => {
  const frame = useCurrentFrame();
  const offMac = OFF_MAC.some(([from, to]) => frame >= from && frame < to);
  const v = Math.round(255 * lightsAt(frame));
  const fadeAt = hit(29);
  return (
    <AbsoluteFill style={{ background: `rgb(${v},${v},${v})` }}>
      {/* Space, the woosh as Molt flies up (its peak is 0.55 s in), then the song. */}
      <Audio src={staticFile("v4/audio/space.wav")} volume={(f) => interpolate(f, [0, 30, SPACE.cut, PAN[1]], [0, 0.5, 0.5, 0], clamp)} />
      <Sequence from={SPACE.cut - 4 - 16} layout="none">
        <Audio src={staticFile("v4/audio/woosh.wav")} volume={0.9} />
      </Sequence>
      <Sequence from={MUSIC} layout="none">
        <Audio src={staticFile("v4/audio/music.mp3")} volume={(f) => interpolate(f, [fadeAt - MUSIC, V4_DURATION - MUSIC - 1], [1, 0], clamp)} />
      </Sequence>

      {frame >= SPACE.cut && !offMac ? <MacBook /> : null}
      {!offMac && frame >= PAN[1] ? <MacTitle /> : null}
      <Opening />
      <Space />
      {/* The stars streak on into the dark for a moment as Molt arrives home. */}
      {frame >= SPACE.cut && frame < SPACE.cut + 16 ? <Stars frame={frame} opacity={interpolate(frame, [SPACE.cut, SPACE.cut + 16], [1, 0], clamp)} /> : null}

      <Cycle from={STAGES.moods[0]} to={STAGES.moods[1]} times={onBeats([4, 5])} items={MOODS} title="Full of feelings." sub="It knows when you care." />
      <Cycle from={STAGES.outfits[0]} to={STAGES.outfits[1]} times={onEighths([6, 7])} items={FITS} title="Dress it up." sub="Sixteen pieces to collect." />
      <Cycle from={STAGES.colors[0]} to={STAGES.colors[1]} times={onBeats([8])} items={COLORS} title="Pick a color." sub="Sage, ocean, sunset or violet." />

      <Clip range={HERO_A} src="v4/clips/hero-a.mp4" />
      <ShotTitles screens={HERO_A_SCREENS} to={HERO_A[1]} />
      <Clip range={HERO_B} src="v4/clips/hero-b.mp4" />
      <ShotTitles screens={HERO_B_SCREENS} to={HERO_B[1]} />
      <Clip range={GRID} src="v4/clips/grid.mp4" />
      <Title title="Make it yours." sub="Every Hub, outfit and color." at={GRID[0]} until={GRID_STEPS[3]} top={250} />

      <EndCard />
    </AbsoluteFill>
  );
};
