# Credits and third-party licenses

## Original content

The code, story, dialogue, procedural models, textures, the world and the
music of *Interstate '51* were created for this project. The music is
synthesized from scratch by the Python scripts in `tools/audio/`.

## Sound effects (`assets/audio/sfx/`)

Most sound effects are built from real recordings taken from the openly
licensed data of two open-source games, **SuperTuxKart** and **Red Eclipse**
(Debian packages `supertuxkart-data` and `redeclipse-data`). They are
processed (trimmed, layered, filtered, pitched, looped, normalised) by
`tools/audio/make_sfx_recorded.py`. The processed files are adaptations and
carry the licence of their sources:

| Game sound(s) | Source recording(s) | Author / licence |
|---|---|---|
| `mg30_shot`, `mg50_shot`, `rocket_launch`, `explosion_small`, `explosion_big` (with `explosion` below), `atomic_blast` (with `thunder` below), `mine_beep`, `mine_drop`, `impact_metal_1-2`, `ricochet`, `flame_loop`, `wreck_fire_loop`, `crash_light`/`crash_heavy` (low layer), `ui_move`, `ui_select`, `ui_back`, `pickup`, `repair` | Red Eclipse weapon, interface and ambience sounds | Red Eclipse Team, CC BY-SA 3.0 |
| `wind_loop` | Red Eclipse `ambience/wind.ogg` | Batuhan Bozkurt (freesound.org), CC BY-SA 3.0 |
| `crickets_loop` | Red Eclipse `ambience/nightcrickets.ogg` | Richard "RHumphries" Humphries (freesound.org), CC BY-SA 3.0 |
| `explosion_big` (layer) | SuperTuxKart `explosion.ogg` | ZAQraven, CC0 |
| `crash_light`, `crash_heavy` | SuperTuxKart `crash*.ogg` | The Audio Monkey, CC BY-SA 4.0 |
| `skid_loop` | SuperTuxKart `skid.ogg` | Tom "audible-edge" Haigh, Iwan "qubodup" Gabovitch, CC BY 3.0 |
| `horn` | SuperTuxKart `horn.ogg` | Mike Koenig, Marianne Gagnon, Magne Djupvik, CC BY 3.0 |
| `engine_loop`, `engine_heavy_loop` | SuperTuxKart `engine_large.ogg` | Mike Koenig, "Stephan", Marianne Gagnon, "SnapJunkie", CC BY-SA 3.0 |
| `atomic_blast` (layer) | SuperTuxKart `thunder.ogg` | Mike Koenig, Marianne Gagnon, CC BY 3.0 |
| `radio_on`, `radio_off` | SuperTuxKart `static-radio.ogg` | nicStage, Jean-Manuel Clémençon, CC BY 3.0 |
| `impact_metal_3` | SuperTuxKart `metal_clang.ogg` | dADDoiT, Mike Koenig, Marianne Gagnon, CC BY 3.0 |

The remaining effects (`siren_loop`, `klaxon`, `oil_drop`, `objective`,
`objective_fail`, `warning_beep`, `countdown_tick`) are synthesized by
`tools/audio/make_sfx.py` and are original.

*Interstate '51* is an homage to *Interstate '76* (Activision, 1997). It shares
no code, assets, characters or story with that game.

## Engine

- **Godot Engine 4.4**, MIT License, https://godotengine.org
- **Jolt Physics** (bundled with Godot), MIT License

## Fonts (`assets/fonts/`)

- **Rye** by Nicole Fally / Sorkin Type, SIL Open Font License 1.1 (`OFL-Rye.txt`)
- **Bebas Neue** by Dharma Type, SIL Open Font License 1.1 (`OFL-BebasNeue.txt`)
- **Special Elite** by Astigmatic, Apache License 2.0 (`LICENSE-SpecialElite.txt`)

## Voices (`assets/voice/`)

The voice lines were synthesized with **Piper** (https://github.com/rhasspy/piper,
MIT License) and then processed with CB-radio and PA effects. The voice models
come from the rhasspy/piper v0.0.2 release:

| Characters | Piper voice | Training data license |
|---|---|---|
| Deacon, Rosa, Preacher, Vale, Harlan, Hollis, Hal, Rusk, Shot Control, Legion, Deputy | `en-us-libritts-high` (multi-speaker) | LibriTTS, CC BY 4.0 (openslr.org/60) |
| Dr. Miriam Holt | `en-gb-southern_english_female-low` | CC BY-SA 4.0 (openslr.org/83) |

Because the Holt lines come from a model trained on CC BY-SA 4.0 data, those
generated audio files (`assets/voice/m*_miriam_*.ogg`) are distributed under
CC BY-SA 4.0.
