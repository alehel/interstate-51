"""
synth_lib.py -- DSP + instrument toolkit for INTERSTATE '51.

Everything here is procedural: oscillators, filters, envelopes, physical-model
plucked strings (Karplus-Strong), additive piano / vibraphone, brassy saws,
noise-based drum kit, convolution reverbs built from synthetic impulse
responses, spring reverb, tremolo, slapback echo, tape saturation, loudness
measurement (ITU-R BS.1770) and a look-ahead limiter.

Only numpy + scipy are required.  Encoding to OGG Vorbis uses ffmpeg.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile
from scipy.ndimage import minimum_filter1d, uniform_filter1d

SR = 44100
TWO_PI = 2.0 * np.pi


# --------------------------------------------------------------------------
# basic helpers
# --------------------------------------------------------------------------
def ns(t: float) -> int:
    """seconds -> samples"""
    return int(round(t * SR))


def tvec(n: int) -> np.ndarray:
    return np.arange(n) / SR


def mtof(m):
    return 440.0 * 2.0 ** ((np.asarray(m, dtype=float) - 69.0) / 12.0)


_NOTE_OFS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def nm(name: str) -> int:
    """'E4' -> 64, 'F#3' -> 54, 'Bb2' -> 46"""
    letter = name[0].upper()
    rest = name[1:]
    acc = 0
    while rest and rest[0] in "#b":
        acc += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + _NOTE_OFS[letter] + acc


def db(x):
    return 10.0 ** (np.asarray(x, dtype=float) / 20.0)


def rng_for(seed) -> np.random.Generator:
    return np.random.default_rng(seed)


def fit(x: np.ndarray, n: int) -> np.ndarray:
    """pad / truncate the last axis to n samples"""
    if x.shape[-1] >= n:
        return x[..., :n]
    pad = [(0, 0)] * (x.ndim - 1) + [(0, n - x.shape[-1])]
    return np.pad(x, pad)


def mix_into(dst: np.ndarray, src: np.ndarray, start: int, gain: float = 1.0):
    """add src into dst (both mono or both (2, n)) at sample offset start."""
    if start >= dst.shape[-1]:
        return
    s0 = 0
    if start < 0:
        s0 = -start
        start = 0
    n = min(src.shape[-1] - s0, dst.shape[-1] - start)
    if n <= 0:
        return
    dst[..., start:start + n] += gain * src[..., s0:s0 + n]


# --------------------------------------------------------------------------
# filters
# --------------------------------------------------------------------------
def _clipf(fc):
    return float(np.clip(fc, 5.0, 0.45 * SR))


def lowpass(x, fc, order=2):
    sos = signal.butter(order, _clipf(fc), btype="lowpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=-1)


def highpass(x, fc, order=2):
    sos = signal.butter(order, _clipf(fc), btype="highpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=-1)


def bandpass(x, lo, hi, order=2):
    sos = signal.butter(order, [_clipf(lo), _clipf(hi)], btype="bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=-1)


def rbj(kind: str, f0: float, q: float = 0.707, gain_db: float = 0.0):
    """RBJ audio-EQ-cookbook biquad coefficients (b, a) normalized."""
    f0 = _clipf(f0)
    A = 10 ** (gain_db / 40.0)
    w0 = TWO_PI * f0 / SR
    cw, sw = np.cos(w0), np.sin(w0)
    alpha = sw / (2 * q)
    if kind == "lowpass":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "highpass":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "bandpass":  # constant 0 dB peak gain
        b = [alpha, 0.0, -alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "peak":
        b = [1 + alpha * A, -2 * cw, 1 - alpha * A]
        a = [1 + alpha / A, -2 * cw, 1 - alpha / A]
    elif kind == "lowshelf":
        sa = 2 * np.sqrt(A) * alpha
        b = [A * ((A + 1) - (A - 1) * cw + sa), 2 * A * ((A - 1) - (A + 1) * cw), A * ((A + 1) - (A - 1) * cw - sa)]
        a = [(A + 1) + (A - 1) * cw + sa, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - sa]
    elif kind == "highshelf":
        sa = 2 * np.sqrt(A) * alpha
        b = [A * ((A + 1) + (A - 1) * cw + sa), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - sa)]
        a = [(A + 1) - (A - 1) * cw + sa, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - sa]
    else:
        raise ValueError(kind)
    b = np.array(b) / a[0]
    a = np.array(a) / a[0]
    return b, a


def biquad(x, kind, f0, q=0.707, gain_db=0.0):
    b, a = rbj(kind, f0, q, gain_db)
    return signal.lfilter(b, a, x, axis=-1)


def peq(x, f0, q, gain_db):
    return biquad(x, "peak", f0, q, gain_db)


def tv_filter(x, fc, q=0.707, kind="lowpass", block=64):
    """Time-varying biquad. fc: scalar or per-sample array."""
    x = np.asarray(x, dtype=float)
    n = len(x)
    fc = np.broadcast_to(np.asarray(fc, dtype=float), (n,))
    out = np.empty(n)
    zi = np.zeros(2)
    for i in range(0, n, block):
        j = min(i + block, n)
        b, a = rbj(kind, fc[(i + j) // 2], q)
        out[i:j], zi = signal.lfilter(b, a, x[i:j], zi=zi)
    return out


def onepole(x, fc):
    """gentle 6 dB/oct lowpass"""
    a = np.exp(-TWO_PI * _clipf(fc) / SR)
    return signal.lfilter([1 - a], [1, -a], x, axis=-1)


def dc_block(x, fc=20.0):
    return highpass(x, fc, order=1)


def circ_filter(x, gain_fn):
    """Zero-phase circular filtering in the frequency domain (keeps loops periodic).
    gain_fn(freqs) -> gain array."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X * gain_fn(f), len(x))


def circ_bandpass(x, lo, hi, order=2):
    def g(f):
        f = np.maximum(f, 1e-3)
        glo = 1 / np.sqrt(1 + (lo / f) ** (2 * order)) if lo else 1.0
        ghi = 1 / np.sqrt(1 + (f / hi) ** (2 * order)) if hi else 1.0
        return glo * ghi
    return circ_filter(x, g)


def circ_convolve(x, h):
    """circular convolution of a periodic signal with an impulse response"""
    n = len(x)
    hh = np.zeros(n)
    m = min(len(h), n)
    hh[:m] = h[:m]
    if len(h) > n:  # fold longer responses
        for k in range(n, len(h), n):
            seg = h[k:k + n]
            hh[:len(seg)] += seg
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(hh), n)


# --------------------------------------------------------------------------
# noise
# --------------------------------------------------------------------------
def white(n, rng):
    return rng.standard_normal(n)


