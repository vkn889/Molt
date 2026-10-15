import React from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";
import { Dock, WALLPAPERS } from "./MacScreen";
import { H, INK, MENU, NOTCH, SF, W } from "./MoltAd";

// Mockups of Molt 0.9.2: the notch fitting its content, typing to jump anywhere, focus sessions,
// the drop tray, new Hub widgets, a menu-bar popup and Molt reacting to the Mac. Rendered as
// stills by render-mockups.mjs.

const BLUE = "#0a84ff", GREEN = "#5dcc8c", ORANGE = "#ff9f0a", RED = "#ff453a", YELLOW = "#ffd60a", TEAL = "#64d2ff";
const DIM = "rgba(235,235,245,0.55)", FAINT = "rgba(235,235,245,0.3)";
const CARD: React.CSSProperties = { background: "#131316", border: "1px solid rgba(255,255,255,0.07)", borderRadius: 16 };
const ROUNDED = '"SF Pro Rounded", ui-rounded, ' + SF;

// MARK: Pieces

/** Molt from a rendered loop, `c` points wide, standing on the bottom of its box. */
const Pet: React.FC<{ loop: string; c: number; at?: number; style?: React.CSSProperties }> = ({ loop, c, at = 0, style }) => {
  const s = c / 0.3773;
  return (
    <div style={{ position: "relative", width: c, height: c, flexShrink: 0, ...style }}>
      <Img
        src={staticFile(`molt/${loop}/frame-${String(at).padStart(4, "0")}.png`)}
        style={{ position: "absolute", width: s, height: s, left: c / 2 - s / 2, top: c - s * 0.7114, imageRendering: "pixelated", maxWidth: "none" }}
      />
    </div>
  );
};

const PATHS: Record<string, React.ReactNode> = {
  home: <path d="M3.5 11 12 4l8.5 7v8.5h-5.5v-5.5h-6v5.5H3.5z" fill="currentColor" />,
  grid: <g fill="currentColor"><rect x="4" y="4" width="7" height="7" rx="1.8" /><rect x="13" y="4" width="7" height="7" rx="1.8" /><rect x="4" y="13" width="7" height="7" rx="1.8" /><rect x="13" y="13" width="7" height="7" rx="1.8" /></g>,
  game: <g fill="currentColor"><path d="M7 7h10a5 5 0 0 1 4.6 7l-1 2.4a2.6 2.6 0 0 1-4.3.7L14.6 15H9.4l-1.7 2.1a2.6 2.6 0 0 1-4.3-.7l-1-2.4A5 5 0 0 1 7 7z" /><path d="M7.5 9.5v4M5.5 11.5h4" stroke="#000" strokeWidth="1.5" /><circle cx="16" cy="10.5" r="1.1" fill="#000" /><circle cx="18" cy="12.6" r="1.1" fill="#000" /></g>,
  people: <g fill="currentColor"><circle cx="8.5" cy="8" r="3.2" /><circle cx="16" cy="8.6" r="2.7" /><path d="M2.5 19c.4-3.6 2.9-5.6 6-5.6s5.6 2 6 5.6zM15.5 13.6c2.8 0 5 1.8 5.6 5.4h-5.2c-.2-2-1-3.8-2.3-5 .6-.3 1.2-.4 1.9-.4z" /></g>,
  lens: <g fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round"><path d="M4 8V5.5A1.5 1.5 0 0 1 5.5 4H8M16 4h2.5A1.5 1.5 0 0 1 20 5.5V8M20 16v2.5a1.5 1.5 0 0 1-1.5 1.5H16M8 20H5.5A1.5 1.5 0 0 1 4 18.5V16" /><path d="M8 9.5h8M8 12h8M8 14.5h5" /></g>,
  terminal: <g><rect x="3" y="4.5" width="18" height="15" rx="3" fill="currentColor" /><path d="m7 9.5 2.6 2.4L7 14.3M11.5 14.5h4.5" stroke="#000" strokeWidth="1.7" fill="none" strokeLinecap="round" strokeLinejoin="round" /></g>,
  bubble: <path d="M5.5 4.5h13a2.5 2.5 0 0 1 2.5 2.5v8a2.5 2.5 0 0 1-2.5 2.5H11l-4.2 3v-3H5.5A2.5 2.5 0 0 1 3 15V7a2.5 2.5 0 0 1 2.5-2.5z" fill="currentColor" />,
  gear: <g><circle cx="12" cy="12" r="6.6" fill="none" stroke="currentColor" strokeWidth="3.6" strokeDasharray="2.6 2.6" /><circle cx="12" cy="12" r="5.6" fill="currentColor" /><circle cx="12" cy="12" r="2.2" fill="#000" /></g>,
  search: <g fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><circle cx="10.5" cy="10.5" r="6" /><path d="m15 15 5 5" /></g>,
  play: <path d="M8 5.5v13l10.5-6.5z" fill="currentColor" />,
  pause: <g fill="currentColor"><rect x="6.5" y="5" width="4" height="14" rx="1.2" /><rect x="13.5" y="5" width="4" height="14" rx="1.2" /></g>,
  next: <g fill="currentColor"><path d="M4 6.5v11l7.5-5.5zM12 6.5v11l7.5-5.5z" /></g>,
  prev: <g fill="currentColor"><path d="M20 6.5v11L12.5 12zM12 6.5v11L4.5 12z" /></g>,
  timer: <g fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><circle cx="12" cy="13" r="7.5" /><path d="M12 13V9M10 3h4" /></g>,
  tray: <g fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinejoin="round"><path d="M3.5 13.5 6 5.5h12l2.5 8v5h-17z" /><path d="M3.5 13.5h5l1 2h5l1-2h5" /></g>,
  share: <g fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M8 9.5H6.5v10h11v-10H16M12 3.5v11M8.5 7 12 3.5 15.5 7" /></g>,
  sparkle: <path d="M12 3c.7 4.6 2.4 6.3 7 7-4.6.7-6.3 2.4-7 7-.7-4.6-2.4-6.3-7-7 4.6-.7 6.3-2.4 7-7z" fill="currentColor" />,
  chevronL: <path d="m14.5 5-7 7 7 7" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />,
  chevronR: <path d="m9.5 5 7 7-7 7" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />,
  more: <g fill="currentColor"><circle cx="6" cy="12" r="1.7" /><circle cx="12" cy="12" r="1.7" /><circle cx="18" cy="12" r="1.7" /></g>,
  plus: <path d="M12 5v14M5 12h14" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" />,
  check: <path d="m5 12.5 4.5 4.5L19 7.5" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />,
  note: <path d="M9 17.5V6l10-2v11.5M9 17.5a2.5 2.5 0 1 1-2.5-2.5A2.5 2.5 0 0 1 9 17.5zM19 15.5a2.5 2.5 0 1 1-2.5-2.5 2.5 2.5 0 0 1 2.5 2.5z" fill="none" stroke="currentColor" strokeWidth="1.8" />,
  calendar: <g fill="none" stroke="currentColor" strokeWidth="1.9"><rect x="3.5" y="5" width="17" height="15" rx="3" /><path d="M3.5 10h17M8 3v4M16 3v4" strokeLinecap="round" /></g>,
  doc: <g><path d="M6 3h8l4.5 4.5V21H6z" fill="currentColor" /><path d="M14 3v4.5h4.5" fill="none" stroke="#000" strokeOpacity="0.25" strokeWidth="1.2" /></g>,
  photo: <g fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinejoin="round"><rect x="3.5" y="5" width="17" height="14" rx="2.5" /><path d="m5 17 4.5-5 3.5 3.5 2.5-2.5 3.5 4" /><circle cx="15.5" cy="9.5" r="1.4" fill="currentColor" /></g>,
  link: <g fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3A4 4 0 0 0 11 18.7l1-1" /></g>,
  bolt: <path d="M13.5 2.5 5 13.5h6l-1 8 8.5-11h-6z" fill="currentColor" />,
  grip: <g fill="currentColor">{[7, 12, 17].flatMap((y) => [9, 15].map((x) => <circle key={`${x}${y}`} cx={x} cy={y} r="1.5" />))}</g>,
  record: <circle cx="12" cy="12" r="6.5" fill="currentColor" />,
  moon: <path d="M19 14.5A7.5 7.5 0 0 1 9.5 5a7.5 7.5 0 1 0 9.5 9.5z" fill="currentColor" />,
  leaf: <path d="M5 19C5 10 10 5 19.5 4.5 19 14 14 19 5 19zM5 19l7-7" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" />,
  battery: <g><rect x="2.5" y="7" width="17" height="10" rx="2.6" fill="none" stroke="currentColor" strokeWidth="1.6" /><rect x="4.5" y="9" width="3" height="6" rx="1" fill={RED} /><rect x="20.3" y="10" width="1.8" height="4" rx="0.9" fill="currentColor" /></g>,
  airdrop: <g fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"><path d="M7.5 16.5a6.5 6.5 0 1 1 9 0M9.6 14.4a3.5 3.5 0 1 1 4.8 0" /><path d="M12 13.5 9 20h6z" fill="currentColor" stroke="none" /></g>,
};

