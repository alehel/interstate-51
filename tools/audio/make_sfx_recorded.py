#!/usr/bin/env python3
"""Build the game's sound effects from real recordings.

The recordings come from the openly licensed data of two open-source games,
available as Debian/Ubuntu packages:

    apt-get download supertuxkart-data redeclipse-data
    mkdir -p src && for d in *.deb; do dpkg-deb -x "$d" src; done
    python3 tools/audio/make_sfx_recorded.py src

Each output is trimmed, layered, filtered, pitched, turned into a seamless
loop where needed and normalised, then written to assets/audio/sfx/<name>.ogg
with the same names the synthesised set used (make_sfx.py), so the game code
does not change. Sounds with no good recorded source (siren, klaxon, chimes,
UI beeps) keep their synthesised versions.

Licences of every source file are listed in SOURCES below and in CREDITS.md.
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np
from scipy import signal

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "sfx")

STK = "usr/share/games/supertuxkart/data/sfx/"
RE = "usr/share/games/redeclipse/data/sounds/"

# source key -> (path inside the package tree, author / licence)
SOURCES = {
    "re_smg": (RE + "weapons/smg/primary.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_rifle": (RE + "weapons/rifle/primary2.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_pistol": (RE + "weapons/pistol/primary.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_rocket": (RE + "weapons/rocket/primary.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_flamer": (RE + "weapons/flamer/primary.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_burn": (RE + "weapons/burn.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_explode": (RE + "weapons/explode.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_explode2": (RE + "weapons/explode2.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_explode3": (RE + "weapons/explode3.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_mine_boom": (RE + "weapons/mine/explode.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_mine_beep": (RE + "weapons/mine/beep.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_ricochet": (RE + "weapons/ricochet.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_tink": (RE + "weapons/tink.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_thwack": (RE + "weapons/thwack.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_thud": (RE + "weapons/thud.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_reload": (RE + "weapons/shotgun/reload.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_switch": (RE + "weapons/switch.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_press": (RE + "interface/press.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_back": (RE + "interface/back.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_change": (RE + "interface/change.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "re_wind": (RE + "ambience/wind.ogg", "Batuhan Bozkurt (freesound), CC-BY-SA 3.0, via Red Eclipse"),
    "re_crickets": (RE + "ambience/nightcrickets.ogg", "Richard Humphries (freesound), CC-BY-SA 3.0, via Red Eclipse"),
    "re_fire": (RE + "ambience/fire.ogg", "Red Eclipse Team, CC-BY-SA 3.0"),
    "stk_explosion": (STK + "explosion.ogg", "ZAQraven, CC0, via SuperTuxKart"),
    "stk_crash": (STK + "crash.ogg", "The Audio Monkey, CC-BY-SA 4.0, via SuperTuxKart"),
    "stk_crash2": (STK + "crash2.ogg", "The Audio Monkey, CC-BY-SA 4.0, via SuperTuxKart"),
    "stk_crash3": (STK + "crash3.ogg", "The Audio Monkey, CC-BY-SA 4.0, via SuperTuxKart"),
    "stk_skid": (STK + "skid.ogg", "Tom Haigh / Iwan Gabovitch, CC-BY 3.0, via SuperTuxKart"),
    "stk_horn": (STK + "horn.ogg", "Mike Koenig / M. Gagnon / M. Djupvik, CC-BY 3.0, via SuperTuxKart"),
    "stk_engine": (STK + "engine_large.ogg", "M. Koenig, Stephan, M. Gagnon, SnapJunkie, CC-BY-SA 3.0, via SuperTuxKart"),
    "stk_thunder": (STK + "thunder.ogg", "Mike Koenig / M. Gagnon, CC-BY 3.0, via SuperTuxKart"),
    "stk_static": (STK + "static-radio.ogg", "nicStage / J-M. Clemencon, CC-BY 3.0, via SuperTuxKart"),
    "stk_clang": (STK + "metal_clang.ogg", "dADDoiT / M. Koenig / M. Gagnon, CC-BY 3.0, via SuperTuxKart"),
}

SRC_DIR = ""


def load(key):
    path = os.path.join(SRC_DIR, SOURCES[key][0])
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).astype(np.float64)


# ------------------------------------------------------------------ helpers

def seg(x, a, b=None):
    return x[int(a * SR): (int(b * SR) if b is not None else None)].copy()


def trim(x, thresh=0.01):
    idx = np.where(np.abs(x) > thresh * np.max(np.abs(x)))[0]
    if len(idx) == 0:
        return x
    return x[idx[0]: idx[-1] + 1]


def fade(x, fin=0.002, fout=0.05):
    x = x.copy()
    a = max(1, int(fin * SR))
    b = max(1, int(fout * SR))
    x[:a] *= np.linspace(0, 1, a)
    x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def filt(x, kind, freq, order=2):
    sos = signal.butter(order, freq, btype=kind, fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def shelf_low(x, gain_db, freq=150):
    lo = filt(x, "low", freq)
    return x + lo * (10 ** (gain_db / 20) - 1)


def pitch(x, factor):
    """Resample: factor < 1 = lower and longer (tape-speed style)."""
    n = int(len(x) / factor)
    return signal.resample(x, n)


def mix(*parts):
    n = max(len(p[0]) + int(p[2] * SR) if len(p) > 2 else len(p[0]) for p in parts)
    out = np.zeros(n)
    for p in parts:
        x, g = p[0], p[1]
        off = int(p[2] * SR) if len(p) > 2 else 0
        out[off: off + len(x)] += x * g
    return out


def reverb(x, secs=1.2, wet=0.25, seed=1, lp=5000):
    rng = np.random.default_rng(seed)
    n = int(secs * SR)
    ir = rng.normal(0, 1, n) * np.exp(-np.linspace(0, 7, n))
    ir = filt(ir, "low", lp)
    ir /= np.sqrt(np.sum(ir ** 2))
    dry = np.concatenate([x, np.zeros(n)])
    tail = np.zeros(len(dry))
    conv = signal.fftconvolve(x, ir)[: len(dry)]
    tail[: len(conv)] = conv
    return dry * (1 - wet) + tail * wet


def compress(x, amount=2.0):
    m = np.max(np.abs(x)) or 1
    return np.tanh(x / m * amount) / np.tanh(amount)


def norm(x, db=-1.0):
    m = np.max(np.abs(x)) or 1
    return x / m * 10 ** (db / 20)


def loopify(x, xfade=0.25):
    """Seamless loop: crossfade the tail into the head (equal power)."""
    n = int(xfade * SR)
    body = x[: len(x) - n].copy()
    tail = x[len(x) - n:]
    t = np.linspace(0, np.pi / 2, n)
    body[:n] = body[:n] * np.sin(t) + tail * np.cos(t)
    return body


def write(name, x, db=-1.0, q=6):
    x = norm(x, db)
    os.makedirs(OUT, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        p = tmp.name
    with wave.open(p, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", p, "-c:a", "libvorbis", "-q:a", str(q),
                    os.path.join(OUT, name + ".ogg")], check=True)
    os.unlink(p)
    print("%-20s %5.2fs" % (name, len(x) / SR))


# -------------------------------------------------------------------- build

def build():
    rng = np.random.default_rng(51)

    # --- guns: a real crack on top, a short low "thump" for weight
    smg = trim(load("re_smg"))
    body = filt(pitch(smg, 0.7), "low", 900) * 0.6
    mg30 = mix((smg, 1.0), (body, 0.8))
    write("mg30_shot", fade(shelf_low(seg(mg30, 0, 0.26), 3), 0.0005, 0.08))

    rifle = trim(load("re_rifle"))
    mg50 = mix((rifle, 1.0), (filt(pitch(rifle, 0.8), "low", 500), 0.7))
    write("mg50_shot", fade(shelf_low(seg(mg50, 0, 0.55), 4), 0.0005, 0.25))

    # --- flamethrower: gas roar loop (burn) with the nozzle hiss on top
    burn = load("re_burn")
    hiss = filt(load("re_flamer"), "high", 1500)
    hiss = np.tile(hiss, int(np.ceil(len(burn) / len(hiss))))[: len(burn)]
    write("flame_loop", loopify(mix((burn, 1.0), (hiss, 0.35)), 0.4), -3.0)

    # --- rockets and explosions
    write("rocket_launch", fade(shelf_low(trim(load("re_rocket")), 3), 0.001, 0.4))

    ex2 = trim(load("re_explode2"))
    write("explosion_small", fade(shelf_low(ex2, 3), 0.001, 0.3))

    ex = trim(load("re_explode"))
    ex3 = trim(load("re_explode3"))
    stk = trim(load("stk_explosion"))
    sub = filt(pitch(ex, 0.55), "low", 250)
    big = mix((ex3, 0.9), (stk, 0.55, 0.01), (sub, 1.2), (filt(ex, "high", 2500), 0.3, 0.05))
    big = reverb(big, 1.6, 0.22, 3, 3500)
    write("explosion_big", fade(compress(big, 1.6), 0.001, 0.8))

    # atomic test heard from ~10 miles: long rolling rumble, top end gone
    thunder = trim(load("stk_thunder"))
    boom = trim(load("re_mine_boom"))
    rum1 = filt(pitch(ex, 0.3), "low", 180, 4)
    rum2 = filt(pitch(thunder, 0.5), "low", 400, 2)
    rum3 = filt(pitch(boom, 0.35), "low", 220, 2)
    atomic = mix((rum1, 1.0), (rum2, 0.9, 0.3), (rum3, 0.7, 1.4), (filt(pitch(thunder, 0.7), "low", 900), 0.35, 3.0))
    atomic = reverb(atomic, 4.0, 0.45, 9, 900)
    atomic = atomic[: int(10.0 * SR)]
    write("atomic_blast", fade(compress(atomic, 1.3), 0.3, 3.0), -0.5)

    # --- mines
    write("mine_beep", fade(seg(trim(load("re_mine_beep")), 0, 0.22), 0.001, 0.05), -4.0)
    thud = trim(load("re_thud"))
    write("mine_drop", fade(mix((filt(pitch(thud, 0.6), "low", 1200), 1.0), (trim(load("re_tink")), 0.25, 0.02)), 0.001, 0.15), -3.0)

    # --- bullet impacts on sheet metal and ricochet
    tink = trim(load("re_tink"))
    thwack = trim(load("re_thwack"))
    clang = trim(load("stk_clang"))
    write("impact_metal_1", fade(seg(tink, 0, 0.3), 0.0005, 0.12), -2.0)
    write("impact_metal_2", fade(mix((seg(thwack, 0, 0.3), 1.0), (seg(tink, 0, 0.2), 0.4)), 0.0005, 0.12), -2.0)
    write("impact_metal_3", fade(seg(clang, 0, 0.35), 0.0005, 0.15), -2.0)
    write("ricochet", fade(trim(load("re_ricochet")), 0.001, 0.1), -3.0)

    # --- collisions
    c1 = trim(load("stk_crash"))
    c2 = trim(load("stk_crash2"))
    c3 = trim(load("stk_crash3"))
    write("crash_light", fade(shelf_low(mix((c2, 1.0), (filt(pitch(thud, 0.7), "low", 600), 0.6)), 3), 0.001, 0.1))
    heavy = mix((c1, 1.0), (c3, 0.7, 0.06), (filt(pitch(c1, 0.6), "low", 700), 0.9), (filt(pitch(thud, 0.5), "low", 400), 1.0))
    write("crash_heavy", fade(reverb(heavy, 0.6, 0.12, 5), 0.001, 0.3))

    # --- tyres, engine, horn
    write("skid_loop", loopify(load("stk_skid"), 0.3), -3.0)
    eng = load("stk_engine")
    write("engine_loop", loopify(filt(eng, "low", 7000), 0.35), -2.0)
    # big trucks: the same recording, slower and darker
    heavy_eng = filt(pitch(eng, 0.72), "low", 2500)
    heavy_eng = shelf_low(heavy_eng, 4, 120)
    write("engine_heavy_loop", loopify(heavy_eng, 0.4), -2.0)
    horn = trim(load("stk_horn"))
    # 1950s cars used two-tone horns: add a copy a major third below
    horn2 = mix((horn, 0.8), (pitch(horn, 0.8), 0.7))
    write("horn", fade(filt(horn2, "low", 5000), 0.005, 0.1), -2.0)

    # --- ambience and burning wrecks
    write("wind_loop", loopify(load("re_wind"), 1.5), -3.0)
    write("crickets_loop", loopify(load("re_crickets"), 1.0), -3.0)
    write("wreck_fire_loop", loopify(load("re_fire"), 0.6), -3.0)

    # --- CB radio: key-up click + a burst of real static, squelch tail
    static = load("stk_static")
    starts = [int(s * SR) for s in (12.0, 37.5)]
    burst = static[starts[0]: starts[0] + int(0.22 * SR)]
    click = np.zeros(int(0.012 * SR))
    click[:40] = np.linspace(1, 0, 40)
    write("radio_on", fade(mix((click, 0.9), (filt(burst, "band", [400, 3500]), 0.6, 0.01)), 0.0005, 0.08), -6.0)
    tail = static[starts[1]: starts[1] + int(0.3 * SR)]
    write("radio_off", fade(mix((filt(tail, "band", [500, 3500]) * np.linspace(1, 0.1, len(tail)), 0.7), (click, 0.6, 0.26)), 0.002, 0.04), -7.0)

    # --- interface and pickups
    write("ui_move", fade(seg(trim(load("re_change")), 0, 0.12), 0.0005, 0.04), -8.0)
    write("ui_select", fade(trim(load("re_press")), 0.0005, 0.05), -5.0)
    write("ui_back", fade(trim(load("re_back")), 0.0005, 0.05), -6.0)
    write("pickup", fade(trim(load("re_switch")), 0.0005, 0.1), -3.0)
    write("repair", fade(trim(load("re_reload")), 0.0005, 0.1), -3.0)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    SRC_DIR = sys.argv[1]
    build()
