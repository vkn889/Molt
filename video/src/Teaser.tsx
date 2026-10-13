import React from "react";
import { AbsoluteFill, Audio, Easing, Img, Sequence, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { BEZEL, GRAY, H, INK, Molt, NOTCH, RIM, SF, W, clamp, ease } from "./MoltAd";

// The teaser: a MacBook in the dark, an ominous 8-bit score, Molt wakes up in the notch, puts on
// its glasses and walks off. The notch closes, "Stay Tuned..." lands on the boom, and a white
// card shows Molt with a coffee over the logo and the date.
//
// The Mac is the same drawn MacBook as the commercials; its display is in screen points.

export const TEASER_DURATION = 720;

const SW = W, SH = H;

const T = {
  open: 150, tired: 215, idle: 255, glasses: 290, wear: 305, hop: 336, walk: 352, gone: 420,
  close: 425, boom: 465, card: 555,
};

// MARK: Pixel art over Molt's sprite

// Molt's loops are 660 px squares with a 21 px grid; cell (0, 0) sits at (183, 235.5).
const cellAt = (size: number, x: number, y: number) => {
  const k = size / 660;
  return { left: (183 + x * 21) * k, top: (193.5 + (y + 2) * 21) * k, side: 21 * k + 0.4 };
};

const Pixels: React.FC<{ size: number; pixels: [number, number, string, number?][] }> = ({ size, pixels }) => (
  <>
    {pixels.map(([x, y, color, opacity], i) => {
      const c = cellAt(size, x, y);
      return <div key={i} style={{ position: "absolute", left: c.left, top: c.top, width: c.side, height: c.side, background: color, opacity: opacity ?? 1 }} />;
    })}
  </>
);

const GLASSES: [number, number][] = [[3, 4], [4, 4], [5, 4], [8, 4], [9, 4], [10, 4], [6, 5], [7, 5], [3, 5], [10, 5]];

/** A mug of coffee in Molt's hand, steaming, lifted to its mouth for a sip now and then. */
const Coffee: React.FC<{ size: number; t: number }> = ({ size, t }) => {
  const cycle = t % 96;
  // Pixel steps over to the mouth and back, like the rest of the sprite.
  const steps = cycle < 54 ? 0 : cycle < 84 ? Math.min(5, Math.floor((cycle - 54) / 2)) : Math.max(0, 5 - Math.floor((cycle - 84) / 2));
  const ox = -steps, oy = steps >= 3 ? 1 : 0;
  const cup = "#f4f1ea", shade = "#d6cfc2", brew = "#6b4428";
  const px: [number, number, string, number?][] = [];
  px.push([13 + ox, 5 + oy, brew], [14 + ox, 5 + oy, brew]);
  for (const y of [6, 7]) px.push([13 + ox, y + oy, cup], [14 + ox, y + oy, shade]);
  px.push([15 + ox, 6 + oy, shade]);
  // Two wisps of steam rising while the mug rests.
  if (steps === 0) {
    for (let k = 0; k < 2; k++) {
      const p = ((t + k * 24) % 48) / 48;
      const y = 4 - Math.floor(p * 4);
      const x = 13 + k - (Math.floor(p * 4) % 2) * k;
      px.push([x, y, "#c9c9cc", interpolate(p, [0, 0.2, 0.8, 1], [0, 0.9, 0.6, 0])]);
    }
  }
  return <Pixels size={size} pixels={px} />;
};

// MARK: The screen

/** Everything on the display, in flat screen points. */
const Screen: React.FC<{ frame: number }> = ({ frame }) => {
  const { fps } = useVideoConfig();
  const opened = spring({ frame: frame - T.open, fps, config: { damping: 18, stiffness: 150, mass: 0.8 } });
  const closed = spring({ frame: frame - T.close, fps, config: { damping: 20, stiffness: 170, mass: 0.7 } });
  const o = Math.max(0, opened - closed);
  const w = interpolate(o, [0, 1], [NOTCH.w, 842]), h = interpolate(o, [0, 1], [NOTCH.h, 486]);
  const radius = interpolate(o, [0, 1], [12, 66]);

  // Molt: asleep, waking, glasses on, a hop down to the screen and a walk off to the right.
  const size = 650;
  const home = { x: SW / 2, y: 227 };
  const hop = interpolate(frame, [T.hop, T.walk], [0, 1], clamp);
  const walkX = interpolate(frame, [T.walk, T.gone], [0, 1170], clamp);
  const x = home.x + interpolate(hop, [0, 1], [0, 130]) + walkX;
  const y = home.y + interpolate(hop, [0, 1], [0, 432], { easing: Easing.in(Easing.quad) }) - Math.sin(hop * Math.PI) * 150;
  const loop =
    // Each loop plays from its own start and is long enough never to wrap, since a wrap jumps.
    frame < T.tired ? { name: "sleep", n: 90, at: frame - T.open } : frame < T.idle ? { name: "tired", n: 60, at: frame - T.tired }
    : frame < T.wear ? { name: "idle", n: 300, at: frame - T.idle }
    : frame < T.walk ? { name: "glasses-idle", n: 300, at: frame - T.wear } : { name: "glasses-walk", n: 120, at: frame - T.walk };
  const show = interpolate(frame, [T.open + 6, T.open + 18], [0, 1], clamp);
  // The glasses drop on from above, in whole pixels.
  const drop = Math.round(interpolate(frame, [T.glasses, T.wear], [-9, 0], { ...clamp, easing: Easing.in(Easing.quad) }));
  // A little sparkle when they land.
  const ping = interpolate(frame, [T.wear, T.wear + 12], [0, 1], clamp);

  // "Stay Tuned..." lands on the boom, the dots one by one.
  const words = interpolate(frame, [T.boom, T.boom + 16], [0, 1], { ...clamp, easing: Easing.out(Easing.cubic) });
  const dot = (k: number) => interpolate(frame, [T.boom + 14 + k * 8, T.boom + 20 + k * 8], [0, 1], clamp);

  return (
    <div style={{ position: "absolute", width: SW, height: SH, overflow: "hidden" }}>
      {/* The notch, and the island it opens into. */}
      <div
        style={{
          position: "absolute", top: -2, left: SW / 2 - w / 2, width: w, height: h + 2, background: "#000",
          borderBottomLeftRadius: radius, borderBottomRightRadius: radius,
        }}
      />
      {frame >= T.open && frame < T.gone ? (
        <div style={{ position: "absolute", left: x - size / 2, top: y - size / 2, width: size, height: size, opacity: show }}>
          <Molt loop={loop.name} frames={loop.n} size={size} at={loop.at} />
          {frame >= T.glasses && frame < T.wear ? <Pixels size={size} pixels={GLASSES.map(([gx, gy]) => [gx, gy + drop, "#22252b"])} /> : null}
          {frame >= T.wear && frame < T.wear + 12 ? (
            <Pixels size={size} pixels={[[1, 3, "#fff", 1 - ping], [12, 2, "#fff", 1 - ping], [0, 4 - Math.round(ping * 2), "#ffe27a", 1 - ping], [13, 3 - Math.round(ping * 2), "#ffe27a", 1 - ping]]} />
          ) : null}
        </div>
      ) : null}
      {frame >= T.boom ? (
        <div
          style={{
            position: "absolute", left: 0, right: 0, top: 440, textAlign: "center", fontFamily: SF, fontSize: 182, fontWeight: 600,
            letterSpacing: -4.5, color: INK, opacity: words, filter: `blur(${(1 - words) * 18}px)`,
            transform: `scale(${interpolate(words, [0, 1], [1.12, 1])})`,
          }}
        >
          Stay Tuned
          {[0, 1, 2].map((k) => (
            <span key={k} style={{ opacity: dot(k) }}>.</span>
          ))}
        </div>
      ) : null}
    </div>
  );
};

// MARK: The end card

const Card: React.FC<{ frame: number }> = ({ frame }) => {
  const { fps } = useVideoConfig();
  const t = frame - T.card;
  const rise = (at: number) => spring({ frame: t - at, fps, config: { damping: 20, stiffness: 120, mass: 0.8 } });
  const size = 760;
  return (
    <AbsoluteFill style={{ background: "#fff", alignItems: "center", fontFamily: SF }}>
      <div style={{ position: "absolute", top: 430, width: size, height: size, opacity: rise(0), transform: `translateY(${(1 - rise(0)) * 40}px)` }}>
        <Molt loop="glasses-idle" frames={300} size={size} at={t} />
        <Coffee size={size} t={t} />
      </div>
      <div
        style={{
          position: "absolute", top: 1190, display: "flex", alignItems: "center", gap: 30,
          opacity: rise(8), transform: `translateY(${(1 - rise(8)) * 30}px)`,
        }}
      >
        <Img src={staticFile("teaser/app-icon.png")} style={{ width: 150, height: 150 }} />
        <div style={{ fontSize: 150, fontWeight: 700, letterSpacing: -4.5, color: INK }}>Molt</div>
      </div>
      <div
        style={{
          position: "absolute", top: 1420, fontSize: 64, fontWeight: 600, letterSpacing: 6, color: GRAY,
          opacity: rise(18), transform: `translateY(${(1 - rise(18)) * 24}px)`,
        }}
      >
        10.17.26
      </div>
    </AbsoluteFill>
  );
};

// MARK: The teaser

const lerp = (a: number, b: number, k: number) => a + (b - a) * k;

/** Where the camera looks: a point on the display, where it sits in the frame, and the zoom. */
const camera = (frame: number) => {
  const wide = { x: W / 2, y: H * 0.56, cy: 980, s: interpolate(frame, [0, 120], [0.5, 0.6], { ...clamp, easing: Easing.out(Easing.sin) }) };
  const close = { x: W / 2, y: 262, cy: 880, s: 1.05 };
  const full = { x: W / 2, y: H / 2 + 20, cy: 960, s: 0.58 };
  const mix = (p: typeof full, q: typeof full, k: number) => ({
    x: lerp(p.x, q.x, k), y: lerp(p.y, q.y, k), cy: lerp(p.cy, q.cy, k), s: Math.exp(lerp(Math.log(p.s), Math.log(q.s), k)),
  });
  const inT = interpolate(frame, [110, 200], [0, 1], { ...clamp, easing: ease });
  const outT = interpolate(frame, [T.hop - 6, T.walk + 40], [0, 1], { ...clamp, easing: ease });
  const cam = mix(mix(wide, close, inT), full, outT);
  // A slow push while the words sit on the screen.
  cam.s *= interpolate(frame, [T.walk + 40, T.card], [1, 1.07], clamp);
  return cam;
};

/** The MacBook from the commercials, lit only by its own display. */
const DarkMac: React.FC<{ frame: number }> = ({ frame }) => {
  const cam = camera(frame);
  const lidW = W + 2 * BEZEL, lidH = H + 2 * BEZEL;
  return (
    <div
      style={{
        position: "absolute", left: 540 - (cam.x + BEZEL) * cam.s, top: cam.cy - (cam.y + BEZEL) * cam.s,
        width: lidW, transformOrigin: "0 0", transform: `scale(${cam.s})`,
      }}
    >
      {/* The glow the display throws on the desk. */}
      <div
        style={{
          position: "absolute", left: -500, right: -500, top: lidH - 120, height: 900,
          background: "radial-gradient(50% 40% at 50% 30%, rgba(225,230,245,0.16), rgba(225,230,245,0.05) 55%, transparent 75%)",
        }}
      />
      <div
        style={{
          position: "relative", width: lidW, height: lidH, borderRadius: 44, background: "#0b0b0d",
          boxShadow: `0 0 0 ${RIM}px rgba(150,152,158,0.55), 0 0 0 ${RIM + 1}px rgba(90,92,98,0.6), 0 0 260px rgba(220,226,245,0.14)`,
        }}
      >
        <div
          style={{
            position: "absolute", left: BEZEL, top: BEZEL, width: W, height: H, borderRadius: 16, overflow: "hidden",
            background: "radial-gradient(120% 110% at 50% 35%, #f6f7f9 0%, #eceef2 55%, #dfe2e7 100%)",
          }}
        >
          <Screen frame={frame} />
        </div>
      </div>
      <div style={{ position: "relative", width: lidW + 150, marginLeft: -75, height: 40 }}>
        <div
          style={{
            position: "absolute", inset: 0, borderRadius: "6px 6px 40px 40px / 6px 6px 30px 30px",
            background: "linear-gradient(#8d8f95, #56585d 45%, #26272a)",
          }}
        />
        <div style={{ position: "absolute", top: 0, left: "50%", width: 300, height: 13, marginLeft: -150, borderRadius: "0 0 14px 14px", background: "linear-gradient(#4a4c50, #6a6c71)" }} />
      </div>
    </div>
  );
};

export const Teaser: React.FC = () => {
  const frame = useCurrentFrame();
  const fadeIn = interpolate(frame, [0, 36], [0, 1], clamp);
  return (
    <AbsoluteFill style={{ background: "#000" }}>
      {frame >= T.card ? (
        <Card frame={frame} />
      ) : (
        <AbsoluteFill style={{ opacity: fadeIn }}>
          <DarkMac frame={frame} />
        </AbsoluteFill>
      )}
      <Audio2 />
    </AbsoluteFill>
  );
};

/** The 8-bit score until the words, then the boom under them. */
const Audio2: React.FC = () => (
  <>
    <Sequence from={0} durationInFrames={T.boom}>
      {/* The score cuts to silence on its own just before the boom. */}
      <Audio src={staticFile("teaser/chiptune.wav")} volume={(f) => interpolate(f, [0, 20], [0, 0.85], clamp)} />
    </Sequence>
    {/* The boom's hit is 0.16 s into the file. */}
    <Sequence from={T.boom - 5}>
      <Audio src={staticFile("teaser/boom.mp3")} volume={0.85} />
    </Sequence>
  </>
);
