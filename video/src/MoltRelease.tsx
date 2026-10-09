import React from "react";
import {
  AbsoluteFill, Easing, Img, Sequence, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig,
} from "remotion";
import { loadFont as loadInter } from "@remotion/google-fonts/Inter";
import { loadFont as loadPixel } from "@remotion/google-fonts/Silkscreen";

const { fontFamily: inter } = loadInter("normal", { weights: ["500", "700", "800"], subsets: ["latin"] });
const { fontFamily: pixel } = loadPixel("normal", { weights: ["400"], subsets: ["latin"] });

const AGENT = { claude: "#F2A07B", codex: "#7DE3CF", gemini: "#8FB2F5", molt: "#5DCC8C" };

// Scene timing, in frames at 30 fps.
const S = {
  intro: [0, 105],
  approval: [105, 315],
  agents: [315, 495],
  finished: [495, 615],
  usage: [615, 780],
  github: [780, 945],
  chat: [945, 1080],
  wardrobe: [1080, 1260],
  outro: [1260, 1440],
} as const;
export const DURATION = 1440;

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** One of Molt's rendered animation loops, played at the video's frame rate. */
const Molt: React.FC<{ loop: string; frames: number; size: number; style?: React.CSSProperties }> = ({ loop, frames, size, style }) => {
  const frame = useCurrentFrame();
  const index = String(((frame % frames) + frames) % frames).padStart(4, "0");
  return (
    <Img
      src={staticFile(`molt/${loop}/frame-${index}.png`)}
      style={{ width: size, height: size, imageRendering: "pixelated", ...style }}
    />
  );
};

/** Fades a scene in and out at its edges. */
const useSceneFade = (length: number) => {
  const frame = useCurrentFrame();
  return interpolate(frame, [0, 10, length - 10, length], [0, 1, 1, 0], clamp);
};

const Background: React.FC = () => {
  const frame = useCurrentFrame();
  // A slow glow that takes on the color of whichever part of the story is playing.
  const hue = interpolate(frame, [0, 315, 495, 780, 1080, 1440], [150, 20, 170, 200, 30, 150], clamp);
  return (
    <AbsoluteFill style={{ background: "#05060A" }}>
      <AbsoluteFill
        style={{
          background: `radial-gradient(circle at 50% ${38 + Math.sin(frame / 60) * 4}%, hsla(${hue}, 70%, 45%, 0.28), transparent 60%)`,
        }}
      />
      <AbsoluteFill
        style={{
          backgroundImage: "linear-gradient(rgba(255,255,255,0.025) 2px, transparent 2px), linear-gradient(90deg, rgba(255,255,255,0.025) 2px, transparent 2px)",
          backgroundSize: "36px 36px",
          opacity: 0.6,
        }}
      />
    </AbsoluteFill>
  );
};

/** The MacBook notch everything comes out of. */
const Notch: React.FC = () => (
  <div
    style={{
      position: "absolute", top: 0, left: "50%", transform: "translateX(-50%)",
      width: 380, height: 64, background: "#000", borderBottomLeftRadius: 34, borderBottomRightRadius: 34,
      boxShadow: "0 0 0 2px rgba(255,255,255,0.04)",
    }}
  />
);

const Kicker: React.FC<{ children: React.ReactNode; color: string; delay?: number }> = ({ children, color, delay = 0 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const show = spring({ frame: frame - delay, fps, config: { damping: 200 } });
  return (
    <div style={{ fontFamily: pixel, fontSize: 34, color, letterSpacing: 2, opacity: show, transform: `translateY(${(1 - show) * 20}px)` }}>
      {children}
    </div>
  );
};

const Headline: React.FC<{ children: React.ReactNode; delay?: number; size?: number }> = ({ children, delay = 4, size = 84 }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const show = spring({ frame: frame - delay, fps, config: { damping: 18, stiffness: 140 } });
  return (
    <div
      style={{
        fontFamily: inter, fontWeight: 800, fontSize: size, lineHeight: 1.04, color: "white", letterSpacing: -2,
        opacity: show, transform: `translateY(${(1 - show) * 40}px)`, whiteSpace: "pre-line",
      }}
    >
      {children}
    </div>
  );
};

const Caption: React.FC<{ children: React.ReactNode; delay?: number }> = ({ children, delay = 14 }) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [delay, delay + 12], [0, 1], clamp);
  return <div style={{ fontFamily: inter, fontWeight: 500, fontSize: 40, color: "rgba(255,255,255,0.68)", opacity, lineHeight: 1.3 }}>{children}</div>;
};

