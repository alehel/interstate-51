#!/usr/bin/env python3
"""Generate every voiced line of INTERSTATE '51 from data/dialogue.json.

Uses the Piper neural TTS engine (pip install piper-tts) with the voice models
from the rhasspy/piper v0.0.2 GitHub release, extracted into $PIPER_VOICES
(default /opt/piper).  Each character gets a fixed voice + delivery settings,
then the audio is post-processed (CB radio band-pass, PA-system echo, ...)
and encoded to OGG Vorbis in assets/voice/<line_id>.ogg.

    python3 tools/voice/make_voices.py            # only missing lines
    python3 tools/voice/make_voices.py --force    # regenerate everything
    python3 tools/voice/make_voices.py m1_rosa_01 # specific ids
"""
import json
import zlib
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np
from scipy import signal

from piper import PiperVoice
from piper.config import SynthesisConfig

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
VOICES = os.environ.get("PIPER_VOICES", "/opt/piper")
OUT = os.path.join(ROOT, "assets", "voice")

# model file, speaker id, length_scale (slower > 1), noise, fx chain
CAST = {
    "DEACON":   ("en-us-libritts-high", 385, 1.06, 0.62, "car"),
    "ROSA":     ("en-us-libritts-high", 119, 0.98, 0.667, "radio"),
    "PREACHER": ("en-us-libritts-high", 805, 1.14, 0.70, "radio"),
    "MIRIAM":   ("en-gb-southern_english_female-low", None, 0.96, 0.667, "radio"),
    "VALE":     ("en-us-libritts-high", 105, 1.12, 0.55, "radio_clean"),
    "HARLAN":   ("en-us-libritts-high", 595, 1.06, 0.70, "radio"),
    "HOLLIS":   ("en-us-libritts-high", 350, 0.97, 0.70, "radio"),
    "HAL":      ("en-us-libritts-high", 518, 1.06, 0.70, "radio"),
    "RUSK":     ("en-us-libritts-high", 427, 1.02, 0.55, "radio"),
    "CONTROL":  ("en-us-libritts-high", 42, 1.12, 0.45, "pa"),
    "LEGION1":  ("en-us-libritts-high", 217, 0.90, 0.80, "radio_hot"),
    "LEGION2":  ("en-us-libritts-high", 868, 0.88, 0.80, "radio_hot"),
    "LEGION3":  ("en-us-libritts-high", 7, 0.90, 0.80, "radio_hot"),
    "DEPUTY":   ("en-us-libritts-high", 392, 0.94, 0.70, "radio_hot"),
}

_models = {}


def model(name):
    if name not in _models:
        _models[name] = PiperVoice.load(os.path.join(VOICES, name + ".onnx"))
    return _models[name]


def synth(speaker, text):
    mname, spk, length, noise, _ = CAST[speaker]
    v = model(mname)
    cfg = SynthesisConfig(speaker_id=spk, length_scale=length, noise_scale=noise)
    chunks = list(v.synthesize(text, cfg))
    audio = np.concatenate([c.audio_float_array for c in chunks]).astype(np.float64)
    return audio, v.config.sample_rate


def resample(x, sr, target=22050):
    if sr == target:
        return x
    g = np.gcd(sr, target)
    return signal.resample_poly(x, target // g, sr // g)


def bandpass(x, sr, lo, hi, order=4):
    sos = signal.butter(order, [lo, hi], btype="band", fs=sr, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x, sr, hi, order=2):
    sos = signal.butter(order, hi, btype="low", fs=sr, output="sos")
    return signal.sosfilt(sos, x)


def normalize(x, peak=0.89):
    m = np.max(np.abs(x)) or 1.0
    return x * (peak / m)


def compress(x, amount=2.5):
    return np.tanh(x * amount) / np.tanh(amount)


def fx(x, sr, chain, rng):
    x = normalize(x, 0.9)
    if chain == "car":
        # close mic inside the car: slight low-mid warmth, gentle top roll-off
        x = lowpass(x, sr, 7000)
        x = normalize(compress(x, 1.4), 0.85)
    elif chain in ("radio", "radio_hot", "radio_clean"):
        lo, hi = (300, 3400) if chain != "radio_clean" else (220, 4200)
        x = bandpass(x, sr, lo, hi)
        drive = {"radio": 3.0, "radio_hot": 5.0, "radio_clean": 1.8}[chain]
        x = compress(normalize(x, 1.0), drive)
        hiss = rng.normal(0, 1, len(x))
        hiss = bandpass(hiss, sr, 1500, 6000, 2) * (0.018 if chain != "radio_clean" else 0.01)
        # slow AM wobble, like a CB signal drifting
        t = np.arange(len(x)) / sr
        wob = 1.0 - 0.06 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.7 * t + rng.uniform(0, 6)))
        x = x * wob + hiss
        x = normalize(x, 0.85)
    elif chain == "pa":
        x = bandpass(x, sr, 450, 2600)
        x = compress(normalize(x, 1.0), 4.0)
        out = np.zeros(len(x) + int(sr * 1.4))
        out[: len(x)] += x
        for delay, gain in ((0.19, 0.45), (0.41, 0.28), (0.73, 0.15), (1.1, 0.08)):
            d = int(sr * delay)
            out[d: d + len(x)] += lowpass(x, sr, 1800) * gain
        x = normalize(out, 0.85)
    # tiny fades to avoid clicks
    f = int(sr * 0.01)
    x[:f] *= np.linspace(0, 1, f)
    x[-f:] *= np.linspace(1, 0, f)
    # short pad of silence at the end
    return np.concatenate([np.zeros(int(sr * 0.05)), x, np.zeros(int(sr * 0.12))])


def write_ogg(x, sr, path):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp_path = tmp.name
    with wave.open(tmp_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp_path,
                    "-c:a", "libvorbis", "-q:a", "4", path], check=True)
    os.unlink(tmp_path)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    force = "--force" in sys.argv
    with open(os.path.join(ROOT, "data", "dialogue.json")) as f:
        data = json.load(f)
    os.makedirs(OUT, exist_ok=True)
    ids = args or list(data["lines"].keys())
    for i, lid in enumerate(ids):
        line = data["lines"][lid]
        path = os.path.join(OUT, lid + ".ogg")
        if os.path.exists(path) and not force and not args:
            continue
        speaker = line["s"]
        chain = CAST[speaker][4]
        # briefing narration and the epilogue are clean voice-over
        if lid.startswith("b") and lid[1].isdigit() or lid.startswith("epi_"):
            chain = "car"
        rng = np.random.default_rng(zlib.crc32(lid.encode()))
        audio, sr = synth(speaker, line["t"])
        audio = resample(audio, sr, 22050)
        audio = fx(audio, 22050, chain, rng)
        write_ogg(audio, 22050, path)
        print("[%d/%d] %s (%s, %.1fs)" % (i + 1, len(ids), lid, speaker, len(audio) / 22050))


if __name__ == "__main__":
    main()
