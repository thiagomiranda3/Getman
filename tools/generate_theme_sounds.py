#!/usr/bin/env python3
"""Generate the themed UI sound cues consumed by ThemeSoundService.

The audio backend (`lib/core/audio/theme_sound_service_io.dart`) plays
`assets/sounds/<themeId>/{send,success,error}.mp3` at volume 0.5 whenever the
`enableThemeSounds` setting is on. This script SYNTHESIZES those 18 short
one-shot cues from scratch — no third-party samples — so the assets are
license-clean (CC0 / project-owned), offline-reproducible, and tuned per theme.

Each theme's voice mirrors its documented personality (docs/THEME_AUTHORING.md):
  brutalist -> blunt, percussive, 8-bit/lo-fi      rpg       -> magical FM chimes
  glass     -> crystalline bells, water-drop       classic   -> clean calm pips
  editorial -> soft warm paper                      dracula   -> dark gothic calm

Requires: numpy + ffmpeg (libmp3lame). Run from the repo root:
    python3 tools/generate_theme_sounds.py
"""

import os
import subprocess
import wave

import numpy as np

SR = 44100
np.random.seed(7)  # deterministic regeneration

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "assets", "sounds")

# Note frequencies (Hz)
C4, D4, Eb4, E4, F4, Gs4, G4, A4, B4 = 261.63, 293.66, 311.13, 329.63, 349.23, 415.30, 392.00, 440.00, 493.88
C5, D5, Eb5, E5, G5, Gs5, A5, B5 = 523.25, 587.33, 622.25, 659.25, 783.99, 830.61, 880.00, 987.77
C6, D6, E6, G6, A6, E7 = 1046.50, 1174.66, 1318.51, 1567.98, 1760.00, 2637.02


# ── primitives ──────────────────────────────────────────────────────────────
def t(dur):
    return np.linspace(0, dur, int(SR * dur), endpoint=False)


def sine(f, dur):
    return np.sin(2 * np.pi * f * t(dur))


def tri(f, dur):
    return (2 / np.pi) * np.arcsin(np.sin(2 * np.pi * f * t(dur)))


def square(f, dur, duty=0.5):
    return np.where((f * t(dur)) % 1.0 < duty, 1.0, -1.0)


def saw(f, dur):
    return 2 * ((f * t(dur)) % 1.0) - 1.0


def noise(dur):
    return np.random.uniform(-1, 1, int(SR * dur))


def glide(f0, f1, dur, exp=True):
    tt = t(dur)
    freqs = f0 * (f1 / f0) ** (tt / dur) if exp else np.linspace(f0, f1, len(tt))
    return np.sin(2 * np.pi * np.cumsum(freqs) / SR)


def fm_bell(carrier, ratio, index, dur, idx_decay=3.0):
    tt = t(dur)
    mod = np.sin(2 * np.pi * carrier * ratio * tt)
    idxenv = index * np.exp(-idx_decay * tt / dur)
    return np.sin(2 * np.pi * carrier * tt + idxenv * mod)


def perc(dur, attack=0.004, curve=4.0):
    """Percussive envelope: quick linear attack, exponential decay."""
    n = int(SR * dur)
    env = np.empty(n)
    a = max(1, int(SR * attack))
    a = min(a, n)
    env[:a] = np.linspace(0, 1, a)
    env[a:] = np.exp(-curve * np.linspace(0, 1, n - a))
    return env


def lowpass(sig, cutoff):
    rc = 1.0 / (2 * np.pi * cutoff)
    alpha = (1.0 / SR) / (rc + 1.0 / SR)
    out = np.empty_like(sig)
    acc = 0.0
    for i, x in enumerate(sig):
        acc += alpha * (x - acc)
        out[i] = acc
    return out


def env_(sig, e):
    n = min(len(sig), len(e))
    return sig[:n] * e[:n]


def add(buf, sig, start):
    s = int(SR * start)
    e = min(s + len(sig), len(buf))
    if e > s:
        buf[s:e] += sig[: e - s]
    return buf


def mix(total, parts):
    buf = np.zeros(int(SR * total))
    for sig, start in parts:
        add(buf, sig, start)
    return buf