/** A screenshot that drops out of the notch like the real panel does. */
const Panel: React.FC<{ src: string; width: number; delay?: number; top: number }> = ({ src, width, delay = 6, top }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const open = spring({ frame: frame - delay, fps, config: { damping: 16, stiffness: 120 } });
  return (
    <div
      style={{
        position: "absolute", left: "50%", top, width,
        transform: `translateX(-50%) scale(${0.6 + 0.4 * open}, ${0.2 + 0.8 * open})`, transformOrigin: "top center",
        opacity: Math.min(1, open * 1.5), borderRadius: 40, overflow: "hidden",
        boxShadow: "0 40px 120px rgba(0,0,0,0.7), 0 0 0 2px rgba(255,255,255,0.06)",
      }}
    >
      <Img src={staticFile(src)} style={{ width: "100%", display: "block" }} />
    </div>
  );
};

const Keycap: React.FC<{ label: string; pressAt: number }> = ({ label, pressAt }) => {
  const frame = useCurrentFrame();
  const pressed = frame >= pressAt && frame < pressAt + 8;
  return (
    <div
      style={{
        fontFamily: inter, fontWeight: 700, fontSize: 44, color: "white", padding: "18px 30px", borderRadius: 22,
        background: pressed ? "#3A3F4B" : "#1B1E25", boxShadow: pressed ? "0 2px 0 #000" : "0 8px 0 #000",
        transform: `translateY(${pressed ? 6 : 0}px)`, border: "2px solid rgba(255,255,255,0.08)",
      }}
    >
      {label}
    </div>
  );
};

const Copy: React.FC<{ children: React.ReactNode; top: number }> = ({ children, top }) => (
  <div style={{ position: "absolute", left: 90, right: 90, top, display: "flex", flexDirection: "column", gap: 26 }}>{children}</div>
);

// MARK: Scenes

const Intro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const fade = useSceneFade(S.intro[1] - S.intro[0]);
  // Molt drops out of the notch and lands with a squash.
  const drop = spring({ frame: frame - 6, fps, config: { damping: 9, stiffness: 90 } });
  const y = interpolate(drop, [0, 1], [-520, 300]);
  return (
    <AbsoluteFill style={{ opacity: fade }}>
      <div style={{ position: "absolute", left: "50%", top: y, transform: "translateX(-50%)" }}>
        <Molt loop={frame < 50 ? "happy" : "celebrate"} frames={frame < 50 ? 60 : 90} size={920} />
      </div>
      <Copy top={1240}>
        <Kicker color={AGENT.molt} delay={30}>MOLT 0.9</Kicker>
        <Headline delay={36} size={104}>{"Your agents,\nin your notch."}</Headline>
      </Copy>
    </AbsoluteFill>
  );
};

const Approval: React.FC = () => {
  const frame = useCurrentFrame();
  const fade = useSceneFade(S.approval[1] - S.approval[0]);
  const allowed = frame >= 120;
  const flash = interpolate(frame, [120, 128, 150], [0, 0.55, 0], clamp);
  return (
    <AbsoluteFill style={{ opacity: fade }}>
      <Panel src="crop-notch-approval.png" width={1000} top={64} />
      <div style={{ position: "absolute", left: 40, right: 40, top: 64, height: 224, borderRadius: 40, background: `rgba(93,204,140,${flash})` }} />
      <div style={{ position: "absolute", top: 400, left: 0, right: 0, display: "flex", justifyContent: "center", gap: 20, alignItems: "center" }}>
        <Keycap label="⌃" pressAt={112} />
        <Keycap label="⌥" pressAt={112} />
        <Keycap label="Y" pressAt={114} />
        <div style={{ fontFamily: inter, fontWeight: 700, fontSize: 40, color: allowed ? AGENT.molt : "rgba(255,255,255,0.4)", marginLeft: 14 }}>
          {allowed ? "Allowed" : "to allow"}
        </div>
      </div>
      <Copy top={1100}>
        <Kicker color={AGENT.claude}>ANSWER FROM THE NOTCH</Kicker>
        <Headline>{"Claude Code asks.\nYou answer, without\nleaving your work."}</Headline>
        <Caption delay={60}>What it wants to run, how risky it looks, and why. Allow it three times and Molt offers to remember it. Risky commands always ask.</Caption>
      </Copy>
    </AbsoluteFill>
  );
};

