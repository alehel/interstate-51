#!/usr/bin/env python3
"""
make_sfx.py -- renders every sound effect for INTERSTATE '51 (mono, 44.1 kHz OGG).

    python3 tools/audio/make_sfx.py                 # everything
    python3 tools/audio/make_sfx.py engine_loop horn # just some

Seamless loops (*_loop) are built one of two ways:
  * "circular" synthesis -- every noise source, filter and event is computed on a
    periodic buffer (FFT-domain filtering, events wrapped modulo the loop), so the
    last sample flows exactly into the first;
  * or render a little longer and equal-power crossfade the overhang into the start.
"""
from __future__ import annotations

import argparse
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from synth_lib import (SR, TWO_PI, bandpass, brown, circ_bandpass, circ_convolve, circ_filter, colored_noise,  # noqa
                       db, env_exp, fade, fm_bell, hall_ir, highpass, loop_xfade, lowpass, mix_into, mtof, ns,
                       onepole, peak_normalize, peq, phase_acc, pink, pulse, saw, smooth_rand, tv_filter, tvec,
                       vibraphone, write_ogg)

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "sfx")

# per-sound peak targets (dBFS). Everything else is -1 dBFS.
PEAKS = {"ui_move": -6.0, "ui_back": -4.0, "countdown_tick": -3.0, "wind_loop": -3.0, "crickets_loop": -3.0,
         "mine_beep": -3.0}

REGISTRY = {}


def sfx(fn):
    REGISTRY[fn.__name__] = fn
    return fn


def save(name, x, loop=False):
    x = np.asarray(x, dtype=float)
    x = x - (np.mean(x) if loop else 0.0)
    if not loop:
        x = fade(x, 0.0, min(0.01, len(x) / SR / 4))
        x[:ns(0.0005)] *= np.linspace(0, 1, ns(0.0005))
    x = peak_normalize(x, PEAKS.get(name, -1.0))
    path = os.path.join(OUT, name + ".ogg")
    write_ogg(path, x)
    seam = ""
    if loop:
        d = np.abs(np.diff(x))
        seam = f"  seam |x[-1]-x[0]|={abs(x[-1] - x[0]):.4f} (median step {np.median(d):.4f}, 99.9% {np.quantile(d, 0.999):.4f})"
    print(f"  -> {name}.ogg {len(x) / SR:.3f}s{seam}")


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
def modal(freqs, decays, amps, dur, rng=None, detune=0.0):
    n = ns(dur)
    t = tvec(n)
    y = np.zeros(n)
    rr = rng or np.random.default_rng()
    for f, d, a in zip(freqs, decays, amps):
        f = f * (1 + rr.uniform(-detune, detune))
        y += a * np.sin(TWO_PI * f * t + rr.uniform(0, TWO_PI)) * np.exp(-t / d)
    return y * np.minimum(1, t / 0.0003)


def click(dur=0.004, lo=2000, hi=9000, rng=None):
    rr = rng or np.random.default_rng()
    n = ns(max(dur * 6, 0.01))
    t = tvec(n)
    return bandpass(rr.standard_normal(n), lo, hi) * np.exp(-t / dur)


def place(buf, ev, t, gain=1.0, circular=False):
    i = ns(t)
    if circular:
        n = len(buf)
        idx = (i + np.arange(len(ev))) % n
        np.add.at(buf, idx, ev * gain)
    else:
        mix_into(buf, ev, i, gain)


def pulse_kernel(width_s):
    """smooth single-sided pressure pulse (raised cosine)"""
    m = max(3, ns(width_s))
    return 0.5 - 0.5 * np.cos(TWO_PI * np.arange(m) / m)


def snap_cycles(f, n):
    """scale a frequency curve so it completes a whole number of cycles in n samples (for loops)."""
    c = np.sum(f) / SR
    return f * (round(c) / c)


def small_room(x, rt=0.35, mix=0.25, seed=1):
    ir = hall_ir(rt, seed=seed, predelay=0.004)[0]
    return x + mix * np.convolve(x, ir)[:len(x)] / 3


# --------------------------------------------------------------------------
# ENGINES (circular synthesis -> perfectly seamless)
# --------------------------------------------------------------------------
def _exhaust_ir(freqs, decays, amps, noise_amt, rng, length=0.12):
    n = ns(length)
    t = tvec(n)
    h = np.zeros(n)
    for f, d, a in zip(freqs, decays, amps):
        h += a * np.sin(TWO_PI * f * t) * np.exp(-t / d)
    h += noise_amt * lowpass(rng.standard_normal(n), 2200) * np.exp(-t / 0.006)
    return h