def sparkle(total, n, fmin, fmax, spread):
    out = np.zeros(int(SR * total))
    for _ in range(n):
        f = np.random.uniform(fmin, fmax)
        d = np.random.uniform(0.04, 0.09)
        s = env_(fm_bell(f, 2.0, 2.5, d, 4), perc(d, 0.001, 6)) * np.random.uniform(0.12, 0.26)
        add(out, s, np.random.uniform(0, total * spread))
    return out


def finalize(sig, peak=0.72):
    fade = int(SR * 0.005)
    if len(sig) > 2 * fade:
        sig[:fade] *= np.linspace(0, 1, fade)
        sig[-fade:] *= np.linspace(1, 0, fade)
    m = np.max(np.abs(sig))
    if m > 0:
        sig = sig / m * peak
    return np.clip(sig, -1, 1)


# ── theme voices ────────────────────────────────────────────────────────────
def classic():
    send = mix(0.16, [(env_(glide(A5, D6, 0.12), perc(0.12, 0.004, 5)), 0.0)])
    success = mix(0.34, [
        (env_(sine(C6, 0.16), perc(0.16, 0.004, 4)), 0.0),
        (env_(sine(G6, 0.22), perc(0.22, 0.004, 3.5)), 0.09),
    ])
    error = lowpass(mix(0.34, [
        (env_(sine(E5, 0.16), perc(0.16, 0.004, 4)), 0.0),
        (env_(sine(C5, 0.26), perc(0.26, 0.004, 3)), 0.10),
    ]), 3500)
    return {"send": send, "success": success, "error": error}


def brutalist():
    click = env_(noise(0.02), perc(0.02, 0.0, 9)) * 0.6
    thud = lowpass(env_(square(140, 0.14), perc(0.14, 0.001, 6)), 1800)
    drop = env_(glide(420, 90, 0.13), perc(0.13, 0.004, 5)) * 0.5
    send = mix(0.16, [(click, 0.0), (thud, 0.0), (drop, 0.0)])

    def stab(f, dur):
        a = square(f, dur) * 0.5 + square(f * 1.5, dur) * 0.4 + square(f * 2, dur) * 0.25
        return env_(a, perc(dur, 0.002, 4))
    success = lowpass(mix(0.42, [(stab(C4, 0.12), 0.0), (stab(G4, 0.30), 0.12)]), 4500)

    buzz = square(98, 0.30) * 0.5 + square(104, 0.30) * 0.5 + saw(146.83, 0.30) * 0.3
    error = lowpass(env_(buzz, perc(0.30, 0.002, 2.2)), 2600)
    return {"send": send, "success": success, "error": error}


def editorial():
    swoosh = env_(lowpass(noise(0.18), 2500), perc(0.18, 0.03, 2.5)) * 0.8
    pip = env_(sine(E6, 0.12), perc(0.12, 0.004, 5)) * 0.25
    send = mix(0.20, [(swoosh, 0.0), (pip, 0.02)])
    success = lowpass(mix(0.40, [
        (env_(tri(E5, 0.20), perc(0.20, 0.008, 3)), 0.0),
        (env_(tri(Gs5, 0.28), perc(0.28, 0.008, 2.6)), 0.10),
    ]), 3800) * 0.9
    error = lowpass(env_(tri(Eb4, 0.30), perc(0.30, 0.01, 2.2)), 1600)
    return {"send": send, "success": success, "error": error}


def rpg():
    send = np.zeros(int(SR * 0.26))
    for i, f in enumerate([C5, E5, G5, C6]):
        add(send, env_(fm_bell(f, 1.5, 2.0, 0.14, 3), perc(0.14, 0.002, 5)) * 0.5, i * 0.035)
    add(send, sparkle(0.26, 4, 2500, 6000, 0.6), 0.0)

    success = np.zeros(int(SR * 0.5))
    for i, f in enumerate([C5, E5, G5, C6, E6]):
        d = 0.18 if i < 4 else 0.32
        add(success, env_(fm_bell(f, 2.0, 2.2, d, 2.5), perc(d, 0.002, 2.8)) * 0.45, i * 0.06)
    add(success, sparkle(0.5, 9, 3000, 7000, 0.7), 0.1)

    error = np.zeros(int(SR * 0.4))
    for i, f in enumerate([G5, E5, C5, A4]):
        tt = t(0.16)
        ph = 2 * np.pi * np.cumsum(f + np.sin(2 * np.pi * 18 * tt) * 0.03 * f) / SR
        w = np.sin(ph) + 0.5 * np.sin(2 * ph)
        add(error, env_(w, perc(0.16, 0.002, 3)) * 0.4, i * 0.07)
    add(error, env_(glide(600, 140, 0.4), perc(0.4, 0.004, 2)) * 0.25, 0.0)
    return {"send": send, "success": success, "error": error}