def colored_noise(n, rng, slope_db_oct=-3.0, lo=None, hi=None):
    """periodic colored noise: -3 = pink, -6 = brown. Periodic with period n."""
    spec = rng.standard_normal(n // 2 + 1) + 1j * rng.standard_normal(n // 2 + 1)
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1]
    g = (f / 1000.0) ** (slope_db_oct / 6.0206)
    if lo:
        g *= 1 / np.sqrt(1 + (lo / f) ** 4)
    if hi:
        g *= 1 / np.sqrt(1 + (f / hi) ** 4)
    g[0] = 0
    y = np.fft.irfft(spec * g, n)
    return y / (np.std(y) + 1e-12)


def pink(n, rng, **kw):
    return colored_noise(n, rng, -3.0, **kw)


def brown(n, rng, **kw):
    return colored_noise(n, rng, -6.0, **kw)


def smooth_rand(n, rng, rate_hz, periodic=True):
    """slowly varying random control signal, zero mean, unit-ish std."""
    return colored_noise(n, rng, 0.0, hi=rate_hz) if periodic else lowpass(white(n, rng), rate_hz, 2)


# --------------------------------------------------------------------------
# envelopes
# --------------------------------------------------------------------------
def env_exp(n, t60):
    return 10.0 ** (-3.0 * np.arange(n) / SR / max(t60, 1e-4))


def env_adsr(n, a=0.005, d=0.1, s=0.7, r=0.1, gate=None):
    """ADSR where gate (s) is note length; release follows after the gate."""
    if gate is None:
        gate = n / SR - r
    t = tvec(n)
    e = np.empty(n)
    a = max(a, 1e-4)
    att = t < a
    e[att] = t[att] / a
    dec = (t >= a)
    e[dec] = s + (1 - s) * np.exp(-(t[dec] - a) / max(d, 1e-4) * 3.0)
    g_level = s + (1 - s) * np.exp(-(max(gate - a, 0)) / max(d, 1e-4) * 3.0) if gate > a else min(gate / a, 1)
    rel = t >= gate
    e[rel] = g_level * np.exp(-(t[rel] - gate) / max(r, 1e-4) * 6.9)
    return e


def fade(x, fin=0.0, fout=0.0):
    x = x.copy()
    n = x.shape[-1]
    a, b = ns(fin), ns(fout)
    if a > 0:
        x[..., :a] *= np.linspace(0, 1, a) ** 2
    if b > 0:
        x[..., n - b:] *= np.linspace(1, 0, b) ** 2
    return x


def release_gate(x, gate_s, rel_s=0.06):
    """apply a note-off: exponential damp after gate_s."""
    n = len(x)
    g = ns(gate_s)
    if g >= n:
        return x
    e = np.ones(n)
    e[g:] = np.exp(-np.arange(n - g) / SR / max(rel_s, 1e-3) * 6.9)
    return x * e


# --------------------------------------------------------------------------
# oscillators (band-limited)
# --------------------------------------------------------------------------
def phase_acc(freq, n):
    """cycles (not radians) accumulated from a scalar or per-sample frequency"""
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    return np.cumsum(f) / SR - f[0] / SR


def _blep(ph, dt):
    y = np.zeros_like(ph)
    m = ph < dt
    t = ph[m] / dt[m]
    y[m] = t + t - t * t - 1
    m2 = ph > 1 - dt
    t = (ph[m2] - 1) / dt[m2]
    y[m2] = t * t + t + t + 1
    return y


def saw(freq, n, phase0=0.0):
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    dt = np.clip(f / SR, 1e-6, 0.5)
    ph = (phase_acc(f, n) + phase0) % 1.0
    return 2 * ph - 1 - _blep(ph, dt)


def pulse(freq, n, width=0.5, phase0=0.0):
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    dt = np.clip(f / SR, 1e-6, 0.5)
    ph = (phase_acc(f, n) + phase0) % 1.0
    ph2 = (ph + (1 - width)) % 1.0
    y = (2 * ph - 1 - _blep(ph, dt)) - (2 * ph2 - 1 - _blep(ph2, dt))
    return y - np.mean(y)


def sine(freq, n, phase0=0.0):
    return np.sin(TWO_PI * (phase_acc(freq, n) + phase0))


def tri(freq, n, phase0=0.0):
    # integrated band-limited square
    sq = pulse(freq, n, 0.5, phase0)
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    y = np.cumsum(sq * 4 * f / SR)
    return dc_block(y, 5.0)


def vibrato(n, rate=5.5, depth_cents=15.0, delay=0.25, rng=None, onset=0.3):
    """returns a frequency multiplier array"""
    t = tvec(n)
    ramp = np.clip((t - delay) / max(onset, 1e-3), 0, 1)
    jitter = 0
    if rng is not None:
        jitter = smooth_rand(n, rng, 4.0, periodic=False) * 0.15
    cents = depth_cents * ramp * (np.sin(TWO_PI * rate * t) + jitter)
    return 2 ** (cents / 1200.0)


# --------------------------------------------------------------------------
# Karplus-Strong plucked string (vectorised in delay-length blocks)
# --------------------------------------------------------------------------
def ks_string(freq, dur, t60=2.0, damp=0.3, pick=0.18, exc_bright=0.7, rng=None,
              excitation=None, pickup=None, tri_mix=0.5):
    """Extended Karplus-Strong.
    damp: loop lowpass weight 0 (bright) .. 0.5 (dark)
    pick: pluck position (fraction of string) -> comb on excitation
    exc_bright: brightness of the noise burst (0..1)
    pickup: electric pickup position (fraction), adds comb at output
    """
    rng = rng if rng is not None else np.random.default_rng()
    n = ns(dur)
    P = SR / freq
    s = float(np.clip(damp, 0.02, 0.5))
    M = int(np.floor(P - s))
    fr = P - s - M
    if M < 3:
        M, fr = 3, 0.0
    w0 = (1 - s) * (1 - fr)
    w1 = (1 - s) * fr + s * (1 - fr)
    w2 = s * fr
    g = 0.001 ** (1.0 / (freq * max(t60, 0.01)))
    L = int(round(P))
    if excitation is None:
        e = rng.uniform(-1, 1, L)
        e -= e.mean()
        # brightness: one-pole lowpass of the burst
        fcb = 400 + exc_bright ** 2 * 12000
        e = onepole(np.concatenate([e, np.zeros(L)]), fcb)[:L] * (1 + (1 - exc_bright) * 1.5)
        if tri_mix > 0:
            # plucked-shape displacement (triangle with apex at pluck point): strong fundamental
            ap = max(1, int(round((pick or 0.2) * L)))
            tri = np.concatenate([np.linspace(0, 1, ap, endpoint=False), np.linspace(1, 0, L - ap)])
            tri = tri - tri.mean()
            e = (1 - tri_mix) * e + tri_mix * tri * 1.5
            e = e - e.mean()
    else:
        e = excitation
    if pick and excitation is None and tri_mix < 1:
        d = max(1, int(round(pick * P)))
        e2 = np.concatenate([e, np.zeros(d)])
        e2[d:] -= e
        e = e2
    pad = M + 3
    y = np.zeros(n + pad)
    x = np.zeros(n + pad)
    ne = min(len(e), n)
    x[pad:pad + ne] = e[:ne]
    i = pad
    end = n + pad
    while i < end:
        j = min(i + M, end)
        y[i:j] = x[i:j] + g * (w0 * y[i - M:j - M] + w1 * y[i - M - 1:j - M - 1] + w2 * y[i - M - 2:j - M - 2])
        i = j
    out = y[pad:]
    if pickup:
        d = max(1, int(round(pickup * P)))
        out = out - np.concatenate([np.zeros(d), out[:-d]])
    return out


