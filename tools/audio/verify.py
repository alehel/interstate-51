#!/usr/bin/env python3
"""
verify.py -- sanity-checks the rendered audio:
  * every expected file exists and decodes (duration via ffprobe),
  * no clipping, peak level,
  * loops: the seam (last sample -> first sample) is no bigger a jump than the
    signal's own normal sample-to-sample motion.

    python3 tools/audio/verify.py
"""
import os
import subprocess
import sys

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SFX = ["engine_loop", "engine_heavy_loop", "mg30_shot", "mg50_shot", "flame_loop", "rocket_launch",
       "explosion_small", "explosion_big", "atomic_blast", "impact_metal_1", "impact_metal_2", "impact_metal_3",
       "ricochet", "crash_light", "crash_heavy", "skid_loop", "mine_drop", "mine_beep", "oil_drop", "pickup",
       "repair", "ui_move", "ui_select", "ui_back", "objective", "objective_fail", "warning_beep", "radio_on",
       "radio_off", "siren_loop", "horn", "wind_loop", "crickets_loop", "countdown_tick", "klaxon",
       "wreck_fire_loop"]
MUSIC = ["menu_theme", "drive_boogie", "drive_rockabilly", "tension_night", "finale", "victory", "defeat",
         "trailer_theme"]
MUSIC_LOOPS = {"menu_theme", "drive_boogie", "drive_rockabilly", "tension_night", "finale"}


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_name,channels,sample_rate",
                          "-of", "default=nw=1", path], capture_output=True, text=True).stdout
    d = dict(line.split("=", 1) for line in out.strip().splitlines() if "=" in line)
    return d


def decode(path, ch):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-"], capture_output=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, ch).T.astype(float)


def seam_score(x):
    """2nd-difference 'surprise' of the wrap-around sample relative to the 99.9th percentile of the
    signal's own 2nd differences. < 1 means the seam is as smooth as the audio itself."""
    worst = 0.0
    for c in x:
        d2 = np.abs(c[2:] - 2 * c[1:-1] + c[:-2])
        ref = np.quantile(d2, 0.999) + 1e-9
        s1 = abs(c[0] - 2 * c[-1] + c[-2])
        s2 = abs(c[1] - 2 * c[0] + c[-1])
        worst = max(worst, max(s1, s2) / ref)
    return worst


def main():
    ok = True
    rows = []
    for kind, names in (("sfx", SFX), ("music", MUSIC)):
        for n in names:
            p = os.path.join(ROOT, "assets", "audio", kind, n + ".ogg")
            if not os.path.exists(p):
                print(f"MISSING {p}")
                ok = False
                continue
            info = probe(p)
            ch = int(info.get("channels", 1))
            x = decode(p, ch)
            peak = 20 * np.log10(np.max(np.abs(x)) + 1e-12)
            loop = n.endswith("_loop") or n in MUSIC_LOOPS
            seam = seam_score(x) if loop else None
            bad = (not np.isfinite(x).all()) or peak > -0.1 or (seam is not None and seam > 1.0)
            ok &= not bad
            rows.append((kind, n, float(info["duration"]), ch, info.get("codec_name"), peak, seam, bad))
    for kind, n, dur, ch, codec, peak, seam, bad in rows:
        s = f"{seam:5.2f}" if seam is not None else "   - "
        print(f"{'!!' if bad else 'ok'} {kind:5s} {n + '.ogg':24s} {dur:7.3f}s  {'stereo' if ch == 2 else 'mono  '} "
              f"{codec:7s} peak {peak:6.2f} dBFS  seam {s}")
    print("ALL OK" if ok else "PROBLEMS FOUND")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
