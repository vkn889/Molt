import React, { useEffect, useMemo, useState } from "react";
import { ThreeCanvas } from "@remotion/three";
import { useThree } from "@react-three/fiber";
import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";
import { AbsoluteFill, cancelRender, delayRender, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { GRAY, INK, SF, clamp, ease } from "./MoltAd";
import { Painter } from "./Painter";

// The many-Macs scene: one MacBook Pro becomes 2, 4, 8, 16 and 32 (version 3, one step per bar) or
// on up to 128 (version 4, one step every half bar), and every screen keeps changing to another
// Hub, outfit, color and wallpaper on the hits of the music.
//
// The model is public/v3/macbook.glb, made from the 16-inch MacBook Pro model by
// `make-macbook.py` with Blender: three meshes (Body, Dark and Screen), the screen mapped to
// a full 1728 × 1117 display. The screens are stills of the `MacScreen` composition.

const SCREENS = 32;
type Step = { cols: number; rows: number };
export const STEPS_32: Step[] = [
  { cols: 1, rows: 1 },
  { cols: 1, rows: 2 },
  { cols: 2, rows: 2 },
  { cols: 2, rows: 4 },
  { cols: 4, rows: 4 },
  { cols: 4, rows: 8 },
];
export const STEPS_128: Step[] = [...STEPS_32, { cols: 8, rows: 8 }, { cols: 8, rows: 16 }];
const SX = 1.16, SY = 1.0;
// At 10 units with a 30° field of view, the frame is 3.01 × 5.36 units.
const VIEW_W = 3.014, VIEW_H = 5.359;

type Parts = { body: THREE.BufferGeometry; dark: THREE.BufferGeometry; screen: THREE.BufferGeometry };

const useMacbook = () => {
  const [parts, setParts] = useState<Parts | null>(null);
  const [textures, setTextures] = useState<THREE.Texture[] | null>(null);
  const [handle] = useState(() => delayRender("Loading the MacBook model and screens"));
  useEffect(() => {
    const model = new GLTFLoader().loadAsync(staticFile("v3/macbook.glb")).then((gltf) => {
      const find = (name: string) => {
        let geometry: THREE.BufferGeometry | null = null;
        gltf.scene.traverse((o) => {
          if (!geometry && (o as THREE.Mesh).isMesh && o.name.startsWith(name)) geometry = (o as THREE.Mesh).geometry;
        });
        if (!geometry) throw new Error(`No ${name} mesh in macbook.glb`);
        // Centre the Mac on its own middle and make it one unit wide (the model is in centimetres).
        const g = (geometry as THREE.BufferGeometry).clone();
        g.translate(0, -11, 4);
        g.scale(1 / 35.5, 1 / 35.5, 1 / 35.5);
        return g;
      };
      return { body: find("Body"), dark: find("Dark"), screen: find("Screen") };
    });
    const loader = new THREE.TextureLoader();
    const screens = Promise.all(
      Array.from({ length: SCREENS }, (_, i) =>
        loader.loadAsync(staticFile(`v3/screens/${String(i).padStart(2, "0")}.jpg`)).then((t) => {
          t.colorSpace = THREE.SRGBColorSpace;
          // glTF UVs start at the top.
          t.flipY = false;
          t.anisotropy = 8;
          return t;
        }),
      ),
    );
    Promise.all([model, screens])
      .then(([p, t]) => {
        setParts(p);
        setTextures(t);
      })
      .catch((err) => cancelRender(err));
  }, [handle]);
  return { parts, textures, handle };
};

/** Soft studio reflections, so the aluminium reads as metal. */
const Studio: React.FC = () => {
  const { gl, scene } = useThree();
  useEffect(() => {
    const pmrem = new THREE.PMREMGenerator(gl);
    const env = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    scene.environment = env;
    scene.environmentIntensity = 1.4;
    return () => {
      env.dispose();
      pmrem.dispose();
    };
  }, [gl, scene]);
  return null;
};

const Mac: React.FC<{ parts: Parts; body: THREE.Material; dark: THREE.Material; screen: THREE.Texture; position: [number, number, number]; scale: number; tilt: number }> = ({
  parts, body, dark, screen, position, scale, tilt,
}) => {
  // Made with its first screen; later screens are a plain texture swap, with no shader rebuild.
  const material = useMemo(() => new THREE.MeshBasicMaterial({ toneMapped: false, map: screen }), []);
  if (material.map !== screen) material.map = screen;
  return (
    <group position={position} scale={scale} rotation={[0.32, tilt, 0]}>
      <mesh geometry={parts.body} material={body} />
      <mesh geometry={parts.dark} material={dark} />
      <mesh geometry={parts.screen} material={material} />
    </group>
  );
};

type GridProps = {
  from: number; to: number; hits: number[]; fast: number[];
  /** Version 3: one step per bar of this many frames. */
  bar?: number;
  /** Version 4: the steps, and the frame each one lands on. */
  steps?: Step[]; stepTimes?: number[];
  /** Draws "Make it yours." over the first steps; version 4 draws its titles in the trailer. */
  title?: boolean;
};

export const MacGrid: React.FC<GridProps> = ({ from, to, bar = 0, hits, fast, steps = STEPS_32, stepTimes, title: showTitle = true }) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const { parts, textures, handle } = useMacbook();
  const silver = useMemo(() => new THREE.MeshStandardMaterial({ color: "#e3e5e9", metalness: 0.55, roughness: 0.3 }), []);
  const black = useMemo(() => new THREE.MeshStandardMaterial({ color: "#55565c", metalness: 0.6, roughness: 0.36 }), []);
  const glass = useMemo(() => new THREE.MeshStandardMaterial({ color: "#050506", metalness: 0.2, roughness: 0.25 }), []);

  const local = frame - from;
  const STEPS = steps;
  const COLS = Math.max(...STEPS.map((x) => x.cols));
  const stepAt = (k: number) => (stepTimes ? stepTimes[Math.min(k, stepTimes.length - 1)] + (k >= stepTimes.length ? to - stepTimes[stepTimes.length - 1] : 0) : from + Math.round(k * bar));
  let step = 0;
  for (let k = 0; k < STEPS.length; k++) if (frame >= stepAt(k)) step = k;

  // The framing eases from one grid size to the next on each downbeat.
  const fit = (k: number) => {
    const { cols, rows } = STEPS[k];
    const w = cols * SX, h = rows * SY;
    // The first steps leave room for the headline.
    const room = k < 3 ? 0.62 : 0.8;
    return { s: Math.min((VIEW_W * 0.9) / w, (VIEW_H * room) / h), cx: ((cols - 1) * SX) / 2, cy: -((rows - 1) * SY) / 2 };
  };
  const prev = fit(Math.max(0, step - 1)), cur = fit(step);
  const t = step === 0 ? 1 : interpolate(frame, [stepAt(step), stepAt(step) + 14], [0, 1], { ...clamp, easing: ease });
  const s = Math.exp(interpolate(t, [0, 1], [Math.log(prev.s), Math.log(cur.s)]));
  const cx = interpolate(t, [0, 1], [prev.cx, cur.cx]);
  const cy = interpolate(t, [0, 1], [prev.cy, cur.cy]);
  // Room for the headline over the first few steps; then the Macs fill the frame.
  const lift = interpolate(frame, [stepAt(2), stepAt(3) + 14], [-0.18, 0], { ...clamp, easing: ease });
  // A slow drift, and a little push in on the last bar.
  const drift = interpolate(frame, [from, to], [0, 1]);
  // Version 3 pushes in over the bar after its last step; version 4 over its 128 Macs.
  const push = stepTimes
    ? interpolate(frame, [stepAt(STEPS.length - 1) + 14, to], [1, 1.1], { ...clamp, easing: ease })
    : interpolate(frame, [stepAt(6), stepAt(7)], [1, 1.12], { ...clamp, easing: ease });

  // Each hit moves every screen on to another design.
  const changes = [...hits, ...fast].filter((h) => frame >= h).length;

  const title = interpolate(frame, [from, from + 8, stepAt(3) - 6, stepAt(3)], [0, 1, 1, 0], clamp);
  const sub = interpolate(frame, [from + 6, from + 14], [0, 1], clamp);

  const macs: React.ReactNode[] = [];
  if (parts && textures) {
    const { cols, rows } = STEPS[step];
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const i = r * COLS + c;
        // A Mac arrives with the step that first includes it.
        let born = 0;
        while (c >= STEPS[born].cols || r >= STEPS[born].rows) born++;
        const pop = born === 0 ? 1 : spring({ frame: frame - stepAt(born) - ((r + c) % 3), fps, config: { damping: 14, stiffness: 160, mass: 0.6 } });
        const design = (i * 7 + changes * 5 + r) % SCREENS;
        macs.push(
          <Mac
            key={i}
            parts={parts}
            body={(r + c) % 3 === 1 ? black : silver}
            dark={glass}
            screen={textures[design]}
            position={[c * SX, -r * SY, 0]}
            scale={pop}
            tilt={Math.sin((local + i * 9) / 28) * 0.06}
          />,
        );
      }
    }
  }

  return (
    <AbsoluteFill style={{ background: "#fff" }}>
      <ThreeCanvas width={width} height={height} camera={{ position: [0, 0, 10], fov: 30 }} gl={{ antialias: true, preserveDrawingBuffer: true }}>
        <Studio />
        <ambientLight intensity={0.6} />
        <directionalLight position={[3, 6, 8]} intensity={1.6} />
        <directionalLight position={[-4, 2, 5]} intensity={0.5} />
        <group scale={s * push} position={[-cx * s * push, (-cy + lift) * s * push, 0]} rotation={[0, interpolate(drift, [0, 1], [-0.06, 0.06]), 0]}>
          {macs}
        </group>
        <Painter ready={!!parts && !!textures} handle={handle} />
      </ThreeCanvas>
      <div style={{ position: "absolute", top: 250, left: 50, right: 50, textAlign: "center", fontFamily: SF, opacity: showTitle ? title : 0 }}>
        <div style={{ fontSize: 86, fontWeight: 700, letterSpacing: -2.2, lineHeight: 1.05, color: INK }}>Make it yours.</div>
        <div style={{ marginTop: 22, fontSize: 40, fontWeight: 500, letterSpacing: -0.4, color: GRAY, opacity: sub }}>Every Hub, outfit and color.</div>
      </div>
    </AbsoluteFill>
  );
};
