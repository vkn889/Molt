# An ominous 8-bit score for the teaser: a detuned low drone, a slow heartbeat, a harmonic-minor
# arpeggio, a falling lead and a noise riser that cuts out just before the boom.
# Usage: python3 make-chiptune.py out.wav [seconds]
import sys, wave, numpy as np

SR = 44100
LENGTH = float(sys.argv[2]) if len(sys.argv) > 2 else 15.4
N = int(SR * (LENGTH + 3))
t = np.arange(N) / SR
mix = np.zeros(N)

def hz(m): return 440 * 2 ** ((m - 69) / 12)

def square(f, n, duty=0.5, start=0.0):
    ph = (start + np.arange(n) * f / SR) % 1
    return np.where(ph < duty, 1.0, -1.0)

def lowpass(x, a):
    """A one-pole low-pass; `a` may change over time."""
    a = np.broadcast_to(np.asarray(a, dtype=float), x.shape)
    y = np.zeros_like(x)
    for i in range(1, len(x)): y[i] = y[i - 1] + a[i] * (x[i] - y[i - 1])
    return y

def place(start, seg):
    i = int(start * SR); end = min(N, i + len(seg)); mix[i:end] += seg[: end - i]

# A low D, two pulse voices slightly apart so they beat against each other, swelling in.
drone = (square(hz(38), N, 0.5) + square(hz(38) * 1.006, N, 0.3)) * 0.5
drone = lowpass(drone, 0.04) * np.minimum(1, t / 4) * 0.55
mix += drone

# A heartbeat: two thumps every two seconds, an 8-bit kick falling in pitch.
def thump(amp):
    n = int(0.28 * SR); k = np.arange(n) / SR
    f = 45 + 95 * np.exp(-k / 0.04)
    ph = np.cumsum(f / SR) % 1
    return (4 * np.abs(ph - 0.5) - 1) * np.exp(-k / 0.09) * amp
for beat in np.arange(2.0, LENGTH - 0.6, 2.0):
    place(beat, thump(0.9)); place(beat + 0.32, thump(0.55))

# D harmonic minor, slow and quiet: D F A Bb, then C# for the unease.
ARP = [62, 65, 69, 70, 69, 65, 62, 61]
E = 0.5
for k, m in enumerate(ARP * 6):
    at = 1.0 + k * E
    if at > LENGTH - 0.8: break
    n = int(0.45 * SR)
    seg = square(hz(m), n, 0.125) * np.exp(-np.arange(n) / SR / 0.18) * 0.16
    place(at, seg)

# A falling lead from the second phrase on.
LEAD = [(5.0, 74, 1.5), (6.5, 73, 0.5), (7.0, 70, 2.0), (9.0, 69, 1.0), (10.0, 67, 1.0), (11.0, 66, 2.0), (13.0, 62, 2.2)]
for at, m, ln in LEAD:
    n = int((ln + 0.4) * SR); k = np.arange(n) / SR
    vib = 1 + 0.006 * np.sin(2 * np.pi * 4.5 * k) * np.minimum(1, k / 0.5)
    ph = np.cumsum(hz(m) * vib / SR) % 1
    env = np.minimum(1, k / 0.08) * np.where(k < ln, 1, np.exp(-(k - ln) / 0.1))
    place(at, np.where(ph < 0.25, 1.0, -1.0) * env * 0.12)

# A noise riser: 8-bit style random steps, opening up over the last few seconds.
rng = np.random.default_rng(7)
steps = np.repeat(rng.choice([-1.0, 1.0], N // 8 + 1), 8)[:N]
rise = np.clip((t - (LENGTH - 5)) / 5, 0, 1) ** 2
mix += lowpass(steps, 0.02 + 0.25 * rise) * rise * 0.35

# Long echoes, then cut to silence just before the boom.
d = int(SR * 0.75)
out = mix.copy()
for k in range(1, 5): out[d * k:] += mix[: N - d * k] * 0.38 ** k
out *= np.clip((LENGTH - t) / 0.12, 0, 1)
out /= np.max(np.abs(out)) / 0.75
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((out[: int(SR * (LENGTH + 0.1))] * 32767).astype("<i2").tobytes())
