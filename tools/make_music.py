"""The game's music (v0.12.16), composed and synthesised from scratch (no samples, nothing borrowed): numpy additive
synthesis for strings, brass, choir, harp, flute, organ, bells and a drum kit (kick, snare, hats, taiko, timpani, toms,
crash), a synthetic-reverb hall, and seamless loops (each loop is rendered twice through the reverb and the second
pass kept, so the tail of the end rings into the start).

    python tools/make_music.py            # writes assets/music/*.ogg (needs numpy, scipy and ffmpeg)

Pieces (scripts/music.gd decides which plays):
  menu.ogg        A minor, 70 bpm, 16 bars: harp, pad, a soft choir, the boss's motif on bells.
  explore.ogg     F major, 84 bpm, 32 bars: harp arpeggios, a warm pad, a flute tune, soft bass, a shaker.
  combat.ogg      E minor, 128 bpm, 16 bars: drums, a driving bass, string stabs and ostinato, a brass call.
  boss_*.ogg      Thunderhorn, D minor, 140 bpm, 16 bars, in layers that play together in sync and are faded in
                  and out with the fight: pad (strings), timp (timpani), bass, drums, lead (brass theme),
                  corrupt (dissonant choir and organ: after the Duel Stone's corruption), fast (double-time drums
                  and spiccato strings: enraged), storm (tremolo strings, thunder, bells: his last quarter).
  cutscene.ogg    the corruption cutscene's score, 14 s, timed to Cutscene's moments (the slam at 4.47 s, the
                  corruption, the rising, the eyes, the twitching, the snap and the drawn weapons at 11.57 s).
  levelup.ogg, mastery.ogg, boss_fall.ogg, defeat.ogg   short cues.
"""
import os
import subprocess
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, fftconvolve, lfilter

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "music")
RNG = np.random.default_rng(20261106)


# ================================================================ basics
def mtof(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def n_of(sec):
    return max(int(round(sec * SR)), 1)


def lowpass(x, fc, order=2):
    b, a = butter(order, min(fc, SR * 0.45) / (SR / 2), "low")
    return lfilter(b, a, x)


def highpass(x, fc, order=2):
    b, a = butter(order, fc / (SR / 2), "high")
    return lfilter(b, a, x)


def bandpass(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), min(hi, SR * 0.45) / (SR / 2)], "band")
    return lfilter(b, a, x)


def env(total, hold, a, d, s, r):
    """Attack a, decay d to sustain s while held (hold seconds), then release r. total: the length rendered."""
    t = np.arange(n_of(total)) / SR
    e = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    at_rel = (hold / max(a, 1e-4)) if hold < a else s + (1 - s) * np.exp(-(hold - a) / max(d, 1e-4))
    e = np.where(t > hold, at_rel * np.exp(-(t - hold) / max(r, 1e-4)), e)
    return e


def phase_of(freq):
    """freq: an array (Hz per sample) -> phase in cycles."""
    return np.cumsum(freq) / SR


