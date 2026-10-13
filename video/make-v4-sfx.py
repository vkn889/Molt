# Sound effects for the version 4 intro: a woosh as Molt flies up out of space, and a quiet,
# low ambience for space itself.
# Usage: python3 make-v4-sfx.py <out-dir>
import sys, wave, numpy as np

SR = 44100
rng = np.random.default_rng(3)

def save(path, left, right):
    st = np.stack([left, right], axis=1)
    st /= np.max(np.abs(st)) / 0.9
    with wave.open(path, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((st * 32767).astype("<i2").tobytes())

def onepole(x, a):
    y = np.zeros_like(x); acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc); y[i] = acc
    return y

# The woosh: noise through a band that sweeps up and back down, peaking 0.55 s in, with a low
# sweep under it for weight, passing from left to right.
n = int(1.4 * SR); t = np.arange(n) / SR
peak = 0.55
env = np.where(t < peak, (t / peak) ** 2.2, np.exp(-(t - peak) / 0.22))
centre = 350 + 2600 * np.exp(-((t - peak) / 0.22) ** 2)
a_hi = 1 - np.exp(-2 * np.pi * centre * 1.6 / SR)
a_lo = 1 - np.exp(-2 * np.pi * centre * 0.5 / SR)
noise = rng.standard_normal(n)
band = onepole(noise, a_hi) - onepole(noise, a_lo)
f = 70 + 90 * np.exp(-((t - peak) / 0.25) ** 2)
body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-((t - peak) / 0.3) ** 2) * 0.5
mono = band * env * 3 + body
pan = np.clip((t - 0.15) / 0.9, 0, 1)
save(f"{sys.argv[1]}/woosh.wav", mono * np.cos(pan * np.pi / 2) * 1.2, mono * np.sin(pan * np.pi / 2) * 1.2)

# Space: two low tones drifting against each other and a breath of filtered noise.
n = int(10 * SR); t = np.arange(n) / SR
drone = np.sin(2 * np.pi * 55 * t) * 0.5 + np.sin(2 * np.pi * 82.6 * t + np.sin(t * 0.7)) * 0.3
air = onepole(rng.standard_normal(n), np.full(n, 0.01)) * 6
amb = (drone * (0.75 + 0.25 * np.sin(2 * np.pi * t / 6)) + air) * np.minimum(1, t / 2) * np.minimum(1, (10 - t) / 2)
save(f"{sys.argv[1]}/space.wav", amb * 0.98, amb)