@sfx
def engine_loop():
    """Cross-plane V8 at ~750 rpm: engine cycle (2 revs) = 6.25 Hz, firing = 50 Hz.
    1.6 s = exactly 10 engine cycles. Per-bank uneven pulse spacing gives the V8 burble."""
    rng = np.random.default_rng(801)
    Ls = 1.6
    n = ns(Ls)
    cycles = 10
    fcyc = cycles / Ls
    bank_seq = [0, 1, 1, 0, 1, 0, 0, 1]  # firing order 1-8-4-3-6-5-7-2 mapped to left/right banks
    trains = [np.zeros(n), np.zeros(n)]
    ker = pulse_kernel(0.0016)
    lope = 1 + 0.10 * np.sin(TWO_PI * np.arange(cycles) / cycles * 2 + 0.7)  # slow cam lope, periodic
    for c in range(cycles):
        for k in range(8):
            tt = (c + k / 8) / fcyc + rng.normal(0, 0.0004)
            a = lope[c] * (1 + rng.normal(0, 0.1)) * (1.12 if k in (0, 3) else 1.0)
            place(trains[bank_seq[k]], ker, tt, a, circular=True)
    irL = _exhaust_ir([92, 184, 305, 520, 880, 1400], [0.035, 0.022, 0.016, 0.01, 0.006, 0.004],
                      [1.0, 0.85, 0.7, 0.5, 0.3, 0.15], 0.9, rng)
    irR = _exhaust_ir([97, 176, 322, 545, 910, 1350], [0.033, 0.024, 0.015, 0.01, 0.006, 0.004],
                      [1.0, 0.8, 0.75, 0.45, 0.3, 0.15], 0.9, rng)
    y = circ_convolve(trains[0], irL) + circ_convolve(trains[1], irR)
    # firing-rate fundamental reinforcement (big pipes)
    t = tvec(n)
    y += 0.25 * np.max(np.abs(y)) * np.sin(TWO_PI * 50.0 * t + 0.3) * (0.8 + 0.2 * np.sin(TWO_PI * fcyc * t))
    # mechanical / valvetrain noise tied to the firing envelope
    envf = circ_convolve(trains[0] + trains[1], np.exp(-tvec(ns(0.02)) / 0.006))
    mech = circ_bandpass(colored_noise(n, rng, -1.5), 900, 3500) * envf
    y = y / np.std(y) + 0.10 * mech / (np.std(mech) + 1e-9)
    rumble = circ_bandpass(brown(n, rng), 25, 180)
    y += 0.25 * rumble
    y = circ_bandpass(y, 28, 5200)
    y = np.tanh(0.7 * y / np.std(y))
    y = circ_bandpass(y, 25, 7000)
    save("engine_loop", y, loop=True)


@sfx
def engine_heavy_loop():
    """Big inline-6 diesel truck at ~600 rpm: cycle 5 Hz, firing 30 Hz, 2.0 s = 10 cycles.
    Lower pipe resonances, diesel knock ('clatter') on each combustion and loose-metal rattles."""
    rng = np.random.default_rng(802)
    Ls = 2.0
    n = ns(Ls)
    cycles = 10
    fcyc = cycles / Ls
    train = np.zeros(n)
    knock = np.zeros(n)
    ker = pulse_kernel(0.0025)
    kn_n = ns(0.02)
    for c in range(cycles):
        for k in range(6):
            tt = (c + k / 6) / fcyc + rng.normal(0, 0.0006)
            a = 1 + rng.normal(0, 0.08)
            place(train, ker, tt, a, circular=True)
            kev = bandpass(rng.standard_normal(kn_n), 1400, 5200) * np.exp(-tvec(kn_n) / 0.004)
            kev += 0.6 * np.sin(TWO_PI * rng.uniform(2300, 2800) * tvec(kn_n)) * np.exp(-tvec(kn_n) / 0.005)
            place(knock, kev, tt + 0.002, a * rng.uniform(0.7, 1.1), circular=True)
    ir = _exhaust_ir([58, 118, 176, 260, 410, 690], [0.05, 0.035, 0.025, 0.018, 0.01, 0.006],
                     [1.0, 0.8, 0.55, 0.4, 0.2, 0.1], 0.6, rng, length=0.18)
    y = circ_convolve(train, ir)
    y /= np.std(y)
    t = tvec(n)
    y += 0.5 * np.sin(TWO_PI * 30.0 * t) * (0.85 + 0.15 * np.sin(TWO_PI * fcyc * t + 1.0))
    # rattles: loose sheet-metal and chains, randomly retriggered (periodic)
    rat = np.zeros(n)
    for _ in range(70):
        tt = rng.uniform(0, Ls)
        f0 = rng.uniform(700, 2400)
        ev = np.sin(TWO_PI * f0 * tvec(ns(0.03))) * np.exp(-tvec(ns(0.03)) / 0.006)
        ev += 0.5 * bandpass(rng.standard_normal(ns(0.03)), 1500, 6000) * np.exp(-tvec(ns(0.03)) / 0.003)
        place(rat, ev, tt, rng.uniform(0.2, 1.0), circular=True)
    rat = circ_filter(rat, lambda f: 1.0)
    y += 0.30 * knock / (np.std(knock) + 1e-9) + 0.12 * rat / (np.std(rat) + 1e-9)
    y += 0.4 * circ_bandpass(brown(n, rng), 20, 150)
    y = circ_bandpass(y, 22, 6000)
    y = np.tanh(0.5 * y / np.std(y))
    y = circ_bandpass(y, 20, 8000)
    save("engine_heavy_loop", y, loop=True)


# --------------------------------------------------------------------------
# WEAPONS
# --------------------------------------------------------------------------
@sfx
def mg30_shot():
    rng = np.random.default_rng(303)
    n = ns(0.18)
    t = tvec(n)
    crack = highpass(rng.standard_normal(n), 2500, 2) * np.exp(-t / 0.0025) * 1.4
    body = bandpass(rng.standard_normal(n), 250, 2600) * np.exp(-t / 0.028)
    f = 70 + 110 * np.exp(-t / 0.012)
    thump = np.sin(TWO_PI * phase_acc(f, n)) * np.exp(-t / 0.035) * 1.1
    tail = lowpass(rng.standard_normal(n), 900) * np.exp(-t / 0.06) * 0.25
    y = crack + body + thump + tail
    y = np.tanh(2.2 * y / np.max(np.abs(y)))
    mech = modal([2350, 3720, 5210], [0.008, 0.006, 0.004], [0.4, 0.3, 0.2], 0.05, rng)
    place(y, mech, 0.05, 0.25)
    save("mg30_shot", y)