const I: React.FC<{ n: string; s?: number; c?: string; style?: React.CSSProperties }> = ({ n, s = 16, c = "currentColor", style }) => (
  <svg width={s} height={s} viewBox="0 0 24 24" style={{ color: c, flexShrink: 0, display: "block", ...style }}>
    {PATHS[n]}
  </svg>
);

const Key: React.FC<{ children: React.ReactNode; light?: boolean }> = ({ children, light }) => (
  <span
    style={{
      fontSize: 10.5, fontWeight: 600, padding: "2px 6px", borderRadius: 5, letterSpacing: 0.3,
      color: light ? "rgba(0,0,0,0.55)" : DIM, background: light ? "rgba(0,0,0,0.06)" : "rgba(255,255,255,0.08)",
    }}
  >
    {children}
  </span>
);

const Bar: React.FC<{ v: number; c: string; h?: number; track?: string }> = ({ v, c, h = 4, track = "rgba(255,255,255,0.12)" }) => (
  <div style={{ height: h, borderRadius: h, background: track, overflow: "hidden" }}>
    <div style={{ width: `${v * 100}%`, height: "100%", borderRadius: h, background: c }} />
  </div>
);

/** A mac menu bar with Molt's status item; `open` highlights it. */
const MenuBar: React.FC<{ open?: boolean }> = ({ open }) => (
  <div
    style={{
      position: "absolute", top: 0, left: 0, right: 0, height: MENU, display: "flex", alignItems: "center", padding: "0 18px 0 22px",
      background: "rgba(240,232,246,0.78)", backdropFilter: "blur(20px)", fontFamily: SF, fontSize: 14.5, color: INK, gap: 21,
    }}
  >
    <svg width="15" height="18" viewBox="0 0 814 1000" style={{ marginTop: -3 }}>
      <path fill={INK} d="M788 341c-6 4-108 62-108 190 0 148 130 200 134 202-1 3-21 72-69 142-43 62-88 124-156 124s-86-40-165-40c-77 0-104 41-167 41s-106-58-156-128C43 790 0 671 0 557c0-182 119-279 236-279 62 0 114 41 153 41 37 0 95-43 166-43 27 0 124 2 188 98zM554 160c29-35 50-83 50-131 0-7-1-13-2-19-47 2-104 32-138 72-27 30-52 79-52 128 0 7 1 15 2 17 3 1 8 1 13 1 43 0 96-29 127-68z" />
    </svg>
    <b>Xcode</b>
    {["File", "Edit", "View", "Find", "Navigate", "Editor", "Product", "Window", "Help"].map((m) => (
      <span key={m}>{m}</span>
    ))}
    <div style={{ flex: 1 }} />
    <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
      <div style={{ padding: "3px 7px", borderRadius: 6, background: open ? "rgba(0,0,0,0.12)" : "transparent" }}>
        <MoltGlyph />
      </div>
      <svg width="26" height="13" viewBox="0 0 26 13">
        <rect x="0.5" y="0.5" width="22" height="12" rx="3.5" fill="none" stroke={INK} strokeOpacity="0.5" />
        <rect x="2.5" y="2.5" width="14" height="8" rx="2" fill={INK} />
        <rect x="23.5" y="4" width="2" height="5" rx="1" fill={INK} fillOpacity="0.5" />
      </svg>
      <I n="search" s={15} c={INK} />
      <span>Tue Oct 13&nbsp;&nbsp;9:41 AM</span>
    </div>
  </div>
);

/** Molt's template icon in the menu bar: the sprout, as pixels. */
const MoltGlyph: React.FC = () => {
  const px = [
    "....#....", "...###...", "....#....", ".#######.", "##.###.##", "#########", "#########", ".#.#.#.#.",
  ];
  return (
    <svg width="18" height="16" viewBox="0 0 9 8" shapeRendering="crispEdges">
      {px.flatMap((row, y) => [...row].map((ch, x) => (ch === "#" ? <rect key={`${x}-${y}`} x={x} y={y} width="1" height="1" fill={INK} /> : null)))}
    </svg>
  );
};

/** A desktop at the size of a 14-inch MacBook Pro's display, in points. `zoom` shows its top bigger. */
const Desk: React.FC<{ wall?: string; open?: boolean; zoom?: number; origin?: string; children?: React.ReactNode }> = ({ wall = "dusk", open, zoom = 1, origin = "50%", children }) => (
  <AbsoluteFill style={{ width: W, height: H, overflow: "hidden", fontFamily: SF }}>
    <div style={{ position: "absolute", inset: 0, background: WALLPAPERS[wall] }} />
    <div style={{ position: "absolute", inset: 0, transform: `scale(${zoom})`, transformOrigin: `${origin} 0` }}>
      <MenuBar open={open} />
      <Dock />
      {children}
    </div>
  </AbsoluteFill>
);