def dracula():
    send = lowpass(mix(0.18, [
        (env_(glide(E5, A5, 0.13), perc(0.13, 0.004, 5)) * 0.7, 0.0),
        (env_(sine(A4 / 2, 0.16), perc(0.16, 0.004, 4)) * 0.3, 0.0),
    ]), 4000)
    n1 = env_(sine(E5, 0.18), perc(0.18, 0.004, 3.5)) * 0.6 + env_(tri(E5, 0.18), perc(0.18, 0.004, 3.5)) * 0.3
    n2 = env_(sine(B5, 0.30), perc(0.30, 0.004, 2.6)) * 0.6 + env_(tri(B5, 0.30), perc(0.30, 0.004, 2.6)) * 0.3
    success = lowpass(mix(0.42, [(n1, 0.0), (n2, 0.10)]), 3200)
    error = lowpass(mix(0.46, [
        (env_(sine(Gs4, 0.20), perc(0.20, 0.004, 3)) * 0.6, 0.0),
        (env_(sine(Eb4, 0.34), perc(0.34, 0.004, 2.2)) * 0.6, 0.12),
        (env_(sine(Eb4 / 2, 0.34), perc(0.34, 0.004, 2)) * 0.3, 0.12),
    ]), 2200)
    return {"send": send, "success": success, "error": error}


def glass():
    send = mix(0.28, [
        (env_(glide(1600, 500, 0.09), perc(0.09, 0.002, 6)) * 0.5, 0.0),
        (env_(fm_bell(A5, 3.0, 1.2, 0.22, 3), perc(0.22, 0.003, 2.6)) * 0.5, 0.05),
    ])
    success = np.zeros(int(SR * 0.5))
    for i, f in enumerate([G5, C6, E6, G6]):
        d = 0.22 if i < 3 else 0.34
        add(success, env_(fm_bell(f, 3.0, 1.4, d, 2.4), perc(d, 0.003, 2.4)) * 0.4, i * 0.05)
    add(success, env_(fm_bell(E7, 4.0, 1.0, 0.30, 2), perc(0.30, 0.02, 2)) * 0.15, 0.12)

    crack = env_(noise(0.015), perc(0.015, 0.0, 11)) * 0.3
    beat = (fm_bell(E5, 3.0, 1.6, 0.32, 2.5) + fm_bell(E5 * 1.03, 3.0, 1.6, 0.32, 2.5)) * 0.5
    error = lowpass(mix(0.36, [(crack, 0.0), (env_(beat, perc(0.32, 0.002, 2.6)) * 0.5, 0.005)]), 3000)
    return {"send": send, "success": success, "error": error}


THEMES = {
    "classic": classic, "brutalist": brutalist, "editorial": editorial,
    "rpg": rpg, "dracula": dracula, "glass": glass,
}


def write_wav(path, sig):
    data = (sig * 32767).astype("<i2").tobytes()
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


def main():
    for theme, builder in THEMES.items():
        d = os.path.join(OUT, theme)
        os.makedirs(d, exist_ok=True)
        for cue, sig in builder().items():
            sig = finalize(sig)
            rms = float(np.sqrt(np.mean(sig ** 2)))
            wav = os.path.join(d, f"{cue}.wav")
            mp3 = os.path.join(d, f"{cue}.mp3")
            write_wav(wav, sig)
            subprocess.run(
                ["ffmpeg", "-y", "-loglevel", "error", "-i", wav,
                 "-c:a", "libmp3lame", "-b:a", "128k", "-ar", "44100", "-ac", "1", mp3],
                check=True,
            )
            os.remove(wav)
            print(f"  {theme}/{cue}.mp3  ({len(sig)/SR:.2f}s rms={rms:.3f})")
        gk = os.path.join(d, ".gitkeep")
        if os.path.exists(gk):
            os.remove(gk)
    print("done")


if __name__ == "__main__":
    main()