@sfx
def mg50_shot():
    rng = np.random.default_rng(350)
    n = ns(0.32)
    t = tvec(n)
    crack = highpass(rng.standard_normal(n), 2000, 2) * np.exp(-t / 0.003) * 1.2
    body = lowpass(rng.standard_normal(n), 1600, 2) * np.exp(-t / 0.055) * 1.2
    f = 45 + 110 * np.exp(-t / 0.018)
    thump = np.sin(TWO_PI * phase_acc(f, n)) * np.exp(-t / 0.08) * 1.6
    tail = lowpass(rng.standard_normal(n), 600) * np.exp(-t / 0.11) * 0.45
    y = crack + body + thump + tail
    y = np.tanh(2.0 * y / np.max(np.abs(y)))
    mech = modal([1450, 2380, 3900], [0.02, 0.012, 0.008], [0.5, 0.35, 0.2], 0.08, rng)
    place(y, mech, 0.07, 0.2)
    save("mg50_shot", y)


@sfx
def flame_loop():
    rng = np.random.default_rng(401)
    Ls = 1.5
    n = ns(Ls)
    roar = circ_bandpass(pink(n, rng), 60, 900)
    roar *= 1 + 0.35 * smooth_rand(n, rng, 9.0)
    body = circ_bandpass(colored_noise(n, rng, -2.0), 300, 2200) * (1 + 0.4 * smooth_rand(n, rng, 14.0))
    hiss = circ_bandpass(pink(n, rng), 2500, 9000) * (1 + 0.3 * smooth_rand(n, rng, 20.0))
    crack = np.zeros(n)
    for _ in range(45):
        ev = click(rng.uniform(0.0008, 0.003), 1200, 7000, rng)
        place(crack, ev, rng.uniform(0, Ls), rng.uniform(0.2, 1.0) ** 2, circular=True)
    sub = circ_bandpass(brown(n, rng), 30, 160)
    y = roar + 0.55 * body + 0.22 * hiss + 0.6 * crack / (np.std(crack) + 1e-9) * 0.2 + 0.5 * sub
    y = np.tanh(0.7 * y / np.std(y))
    save("flame_loop", y, loop=True)


@sfx
def rocket_launch():
    rng = np.random.default_rng(505)
    n = ns(0.85)
    t = tvec(n)
    nz = rng.standard_normal(n)
    center = np.interp(t, [0, 0.08, 0.35, 0.85], [350, 1800, 2600, 1300])
    whoosh = tv_filter(nz, center, q=1.2, kind="bandpass")
    env = np.interp(t, [0, 0.02, 0.12, 0.4, 0.85], [0, 0.8, 1.0, 0.45, 0.0])
    roar = lowpass(brown(n, rng), 900) * np.interp(t, [0, 0.03, 0.2, 0.85], [0, 1, 0.5, 0.0])
    hiss = highpass(nz, 5000) * np.interp(t, [0, 0.01, 0.15, 0.85], [0, 0.6, 0.3, 0.0])
    f = np.interp(t, [0, 0.1, 0.85], [700, 1500, 1050])
    whistle = np.sin(TWO_PI * phase_acc(f, n)) * np.interp(t, [0, 0.08, 0.3, 0.85], [0, 0.18, 0.1, 0])
    ign = lowpass(rng.standard_normal(n), 2500) * np.exp(-t / 0.012) * 1.5
    ign += np.sin(TWO_PI * phase_acc(60 + 90 * np.exp(-t / 0.02), n)) * np.exp(-t / 0.05) * 1.2
    y = whoosh * env * 1.6 + roar * 1.2 + hiss * 0.5 + whistle + ign
    y = np.tanh(1.4 * y / np.max(np.abs(y)))
    save("rocket_launch", y)


# --------------------------------------------------------------------------
# EXPLOSIONS
# --------------------------------------------------------------------------
def _blast(dur, rng, boom_hi, boom_lo, boom_decay, body_decay, bright=6000, sat=2.0):
    n = ns(dur)
    t = tvec(n)
    crack = highpass(rng.standard_normal(n), 1500) * np.exp(-t / 0.005) * 1.3
    f = boom_lo + (boom_hi - boom_lo) * np.exp(-t / 0.06)
    boom_ = np.sin(TWO_PI * phase_acc(f, n)) * np.exp(-t / boom_decay) * 1.6
    nz = rng.standard_normal(n) * 0.6 + brown(n, rng) * 0.8
    cutoff = 250 + bright * np.exp(-t / 0.09)
    body = tv_filter(nz, cutoff, q=0.8) * np.exp(-t / body_decay) * np.minimum(1, t / 0.003)
    rumble = lowpass(brown(n, rng), 160, 2) * np.exp(-t / (body_decay * 2.2)) * np.minimum(1, t / 0.05)
    y = crack + boom_ + 1.4 * body + 0.9 * rumble
    return np.tanh(sat * y / np.max(np.abs(y)))


def _debris(buf, rng, t0, t1, count, lo=300, hi=3500, amp=0.3):
    for _ in range(count):
        tt = t0 + (t1 - t0) * rng.uniform() ** 1.8
        f0 = rng.uniform(lo, hi)
        fr = f0 * np.array([1, 1.53, 2.31, 3.07])
        ev = modal(fr, rng.uniform(0.02, 0.12, 4), [1, 0.6, 0.4, 0.25], 0.25, rng)
        c = click(0.002, 1500, 8000, rng)
        ev[:len(c)] += 0.5 * c
        place(buf, ev, tt, amp * rng.uniform(0.3, 1.0) * (1 - 0.7 * (tt - t0) / (t1 - t0 + 1e-9)))


@sfx
def explosion_small():
    rng = np.random.default_rng(601)
    y = _blast(1.5, rng, 95, 38, 0.25, 0.32, bright=6000)
    for _ in range(25):  # crackle
        tt = rng.uniform(0.08, 1.1)
        place(y, click(rng.uniform(0.001, 0.004), 800, 5000, rng), tt, 0.15 * rng.uniform(0.2, 1) * (1.2 - tt))
    _debris(y, rng, 0.2, 1.2, 6, amp=0.12)
    y = fade(y, 0, 0.3)
    save("explosion_small", y)