/** The island: black, hugging the top edge, with the notch's flared top corners. */
const Island: React.FC<{ w: number; h: number; r?: number; children?: React.ReactNode; glow?: string }> = ({ w, h, r = 26, children, glow }) => (
  <div style={{ position: "absolute", top: 0, left: "50%", width: w, height: h, transform: "translateX(-50%)", color: "#fff" }}>
    {[-1, 1].map((side) => (
      <svg key={side} width="12" height="12" viewBox="0 0 12 12" style={{ position: "absolute", top: 0, [side < 0 ? "left" : "right"]: -12 }}>
        <path d={side < 0 ? "M0 0h12v12C12 5 7 0 0 0z" : "M12 0H0v12C0 5 5 0 12 0z"} fill="#000" />
      </svg>
    ))}
    <div
      style={{
        position: "absolute", inset: 0, background: "#000", borderBottomLeftRadius: r, borderBottomRightRadius: r, overflow: "hidden",
        boxShadow: `0 20px 60px rgba(0,0,0,0.35)${glow ? `, 0 0 0 1px ${glow}` : ""}`,
      }}
    >
      {children}
    </div>
  </div>
);

const TABS = [
  { n: "home", t: "Home" }, { n: "grid", t: "Hub" }, { n: "game", t: "Play" }, { n: "people", t: "Molting" },
];
const TOOLS = ["lens", "terminal", "bubble", "gear"];

/** The open notch's header: tabs on the left, tools on the right, or a back arrow, a title and its menu. */
const Header: React.FC<{ tab?: string; tool?: string; back?: string; title?: string; extra?: React.ReactNode }> = ({ tab, tool, back, title, extra }) => (
  <div style={{ height: 48, display: "flex", alignItems: "center", padding: "6px 20px 0", gap: 6, fontSize: 13.5 }}>
    {back ? (
      <>
        <div style={{ display: "flex", alignItems: "center", gap: 4, color: DIM, fontWeight: 500 }}>
          <I n="chevronL" s={14} /> {back}
        </div>
        <div style={{ width: 1, height: 14, background: "rgba(255,255,255,0.14)", margin: "0 8px" }} />
        <div style={{ fontWeight: 650, fontSize: 15 }}>{title}</div>
        <div style={{ flex: 1 }} />
        {extra}
        <div style={{ width: 28, height: 28, borderRadius: 14, display: "grid", placeItems: "center", background: "rgba(255,255,255,0.08)" }}>
          <I n="more" s={16} c={DIM} />
        </div>
      </>
    ) : (
      <>
        {TABS.map(({ n, t }) =>
          t === tab ? (
            <div key={t} style={{ display: "flex", alignItems: "center", gap: 7, height: 30, padding: "0 13px 0 11px", borderRadius: 15, background: "rgba(255,255,255,0.12)", fontWeight: 650 }}>
              <I n={n} s={15} /> {t}
            </div>
          ) : (
            <div key={t} style={{ width: 34, height: 30, display: "grid", placeItems: "center", color: "rgba(255,255,255,0.78)" }}>
              <I n={n} s={16} />
            </div>
          ),
        )}
        <div style={{ flex: 1 }} />
        {extra}
        {TOOLS.map((n) => (
          <div key={n} style={{ width: 32, height: 30, borderRadius: 15, display: "grid", placeItems: "center", background: n === tool ? "rgba(255,255,255,0.14)" : "transparent", color: "rgba(255,255,255,0.8)" }}>
            <I n={n} s={16} />
          </div>
        ))}
      </>
    )}
  </div>
);

/** Closed-notch wings: something on each side of the camera. */
const Wings: React.FC<{ left: React.ReactNode; right: React.ReactNode; w?: number; dots?: number; dot?: number }> = ({ left, right, w = 120, dots, dot = 0 }) => (
  <>
    <Island w={NOTCH.w + 2 * w} h={NOTCH.h} r={12}>
      <div style={{ display: "flex", height: "100%", alignItems: "center", justifyContent: "space-between", padding: "0 14px" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 7 }}>{left}</div>
        <div style={{ display: "flex", alignItems: "center", gap: 7 }}>{right}</div>
      </div>
    </Island>
    {dots ? (
      <div style={{ position: "absolute", top: NOTCH.h + 7, left: "50%", transform: "translateX(-50%)", display: "flex", gap: 5 }}>
        {Array.from({ length: dots }, (_, i) => (
          <div key={i} style={{ width: i === dot ? 14 : 5, height: 5, borderRadius: 3, background: i === dot ? "rgba(0,0,0,0.75)" : "rgba(0,0,0,0.28)" }} />
        ))}
      </div>
    ) : null}
  </>
);

/** A soft caption card on the desktop, for showing what's going on in a close-up. */
const Note: React.FC<{ top: number; children: React.ReactNode }> = ({ top, children }) => (
  <div
    style={{
      position: "absolute", top, left: "50%", transform: "translateX(-50%)", padding: "9px 16px", borderRadius: 14, whiteSpace: "nowrap",
      background: "rgba(255,255,255,0.72)", backdropFilter: "blur(20px)", color: INK, fontSize: 12.5, fontWeight: 500,
      boxShadow: "0 6px 24px rgba(0,0,0,0.12)", display: "flex", alignItems: "center", gap: 8,
    }}
  >
    {children}
  </div>
);

const Art: React.FC<{ s: number; r?: number }> = ({ s, r = 12 }) => (
  <div
    style={{
      width: s, height: s, borderRadius: r, flexShrink: 0, position: "relative", overflow: "hidden",
      background: "radial-gradient(80% 70% at 30% 25%, #ffd6a0, transparent 60%), radial-gradient(90% 80% at 80% 90%, #4b8f6a, transparent 60%), linear-gradient(160deg, #f2a65e, #6aa57f 60%, #23493c)",
    }}
  >
    <svg viewBox="0 0 40 40" style={{ position: "absolute", inset: 0, width: "100%", height: "100%", opacity: 0.55 }}>
      <path d="M20 34c0-10 2-16 9-21M20 34c0-7-3-12-9-15" stroke="#173a2c" strokeWidth="1.6" fill="none" strokeLinecap="round" />
      <ellipse cx="29.5" cy="12" rx="4" ry="2.2" fill="#173a2c" transform="rotate(-35 29.5 12)" />
      <ellipse cx="10.5" cy="18.5" rx="3.6" ry="2" fill="#173a2c" transform="rotate(25 10.5 18.5)" />
    </svg>
  </div>
);

// MARK: 1. Home