# --------------------------------------------------------------------------
# instruments (each returns a mono numpy array)
# --------------------------------------------------------------------------
def guitar(midi, dur, vel=0.8, rng=None, bright=0.75, t60=None, pickup=0.12, pick=0.14,
           damp=0.22, rel=0.05, palm=False):
    """electric (twangy) guitar note. dur = sounding length (gate)."""
    f = mtof(midi)
    if t60 is None:
        t60 = 3.2 * (220.0 / f) ** 0.35
    if palm:
        t60 = 0.18
        damp = 0.45
        bright *= 0.6
    tail = rel + 0.02
    x = ks_string(f, dur + tail, t60=t60, damp=damp, pick=pick, exc_bright=bright * (0.6 + 0.4 * vel),
                  rng=rng, pickup=pickup)
    x = release_gate(x, dur, rel)
    return x * vel * 0.9


def guitar_tone(x, twang=4.0, body=1.0, cab_lp=5500.0, drive=1.4):
    """amp + cabinet voicing for a guitar bus (mono or stereo)"""
    y = highpass(x, 75.0, 2)
    y = peq(y, 2600.0, 1.0, twang)
    y = peq(y, 180.0, 0.8, body)
    y = np.tanh(drive * y) / np.tanh(drive)
    y = lowpass(y, cab_lp, 2)
    y = peq(y, 850, 1.2, -2.0)
    return y


def upright_bass(midi, dur, vel=0.8, rng=None, t60=1.4, rel=0.07):
    f = mtof(midi)
    x = ks_string(f, dur + rel + 0.05, t60=t60, damp=0.48, pick=0.22, exc_bright=0.35, rng=rng)
    n = len(x)
    t = tvec(n)
    # finger thump: low sine burst + soft noise
    thump = np.sin(TWO_PI * f * t) * np.exp(-t / 0.05) * 0.6
    rr = rng if rng is not None else np.random.default_rng()
    thump += lowpass(rr.standard_normal(n), 400) * np.exp(-t / 0.012) * 0.25
    y = x / (np.max(np.abs(x[:ns(0.1)])) + 1e-9) + thump
    y = lowpass(y, 1600, 2)
    y = peq(y, 90, 1.0, 3)
    y = release_gate(y, dur, rel)
    return y * vel * 0.8


def slap_bass(midi, dur, vel=0.8, rng=None):
    rr = rng if rng is not None else np.random.default_rng()
    y = upright_bass(midi, dur, vel, rr, t60=1.1)
    n = len(y)
    t = tvec(n)
    click = bandpass(rr.standard_normal(n), 1200, 5000) * np.exp(-t / 0.006) * 0.5
    y[:n] += click * vel
    return y


def slap_click(vel=0.8, rng=None):
    """the percussive string-against-fingerboard slap"""
    rr = rng if rng is not None else np.random.default_rng()
    n = ns(0.08)
    t = tvec(n)
    c = bandpass(rr.standard_normal(n), 900, 4500) * np.exp(-t / 0.009)
    c += np.sin(TWO_PI * 180 * t) * np.exp(-t / 0.015) * 0.6
    return c * vel * 0.6


def piano(midi, dur, vel=0.8, rng=None, rel=0.12, bright=1.0):
    """additive piano: inharmonic partials, per-partial two-stage decay, 3 detuned strings."""
    rr = rng if rng is not None else np.random.default_rng()
    f0 = mtof(midi)
    ring = min(dur + rel + 0.1, 6.0)
    sustain_time = 8.0 * (261.6 / f0) ** 0.6
    n = ns(ring)
    t = tvec(n)
    B = 0.00015 * (f0 / 261.6) ** 1.2 + 0.00005
    y = np.zeros(n)
    kmax = int(min(40, (0.42 * SR) / f0))
    tilt = 1.3 - 0.6 * vel * bright
    detunes = [-0.6, 0.0, 0.7] if midi > 45 else [-0.3, 0.3]
    for k in range(1, kmax + 1):
        fk = k * f0 * np.sqrt(1 + B * k * k)
        if fk > 0.45 * SR:
            break
        amp = (1.0 / k ** tilt) * (1 + 0.5 * np.sin(np.pi * k * 0.12))  # hammer strike position comb
        fast_t60 = sustain_time / (1 + 0.35 * k) * 0.25
        slow_t60 = sustain_time / (1 + 0.15 * k)
        env = 0.7 * env_exp(n, fast_t60) + 0.3 * env_exp(n, slow_t60)
        part = np.zeros(n)
        for dc in detunes:
            part += np.sin(TWO_PI * fk * 2 ** (dc / 1200) * t + rr.uniform(0, TWO_PI))
        y += amp * env * part / len(detunes)
    # hammer thunk
    ham = lowpass(rr.standard_normal(n), 1500 + 3000 * vel) * np.exp(-t / 0.006) * 0.08
    y = y / (kmax ** 0.1) + ham
    y *= np.minimum(1, t / 0.002)
    y = release_gate(y, dur, rel)
    return y * (0.25 + 0.75 * vel) * 0.5


def vibraphone(midi, dur, vel=0.8, rng=None, motor=5.0, motor_depth=0.35):
    rr = rng if rng is not None else np.random.default_rng()
    f0 = mtof(midi)
    ring = dur + 2.5
    n = ns(ring)
    t = tvec(n)
    y = np.sin(TWO_PI * f0 * t) * env_exp(n, 4.0)
    y += 0.30 * np.sin(TWO_PI * f0 * 3.99 * t) * env_exp(n, 0.9)
    y += 0.12 * np.sin(TWO_PI * f0 * 9.9 * t) * env_exp(n, 0.25)
    y += 0.05 * np.sin(TWO_PI * f0 * 2.0 * t) * env_exp(n, 1.2)
    y += bandpass(rr.standard_normal(n), f0 * 2, min(f0 * 12, 16000)) * np.exp(-t / 0.004) * 0.15
    trem = 1 - motor_depth * 0.5 * (1 - np.cos(TWO_PI * motor * t))
    y *= trem * np.minimum(1, t / 0.001)
    y = release_gate(y, dur + 1.0, 0.8)
    return y * vel * 0.6