@sfx
def explosion_big():
    rng = np.random.default_rng(602)
    y = _blast(3.0, rng, 80, 28, 0.7, 0.6, bright=7000, sat=2.4)
    y2 = _blast(2.6, rng, 70, 30, 0.5, 0.45, bright=4000)  # fuel tank goes up a beat later
    place(y, y2 * 0.7, 0.13)
    _debris(y, rng, 0.25, 2.6, 30, amp=0.22)
    for _ in range(18):  # glass
        tt = rng.uniform(0.1, 1.0)
        f0 = rng.uniform(3000, 7500)
        ev = modal([f0, f0 * 1.41, f0 * 2.13], [0.02, 0.015, 0.01], [1, 0.5, 0.3], 0.08, rng)
        place(y, ev, tt, 0.08 * rng.uniform(0.3, 1))
    n = len(y)
    t = tvec(n)
    fire = lowpass(brown(n, rng), 700) * np.clip((t - 0.3) / 0.4, 0, 1) * np.exp(-np.clip(t - 0.7, 0, None) / 0.9)
    y = y + 0.3 * fire / (np.max(np.abs(fire)) + 1e-9)
    y = fade(y, 0, 0.6)
    save("explosion_big", y)


@sfx
def atomic_blast():
    """distant, enormous: a flash-thud, then the rumble rolls in, swells, and slowly dies away"""
    rng = np.random.default_rng(1951)
    dur = 10.0
    n = ns(dur)
    t = tvec(n)
    env = np.where(t < 3.2, (np.clip(t - 0.3, 0, None) / 2.9) ** 2, np.exp(-(t - 3.2) / 2.3))
    roll = 1 + 0.45 * np.clip(smooth_rand(n, rng, 2.5, periodic=False) * 2.5, -1, 1)
    deep = lowpass(brown(n, rng), 90, 4)
    deep /= np.std(deep)
    mid = lowpass(brown(n, rng), 380, 2)
    mid /= np.std(mid)
    f = np.interp(t, [0, 3.2, 10], [34, 28, 22])
    sub = np.sin(TWO_PI * phase_acc(f, n))
    y = (deep * 1.0 + 0.8 * sub + 0.35 * mid * roll) * env * roll
    # the blast wave arriving: a broader, rolling surge
    wave = lowpass(rng.standard_normal(n), 700) + 0.8 * brown(n, rng)
    wenv = np.clip((t - 2.2) / 0.25, 0, 1) * np.exp(-np.clip(t - 2.45, 0, None) / 1.1)
    y += 0.55 * lowpass(wave, 380, 4) * wenv * roll
    # far-away flash thud at the start
    th = np.sin(TWO_PI * phase_acc(30 + 25 * np.exp(-t / 0.08), n)) * np.exp(-t / 0.35) * np.minimum(1, t / 0.01)
    y += 0.5 * th
    y = highpass(y, 16, 2)
    y = np.tanh(1.3 * y / np.max(np.abs(y)))
    y = fade(y, 0.0, 1.5)
    save("atomic_blast", y)


# --------------------------------------------------------------------------
# IMPACTS
# --------------------------------------------------------------------------
@sfx
def impact_metal_1():
    rng = np.random.default_rng(701)
    y = modal([1850, 2710, 3980, 5230, 6900], [0.12, 0.09, 0.06, 0.04, 0.03], [1, 0.7, 0.55, 0.4, 0.25], 0.35, rng,
              detune=0.01)
    c = click(0.0012, 3000, 12000, rng)
    y[:len(c)] += 1.5 * c
    save("impact_metal_1", np.tanh(1.5 * y / np.max(np.abs(y))))


@sfx
def impact_metal_2():
    rng = np.random.default_rng(702)
    y = modal([980, 1420, 2330, 3150, 4410, 5900], [0.08, 0.07, 0.05, 0.04, 0.03, 0.02],
              [1, 0.8, 0.6, 0.45, 0.3, 0.2], 0.3, rng, detune=0.01)
    c = click(0.002, 1500, 9000, rng)
    y[:len(c)] += 1.2 * c
    r = modal([2600, 3900], [0.015, 0.01], [1, 0.6], 0.06, rng)
    place(y, r, 0.025, 0.4)
    save("impact_metal_2", np.tanh(1.5 * y / np.max(np.abs(y))))


@sfx
def impact_metal_3():
    rng = np.random.default_rng(703)
    y = modal([420, 730, 1190, 1870, 2650, 3720], [0.15, 0.1, 0.08, 0.05, 0.04, 0.03],
              [1, 0.9, 0.7, 0.5, 0.35, 0.25], 0.4, rng, detune=0.01)
    n = len(y)
    t = tvec(n)
    y += lowpass(rng.standard_normal(n), 1200) * np.exp(-t / 0.015) * 1.2
    c = click(0.0015, 2000, 9000, rng)
    y[:len(c)] += c
    save("impact_metal_3", np.tanh(1.6 * y / np.max(np.abs(y))))


@sfx
def ricochet():
    rng = np.random.default_rng(777)
    n = ns(0.55)
    t = tvec(n)
    f = 1450 + 2100 * np.exp(-t / 0.16)
    tumble = 1 - 0.35 * (0.5 + 0.5 * np.sin(TWO_PI * phase_acc(85 - 40 * t, n)))
    ph = TWO_PI * phase_acc(f * (1 + 0.004 * np.sin(TWO_PI * 23 * t)), n)
    tone = np.sin(ph) + 0.22 * np.sin(2 * ph) + 0.08 * np.sin(3 * ph)
    air = tv_filter(rng.standard_normal(n), f, q=6, kind="bandpass") * 0.6
    env = np.minimum(1, t / 0.006) * np.exp(-t / 0.22) * np.clip((0.55 - t) / 0.1, 0, 1)
    y = (tone + air) * env * tumble
    c = click(0.0015, 2500, 10000, rng)
    y[:len(c)] += 0.9 * c
    save("ricochet", y)


