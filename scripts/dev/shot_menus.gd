extends Node
## Dev: walks through the menu screens and saves screenshots.
## godot --path . res://scenes/dev/shot_menus.tscn -- --out=DIR
var out := "user://menus"
var steps := [
	["res://scenes/main_menu.tscn", 12.0, "main"],
	["res://scenes/briefing.tscn", 9.0, "briefing"],
	["garage", 2.0, "garage"],
	["res://scenes/debrief.tscn", 2.5, "debrief"],
	["res://scenes/credits.tscn", 6.0, "credits"],
]

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	Game.current_mission = 5
	Game.progress.unlocked = 5
	Game.last_result = {"title": "Chain Reaction", "time": 312.0, "kills": 11, "damage": 240.0, "shots": 1320}
	get_tree().root.add_child.call_deferred(Driver.new(steps, out))

class Driver extends Node:
	var steps: Array
	var out: String
	func _init(s: Array, o: String) -> void:
		steps = s
		out = o
		process_mode = Node.PROCESS_MODE_ALWAYS
	func _ready() -> void:
		for st in steps:
			if st[0] == "garage":
				var b := get_tree().current_scene
				b.call("_show_garage")
			else:
				get_tree().change_scene_to_file(st[0])
			await get_tree().create_timer(st[1]).timeout
			get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, st[2]])
		get_tree().quit()