def saw(freq, top=9000.0, kmax=28):
    """A band-limited saw: harmonics up to `top` Hz."""
    ph = phase_of(freq)
    f0 = float(np.mean(freq))
    k_n = int(max(1, min(kmax, top // max(f0, 1.0))))
    out = np.zeros_like(ph)
    off = RNG.random()
    for k in range(1, k_n + 1):
        out += np.sin(2 * np.pi * (k * ph + off * k)) / k
    return out * 0.6


def vib(f, n, rate=5.5, depth=0.004, delay=0.25):
    t = np.arange(n) / SR
    ramp = np.clip((t - delay) / 0.4, 0, 1)
    return f * (1 + depth * ramp * np.sin(2 * np.pi * rate * t + RNG.random() * 6))


def cents(c):
    return 2 ** (c / 1200.0)


# ================================================================ instruments (mono)
def strings(m, hold, vel=1.0, bright=3600.0, a=0.25, r=0.7, voices=5, s=0.85):
    total = hold + r * 4
    n = n_of(total)
    f = mtof(m)
    out = np.zeros(n)
    for v in range(voices):
        det = cents((v - (voices - 1) / 2) * 6)
        out += saw(vib(f * det, n, 5.2 + RNG.random(), 0.004))
    out = lowpass(out / voices, bright)
    return out * env(total, hold, a, 0.6, s, r) * vel


def pad(m, hold, vel=1.0):
    return strings(m, hold, vel, bright=1700.0, a=0.7, r=1.4, voices=4)


def spicc(m, hold, vel=1.0):
    return strings(m, hold, vel, bright=4200.0, a=0.008, r=0.06, voices=3, s=0.25)


def tremolo(m, hold, vel=1.0, rate=13.0):
    x = strings(m, hold, vel, bright=5000.0, a=0.15, r=0.5, voices=4)
    t = np.arange(len(x)) / SR
    return x * (0.55 + 0.45 * np.abs(np.sin(np.pi * rate * t)))


def brass(m, hold, vel=1.0):
    total = hold + 1.0
    n = n_of(total)
    f = mtof(m)
    x = np.zeros(n)
    for c in (-5, 0, 5):
        x += saw(vib(f * cents(c), n, 5.0, 0.003, 0.35), top=7000)
    x /= 3
    dark = lowpass(x, 700)
    bright = lowpass(x, 4200 * (0.6 + 0.4 * vel))
    t = np.arange(n) / SR
    fe = 0.35 + 0.65 * np.exp(-t / 0.22)
    return (dark + (bright - dark) * fe) * env(total, hold, 0.035, 0.3, 0.8, 0.22) * vel


def bass(m, hold, vel=1.0):
    total = hold + 0.4
    n = n_of(total)
    f = mtof(m)
    t = np.arange(n) / SR
    x = saw(np.full(n, f), top=2500) * 0.8 + np.sin(2 * np.pi * f * t) * 0.6
    fe = np.exp(-t / 0.12)
    x = lowpass(x, 400) + (lowpass(x, 1800) - lowpass(x, 400)) * fe
    return x * env(total, hold, 0.004, 0.15, 0.7, 0.07) * vel


def pluck(m, ring=2.5, vel=1.0, dark=1.0):
    """A harp: harmonics dying away, the high ones first."""
    n = n_of(ring)
    f = mtof(m)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for k in range(1, 12):
        if f * k > 10000:
            break
        x += np.sin(2 * np.pi * f * k * t + RNG.random()) * np.exp(-t * (1.2 + k * 0.9 * dark)) / k ** 1.3
    x *= np.minimum(t / 0.002, 1.0)
    return x * vel


def flute(m, hold, vel=1.0):
    total = hold + 0.5
    n = n_of(total)
    f = vib(mtof(m), n, 5.0, 0.006, 0.3)
    ph = phase_of(f)
    x = np.sin(2 * np.pi * ph) + 0.25 * np.sin(4 * np.pi * ph) + 0.07 * np.sin(6 * np.pi * ph)
    breath = bandpass(RNG.standard_normal(n), mtof(m) * 1.5, mtof(m) * 3) * 0.08
    return (x + breath) * env(total, hold, 0.07, 0.2, 0.9, 0.15) * vel


def choir(m, hold, vel=1.0, vowel="a"):
    total = hold + 2.0
    n = n_of(total)
    form = {"a": [(730, 1.0), (1090, 0.5), (2440, 0.25)], "o": [(570, 1.0), (840, 0.45), (2410, 0.15)],
            "u": [(300, 1.0), (870, 0.3), (2240, 0.1)]}[vowel]
    out = np.zeros(n)
    for c in (-12, -4, 4, 12):
        x = saw(vib(mtof(m) * cents(c), n, 5.0 + RNG.random(), 0.006, 0.2), top=6000)
        y = np.zeros(n)
        for fc, g in form:
            y += bandpass(x, fc * 0.85, fc * 1.15) * g
        out += y
    return out / 4 * 3.0 * env(total, hold, 0.6, 1.0, 0.9, 0.9) * vel


def organ(m, hold, vel=1.0):
    total = hold + 0.8
    n = n_of(total)
    t = np.arange(n) / SR
    f = mtof(m)
    x = sum(w * np.sin(2 * np.pi * f * k * t) for k, w in ((0.5, 0.6), (1, 1.0), (2, 0.5), (3, 0.3), (4, 0.25)))
    return x * env(total, hold, 0.08, 0.5, 0.9, 0.5) * vel * 0.5


def bell(m, ring=3.0, vel=1.0):
    n = n_of(ring)
    t = np.arange(n) / SR
    f = mtof(m)
    idx = 2.5 * np.exp(-t * 2.0) + 0.3
    x = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * 3.5 * t)) * np.exp(-t * 1.3)
    x += 0.3 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 2.5)
    return x * np.minimum(t / 0.002, 1.0) * vel * 0.6


# drums
def kick(vel=1.0):
    n = n_of(0.5)
    t = np.arange(n) / SR
    ph = phase_of(45 + 110 * np.exp(-t * 30))
    x = np.sin(2 * np.pi * ph) * np.exp(-t * 6) + RNG.standard_normal(n) * np.exp(-t * 300) * 0.3
    return x * vel


def snare(vel=1.0):
    n = n_of(0.35)
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 20) * 0.5
    nz = bandpass(RNG.standard_normal(n), 1000, 8000) * np.exp(-t * 14)
    return (tone + nz) * vel


def hat(vel=1.0, open_=False):
    n = n_of(0.5 if open_ else 0.08)
    t = np.arange(n) / SR
    return highpass(RNG.standard_normal(n), 7000) * np.exp(-t * (7 if open_ else 50)) * vel * 0.5


def taiko(vel=1.0):
    n = n_of(1.2)
    t = np.arange(n) / SR
    ph = phase_of(62 + 45 * np.exp(-t * 14))
    x = np.sin(2 * np.pi * ph) * np.exp(-t * 3.5) + lowpass(RNG.standard_normal(n), 500) * np.exp(-t * 9) * 0.6
    return x * vel


