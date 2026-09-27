extends Control
## After-action report and what's waiting in the garage next time.

func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.backdrop(Color(0.12, 0.08, 0.06), Color(0.04, 0.03, 0.02)))
	var r: Dictionary = Game.last_result
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.custom_minimum_size = Vector2(760, 0)
	add_child(vb)
	vb.add_child(UiKit.label("AFTER ACTION REPORT", "bebasneue", 30, Color(0.8, 0.6, 0.35)))
	var t := UiKit.label(String(r.get("title", "")).to_upper(), "rye", 60, UiKit.GOLD)
	vb.add_child(t)
	var stats := "Time on the road:  %d:%02d\nChrome Legion wrecked:  %d\nDamage absorbed:  %d\nRounds fired:  %d" % [
		int(r.get("time", 0)) / 60, int(r.get("time", 0)) % 60, r.get("kills", 0), int(r.get("damage", 0)), r.get("shots", 0)]
	vb.add_child(UiKit.label(stats, "specialelite", 26, UiKit.CREAM))
	var last := Game.current_mission >= Defs.MISSIONS.size() - 1
	if not last:
		var nxt: Dictionary = Game.mission_def(Game.current_mission + 1)
		var got: Array = []
		for it in nxt.unlock:
			got.append(Defs.WEAPONS[it].name if Defs.WEAPONS.has(it) else Defs.UPGRADES[it].name)
		if not got.is_empty():
			vb.add_child(UiKit.label("NEW IN THE GARAGE:  " + ",  ".join(got), "bebasneue", 30, Color(0.6, 0.9, 0.6)))
		vb.add_child(UiKit.label("NEXT:  " + nxt.title.to_upper(), "bebasneue", 30, UiKit.CREAM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	vb.add_child(row)
	var cont := UiKit.button("CONTINUE  ▶", func():
		if last:
			Game.goto("res://scenes/credits.tscn")
		else:
			Game.start_mission(Game.current_mission + 1))
	row.add_child(cont)
	row.add_child(UiKit.button("MAIN MENU", func(): Game.goto("res://scenes/main_menu.tscn")))
	await get_tree().process_frame
	vb.position = (get_viewport_rect().size - vb.size) * 0.5
	cont.grab_focus()
	Audio.music("menu_theme", 2.0)
