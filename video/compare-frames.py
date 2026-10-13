# Compares rendered frames. With two files, prints their mean absolute difference (0–255) at a
# reduced size. With --dirs a b, prints the frame numbers where two passes disagree.
import sys, os, numpy as np
from PIL import Image

def small(p):
    return np.asarray(Image.open(p).convert("RGB").resize((216, 384), Image.BILINEAR), dtype=np.float32)

if sys.argv[1] == "--dirs":
    a, b = sys.argv[2], sys.argv[3]
    names = sorted(f for f in os.listdir(a) if f.endswith(".png"))
    bad = []
    for f in names:
        if np.abs(small(os.path.join(a, f)) - small(os.path.join(b, f))).mean() > 0.5:
            bad.append(str(int(f[:-4])))
    print(",".join(bad))
else:
    print(float(np.abs(small(sys.argv[1]) - small(sys.argv[2])).mean()))