const AGENTS = ["Claude Code", "Codex", "Gemini CLI", "Cursor Agent", "OpenCode", "Amp", "Copilot CLI", "Aider", "Goose"];
const Agents: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const fade = useSceneFade(S.agents[1] - S.agents[0]);
  const phase = Math.floor(frame / 60) % 3;
  const loop = ["work-claude", "work-codex", "work-gemini"][phase];
  const name = ["Claude Code", "Codex", "Gemini CLI"][phase];
  const color = [AGENT.claude, AGENT.codex, AGENT.gemini][phase];
  return (
    <AbsoluteFill style={{ opacity: fade }}>
      <div style={{ position: "absolute", top: 20, left: "50%", transform: "translateX(-50%)", textAlign: "center" }}>
        <Molt loop={loop} frames={60} size={940} />
        <div style={{ fontFamily: pixel, fontSize: 44, color, marginTop: -250 }}>{name} is working</div>
      </div>
      <Copy top={1000}>
        <Kicker color={AGENT.codex}>MOLT MOLTS</Kicker>
        <Headline>{"Every agent,\nat a glance."}</Headline>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 16, marginTop: 6 }}>
          {AGENTS.map((agent, i) => {
            const show = spring({ frame: frame - 20 - i * 4, fps, config: { damping: 14 } });
            return (
              <div
                key={agent}
                style={{
                  fontFamily: inter, fontWeight: 700, fontSize: 34, color: "white", padding: "12px 24px", borderRadius: 40,
                  background: "rgba(255,255,255,0.08)", border: "2px solid rgba(255,255,255,0.1)",
                  transform: `scale(${show})`, opacity: show,
                }}
              >
                {agent}
              </div>
            );
          })}
        </div>
        <Caption delay={60}>Molt sits at its laptop in the color of whoever is working, and shows a ! when one needs you.</Caption>
      </Copy>
    </AbsoluteFill>
  );
};

const Finished: React.FC = () => {
  const fade = useSceneFade(S.finished[1] - S.finished[0]);
  return (
    <AbsoluteFill style={{ opacity: fade }}>
      <Panel src="crop-notch-finished.png" width={1000} top={64} />
      <div style={{ position: "absolute", top: 230, left: "50%", transform: "translateX(-50%)" }}>
        <Molt loop="celebrate" frames={90} size={980} />
      </div>
      <Copy top={1260}>
        <Kicker color={AGENT.codex}>DONE</Kicker>
        <Headline>{"Long task finished?\nYou'll know."}</Headline>
      </Copy>
    </AbsoluteFill>
  );
};

const CountUp: React.FC<{ to: number; suffix?: string; color: string; delay?: number }> = ({ to, suffix = "", color, delay = 10 }) => {
  const frame = useCurrentFrame();
  const value = Math.round(interpolate(frame, [delay, delay + 40], [0, to], { ...clamp, easing: Easing.out(Easing.cubic) }));
  return <span style={{ fontFamily: inter, fontWeight: 800, fontSize: 180, color, letterSpacing: -6 }}>{value}{suffix}</span>;
};

const Usage: React.FC = () => {
  const fade = useSceneFade(S.usage[1] - S.usage[0]);
  return (
    <AbsoluteFill style={{ opacity: fade }}>
      <Panel src="crop-notch-usage.png" width={1000} top={64} />
      <div style={{ position: "absolute", top: 470, left: 90, display: "flex", alignItems: "center", gap: 20 }}>
        <CountUp to={64} suffix="%" color={AGENT.claude} />
        <Molt loop="tired" frames={60} size={460} style={{ margin: -60 }} />
      </div>
      <Copy top={1010}>
        <Kicker color={AGENT.claude}>PLAN USAGE</Kicker>
        <Headline>{"At this pace,\nfull at 3:40 PM."}</Headline>
        <Caption delay={30}>Claude and Codex, 5-hour and weekly limits, with a forecast. Close to the limit, Molt gets sleepy.</Caption>
      </Copy>
    </AbsoluteFill>
  );
};

const GitHub: React.FC = () => {
  const fade = useSceneFade(S.github[1] - S.github[0]);
  return (
    <AbsoluteFill style={{ opacity: fade }}>
      <Panel src="crop-notch-github.png" width={1000} top={64} />
      <div style={{ position: "absolute", top: 470, left: 90, display: "flex", alignItems: "center", gap: 10 }}>
        <CountUp to={19} color={AGENT.molt} />
        <div style={{ fontFamily: inter, fontWeight: 700, fontSize: 48, color: "rgba(255,255,255,0.6)", lineHeight: 1.1 }}>day<br />streak</div>
        <Molt loop="worried" frames={60} size={440} style={{ margin: -60, marginLeft: 0 }} />
      </div>
      <Copy top={1010}>
        <Kicker color="#9BE59E">GITHUB</Kicker>
        <Headline>{"PRs, checks\nand your streak."}</Headline>
        <Caption delay={30}>Reviews waiting on you, and your default branch. If it turns red, Molt worries.</Caption>
      </Copy>
    </AbsoluteFill>
  );
};

