# Credits and third-party licenses

## Original content

The code, story, dialogue, procedural models, textures, the world, the music
and the sound effects of *Interstate '51* were created for this project.
Music and SFX are synthesized from scratch by the Python scripts in
`tools/audio/`. No samples were used.

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
