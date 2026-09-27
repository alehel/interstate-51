extends Node3D
## Title screen: Sally parked at the Boneyard at dusk, a slow orbiting camera,
## and the campaign / options / credits menus.

var ui: Control
var _panel: VBoxContainer
var _cam: Camera3D
var _t := 0.0
var _center := Vector3.ZERO
var _built := false
var _sub: Control
var _title: Label

func _ready() -> void:
	ui = Control.new()
	ui.theme = UiKit.theme()
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(ui)
	UiKit.full_rect(ui)
	var bg := UiKit.backdrop(Color(0.12, 0.08, 0.16), Color(0.75, 0.35, 0.2))
	bg.name = "Backdrop"
	ui.add_child(bg)
	_build_ui()
	Audio.music("menu_theme", 2.0)
	Lib.start_world_thread()
	if not Game.fast_boot:
		_wait_world()

func _wait_world() -> void:
	while not Lib.world_ready():
		await get_tree().process_frame
	_build_scene()

func _build_scene() -> void:
	var w := Lib.world
	var fx := Fx.new()
	add_child(fx)
	var wb := WorldBuilder.new()
	add_child(wb)
	wb.build(w, "dusk")
	EnvSetup.build(self, "dusk")
	_center = w.pos(-590, 1050)
	var car := Car.new()
	car.setup("merc", Defs.Team.PLAYER, {"weapons": ["mg30", "mg30", "rockets"]})
	add_child(car)
	car.place(_center, 2.3)
	car.enable_headlights(true)
	car.freeze = false
	_cam = Camera3D.new()
	_cam.far = 30000.0
	_cam.fov = 55.0
	add_child(_cam)
	_cam.current = true
	_built = true
	var tw := create_tween()
	tw.tween_property(ui.get_node("Backdrop"), "modulate:a", 0.0, 2.0)

func _process(dt: float) -> void:
	_t += dt
	if _built and _cam:
		var a := _t * 0.06 + 0.8
		var r := 10.5
		_cam.global_position = _center + Vector3(cos(a) * r, 2.2 + sin(_t * 0.2) * 0.4, sin(a) * r)
		_cam.look_at(_center + Vector3(0, 0.9, 0), Vector3.UP)
	if _title:
		_title.add_theme_color_override("font_color", UiKit.GOLD.lerp(Color(1, 0.9, 0.6), 0.5 + 0.5 * sin(_t * 1.5)))

func _build_ui() -> void:
	var margin := MarginContainer.new()
	UiKit.full_rect(margin)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_top", 60)
	ui.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)
	_title = UiKit.label("INTERSTATE '51", "rye", 96, UiKit.GOLD)
	_title.add_theme_color_override("font_outline_color", Color(0.45, 0.08, 0.05))
	_title.add_theme_constant_override("outline_size", 18)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_title.add_theme_constant_override("shadow_offset_x", 5)
	_title.add_theme_constant_override("shadow_offset_y", 6)
	vb.add_child(_title)
	var sub := UiKit.label("NEVADA  ·  1951  ·  THE ATOMIC AGE HAS A SPEED LIMIT", "bebasneue", 30, UiKit.CREAM)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	sub.add_theme_constant_override("outline_size", 6)
	vb.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	vb.add_child(spacer)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 10)
	_panel.custom_minimum_size = Vector2(380, 0)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vb.add_child(_panel)
	_main_buttons()
	var foot := UiKit.label("%s / %s select   ·   Xbox controller supported" % [InputSetup.prompt("ui_accept"), "Enter"], "bebasneue", 22, Color(0.9, 0.85, 0.75, 0.8))
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(80, -50)
	ui.add_child(foot)

func _clear() -> void:
	for c in _panel.get_children():
		c.queue_free()
	if _sub:
		_sub.queue_free()
		_sub = null