def fm_bell(freq, dur, vel=0.8, ratio=1.4, index=3.0, t60=2.5):
    n = ns(dur)
    t = tvec(n)
    I = index * env_exp(n, t60 * 0.35)
    y = np.sin(TWO_PI * freq * t + I * np.sin(TWO_PI * freq * ratio * t))
    y *= env_exp(n, t60) * np.minimum(1, t / 0.0015)
    return y * vel


def brass(midi, dur, vel=0.8, rng=None, bright=1.0, rel=0.08, scoop=True, vib=0.0, detune_c=6.0,
          attack=0.03):
    """brassy saws through a filter envelope (cutoff tracks loudness)."""
    rr = rng if rng is not None else np.random.default_rng()
    f0 = mtof(midi)
    n = ns(dur + rel + 0.05)
    t = tvec(n)
    fm = np.ones(n)
    if scoop:
        fm *= 2 ** (-0.35 * np.exp(-t / 0.035) / 12.0)
    if vib:
        fm *= vibrato(n, 5.3, vib, delay=0.18, rng=rr)
    amp = env_adsr(n, attack, 0.18, 0.75, rel, gate=dur)
    y = 0.5 * saw(f0 * fm * 2 ** (detune_c / 2400), n, rr.uniform()) + \
        0.5 * saw(f0 * fm * 2 ** (-detune_c / 2400), n, rr.uniform())
    # filter envelope: blat at the attack, settles, follows amplitude
    fenv = env_adsr(n, attack * 0.8, 0.12, 0.55, rel, gate=dur)
    cutoff = f0 * (1.2 + bright * (2.0 + 6.0 * vel) * fenv) + 300 * fenv
    cutoff = np.minimum(cutoff, 14000)
    y = tv_filter(y, cutoff, q=1.2, kind="lowpass")
    y = tv_filter(y, cutoff * 1.1, q=0.8, kind="lowpass")
    breath = bandpass(rr.standard_normal(n), 1500, 6000) * amp * 0.015
    y = (y + breath) * amp
    return y * vel * 0.7


def lead_horn(midi, dur, vel=0.8, rng=None, rel=0.15, vib_cents=18.0, whistle=0.25):
    """lonely trumpet / whistle-ish lead: filtered saw + sine with delayed vibrato"""
    rr = rng if rng is not None else np.random.default_rng()
    f0 = mtof(midi)
    n = ns(dur + rel + 0.05)
    t = tvec(n)
    fm = vibrato(n, 5.2, vib_cents, delay=0.22, rng=rr, onset=0.35)
    fm *= 2 ** (-0.25 * np.exp(-t / 0.05) / 12.0)
    amp = env_adsr(n, 0.06, 0.3, 0.8, rel, gate=dur)
    s = saw(f0 * fm, n)
    cutoff = f0 * (1.5 + 3.5 * amp * vel) + 200
    s = tv_filter(s, cutoff, q=0.9)
    s = tv_filter(s, cutoff * 1.3, q=0.7)
    w = sine(f0 * fm, n)
    y = (1 - whistle) * s + whistle * w * 0.8
    y += bandpass(rr.standard_normal(n), 1800, 5000) * 0.012
    return y * amp * vel


def theremin(freqs_t, n, vib_rate=6.2, vib_cents=25.0, rng=None):
    """freqs_t: per-sample frequency curve (already glided)."""
    rr = rng if rng is not None else np.random.default_rng()
    fm = vibrato(n, vib_rate, vib_cents, delay=0.05, rng=rr, onset=0.4)
    ph = TWO_PI * phase_acc(freqs_t * fm, n)
    y = np.sin(ph) + 0.12 * np.sin(2 * ph) + 0.05 * np.sin(3 * ph)
    return y


def saw_pad(midi, dur, rng=None, detune=8.0, voices=3, cutoff=900.0, attack=0.8, rel=1.2):
    rr = rng if rng is not None else np.random.default_rng()
    f0 = mtof(midi)
    n = ns(dur + rel)
    y = np.zeros(n)
    for v in range(voices):
        dc = (v - (voices - 1) / 2) * detune
        y += saw(f0 * 2 ** (dc / 1200), n, rr.uniform())
    y = lowpass(y / voices, cutoff, 2)
    return y * env_adsr(n, attack, 0.5, 0.9, rel, gate=dur)


# --------------------------------------------------------------------------
# drums
# --------------------------------------------------------------------------
_METAL_RATIOS = np.array([1.0, 1.4829, 1.8009, 2.5468, 2.6308, 3.8987])  # 808-ish square ratios


def _metal_cluster(n, base, rng, partials=40, spread=(1.0, 14.0)):
    t = tvec(n)
    y = np.zeros(n)
    for r in _METAL_RATIOS:
        f = base * r
        for h in (1, 3, 5):
            if f * h < 0.45 * SR:
                y += np.sin(TWO_PI * f * h * t + rng.uniform(0, TWO_PI)) / h
    fr = base * rng.uniform(*spread, partials)
    for f in fr:
        if f < 0.45 * SR:
            y += 0.4 * np.sin(TWO_PI * f * t + rng.uniform(0, TWO_PI))
    return y


def kick(vel=0.9, rng=None, f_hi=140.0, f_lo=46.0, decay=0.42, click=0.4, sweep=0.045):
    rr = rng if rng is not None else np.random.default_rng()
    n = ns(decay * 1.8)
    t = tvec(n)
    f = f_lo + (f_hi - f_lo) * np.exp(-t / sweep)
    body = np.sin(TWO_PI * phase_acc(f, n)) * np.exp(-t / (decay * 0.45))
    body = np.tanh(1.5 * body)
    cl = lowpass(rr.standard_normal(n), 3500) * np.exp(-t / 0.004) * click
    y = body + cl
    y *= np.minimum(1, t / 0.0008)
    return y * vel


def snare(vel=0.9, rng=None, tone=185.0, decay=0.18, snappy=1.0):
    rr = rng if rng is not None else np.random.default_rng()
    n = ns(decay * 2.5)
    t = tvec(n)
    f = tone * (1 + 0.4 * np.exp(-t / 0.01))
    body = (np.sin(TWO_PI * phase_acc(f, n)) + 0.5 * np.sin(TWO_PI * phase_acc(f * 1.62, n))) * np.exp(-t / 0.045)
    nz = rr.standard_normal(n)
    nz = highpass(nz, 1100, 2)
    nz = peq(nz, 4500, 0.8, 4)
    nz = lowpass(nz, 11000, 2) * np.exp(-t / (decay * 0.5)) * snappy
    y = 0.55 * body + 0.8 * nz
    y *= np.minimum(1, t / 0.0005)
    return y * vel


