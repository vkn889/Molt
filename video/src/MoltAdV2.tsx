import React from "react";
import { AbsoluteFill, Audio, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { BEZEL, GRAY, H, INK, MenuBar, Molt, NOTCH, RIM, SF, W, clamp, ease } from "./MoltAd";

// Version 2: every part of Molt in under a minute, cut to the music (1080 × 1920, 30 fps).
//
// The track runs at 100 BPM: a beat every 18 frames, starting at frame 20, and every hit in it
// falls on a 6-frame grid. Everything below is placed with `b(n)`, the frame of beat n.

const b = (n: number) => 20 + 18 * n;
export const V2_DURATION = b(89) + 30;

type Beat = { at: number; w: number; h: number; radius: number; content: string; title?: string; sub?: string; gradient?: boolean };
const FULL = { w: 720, h: 208, radius: 30 };
const CARD = { w: 611, radius: 28 };
const MINI = { w: 470, h: 230, radius: 46 };
const shot = (n: number, content: string, title: string, sub = ""): Beat => ({ at: b(n), ...FULL, content, title, sub });

const WIDGETS = "21 widgets, your way.";
const WIDGETS_SUB = "Shortcuts, focus, music, GitHub and more.";
const BEATS: Beat[] = [
  { at: 0, w: NOTCH.w, h: NOTCH.h, radius: 12, content: "none" },
  { at: b(6), ...MINI, content: "sleep" },
  { at: b(12), ...MINI, content: "wave", title: "Meet Molt.", sub: "A little companion that lives in your notch.", gradient: true },
  shot(15, "v2/home", "Your Mac, at a glance.", "Music, calendar and Mac health."),
  shot(18, "v2/play", "A pet that needs you.", "Feed it, play with it, pat it."),
  shot(32, "v2/molting", "Better with friends.", "See who's online and what they're up to."),
  shot(36, "v2/hangout", "Hang out together.", "Wave, dance and earn points."),
  shot(39, "v2/wedit", "Build your Hub.", "Drag, resize and add."),
  ...["w1", "w2", "w3", "w4", "w5", "w6", "w7", "w8"].map((w, i) => shot(41 + i, `v2/${w}`, WIDGETS, WIDGETS_SUB)),
  { at: b(49), ...MINI, content: "work", title: "Watches your agents.", sub: "Claude Code, Codex and more." },
  shot(51, "v2/agents", "Every agent, live.", "What's running, and a Stop button."),
  { at: b(53), ...CARD, h: 136, content: "ad/approval", title: "Approve from the notch.", sub: "Allow, deny, or always allow." },
  { at: b(56), ...CARD, h: 224, content: "ad/diff", title: "See every edit first." },
  { at: b(59), ...CARD, h: 216, content: "ad/question", title: "Answer in a click." },
  { at: b(62), ...CARD, h: 90, content: "ad/finished", title: "Know when it's done." },
  shot(64, "ad/usage", "No surprise limits.", "Claude and Codex, with a forecast."),
  shot(67, "ad/github", "Your GitHub, too.", "Streak, pull requests and checks."),
  shot(70, "v2/chat", "Chat with any model.", "On your Mac, or with your own key."),
  shot(74, "v2/lens", "Ask about your screen.", "Errors, text, images and QR codes."),
  shot(78, "v2/settings", "Tuned to you.", "Colors, accents, hover and more."),
  { at: b(80), w: NOTCH.w, h: NOTCH.h, radius: 12, content: "none" },
];
// Three scenes leave the Mac for a white stage.
const STAGES = { moods: [b(21), b(26)], outfits: [b(26), b(30)], colors: [b(30), b(32)] } as const;
const OFF_MAC = [b(21), b(32)] as const;
const END = b(82);

const beatAt = (frame: number) => {
  let i = 0;
  for (let j = 0; j < BEATS.length; j++) if (frame >= BEATS[j].at) i = j;
  return i;
};

/** A small kick on every beat, fading over the next few frames. */
const pulse = (frame: number) => {
  if (frame < b(12)) return 0;
  const p = (((frame - 20) % 18) + 18) % 18;
  return Math.exp(-p / 3);
};

const camera = (frame: number) => {
  const wide = { x: W / 2, y: H * 0.62, cy: 930, s: 0.54 };
  const close = { x: W / 2, y: 0, cy: 880, s: 1.45 };
  const push = interpolate(frame, [b(4), b(6)], [0, 1], { ...clamp, easing: ease });
  const back = interpolate(frame, [b(80), b(82)], [0, 1], { ...clamp, easing: ease });
  const t = push * (1 - back);
  const lean = interpolate(frame, [b(6), b(8), b(13), b(15)], [0, 1, 1, 0], { ...clamp, easing: ease });
  return {
    x: interpolate(t, [0, 1], [wide.x, close.x]),
    y: interpolate(t, [0, 1], [wide.y, close.y]),
    cy: interpolate(t, [0, 1], [wide.cy, close.cy]) + lean * 60,
    s: interpolate(t, [0, 1], [wide.s, close.s]) * (1 + lean * 0.22),
  };
};

// MARK: Text

const Title: React.FC<{ title: string; sub?: string; at: number; until: number; top?: number; gradient?: boolean }> = ({ title, sub, at, until, top = 330, gradient }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (frame < at || frame >= until) return null;
  // The headline lands on the beat; the line under it on the next hit of the grid.
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
  if (BEATS[first].at < OFF_MAC[0] && until > OFF_MAC[0]) until = OFF_MAC[0];
  return <Title title={beat.title} sub={beat.sub} at={BEATS[first].at} until={until} gradient={beat.gradient} />;
};

// MARK: The Mac

const Content: React.FC<{ beat: Beat; local: number }> = ({ beat, local }) => {
  const creature = (node: React.ReactNode) => (
    <div style={{ position: "absolute", left: "50%", top: -42, transform: "translateX(-50%)" }}>{node}</div>
  );
  switch (beat.content) {
    case "sleep": {
      // Asleep for two beats, groggy for two, then eyes open: a look left, a look right.
      if (local < 36) return creature(<Molt loop="sleep" frames={90} size={350} at={local + 20} />);
      if (local < 66) return creature(<Molt loop="tired" frames={60} size={350} at={local} />);
      if (local < 72) return creature(<Molt loop="look" frames={240} size={350} at={60} />);
      if (local < 90) return creature(<Molt loop="look" frames={240} size={350} at={188 + (local - 72)} />);
      return creature(<Molt loop="look" frames={240} size={350} at={208 + Math.min(18, local - 90)} />);
    }
    case "wave":
      return creature(<Molt loop="wave" frames={60} size={350} />);
    case "work":
      return creature(local < 18 ? <Molt loop="work-claude" frames={60} size={350} /> : <Molt loop="alert" frames={60} size={350} at={local - 18} />);
    case "none":
      return null;
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
  const grow = spring({ frame: local, fps, config: { damping: 15, stiffness: 140, mass: 0.8 } });
  const w = interpolate(grow, [0, 1], [prev.w, beat.w]);
  const h = interpolate(grow, [0, 1], [prev.h, beat.h]);
  const r = interpolate(grow, [0, 1], [prev.radius, beat.radius]);
  const fadeIn = interpolate(local, [0, 6], [0, 1], clamp);
  const fadeOut = interpolate(local, [0, 6], [1, 0], clamp);
  const keep = prev.content === "sleep" && beat.content === "wave";
  const kick = beat.content === "none" ? 0 : pulse(frame);
  return (
    <div
      style={{
        position: "absolute", top: 0, left: "50%", width: w, height: h, transform: `translateX(-50%) scale(${1 + 0.02 * kick})`,
        transformOrigin: "50% 0", background: "#000", borderBottomLeftRadius: r, borderBottomRightRadius: r, overflow: "hidden",
        boxShadow: h > 60 ? "0 18px 50px rgba(0,0,0,0.35)" : "none",
      }}
    >
      <div style={{ position: "absolute", top: 13, left: "50%", width: 8, height: 8, marginLeft: -4, borderRadius: 4, background: "#1a1c22", boxShadow: "inset 0 0 0 2px #0d0e12" }} />
      {i > 0 && !keep && local < 6 ? <div style={{ opacity: fadeOut }}><Content beat={prev} local={frame - prev.at} /></div> : null}
      <div style={{ opacity: keep ? 1 : fadeIn }}>
        <Content beat={beat} local={local} />
      </div>
    </div>
  );
};

const MacBook: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const cam = camera(frame);
  // Lands on the first beat.
  const rise = spring({ frame, fps, config: { damping: 20, stiffness: 90 }, durationInFrames: 20 });
  const lidW = W + 2 * BEZEL, lidH = H + 2 * BEZEL;
  return (
    <AbsoluteFill style={{ perspective: frame < b(1) ? 2600 : undefined }}>
      <div
        style={{
          position: "absolute", left: 540 - (cam.x + BEZEL) * cam.s, top: cam.cy - (cam.y + BEZEL) * cam.s,
          width: lidW, transformOrigin: "0 0",
          // Flat once it has landed: 3D layers can drop children in headless Chrome.
          transform: rise > 0.995 ? `scale(${cam.s})` : `scale(${cam.s}) translateY(${(1 - rise) * 260}px) rotateX(${(1 - rise) * 14}deg)`,
          opacity: interpolate(rise, [0, 0.4], [0, 1], clamp),
        }}
      >
        <div
          style={{
            position: "relative", width: lidW, height: lidH, borderRadius: 44, background: "#0b0b0d",
            boxShadow: `0 0 0 ${RIM}px #b9bbc0, 0 0 0 ${RIM + 1}px #8d8f95, 0 60px 120px rgba(0,0,0,0.18)`,
          }}
        >
          <div style={{ position: "absolute", left: BEZEL, top: BEZEL, width: W, height: H, borderRadius: 16, overflow: "hidden", background: "#c9b6e4" }}>
            <Img src={staticFile("ad/wallpaper.png")} style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover", objectPosition: "50% 20%" }} />
            <MenuBar />
            <Island />
          </div>
        </div>
        <div style={{ position: "relative", width: lidW + 150, marginLeft: -75, height: 40 }}>
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

/** Cycles through Molt loops, `every` frames each, popping on each change. */
const Cycle: React.FC<{ from: number; to: number; every: number; items: { loop: string; frames: number; word?: string }[]; title: string; sub: string }> = ({
  from, to, every, items, title, sub,
}) => {
  const frame = useCurrentFrame();
  if (frame < from || frame >= to) return null;
  const local = frame - from;
  const step = Math.min(items.length - 1, Math.floor(local / every));
  const item = items[step];
  const pop = interpolate(local - step * every, [0, 2, 5], [0.92, 1.04, 1], clamp);
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

const MOODS = [
  { loop: "eat", frames: 60, word: "Snack time" },
  { loop: "love", frames: 60, word: "Loved" },
  { loop: "happy", frames: 60, word: "Happy" },
  { loop: "celebrate", frames: 90, word: "Party" },
  { loop: "sleep", frames: 90, word: "Sleepy" },
];
const FITS = ["pumpkin", "headphones", "hardhat", "halo", "beanie", "shades", "santa", "hat", "bunny", "flower", "cape", "backpack"].map((f) => ({ loop: `fit-${f}`, frames: 30 }));
const COLORS = [
  { loop: "wave", frames: 60, word: "Sage" },
  { loop: "pal-ocean", frames: 30, word: "Ocean" },
  { loop: "pal-sunset", frames: 30, word: "Sunset" },
  { loop: "pal-violet", frames: 30, word: "Violet" },
];

// MARK: Opening and ending

const Opening: React.FC = () => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [b(0), b(0) + 6, b(4) - 6, b(4)], [0, 1, 1, 0], clamp);
  const y = interpolate(frame, [b(0), b(0) + 12], [24, 0], { ...clamp, easing: ease });
  return (
    <div style={{ position: "absolute", top: 300, left: 0, right: 0, textAlign: "center", fontFamily: SF, fontSize: 86, fontWeight: 700, letterSpacing: -2.2, color: INK, opacity, transform: `translateY(${y}px)` }}>
      It's just a notch.
    </div>
  );
};

const EndCard: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  if (frame < END - 6) return null;
  const local = frame - END;
  const bg = interpolate(local, [-6, 6], [0, 1], clamp);
  const icon = spring({ frame: local, fps, config: { damping: 14, stiffness: 120 } });
  const word = spring({ frame: local - 18, fps, config: { damping: 200 } });
  const line = spring({ frame: local - 36, fps, config: { damping: 200 } });
  return (
    <AbsoluteFill style={{ background: `rgba(255,255,255,${bg})`, alignItems: "center", fontFamily: SF }}>
      <div style={{ position: "absolute", top: 470, transform: `scale(${icon * (1 + 0.025 * pulse(frame))})` }}>
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

export const MoltAdV2: React.FC = () => {
  const frame = useCurrentFrame();
  const offMac = frame >= OFF_MAC[0] && frame < OFF_MAC[1];
  const flash = Math.max(...OFF_MAC.map((at) => interpolate(frame, [at - 4, at, at + 5], [0, 1, 0], clamp)));
  return (
    <AbsoluteFill style={{ background: "#fff" }}>
      <Audio
        src={staticFile("audio/music.mp3")}
        volume={(f) => interpolate(f, [0, 4, V2_DURATION - 45, V2_DURATION - 1], [0, 1, 1, 0], clamp)}
      />
      {!offMac ? <MacBook /> : null}
      {!offMac ? <MacTitle /> : null}
      <Opening />
      <Cycle from={STAGES.moods[0]} to={STAGES.moods[1]} every={18} items={MOODS} title="Full of feelings." sub="It knows when you care." />
      <Cycle from={STAGES.outfits[0]} to={STAGES.outfits[1]} every={6} items={FITS} title="Dress it up." sub="Sixteen pieces to collect." />
      <Cycle from={STAGES.colors[0]} to={STAGES.colors[1]} every={9} items={COLORS} title="Make it yours." sub="Pick Molt's color." />
      <EndCard />
      <AbsoluteFill style={{ background: "#fff", opacity: flash, pointerEvents: "none" }} />
    </AbsoluteFill>
  );
};
