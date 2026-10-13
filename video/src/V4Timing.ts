// Timing for version 4, shared by the trailer and its 3D shots (30 fps).
//
// The song (musicNONCOPYRIGHT.mp3) is 102 BPM in 4/4: a beat every 0.5882 s, a bar every
// 2.3529 s, and its first downbeat 0.40 s into the file. Everything after the intro is placed
// with `hit(bar, beat)`.

/** The frame the song starts on; before it, Molt wakes up in space and flies home. */
export const MUSIC = 288;
export const BEAT_S = 60 / 102.005, BAR_S = 4 * BEAT_S, FIRST_S = 0.4;
export const BAR = 30 * BAR_S, BEAT = 30 * BEAT_S;
export const hit = (bar: number, beat = 0) => MUSIC + Math.round(30 * (FIRST_S + BAR_S * bar + BEAT_S * beat));

/** The 3D shots, rendered on their own and played back in the trailer. */
export const HERO_A = [hit(11), hit(14)] as const;
export const HERO_B = [hit(16), hit(19)] as const;
export const GRID = [hit(19), hit(24)] as const;

/** One step every half bar: 1, 2, 4, 8, 16, 32, 64 and then 128 Macs. */
export const GRID_STEPS = [0, 1, 2, 3, 4, 5, 6, 7].map((k) => hit(19 + Math.floor(k / 2), (k % 2) * 2));

const beats = (from: number, to: number) => {
  const out: number[] = [];
  for (let b = from * 4; b < to * 4; b++) out.push(hit(Math.floor(b / 4), b % 4));
  return out;
};
const eighths = (from: number, to: number) => {
  const out: number[] = [];
  for (let e = from * 8; e < to * 8; e++) out.push(hit(Math.floor(e / 8), (e % 8) / 2));
  return out;
};

/** When every screen in the grid moves on to another design: on the beat, then on the eighths. */
export const GRID_CHANGES = [...beats(19, 23), ...eighths(23, 24)].filter((f) => f > GRID[0]);

/** What the 14-inch MacBook Pro shows as the camera circles it: Molt at work, then each request. */
export const HERO_A_SCREENS = [
  { at: hit(11, 0), screen: "work", title: "Watches your agents.", sub: "Claude Code, Codex and more." },
  { at: hit(11, 2), screen: "agents", title: "Every agent, live.", sub: "What's running, and a Stop button." },
  { at: hit(12, 0), screen: "approval", title: "Approve from the notch.", sub: "Allow, deny, or always allow." },
  { at: hit(12, 2), screen: "diff", title: "See every edit first.", sub: "" },
  { at: hit(13, 0), screen: "question", title: "Answer in a click.", sub: "" },
  { at: hit(13, 2), screen: "finished", title: "Know when it's done.", sub: "" },
];

/** The other MacBook: building the Hub, then the widgets on the beat. */
export const HERO_B_SCREENS = [
  { at: hit(16, 0), screen: "wedit", title: "Build your Hub.", sub: "Drag, resize and add." },
  ...beats(16, 19).slice(2).map((at, k) => ({ at, screen: `w${(k % 8) + 1}`, title: "21 widgets, your way.", sub: "Shortcuts, focus, music, GitHub and more." })),
];

export const END = hit(28);
export const V4_DURATION = hit(30);