const Home: React.FC = () => (
  <Desk wall="dusk">
    <Island w={720} h={218}>
      <Header tab="Home" />
      <div style={{ display: "flex", gap: 18, padding: "10px 20px 0" }}>
        {/* Music, with Molt bopping along. */}
        <div style={{ width: 300, display: "flex", gap: 14 }}>
          <div style={{ position: "relative" }}>
            <Art s={96} />
            <Pet loop="fit-headphones" c={46} at={12} style={{ position: "absolute", left: 26, top: 92 }} />
            {[[-6, 104, 0.9], [78, 98, 0.7], [86, 120, 0.5]].map(([x, y, o], i) => (
              <I key={i} n="note" s={12 - i * 1.5} c={GREEN} style={{ position: "absolute", left: x, top: y, opacity: o }} />
            ))}
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 16, fontWeight: 650 }}>Wind Garden</div>
            <div style={{ fontSize: 13, color: DIM, marginTop: 2 }}>Lofi Pocket · Morning Mix</div>
            <div style={{ marginTop: 12 }}>
              <Bar v={0.42} c="#fff" h={4} />
              <div style={{ display: "flex", justifyContent: "space-between", fontSize: 10.5, color: FAINT, marginTop: 4, fontVariantNumeric: "tabular-nums" }}>
                <span>1:14</span><span>-1:41</span>
              </div>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 22, marginTop: 4, paddingLeft: 2 }}>
              <I n="prev" s={20} c="rgba(255,255,255,0.65)" />
              <I n="pause" s={24} />
              <I n="next" s={20} c="rgba(255,255,255,0.65)" />
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 12, fontSize: 11.5, color: DIM }}>
              <span style={{ color: FAINT }}>Up next</span> Paper Lanterns
            </div>
          </div>
        </div>
        {/* Today, with what's next. */}
        <div style={{ width: 176, paddingTop: 2 }}>
          <div style={{ display: "flex", alignItems: "baseline", gap: 8 }}>
            <span style={{ fontSize: 26, fontWeight: 750, letterSpacing: -0.5 }}>Oct</span>
            <div style={{ display: "flex", gap: 6, fontSize: 13, fontWeight: 650 }}>
              {[["MON", "12"], ["TUE", "13"], ["WED", "14"], ["THU", "15"]].map(([d, n], i) => (
                <div key={d} style={{ textAlign: "center", color: i === 1 ? BLUE : DIM }}>
                  <div style={{ fontSize: 8.5, letterSpacing: 0.4 }}>{d}</div>
                  <div style={{ fontSize: 15 }}>{n}</div>
                </div>
              ))}
            </div>
          </div>
          <div style={{ marginTop: 12, padding: "9px 11px", borderRadius: 12, background: "rgba(10,132,255,0.16)", border: "1px solid rgba(10,132,255,0.3)" }}>
            <div style={{ fontSize: 10.5, color: TEAL, fontWeight: 650 }}>IN 12 MIN</div>
            <div style={{ fontSize: 13, fontWeight: 600, marginTop: 1 }}>Design standup</div>
            <div style={{ fontSize: 11, color: DIM }}>10:00 – 10:15 · Zoom</div>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 9, fontSize: 12.5, color: DIM }}>
            <div style={{ width: 12, height: 12, borderRadius: 6, border: `1.5px solid ${FAINT}` }} /> Ship 0.9.2 notes
          </div>
        </div>
        {/* The Mac and Molt. */}
        <div style={{ flex: 1, paddingTop: 4, display: "grid", gap: 9 }}>
          {[
            ["Battery", "100%", 1, "#fff"], ["CPU", "18%", 0.18, "#fff"], ["Memory", "71%", 0.71, "#fff"], ["Focus today", "50 min", 0.55, GREEN], ["Molt", "Happy", 0.86, GREEN],
          ].map(([k, v, x, c]) => (
            <div key={k as string}>
              <div style={{ display: "flex", justifyContent: "space-between", fontSize: 12, marginBottom: 4 }}>
                <span style={{ color: DIM }}>{k}</span><span style={{ fontWeight: 650 }}>{v}</span>
              </div>
              <Bar v={x as number} c={c as string} h={3} />
            </div>
          ))}
        </div>
      </div>
    </Island>
  </Desk>
);

// MARK: 2. Type to jump

const Jump: React.FC = () => {
  const rows = [
    { i: "timer", t: "Start a focus session", s: "25 minutes · Molt works with you", k: "↩", hot: true, c: GREEN },
    { i: "grid", t: "Focus widget", s: "Hub", k: "⌥1" },
    { i: "pause", t: "Pause app tracking", s: "Action", k: "⌥P" },
    { i: "gear", t: "Focus sounds", s: "Settings › Focus", k: "" },
  ];
  return (
    <Desk wall="sea">
      <Island w={600} h={322}>
        <div style={{ padding: "18px 18px 0" }}>
          <div style={{ height: 40, display: "flex", alignItems: "center", gap: 10, padding: "0 12px", borderRadius: 12, background: "rgba(255,255,255,0.08)" }}>
            <I n="search" s={16} c={DIM} />
            <span style={{ fontSize: 16, fontWeight: 500 }}>
              foc<span style={{ display: "inline-block", width: 2, height: 18, background: BLUE, verticalAlign: -3, marginLeft: 1 }} />
            </span>
            <div style={{ flex: 1 }} />
            <Pet loop="look" c={24} at={20} />
          </div>
        </div>
        <div style={{ padding: "10px 10px 0" }}>
          {rows.map((r) => (
            <div key={r.t} style={{ display: "flex", alignItems: "center", gap: 12, height: 50, padding: "0 12px", borderRadius: 12, background: r.hot ? "rgba(255,255,255,0.09)" : "transparent" }}>
              <div style={{ width: 30, height: 30, borderRadius: 9, display: "grid", placeItems: "center", background: r.c ? "rgba(93,204,140,0.18)" : "rgba(255,255,255,0.07)" }}>
                <I n={r.i} s={16} c={r.c ?? "rgba(255,255,255,0.8)"} />
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 14, fontWeight: 600 }}>
                  {r.t.toLowerCase().includes("foc") ? r.t.slice(0, r.t.toLowerCase().indexOf("foc")) : r.t}
                  {r.t.toLowerCase().includes("foc") ? (
                    <>
                      <u style={{ textDecorationColor: BLUE, textUnderlineOffset: 3 }}>{r.t.slice(r.t.toLowerCase().indexOf("foc"), r.t.toLowerCase().indexOf("foc") + 3)}</u>
                      {r.t.slice(r.t.toLowerCase().indexOf("foc") + 3)}
                    </>
                  ) : null}
                </div>
                <div style={{ fontSize: 11.5, color: DIM, marginTop: 1 }}>{r.s}</div>
              </div>
              {r.k ? <Key>{r.k}</Key> : null}
            </div>
          ))}
        </div>
        <div style={{ position: "absolute", bottom: 14, left: 22, right: 22, display: "flex", gap: 16, fontSize: 11, color: FAINT }}>
          <span><Key>↑↓</Key> move</span><span><Key>↩</Key> open</span><span><Key>⌥</Key> hold for shortcuts</span>
          <div style={{ flex: 1 }} />
          <span>Just start typing when the notch is open</span>
        </div>
      </Island>
    </Desk>
  );
};

// MARK: 3. Focus