def timpani(m, vel=1.0, ring=2.2):
    n = n_of(ring)
    t = np.arange(n) / SR
    f = mtof(m)
    x = np.zeros(n)
    for r, g in ((1.0, 1.0), (1.5, 0.5), (1.98, 0.35), (2.44, 0.2)):
        x += np.sin(2 * np.pi * f * r * t * (1 + 0.02 * np.exp(-t * 8))) * g * np.exp(-t * (1.4 + r * 0.6))
    x += lowpass(RNG.standard_normal(n), 900) * np.exp(-t * 25) * 0.4
    return x * vel


def tom(m, vel=1.0):
    n = n_of(0.6)
    t = np.arange(n) / SR
    ph = phase_of(mtof(m) * (1 + 0.5 * np.exp(-t * 20)))
    return np.sin(2 * np.pi * ph) * np.exp(-t * 7) * vel


def crash(vel=1.0, ring=2.8):
    n = n_of(ring)
    t = np.arange(n) / SR
    x = highpass(RNG.standard_normal(n), 3500) * np.exp(-t * 1.6)
    for f in (3150, 4430, 5870, 7220):
        x += 0.08 * np.sin(2 * np.pi * f * t + RNG.random() * 6) * np.exp(-t * 2.2)
    return x * vel * 0.6


def thunder(sec=3.5, vel=1.0):
    n = n_of(sec)
    t = np.arange(n) / SR
    rum = lowpass(RNG.standard_normal(n), 220, 4)
    mod = lowpass(np.abs(RNG.standard_normal(n)), 6, 1)
    mod /= max(mod.max(), 1e-6)
    return rum * (0.3 + mod) * np.minimum(t / 0.05, 1) * np.exp(-t * 0.9) * vel * 4.0


def swell(sec=1.5, vel=1.0):
    """A reversed cymbal: rising into the beat it ends on."""
    return crash(vel, sec)[::-1]


def shaker(vel=1.0):
    n = n_of(0.09)
    t = np.arange(n) / SR
    return bandpass(RNG.standard_normal(n), 5000, 12000) * np.sin(np.pi * t / t[-1]) * vel * 0.35


# ================================================================ mixing
class Mix:
    def __init__(self, sec):
        self.n = n_of(sec)
        self.L = np.zeros(self.n)
        self.R = np.zeros(self.n)

    def add(self, sig, at, pan=0.0, gain=1.0):
        i = n_of(at) if at > 0 else 0
        if i >= self.n:
            return
        sig = sig[: self.n - i] * gain
        gl = np.cos((pan + 1) * np.pi / 4)
        gr = np.sin((pan + 1) * np.pi / 4)
        self.L[i:i + len(sig)] += sig * gl
        self.R[i:i + len(sig)] += sig * gr


_IR = {}


def reverb(L, R, wet=0.25, rt=2.2):
    key = rt
    if key not in _IR:
        n = n_of(rt * 1.2)
        t = np.arange(n) / SR
        dec = np.exp(-t * 6.9 / rt)
        pre = n_of(0.02)
        irs = []
        for _ in range(2):
            ir = RNG.standard_normal(n) * dec
            ir = lowpass(ir, 6000)
            ir[:pre] = 0
            irs.append(ir / np.sqrt(np.sum(ir ** 2)))
        _IR[key] = irs
    il, ir_ = _IR[key]
    wl = fftconvolve(L, il)[: len(L)]
    wr = fftconvolve(R, ir_)[: len(R)]
    return L * (1 - wet * 0.5) + wl * wet, R * (1 - wet * 0.5) + wr * wet


def render_loop(sec, compose, wet=0.25, rt=2.2):
    """compose(mix, offset) puts one pass of the loop at `offset`; two passes go through the reverb and the second is
    kept, so the loop wraps seamlessly (the first pass's tails ring into the start)."""
    m = Mix(sec * 2)
    compose(m, 0.0)
    compose(m, sec)
    L, R = reverb(m.L, m.R, wet, rt)
    a = n_of(sec)
    return L[a:a * 2].copy(), R[a:a * 2].copy()


def render_once(sec, compose, wet=0.25, rt=2.2):
    m = Mix(sec)
    compose(m, 0.0)
    return reverb(m.L, m.R, wet, rt)


def limit(L, R, peak=0.85):
    L = np.tanh(L * 1.2) / 1.2
    R = np.tanh(R * 1.2) / 1.2
    p = max(np.abs(L).max(), np.abs(R).max(), 1e-6)
    return L * peak / p, R * peak / p