def _crash(dur, grains, span, thud_f, seed, glass=0, groan=False):
    rng = np.random.default_rng(seed)
    n = ns(dur)
    t = tvec(n)
    y = np.zeros(n)
    thud = np.sin(TWO_PI * phase_acc(thud_f * (1 + 0.6 * np.exp(-t / 0.02)), n)) * np.exp(-t / 0.09)
    thud += lowpass(rng.standard_normal(n), 500) * np.exp(-t / 0.06)
    y += 1.2 * thud
    for _ in range(grains):  # crunching sheet metal
        tt = span * rng.uniform() ** 1.5
        L = rng.uniform(0.004, 0.02)
        fc = rng.uniform(600, 4000)
        g = bandpass(rng.standard_normal(ns(L * 5)), fc * 0.6, fc * 1.6)
        g *= np.exp(-tvec(len(g)) / L)
        place(y, g, tt, rng.uniform(0.2, 0.8))
    for _ in range(max(3, grains // 5)):
        tt = span * rng.uniform() ** 1.3
        f0 = rng.uniform(250, 1800)
        ev = modal([f0, f0 * 1.61, f0 * 2.47, f0 * 3.3], rng.uniform(0.03, 0.14, 4), [1, 0.7, 0.5, 0.3], 0.3, rng)
        place(y, ev, tt, rng.uniform(0.2, 0.55))
    for _ in range(glass):
        tt = rng.uniform(0.03, span * 1.6)
        f0 = rng.uniform(2800, 8000)
        ev = modal([f0, f0 * 1.37, f0 * 2.21], [0.03, 0.02, 0.012], [1, 0.6, 0.35], 0.1, rng)
        ev[:ns(0.003)] += click(0.0005, 4000, 12000, rng)[:ns(0.003)]
        place(y, ev, tt, 0.18 * rng.uniform(0.3, 1.0))
    if groan:
        m = ns(0.7)
        tg = tvec(m)
        fg = np.interp(tg, [0, 0.7], [190, 120])
        gr = saw(fg * (1 + 0.02 * np.sin(TWO_PI * 13 * tg)), m)
        gr = bandpass(gr, 250, 1600) * np.sin(np.pi * tg / 0.7) ** 2
        place(y, gr, 0.2, 0.25)
    scrape = bandpass(rng.standard_normal(n), 1500, 5000) * np.exp(-t / (span * 0.8)) * 0.25
    y += scrape
    return np.tanh(1.8 * y / np.max(np.abs(y)))


@sfx
def crash_light():
    y = _crash(0.5, 18, 0.12, 85, 901, glass=0)
    save("crash_light", fade(y, 0, 0.15))


@sfx
def crash_heavy():
    y = _crash(1.2, 70, 0.35, 60, 902, glass=22, groan=True)
    rng = np.random.default_rng(903)
    _debris(y, rng, 0.5, 1.05, 8, amp=0.12)
    save("crash_heavy", fade(y, 0, 0.3))


@sfx
def skid_loop():
    """tire squeal, 1.0 s, periodic: pitch jitter and scrub modulations all complete whole cycles."""
    rng = np.random.default_rng(1001)
    n = ns(1.0)
    wob = smooth_rand(n, rng, 7.0)
    jit = smooth_rand(n, rng, 45.0)
    f = 1020 * (1 + 0.035 * wob / np.std(wob) + 0.008 * jit / np.std(jit))
    f = snap_cycles(f, n)
    ph = TWO_PI * np.cumsum(f) / SR
    tone = np.sin(ph) + 0.45 * np.sin(2 * ph) + 0.25 * np.sin(3 * ph) + 0.1 * np.sin(4 * ph)
    am = 1 + 0.3 * smooth_rand(n, rng, 12.0) / 1.0
    scrub = circ_bandpass(colored_noise(n, rng, -1.0), 1500, 6500) * (1 + 0.4 * smooth_rand(n, rng, 20.0))
    road = circ_bandpass(brown(n, rng), 60, 400)
    y = 0.9 * tone * am + 0.45 * scrub + 0.35 * road
    y = np.tanh(1.2 * y / np.std(y) * 0.5)
    save("skid_loop", y, loop=True)


# --------------------------------------------------------------------------
# GADGETS / PICKUPS
# --------------------------------------------------------------------------
@sfx
def mine_drop():
    rng = np.random.default_rng(1101)
    n = ns(0.5)
    y = np.zeros(n)
    for tt, a in ((0.0, 1.0), (0.14, 0.35), (0.22, 0.12)):
        ev = modal([160, 390, 710, 1150, 1720], [0.12, 0.08, 0.05, 0.03, 0.02], [1, 0.7, 0.5, 0.35, 0.2], 0.3, rng)
        te = tvec(len(ev))
        ev += lowpass(rng.standard_normal(len(ev)), 800) * np.exp(-te / 0.02) * 1.3
        place(y, ev, tt, a)
    save("mine_drop", np.tanh(1.4 * y / np.max(np.abs(y))))


@sfx
def mine_beep():
    n = ns(0.15)
    t = tvec(n)
    ph = TWO_PI * 2093.0 * t
    y = np.tanh(2.5 * np.sin(ph)) + 0.25 * np.sin(2 * ph)
    env = np.minimum(1, t / 0.003) * np.clip((0.1 - t) / 0.015, 0, 1)
    y = lowpass(y * env, 7000)
    save("mine_beep", y)


@sfx
def oil_drop():
    rng = np.random.default_rng(1201)
    n = ns(0.65)
    t = tvec(n)
    y = lowpass(rng.standard_normal(n), 2400) * np.minimum(1, t / 0.004) * np.exp(-t / 0.09) * 0.6
    y += np.sin(TWO_PI * phase_acc(90 + 60 * np.exp(-t / 0.03), n)) * np.exp(-t / 0.07) * 0.9
    for tt, f0 in ((0.06, 280), (0.15, 420), (0.21, 330), (0.3, 520), (0.38, 390), (0.47, 610)):
        m = ns(0.08)
        tb = tvec(m)
        bub = np.sin(TWO_PI * phase_acc(f0 * (1 + 2.8 * tb), m)) * np.exp(-tb / 0.025) * np.minimum(1, tb / 0.002)
        place(y, bub, tt, rng.uniform(0.45, 0.8))
    y = lowpass(y, 5000)
    save("oil_drop", y)


@sfx
def pickup():
    rng = np.random.default_rng(1301)
    n = ns(1.3)
    y = np.zeros(n)
    for k in range(6):  # ratchet
        ev = click(0.0025, 2000, 7000, rng) * 0.9
        ev = np.concatenate([ev, np.zeros(ns(0.05))])
        m = modal([3100, 4700], [0.008, 0.006], [0.5, 0.3], len(ev) / SR, rng)
        place(y, ev + m, k * 0.028, 0.5 + 0.08 * k)
    b1 = fm_bell(1318.5, 1.1, 0.8, ratio=2.0, index=1.2, t60=1.2)
    b2 = fm_bell(1975.5, 1.0, 0.7, ratio=2.0, index=1.0, t60=1.1)
    place(y, b1, 0.19, 0.55)
    place(y, b2, 0.27, 0.5)
    y = small_room(y, 0.4, 0.3)
    save("pickup", y)


@sfx
def repair():
    rng = np.random.default_rng(1401)
    n = ns(1.5)
    y = np.zeros(n)
    for tt, base, a in ((0.0, 1250, 1.0), (0.16, 1420, 0.8), (0.30, 1180, 0.9)):
        ev = modal([base, base * 2.32, base * 3.44, base * 4.9], [0.06, 0.04, 0.03, 0.02], [1, 0.6, 0.4, 0.25], 0.25,
                   rng)
        c = click(0.0015, 1500, 9000, rng)
        ev[:len(c)] += c
        place(y, ev, tt, a)
    ding = fm_bell(1760.0, 1.0, 0.8, ratio=2.0, index=1.0, t60=1.0)
    place(y, ding, 0.48, 0.7)
    y = small_room(y, 0.35, 0.25)
    save("repair", y)


# --------------------------------------------------------------------------
# UI
# --------------------------------------------------------------------------
@sfx
def ui_move():
    rng = np.random.default_rng(1501)
    n = ns(0.04)
    t = tvec(n)
    y = np.sin(TWO_PI * 1600 * t) * np.exp(-t / 0.004) + 0.4 * bandpass(rng.standard_normal(n), 2000, 6000) * np.exp(
        -t / 0.0015)
    save("ui_move", y)


def _type_clack(rng, body_f=180.0, bright=1.0):
    n = ns(0.12)
    t = tvec(n)
    thunk = lowpass(rng.standard_normal(n), 1200) * np.exp(-t / 0.012) + np.sin(TWO_PI * body_f * t) * np.exp(
        -t / 0.02) * 0.8
    strike = np.zeros(n)
    s = highpass(rng.standard_normal(n), 3000) * np.exp(-t / 0.003) * bright
    s += modal([2500, 3900, 5600], [0.02, 0.015, 0.01], [0.6, 0.4, 0.25], n / SR, rng) * bright
    place(strike, s, 0.008)
    return thunk * 0.8 + strike


@sfx
def ui_select():
    rng = np.random.default_rng(1601)
    n = ns(0.75)
    y = np.zeros(n)
    place(y, _type_clack(rng), 0.0)
    bell = fm_bell(2794.0, 0.65, 0.6, ratio=2.76, index=0.9, t60=0.7)
    place(y, bell, 0.07)
    save("ui_select", y)


@sfx
def ui_back():
    rng = np.random.default_rng(1701)
    n = ns(0.25)
    y = np.zeros(n)
    place(y, _type_clack(rng, 150, 0.5), 0.0, 0.9)
    place(y, _type_clack(rng, 120, 0.35), 0.075, 0.6)
    y = lowpass(y, 5000)
    save("ui_back", y)


@sfx
def objective():
    rng = np.random.default_rng(1801)
    n = ns(2.3)
    y = np.zeros(n)
    for k, m in enumerate((76, 80, 83)):  # E5 G#5 B5 -- bright major arpeggio on vibes
        v = vibraphone(m, 0.35 + 0.15 * (2 - k), 0.8 - 0.05 * k, rng, motor=5.5, motor_depth=0.25)
        place(y, v, k * 0.12)
    y = small_room(y, 1.2, 0.35, seed=4)
    save("objective", fade(y, 0, 0.4))


@sfx
def objective_fail():
    n = ns(0.9)
    t = tvec(n)
    bend = 2 ** (np.interp(t, [0, 0.55, 0.9], [0, 0, -1.2]) / 12)
    y = saw(98.0 * bend, n) + saw(103.8 * bend, n) + 0.6 * pulse(146.8 * bend, n, 0.3)
    y = lowpass(y, 1400, 2)
    y = peq(y, 600, 1.0, 5)
    env = np.minimum(1, t / 0.012) * np.clip((0.9 - t) / 0.18, 0, 1)
    y = np.tanh(2.0 * y * env / 2)
    save("objective_fail", y)


@sfx
def warning_beep():
    n = ns(0.22)
    t = tvec(n)
    y = pulse(1046.5, n, 0.5) * 0.7 + 0.3 * np.sin(TWO_PI * 1568 * t)
    y = lowpass(y, 5000, 2)
    env = np.minimum(1, t / 0.003) * np.clip((0.17 - t) / 0.015, 0, 1)
    save("warning_beep", y * env)


@sfx
def countdown_tick():
    rng = np.random.default_rng(1901)
    n = ns(0.1)
    y = modal([2200, 3500, 5200], [0.012, 0.008, 0.005], [1, 0.6, 0.35], 0.1, rng)
    c = click(0.0008, 2500, 10000, rng)
    y[:len(c)] += 0.8 * c
    save("countdown_tick", y)


# --------------------------------------------------------------------------
# RADIO
# --------------------------------------------------------------------------
def _static(n, rng):
    x = bandpass(rng.standard_normal(n), 400, 3200, 3)
    crackle = np.zeros(n)
    for _ in range(int(n / SR * 90)):
        place(crackle, click(rng.uniform(0.0004, 0.002), 800, 4000, rng), rng.uniform(0, n / SR), rng.uniform(0.3, 1.5))
    dropout = 1 - 0.5 * (lowpass(rng.standard_normal(n), 30) > 0.4)
    return (x + 0.5 * crackle[:n]) * dropout


@sfx
def radio_on():
    rng = np.random.default_rng(2001)
    n = ns(0.28)
    t = tvec(n)
    y = np.zeros(n)
    c = click(0.0008, 1000, 8000, rng) * 2.0
    c[:ns(0.004)] += np.sin(TWO_PI * 1000 * tvec(ns(0.004))) * 0.8
    place(y, c, 0.0)
    st = _static(n, rng) * np.clip((t - 0.012) / 0.01, 0, 1) * np.clip((0.28 - t) / 0.08, 0, 1) * 0.6
    st += 0.08 * np.sin(TWO_PI * 1100 * t) * np.clip((t - 0.02) / 0.02, 0, 1) * np.clip((0.25 - t) / 0.05, 0, 1)
    y += st
    save("radio_on", y)


@sfx
def radio_off():
    rng = np.random.default_rng(2101)
    n = ns(0.3)
    t = tvec(n)
    sq = bandpass(rng.standard_normal(n), 300, 5000, 2) * np.exp(-t / 0.09) * np.minimum(1, t / 0.004)
    sq = tv_filter(sq, np.interp(t, [0, 0.3], [4500, 1200]), q=0.7)
    y = sq + 0.4 * _static(n, rng) * np.exp(-t / 0.06)
    c = click(0.0006, 1000, 7000, rng) * 1.2
    place(y, c, 0.255)
    save("radio_off", y)


# --------------------------------------------------------------------------
# VEHICLES / ALARMS
# --------------------------------------------------------------------------
@sfx
def siren_loop():
    """1950s mechanical siren: fast-ish rise, slower fall, 3.0 s period, whole-cycle phase closure."""
    rng = np.random.default_rng(2201)
    Ls = 3.0
    n = ns(Ls)
    u = np.arange(n) / n
    g = u + 0.12 * np.sin(TWO_PI * u)            # warp: peak arrives at ~43% of the period
    w = 0.5 - 0.5 * np.cos(TWO_PI * g)
    f = 430 + 760 * w ** 0.9
    f = snap_cycles(f, n)
    ph = TWO_PI * np.cumsum(f) / SR
    amps = [1, 0.55, 0.38, 0.22, 0.16, 0.1, 0.07, 0.05]
    y = sum(a * np.sin((k + 1) * ph) for k, a in enumerate(amps))
    y *= 0.75 + 0.25 * w  # louder near the top of the wail
    whoosh = circ_bandpass(pink(n, rng), 500, 3000) * (0.3 + 0.7 * w) * 0.12
    y = y / np.std(y) + whoosh / (np.std(whoosh) + 1e-9) * 0.15
    y = circ_filter(y, lambda fr: 1 / np.sqrt(1 + (fr / 4500) ** 4))
    y = np.tanh(0.8 * y / np.std(y))
    save("siren_loop", y, loop=True)


@sfx
def horn():
    n = ns(0.62)
    t = tvec(n)
    y = np.zeros(n)
    rise = 2 ** (-0.3 * np.exp(-t / 0.02) / 12)
    for f, a in ((349.2, 1.0), (440.0, 0.9)):  # F4 + A4 dual trumpets
        for dc in (-0.6, 0.6):
            y += a * pulse(f * rise + dc, n, 0.28)
    y = highpass(y, 200)
    y = peq(y, 720, 1.2, 6)
    y = peq(y, 1850, 1.5, 5)
    y = peq(y, 3000, 2.0, 3)
    y = np.tanh(1.6 * y / np.max(np.abs(y)))
    y = lowpass(y, 6500)
    env = np.minimum(1, t / 0.012) * np.clip((0.6 - t) / 0.05, 0, 1)
    save("horn", y * env)


@sfx
def klaxon():
    """AH-OO-GAH alarm klaxon, 1.0 s sound + 0.2 s silence so it repeats cleanly."""
    rng = np.random.default_rng(2301)
    n = ns(1.2)
    t = tvec(n)
    f = np.interp(t, [0, 0.09, 0.35, 0.68, 0.78, 0.98, 1.2], [170, 330, 355, 365, 320, 255, 255])
    f = f * (1 + 0.006 * lowpass(rng.standard_normal(n), 200) / 0.05)
    y = pulse(f, n, 0.18) + 0.5 * saw(f * 1.003, n)
    form = np.interp(t, [0, 0.09, 0.4, 0.68, 0.85, 1.0], [1200, 900, 600, 650, 1100, 1100])
    y = tv_filter(y, form, q=2.0, kind="bandpass") * 2.5 + 0.35 * highpass(y, 150)
    y = np.tanh(2.8 * y / np.max(np.abs(y)))
    y = lowpass(y, 6000)
    env = np.minimum(1, t / 0.015) * np.clip((1.0 - t) / 0.04, 0, 1)
    save("klaxon", y * env)


# --------------------------------------------------------------------------
# AMBIENCE LOOPS
# --------------------------------------------------------------------------
@sfx
def wind_loop():
    rng = np.random.default_rng(2401)
    Ls, X = 8.0, 1.5
    n = ns(Ls + X)
    t = tvec(n)
    gust = smooth_rand(n, rng, 0.35, periodic=False)
    gust = 0.35 + 0.65 * np.clip(0.5 + gust / (3 * np.std(gust)), 0, 1)
    base = lowpass(pink(n, rng), 900, 2)
    base = highpass(base, 60, 2)
    wr = smooth_rand(n, rng, 0.25, periodic=False)
    wc = 520 + 350 * np.tanh(wr / (np.std(wr) + 1e-9))
    whistle = tv_filter(rng.standard_normal(n), wc * (0.8 + 0.4 * gust), q=9.0, kind="bandpass")
    whistle2 = tv_filter(rng.standard_normal(n), wc * 1.9 * (0.8 + 0.4 * gust), q=12.0, kind="bandpass")
    sand = highpass(rng.standard_normal(n), 3500) * gust ** 2 * 0.1
    y = base * gust + 0.55 * whistle * gust ** 1.5 / (np.std(whistle) + 1e-9) * np.std(base) + \
        0.25 * whistle2 * gust ** 2 / (np.std(whistle2) + 1e-9) * np.std(base) + sand * np.std(base) * 3
    y = loop_xfade(y, ns(Ls), ns(X))
    save("wind_loop", y, loop=True)


@sfx
def crickets_loop():
    """desert night: three crickets on periods that divide 6 s evenly + soft night air (fully periodic)."""
    rng = np.random.default_rng(2501)
    Ls = 6.0
    n = ns(Ls)
    y = np.zeros(n)
    species = [  # (carrier Hz, chirp period s, pulses per chirp, pulse len, pulse gap, gain)
        (4650, 0.5, 3, 0.018, 0.036, 1.0),
        (4180, 0.75, 4, 0.014, 0.028, 0.7),
        (5050, 0.6, 2, 0.02, 0.04, 0.35),
        (3900, 1.2, 5, 0.012, 0.025, 0.25),
    ]
    for (fc, period, npul, pl, gap, gain) in species:
        off = rng.uniform(0, period)
        count = int(round(Ls / period))
        for c in range(count):
            t0 = off + c * period + rng.normal(0, 0.004)
            a_c = gain * rng.uniform(0.8, 1.0)
            for p in range(npul):
                m = ns(pl)
                tp = tvec(m)
                env = np.sin(np.pi * tp / pl) ** 2
                fr = fc * (1 + 0.01 * rng.normal())
                ev = np.sin(TWO_PI * fr * tp) * env * (1 + 0.3 * np.sin(TWO_PI * 180 * tp))
                place(y, ev, t0 + p * gap, a_c * (0.8 + 0.2 * (p == 0)), circular=True)
    # distant ones get a little air absorption + space: circular short reverb
    ir = np.random.default_rng(3).standard_normal(ns(0.35)) * np.exp(-tvec(ns(0.35)) / 0.08)
    ir = bandpass(ir, 1500, 7000)
    y = y + 0.25 * circ_convolve(y, ir) / (np.sqrt(np.sum(ir ** 2)) + 1e-9)
    air = circ_bandpass(pink(n, rng), 80, 600)
    y += air * 0.3 * np.std(y) / np.std(air)
    save("crickets_loop", y, loop=True)


@sfx
def wreck_fire_loop():
    rng = np.random.default_rng(2601)
    Ls = 3.0
    n = ns(Ls)
    roar = circ_bandpass(brown(n, rng), 40, 500) * (1 + 0.35 * smooth_rand(n, rng, 1.5) / 1.0)
    roar /= np.std(roar)
    hiss = circ_bandpass(pink(n, rng), 2000, 8000) * (1 + 0.5 * smooth_rand(n, rng, 6.0))
    hiss /= np.std(hiss)
    crack = np.zeros(n)
    for _ in range(110):
        lo = rng.uniform(900, 4000)
        ev = click(rng.uniform(0.0005, 0.0025), lo, lo * 2.5, rng)
        place(crack, ev, rng.uniform(0, Ls), rng.pareto(2.5) + 0.1, circular=True)
    for _ in range(9):  # bigger pops (burning paint / rubber)
        m = ns(0.03)
        tp = tvec(m)
        ev = lowpass(rng.standard_normal(m), 2500) * np.exp(-tp / 0.006) + 0.4 * np.sin(
            TWO_PI * rng.uniform(300, 700) * tp) * np.exp(-tp / 0.01)
        place(crack, ev, rng.uniform(0, Ls), rng.uniform(1.5, 3.0), circular=True)
    crack /= np.std(crack) + 1e-9
    y = 0.8 * roar + 0.12 * hiss + 0.35 * crack
    y = np.tanh(0.6 * y)
    save("wreck_fire_loop", y, loop=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("names", nargs="*", help="subset of effects to render")
    a = ap.parse_args()
    names = a.names or list(REGISTRY)
    os.makedirs(OUT, exist_ok=True)
    for nme in names:
        t0 = time.time()
        print(f"[sfx] {nme}")
        REGISTRY[nme]()
        print(f"      ({time.time() - t0:.1f}s)")


if __name__ == "__main__":
    main()