const Ruler: React.FC = () => {
  const marks = Array.from({ length: 61 }, (_, i) => i);
  return (
    <div style={{ position: "relative", height: 56 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", height: 34 }}>
        {marks.map((m) => {
          const on = m <= 25, big = m % 5 === 0;
          return (
            <div key={m} style={{ width: 4, height: big ? 26 : 14, background: on ? GREEN : "rgba(255,255,255,0.18)", opacity: on ? 0.55 + 0.45 * (m / 25) : 1, imageRendering: "pixelated" }} />
          );
        })}
      </div>
      <div style={{ display: "flex", justifyContent: "space-between", marginTop: 6, fontSize: 10.5, fontWeight: 650, color: FAINT, fontFamily: ROUNDED }}>
        {[0, 10, 20, 30, 40, 50, 60].map((n) => (
          <span key={n} style={{ width: 20, textAlign: "center", color: n === 20 ? DIM : FAINT }}>{n}</span>
        ))}
      </div>
      {/* The handle: a pixel leaf. */}
      <svg width="16" height="16" viewBox="0 0 8 8" shapeRendering="crispEdges" style={{ position: "absolute", left: `calc(${(25 / 60) * 100}% - 8px)`, top: -18 }}>
        {["..####..", ".######.", "########", "########", ".######.", "...##...", "...##...", "...##..."].flatMap((row, y) =>
          [...row].map((ch, x) => (ch === "#" ? <rect key={`${x}${y}`} x={x} y={y} width="1" height="1" fill={y > 4 ? "#3f9a66" : GREEN} /> : null)),
        )}
      </svg>
    </div>
  );
};

const Focus: React.FC = () => (
  <Desk wall="mint">
    <Island w={640} h={232}>
      <Header back="Home" title="Focus" />
      <div style={{ display: "flex", gap: 22, padding: "8px 24px 0", alignItems: "center" }}>
        <div style={{ position: "relative", width: 110, height: 120, display: "grid", placeItems: "end center" }}>
          <div style={{ position: "absolute", bottom: 4, width: 96, height: 10, borderRadius: "50%", background: "rgba(93,204,140,0.18)" }} />
          <Pet loop="glasses-idle" c={86} at={40} />
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ display: "flex", alignItems: "baseline", gap: 12 }}>
            <span style={{ fontFamily: ROUNDED, fontSize: 44, fontWeight: 700, letterSpacing: -1, fontVariantNumeric: "tabular-nums" }}>25:00</span>
            <span style={{ fontSize: 13, color: DIM }}>Molt will sit and work with you</span>
          </div>
          <div style={{ marginTop: 14 }}>
            <Ruler />
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 4 }}>
            {["15", "25", "50"].map((p) => (
              <div key={p} style={{ height: 28, padding: "0 12px", borderRadius: 14, display: "grid", placeItems: "center", whiteSpace: "nowrap", fontSize: 12.5, fontWeight: 600, background: p === "25" ? "rgba(255,255,255,0.14)" : "rgba(255,255,255,0.06)", color: p === "25" ? "#fff" : DIM }}>
                {p} min
              </div>
            ))}
            <div style={{ flex: 1 }} />
            <span style={{ fontSize: 11.5, color: FAINT, marginRight: 6, whiteSpace: "nowrap" }}>2 done today · +10 energy</span>
            <div style={{ height: 32, padding: "0 18px", borderRadius: 16, display: "flex", alignItems: "center", gap: 6, background: GREEN, color: "#0b2416", fontWeight: 700, fontSize: 13.5 }}>
              <I n="play" s={13} /> Start
            </div>
          </div>
        </div>
      </div>
    </Island>
  </Desk>
);

// MARK: 4. Focus running, notch closed

const FocusLive: React.FC = () => (
  <Desk wall="mint" zoom={2.6}>
      <Wings
        w={86}
        dots={3}
        left={<><Pet loop="glasses-idle" c={20} at={90} style={{ marginTop: 2 }} /><span style={{ fontSize: 11.5, fontWeight: 600, color: DIM }}>Focus</span></>}
        right={
          <>
            <span style={{ fontFamily: ROUNDED, fontSize: 13.5, fontWeight: 700, color: GREEN, fontVariantNumeric: "tabular-nums" }}>18:42</span>
            <svg width="16" height="16" viewBox="0 0 16 16">
              <circle cx="8" cy="8" r="6" fill="none" stroke="rgba(255,255,255,0.15)" strokeWidth="2.4" />
              <circle cx="8" cy="8" r="6" fill="none" stroke={GREEN} strokeWidth="2.4" strokeDasharray={`${0.25 * 37.7} 37.7`} transform="rotate(-90 8 8)" strokeLinecap="round" />
            </svg>
          </>
        }
      />
      <Note top={62}>
        <span style={{ color: "rgba(0,0,0,0.5)" }}>Swipe on the notch</span> Focus · Music · Agents
      </Note>
  </Desk>
);

// MARK: 5. Drop on Molt

const Drop: React.FC = () => (
  <Desk wall="lilac">
    <Island w={600} h={218} glow="rgba(93,204,140,0.5)">
      <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "16px 22px 0" }}>
        <Pet loop="happy" c={34} at={8} />
        <div>
          <div style={{ fontSize: 15, fontWeight: 650 }}>Drop it on Molt</div>
          <div style={{ fontSize: 12, color: DIM }}>Pitch Deck.pdf · 4.2 MB</div>
        </div>
      </div>
      <div style={{ display: "flex", gap: 10, padding: "14px 18px 0" }}>
        {[
          { i: "bubble", t: "Ask", s: "Chat about it", c: BLUE },
          { i: "tray", t: "Keep", s: "Molt holds it for later", c: GREEN, hot: true },
          { i: "airdrop", t: "Share", s: "AirDrop, Mail, Messages", c: TEAL },
        ].map((d) => (
          <div
            key={d.t}
            style={{
              flex: 1, height: 112, borderRadius: 18, display: "grid", placeItems: "center", textAlign: "center",
              background: d.hot ? "rgba(93,204,140,0.16)" : "rgba(255,255,255,0.05)",
              border: d.hot ? `1.5px solid ${GREEN}` : "1.5px dashed rgba(255,255,255,0.14)",
            }}
          >
            <div>
              <I n={d.i} s={26} c={d.c} style={{ margin: "0 auto" }} />
              <div style={{ fontSize: 14, fontWeight: 650, marginTop: 8 }}>{d.t}</div>
              <div style={{ fontSize: 11, color: DIM, marginTop: 2 }}>{d.s}</div>
            </div>
          </div>
        ))}
      </div>
    </Island>
    {/* The file being dragged, under the pointer. */}
    <div style={{ position: "absolute", left: 958, top: 166, transform: "rotate(-4deg)", filter: "drop-shadow(0 12px 18px rgba(0,0,0,0.3))" }}>
      <div style={{ width: 58, height: 72, borderRadius: 6, background: "#fff", position: "relative", overflow: "hidden" }}>
        <div style={{ position: "absolute", top: 0, left: 0, right: 0, height: 24, background: RED, color: "#fff", fontSize: 10, fontWeight: 800, display: "grid", placeItems: "center" }}>PDF</div>
        {[34, 42, 50, 58].map((y) => <div key={y} style={{ position: "absolute", top: y, left: 8, right: y === 58 ? 24 : 8, height: 3, borderRadius: 2, background: "#ddd" }} />)}
      </div>
    </div>
    <svg width="22" height="26" viewBox="0 0 22 26" style={{ position: "absolute", left: 1000, top: 214 }}>
      <path d="M2 2v19l5-5 3.5 8 3-1.4L10 15h7z" fill="#000" stroke="#fff" strokeWidth="1.5" strokeLinejoin="round" />
    </svg>
  </Desk>
);