def brush_tap(vel=0.7, rng=None):
    rr = rng if rng is not None else np.random.default_rng()
    n = ns(0.3)
    t = tvec(n)
    nz = bandpass(rr.standard_normal(n), 1500, 9000) * np.exp(-t / 0.07)
    body = np.sin(TWO_PI * 200 * t) * np.exp(-t / 0.03) * 0.25
    y = (nz + body) * np.minimum(1, t / 0.002)
    return y * vel * 0.8


def brush_swish(dur=0.35, vel=0.5, rng=None):
    rr = rng if rng is not None else np.random.default_rng()
    n = ns(dur)
    t = tvec(n)
    nz = bandpass(rr.standard_normal(n), 2500, 10000)
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.5
    # slight sweep of the brush across the head
    nz = tv_filter(nz, 3000 + 3000 * t / dur, q=0.6, kind="highpass")
    return nz * env * vel * 0.35


def hihat(vel=0.6, rng=None, open_=False, decay=None):
    rr = rng if rng is not None else np.random.default_rng()
    d = decay if decay is not None else (0.35 if open_ else 0.045)
    n = ns(d * 3 + 0.02)
    t = tvec(n)
    m = _metal_cluster(n, 330.0, rr, partials=20, spread=(4, 30))
    y = 0.6 * m / 6 + rr.standard_normal(n)
    y = highpass(y, 7000, 3)
    y = peq(y, 10000, 1.0, 3)
    y *= np.exp(-t / d) * np.minimum(1, t / 0.0005)
    return y * vel * 0.5


def ride(vel=0.6, rng=None, decay=1.4, bell=0.25):
    rr = rng if rng is not None else np.random.default_rng()
    n = ns(decay * 1.5)
    t = tvec(n)
    m = _metal_cluster(n, 420.0, rr, partials=60, spread=(1.5, 24))
    m = highpass(m / 10, 2500, 2)
    stick = highpass(rr.standard_normal(n), 5000) * np.exp(-t / 0.008) * 0.6
    bl = (np.sin(TWO_PI * 2380 * t) + 0.5 * np.sin(TWO_PI * 3570 * t)) * np.exp(-t / 0.5) * bell
    y = m * np.exp(-t / (decay * 0.4)) + stick + bl * 0.4
    y *= np.minimum(1, t / 0.0005)
    return y * vel * 0.4


def crash(vel=0.8, rng=None, decay=2.5):
    rr = rng if rng is not None else np.random.default_rng()
    n = ns(decay * 1.6)
    t = tvec(n)
    m = _metal_cluster(n, 350.0, rr, partials=90, spread=(1.0, 36))
    nz = rr.standard_normal(n)
    y = highpass(m / 12 + 0.8 * nz, 1800, 2)
    y = lowpass(y, 14000, 2)
    env = np.exp(-t / (decay * 0.3)) * np.minimum(1, t / 0.002)
    y *= env
    return y * vel * 0.45


def tom(freq=100.0, vel=0.85, rng=None, decay=0.5):
    rr = rng if rng is not None else np.random.default_rng()
    n = ns(decay * 1.6)
    t = tvec(n)
    f = freq * (1 + 0.55 * np.exp(-t / 0.03))
    body = np.sin(TWO_PI * phase_acc(f, n)) + 0.25 * np.sin(TWO_PI * phase_acc(f * 1.5, n)) * np.exp(-t / 0.08)
    body *= np.exp(-t / (decay * 0.4))
    head = lowpass(rr.standard_normal(n), 3000) * np.exp(-t / 0.02) * 0.35
    y = np.tanh(1.3 * (body + head)) * np.minimum(1, t / 0.0008)
    return y * vel


def timpani(freq=82.0, vel=0.9, rng=None, decay=2.2):
    rr = rng if rng is not None else np.random.default_rng()
    n = ns(decay * 1.5)
    t = tvec(n)
    y = np.zeros(n)
    for r, a, d in ((1.0, 1.0, 1.0), (1.504, 0.5, 0.7), (1.742, 0.35, 0.5), (2.0, 0.25, 0.4), (2.245, 0.15, 0.3)):
        y += a * np.sin(TWO_PI * freq * r * t * (1 + 0.01 * np.exp(-t / 0.05))) * np.exp(-t / (decay * 0.35 * d))
    y += lowpass(rr.standard_normal(n), 900) * np.exp(-t / 0.03) * 0.3
    return y * np.minimum(1, t / 0.001) * vel * 0.6


def woodblock(freq=1800.0, vel=0.6, rng=None):
    rr = rng if rng is not None else np.random.default_rng()
    n = ns(0.12)
    t = tvec(n)
    y = np.sin(TWO_PI * freq * t) * np.exp(-t / 0.018) + 0.4 * np.sin(TWO_PI * freq * 2.7 * t) * np.exp(-t / 0.006)
    y += bandpass(rr.standard_normal(n), freq, freq * 3) * np.exp(-t / 0.002) * 0.4
    return y * vel


def heartbeat(vel=0.8, rng=None):
    """lub-dub: two soft low thumps"""
    n = ns(0.7)
    out = np.zeros(n)
    k1 = kick(vel, rng, f_hi=75, f_lo=42, decay=0.28, click=0.02, sweep=0.03)
    k2 = kick(vel * 0.7, rng, f_hi=85, f_lo=48, decay=0.22, click=0.02, sweep=0.03)
    mix_into(out, k1, 0)
    mix_into(out, k2, ns(0.2))
    return lowpass(out, 400, 2)


# --------------------------------------------------------------------------
# effects
# --------------------------------------------------------------------------
def pan_mono(x, p=0.0):
    """constant-power pan, p in [-1, 1] -> (2, n)"""
    a = (p + 1) * np.pi / 4
    return np.vstack([x * np.cos(a), x * np.sin(a)])


def to_stereo(x):
    return x if x.ndim == 2 else np.vstack([x, x])


def tremolo(x, rate, depth=0.5, t0=0.0, shape=0.6):
    """amplitude tremolo. t0 = absolute start time so it can be tempo-synced across a song."""
    n = x.shape[-1]
    t = tvec(n) + t0
    lfo = 0.5 * (1 + np.sin(TWO_PI * rate * t))
    lfo = lfo ** (1 + shape)  # a bit more "choppy", like a valve tremolo
    g = 1 - depth + depth * lfo
    return x * g


