# INTERSTATE '51

**Vehicular combat in atomic-age Nevada, 1951.** A single-player story
campaign inspired by *Interstate '76*, built in **Godot 4.4** with an
early-2000s look (Gouraud-lit low-poly cars, vertex-colored terrain, detail
textures, blob shadows, billboard foliage and a bloom-heavy sky). Draw
distance and vehicle count are not held back.

You drive Wade "Deacon" Calloway and his chopped '49 Mercury, **Black Sally**,
across nine voiced missions. He is looking for his missing brother and runs
into a plot to steal an atom bomb. The full story bible is in
[`docs/STORY.md`](docs/STORY.md).

**Trailer:** [`trailer/interstate51_trailer.mp4`](trailer/interstate51_trailer.mp4). It is
rendered in-engine from the game's own systems with Godot's Movie Maker.

## Running

1. Install **Godot 4.4** or newer, the standard (non-.NET) build.
2. Open `project.godot` in the editor, or run `godot --path .` from the repository root.
3. The first launch imports the assets and generates the 6 x 6 km world, which takes a few seconds. The heightmap is then cached in `user://`.

The game uses the **Compatibility (OpenGL 3.3)** renderer, so it runs on
modest hardware, and **Jolt** physics.

## Controls

Xbox-style controllers work out of the box (XInput layout through SDL). Menus
can be driven by pad, keyboard or mouse. On-screen prompts switch to match the
last device you used.

| Action | Xbox controller | Keyboard / mouse |
|---|---|---|
| Throttle | RT | W / Up |
| Brake / reverse | LT | S / Down |
| Steer | Left stick | A / D |
| Fire hood guns | RB | Ctrl / Left mouse |
| Fire special (rockets, mines, oil) | LB | Shift / Right mouse |
| Cycle special | Y | Q |
| Handbrake | A | Space |
| Look back | B | V |
| Change camera (near / far / bumper) | X | C |
| Look around | Right stick | — |
| Cycle target | D-pad left / right | Tab / R |
| Horn | L3 | H |
| Objectives | View | O |
| Pause | Menu | Esc / P |
| Skip cinematic | A / Menu | Enter |

Rumble is supported, and you can turn it off in Options.

## Features

- **Nine-mission campaign** with briefings voiced as Deacon's journal, in-mission radio dialogue (about 150 lines, 13 characters), combat barks, cinematics, a debrief after each mission, an epilogue and credits.
- **Mission types:** tutorial, clear-and-search, boss fight, convoy escort, rescue and escort, timed base raid, prison break, intercept-the-convoy and a final boss chase while an atomic test goes off on the horizon.
- **Vehicle combat.** Every car uses raycast suspension, has rear-wheel drive and a three-speed box, can slide under the handbrake, and has directional armor (front, rear, left, right plus chassis). Ramming does damage, and wrecks burn.
- **Weapons:** .30 Brownings, the .50 "Thumper", the Dragon's Breath flamethrower, Zuni rockets, road mines and oil slicks, plus salvage progression and a garage loadout screen.
- **AI** that dogfights: it leads its shots, strafes, jousts, rams, drops mines behind it, fires in bursts, escorts, guards, follows convoy routes, avoids obstacles and steep ground, navigates the road network, and gets itself unstuck.
- **An open, hand-laid world:** a 6 km basin with two dry lakes, canyons cut by roads, US-95, the Mercury road, Hal's truck stop, the Gold Creek ghost town, Vale's depot, the Silver Queen mine, the Doom Town test houses, the Indian Springs airstrip, Burma-Shave-style signs, billboards, telephone lines, and Joshua trees you can knock down. Distant ranges run out to the horizon.
- **Seven times of day:** noon, afternoon, golden hour, dusk, night, dawn and morning. Headlights, neon, floodlights and police sirens come on in the dark.
- **Sound:** real recorded gunfire, explosions, crashes, tyres, V8 engines, desert wind and night crickets (openly licensed, see `CREDITS.md`), with synthesized music.
- **Effects:** a batched particle engine drives tracers, muzzle flashes, sparks, fire, smoke, dust, debris and shock rings. There is also a mushroom cloud.
- **HUD:** a 1950s speedometer dial, armor diagram, radar, weapon list, target brackets with health, objective beacons and subtitles.

## Project layout

```
project.godot            Godot project (Compatibility renderer, Jolt physics)
scenes/                  Thin scene files; everything is built in code
scripts/
  autoload/              InputSetup (keyboard + Xbox bindings), Game (save/progress),
                         Audio (music, SFX, dialogue queue), Lib (textures/materials)
  defs.gd                Weapons, vehicles, campaign data
  mesh_builder.gd        Procedural geometry toolkit (boxes, cylinders, lofts)
  world/                 Terrain/road generation, scenery, locations, time of day
  vehicles/              Car physics, procedural 1950s car models, AI, player input, camera
  weapons/               Weapons, rockets, mines, oil, destructible structures, pickups
  fx/                    Particle system, atomic blast
  mission/               Level runner and MissionBase scripting API
  missions/              The nine mission scripts
  ui/                    Menus, briefing/garage, HUD, debrief, credits
  trailer/               Scripted trailer director
data/dialogue.json       Every line of dialogue + speaker table
assets/                  Fonts, synthesized music & SFX, generated voice lines
tools/audio/             Python synthesizers that produced the music and SFX
tools/voice/             Voice-line generator (Piper TTS + radio/PA effects)
docs/STORY.md            Story bible
```

### Writing a mission

Mission scripts extend `MissionBase` and tell their story as a coroutine:

```gdscript
func run() -> void:
	await say("m2_rosa_01")
	objective("raiders", "Drive off the raiders torching Hal's truck stop")
	await wait_dead(raiders)
	complete("raiders")
	await wait_reach(p(-150, -1745), 14.0, "HOLLIS'S RIG")
	win()
```

## Developer tools

| Task | Command |
|---|---|
| Play a mission directly | `godot --path . -- --mission=5` |
| Autopilot regression run of a mission (the AI drives Sally, headless, faster than real time) | `godot --headless --path . --fixed-fps 60 -- --mission=5 --autoplay` |
| Render the trailer | `godot --path . --write-movie trailer.avi --fixed-fps 30 --resolution 1280x720 -- --trailer` |
| Regenerate the voice lines (needs `pip install piper-tts` and the rhasspy/piper v0.0.2 voice models in `/opt/piper`) | `python3 tools/voice/make_voices.py --force` |
| Regenerate the music and synthesized SFX (see `tools/audio/README.md`) | `python3 tools/audio/make_sfx.py && python3 tools/audio/make_music.py` |
| Rebuild the recorded SFX (needs the `supertuxkart-data` and `redeclipse-data` packages extracted into `src/`, see the script's docstring) | `python3 tools/audio/make_sfx_recorded.py src` |

## Credits and licenses

See [`CREDITS.md`](CREDITS.md).
