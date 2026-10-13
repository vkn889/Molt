import React from "react";
import { AbsoluteFill, Easing, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";

// An Apple-style tour of everything Molt does, for Reels, Shorts and TikTok (1080 × 1920, 30 fps).

export const SF = '"SF Pro Display", -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif';
export const INK = "#1d1d1f";
export const GRAY = "#86868b";
export const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
export const ease = Easing.bezier(0.65, 0, 0.35, 1);

// The Mac is drawn in screen points: a 1728 × 1117 display, like a 16-inch MacBook Pro.
export const W = 1728, H = 1117, BEZEL = 26, RIM = 5, MENU = 34;
export const NOTCH = { w: 190, h: MENU };

export const AD_DURATION = 1700;

/** One of Molt's rendered animation loops. `from` picks a fixed stretch of a loop instead. */
export const Molt: React.FC<{ loop: string; frames: number; size: number; at?: number; style?: React.CSSProperties }> = ({ loop, frames, size, at, style }) => {
  const frame = useCurrentFrame();
  const n = at ?? frame;
  const index = String(((Math.floor(n) % frames) + frames) % frames).padStart(4, "0");
  return <Img src={staticFile(`molt/${loop}/frame-${index}.png`)} style={{ width: size, height: size, imageRendering: "pixelated", display: "block", ...style }} />;
};

// MARK: Story

/** What the notch shows, beat by beat: its size in points and what's inside. */
type Beat = { at: number; w: number; h: number; radius: number; content: string; title?: string; sub?: string; gradient?: boolean };
const BEATS: Beat[] = [
  { at: 0, w: NOTCH.w, h: NOTCH.h, radius: 12, content: "none" },
  { at: 160, w: 470, h: 230, radius: 46, content: "sleep" },
  { at: 290, w: 470, h: 230, radius: 46, content: "wave", title: "Meet Molt.", sub: "A little companion that lives in your notch.", gradient: true },
  { at: 380, w: 720, h: 208, radius: 30, content: "home", title: "Your Mac, at a glance.", sub: "Music, calendar and Mac health." },
  { at: 480, w: 720, h: 208, radius: 30, content: "play", title: "A pet that needs you.", sub: "Feed it, play with it, pat it." },
  { at: 790, w: 720, h: 208, radius: 30, content: "wardrobe", title: "Earn every piece.", sub: "By caring, coding and keeping your streak." },
  { at: 880, w: 470, h: 230, radius: 46, content: "work", title: "Watches your agents.", sub: "Claude Code, Codex and more." },
  { at: 960, w: 611, h: 136, radius: 28, content: "approval", title: "Approve from the notch.", sub: "Allow, deny, or always allow." },
  { at: 1050, w: 611, h: 224, radius: 28, content: "diff", title: "See every edit first.", sub: "" },
  { at: 1130, w: 611, h: 216, radius: 28, content: "question", title: "Answer in a click.", sub: "" },
  { at: 1210, w: 611, h: 90, radius: 28, content: "finished", title: "Know when it's done.", sub: "" },
  { at: 1290, w: 720, h: 208, radius: 30, content: "usage", title: "No more surprise limits.", sub: "Claude and Codex, with a forecast." },
  { at: 1380, w: 720, h: 208, radius: 30, content: "github", title: "Your GitHub, at a glance.", sub: "Streak, pull requests and checks." },
  { at: 1470, w: 720, h: 208, radius: 30, content: "hub-dev", title: "Widgets, your way.", sub: "" },
  { at: 1560, w: NOTCH.w, h: NOTCH.h, radius: 12, content: "none" },
];
// Two scenes leave the Mac for a white stage.
const STAGE = { moods: [570, 680], outfits: [680, 790] } as const;

const beatAt = (frame: number) => {
  let i = 0;
  for (let j = 0; j < BEATS.length; j++) if (frame >= BEATS[j].at) i = j;
  return i;
};

/** Where the camera looks: a point on the screen, its place in the frame, and the zoom. */
const camera = (frame: number) => {
  const wide = { x: W / 2, y: H * 0.62, cy: 930, s: 0.54 };
  const close = { x: W / 2, y: 0, cy: 880, s: 1.45 };
  const push = interpolate(frame, [92, 160], [0, 1], { ...clamp, easing: ease });
  const back = interpolate(frame, [1545, 1610], [0, 1], { ...clamp, easing: ease });
  const t = push * (1 - back);
  // A little extra lean-in while Molt wakes up.
  const lean = interpolate(frame, [180, 260, 360, 395], [0, 1, 1, 0], { ...clamp, easing: ease });
  return {
    x: interpolate(t, [0, 1], [wide.x, close.x]),
    y: interpolate(t, [0, 1], [wide.y, close.y]),
    cy: interpolate(t, [0, 1], [wide.cy, close.cy]) + lean * 60,
    s: interpolate(t, [0, 1], [wide.s, close.s]) * (1 + lean * 0.22),
  };
};

// MARK: Pieces

const Text: React.FC<{ beat: Beat; since: number; until: number; top: number }> = ({ beat, since, until, top }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame - beat.at;
  const show = spring({ frame: t - 6, fps, config: { damping: 200 } });
  const sub = spring({ frame: t - 14, fps, config: { damping: 200 } });
  const out = interpolate(frame, [until - 8, until], [1, 0], clamp);
  if (!beat.title || frame < since) return null;
  return (
    <div style={{ position: "absolute", top, left: 60, right: 60, textAlign: "center", fontFamily: SF, opacity: out }}>
      <div
        style={{
          fontSize: 86, fontWeight: 700, letterSpacing: -2.2, lineHeight: 1.05, color: INK,
          opacity: show, transform: `translateY(${(1 - show) * 30}px)`, filter: `blur(${(1 - show) * 8}px)`,
          ...(beat.gradient
            ? { background: "linear-gradient(90deg, #3fb871, #5DCC8C 40%, #7fd3e6)", WebkitBackgroundClip: "text", color: "transparent" }
            : {}),
        }}
      >
        {beat.title}
      </div>
      {beat.sub ? (
        <div style={{ marginTop: 22, fontSize: 40, fontWeight: 500, letterSpacing: -0.4, color: GRAY, opacity: sub, transform: `translateY(${(1 - sub) * 20}px)` }}>
          {beat.sub}
        </div>
      ) : null}
    </div>
  );
};

const Apple = () => (
  <svg width="15" height="18" viewBox="0 0 814 1000" style={{ marginTop: -3 }}>
    <path
      fill="#1d1d1f"
      d="M788 341c-6 4-108 62-108 190 0 148 130 200 134 202-1 3-21 72-69 142-43 62-88 124-156 124s-86-40-165-40c-77 0-104 41-167 41s-106-58-156-128C43 790 0 671 0 557c0-182 119-279 236-279 62 0 114 41 153 41 37 0 95-43 166-43 27 0 124 2 188 98zM554 160c29-35 50-83 50-131 0-7-1-13-2-19-47 2-104 32-138 72-27 30-52 79-52 128 0 7 1 15 2 17 3 1 8 1 13 1 43 0 96-29 127-68z"
    />
  </svg>
);

export const MenuBar = () => (
  <div
    style={{
      position: "absolute", top: 0, left: 0, right: 0, height: MENU, display: "flex", alignItems: "center", padding: "0 22px",
      background: "rgba(240,230,244,0.86)", fontFamily: SF, fontSize: 15, color: INK, gap: 22,
    }}
  >
    <Apple />
    <b style={{ fontWeight: 700 }}>Finder</b>
    {["File", "Edit", "View", "Go", "Window", "Help"].map((m) => (
      <span key={m}>{m}</span>
    ))}
    <div style={{ flex: 1 }} />
    <svg width="26" height="13" viewBox="0 0 26 13">
      <rect x="0.5" y="0.5" width="22" height="12" rx="3.5" fill="none" stroke="#1d1d1f" strokeOpacity="0.5" />
      <rect x="2.5" y="2.5" width="16" height="8" rx="2" fill="#1d1d1f" />
      <rect x="23.5" y="4" width="2" height="5" rx="1" fill="#1d1d1f" fillOpacity="0.5" />
    </svg>
    <svg width="18" height="14" viewBox="0 0 18 14">
      <path d="M9 13.5 6.4 10.6a3.7 3.7 0 0 1 5.2 0zM3.8 7.9a7.4 7.4 0 0 1 10.4 0l-1.3 1.4a5.5 5.5 0 0 0-7.8 0zM1.2 5.2a11.1 11.1 0 0 1 15.6 0l-1.3 1.4a9.2 9.2 0 0 0-13 0z" fill="#1d1d1f" />
    </svg>
    <svg width="15" height="15" viewBox="0 0 15 15">
      <circle cx="6" cy="6" r="4.6" fill="none" stroke="#1d1d1f" strokeWidth="1.7" />
      <path d="m9.5 9.5 4 4" stroke="#1d1d1f" strokeWidth="1.8" strokeLinecap="round" />
    </svg>
    <span>Sun Oct 11&nbsp;&nbsp;9:41 AM</span>
  </div>
);

/** What's inside the notch for one beat. */
const Content: React.FC<{ beat: Beat; local: number }> = ({ beat, local }) => {
  const image = (name: string, width: number) => (
    <Img src={staticFile(`ad/${name}.png`)} style={{ position: "absolute", top: 0, left: "50%", width, transform: "translateX(-50%)", display: "block" }} />
  );
  const creature = (node: React.ReactNode) => (
    <div style={{ position: "absolute", left: "50%", top: -42, transform: "translateX(-50%)" }}>{node}</div>
  );
  switch (beat.content) {
    case "sleep": {
      // Asleep, then waking: sleepy eyes, a little shake, eyes open, a look left and right.
      if (local < 62) return creature(<Molt loop="sleep" frames={90} size={350} at={local + 20} />);
      if (local < 92) return creature(<Molt loop="tired" frames={60} size={350} at={local} />);
      if (local < 100) return creature(<Molt loop="look" frames={240} size={350} at={60 + local} />);
      if (local < 122) return creature(<Molt loop="look" frames={240} size={350} at={186 + (local - 100)} />);
      return creature(<Molt loop="look" frames={240} size={350} at={207 + Math.min(20, local - 122)} />);
    }
    case "wave":
      return creature(<Molt loop="wave" frames={60} size={350} />);
    case "work":
      return creature(local < 64 ? <Molt loop="work-claude" frames={60} size={350} /> : <Molt loop="alert" frames={60} size={350} at={local - 64} />);
    case "none":
      return null;
    default:
      return image(beat.content, beat.content.match(/approval|diff|question|finished/) ? 611 : 720);
  }
};

/** The black island that grows out of the notch. */
const Island: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const i = beatAt(frame);
  const beat = BEATS[i], prev = BEATS[Math.max(0, i - 1)];
  const local = frame - beat.at;
  const grow = spring({ frame: local, fps, config: { damping: 15, stiffness: 120, mass: 0.9 } });
  const w = interpolate(grow, [0, 1], [prev.w, beat.w]);
  const h = interpolate(grow, [0, 1], [prev.h, beat.h]);
  const r = interpolate(grow, [0, 1], [prev.radius, beat.radius]);
  const fadeIn = interpolate(local, [3, 12], [0, 1], clamp);
  const fadeOut = interpolate(local, [0, 6], [1, 0], clamp);
  // The same creature carries on between the sleeping and waving beats, so nothing flashes.
  const keep = prev.content === "sleep" && beat.content === "wave";
  return (
    <div
      style={{
        position: "absolute", top: 0, left: "50%", width: w, height: h, transform: "translateX(-50%)",
        background: "#000", borderBottomLeftRadius: r, borderBottomRightRadius: r, overflow: "hidden",
        boxShadow: h > 60 ? "0 18px 50px rgba(0,0,0,0.35)" : "none",
      }}
    >
      {/* The camera, so the notch still looks like a notch. */}
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
  const rise = spring({ frame: frame - 2, fps, config: { damping: 22, stiffness: 70 } });
  const lidW = W + 2 * BEZEL, lidH = H + 2 * BEZEL;
  return (
    <AbsoluteFill style={{ perspective: frame < 120 ? 2600 : undefined }}>
      <div
        style={{
          position: "absolute", left: 540 - (cam.x + BEZEL) * cam.s, top: cam.cy - (cam.y + BEZEL) * cam.s,
          width: lidW, transformOrigin: "0 0",
          // Flat once it has landed: 3D layers can drop children in headless Chrome.
          transform: rise > 0.995 ? `scale(${cam.s})` : `scale(${cam.s}) translateY(${(1 - rise) * 260}px) rotateX(${(1 - rise) * 14}deg)`,
          opacity: interpolate(rise, [0, 0.4], [0, 1], clamp),
        }}
      >
        {/* Lid */}
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
        {/* Base */}
        <div style={{ position: "relative", margin: "0 auto", width: lidW + 150, marginLeft: -75, height: 40 }}>
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

// MARK: White stage scenes

const Stage: React.FC<{ from: number; to: number; children: React.ReactNode }> = ({ from, to, children }) => {
  const frame = useCurrentFrame();
  if (frame < from || frame >= to) return null;
  return <AbsoluteFill style={{ background: "#fff" }}>{children}</AbsoluteFill>;
};

const StageTitle: React.FC<{ title: string; sub: string; from: number; to: number }> = ({ title, sub, from, to }) => (
  <Text beat={{ at: from, w: 0, h: 0, radius: 0, content: "", title, sub }} since={from} until={to} top={330} />
);

const MOODS = [
  { loop: "eat", frames: 60, word: "Snack time" },
  { loop: "love", frames: 60, word: "Loved" },
  { loop: "happy", frames: 60, word: "Happy" },
  { loop: "celebrate", frames: 90, word: "Party" },
];
const Moods: React.FC = () => {
  const frame = useCurrentFrame();
  const [from, to] = STAGE.moods;
  const local = frame - from;
  const step = Math.max(0, Math.min(MOODS.length - 1, Math.floor(local / 27)));
  const mood = MOODS[step];
  const pop = interpolate(local - step * 27, [0, 5, 10], [0.9, 1.04, 1], clamp);
  return (
    <Stage from={from} to={to}>
      <StageTitle title="Full of feelings." sub="It knows when you care." from={from} to={to} />
      <div style={{ position: "absolute", top: 640, left: 0, right: 0, display: "flex", justifyContent: "center", transform: `scale(${pop})` }}>
        <Molt loop={mood.loop} frames={mood.frames} size={900} />
      </div>
      <div style={{ position: "absolute", top: 1560, left: 0, right: 0, textAlign: "center", fontFamily: SF, fontSize: 46, fontWeight: 600, color: "#3fb871", letterSpacing: -0.5 }}>
        {mood.word}
      </div>
    </Stage>
  );
};

const FITS = ["pumpkin", "headphones", "hardhat", "halo", "beanie", "shades", "santa", "hat", "bunny"];
const Outfits: React.FC = () => {
  const frame = useCurrentFrame();
  const [from, to] = STAGE.outfits;
  const local = frame - from;
  const step = Math.max(0, Math.min(FITS.length - 1, Math.floor(local / 12)));
  const pop = interpolate(local - step * 12, [0, 3, 7], [0.94, 1.03, 1], clamp);
  return (
    <Stage from={from} to={to}>
      <StageTitle title="Dress it up." sub="Sixteen pieces to collect." from={from} to={to} />
      <div style={{ position: "absolute", top: 640, left: 0, right: 0, display: "flex", justifyContent: "center", transform: `scale(${pop})` }}>
        <Molt loop={`fit-${FITS[step]}`} frames={30} size={900} />
      </div>
    </Stage>
  );
};

// MARK: Opening and ending

const Opening: React.FC = () => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [26, 40, 80, 92], [0, 1, 1, 0], clamp);
  const y = interpolate(frame, [26, 44], [24, 0], { ...clamp, easing: Easing.out(Easing.cubic) });
  return (
    <div style={{ position: "absolute", top: 300, left: 0, right: 0, textAlign: "center", fontFamily: SF, fontSize: 86, fontWeight: 700, letterSpacing: -2.2, color: INK, opacity, transform: `translateY(${y}px)` }}>
      It's just a notch.
    </div>
  );
};

const EndCard: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const from = 1612;
  if (frame < from) return null;
  const local = frame - from;
  const bg = interpolate(local, [0, 14], [0, 1], clamp);
  const icon = spring({ frame: local - 8, fps, config: { damping: 14, stiffness: 120 } });
  const word = spring({ frame: local - 18, fps, config: { damping: 200 } });
  const line = spring({ frame: local - 28, fps, config: { damping: 200 } });
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

export const MoltAd: React.FC = () => {
  const frame = useCurrentFrame();
  const beat = BEATS[beatAt(frame)];
  const next = BEATS[beatAt(frame) + 1];
  const onStage = frame >= STAGE.moods[0] && frame < STAGE.outfits[1];
  // The stage cuts in and out with a quick white flash, like a page turn.
  const flash = Math.max(
    interpolate(frame, [STAGE.moods[0] - 6, STAGE.moods[0], STAGE.moods[0] + 6], [0, 1, 0], clamp),
    interpolate(frame, [STAGE.outfits[1] - 6, STAGE.outfits[1], STAGE.outfits[1] + 6], [0, 1, 0], clamp),
  );
  const textUntil = Math.min(next?.at ?? AD_DURATION, beat.content === "play" ? STAGE.moods[0] : Infinity);
  return (
    <AbsoluteFill style={{ background: "#fff" }}>
      {!onStage ? <MacBook /> : null}
      {!onStage ? <Text beat={beat} since={beat.at} until={textUntil} top={330} /> : null}
      <Opening />
      <Moods />
      <Outfits />
      <EndCard />
      <AbsoluteFill style={{ background: "#fff", opacity: flash, pointerEvents: "none" }} />
    </AbsoluteFill>
  );
};