// MARK: 6. Hub with the new widgets

const Widget: React.FC<{ w: number; h?: number; title?: string; icon?: string; ic?: string; children: React.ReactNode; badge?: boolean }> = ({ w, h = 152, title, icon, ic, children, badge }) => (
  <div style={{ ...CARD, width: w, height: h, padding: "12px 14px", position: "relative", boxSizing: "border-box" }}>
    {title ? (
      <div style={{ display: "flex", alignItems: "center", gap: 7, fontSize: 12.5, fontWeight: 600, color: DIM }}>
        {icon ? <I n={icon} s={14} c={ic ?? DIM} /> : null} {title}
        {badge ? <span style={{ marginLeft: "auto", fontSize: 9.5, fontWeight: 750, color: GREEN, letterSpacing: 0.4 }}>NEW</span> : null}
      </div>
    ) : null}
    {children}
  </div>
);

const FocusWidget: React.FC<{ w: number }> = ({ w }) => (
  <Widget w={w} title="Focus" icon="timer" ic={GREEN} badge>
    <div style={{ display: "flex", alignItems: "center", gap: 12, marginTop: 10 }}>
      <svg width="74" height="74" viewBox="0 0 74 74">
        <circle cx="37" cy="37" r="31" fill="none" stroke="rgba(255,255,255,0.1)" strokeWidth="7" />
        <circle cx="37" cy="37" r="31" fill="none" stroke={GREEN} strokeWidth="7" strokeDasharray={`${0.25 * 194.8} 194.8`} transform="rotate(-90 37 37)" strokeLinecap="round" />
        <text x="37" y="42" textAnchor="middle" fill="#fff" fontSize="15" fontWeight="700" fontFamily={ROUNDED}>18:42</text>
      </svg>
      <div>
        <Pet loop="glasses-idle" c={40} at={140} />
        <div style={{ fontSize: 11, color: DIM, marginTop: 4 }}>3rd today</div>
      </div>
    </div>
  </Widget>
);

const TrayWidget: React.FC<{ w: number }> = ({ w }) => (
  <Widget w={w} title="Tray" icon="tray" badge>
    <div style={{ display: "grid", gap: 6, marginTop: 10 }}>
      {[
        { i: "doc", c: RED, t: "Pitch Deck.pdf" }, { i: "photo", c: ORANGE, t: "hero-shot.png" }, { i: "link", c: BLUE, t: "github.com/vkn889/Molt" },
      ].map((f) => (
        <div key={f.t} style={{ display: "flex", alignItems: "center", gap: 8, height: 28, padding: "0 8px", borderRadius: 8, background: "rgba(255,255,255,0.05)", fontSize: 12 }}>
          <I n={f.i} s={14} c={f.c} /> <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{f.t}</span>
        </div>
      ))}
    </div>
  </Widget>
);

const MeetingWidget: React.FC<{ w: number }> = ({ w }) => (
  <Widget w={w} title="Next up" icon="calendar" ic={TEAL} badge>
    <div style={{ marginTop: 10, fontFamily: ROUNDED, fontSize: 30, fontWeight: 700, letterSpacing: -0.5 }}>
      12<span style={{ fontSize: 15, color: DIM, marginLeft: 3 }}>min</span>
    </div>
    <div style={{ fontSize: 13.5, fontWeight: 600, marginTop: 2 }}>Design standup</div>
    <div style={{ fontSize: 11.5, color: DIM }}>Zoom · 4 people</div>
    <div style={{ position: "absolute", right: 12, bottom: 10, height: 26, padding: "0 11px", borderRadius: 13, display: "grid", placeItems: "center", background: BLUE, fontSize: 12, fontWeight: 650 }}>Join</div>
  </Widget>
);

const MoodWidget: React.FC<{ w: number }> = ({ w }) => (
  <Widget w={w} title="Molt" icon="leaf" ic={GREEN}>
    <div style={{ display: "flex", alignItems: "center", gap: 12, marginTop: 8 }}>
      <Pet loop="love" c={54} at={30} />
      <div style={{ flex: 1, display: "grid", gap: 7 }}>
        {[["Food", 0.8, ORANGE], ["Energy", 0.62, YELLOW], ["Fun", 0.9, RED]].map(([k, v, c]) => (
          <div key={k as string} style={{ fontSize: 10.5, color: DIM }}>
            <div style={{ marginBottom: 3 }}>{k}</div>
            <Bar v={v as number} c={c as string} h={4} />
          </div>
        ))}
      </div>
    </div>
  </Widget>
);

const MusicWidget: React.FC<{ w: number }> = ({ w }) => (
  <Widget w={w} title="Up next" icon="note" badge>
    <div style={{ display: "flex", gap: 10, alignItems: "center", marginTop: 10 }}>
      <Art s={44} r={8} />
      <div>
        <div style={{ fontSize: 13, fontWeight: 650 }}>Wind Garden</div>
        <div style={{ fontSize: 11, color: DIM }}>Lofi Pocket</div>
      </div>
    </div>
    <div style={{ marginTop: 10, display: "grid", gap: 5, fontSize: 11.5, color: DIM }}>
      <div>2 · Paper Lanterns</div><div>3 · Slow Tide</div>
    </div>
  </Widget>
);

const Hub: React.FC = () => (
  <Desk wall="graphite">
    <Island w={720} h={384}>
      <Header tab="Hub" extra={<div style={{ width: 30, height: 30, display: "grid", placeItems: "center", color: DIM, marginRight: 4 }}><svg width="15" height="15" viewBox="0 0 24 24"><path d="M4 20l4-1L19.5 7.5l-3-3L5 16z" fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" /></svg></div>} />
      <div style={{ display: "flex", flexWrap: "wrap", gap: 10, padding: "8px 20px" }}>
        <FocusWidget w={220} />
        <MeetingWidget w={210} />
        <MoodWidget w={230} />
        <TrayWidget w={240} />
        <MusicWidget w={200} />
        <Widget w={220} title="Actions" icon="bolt" ic={YELLOW}>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 6, marginTop: 10 }}>
            {[["record", RED, "Record"], ["lens", TEAL, "Ask"], ["moon", "#bf5af2", "Dark"], ["timer", GREEN, "Focus"]].map(([i, c, t]) => (
              <div key={t} style={{ height: 46, borderRadius: 10, background: "rgba(255,255,255,0.06)", display: "grid", placeItems: "center", fontSize: 11, fontWeight: 600 }}>
                <div style={{ textAlign: "center" }}><I n={i} s={16} c={c} style={{ margin: "0 auto 3px" }} />{t}</div>
              </div>
            ))}
          </div>
        </Widget>
      </div>
    </Island>
  </Desk>
);

// MARK: 7. Adding widgets