def save(name, L, R, quality=5):
    os.makedirs(OUT, exist_ok=True)
    wav = os.path.join(OUT, name + ".wav")
    ogg = os.path.join(OUT, name + ".ogg")
    st = np.stack([L, R], axis=1)
    wavfile.write(wav, SR, (np.clip(st, -1, 1) * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", str(quality), ogg],
                   check=True)
    os.remove(wav)
    print("  %-14s %5.1f s  %4d KB" % (name, len(L) / SR, os.path.getsize(ogg) // 1024))


def chord_notes(root, kind, base=0):
    iv = {"m": [0, 3, 7], "M": [0, 4, 7], "7": [0, 4, 7, 10], "m7": [0, 3, 7, 10], "sus": [0, 5, 7]}[kind]
    return [root + base + i for i in iv]


# ================================================================ Thunderhorn (D minor, 140 bpm, 16 bars)
B_BPM = 140
B_BEAT = 60.0 / B_BPM
B_BARS = 16
B_SEC = B_BARS * 4 * B_BEAT
# a chord every 2 bars: root (MIDI, octave 3), quality
B_CHORDS = [(50, "m"), (46, "M"), (43, "m"), (45, "M"), (50, "m"), (41, "M"), (46, "M"), (45, "7")]
B_LEAD = [  # (bar, beat, beats, note)
    (0, 0, 1.5, 62), (0, 1.5, .5, 65), (0, 2, 1, 69), (0, 3, 1, 67), (1, 0, 2, 65), (1, 2, 1, 64), (1, 3, 1, 62),
    (2, 0, 1.5, 62), (2, 1.5, .5, 65), (2, 2, 1, 70), (2, 3, 1, 69), (3, 0, 3, 65), (3, 3, 1, 67),
    (4, 0, 1.5, 67), (4, 1.5, .5, 70), (4, 2, 1, 74), (4, 3, 1, 72), (5, 0, 2, 70), (5, 2, 1, 69), (5, 3, 1, 67),
    (6, 0, 1, 69), (6, 1, 1, 73), (6, 2, 1, 76), (6, 3, 1, 73), (7, 0, 3, 69),
    (8, 0, 1, 74), (8, 1, .5, 72), (8, 1.5, .5, 70), (8, 2, 2, 69), (9, 0, 1, 65), (9, 1, 1, 67), (9, 2, 2, 69),
    (10, 0, 1, 72), (10, 1, .5, 70), (10, 1.5, .5, 69), (10, 2, 2, 65), (11, 0, 1, 64), (11, 1, 1, 65), (11, 2, 2, 67),
    (12, 0, 1.5, 70), (12, 1.5, .5, 69), (12, 2, 1, 67), (12, 3, 1, 65), (13, 0, 2, 67), (13, 2, 2, 62),
    (14, 0, 1, 64), (14, 1, 1, 67), (14, 2, 1, 73), (14, 3, 1, 76), (15, 0, 2, 73), (15, 2, 2, 69)]


def b_at(bar, beat=0.0):
    return (bar * 4 + beat) * B_BEAT


def boss_pad(m, o):
    for i, (r, q) in enumerate(B_CHORDS):
        for k, nn in enumerate(chord_notes(r, q, 0) + [r + 12]):
            m.add(strings(nn, 8 * B_BEAT - 0.05, 0.32, bright=2600, a=0.35), o + b_at(i * 2), pan=-0.4 + 0.27 * k)
        m.add(strings(r - 12, 8 * B_BEAT - 0.05, 0.35, bright=1200, a=0.3), o + b_at(i * 2), pan=0)


def boss_timp(m, o):
    for bar in range(B_BARS):
        r = B_CHORDS[bar // 2][0] - 12
        m.add(timpani(r, 0.9), o + b_at(bar), pan=0.1)
        if bar % 2 == 1:
            m.add(timpani(r + 7, 0.5), o + b_at(bar, 2.5), pan=0.15)
        if bar in (7, 15):   # a roll into the next phrase
            for k in range(16):
                m.add(timpani(r, 0.25 + 0.04 * k, 0.6), o + b_at(bar, 2 + k * 0.125), pan=0.1)


def boss_bass(m, o):
    pat = [0, 0, 12, 0, 0, 12, 0, 7]
    for bar in range(B_BARS):
        r = B_CHORDS[bar // 2][0] - 12
        for e, iv in enumerate(pat):
            m.add(bass(r + iv, B_BEAT * 0.45, 0.9 if e in (0, 3, 6) else 0.65), o + b_at(bar, e * 0.5))


def boss_drums(m, o):
    for bar in range(B_BARS):
        for b in (0, 1.5, 2, 3.5):
            m.add(taiko(0.9 if b in (0, 2) else 0.6), o + b_at(bar, b), pan=-0.1)
            m.add(kick(0.7), o + b_at(bar, b))
        for b in (1, 3):
            m.add(snare(0.7), o + b_at(bar, b), pan=0.1)
        for e in range(8):
            m.add(hat(0.35 if e % 2 else 0.5), o + b_at(bar, e * 0.5), pan=0.35)
        if bar in (7, 15):
            for k, t in enumerate((45, 43, 41, 38)):
                m.add(tom(t + 12, 0.8), o + b_at(bar, 3 + k * 0.25), pan=-0.3 + 0.2 * k)
        if bar in (0, 8):
            m.add(crash(0.7), o + b_at(bar), pan=-0.3)


def boss_lead(m, o):
    for bar, beat, ln, nn in B_LEAD:
        m.add(brass(nn, ln * B_BEAT * 0.95, 0.75), o + b_at(bar, beat), pan=0.1)
        m.add(brass(nn - 12, ln * B_BEAT * 0.95, 0.4), o + b_at(bar, beat), pan=-0.1)


def boss_corrupt(m, o):
    for i, (r, q) in enumerate(B_CHORDS):
        root = r + 12
        for k, nn in enumerate((root, root + 1, root + 6)):   # a root, a semitone, a tritone: wrong
            m.add(choir(nn, 8 * B_BEAT - 0.6, 0.3, "a" if i % 2 else "o"), o + b_at(i * 2), pan=-0.5 + 0.5 * k)
        m.add(swell(1.6, 0.5), o + b_at(i * 2) - 1.6, pan=0.4)
    m.add(organ(26, B_SEC - 0.3, 0.55), o, pan=0)      # a low D drone
    m.add(organ(32, B_SEC - 0.3, 0.35), o, pan=0)      # and the tritone above it


def boss_fast(m, o):
    for bar in range(B_BARS):
        r, q = B_CHORDS[bar // 2]
        tones = chord_notes(r, q, 12)
        arp = tones + [tones[0] + 12] + tones[::-1]
        for s in range(16):
            m.add(spicc(arp[s % len(arp)], B_BEAT * 0.2, 0.45), o + b_at(bar, s * 0.25), pan=0.5 if s % 2 else 0.3)
            m.add(hat(0.25 if s % 4 else 0.4), o + b_at(bar, s * 0.25), pan=-0.4)
        for b in (0.75, 2.75):
            m.add(kick(0.6), o + b_at(bar, b))
        for b in (1.75, 3.25, 3.75):
            m.add(snare(0.3), o + b_at(bar, b), pan=0.1)
        if bar % 4 == 3:
            for k in range(8):
                m.add(tom(50 - k, 0.6), o + b_at(bar, 2 + k * 0.25), pan=-0.4 + 0.1 * k)


def boss_storm(m, o):
    for i, (r, q) in enumerate(B_CHORDS):
        for k, nn in enumerate(chord_notes(r, q, 24)):
            m.add(tremolo(nn, 8 * B_BEAT - 0.1, 0.22), o + b_at(i * 2), pan=-0.5 + 0.5 * k)
        motif = [r + 24, r + 31, r + 27, r + 24] if q == "m" else [r + 24, r + 31, r + 28, r + 24]
        for k, nn in enumerate(motif):
            m.add(bell(nn, 2.0, 0.35), o + b_at(i * 2 + 1, k), pan=0.6 - 0.3 * k)
    for bar in (0, 6, 11):
        m.add(thunder(4.0, 0.5), o + b_at(bar, 0.5), pan=-0.2)
    for bar in range(0, B_BARS, 4):
        m.add(crash(0.8), o + b_at(bar), pan=0.3)


BOSS_STEMS = [("pad", boss_pad, 0.30), ("timp", boss_timp, 0.25), ("bass", boss_bass, 0.12), ("drums", boss_drums, 0.12),
              ("lead", boss_lead, 0.22), ("corrupt", boss_corrupt, 0.35), ("fast", boss_fast, 0.15),
              ("storm", boss_storm, 0.30)]


def make_boss():
    stems = {}
    for name, fn, wet in BOSS_STEMS:
        stems[name] = render_loop(B_SEC, fn, wet)
    # one gain for every stem, so all of them together (the storm) peak just under full scale
    L = sum(s[0] for s in stems.values())
    R = sum(s[1] for s in stems.values())
    g = 0.9 / max(np.abs(L).max(), np.abs(R).max())
    for name, (l, r) in stems.items():
        save("boss_" + name, np.tanh(l * g * 1.1) / 1.1, np.tanh(r * g * 1.1) / 1.1)


# ================================================================ the cutscene (14 s, in step with Cutscene)
def make_cutscene():
    T = 1.0 / 60.0
    slam, corrupt, rise, eyes, twitch, snap, drawn, end = (268 * T, 280 * T, 372 * T, 468 * T, 504 * T, 672 * T,
                                                           694 * T, 720 * T)

    def c(m, o):
        # he turns: a low drone and a heartbeat
        m.add(strings(38, slam, 0.5, bright=900, a=0.6, r=0.4), 0, 0)
        for k in range(4):
            m.add(timpani(38, 0.7), k * 0.85, 0.1)
            m.add(timpani(38, 0.45), k * 0.85 + 0.22, 0.1)
        # the gallop: a quickening taiko pulse and rising strings
        t = 1.2
        gap = 0.32
        while t < slam - 0.15:
            m.add(taiko(0.5 + 0.4 * (t / slam)), t, -0.1)
            t += gap
            gap = max(gap * 0.93, 0.12)
        for k, nn in enumerate((50, 53, 57, 62)):
            m.add(strings(nn + 12, slam - 1.2, 0.25, bright=3000, a=1.4, r=0.2), 1.2, -0.4 + 0.25 * k)
        for k in range(24):   # a snare roll up to the slam
            m.add(snare(0.1 + 0.03 * k), 3.4 + k * (slam - 3.4) / 24, 0.15)
        m.add(swell(1.2, 0.8), slam - 1.2, 0.3)
        # THE SLAM
        m.add(taiko(1.4), slam, 0)
        m.add(kick(1.2), slam, 0)
        m.add(crash(1.2, 3.5), slam, -0.2)
        m.add(thunder(4.0, 0.9), slam, 0.2)
        for nn in (38, 50, 57, 62):
            m.add(brass(nn, 0.5, 1.0), slam, 0)
        # the corruption: a dissonant choir swells, an organ drone, a reversed swell
        for k, nn in enumerate((62, 63, 68, 74)):
            m.add(choir(nn, rise - corrupt + 1.0, 0.35, "o"), corrupt, -0.5 + 0.33 * k)
        m.add(organ(26, end - corrupt, 0.6), corrupt, 0)
        m.add(organ(32, end - corrupt, 0.35), corrupt, 0)
        # they rise: low pizzicato creeping upward, a heartbeat
        for k in range(10):
            m.add(pluck(38 + k, 0.6, 0.6, dark=3.0), rise + k * 0.16, -0.2 + 0.04 * k)
        for k in range(3):
            m.add(timpani(38, 0.5), rise + k * 0.55, 0.1)
        # the eyes: a cluster of bells and a high whisper of choir
        for k, nn in enumerate((86, 87, 92, 93)):
            m.add(bell(nn, 2.5, 0.35), eyes + k * 0.03, -0.6 + 0.4 * k)
        m.add(choir(81, twitch - eyes + 1.5, 0.25, "u"), eyes, 0.3)
        m.add(choir(82, twitch - eyes + 1.5, 0.2, "u"), eyes, -0.3)
        # they twitch: jerky, off-beat string stabs and ticks
        jt = twitch
        k = 0
        while jt < snap - 0.1:
            nn = [50, 51, 56, 50, 57, 51, 62, 56][k % 8]
            m.add(spicc(nn + 12, 0.08, 0.7), jt, -0.5 + (k % 5) * 0.25)
            m.add(spicc(nn, 0.08, 0.5), jt, 0.3)
            m.add(hat(0.35), jt + 0.04, 0.4)
            jt += [0.21, 0.13, 0.34, 0.17, 0.26, 0.11, 0.29, 0.19][k % 8]
            k += 1
        # the snap: a silence, then weapons drawn: everything hits
        m.add(swell(drawn - snap, 0.9), snap, 0)
        for nn in (38, 50, 57, 62, 65, 69):
            m.add(brass(nn, 1.4, 1.0), drawn, 0)
            m.add(strings(nn + 12, 1.4, 0.4, bright=4000, a=0.02, r=0.6), drawn, 0.2)
        m.add(taiko(1.3), drawn, 0)
        m.add(kick(1.0), drawn, 0)
        m.add(crash(1.0, 3.0), drawn, 0.3)
        # into the fight
        for k in range(8):
            m.add(taiko(0.5 + 0.06 * k), end + k * B_BEAT * 0.5, -0.1)

    L, R = render_once(14.0, c, 0.3, 2.6)
    # a quiet gap at the snap (before the weapons are drawn), and a fade at the very end
    t = np.arange(len(L)) / SR
    gate = np.where((t > snap + 0.05) & (t < drawn - 0.02), 0.25, 1.0)
    gate = lowpass(gate, 30, 1)
    fade = np.clip((14.0 - t) / 1.2, 0, 1)
    L, R = limit(L * gate * fade, R * gate * fade)
    save("cutscene", L, R)


# ================================================================ exploring (F major, 84 bpm, 32 bars)
def make_explore():
    bpm = 84
    beat = 60.0 / bpm
    bars = 32
    sec = bars * 4 * beat
    A = [(53, "M"), (48, "M"), (50, "m"), (46, "M"), (53, "M"), (48, "M"), (46, "M"), (48, "M")]
    Bc = [(50, "m"), (46, "M"), (53, "M"), (48, "M"), (50, "m"), (46, "M"), (43, "m"), (48, "M")]
    chords = A + A + Bc + Bc
    tune = {8: [(0, 1, 72), (1, 1, 69), (2, 2, 72)], 9: [(0, 1, 72), (1, 1, 74), (2, 1, 76), (3, 1, 74)],
            10: [(0, 3, 74), (3, 1, 72)], 11: [(0, 2, 70), (2, 1, 69), (3, 1, 67)],
            12: [(0, 1, 69), (1, 1, 72), (2, 2, 77)], 13: [(0, 1, 76), (1, 1, 74), (2, 2, 72)],
            14: [(0, 1, 74), (1, 1, 72), (2, 1, 70), (3, 1, 69)], 15: [(0, 4, 67)],
            24: [(0, 1.5, 74), (1.5, .5, 72), (2, 2, 69)], 25: [(0, 1, 70), (1, 1, 74), (2, 2, 77)],
            26: [(0, 1.5, 77), (1.5, .5, 76), (2, 2, 72)], 27: [(0, 1, 72), (1, 1, 74), (2, 2, 76)],
            28: [(0, 2, 77), (2, 1, 76), (3, 1, 74)], 29: [(0, 2, 74), (2, 1, 72), (3, 1, 70)],
            30: [(0, 1, 70), (1, 1, 69), (2, 2, 67)], 31: [(0, 2, 72), (2, 2, 67)]}

    def c(m, o):
        for bar, (r, q) in enumerate(chords):
            t0 = o + bar * 4 * beat
            tones = chord_notes(r, q)
            for k, nn in enumerate(tones):
                m.add(pad(nn, 4 * beat - 0.1, 0.18), t0, -0.3 + 0.3 * k)
            arp = [tones[0] - 12, tones[2] - 12, tones[0], tones[1], tones[2], tones[0] + 12, tones[2], tones[1]]
            for e, nn in enumerate(arp):
                m.add(pluck(nn + 12, 2.2, 0.32 if e % 2 else 0.42), t0 + e * 0.5 * beat, 0.35 - 0.1 * (e % 3))
            m.add(bass(r - 12, 2 * beat, 0.35), t0, 0)
            m.add(bass(r - 12 + 7, 1.5 * beat, 0.25), t0 + 2 * beat, 0)
            if bar >= 16:
                for e in range(8):
                    m.add(shaker(0.5 if e % 2 else 0.3), t0 + e * 0.5 * beat, -0.5)
            if bar % 8 == 7:
                m.add(bell(tones[2] + 24, 2.5, 0.15), t0 + 3 * beat, 0.6)
            for b, ln, nn in tune.get(bar, []):
                m.add(flute(nn, ln * beat * 0.92, 0.45), t0 + b * beat, 0.1)

    L, R = render_loop(sec, c, 0.32, 2.4)
    L, R = limit(L, R)
    save("explore", L, R)


# ================================================================ a fight (E minor, 128 bpm, 16 bars)
def make_combat():
    bpm = 128
    beat = 60.0 / bpm
    bars = 16
    sec = bars * 4 * beat
    chords = [(52, "m"), (52, "m"), (48, "M"), (50, "M"), (52, "m"), (52, "m"), (48, "M"), (47, "M")] * 2
    call = {8: [(0, 1, 76), (1, .5, 74), (1.5, .5, 72), (2, 2, 71)], 9: [(0, 1, 69), (1, 1, 71), (2, 2, 67)],
            10: [(0, 1, 72), (1, .5, 71), (1.5, .5, 69), (2, 2, 67)], 11: [(0, 2, 66), (2, 2, 69)],
            12: [(0, 1, 76), (1, .5, 74), (1.5, .5, 72), (2, 2, 71)], 13: [(0, 1, 72), (1, 1, 74), (2, 2, 76)],
            14: [(0, 1, 79), (1, 1, 76), (2, 2, 72)], 15: [(0, 2, 71), (2, 2, 75)]}

    def c(m, o):
        for bar, (r, q) in enumerate(chords):
            t0 = o + bar * 4 * beat
            tones = chord_notes(r, q)
            for b in (0, 1.5, 2.5):
                m.add(kick(0.8), t0 + b * beat)
            for b in (1, 3):
                m.add(snare(0.6), t0 + b * beat, 0.1)
            for s in range(16):
                m.add(hat(0.3 if s % 2 else 0.42), t0 + s * 0.25 * beat, 0.35)
            for e, iv in enumerate([0, 0, 12, 0, 7, 0, 12, 10]):
                m.add(bass(r - 12 + iv, beat * 0.42, 0.8 if e in (0, 3, 6) else 0.6), t0 + e * 0.5 * beat)
            for b in (0.5, 2.0, 3.5):   # string stabs off the beat
                for k, nn in enumerate(tones):
                    m.add(spicc(nn + 12, beat * 0.3, 0.45), t0 + b * beat, -0.4 + 0.4 * k)
            if bar % 4 == 0:
                m.add(crash(0.5), t0, -0.3)
            if bar % 8 == 7:
                for k in range(4):
                    m.add(tom(47 - 2 * k, 0.7), t0 + (3 + k * 0.25) * beat, -0.3 + 0.2 * k)
            for b, ln, nn in call.get(bar, []):
                m.add(brass(nn, ln * beat * 0.9, 0.65), t0 + b * beat, 0.15)

    L, R = render_loop(sec, c, 0.18, 1.8)
    L, R = limit(L, R)
    save("combat", L, R)


# ================================================================ the menu (A minor, 70 bpm, 16 bars)
def make_menu():
    bpm = 70
    beat = 60.0 / bpm
    bars = 16
    sec = bars * 4 * beat
    chords = [(57, "m"), (53, "M"), (48, "M"), (55, "M"), (57, "m"), (53, "M"), (50, "m"), (52, "M")]
    motif = [(0, 1.5, 81), (1.5, .5, 84), (2, 1, 88), (3, 1, 86), (4, 2, 84), (6, 1, 83), (7, 1, 81)]   # the boss's

    def c(m, o):
        for i, (r, q) in enumerate(chords):
            t0 = o + i * 8 * beat
            tones = chord_notes(r, q, -12)
            for k, nn in enumerate(tones):
                m.add(pad(nn, 8 * beat - 0.2, 0.22), t0, -0.4 + 0.4 * k)
            m.add(choir(tones[0] + 12, 8 * beat - 1.0, 0.12, "o"), t0, 0.2)
            arp = [tones[0], tones[2], tones[0] + 12, tones[1] + 12]
            for e in range(8):
                m.add(pluck(arp[e % 4] + 12, 2.6, 0.35), t0 + e * beat, 0.3 - 0.15 * (e % 4))
            m.add(bass(r - 24, 6 * beat, 0.3), t0, 0)
            if i in (4, 5, 6, 7):
                base = (r - 57) if i < 6 else 0
                if i % 2 == 0:
                    for b, ln, nn in motif:
                        m.add(bell(nn + base - 12, 3.0, 0.32), t0 + b * beat, 0.2)

    L, R = render_loop(sec, c, 0.38, 3.0)
    L, R = limit(L, R)
    save("menu", L, R)


# ================================================================ short cues
def make_cues():
    def lvl(m, o):   # a weapon levels up: a bright brass call and a crash
        for k, nn in enumerate((60, 64, 67)):
            m.add(brass(nn + 12, 0.14, 0.8), 0.0 + k * 0.11, 0.1)
        for nn in (60, 64, 67, 72, 76):
            m.add(brass(nn + 12, 1.3, 0.75), 0.33, 0)
        m.add(timpani(48, 0.8), 0.33, 0)
        m.add(crash(0.6), 0.33, 0.3)
        for k, nn in enumerate((84, 88, 91, 96)):
            m.add(bell(nn, 1.8, 0.25), 0.45 + k * 0.09, -0.4 + 0.25 * k)

    L, R = render_once(2.8, lvl, 0.3, 2.0)
    save("levelup", *limit(L, R))

    def mas(m, o):   # a spell's mastery: a harp sweep up and a shimmering chord
        notes = [60, 62, 64, 67, 69, 72, 74, 76, 79, 81, 84, 86, 88]
        for k, nn in enumerate(notes):
            m.add(pluck(nn, 1.8, 0.35), k * 0.055, -0.6 + 0.1 * k)
        for k, nn in enumerate((72, 76, 79, 83, 88)):
            m.add(bell(nn, 2.2, 0.3), 0.75 + k * 0.02, -0.4 + 0.2 * k)
            m.add(pad(nn - 12, 1.2, 0.18), 0.7, 0)
        m.add(swell(0.7, 0.4), 0.05, 0.2)

    L, R = render_once(2.6, mas, 0.4, 2.5)
    save("mastery", *limit(L, R))

    def fall(m, o):   # Thunderhorn falls: a timpani roll, then a great D major chord
        for k in range(28):
            m.add(timpani(38, 0.2 + 0.03 * k, 0.6), k * 0.055, 0.1)
        for nn in (38, 50, 54, 57, 62, 66, 69, 74):
            m.add(brass(nn, 2.6, 0.85), 1.55, 0)
            m.add(strings(nn + 12, 2.6, 0.35, bright=4000, a=0.05), 1.55, 0.2)
        m.add(taiko(1.2), 1.55, 0)
        m.add(crash(1.0, 3.5), 1.55, -0.2)
        m.add(timpani(38, 1.0), 1.55, 0.1)

    L, R = render_once(5.6, fall, 0.35, 2.8)
    save("boss_fall", *limit(L, R))

    def lost(m, o):   # everyone down: low strings falling, a choir, a last drum
        for k, nn in enumerate((50, 48, 46, 45)):
            m.add(strings(nn - 12, 0.85, 0.5, bright=1600, a=0.15), k * 0.8, 0)
            m.add(strings(nn, 0.85, 0.3, bright=2000, a=0.15), k * 0.8, 0.2)
        m.add(choir(62, 2.5, 0.25, "o"), 1.6, -0.2)
        m.add(choir(57, 2.5, 0.2, "o"), 1.6, 0.2)
        m.add(timpani(38, 0.9), 3.2, 0)

    L, R = render_once(4.8, lost, 0.4, 2.8)
    save("defeat", *limit(L, R))


if __name__ == "__main__":
    only = sys.argv[1:]
    jobs = [("menu", make_menu), ("explore", make_explore), ("combat", make_combat), ("boss", make_boss),
            ("cutscene", make_cutscene), ("cues", make_cues)]
    for name, fn in jobs:
        if not only or name in only:
            print(name)
            fn()
