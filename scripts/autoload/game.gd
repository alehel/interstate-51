extends Node
## Campaign state, settings, save data and scene flow.

const SAVE_PATH := "user://interstate51_save.json"

var settings := {
	"master": 0.9, "music": 0.7, "sfx": 0.9, "voice": 1.0,
	"rumble": true, "subtitles": true, "invert_look": false,
	"fullscreen": false, "render_scale": 1.0, "shadows": true, "difficulty": 1,
}

var progress := {
	"unlocked": 0,          # highest mission index available
	"completed": [],        # mission ids
	"items": [],            # weapons + upgrades owned
	"loadout": {"gun": "mg30", "special": ["", ""]},
	"stats": {},            # mission id -> best stats
}

var current_mission := 0
var last_result := {}       # filled by Level at mission end
var autoplay := false       # testing: AI drives the player
var god_mode := false
var skip_cinematics := false
var fast_boot := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_game()
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay":
			autoplay = true
			god_mode = true
			skip_cinematics = true
		elif a == "--god":
			god_mode = true
		elif a.begins_with("--mission="):
			current_mission = int(a.substr(10)) - 1
		elif a == "--fast":
			fast_boot = true
	apply_settings.call_deferred()

func apply_settings() -> void:
	Audio.apply_volumes()
	if not Engine.is_editor_hint() and DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want and not OS.has_feature("movie"):
			DisplayServer.window_set_mode(want)
	get_viewport().scaling_3d_scale = clampf(settings.render_scale, 0.5, 1.0)

func new_game() -> void:
	progress.unlocked = 0
	progress.completed = []
	progress.items = []
	progress.loadout = {"gun": "mg30", "special": ["", ""]}
	current_mission = 0
	save_game()

func mission_def(i: int = -1) -> Dictionary:
	if i < 0:
		i = current_mission
	return Defs.MISSIONS[clampi(i, 0, Defs.MISSIONS.size() - 1)]

## Items owned when starting mission i (everything unlocked up to and including it).
func items_for_mission(i: int) -> Array:
	var items: Array = []
	for k in range(0, i + 1):
		for it in Defs.MISSIONS[k].unlock:
			if not items.has(it):
				items.append(it)
	return items

func has_item(it: String) -> bool:
	return items_for_mission(current_mission).has(it)

## Returns a valid loadout for the current mission, fixing up anything not owned.
func loadout() -> Dictionary:
	var items := items_for_mission(current_mission)
	var lo: Dictionary = progress.loadout.duplicate(true)
	if not items.has(lo.gun):
		lo.gun = "mg30"
	var specials: Array = []
	for s in lo.special:
		if s != "" and items.has(s) and not specials.has(s):
			specials.append(s)
	# Auto-fill empty special slots with owned specials.
	for s in ["rockets", "mines", "oil"]:
		if specials.size() >= 2:
			break
		if items.has(s) and not specials.has(s):
			specials.append(s)
	while specials.size() < 2:
		specials.append("")
	lo.special = specials
	return lo

func set_loadout(lo: Dictionary) -> void:
	progress.loadout = lo.duplicate(true)
	save_game()

func mission_completed(stats: Dictionary) -> void:
	var id: String = mission_def().id
	if not progress.completed.has(id):
		progress.completed.append(id)
	var best: Dictionary = progress.stats.get(id, {})
	if best.is_empty() or stats.get("time", 9999.0) < best.get("time", 9999.0):
		progress.stats[id] = stats
	progress.unlocked = maxi(progress.unlocked, mini(current_mission + 1, Defs.MISSIONS.size() - 1))
	save_game()

func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"settings": settings, "progress": progress}, "  "))

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	for k in d.get("settings", {}):
		settings[k] = d.settings[k]
	for k in d.get("progress", {}):
		progress[k] = d.progress[k]
	progress.unlocked = int(progress.unlocked)

# ---------------------------------------------------------------- scene flow

var _fade: ColorRect
var _fade_layer: CanvasLayer

func goto(path: String) -> void:
	if not _fade_layer:
		_fade_layer = CanvasLayer.new()
		_fade_layer.layer = 100
		add_child(_fade_layer)
		_fade = ColorRect.new()
		_fade.color = Color(0, 0, 0, 0)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade_layer.add_child(_fade)
	get_tree().paused = false
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	await tw.finished
	Audio.stop_voice()
	Audio.ambience("")
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, 0.45)

func start_mission(i: int) -> void:
	current_mission = i
	goto("res://scenes/briefing.tscn")

func difficulty_mult() -> float:
	return [0.7, 1.0, 1.3][clampi(int(settings.difficulty), 0, 2)]
