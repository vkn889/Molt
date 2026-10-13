import React, { useEffect, useMemo, useState } from "react";
import { ThreeCanvas } from "@remotion/three";
import { useThree } from "@react-three/fiber";
import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";
import { AbsoluteFill, cancelRender, delayRender, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { clamp, ease } from "./MoltAd";
import { Painter } from "./Painter";

// A hero shot for version 4: one MacBook on a white stage, the camera circling it while its
// display changes on the beat. It's rendered on its own (`render-safe.mjs … --gl=angle`) and
// played back in the trailer, which draws the titles over it.
//
// The models are public/v4/m5.glb (a 14-inch MacBook Pro with M5) and public/v4/laptop.glb,
// made by `make-hero-macs.py`; each has a "Screen" mesh mapped to its whole display. The
// displays are stills of the HeroScreen compositions, in public/v4/screens.

export type HeroProps = {
  model: "m5" | "laptop"; screens: { at: number; screen: string }[]; orbit: [number, number];
  /** The camera's height angle over the shot, and how far the Mac sits below the middle. */
  pitch?: [number, number]; drop?: number;
};

type Loaded = { scene: THREE.Object3D; screen: THREE.Mesh; textures: Record<string, THREE.Texture>; floor: number };

const useModel = (model: string, names: string[]) => {
  const [loaded, setLoaded] = useState<Loaded | null>(null);
  const [handle] = useState(() => delayRender(`Loading the ${model} MacBook`));
  useEffect(() => {
    const gltf = new GLTFLoader().loadAsync(staticFile(`v4/${model}.glb`));
    const loader = new THREE.TextureLoader();
    const textures = Promise.all(
      names.map((name) =>
        loader.loadAsync(staticFile(`v4/screens/${model}-${name}.jpg`)).then((t) => {
          t.colorSpace = THREE.SRGBColorSpace;
          t.flipY = false;
          t.anisotropy = 8;
          return [name, t] as const;
        }),
      ),
    );
    Promise.all([gltf, textures])
      .then(([g, t]) => {
        const scene = g.scene;
        let screen: THREE.Mesh | null = null;
        scene.traverse((o) => {
          const mesh = o as THREE.Mesh;
          if (!mesh.isMesh) return;
          const material = mesh.material as THREE.Material;
          if (!screen && (o.name.startsWith("Screen") || o.parent?.name.startsWith("Screen") || material?.name === "Screen")) screen = mesh;
        });
        if (!screen) throw new Error(`No Screen mesh in ${model}.glb`);
        // Centre the Mac and make it one unit wide (with every node's transform applied first).
        scene.updateMatrixWorld(true);
        const box = new THREE.Box3().setFromObject(scene);
        const size = box.getSize(new THREE.Vector3()), centre = box.getCenter(new THREE.Vector3());
        const holder = new THREE.Group();
        scene.position.sub(centre);
        holder.add(scene);
        holder.scale.setScalar(1 / size.x);
        setLoaded({ scene: holder, screen, textures: Object.fromEntries(t), floor: -size.y / size.x / 2 });
      })
      .catch((err) => cancelRender(err));
  }, [model, handle]);
  return { loaded, handle };
};

/** Soft studio reflections, so the aluminium reads as metal. */
const Studio: React.FC = () => {
  const { gl, scene } = useThree();
  useEffect(() => {
    const pmrem = new THREE.PMREMGenerator(gl);
    const env = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    scene.environment = env;
    scene.environmentIntensity = 1.2;
    return () => {
      env.dispose();
      pmrem.dispose();
    };
  }, [gl, scene]);
  return null;
};

/** The camera on its circle around the Mac, set every frame. */
const Orbit: React.FC<{ yaw: number; pitch: number; distance: number }> = ({ yaw, pitch, distance }) => {
  const { camera } = useThree();
  camera.position.set(Math.sin(yaw) * Math.cos(pitch) * distance, Math.sin(pitch) * distance, Math.cos(yaw) * Math.cos(pitch) * distance);
  camera.lookAt(0, 0.06, 0);
  camera.updateMatrixWorld();
  return null;
};

/** A soft round shadow under the Mac, drawn once into a texture. */
const useShadow = () =>
  useMemo(() => {
    const c = document.createElement("canvas");
    c.width = c.height = 256;
    const g = c.getContext("2d")!;
    const r = g.createRadialGradient(128, 128, 0, 128, 128, 128);
    r.addColorStop(0, "rgba(0,0,0,0.42)");
    r.addColorStop(0.55, "rgba(0,0,0,0.16)");
    r.addColorStop(1, "rgba(0,0,0,0)");
    g.fillStyle = r;
    g.fillRect(0, 0, 256, 256);
    const t = new THREE.CanvasTexture(c);
    return new THREE.MeshBasicMaterial({ map: t, transparent: true, depthWrite: false });
  }, []);

export const HeroMac: React.FC<HeroProps> = ({ model, screens, orbit, pitch: tilt = [0.34, 0.22], drop = 0.22 }) => {
  const frame = useCurrentFrame();
  const { width, height, durationInFrames } = useVideoConfig();
  const names = useMemo(() => [...new Set(screens.map((s) => s.screen))], [screens]);
  const { loaded, handle } = useModel(model, names);
  const shadow = useShadow();
  const screenMaterial = useMemo(() => new THREE.MeshBasicMaterial({ toneMapped: false }), []);

  let current = screens[0].screen;
  for (const s of screens) if (frame >= s.at) current = s.screen;
  if (loaded) {
    if (loaded.screen.material !== screenMaterial) loaded.screen.material = screenMaterial;
    const map = loaded.textures[current];
    if (screenMaterial.map !== map) {
      // Swapping one texture for another needs no new shader; only the first one does.
      const first = !screenMaterial.map;
      screenMaterial.map = map;
      if (first) screenMaterial.needsUpdate = true;
    }
  }

  const t = interpolate(frame, [0, durationInFrames - 1], [0, 1], clamp);
  const yaw = interpolate(t, [0, 1], orbit, { easing: ease });
  const pitch = interpolate(t, [0, 1], tilt);
  const distance = interpolate(t, [0, 1], [5.7, 5.0]);

  return (
    <AbsoluteFill style={{ background: "#fff" }}>
      <ThreeCanvas width={width} height={height} camera={{ position: [0, 0, 4.5], fov: 30, near: 0.05, far: 50 }} gl={{ antialias: true, preserveDrawingBuffer: true }}>
        <Studio />
        <Orbit yaw={yaw} pitch={pitch} distance={distance} />
        <ambientLight intensity={0.5} />
        <directionalLight position={[2, 4, 3]} intensity={1.4} />
        <directionalLight position={[-3, 2, 2]} intensity={0.4} />
        {/* The Mac sits a little low, leaving the top of the frame for the titles. */}
        <group position={[0, -drop, 0]}>
          {loaded ? <primitive object={loaded.scene} /> : null}
          <mesh material={shadow} rotation={[-Math.PI / 2, 0, 0]} position={[0, (loaded?.floor ?? -0.3) - 0.002, 0]} scale={[1.5, 1.1, 1]}>
            <planeGeometry args={[1, 1]} />
          </mesh>
        </group>
        <Painter ready={!!loaded} handle={handle} />
      </ThreeCanvas>
    </AbsoluteFill>
  );
};