def slapback(x, delay=0.12, fb=0.18, mix=0.5, lp=3500.0):
    d = ns(delay)
    n = x.shape[-1]
    out = x.copy()
    tap = x
    g = mix
    for _ in range(6):
        tap = lowpass(np.concatenate([np.zeros(x.shape[:-1] + (d,)), tap[..., :n - d]], axis=-1), lp, 1)
        out = out + g * tap
        g *= fb
        if g < 0.005:
            break
    return out


def hall_ir(rt60=2.2, length=None, predelay=0.018, seed=7, hf_damp=0.45, lf_mult=1.15, width=1.0,
            early=True):
    rr = np.random.default_rng(seed)
    length = length or rt60 * 1.15
    n = ns(length)
    t = tvec(n)
    bands = [(None, 250, rt60 * lf_mult), (250, 1200, rt60), (1200, 5000, rt60 * (1 - hf_damp * 0.5)),
             (5000, None, rt60 * (1 - hf_damp))]
    chans = []
    for ch in range(2):
        y = np.zeros(n)
        for lo, hi, rt in bands:
            nz = rr.standard_normal(n)
            if lo and hi:
                nz = bandpass(nz, lo, hi, 2)
            elif lo:
                nz = highpass(nz, lo, 2)
            else:
                nz = lowpass(nz, hi, 2)
            y += nz * 10 ** (-3 * t / rt)
        y *= np.minimum(1, t / 0.012)  # soft onset of the diffuse tail
        if early:
            for _ in range(10):
                pos = ns(rr.uniform(0.004, 0.06))
                y[pos] += rr.uniform(-1, 1) * 4.0 * (1 - pos / ns(0.07))
        chans.append(y)
    L, R = chans
    mid = (L + R) / 2
    side = (L - R) / 2 * width
    ir = np.vstack([mid + side, mid - side])
    ir = np.concatenate([np.zeros((2, ns(predelay))), ir], axis=1)
    ir /= np.sqrt(np.sum(ir ** 2) / 2)
    return ir


def spring_ir(length=2.2, seed=3, decay=1.8):
    """Synthetic spring-reverb IR: repeated dispersive chirps ('drip') + a diffuse tail."""
    rr = np.random.default_rng(seed)
    n = ns(length)
    t = tvec(n)
    # dispersion: cascade of first-order allpasses applied to an impulse
    imp = np.zeros(ns(0.08))
    imp[0] = 1.0
    ap_a = 0.72
    chirp = imp
    for _ in range(90):
        chirp = signal.lfilter([ap_a, 1.0], [1.0, ap_a], chirp)
    chirp = bandpass(chirp, 180, 4500)
    chirp /= np.max(np.abs(chirp)) + 1e-12
    chans = []
    for ch in range(2):
        y = np.zeros(n)
        T = 0.0335 + 0.003 * ch
        k = 0
        pos = ns(0.012 + 0.002 * ch)
        c = chirp.copy()
        while pos < n - len(c):
            y[pos:pos + len(c)] += c * (0.72 ** k) * (1 if k % 2 == 0 else -0.9)
            # each round-trip disperses a bit more
            for _ in range(8):
                c = signal.lfilter([ap_a, 1.0], [1.0, ap_a], c)
            k += 1
            pos += ns(T * (1 + rr.uniform(-0.02, 0.02)))
            if k > 25:
                break
        tail = bandpass(rr.standard_normal(n), 300, 4000) * 10 ** (-3 * t / decay) * 0.25
        tail *= np.minimum(1, t / 0.03)
        chans.append(y + tail)
    ir = np.vstack(chans)
    ir /= np.sqrt(np.sum(ir ** 2) / 2)
    return ir


def reverb(x, ir, mix=1.0):
    """convolve mono or stereo x with a stereo IR -> stereo wet signal, same length as x."""
    n = x.shape[-1]
    mono = x if x.ndim == 1 else 0.5 * (x[0] + x[1])
    wetL = signal.oaconvolve(mono, ir[0])[:n]
    wetR = signal.oaconvolve(mono, ir[1])[:n]
    return np.vstack([wetL, wetR]) * mix


def tape(x, drive=1.3, lp=15000.0):
    y = np.tanh(drive * x) / np.tanh(drive)
    y = y + 0.02 * y ** 2  # a touch of even-order warmth
    y = dc_block(y, 18.0)
    return lowpass(y, lp, 1)


# --------------------------------------------------------------------------
# loudness + limiting
# --------------------------------------------------------------------------
def _kweight(x):
    # BS.1770 K-weighting: high shelf then RLB high-pass (coeffs derived for any fs)
    G, Q, fc = 3.999843853973347, 0.7071752369554196, 1681.974450955533
    A = 10 ** (G / 40)
    w0 = TWO_PI * fc / SR
    alpha = np.sin(w0) / (2 * Q)
    cw = np.cos(w0)
    b = [A * ((A + 1) + (A - 1) * cw + 2 * np.sqrt(A) * alpha), -2 * A * ((A - 1) + (A + 1) * cw),
         A * ((A + 1) + (A - 1) * cw - 2 * np.sqrt(A) * alpha)]
    a = [(A + 1) - (A - 1) * cw + 2 * np.sqrt(A) * alpha, 2 * ((A - 1) - (A + 1) * cw),
         (A + 1) - (A - 1) * cw - 2 * np.sqrt(A) * alpha]
    y = signal.lfilter(np.array(b) / a[0], np.array(a) / a[0], x, axis=-1)
    Q2, fc2 = 0.5003270373238773, 38.13547087602444
    w0 = TWO_PI * fc2 / SR
    alpha = np.sin(w0) / (2 * Q2)
    cw = np.cos(w0)
    b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
    a = [1 + alpha, -2 * cw, 1 - alpha]
    return signal.lfilter(np.array(b) / a[0], np.array(a) / a[0], y, axis=-1)


def lufs(x):
    x2 = np.atleast_2d(x)
    y = _kweight(x2)
    blk, hop = ns(0.4), ns(0.1)
    n = y.shape[-1]
    if n < blk:
        ms = np.mean(y ** 2, axis=-1)
        return -0.691 + 10 * np.log10(np.sum(ms) + 1e-12)
    starts = np.arange(0, n - blk + 1, hop)
    c = np.cumsum(np.concatenate([np.zeros((y.shape[0], 1)), y ** 2], axis=1), axis=1)
    ms = (c[:, starts + blk] - c[:, starts]) / blk
    z = np.sum(ms, axis=0)
    l = -0.691 + 10 * np.log10(z + 1e-12)
    z1 = z[l > -70]
    if len(z1) == 0:
        return -100.0
    rel = -0.691 + 10 * np.log10(np.mean(z1)) - 10
    z2 = z[(l > -70) & (l > rel)]
    return -0.691 + 10 * np.log10(np.mean(z2) + 1e-12)


