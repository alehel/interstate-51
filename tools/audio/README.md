# INTERSTATE '51 procedural audio

All music and sound effects in `assets/audio/` are synthesized from scratch by
the Python scripts in this folder. No samples or recordings are used.

## Regenerating

Requirements: Python 3.9+, numpy, scipy, and `ffmpeg` on the PATH (with
`libvorbis`, or the built-in `vorbis` encoder as a fallback).

```sh
python3 tools/audio/make_sfx.py            # all SFX   -> assets/audio/sfx/*.ogg   (~10 s)
python3 tools/audio/make_music.py          # all music -> assets/audio/music/*.ogg (~5 min)
python3 tools/audio/make_music.py trailer  # one cue: menu boogie rockabilly tension finale victory defeat trailer
python3 tools/audio/make_sfx.py engine_loop horn   # individual effects by name
python3 tools/audio/verify.py              # durations, peaks, loop-seam check
```

Output is deterministic because every random generator is seeded.

## Files

| file | purpose |
|---|---|
| `synth_lib.py` | DSP toolkit: band-limited oscillators (PolyBLEP), RBJ biquads and time-varying filters, Karplus-Strong strings, additive piano, vibraphone, brass (saws through a filter envelope), theremin, a noise-based drum kit, synthetic hall and spring reverb IRs, tremolo, slapback, tape saturation, BS.1770 loudness, look-ahead limiter, loop helpers, `Song` timeline |
| `make_music.py` | compositions (note lists) and mixes for the 8 cues. `MAIN_MOTIF` is the game's 8-bar theme |
| `make_sfx.py` | the 36 sound effects |
| `verify.py` | decodes every file and checks duration, clipping and loop seams |

## Music

Stereo, 44.1 kHz, OGG Vorbis q5. Loops are normalised to about -14 LUFS
integrated (`tension_night` is -16 LUFS on purpose), and the true decoded peak
stays at or below -0.5 dBFS.

| cue | tempo / key | length | loop |
|---|---|---|---|
| `menu_theme` | 84 BPM, E minor | 74.29 s (26 bars) | yes |
| `drive_boogie` | 150 BPM swing, 12-bar blues in A | 96.00 s (5 choruses) | yes |
| `drive_rockabilly` | 170 BPM, 12-bar in E | 84.71 s (5 choruses) | yes |
| `tension_night` | 70 BPM, E minor | 82.29 s (24 bars) | yes |
| `finale` | 160 BPM, E minor | 96.00 s (64 bars) | yes |
| `victory` | E major sting (C to D to E) | 7.0 s | no |
| `defeat` | E minor lament sting | 6.0 s | no |
| `trailer_theme` | free, then 144 BPM | 90.0 s exactly | no |

Loops are rendered on a timeline that runs past the loop end. Everything that
rings over the end (notes and reverb tails) is folded back onto the start, so the
files play seamlessly on repeat. Tremolo rates and LFOs are tempo-synced so they
also complete whole cycles. In Godot, enable `loop` in each loop's import
settings. The loop point is the file start, so no offset is needed.

### The main motif

It is 8 bars in E minor over `Em | Am | D | Em | Em | C | Am B7 | Em`. The
first phrase climbs an E-minor arpeggio (E G B), then answers by falling. The
second phrase climbs to C5 and resolves through the D# leading tone. It is
played by the baritone guitar and then the whistle-trumpet in `menu_theme`, by
brass and guitar in unison in `finale`, and by the guitar and then brass in
`trailer_theme`.

### Trailer theme timeline (`trailer_theme.ogg`, 90.0 s)

| time | section |
|---|---|
| 0.0 - 18.0 s | ominous intro: E drone, desert wind, sparse twang notes, a distant rumble, a theremin glide (about 9-15 s), a ticking clock creeping in |
| **18.0 s** | **HIT** (boom, crash, timpani, low piano, Em brass stab) |
| 18.0 - 20.0 s | near-silence riser and snare swell |
| 20.0 - 45.0 s | 144 BPM tom pulse. The main motif on baritone twang guitar (from 26.7 s), then a snare-roll and brass build |
| **45.0 s** | **HIT** into full energy |
| 45.0 - 80.0 s | driving rockabilly/boogie: motif on brass (45.0-58.3 s), a 12-bar in E with slap bass, twang riffs and horn riffs, then a tom fill |
| **80.0 s** | **BIG STOP / HIT** |
| 80.0 - 84.0 s | reverb tail and two lone twang notes |
| **84.0 s** | final E-minor chord (brass, tremolo guitar, piano, timpani roll) that rings out to silence at 90.0 s |

## Sound effects

Mono, 44.1 kHz, OGG Vorbis q5. Peaks are normalised to -1 dBFS, except the
intentionally softer `ui_move` (-6), `ui_back` (-4), `countdown_tick` (-3),
`mine_beep` (-3), `wind_loop` (-3) and `crickets_loop` (-3). Balance them
against each other with `volume_db` in the game.

`*_loop` files are built so they are periodic, which makes them sample-accurate
seamless loops. Every noise source, filter and event is computed on a circular
buffer, or the file is crossfaded (only `wind_loop`).

Engine notes for pitch-shifting (`pitch_scale` = rpm / base_rpm):

* `engine_loop.ogg`: a cross-plane V8 at about **750 rpm** idle (engine cycle
  6.25 Hz, **firing fundamental 50 Hz**), 1.6 s = exactly 10 engine cycles.
  At 0.6x it is about 450 rpm, and at 2.5x it is about 1900 rpm (125 Hz
  firing).
* `engine_heavy_loop.ogg`: an inline-6 diesel truck at about **600 rpm**
  (firing 30 Hz, cycle 5 Hz), 2.0 s = 10 cycles, with diesel clatter and
  rattles.