const Gallery: React.FC = () => {
  const items = [
    { t: "Focus", i: "timer", c: GREEN, n: true }, { t: "Tray", i: "tray", c: DIM, n: true }, { t: "Next up", i: "calendar", c: TEAL, n: true },
    { t: "Up next", i: "note", c: "#ff6482", n: true }, { t: "Molt mood", i: "leaf", c: GREEN, n: true }, { t: "Battery", i: "battery", c: "#fff" },
    { t: "Clock", i: "timer", c: ORANGE }, { t: "Screen recorder", i: "record", c: RED }, { t: "Lens", i: "lens", c: TEAL },
    { t: "GitHub", i: "link", c: "#fff" }, { t: "Usage", i: "bolt", c: ORANGE }, { t: "Agents", i: "terminal", c: "#fff" },
  ];
  return (
    <Desk wall="graphite">
      <Island w={720} h={322}>
        <Header back="Hub" title="Add a widget" extra={<div style={{ display: "flex", alignItems: "center", gap: 6, height: 28, padding: "0 10px", borderRadius: 14, background: "rgba(255,255,255,0.08)", fontSize: 12, color: DIM, marginRight: 8, width: 150 }}><I n="search" s={13} /> Search 26 widgets</div>} />
        <div style={{ display: "flex", gap: 8, padding: "4px 20px 10px" }}>
          {["All", "New in 0.9.2", "Mac", "Agents", "Molt"].map((c, i) => (
            <div key={c} style={{ height: 26, padding: "0 11px", borderRadius: 13, display: "grid", placeItems: "center", fontSize: 12, fontWeight: 600, background: i === 1 ? "rgba(93,204,140,0.2)" : "rgba(255,255,255,0.06)", color: i === 1 ? GREEN : DIM }}>{c}</div>
          ))}
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(6, 1fr)", gap: 10, padding: "0 20px" }}>
          {items.map((it) => (
            <div key={it.t} style={{ ...CARD, height: 104, display: "grid", placeItems: "center", textAlign: "center", position: "relative" }}>
              <div>
                <div style={{ width: 40, height: 40, borderRadius: 12, margin: "0 auto", display: "grid", placeItems: "center", background: "rgba(255,255,255,0.07)" }}>
                  <I n={it.i} s={20} c={it.c} />
                </div>
                <div style={{ fontSize: 12, fontWeight: 600, marginTop: 8 }}>{it.t}</div>
              </div>
              {it.n ? <span style={{ position: "absolute", top: 7, right: 8, fontSize: 8.5, fontWeight: 800, color: GREEN, letterSpacing: 0.4 }}>NEW</span> : null}
              <div style={{ position: "absolute", top: 6, left: 6, width: 18, height: 18, borderRadius: 9, display: "grid", placeItems: "center", background: BLUE }}>
                <I n="plus" s={11} c="#fff" />
              </div>
            </div>
          ))}
        </div>
      </Island>
    </Desk>
  );
};

// MARK: 8. The menu-bar popup

const Popup: React.FC = () => (
  <Desk wall="sunset" open zoom={1.55} origin="100%">
      <div
        style={{
          position: "absolute", top: MENU + 6, right: 208, width: 300, borderRadius: 18, padding: 14, boxSizing: "border-box",
          background: "rgba(28,28,32,0.86)", backdropFilter: "blur(30px)", color: "#fff",
          boxShadow: "0 24px 60px rgba(0,0,0,0.35), inset 0 0 0 1px rgba(255,255,255,0.1)",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <div style={{ width: 62, height: 62, borderRadius: 16, display: "grid", placeItems: "end center", background: "radial-gradient(circle at 50% 70%, rgba(93,204,140,0.22), rgba(255,255,255,0.04) 70%)" }}>
            <Pet loop="wave" c={48} at={14} style={{ marginBottom: 4 }} />
          </div>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 15, fontWeight: 700 }}>Molt</div>
            <div style={{ fontSize: 11.5, color: DIM }}>Day 42 · Feeling great</div>
            <div style={{ display: "flex", gap: 4, marginTop: 7 }}>
              {[[0.8, ORANGE], [0.62, YELLOW], [0.9, RED]].map(([v, c], i) => (
                <div key={i} style={{ flex: 1 }}><Bar v={v as number} c={c as string} h={4} /></div>
              ))}
            </div>
          </div>
        </div>
        <div style={{ marginTop: 12, fontSize: 10.5, fontWeight: 700, color: FAINT, letterSpacing: 0.5 }}>RIGHT NOW</div>
        <div style={{ marginTop: 6, borderRadius: 12, background: "rgba(255,255,255,0.05)", padding: "4px 0" }}>
          {[
            { dot: ORANGE, t: "Claude Code", s: "molt · working 3m", r: "Stop" },
            { dot: GREEN, t: "Focus", s: "18:42 left", r: "Pause" },
            { dot: "#ff6482", t: "Wind Garden", s: "Lofi Pocket", r: <I n="pause" s={12} /> },
          ].map((row) => (
            <div key={row.t} style={{ display: "flex", alignItems: "center", gap: 9, height: 38, padding: "0 10px" }}>
              <div style={{ width: 7, height: 7, borderRadius: 4, background: row.dot }} />
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 12.5, fontWeight: 600 }}>{row.t}</div>
                <div style={{ fontSize: 10.5, color: DIM }}>{row.s}</div>
              </div>
              <div style={{ fontSize: 11, fontWeight: 600, color: DIM, padding: "3px 9px", borderRadius: 9, background: "rgba(255,255,255,0.08)" }}>{row.r}</div>
            </div>
          ))}
        </div>
        <div style={{ marginTop: 10, display: "grid", gap: 2 }}>
          {[
            ["home", "Open Molt", "⌘O", true], ["lens", "Ask about screen", "⌘⇧L"], ["game", "Play with Molt", ""], ["pause", "Pause app tracking", ""],
          ].map(([i, t, k, hot]) => (
            <div key={t as string} style={{ display: "flex", alignItems: "center", gap: 10, height: 32, padding: "0 10px", borderRadius: 9, background: hot ? BLUE : "transparent", fontSize: 13 }}>
              <I n={i as string} s={15} c={hot ? "#fff" : DIM} /> <span style={{ flex: 1 }}>{t}</span>
              {k ? <span style={{ fontSize: 11.5, color: hot ? "rgba(255,255,255,0.8)" : FAINT }}>{k}</span> : null}
            </div>
          ))}
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", marginTop: 10, padding: "10px 10px 0", borderTop: "1px solid rgba(255,255,255,0.08)", fontSize: 12, color: DIM }}>
          <span>Settings…</span><span>Quit Molt</span>
        </div>
      </div>
  </Desk>
);

// MARK: 9. Molt and the Mac: low battery

const Battery: React.FC = () => (
  <Desk wall="rose" zoom={2.6}>
      <Wings
        w={96}
        left={<><Pet loop="tired" c={20} at={20} style={{ marginTop: 2 }} /><span style={{ fontSize: 11.5, fontWeight: 600, color: DIM }}>Sleepy…</span></>}
        right={<><span style={{ fontSize: 12.5, fontWeight: 700, color: RED, fontVariantNumeric: "tabular-nums" }}>12%</span><I n="battery" s={20} c="rgba(255,255,255,0.8)" /></>}
      />
      <Note top={54}>
        <Pet loop="tired" c={18} at={40} /> Molt's running low with your Mac. Plug in to wake it up.
      </Note>
  </Desk>
);