def limiter(x, ceiling_db=-1.0, lookahead=0.004, hold=0.04, circular=False):
    x2 = np.atleast_2d(x)
    c = db(ceiling_db)
    pk = np.max(np.abs(x2), axis=0)
    g = np.minimum(1.0, c / np.maximum(pk, 1e-12))
    la, hd = ns(lookahead), ns(hold)
    pad = la + hd + 8
    mode = "wrap" if circular else "edge"
    gp = np.pad(g, pad, mode=mode)
    # min over [p - hold, p + lookahead]
    size = la + hd + 1
    origin = (hd - la) // 2
    gm = minimum_filter1d(gp, size=size, origin=origin, mode="nearest")
    gm = uniform_filter1d(gm, size=max(la, 1), mode="nearest")
    gm = uniform_filter1d(gm, size=max(la, 1), mode="nearest")
    gm = gm[pad:pad + len(g)]
    y = x2 * gm
    # final safety (tiny residual overs)
    y = np.clip(y, -c, c)
    return y if x.ndim == 2 else y[0]


def master_music(x, target_lufs=-14.0, ceiling_db=-1.0, loop=False):
    """loudness-normalise then limit; two passes so the result lands near target."""
    y = x.copy()
    for it in range(3):
        L = lufs(y)
        y = y * db(target_lufs - L)
        if it == 0:
            pk = 20 * np.log10(np.max(np.abs(y)) + 1e-12)
            print(f"    master: peak before limiting {pk:+.1f} dBFS (gain reduction ~{max(0, pk - ceiling_db):.1f} dB)")
        y = limiter(y, ceiling_db - 0.3, circular=loop)
    return y


def peak_normalize(x, peak_db=-1.0):
    return x * (db(peak_db) / (np.max(np.abs(x)) + 1e-12))


# --------------------------------------------------------------------------
# loops
# --------------------------------------------------------------------------
def loop_xfade(x, L, X):
    """x has >= L+X samples. Equal-power crossfade of x[L:L+X] into x[0:X] -> length L loop."""
    out = x[..., :L].copy()
    th = np.linspace(0, np.pi / 2, X)
    fin, fout = np.sin(th), np.cos(th)
    out[..., :X] = x[..., :X] * fin + x[..., L:L + X] * fout
    return out


def wrap_tail(x, L):
    """fold everything after sample L back onto the start (for event-based loops)."""
    out = x[..., :L].copy()
    k = L
    while k < x.shape[-1]:
        seg = x[..., k:k + L]
        out[..., :seg.shape[-1]] += seg
        k += L
    return out


# --------------------------------------------------------------------------
# song timeline
# --------------------------------------------------------------------------
class Song:
    """Simple multi-bus timeline. Events are added in seconds; buses are stereo."""

    def __init__(self, length_s: float, tail_s: float = 6.0, bpm: float = 120.0, swing: float = 0.5,
                 seed: int = 1, loop: bool = True):
        self.loop = loop
        self.L = ns(length_s)
        self.N = self.L + ns(tail_s)
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.swing = swing  # position of the off-beat 8th inside a beat (0.5 straight, 0.667 triplet)
        self.buses: dict[str, np.ndarray] = {}
        self.rng = np.random.default_rng(seed)

    def bus(self, name):
        if name not in self.buses:
            self.buses[name] = np.zeros((2, self.N))
        return self.buses[name]

    def t(self, bar, beat=0.0, beats_per_bar=4):
        """musical position -> seconds. Off-beat 8ths (x.5) are pushed by the swing ratio;
        other fractions (triplets, 16ths) are left straight."""
        whole = np.floor(beat + 1e-9)
        frac = beat - whole
        if abs(frac - 0.5) < 1e-6:
            frac = self.swing
        return (bar * beats_per_bar + whole + frac) * self.beat

    def hum(self, amt=0.006):
        return float(self.rng.normal(0, amt))

    def add(self, bus, sig, t, pan=0.0, gain=1.0):
        if t < 0:  # humanised events that land just before bar 0 belong at the end of the loop
            t = t + self.L / SR if self.loop else 0.0
        b = self.bus(bus)
        st = sig if sig.ndim == 2 else pan_mono(sig, pan)
        mix_into(b, st, ns(t), gain)

    def get(self, name):
        return self.buses.get(name, np.zeros((2, self.N)))


# --------------------------------------------------------------------------
# chords
# --------------------------------------------------------------------------
CHORDS = {
    "maj": [0, 4, 7], "min": [0, 3, 7], "7": [0, 4, 7, 10], "m7": [0, 3, 7, 10], "maj7": [0, 4, 7, 11],
    "6": [0, 4, 7, 9], "m6": [0, 3, 7, 9], "9": [0, 4, 7, 10, 14], "dim": [0, 3, 6], "5": [0, 7, 12],
    "sus4": [0, 5, 7], "madd9": [0, 3, 7, 14], "7b9": [0, 4, 7, 10, 13], "m9": [0, 3, 7, 10, 14],
    "add9": [0, 4, 7, 14], "7#9": [0, 4, 7, 10, 15],
}


def chord(root, quality="maj", inversion=0):
    notes = [root + i for i in CHORDS[quality]]
    for _ in range(inversion):
        notes = notes[1:] + [notes[0] + 12]
    return notes


def guitar_voicing(name):
    """a few open-position guitar voicings (low -> high MIDI numbers)"""
    V = {
        "Em": [40, 47, 52, 55, 59, 64], "E": [40, 47, 52, 56, 59, 64], "E7": [40, 47, 50, 56, 59, 64],
        "Am": [45, 52, 57, 60, 64], "A": [45, 52, 57, 61, 64], "A7": [45, 52, 55, 61, 64],
        "C": [48, 52, 55, 60, 64], "Cmaj7": [48, 52, 55, 59, 64], "D": [50, 57, 62, 66], "D7": [50, 57, 60, 66],
        "G": [43, 47, 50, 55, 59, 67], "B7": [47, 51, 57, 59, 66], "Bm": [47, 54, 59, 62, 66],
        "Em9": [40, 47, 52, 55, 59, 66], "Am6": [45, 52, 57, 60, 66], "B7b9": [47, 51, 57, 60, 66],
        "F": [41, 48, 53, 57, 60, 65], "Cadd9": [48, 52, 55, 62, 64], "Dm": [50, 57, 62, 65],
    }
    return V[name]


# --------------------------------------------------------------------------
# I/O
# --------------------------------------------------------------------------
def _encoder_args():
    try:
        out = subprocess.run(["ffmpeg", "-hide_banner", "-encoders"], capture_output=True, text=True).stdout
    except FileNotFoundError:
        raise RuntimeError("ffmpeg not found")
    if "libvorbis" in out:
        return ["-c:a", "libvorbis", "-q:a", "5"]
    return ["-c:a", "vorbis", "-strict", "-2", "-q:a", "5"]


