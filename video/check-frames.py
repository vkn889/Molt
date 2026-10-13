# Finds frames that glitch or stall in a rendered video or a folder of frames: a frame that's far
# from what its two neighbours predict (a flash), or a repeated frame in the middle of motion
# (a stall). Hard cuts pass, since a cut frame matches the frame after it.
# Usage: python3 check-frames.py video.mp4 | --dir frames/ [--list]
import sys, os, subprocess, numpy as np
from PIL import Image

w, h = 108, 192
if sys.argv[1] == "--dir":
    d = sys.argv[2]
    names = sorted(f for f in os.listdir(d) if f.endswith(".png"))
    f = np.stack([np.asarray(Image.open(os.path.join(d, n)).convert("L").resize((w, h), Image.BILINEAR), dtype=np.float32) for n in names])
else:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", sys.argv[1], "-vf", f"scale={w}:{h}", "-f", "rawvideo", "-pix_fmt", "gray", "-"],
                         capture_output=True, check=True).stdout
    f = np.frombuffer(raw, np.uint8).reshape(-1, h, w).astype(np.float32)
d = np.abs(np.diff(f, axis=0)).mean(axis=(1, 2))
flashes, stalls = [], []
for i in range(1, len(f) - 1):
    predicted = (f[i - 1] + f[i + 1]) / 2
    err = np.abs(f[i] - predicted).mean()
    around = np.abs(f[i + 1] - f[i - 1]).mean()
    # Off from both neighbours by much more than they differ from each other.
    if err > 3 and err > 1.2 * around + 1 and min(d[i - 1], d[i]) > 3:
        flashes.append(i)
    if d[i] < 0.02 and i + 1 < len(d) and d[i - 1] > 0.6 and d[i + 1] > 0.6:
        stalls.append(i)
if "--list" in sys.argv:
    print(",".join(str(i) for i in sorted(set(flashes + stalls))))
else:
    print("frames", len(f))
    print("flashes", len(flashes), flashes[:60])
    print("stalls", len(stalls), stalls[:60])