const Chat: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const fade = useSceneFade(S.chat[1] - S.chat[0]);
  const services = [
    ["Ollama", true], ["LM Studio", true], ["Anthropic", false], ["OpenAI", false], ["Google", false], ["OpenRouter", false],
  ] as const;
  return (
    <AbsoluteFill style={{ opacity: fade }}>
      <Panel src="crop-notch-chat.png" width={1000} top={64} />
      <div style={{ position: "absolute", top: 470, left: 90, right: 90, display: "flex", flexWrap: "wrap", gap: 18 }}>
        {services.map(([name, local], i) => {
          const show = spring({ frame: frame - 12 - i * 5, fps, config: { damping: 14 } });
          return (
            <div key={name} style={{ display: "flex", alignItems: "center", gap: 14, fontFamily: inter, fontWeight: 700, fontSize: 40, color: "white", padding: "16px 28px", borderRadius: 50, background: "rgba(255,255,255,0.08)", transform: `scale(${show})` }}>
              <div style={{ width: 16, height: 16, borderRadius: 8, background: local ? AGENT.molt : "#F5A35C" }} />
              {name}
            </div>
          );
        })}
      </div>
      <Copy top={1060}>
        <Kicker color={AGENT.gemini}>CHAT</Kicker>
        <Headline>{"Any model.\nLocal first."}</Headline>
        <Caption delay={30}>Stay on your Mac with Ollama or LM Studio, or bring your own key. Lens can turn an error on screen into a prompt for your agent.</Caption>
      </Copy>
    </AbsoluteFill>
  );
};

const OUTFITS = [
  ["fit-pumpkin", "Pumpkin · October only"], ["fit-headphones", "Headphones"], ["fit-hardhat", "Hard hat · 25 agent tasks"],
  ["fit-halo", "Halo · 100 friend points"], ["fit-beanie", "Beanie"], ["fit-santa", "Winter hat · December"],
] as const;
const Wardrobe: React.FC = () => {
  const frame = useCurrentFrame();
  const fade = useSceneFade(S.wardrobe[1] - S.wardrobe[0]);
  const index = Math.min(OUTFITS.length - 1, Math.floor(frame / 28));
  const pop = interpolate(frame % 28, [0, 4, 10], [0.9, 1.06, 1], clamp);
  return (
    <AbsoluteFill style={{ opacity: fade }}>
      <div style={{ position: "absolute", top: 40, left: "50%", transform: `translateX(-50%) scale(${pop})`, textAlign: "center" }}>
        <Molt loop={OUTFITS[index][0]} frames={30} size={1000} />
        <div style={{ fontFamily: pixel, fontSize: 44, color: "#FFB067", marginTop: -250 }}>{OUTFITS[index][1]}</div>
      </div>
      <Copy top={1110}>
        <Kicker color="#FFB067">WARDROBE</Kicker>
        <Headline>{"Earn it.\nWear it."}</Headline>
        <Caption delay={30}>Sixteen pixel items, from caring for Molt, hanging out with friends, finishing agent work and keeping your streak.</Caption>
      </Copy>
    </AbsoluteFill>
  );
};

const Outro: React.FC = () => {
  const frame = useCurrentFrame();
  const fade = interpolate(frame, [0, 10], [0, 1], clamp);
  return (
    <AbsoluteFill style={{ opacity: fade }}>
      <div style={{ position: "absolute", top: 60, left: "50%", transform: "translateX(-50%)" }}>
        <Molt loop={frame < 90 ? "celebrate" : "love"} frames={frame < 90 ? 90 : 60} size={1000} />
      </div>
      <div style={{ position: "absolute", top: 1000, left: 0, right: 0, textAlign: "center", display: "flex", flexDirection: "column", gap: 24, alignItems: "center" }}>
        <Headline size={150}>Molt 0.9</Headline>
        <Caption delay={14}>Agents · approvals · plan usage · GitHub · any model · wardrobe</Caption>
        <div style={{ fontFamily: pixel, fontSize: 36, color: AGENT.molt, marginTop: 30, opacity: interpolate(frame, [30, 45], [0, 1], clamp) }}>
          FREE FOR MACOS · ON GITHUB
        </div>
      </div>
    </AbsoluteFill>
  );
};

export const MoltRelease: React.FC = () => {
  const scenes: [readonly [number, number], React.FC][] = [
    [S.intro, Intro], [S.approval, Approval], [S.agents, Agents], [S.finished, Finished], [S.usage, Usage],
    [S.github, GitHub], [S.chat, Chat], [S.wardrobe, Wardrobe], [S.outro, Outro],
  ];
  return (
    <AbsoluteFill>
      <Background />
      {scenes.map(([[from, to], Scene], i) => (
        <Sequence key={i} from={from} durationInFrames={to - from} premountFor={30}>
          <Scene />
        </Sequence>
      ))}
      <Notch />
    </AbsoluteFill>
  );
};