_ENC = None


def _decoded_peak(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-"], capture_output=True).stdout
    d = np.frombuffer(raw, np.float32)
    return float(np.max(np.abs(d))) if len(d) else 0.0


def write_ogg(path, x, max_decoded_peak_db=-0.5):
    """x: mono (n,) or stereo (2, n) float in [-1, 1].
    Lossy encoding can overshoot the source peak (esp. on noisy / buzzy material), so the file is
    decoded again and, if needed, re-encoded slightly quieter so the decoded peak stays under the limit."""
    global _ENC
    if _ENC is None:
        _ENC = _encoder_args()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = x.T if x.ndim == 2 else x
    data = np.clip(data, -1, 1).astype(np.float32)
    lim = db(max_decoded_peak_db)
    for _ in range(4):
        fd, tmp = tempfile.mkstemp(suffix=".wav")
        os.close(fd)
        try:
            wavfile.write(tmp, SR, data)
            cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", tmp, "-ar", str(SR)] + _ENC + [path]
            subprocess.run(cmd, check=True)
        finally:
            os.remove(tmp)
        pk = _decoded_peak(path)
        if pk <= lim:
            break
        data = (data * (lim / pk) * 0.995).astype(np.float32)


def write_wav(path, x):
    data = x.T if x.ndim == 2 else x
    wavfile.write(path, SR, np.clip(data, -1, 1).astype(np.float32))


def have_ffmpeg():
    return shutil.which("ffmpeg") is not None


# --------------------------------------------------------------------------
# caches (drum hits / piano notes are re-used with random round-robin variants)
# --------------------------------------------------------------------------
class DrumKit:
    """Pre-renders a few round-robin variants of each drum voice (much faster)."""

    def __init__(self, seed=11, variants=4, **overrides):
        self.rng = np.random.default_rng(seed)
        self.variants = variants
        self.cache = {}
        self.overrides = overrides

    def _render(self, name, rr):
        o = self.overrides.get(name, {})
        if name == "kick":
            return kick(1.0, rr, **o)
        if name == "snare":
            return snare(1.0, rr, **o)
        if name == "rim":
            return snare(1.0, rr, tone=330, decay=0.06, snappy=0.4)
        if name == "brush":
            return brush_tap(1.0, rr)
        if name == "swish":
            return brush_swish(o.get("dur", 0.32), 1.0, rr)
        if name == "hat":
            return hihat(1.0, rr)
        if name == "ohat":
            return hihat(1.0, rr, open_=True)
        if name == "pedal":
            return hihat(1.0, rr, decay=0.03) * 0.6
        if name == "ride":
            return ride(1.0, rr, **o)
        if name == "crash":
            return crash(1.0, rr, **o)
        if name.startswith("tom"):
            return tom(float(name[3:]), 1.0, rr, decay=0.55 if float(name[3:]) < 110 else 0.4)
        if name.startswith("timp"):
            return timpani(float(name[4:]), 1.0, rr)
        if name == "heart":
            return heartbeat(1.0, rr)
        if name == "tick":
            return woodblock(2600, 1.0, rr) * 0.5
        if name == "tock":
            return woodblock(1900, 1.0, rr) * 0.5
        raise KeyError(name)

    def hit(self, name, vel=0.8):
        if name not in self.cache:
            vs = [self._render(name, np.random.default_rng(self.rng.integers(1 << 30))) for _ in range(self.variants)]
            # gentle tail fade so no voice is ever truncated with a click
            self.cache[name] = [fade(v, 0.0, min(0.25 * len(v) / SR, 0.3)) for v in vs]
        v = self.cache[name][self.rng.integers(self.variants)]
        # soft hits are a little darker
        if vel < 0.5 and name not in ("kick", "heart"):
            v = onepole(v, 2500 + 16000 * vel)
        return v * vel


_PIANO_CACHE: dict = {}


def piano_c(midi, dur, vel=0.8, rng=None, variant=None):
    """cached piano note (quantised duration / velocity)."""
    rr = rng if rng is not None else np.random.default_rng()
    d = round(max(dur, 0.05) / 0.05) * 0.05
    v = round(vel * 10) / 10
    k = (int(midi), d, v, int(rr.integers(3)) if variant is None else variant)
    if k not in _PIANO_CACHE:
        _PIANO_CACHE[k] = piano(midi, d, v, np.random.default_rng(hash(k) & 0xFFFFFF))
    return _PIANO_CACHE[k]


def close_voicing(root_pc_midi, intervals, low=58):
    """stack chord tones (intervals over root) in the octave starting at `low`."""
    out = []
    for iv in intervals:
        p = root_pc_midi + iv
        while p < low:
            p += 12
        while p >= low + 12:
            p -= 12
        out.append(p)
    return sorted(out)


# --------------------------------------------------------------------------
# cinematic helpers
# --------------------------------------------------------------------------
def boom(dur=3.0, rng=None, f_hi=90.0, f_lo=28.0, sub=1.0):
    """big low impact (sub drop + noise burst)"""
    rr = rng if rng is not None else np.random.default_rng()
    n = ns(dur)
    t = tvec(n)
    f = f_lo + (f_hi - f_lo) * np.exp(-t / 0.12)
    s = np.sin(TWO_PI * phase_acc(f, n)) * np.exp(-t / (dur * 0.3)) * sub
    nz = brown(n, rr) * np.exp(-t / 0.25)
    nz = lowpass(nz, 600, 2)
    cr = highpass(rr.standard_normal(n), 800) * np.exp(-t / 0.02) * 0.4
    y = np.tanh(1.6 * (s + 0.6 * nz + cr))
    return fade(y * np.minimum(1, t / 0.001), 0.0, dur * 0.3)


def riser(dur=2.0, rng=None, f0=200.0, f1=4000.0):
    """reverse-cymbal style noise swell with a rising filter + rising tone"""
    rr = rng if rng is not None else np.random.default_rng()
    n = ns(dur)
    t = tvec(n)
    x = t / dur
    nz = rr.standard_normal(n)
    fc = f0 * (f1 / f0) ** x
    y = tv_filter(nz, fc, q=2.0, kind="bandpass")
    y = y * x ** 2.5
    tone = saw(80 * 2 ** (x * 3), n)
    tone = tv_filter(tone, 300 + 3000 * x ** 2, q=1.0)
    return (y * 1.2 + 0.25 * tone * x ** 3)


def circ_apply(fn, x, pre=1.0):
    """run a (stateful IIR) process on a loop so its start is already in steady state:
    prepend the loop's own ending, process, drop the pre-roll."""
    p = min(ns(pre), x.shape[-1])
    y = fn(np.concatenate([x[..., -p:], x], axis=-1))
    return y[..., p:]
