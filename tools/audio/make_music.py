#!/usr/bin/env python3
"""
make_music.py -- renders every music cue for INTERSTATE '51.

    python3 tools/audio/make_music.py            # all tracks
    python3 tools/audio/make_music.py menu finale   # just some

All material is composed here as note lists and synthesised with synth_lib.
Loops are rendered on a timeline that is longer than the loop; everything that
rings past the loop end (notes, reverb tails) is folded back onto the start, so
the file is seamless when played on repeat.
"""
from __future__ import annotations

import argparse
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from synth_lib import (SR, DrumKit, Song, boom, brass, chord, circ_apply, close_voicing, db, fade,  # noqa: E402
                       guitar, guitar_tone, guitar_voicing, hall_ir, lead_horn, limiter, lowpass, lufs,
                       master_music, mtof, nm, ns, piano_c, reverb, riser, saw, slap_bass, slap_click,
                       slapback, spring_ir, tape, theremin, tremolo, tv_filter, tvec, upright_bass, wrap_tail,
                       write_ogg, brown, pink, highpass, bandpass, smooth_rand, vibraphone, env_exp,
                       phase_acc, TWO_PI, crash)

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio", "music")

# ==========================================================================
# THE MAIN MOTIF  (E minor, 8 bars of 4/4)
# (start_beat, length_beats, midi) -- written at trumpet pitch (E4 = 64).
# Harmony underneath: | Em | Am | D | Em | Em | C | Am  B7 | Em |
# A rising E-minor arpeggio "call", a falling answer, then a second phrase that
# climbs to C5 and resolves through the D# leading tone (harmonic minor).
# ==========================================================================
MAIN_MOTIF = [
    # bar 1  (Em)      E  . . G  B - - -
    (0.0, 1.5, 64), (1.5, 0.5, 67), (2.0, 2.0, 71),
    # bar 2  (Am)      A - G F# E - - -
    (4.0, 1.0, 69), (5.0, 0.5, 67), (5.5, 0.5, 66), (6.0, 2.0, 64),
    # bar 3  (D)       D - E G F# - D -
    (8.0, 1.0, 62), (9.0, 0.5, 64), (9.5, 0.5, 67), (10.0, 1.0, 66), (11.0, 1.0, 62),
    # bar 4  (Em)      E - - - - - B3 -
    (12.0, 3.0, 64), (15.0, 1.0, 59),
    # bar 5  (Em)      E  . . G  B  . . C
    (16.0, 1.5, 64), (17.5, 0.5, 67), (18.0, 1.5, 71), (19.5, 0.5, 72),
    # bar 6  (C)       B - A G A - B -
    (20.0, 1.0, 71), (21.0, 0.5, 69), (21.5, 0.5, 67), (22.0, 1.0, 69), (23.0, 1.0, 71),
    # bar 7  (Am  B7)  C - B A | F# - D# -
    (24.0, 1.0, 72), (25.0, 0.5, 71), (25.5, 0.5, 69), (26.0, 1.0, 66), (27.0, 1.0, 63),
    # bar 8  (Em)      E - - - - - - -
    (28.0, 4.0, 64),
]
MOTIF_CHORDS = [[(0, "Em")], [(0, "Am")], [(0, "D")], [(0, "Em")],
                [(0, "Em")], [(0, "C")], [(0, "Am"), (2, "B7")], [(0, "Em")]]

PC = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7,
      "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def parse_chord(name):
    r = name[:2] if len(name) > 1 and name[1] in "#b" else name[:1]
    q = name[len(r):]
    qual = {"": "maj", "m": "min", "7": "7", "m7": "m7", "maj7": "maj7", "m6": "m6", "6": "6",
            "7b9": "7b9", "m9": "m9", "9": "9", "5": "5", "madd9": "madd9", "7#9": "7#9"}[q]
    return PC[r], qual


def bass_root(pc, lo=35):
    m = lo + ((pc - lo) % 12)
    return m


def segments(bar_chords):
    """[(beat, name), ...] -> [(start, length, name)]"""
    out = []
    for i, (b, nme) in enumerate(bar_chords):
        e = bar_chords[i + 1][0] if i + 1 < len(bar_chords) else 4
        out.append((b, e - b, nme))
    return out


def level(x, target):
    L = lufs(x)
    if L < -90:
        return x
    return x * db(target - L)


def finish(name, mix, song, loop, target=-14.0, drive=1.25, fade_out=0.0):
    if loop:
        mix = wrap_tail(mix, song.L)
        mix = circ_apply(lambda z: tape(z, drive), mix, pre=2.0)
    else:
        mix = mix[:, :song.L]
        mix = tape(mix, drive)
        if fade_out:
            mix = fade(mix, 0.0, fade_out)
    mix = master_music(mix, target, -1.0, loop=loop)
    if not loop:
        mix[:, -ns(0.01):] *= np.linspace(1, 0, ns(0.01))
    path = os.path.join(OUT, name)
    write_ogg(path, mix)
    print(f"  -> {path}  {mix.shape[1] / SR:.2f}s  LUFS={lufs(mix):.1f}  peak={20 * np.log10(np.max(np.abs(mix))):.2f} dBFS")
    return mix