func _main_buttons() -> void:
	_clear()
	var first: Button
	if Game.progress.unlocked > 0 or not Game.progress.completed.is_empty():
		var m: Dictionary = Game.mission_def(Game.progress.unlocked)
		first = UiKit.button("CONTINUE  -  %s" % m.title.to_upper(), func(): Game.start_mission(Game.progress.unlocked))
		_panel.add_child(first)
	var nb := UiKit.button("NEW CAMPAIGN", func():
		Game.new_game()
		Game.start_mission(0))
	_panel.add_child(nb)
	if not first:
		first = nb
	_panel.add_child(UiKit.button("MISSION SELECT", _mission_select))
	_panel.add_child(UiKit.button("OPTIONS", _options))
	_panel.add_child(UiKit.button("CREDITS", func(): Game.goto("res://scenes/credits.tscn")))
	_panel.add_child(UiKit.button("QUIT", func(): get_tree().quit()))
	await get_tree().process_frame
	first.grab_focus()

func _mission_select() -> void:
	_clear()
	var first: Button
	for i in Defs.MISSIONS.size():
		var m: Dictionary = Defs.MISSIONS[i]
		var done: bool = Game.progress.completed.has(m.id)
		var label := "%d. %s%s" % [i + 1, m.title.to_upper(), "  ✓" if done else ""]
		var b := UiKit.button(label, func(): Game.start_mission(i), 26)
		b.disabled = i > Game.progress.unlocked
		_panel.add_child(b)
		if not first and not b.disabled:
			first = b
	_panel.add_child(UiKit.button("BACK", _main_buttons, 26))
	await get_tree().process_frame
	first.grab_focus()

func _options() -> void:
	_clear()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	_panel.add_child(grid)
	var first: Control
	for k in [["master", "MASTER VOLUME"], ["music", "MUSIC"], ["sfx", "EFFECTS"], ["voice", "VOICES"]]:
		grid.add_child(UiKit.label(k[1], "bebasneue", 26))
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = Game.settings[k[0]]
		s.custom_minimum_size = Vector2(240, 30)
		var key: String = k[0]
		s.value_changed.connect(func(v):
			Game.settings[key] = v
			Game.apply_settings())
		grid.add_child(s)
		if not first:
			first = s
	var diff := ["EASY", "NORMAL", "HARD"]
	var db := UiKit.button("DIFFICULTY: %s" % diff[Game.settings.difficulty], func(): pass, 26)
	db.pressed.connect(func():
		Game.settings.difficulty = (int(Game.settings.difficulty) + 1) % 3
		db.text = "DIFFICULTY: %s" % diff[Game.settings.difficulty])
	_panel.add_child(db)
	for k in [["rumble", "CONTROLLER RUMBLE"], ["subtitles", "SUBTITLES"], ["fullscreen", "FULLSCREEN"], ["shadows", "SUN SHADOWS"]]:
		var key: String = k[0]
		var nm: String = k[1]
		var b := UiKit.button("%s: %s" % [nm, "ON" if Game.settings[key] else "OFF"], func(): pass, 26)
		b.pressed.connect(func():
			Game.settings[key] = not Game.settings[key]
			b.text = "%s: %s" % [nm, "ON" if Game.settings[key] else "OFF"]
			Game.apply_settings())
		_panel.add_child(b)
	var rs := UiKit.button("RESOLUTION SCALE: %d%%" % int(Game.settings.render_scale * 100), func(): pass, 26)
	rs.pressed.connect(func():
		var v: float = Game.settings.render_scale
		v = 0.5 if v >= 1.0 else v + 0.25
		Game.settings.render_scale = v
		rs.text = "RESOLUTION SCALE: %d%%" % int(v * 100)
		Game.apply_settings())
	_panel.add_child(rs)
	_panel.add_child(UiKit.button("BACK", func():
		Game.save_game()
		_main_buttons(), 26))
	await get_tree().process_frame
	first.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Game.save_game()
		_main_buttons()