// MARK: 10. An agent needs you, with other things queued

const Agents: React.FC = () => (
  <Desk wall="dusk" zoom={2.4}>
      <Wings
        w={112}
        dots={3}
        left={<><Pet loop="alert" c={20} at={6} style={{ marginTop: 2 }} /><span style={{ fontSize: 11.5, fontWeight: 650, color: ORANGE }}>Claude needs you</span></>}
        right={
          <>
            <span style={{ height: 20, padding: "0 8px", borderRadius: 10, display: "grid", placeItems: "center", fontSize: 10.5, fontWeight: 700, background: GREEN, color: "#0b2416" }}>Allow</span>
            <span style={{ height: 20, padding: "0 8px", borderRadius: 10, display: "grid", placeItems: "center", fontSize: 10.5, fontWeight: 700, background: "rgba(255,255,255,0.14)" }}>Deny</span>
          </>
        }
      />
      <Note top={62}>
        <span style={{ color: "rgba(0,0,0,0.5)" }}>Up first</span> Agents <span style={{ color: "rgba(0,0,0,0.35)" }}>›</span> Recording <span style={{ color: "rgba(0,0,0,0.35)" }}>›</span> Focus <span style={{ color: "rgba(0,0,0,0.35)" }}>›</span> Music
      </Note>
  </Desk>
);

// MARK: 11. Settings: arrange the notch

const Toggle: React.FC<{ on?: boolean }> = ({ on }) => (
  <div style={{ width: 34, height: 20, borderRadius: 10, background: on ? GREEN : "rgba(255,255,255,0.16)", position: "relative", flexShrink: 0 }}>
    <div style={{ position: "absolute", top: 2, left: on ? 16 : 2, width: 16, height: 16, borderRadius: 8, background: "#fff" }} />
  </div>
);

const Settings: React.FC = () => (
  <Desk wall="sea">
    <Island w={720} h={266}>
      <Header back="Settings" title="Notch" />
      <div style={{ display: "flex", gap: 12, padding: "6px 20px" }}>
        <div style={{ ...CARD, flex: 1, padding: "12px 14px" }}>
          <div style={{ fontSize: 12.5, fontWeight: 600, color: DIM, marginBottom: 6 }}>Tabs</div>
          {[["home", "Home", true], ["grid", "Hub", true], ["game", "Play", true], ["people", "Molting", false]].map(([i, t, on], k) => (
            <div key={t as string} style={{ display: "flex", alignItems: "center", gap: 10, height: 36, padding: "0 8px", borderRadius: 9, background: k === 1 ? "rgba(255,255,255,0.08)" : "transparent", boxShadow: k === 1 ? "0 8px 18px rgba(0,0,0,0.4)" : "none", transform: k === 1 ? "translateX(4px) rotate(-0.6deg)" : "none" }}>
              <I n="grip" s={14} c={FAINT} /><I n={i as string} s={15} c={on ? "#fff" : FAINT} />
              <span style={{ flex: 1, fontSize: 13, color: on ? "#fff" : FAINT }}>{t}</span>
              <Toggle on={on as boolean} />
            </div>
          ))}
        </div>
        <div style={{ ...CARD, flex: 1, padding: "12px 14px" }}>
          <div style={{ fontSize: 12.5, fontWeight: 600, color: DIM, marginBottom: 6 }}>When it's closed, show first</div>
          {[[ORANGE, "Agent requests"], [RED, "Screen recording"], [GREEN, "Focus session"], ["#ff6482", "Music"]].map(([c, t], k) => (
            <div key={t} style={{ display: "flex", alignItems: "center", gap: 10, height: 36, padding: "0 8px" }}>
              <span style={{ width: 14, fontSize: 11.5, fontWeight: 700, color: FAINT }}>{k + 1}</span>
              <div style={{ width: 8, height: 8, borderRadius: 4, background: c }} />
              <span style={{ flex: 1, fontSize: 13 }}>{t}</span>
              <I n="grip" s={14} c={FAINT} />
            </div>
          ))}
        </div>
        <div style={{ ...CARD, width: 200, padding: "12px 14px" }}>
          <div style={{ fontSize: 12.5, fontWeight: 600, color: DIM, marginBottom: 10 }}>Feel</div>
          <div style={{ fontSize: 12.5, marginBottom: 6 }}>Open on hover after</div>
          <div style={{ position: "relative", height: 18 }}>
            <Bar v={0.3} c={BLUE} h={4} />
            <div style={{ position: "absolute", left: "calc(30% - 8px)", top: -6, width: 16, height: 16, borderRadius: 8, background: "#fff", boxShadow: "0 1px 4px rgba(0,0,0,0.4)" }} />
          </div>
          <div style={{ display: "flex", justifyContent: "space-between", fontSize: 10.5, color: FAINT }}><span>Instantly</span><span>0.3 s</span><span>1 s</span></div>
          <div style={{ display: "flex", alignItems: "center", marginTop: 14, fontSize: 12.5 }}><span style={{ flex: 1 }}>Fit to content</span><Toggle on /></div>
          <div style={{ display: "flex", alignItems: "center", marginTop: 10, fontSize: 12.5 }}><span style={{ flex: 1 }}>Molt reacts to the Mac</span><Toggle on /></div>
          <div style={{ display: "flex", alignItems: "center", marginTop: 10, fontSize: 12.5 }}><span style={{ flex: 1 }}>Type to jump</span><Toggle on /></div>
        </div>
      </div>
    </Island>
  </Desk>
);

export const MOCKUPS: Record<string, { title: string; view: React.FC }> = {
  "01-home": { title: "Home that fits: music with Molt bopping along, what's next today, and focus time", view: Home },
  "02-type-to-jump": { title: "Type to jump: start typing with the notch open", view: Jump },
  "03-focus": { title: "Focus sessions: drag the pixel ruler, and Molt works with you", view: Focus },
  "04-focus-closed": { title: "Focus while the notch is closed, with a swipe for what else is live", view: FocusLive },
  "05-drop-on-molt": { title: "Drop anything on Molt: ask, keep in the tray, or share", view: Drop },
  "06-hub-widgets": { title: "New Hub widgets: Focus, Next up, Molt, Tray and Up next", view: Hub },
  "07-add-widget": { title: "Adding widgets, with what's new in 0.9.2", view: Gallery },
  "08-menu-bar": { title: "The menu-bar popup: Molt, what's live right now, and four actions", view: Popup },
  "09-low-battery": { title: "Molt reacts to the Mac: sleepy on low battery", view: Battery },
  "10-agent-needs-you": { title: "Agents come first when the notch is closed", view: Agents },
  "11-settings-notch": { title: "Settings: arrange the tabs and what the closed notch shows", view: Settings },
};

export const Mockup092: React.FC<{ id: string }> = ({ id }) => {
  const View = MOCKUPS[id].view;
  return <View />;
};
