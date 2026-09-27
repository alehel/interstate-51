extends Node
## Entry point: routes to the main menu (or straight into a mission / the
## trailer when launched with -- --mission=N / --trailer for testing).

func _ready() -> void:
	await get_tree().process_frame
	var target := "res://scenes/main_menu.tscn"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mission="):
			target = "res://scenes/level.tscn"
		elif a == "--trailer":
			target = "res://scenes/trailer.tscn"
		elif a == "--credits":
			target = "res://scenes/credits.tscn"
	get_tree().change_scene_to_file(target)