def play_line(s: Song, bus, notes, bar0, fn, transpose=0, vel=0.8, pan=0.0, gate=0.95, hum=0.006,
              accent=True, gain=1.0, **kw):
    for (b, d, m) in notes:
        bar = bar0 + int(b // 4)
        beat = b - 4 * int(b // 4)
        t = s.t(bar, beat) + s.hum(hum)
        v = vel * (1.08 if (accent and abs(beat) < 1e-6) else 1.0) * s.rng.uniform(0.92, 1.05)
        ms = m if isinstance(m, (list, tuple)) else [m]
        for mm in ms:
            s.add(bus, fn(mm + transpose, d * s.beat * gate, min(v, 1.0), s.rng, **kw), t, pan, gain)


def strum(s: Song, bus, t, notes, vel=0.7, dur=2.0, spread=0.014, down=True, pan=0.0, **gkw):
    seq = notes if down else notes[::-1]
    for i, m in enumerate(seq):
        v = vel * (1 - 0.04 * i) * s.rng.uniform(0.9, 1.05)
        s.add(bus, guitar(m, max(dur - i * spread, 0.05), v, s.rng, **gkw), t + i * spread + s.hum(0.002), pan)


def drone_loop(s: Song, midi_list, cutoff=220.0, lfo_bars=8, xfade=2.0, level_=1.0, rng=None):
    """a perfectly periodic drone (all frequencies snapped to whole cycles per loop) with an
    overlapping linear fade so wrap_tail() folds it seamlessly."""
    Ls = s.L / SR
    n = s.L + ns(xfade)
    t = tvec(n)
    y = np.zeros(n)
    rr = rng or s.rng
    for m in midi_list:
        f = round(mtof(m) * Ls) / Ls
        for dc in (-4, 0, 5):
            fd = round(f * 2 ** (dc / 1200) * Ls) / Ls
            y += saw(fd, n, rr.uniform())
        y += 1.5 * np.sin(TWO_PI * f * t)
    lfo_f = round(Ls / (lfo_bars * 4 * s.beat)) / Ls
    fc = cutoff * (1 + 0.8 * (0.5 - 0.5 * np.cos(TWO_PI * lfo_f * t)))
    y = tv_filter(y, fc, q=1.4)
    env = np.ones(n)
    X = ns(xfade)
    env[:X] = np.linspace(0, 1, X)
    env[s.L:] = np.linspace(1, 0, n - s.L)
    return y * env * level_ / len(midi_list)


def bari(m, d, v, rng, **kw):
    """baritone twang guitar (bridge pickup, long ring)"""
    return guitar(m, d, v, rng, bright=0.85, pickup=0.09, t60=4.5, damp=0.14, **kw)


def trem_gtr_kw():
    return dict(bright=0.55, pickup=0.22, t60=3.5, damp=0.25)


# ==========================================================================
# 1. MENU THEME  -- 84 BPM, E minor, 26 bars (~74.3 s)
# ==========================================================================
def menu_theme():
    bpm, bars = 84, 26
    s = Song(bars * 4 * 60 / bpm, tail_s=7.0, bpm=bpm, swing=0.5, seed=51)
    kit = DrumKit(seed=5)
    rng = s.rng
    chords = ([[(0, "Em")], [(0, "Em")]] + MOTIF_CHORDS +
              [[(0, "C")], [(0, "G")], [(0, "Am")], [(0, "B7")]] + MOTIF_CHORDS +
              [[(0, "Em")], [(0, "C")], [(0, "Am")], [(0, "B7")]])
    assert len(chords) == bars

    # --- intro twang
    s.add("bari", bari(40, 5.0, 0.9, rng), s.t(0, 0), -0.15)
    s.add("bari", bari(47, 1.2, 0.6, rng), s.t(1, 2), -0.15)
    s.add("bari", bari(50, 1.0, 0.55, rng), s.t(1, 3), -0.15)
    # --- first pass: motif on baritone guitar (an octave down)
    play_line(s, "bari", MAIN_MOTIF, 2, bari, transpose=-12, vel=0.85, pan=-0.15, gate=1.0)
    # --- bridge
    bridge = [(0, 2, 64), (2, 1, 67), (3, 1, 64), (4, 3, 62), (7, 1, 59), (8, 2, 60), (10, 1, 64), (11, 1, 69),
              (12, 2, 66), (14, 1, 63), (15, 1, 59)]
    play_line(s, "bari", bridge, 10, bari, transpose=-12, vel=0.8, pan=-0.15, gate=1.0)
    # --- second pass: lonely trumpet / whistle lead
    play_line(s, "lead", MAIN_MOTIF, 14, lead_horn, vel=0.85, pan=0.12, gate=0.93, whistle=0.35)
    # baritone answers in the long notes
    fills = [(13, 0.5, 52), (13.5, 0.5, 55), (14.5, 0.5, 59), (15, 1, 62),
             (29, 0.5, 59), (29.5, 0.5, 55), (30, 0.5, 52), (30.5, 1.5, 47)]
    play_line(s, "bari", fills, 14, bari, vel=0.6, pan=-0.3, gate=1.0)
    # --- outro turnaround (leads back to bar 0)
    outro = [(0, 1, 59), (1, 1, 55), (2, 2, 52), (4, 1, 52), (5, 1, 55), (6, 2, 60), (8, 1, 60), (9, 0.5, 59),
             (9.5, 0.5, 57), (10, 2, 52), (12, 1, 51), (13, 1, 54), (14, 1, 57), (15, 1, 59)]
    play_line(s, "bari", outro, 22, bari, vel=0.8, pan=-0.15, gate=1.0)

    # --- tremolo chord guitar + bass
    for bar, bc in enumerate(chords):
        segs = segments(bc)
        for (b0, ln, name) in segs:
            t = s.t(bar, b0) + s.hum(0.004)
            vel = 0.55 if bar < 2 else 0.62
            strum(s, "trem", t, guitar_voicing(name), vel, ln * s.beat + 0.3, spread=0.02, pan=0.35,
                  **trem_gtr_kw())
            if ln == 4 and bar % 2 == 1:
                strum(s, "trem", s.t(bar, 2.5), guitar_voicing(name)[-3:], vel * 0.5, 1.5 * s.beat, spread=0.012,
                      down=False, pan=0.35, **trem_gtr_kw())
        # upright bass: two-feel with chromatic approach notes
        nxt = segments(chords[(bar + 1) % bars])[0][2]
        for i, (b0, ln, name) in enumerate(segs):
            pc, q = parse_chord(name)
            r = bass_root(pc)
            fifth = r + 7 if r + 7 <= 47 else r - 5
            s.add("bass", upright_bass(r, 1.8 * s.beat if ln == 4 else ln * s.beat * 0.9, 0.85, rng),
                  s.t(bar, b0) + s.hum(0.005))
            if ln == 4:
                npc, _ = parse_chord(nxt)
                nr = bass_root(npc)
                if nr != r and bar >= 1:
                    s.add("bass", upright_bass(fifth, 0.9 * s.beat, 0.7, rng), s.t(bar, 2) + s.hum(0.005))
                    appr = nr - 1 if (nr - 1) >= 33 else nr + 1
                    s.add("bass", upright_bass(appr, 0.9 * s.beat, 0.72, rng), s.t(bar, 3) + s.hum(0.005))
                else:
                    s.add("bass", upright_bass(fifth, 1.8 * s.beat, 0.72, rng), s.t(bar, 2) + s.hum(0.005))

    # --- brushes
    for bar in range(bars):
        section_gain = 0.8 if bar < 2 else (1.0 if bar < 14 else 1.12)
        for beat in range(4):
            t = s.t(bar, beat) + s.hum(0.006)
            s.add("drums", kit.hit("swish", 0.55 * section_gain * rng.uniform(0.8, 1.1)), t - 0.02, 0.1)
            if bar >= 2 and beat in (1, 3):
                s.add("drums", kit.hit("brush", 0.62 * section_gain * rng.uniform(0.85, 1.05)), t, 0.05)
            if beat in (0, 2) and bar >= 2:
                s.add("drums", kit.hit("kick", 0.33 * section_gain), t, 0.0)
            if beat in (1, 3) and bar >= 10:
                s.add("drums", kit.hit("pedal", 0.3), t, -0.3)
            if 14 <= bar < 22:
                s.add("drums", kit.hit("ride", 0.22 * (1.2 if beat % 2 == 0 else 1.0)), t, 0.35)
                if beat in (1, 3):
                    s.add("drums", kit.hit("ride", 0.14), s.t(bar, beat + 2 / 3) + s.hum(0.004), 0.35)
        if bar in (9, 13, 21, 25):  # little brush fills
            for k, b in enumerate((3.0, 3 + 1 / 3, 3 + 2 / 3)):
                s.add("drums", kit.hit("brush", 0.4 + 0.1 * k), s.t(bar, b), 0.05)

    # --- mix
    beat_hz = 1 / s.beat
    bari_b = level(guitar_tone(s.get("bari"), twang=5.0, drive=1.3), -19)
    trem_b = guitar_tone(s.get("trem"), twang=2.5, drive=1.8, cab_lp=4500)
    trem_b = level(tremolo(trem_b, 3 * beat_hz, depth=0.75), -25.5)
    bass_b = level(s.get("bass"), -22.5)
    drum_b = level(s.get("drums"), -27)
    lead_b = level(s.get("lead"), -19.5)
    sp, hl = spring_ir(), hall_ir(2.6, seed=21)
    wet_sp = reverb(0.8 * bari_b + 0.9 * trem_b, sp)
    wet_hl = reverb(0.45 * bari_b + 0.5 * trem_b + 0.55 * lead_b + 0.25 * drum_b + 0.12 * bass_b, hl)
    mix = bari_b + trem_b + bass_b + drum_b + lead_b + 0.42 * wet_sp + 0.36 * wet_hl
    return finish("menu_theme.ogg", mix, s, loop=True)


# ==========================================================================
# 2. DRIVE BOOGIE -- 150 BPM swing, 12-bar blues in A, 5 choruses (96 s)
# ==========================================================================
BLUES_A = ["A7", "A7", "A7", "A7", "D7", "D7", "A7", "A7", "E7", "D7", "A7", "E7"]
BLUES_E = ["E7", "E7", "E7", "E7", "A7", "A7", "E7", "E7", "B7", "A7", "E7", "B7"]


def horn_voices(root_pc, low=58):
    """3-part dominant voicing (3, 5/13, b7) plus a trombone root"""
    v = close_voicing(root_pc, [4, 9, 10], low=low)
    bone = 43 + ((root_pc - 43) % 12)
    return v, bone


def horn_hit(s, t, root_pc, dur, vel, low=60):
    v, bone = horn_voices(root_pc, low)
    for m, pan, br in ((v[2], 0.25, 1.0), (v[1], -0.2, 0.8), (v[0], 0.05, 0.8)):
        s.add("horns", brass(m, dur, vel, s.rng, bright=br), t + s.hum(0.004), pan)
    s.add("horns", brass(bone, dur, vel * 0.9, s.rng, bright=0.7), t + s.hum(0.004), -0.05)


HORN_RIFF = [  # 2-bar riff relative to the chord root (swung 8ths)
    [(0.5, 0.5, 7), (1.0, 0.5, 9), (1.5, 1.0, 10), (3.0, 0.5, 9), (3.5, 0.5, 7)],
    [(0.0, 1.0, 4), (1.5, 0.5, 7), (2.0, 1.5, 0)],
]


def drive_boogie():
    bpm, bars = 150, 60
    s = Song(bars * 4 * 60 / bpm, tail_s=4.0, bpm=bpm, swing=0.64, seed=52)
    kit = DrumKit(seed=9, ride={"decay": 1.2, "bell": 0.2})
    rng = s.rng
    form = BLUES_A * 5
    lh_root = {9: 45, 2: 50, 4: 52}
    walk_up, walk_dn = [0, 4, 7, 9], [10, 9, 7, 4]
    boogie = [0, 4, 7, 9, 10, 9, 7, 4]
    licks = {
        "L1": [(0, 0.5, 69), (0.5, 0.5, 72), (1, 0.5, 73), (1.5, 0.5, 76), (2, 1.0, 79), (3, 0.5, 76),
               (3.5, 0.5, 73), (4, 2, 69), (6.5, 0.5, 72), (7, 0.5, 73), (7.5, 0.5, 76)],
        "L2": [(i / 3, 1 / 3, [73, 76] if i % 2 == 0 else [81]) for i in range(12)] +
              [(4, 0.5, 79), (4.5, 0.5, 76), (5, 0.5, 75), (5.5, 0.5, 74), (6, 1.5, 72), (7.5, 0.5, 69)],
        "L3": [(1 + i / 3, 1 / 3, m) for i, m in enumerate([81, 79, 76, 75, 74, 72, 69, 67, 64])] +
              [(3.92, 0.08, 72), (4, 2, 73), (6.5, 0.5, 76), (7, 1, [73, 79])],
        "L4": [(0.5, 0.5, 76), (1, 0.5, 76), (1.5, 0.5, 79), (2, 0.5, 76), (2.5, 1, 73), (4.5, 0.5, 76),
               (5, 0.5, 76), (5.5, 0.5, 79), (6, 0.5, 81), (6.5, 1, 79)],
    }
    solo_plan = ["L1", "L2", "L4", "L3", "L1", "L2"]

    for bar in range(bars):
        ch = bar // 12
        i = bar % 12
        pc, _ = parse_chord(form[bar])
        # piano left hand boogie (octaves, swung 8ths)
        r = lh_root[pc]
        for k, iv in enumerate(boogie):
            beat = k * 0.5
            t = s.t(bar, beat) + s.hum(0.004)
            v = (0.78 if k % 2 == 0 else 0.62) * rng.uniform(0.92, 1.04)
            d = 0.45 * s.beat
            s.add("piano", piano_c(r + iv, d, v, rng), t, -0.25)
            s.add("piano", piano_c(r + iv - 12, d, v * 0.85, rng), t, -0.3)
        # upright bass walking quarters
        br = bass_root(pc, 33)
        pat = walk_up if bar % 2 == 0 else walk_dn
        for k, iv in enumerate(pat):
            s.add("bass", upright_bass(br + iv, 0.85 * s.beat, 0.85 if k == 0 else 0.75, rng, t60=1.0),
                  s.t(bar, k) + s.hum(0.004))
        # piano right hand
        if ch == 3:
            if i % 2 == 0:
                play_line(s, "piano", licks[solo_plan[i // 2]], bar, piano_c, vel=0.8, pan=0.2, gate=0.9, hum=0.004)
        else:
            vo = close_voicing(pc, [4, 7, 10], low=62)
            for b in ((1.5, 3.5) if ch != 1 else (1.5, 2.5, 3.5)):
                for m in vo:
                    s.add("piano", piano_c(m, 0.3 * s.beat, 0.62, rng), s.t(bar, b) + s.hum(0.004), 0.25)
        # horns
        root_h = {9: 57, 2: 62, 4: 52}[pc]
        if ch == 1 or ch == 4:  # stabs
            if bar % 2 == 1:
                npc, _ = parse_chord(form[(bar + 1) % bars])
                horn_hit(s, s.t(bar, 3.5), npc, 0.9 * s.beat, 0.8)
            else:
                horn_hit(s, s.t(bar, 1), pc, 0.35 * s.beat, 0.7)
        if ch == 2 or ch == 4:  # riff in octaves
            if i == 11:
                horn_hit(s, s.t(bar, 0), pc, 0.4 * s.beat, 0.85)
                horn_hit(s, s.t(bar, 1.5), pc, 1.5 * s.beat, 0.9)
            else:
                part = HORN_RIFF[0] if i in (0, 2, 4, 6, 8, 9) else HORN_RIFF[1]
                g = 0.8 if ch == 2 else 0.9
                play_line(s, "horns", part, bar, brass, transpose=root_h + 12, vel=g, pan=0.25, gate=0.85, hum=0.004)
                play_line(s, "horns", part, bar, brass, transpose=root_h, vel=g, pan=-0.2, gate=0.85, hum=0.004,
                          bright=0.8, vib=8)
                play_line(s, "horns", part, bar, brass, transpose=root_h - 12, vel=g * 0.9, pan=0.0, gate=0.85,
                          hum=0.004, bright=0.7)
        # drums
        loud = 1.0 if ch in (2, 4) else (0.85 if ch == 3 else 0.92)
        for b in (0, 1, 1.5, 2, 3, 3.5):
            v = (0.55 if b in (1, 3) else 0.45 if b in (0, 2) else 0.3) * loud
            s.add("drums", kit.hit("ride", v * rng.uniform(0.9, 1.05)), s.t(bar, b) + s.hum(0.003), 0.35)
        for b in range(4):
            s.add("drums", kit.hit("kick", (0.72 if b in (0, 2) else 0.5) * loud), s.t(bar, b) + s.hum(0.003), 0.0)
            if b in (1, 3):
                s.add("drums", kit.hit("snare", 0.78 * loud * rng.uniform(0.92, 1.03)), s.t(bar, b) + s.hum(0.003),
                      0.06)
                s.add("drums", kit.hit("pedal", 0.45), s.t(bar, b) + 0.004, -0.3)
            if ch in (2, 4):
                s.add("drums", kit.hit("snare", 0.2 * rng.uniform(0.8, 1.2)), s.t(bar, b + 0.5) + s.hum(0.003), 0.06)
        if i == 0:
            s.add("drums", kit.hit("crash", 0.55 if ch > 0 else 0.45), s.t(bar, 0), -0.35)
        if i == 11:  # triplet fill into the next chorus
            for k in range(6):
                bb = 2 + k / 3
                nm_ = "snare" if k < 3 else ("tom140" if k < 5 else "tom95")
                s.add("drums", kit.hit(nm_, 0.45 + 0.08 * k), s.t(bar, bb) + s.hum(0.003), 0.1 - 0.05 * k)

    room = hall_ir(1.25, seed=33, hf_damp=0.55)
    pno = level(s.get("piano"), -20)
    bass = level(s.get("bass"), -22)
    drums = level(s.get("drums"), -21.5)
    horns = level(s.get("horns"), -19.5)
    wet = reverb(0.25 * pno + 0.4 * horns + 0.2 * drums + 0.05 * bass, room)
    mix = pno + bass + drums + horns + 0.35 * wet
    return finish("drive_boogie.ogg", mix, s, loop=True)


# ==========================================================================
# 3. DRIVE ROCKABILLY -- 170 BPM, E, 5 x 12-bar (84.7 s)
# ==========================================================================
ROCK_RIFF = [  # 2 bars, relative to root, straight 8ths (twangy low-string riff)
    [(0, 0.5, 0), (0.5, 0.5, 3), (1, 0.5, 4), (1.5, 0.5, 7), (2, 1.0, 9), (3, 0.5, 7), (3.5, 0.5, 4)],
    [(0, 0.5, 3), (0.5, 0.5, 0), (1, 1.5, -2), (2.5, 0.5, 0), (3, 1.0, 0)],
]
ROCK_TURN = [(0, 0.5, 64), (0.5, 0.5, 62), (1, 0.5, 59), (1.5, 0.5, 57), (2, 0.5, 56), (2.5, 0.5, 55),
             (3, 1.0, 52), (4, 0.5, 47), (4.5, 0.5, 51), (5, 0.5, 54), (5.5, 0.5, 57), (6, 1.0, 59)]
ROCK_SOLO = [
    [(0, 0.5, 67), (0.5, 0.5, 68), (1, 0.5, 71), (1.5, 0.5, 76), (2, 1.0, 74), (3, 0.5, 71), (3.5, 0.5, 67),
     (4, 1.5, 64), (5.5, 0.5, 67), (6, 0.5, 64), (6.5, 0.5, 62), (7, 1, 59)],
    [(k * 0.5, 0.5, [71, 76] if k % 4 != 3 else [69, 74]) for k in range(8)] +
    [(4, 0.5, 79), (4.5, 0.5, 76), (5, 0.5, 74), (5.5, 0.5, 71), (6, 2, 76)],
    [(0.5, 0.5, 76), (1, 0.5, 79), (1.5, 0.5, 76), (2, 0.5, 74), (2.5, 0.5, 71), (3, 1, 69),
     (4, 0.5, 67), (4.5, 0.5, 68), (5, 1, 71), (6, 0.5, 68), (6.5, 0.5, 67), (7, 1, 64)],
    [(k / 3, 1 / 3, m) for k, m in enumerate([76, 74, 71, 74, 71, 69, 71, 69, 67, 69, 67, 64])] +
    [(4, 1, [64, 68]), (5, 1, [64, 68]), (6, 2, [64, 71])],
]


def drive_rockabilly():
    bpm, bars = 170, 60
    s = Song(bars * 4 * 60 / bpm, tail_s=4.0, bpm=bpm, swing=0.54, seed=53)
    kit = DrumKit(seed=13, snare={"decay": 0.14, "tone": 200})
    rng = s.rng
    form = BLUES_E * 5
    rhythm_root = {4: 40, 9: 45, 11: 47}
    lead_root = {4: 52, 9: 57, 11: 47}

    def lead(m, d, v, r, **kw):
        return guitar(m, d, v, r, bright=0.9, pickup=0.08, t60=2.5, damp=0.12)

    for bar in range(bars):
        ch, i = bar // 12, bar % 12
        pc, _ = parse_chord(form[bar])
        # slap bass: walking quarters + slap clicks on the &s
        br = rhythm_root[pc]
        pat = [0, 4, 7, 9] if bar % 2 == 0 else [10, 9, 7, 4]
        for k, iv in enumerate(pat):
            s.add("bass", slap_bass(br + iv, 0.8 * s.beat, 0.9 if k == 0 else 0.8, rng), s.t(bar, k) + s.hum(0.003))
            s.add("bass", slap_click(0.75 * rng.uniform(0.85, 1.05), rng), s.t(bar, k + 0.5) + s.hum(0.003))
        # Chuck-Berry shuffle rhythm guitar (5-6 dyads)
        for k in range(8):
            top = 7 if (k // 2) % 2 == 0 else 9
            if i == 11 and k >= 4:
                top = 10
            t = s.t(bar, k * 0.5) + s.hum(0.003)
            v = 0.8 if k % 2 == 0 else 0.62
            for m in (br, br + top):
                s.add("rhythm", guitar(m, 0.42 * s.beat, v, rng, bright=0.6, pickup=0.15, t60=0.35, damp=0.35), t,
                      -0.45)
        # lead guitar
        lr = lead_root[pc]
        if ch in (1, 4) or (ch == 0 and i < 4):
            if i in (0, 2, 4, 6):
                play_line(s, "lead", ROCK_RIFF[0], bar, lead, transpose=lr, vel=0.85, pan=0.3, gate=0.95, hum=0.003)
            elif i in (1, 3, 5, 7):
                play_line(s, "lead", ROCK_RIFF[1], bar, lead, transpose=lr, vel=0.85, pan=0.3, gate=0.95, hum=0.003)
            elif i in (8, 9):
                play_line(s, "lead", ROCK_RIFF[0], bar, lead, transpose=lr, vel=0.85, pan=0.3, gate=0.95, hum=0.003)
            elif i == 10:
                play_line(s, "lead", ROCK_TURN, bar, lead, vel=0.85, pan=0.3, gate=0.95, hum=0.003)
        elif ch == 2 or ch == 3:
            if i % 2 == 0 and i < 10:
                lick = ROCK_SOLO[(i // 2 + (ch - 2) * 2) % 4]
                play_line(s, "lead", lick, bar, lead, transpose=12 if ch == 3 and i < 4 else 0, vel=0.85,
                          pan=0.3, gate=0.95, hum=0.003)
            elif i == 10:
                play_line(s, "lead", ROCK_TURN, bar, lead, transpose=12, vel=0.85, pan=0.3, gate=0.95, hum=0.003)
        # train-beat drums
        for k in range(8):
            b = k * 0.5
            acc = k in (2, 6)
            v = 0.9 if acc else (0.42 if k % 2 == 0 else 0.3)
            s.add("drums", kit.hit("snare", v * rng.uniform(0.92, 1.05)), s.t(bar, b) + s.hum(0.0025), 0.05)
            s.add("drums", kit.hit("hat", 0.35 if k % 2 == 0 else 0.25), s.t(bar, b) + s.hum(0.0025), -0.3)
        for b in (0, 2):
            s.add("drums", kit.hit("kick", 0.85), s.t(bar, b) + s.hum(0.002), 0.0)
        if ch in (2, 4) and bar % 2 == 1:
            s.add("drums", kit.hit("kick", 0.6), s.t(bar, 3.5), 0.0)
        if i == 0:
            s.add("drums", kit.hit("crash", 0.55), s.t(bar, 0), 0.4)
        if i == 11:
            for k, nm_ in enumerate(["tom140", "tom140", "tom110", "tom110", "tom85", "tom85", "snare", "snare"]):
                s.add("drums", kit.hit(nm_, 0.55 + 0.05 * k), s.t(bar, 2 + k * 0.25), 0.3 - 0.08 * k)

    room = hall_ir(1.1, seed=41)
    bass = level(s.get("bass"), -21.5)
    rhythm = level(guitar_tone(s.get("rhythm"), twang=2.0, drive=2.0, cab_lp=5000), -23.5)
    lead_b = guitar_tone(s.get("lead"), twang=5.5, drive=1.5, cab_lp=6000)
    lead_b = level(slapback(lead_b, 0.12, fb=0.25, mix=0.55), -19)
    drums = level(s.get("drums"), -21.5)
    sp = spring_ir(seed=5)
    wet = reverb(0.2 * bass + 0.3 * rhythm + 0.4 * lead_b + 0.25 * drums, room)
    wsp = reverb(0.5 * lead_b + 0.2 * rhythm, sp)
    mix = bass + rhythm + lead_b + drums + 0.3 * wet + 0.25 * wsp
    return finish("drive_rockabilly.ogg", mix, s, loop=True)


# ==========================================================================
# 4. TENSION NIGHT -- 70 BPM, E minor, 24 bars (82.3 s)
# ==========================================================================
def theremin_phrase(points, rng, glide=0.12, vib=28.0):
    """points: [(time_s, midi)] with the last time being the end -> mono array"""
    T = points[-1][0]
    n = ns(T + 0.6)
    t = tvec(n)
    target = np.zeros(n)
    for (t0, m), (t1, _) in zip(points[:-1], points[1:]):
        target[ns(t0):ns(t1)] = mtof(m)
    target[ns(T):] = mtof(points[-2][1])
    # portamento: exponential smoothing of the pitch (in log domain)
    lg = np.log(target)
    a = np.exp(-1 / (glide * SR))
    from scipy.signal import lfilter
    lg = lfilter([1 - a], [1, -a], lg, zi=[lg[0] * a])[0]
    f = np.exp(lg)
    y = theremin(f, n, vib_cents=vib, rng=rng)
    env = np.clip(t / 0.5, 0, 1) * np.clip((T + 0.5 - t) / 0.9, 0, 1)
    return y * env ** 1.5


def tension_night():
    bpm, bars = 70, 24
    s = Song(bars * 4 * 60 / bpm, tail_s=8.0, bpm=bpm, swing=0.5, seed=54)
    kit = DrumKit(seed=17)
    rng = s.rng
    prog = ["Em9", "Cmaj7", "Am6", "B7b9"]
    bass_pc = {"Em9": 4, "Cmaj7": 0, "Am6": 9, "B7b9": 11}

    s.add("drone", np.vstack([drone_loop(s, [28, 35], cutoff=180.0, lfo_bars=8)] * 2), 0.0)
    for bar in range(bars):
        name = prog[(bar // 2) % 4]
        if bar % 2 == 0:
            v = guitar_voicing(name)
            strum(s, "trem", s.t(bar, 0) + s.hum(0.01), v, 0.6, 2 * 4 * s.beat, spread=0.09, pan=-0.3,
                  **trem_gtr_kw())
            s.add("bass", upright_bass(bass_root(bass_pc[name], 28), 3.2 * s.beat, 0.8, rng, t60=2.5), s.t(bar, 0))
        else:
            v = guitar_voicing(name)[-3:]
            strum(s, "trem", s.t(bar, 2) + s.hum(0.01), v, 0.4, 2 * s.beat, spread=0.12, down=False, pan=0.35,
                  **trem_gtr_kw())
        # heartbeat
        if 2 <= bar < 22 and not (bar % 8 == 7):
            for b in range(4):
                s.add("perc", kit.hit("heart", 0.9 if b % 2 == 0 else 0.75), s.t(bar, b) + s.hum(0.004), 0.0)
        # clock ticks
        if bar >= 4:
            for k in range(8):
                nm_ = "tick" if k % 2 == 0 else "tock"
                s.add("tick", kit.hit(nm_, (0.35 if k % 2 == 0 else 0.25) * (1.2 if bar >= 16 else 1.0)),
                      s.t(bar, k * 0.5) + s.hum(0.002), 0.45)
        if bar in (0, 8, 16):
            for m in (28, 40, 47):
                s.add("piano", piano_c(m, 3.0, 0.75, rng), s.t(bar, 0), -0.1)
            s.add("perc", kit.hit("timp82", 0.7), s.t(bar, 0), 0.0)
    # reversed-cymbal swells that suck into every 8-bar downbeat (bar 24 == loop start)
    for target_bar in (8, 16, 24):
        cym = crash(0.9, rng, decay=3.0)[::-1]
        cym = highpass(cym, 3000)
        s.add("shimmer", cym, s.t(target_bar, 0) - len(cym) / SR, 0.0)
    # theremin glides (1950s saucer-movie eeriness)
    b = s.beat
    s.add("ther", theremin_phrase([(0, 76), (1.2 * b, 83), (3.5 * b, 79), (4.5 * b, 78), (6 * b, 71), (8 * b, 71)],
                                  rng), s.t(4, 0), 0.2)
    s.add("ther", theremin_phrase([(0, 71), (1.5 * b, 72), (3 * b, 76), (4 * b, 75), (5.5 * b, 81), (7 * b, 79),
                                   (9 * b, 76), (10 * b, 76)], rng), s.t(12, 0), 0.25)
    s.add("ther", theremin_phrase([(0, 83), (2 * b, 79), (3 * b, 78), (4.5 * b, 76), (6 * b, 75), (8 * b, 76),
                                   (9 * b, 76)], rng, glide=0.2), s.t(20, 0), 0.15)

    rate = 3.0 / s.beat
    trem = guitar_tone(s.get("trem"), twang=2.0, drive=1.6, cab_lp=4200)
    trem = level(tremolo(trem, rate, depth=0.8), -23)
    drone = level(highpass(s.get("drone"), 32.0), -31)
    perc = level(highpass(lowpass(s.get("perc"), 900), 30.0), -29.5)
    tick = level(s.get("tick"), -28)
    shimmer = level(s.get("shimmer"), -30)
    pno = level(s.get("piano"), -26)
    bass = level(s.get("bass"), -26)
    ther = level(s.get("ther"), -21)
    big = hall_ir(3.8, seed=61, hf_damp=0.5)
    sp = spring_ir(seed=8)
    wet = reverb(0.7 * trem + 0.8 * ther + 0.3 * tick + 0.4 * pno + 0.15 * perc + 0.6 * shimmer, big)
    wsp = reverb(0.8 * trem, sp)
    # ticks bounce with a dark delay
    d = ns(s.beat * 0.75)
    tick_d = np.concatenate([np.zeros((2, d)), tick[:, :-d]], axis=1)[::-1] * 0.4
    mix = trem + drone + perc + tick + tick_d + pno + bass + ther + shimmer + 0.55 * wet + 0.3 * wsp
    return finish("tension_night.ogg", mix, s, loop=True, target=-16.0)


# ==========================================================================
# 5. FINALE -- 160 BPM, E minor, 64 bars (96 s)
# ==========================================================================
def finale():
    bpm, bars = 160, 64
    s = Song(bars * 4 * 60 / bpm, tail_s=5.0, bpm=bpm, swing=0.5, seed=55)
    kit = DrumKit(seed=19, kick={"decay": 0.35}, snare={"decay": 0.2, "tone": 175})
    rng = s.rng
    counter = [[(0, "Am")], [(0, "Em")], [(0, "Am")], [(0, "B7")], [(0, "C")], [(0, "G")], [(0, "Am")], [(0, "B7")]]
    breakdown = [[(0, "Em")], [(0, "Em")], [(0, "C")], [(0, "C")], [(0, "Am")], [(0, "Am")], [(0, "B7")],
                 [(0, "B7")]]
    chords = ([[(0, "Em")]] * 3 + [[(0, "Em"), (2, "B7")]] + MOTIF_CHORDS + counter + MOTIF_CHORDS + breakdown +
              MOTIF_CHORDS + counter + MOTIF_CHORDS + [[(0, "C")], [(0, "C")], [(0, "B7")], [(0, "B7")]])
    assert len(chords) == bars
    motif_at = {4: 0, 20: 1, 36: 2, 52: 3}

    def gtr_lead(m, d, v, r, **kw):
        return guitar(m, d, v, r, bright=0.9, pickup=0.09, t60=2.0, damp=0.15)

    for start, k in motif_at.items():
        tp = [0, 12, 0, 12][k]
        play_line(s, "brass", MAIN_MOTIF, start, brass, transpose=tp, vel=0.9, pan=0.2, gate=0.9, bright=1.1)
        play_line(s, "brass", MAIN_MOTIF, start, brass, transpose=tp - 12, vel=0.85, pan=-0.2, gate=0.9, bright=0.8)
        if k == 3:
            play_line(s, "brass", MAIN_MOTIF, start, brass, transpose=-24, vel=0.8, pan=0.0, gate=0.9, bright=0.6)
        play_line(s, "glead", MAIN_MOTIF, start, gtr_lead, transpose=-12, vel=0.85, pan=0.35, gate=0.95)
    sections = {"intro": range(0, 4), "counter": list(range(12, 20)) + list(range(44, 52)), "breakdown": range(28, 36),
                "end": range(60, 64)}
    for bar in range(bars):
        segs = segments(chords[bar])
        is_break = bar in sections["breakdown"]
        is_counter = bar in sections["counter"]
        for (b0, ln, name) in segs:
            pc, q = parse_chord(name)
            r = bass_root(pc, 28)
            # bass gallop 8ths
            for k in range(int(ln * 2)):
                bb = b0 + k * 0.5
                if is_break and k % 2 == 1:
                    continue
                m = r + (12 if k % 4 == 2 else 0)
                s.add("bass", upright_bass(m, 0.45 * s.beat, 0.85 if k % 2 == 0 else 0.7, rng, t60=0.8),
                      s.t(bar, bb) + s.hum(0.003))
            # chugging power chords (double tracked)
            if not is_break:
                pr = 40 + ((pc - 40) % 12)
                pw = [pr, pr + 7, pr + 12]
                for k in range(int(ln * 2)):
                    bb = b0 + k * 0.5
                    acc = k % 2 == 0
                    for side in (-0.55, 0.55):
                        for m in pw:
                            s.add("chug", guitar(m, 0.4 * s.beat, 0.85 if acc else 0.6, rng, palm=True, pickup=0.15),
                                  s.t(bar, bb) + s.hum(0.004), side)
            else:
                strum(s, "trem", s.t(bar, b0), guitar_voicing(name), 0.6, ln * s.beat + 0.2, spread=0.03, pan=0.2,
                      **trem_gtr_kw())
            if is_counter or bar in sections["end"]:
                vo = close_voicing(pc, [0, 4 if q in ("maj", "7") else 3, 7], low=60)
                if q == "7":
                    vo = close_voicing(pc, [4, 7, 10], low=60)
                hits = [(0, 1.2), (1.5, 0.4), (3, 0.9)] if bar not in sections["end"] else [(0, 3.8)]
                for hb, hd in hits:
                    if hb >= b0 + ln or hb < b0:
                        continue
                    for m, pan, brt in ((vo[2], 0.3, 1.0), (vo[1], -0.3, 0.9), (vo[0], 0.1, 0.8), (r + 12, -0.1, 0.6)):
                        s.add("brass", brass(m, hd * s.beat, 0.85, rng, bright=brt), s.t(bar, hb) + s.hum(0.004), pan)
        # drums
        if bar in sections["intro"] or is_break:
            for k in range(8):
                bb = k * 0.5
                s.add("drums", kit.hit("tom75" if k % 2 == 0 else "tom110", 0.8 if k % 2 == 0 else 0.5),
                      s.t(bar, bb) + s.hum(0.003), -0.2 if k % 2 == 0 else 0.25)
            if is_break and bar % 2 == 0:
                s.add("drums", kit.hit("timp82", 0.9), s.t(bar, 0), 0.0)
                s.add("drums", kit.hit("kick", 0.9), s.t(bar, 0), 0.0)
            if bar in (34, 35):  # snare roll crescendo into the motif
                for k in range(16):
                    s.add("drums", kit.hit("snare", 0.25 + 0.6 * ((bar - 34) * 16 + k) / 32), s.t(bar, k * 0.25), 0.05)
        else:
            for k in range(8):
                bb = k * 0.5
                s.add("drums", kit.hit("hat", 0.5 if k % 2 == 0 else 0.35), s.t(bar, bb) + s.hum(0.002), -0.3)
            for bb in (0, 1.5, 2, 2.5):
                s.add("drums", kit.hit("kick", 0.85 if bb in (0, 2) else 0.6), s.t(bar, bb) + s.hum(0.002), 0.0)
            for bb in (1, 3):
                s.add("drums", kit.hit("snare", 0.88), s.t(bar, bb) + s.hum(0.002), 0.05)
            if bar in sections["end"]:
                for k in range(16):
                    s.add("drums", kit.hit("snare", 0.2 + 0.5 * ((bar - 60) * 16 + k) / 64), s.t(bar, k * 0.25), 0.05)
                if bar % 2 == 0:
                    s.add("drums", kit.hit("timp82", 0.9), s.t(bar, 0), 0.0)
        if bar % 8 == 4 or bar == 0 or (bar % 2 == 0 and bar >= 52 and bar < 60):
            s.add("drums", kit.hit("crash", 0.6), s.t(bar, 0), 0.35 if bar % 16 else -0.35)
        if bar in (11, 19, 27, 43, 51, 59):  # big tom fill
            for k, nm_ in enumerate(["tom150", "tom150", "tom120", "tom120", "tom95", "tom95", "tom75", "tom75"]):
                s.add("drums", kit.hit(nm_, 0.7 + 0.03 * k), s.t(bar, 2 + k * 0.25), 0.35 - 0.1 * k)
    # breakdown drone
    n_bd = ns(8 * 4 * s.beat + 2.0)
    dr = np.zeros(n_bd)
    for m in (28, 35, 40):
        dr += saw(mtof(m) * 1.001, n_bd, rng.uniform()) + saw(mtof(m) * 0.999, n_bd, rng.uniform())
    dr = lowpass(dr, 260, 2) * np.clip(tvec(n_bd) / 3.0, 0, 1) * np.clip((n_bd / SR - tvec(n_bd)) / 1.5, 0, 1)
    s.add("drone", dr, s.t(28, 0))

    brass_b = level(s.get("brass"), -18)
    glead = level(slapback(guitar_tone(s.get("glead"), twang=5, drive=1.6), 0.12, 0.2, 0.4), -21)
    chug = level(guitar_tone(s.get("chug"), twang=1.5, drive=2.6, cab_lp=4500), -22.5)
    trem = level(tremolo(guitar_tone(s.get("trem"), twang=2, drive=1.6), 2 / s.beat, depth=0.7), -23)
    bass = level(s.get("bass"), -21)
    drums = level(s.get("drums"), -19.5)
    drone = level(s.get("drone"), -26)
    hall = hall_ir(1.9, seed=71)
    wet = reverb(0.35 * brass_b + 0.3 * glead + 0.25 * drums + 0.5 * trem + 0.1 * chug, hall)
    mix = brass_b + glead + chug + trem + bass + drums + drone + 0.33 * wet
    return finish("finale.ogg", mix, s, loop=True, drive=1.35)


# ==========================================================================
# 6. VICTORY sting (~7 s, E major)
# ==========================================================================
def victory():
    s = Song(7.0, tail_s=0.0, bpm=120, seed=56, loop=False)
    kit = DrumKit(seed=23)
    rng = s.rng
    # snare pickup
    for k in range(6):
        s.add("drums", kit.hit("snare", 0.35 + 0.08 * k), 0.02 + k * 0.07, 0.05)
    for tt in (0.2, 0.36):
        for m, p in ((64, 0.2), (52, -0.2)):
            s.add("brass", brass(m, 0.12, 0.8, rng, bright=1.0), tt, p)
    seq = [(0.5, 0.35, 0), (0.9, 0.35, 2), (1.3, 3.4, 4)]  # bVI - bVII - I  (C - D - E)
    for (t0, d, tp) in seq:
        root = 48 + tp
        voic = [root, root + 7, root + 12, root + 16, root + 19, root + 24, root + 28]
        for i, m in enumerate(voic):
            pan = -0.4 + 0.8 * i / (len(voic) - 1)
            s.add("brass", brass(m, d, 0.9, rng, bright=1.1 if m > 64 else 0.8, vib=10 if d > 1 else 0,
                                 rel=0.9 if d > 1 else 0.08), t0, pan)
        s.add("bass", upright_bass(36 + tp, d, 0.9, rng), t0)
        s.add("drums", kit.hit("timp82", 0.8) if tp == 4 else kit.hit("tom95", 0.7), t0, 0)
    # last chord: trumpet climbs to the high 3rd
    s.add("brass", brass(80, 2.4, 0.95, rng, bright=1.2, vib=14, rel=0.4), 1.75, 0.25)
    strum(s, "gtr", 1.3, guitar_voicing("E"), 0.85, 4.5, spread=0.02, pan=-0.35, bright=0.8, pickup=0.1, t60=4.0)
    s.add("gtr", guitar(64 + 12, 3.5, 0.6, rng, bright=0.9, pickup=0.08), 1.75, -0.35)
    s.add("drums", kit.hit("crash", 0.9), 1.3, 0.3)
    s.add("drums", kit.hit("kick", 1.0), 1.3, 0.0)
    for k in range(18):  # timpani roll under the final chord
        s.add("drums", kit.hit("timp82", 0.25 + 0.3 * np.sin(np.pi * k / 18)), 1.45 + k * 0.08, 0.0)
    brass_b = level(s.get("brass"), -17)
    gtr = level(tremolo(guitar_tone(s.get("gtr"), twang=4), 8.0, depth=0.5), -22)
    bass = level(s.get("bass"), -22)
    drums = level(s.get("drums"), -20)
    hall = hall_ir(2.8, seed=81)
    wet = reverb(0.5 * brass_b + 0.5 * gtr + 0.3 * drums, hall)
    mix = brass_b + gtr + bass + drums + 0.45 * wet
    env = np.ones(mix.shape[1])
    t = tvec(mix.shape[1])
    env *= np.clip((7.0 - t) / 1.6, 0, 1) ** 1.5  # gentle ring-out to silence at 7 s
    return finish("victory.ogg", mix * env, s, loop=False, target=-14.0)


# ==========================================================================
# 7. DEFEAT sting (~6 s, lament bass to E minor)
# ==========================================================================
def defeat():
    bpm = 72
    s = Song(6.0, tail_s=0.0, bpm=bpm, seed=57, loop=False)
    kit = DrumKit(seed=29)
    rng = s.rng
    b = s.beat
    melody = [(0, 0.95, 71), (1, 0.95, 69), (2, 0.95, 67), (3, 0.95, 66), (4, 3.0, 64)]
    for (bt, d, m) in melody:
        s.add("lead", lead_horn(m, d * b, 0.8, rng, whistle=0.15, vib_cents=14), bt * b + 0.05, 0.1)
    harmony = [(0, [52, 55, 59], 40), (1, [50, 54, 57], 38), (2, [48, 52, 55], 36), (3, [47, 51, 54, 57], 35),
               (4, [40, 47, 52, 55, 59], 28)]
    for (bt, notes, bass_m) in harmony:
        d = 0.98 * b if bt < 4 else 3.2
        for m in notes:
            s.add("brass", brass(m, d, 0.55, rng, bright=0.45, scoop=False, attack=0.08, rel=0.4), bt * b + 0.05,
                  -0.2 + 0.1 * (m % 5))
        s.add("bass", upright_bass(bass_m + 12, d, 0.85, rng, t60=2.5), bt * b + 0.05)
    strum(s, "gtr", 4 * b + 0.05, guitar_voicing("Em"), 0.7, 3.0, spread=0.06, pan=-0.3, **trem_gtr_kw())
    for m in (28, 40):
        s.add("pno", piano_c(m, 2.5, 0.8, rng), 4 * b + 0.05, 0.0)
    s.add("drums", kit.hit("timp82", 0.9), 4 * b + 0.05, 0.0)
    s.add("drums", kit.hit("crash", 0.35), 4 * b + 0.05, 0.3)
    lead = level(s.get("lead"), -18)
    brass_b = level(s.get("brass"), -22)
    bass = level(s.get("bass"), -22)
    gtr = level(tremolo(guitar_tone(s.get("gtr"), twang=2), 3 / b, depth=0.7), -24)
    pno = level(s.get("pno"), -24)
    drums = level(s.get("drums"), -22)
    hall = hall_ir(3.0, seed=91)
    wet = reverb(0.6 * lead + 0.4 * brass_b + 0.5 * gtr + 0.4 * pno + 0.3 * drums, hall)
    mix = lead + brass_b + bass + gtr + pno + drums + 0.5 * wet
    t = tvec(mix.shape[1])
    mix *= np.clip((6.0 - t) / 1.6, 0, 1) ** 1.5
    return finish("defeat.ogg", mix, s, loop=False, target=-15.0)


# ==========================================================================
# 8. TRAILER THEME -- exactly 90.0 s.  Accents at 18.0, 45.0, 80.0 (+ final chord 84.0)
# ==========================================================================
TRAILER_HITS = (18.0, 45.0, 80.0, 84.0)


def trailer_theme():
    total = 90.0
    s = Song(total, tail_s=0.0, bpm=144, swing=0.5, seed=58, loop=False)
    s.N = ns(total + 6.0)  # allow tails to be computed, file is cut to 90.0
    s.L = ns(total)
    kit = DrumKit(seed=31, kick={"decay": 0.4})
    rng = s.rng
    B = s.beat          # 144 BPM
    BAR = 4 * B         # 1.6667 s

    def at(t0, bar, beat=0.0):
        return t0 + (bar * 4 + beat) * B

    # ---------------- 0 - 18 s : ominous intro ----------------
    n = ns(18.0)
    t = tvec(n)
    dr = np.zeros(n)
    for m in (28, 35, 40):
        for dc in (-5, 0, 6):
            dr += saw(mtof(m) * 2 ** (dc / 1200), n, rng.uniform())
    dr = tv_filter(dr, 110 + 550 * (t / 18.0) ** 2, q=1.6)
    dr *= np.clip(t / 4.0, 0, 1) * np.clip((18.0 - t) / 0.05, 0, 1)
    s.add("drone", dr, 0.0)
    wind = pink(n + ns(2), rng)[:n]
    wc = 500 + 400 * smooth_rand(n, rng, 0.3, periodic=False) / 1.0
    wind = tv_filter(wind, np.clip(wc, 250, 1500), q=3.0, kind="bandpass")
    gust = 0.6 + 0.4 * np.clip(smooth_rand(n, rng, 0.25, periodic=False) * 2, -1, 1)
    wind *= gust * np.clip(t / 2.0, 0, 1) * np.clip((18.0 - t) / 1.0, 0, 1)
    s.add("wind", np.vstack([wind, np.roll(wind, 900)]), 0.0)
    rum_n = ns(9.0)
    rum = lowpass(brown(rum_n, rng), 110, 4)
    rt = tvec(rum_n)
    rum *= np.clip(rt / 3.0, 0, 1) ** 2 * np.exp(-np.clip(rt - 3.0, 0, None) / 2.0)
    s.add("rumble", rum, 5.0)
    twang = [(1.5, 40, 5.0, 0.9), (4.0, 47, 3.0, 0.6), (6.0, 52, 3.0, 0.7), (8.0, 55, 1.0, 0.65),
             (9.0, 54, 2.5, 0.6), (11.5, 52, 1.2, 0.7), (13.0, 52, 0.9, 0.7), (13.9, 55, 0.4, 0.6),
             (14.3, 59, 2.0, 0.75), (16.2, 51, 1.8, 0.7)]
    for (t0, m, d, v) in twang:
        s.add("bari", bari(m, d, v, rng), t0, -0.1)
    s.add("ther", theremin_phrase([(0, 71), (1.4, 76), (2.8, 79), (3.6, 78), (4.8, 75), (6.0, 76)], rng, glide=0.18),
          9.2, 0.25)
    for k in range(16):  # ticking clock, creeping in
        tt = 10.0 + k * 0.5
        s.add("perc", kit.hit("tick" if k % 2 == 0 else "tock", 0.15 + 0.35 * k / 16), tt, 0.4)

    # ---------------- 18.0 : HIT + riser to 20.0 ----------------
    def big_hit(t0, chord_notes, strength=1.0, brass_len=0.6):
        s.add("fx", boom(3.5, rng) * strength, t0)
        s.add("drums", kit.hit("crash", 0.9 * strength), t0, 0.3)
        s.add("drums", kit.hit("crash", 0.8 * strength), t0, -0.3)
        s.add("drums", kit.hit("kick", 1.0), t0, 0.0)
        s.add("drums", kit.hit("timp82", 1.0 * strength), t0, 0.0)
        for m in (28, 40):
            s.add("pno", piano_c(m, 2.5, 0.9, rng), t0, 0.0)
        for i, m in enumerate(chord_notes):
            s.add("brass", brass(m, brass_len, 0.95, rng, bright=1.2, rel=0.3), t0, -0.4 + 0.8 * i / len(chord_notes))
        strum(s, "gtr", t0, guitar_voicing("Em"), 0.9, 2.5, spread=0.008, pan=-0.35, bright=0.8, pickup=0.12, t60=3.0)

    em_stab = [40, 47, 52, 55, 59, 64, 67, 71]
    big_hit(18.0, em_stab, 1.0, 0.5)
    s.add("fx", riser(1.8, rng) * 0.45, 18.2)
    for k in range(16):  # snare roll swelling into 20.0
        s.add("drums", kit.hit("snare", 0.08 + 0.4 * (k / 16) ** 2), 19.2 + k * 0.05, 0.05)

    # ---------------- 20 - 45 s : 15 bars @144, motif on guitar over tom pulse ----------------
    T0 = 20.0
    motif_ch = MOTIF_CHORDS
    for bar in range(15):
        if bar < 4:
            name = "Em"
            bc = [(0, "Em")]
        elif bar < 12:
            bc = motif_ch[bar - 4]
            name = bc[0][1]
        else:
            bc = [(0, ["C", "Am", "B7"][bar - 12])]
            name = bc[0][1]
        # tom pulse
        for k in range(8):
            v = 0.85 if k in (0, 3, 6) else 0.45
            s.add("drums", kit.hit("tom75", v * (0.8 + 0.2 * bar / 15)), at(T0, bar, k * 0.5), -0.15)
        if bar >= 4:
            for k in range(8):
                s.add("drums", kit.hit("hat", 0.35 if k % 2 == 0 else 0.22), at(T0, bar, k * 0.5) + s.hum(0.002), -0.3)
            s.add("drums", kit.hit("kick", 0.7), at(T0, bar, 0), 0)
            s.add("drums", kit.hit("rim", 0.5), at(T0, bar, 2), 0.1)
        for (b0, nme) in bc:
            pc, _ = parse_chord(nme)
            r = bass_root(pc, 28)
            for k in range(8 if len(bc) == 1 else 4):
                bb = b0 + k * 0.5
                s.add("bass", upright_bass(r + (12 if k % 4 == 3 else 0), 0.45 * B, 0.8, rng, t60=0.9),
                      at(T0, bar, bb))
            if bar % 2 == 0 or bar >= 4:
                strum(s, "trem", at(T0, bar, b0), guitar_voicing(nme), 0.5, 4 * B / len(bc) + 0.2, spread=0.02,
                      pan=0.35, **trem_gtr_kw())
    for (b, d, m) in MAIN_MOTIF:
        s.add("bari", bari(m - 12, d * B, 0.9, rng), at(T0, 4, b), -0.15)
    # build 43.3 -> 45
    for k in range(40):
        tt = at(T0, 12, 0) + k * (3 * BAR) / 40
        s.add("drums", kit.hit("snare", 0.15 + 0.7 * (k / 40) ** 1.5), tt, 0.05)
    for i, m in enumerate([47, 51, 54, 57, 59, 63, 66]):
        s.add("brass", brass(m, 3 * BAR - 0.1, 0.7, rng, bright=0.6 + 0.6 * i / 7, attack=2.5, scoop=False, rel=0.05),
              at(T0, 12, 0), -0.4 + 0.8 * i / 6)
    s.add("fx", riser(2.4, rng) * 0.6, 45.0 - 2.4)

    # ---------------- 45.0 : HIT, then 45 - 80 s full drive ----------------
    big_hit(45.0, em_stab, 1.0, 0.35)
    T1 = 45.0
    form = [c for c in MOTIF_CHORDS] + [[(0, c)] for c in BLUES_E] + [[(0, "B7")]]
    assert len(form) == 21
    for (b, d, m) in MAIN_MOTIF:
        for tp, pan, brt, v in ((0, 0.25, 1.1, 0.9), (-12, -0.25, 0.8, 0.85), (12, 0.1, 1.0, 0.6)):
            s.add("brass", brass(m + tp, d * B * 0.9, v, rng, bright=brt), at(T1, 0, b) + s.hum(0.004), pan)
    for bar in range(21):
        bc = form[bar]
        blues = 8 <= bar < 20
        for (b0, ln, nme) in segments(bc):
            pc, q = parse_chord(nme)
            br = 40 + ((pc - 40) % 12) if pc != 11 else 35
            # slap bass
            pat = ([0, 4, 7, 9] if bar % 2 == 0 else [10, 9, 7, 4]) if blues else [0, 7, 12, 7]
            for k in range(int(ln)):
                s.add("bass", slap_bass(br + pat[k % 4], 0.8 * B, 0.9, rng), at(T1, bar, b0 + k))
                s.add("bass", slap_click(0.7, rng), at(T1, bar, b0 + k + 0.5))
            # rhythm guitar
            for k in range(int(ln * 2)):
                if blues:
                    top = 7 if (k // 2) % 2 == 0 else 9
                    notes = [br, br + top]
                else:
                    notes = [br, br + 7, br + 12]
                for m in notes:
                    s.add("rhythm", guitar(m, 0.42 * B, 0.8 if k % 2 == 0 else 0.6, rng, bright=0.6, pickup=0.15,
                                           t60=0.35, damp=0.35), at(T1, bar, b0 + k * 0.5) + s.hum(0.003), -0.45)
            if blues:
                i = bar - 8
                lr = {4: 52, 9: 57, 11: 47}[pc]
                if i in (0, 2, 4, 6, 8, 9):
                    part = ROCK_RIFF[0]
                elif i in (1, 3, 5, 7):
                    part = ROCK_RIFF[1]
                else:
                    part = []
                for (bb, dd, mm) in part:
                    s.add("lead", guitar(mm + lr, dd * B * 0.95, 0.85, rng, bright=0.9, pickup=0.08, t60=2.5,
                                         damp=0.12), at(T1, bar, bb) + s.hum(0.003), 0.3)
                if i == 10:
                    for (bb, dd, mm) in ROCK_TURN:
                        s.add("lead", guitar(mm, dd * B * 0.95, 0.85, rng, bright=0.9, pickup=0.08, t60=2.5,
                                             damp=0.12), at(T1, bar, bb), 0.3)
                # horn stabs / riff
                root_h = {4: 64, 9: 57, 11: 59}[pc]
                if i < 10:
                    riffpart = HORN_RIFF[0] if i % 2 == 0 else HORN_RIFF[1]
                    for (bb, dd, rel) in riffpart:
                        for tp, pan, brt in ((0, 0.25, 1.0), (-12, -0.2, 0.8)):
                            s.add("brass", brass(root_h + rel + tp, dd * B * 0.85, 0.8, rng, bright=brt),
                                  at(T1, bar, bb) + s.hum(0.003), pan)
        # drums
        if bar < 20:
            for k in range(8):
                acc = k in (2, 6)
                s.add("drums", kit.hit("snare", 0.9 if acc else (0.4 if k % 2 == 0 else 0.28)),
                      at(T1, bar, k * 0.5) + s.hum(0.002), 0.05)
                s.add("drums", kit.hit("hat", 0.35), at(T1, bar, k * 0.5) + s.hum(0.002), -0.3)
            for bb in (0, 2):
                s.add("drums", kit.hit("kick", 0.9), at(T1, bar, bb), 0)
            if bar in (0, 8, 12, 16):
                s.add("drums", kit.hit("crash", 0.6), at(T1, bar, 0), 0.35)
        else:  # final fill bar -> 80.0
            for k in range(16):
                nm_ = ["tom150", "tom120", "tom95", "tom75"][k // 4]
                s.add("drums", kit.hit(nm_, 0.6 + 0.3 * k / 16), at(T1, bar, k * 0.25), 0.3 - 0.04 * k)
            s.add("drums", kit.hit("kick", 0.8), at(T1, bar, 0), 0)
            for i, m in enumerate([47, 51, 54, 57, 63]):
                s.add("brass", brass(m, 3.5 * B, 0.8, rng, bright=1.0, attack=0.6), at(T1, bar, 0), -0.4 + 0.2 * i)

    # ---------------- 80.0 : BIG STOP HIT ----------------
    big_hit(80.0, [28, 40, 47, 52, 55, 59, 64, 67, 71, 76], 1.2, 0.9)
    s.add("bari", bari(47, 1.5, 0.6, rng), 82.2, -0.1)
    s.add("bari", bari(51, 1.0, 0.65, rng), 83.2, -0.1)
    # ---------------- 84.0 : final chord ring-out ----------------
    s.add("fx", boom(5.0, rng, f_hi=70, f_lo=26) * 0.7, 84.0)
    for i, m in enumerate([40, 47, 52, 55, 59, 64, 66, 71]):
        s.add("brass", brass(m, 5.0, 0.8, rng, bright=0.9, attack=0.05, rel=0.8, vib=6), 84.0,
              -0.45 + 0.9 * i / 7)
    strum(s, "trem", 84.0, guitar_voicing("Em9"), 0.85, 5.5, spread=0.05, pan=0.35, **trem_gtr_kw())
    s.add("bari", bari(40, 5.5, 0.9, rng), 84.0, -0.15)
    for m in (28, 40, 52):
        s.add("pno", piano_c(m, 5.0, 0.9, rng), 84.0, 0.0)
    s.add("drums", kit.hit("crash", 0.8), 84.0, -0.3)
    s.add("drums", kit.hit("timp82", 1.0), 84.0, 0.0)
    for k in range(24):
        s.add("drums", kit.hit("timp82", 0.2 + 0.3 * np.sin(np.pi * k / 24)), 84.2 + k * 0.1, 0.0)

    # ---------------- mix ----------------
    def lv(name, target):
        return level(s.get(name), target)

    drone = lv("drone", -25)
    wind = lv("wind", -28)
    rumble = lowpass(s.get("rumble"), 200)
    rumble *= 0.3 / (np.max(np.abs(rumble)) + 1e-9)
    bari_b = level(guitar_tone(s.get("bari"), twang=5, drive=1.4), -20)
    ther = lv("ther", -22)
    perc = lv("perc", -30)
    fx = lv("fx", -20)
    drums = lv("drums", -20)
    pno = lv("pno", -24)
    brass_b = lv("brass", -18.5)
    gtr = level(guitar_tone(s.get("gtr"), twang=3, drive=2.0), -23)
    trem = level(tremolo(guitar_tone(s.get("trem"), twang=2, drive=1.6), 3 / B, depth=0.7), -24)
    bass = lv("bass", -21.5)
    rhythm = level(guitar_tone(s.get("rhythm"), twang=2, drive=2.0), -23)
    lead_b = level(slapback(guitar_tone(s.get("lead"), twang=5.5, drive=1.5), 0.12, 0.25, 0.55), -20)
    sp = spring_ir(seed=9)
    hall = hall_ir(2.8, seed=99)
    wet_sp = reverb(0.9 * bari_b + 0.6 * trem + 0.4 * lead_b, sp)
    wet_h = reverb(0.5 * bari_b + 0.6 * ther + 0.4 * brass_b + 0.35 * drums + 0.3 * fx + 0.5 * pno + 0.4 * trem +
                   0.4 * gtr + 0.2 * perc, hall)
    mix = (drone + wind + rumble + bari_b + ther + perc + fx + drums + pno + brass_b + gtr + trem + bass + rhythm +
           lead_b + 0.4 * wet_sp + 0.4 * wet_h)
    t = tvec(mix.shape[1])
    # keep the intro ominous and the 18-20 s gap "silence-ish" so the hits land hard
    sect = np.interp(t, [0, 17.97, 18.0, 18.6, 19.95, 20.0], db([-6, -6, 0, -3, -3, 0]))
    mix *= sect
    # the ring-out decays to silence exactly at 90.0 s
    mix *= np.where(t < 85.5, 1.0, np.clip((90.0 - t) / 4.5, 0, 1) ** 2)
    return finish("trailer_theme.ogg", mix, s, loop=False, target=-14.0)


TRACKS = {
    "menu": menu_theme, "boogie": drive_boogie, "rockabilly": drive_rockabilly, "tension": tension_night,
    "finale": finale, "victory": victory, "defeat": defeat, "trailer": trailer_theme,
}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("tracks", nargs="*", help=f"subset of {list(TRACKS)}")
    a = ap.parse_args()
    names = a.tracks or list(TRACKS)
    os.makedirs(OUT, exist_ok=True)
    for nme in names:
        t0 = time.time()
        print(f"[music] {nme}")
        TRACKS[nme]()
        print(f"  ({time.time() - t0:.1f}s)")


if __name__ == "__main__":
    main()
