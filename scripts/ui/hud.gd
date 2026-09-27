class_name Hud
extends CanvasLayer
## In-mission HUD. Text widgets are Controls; instruments (radar, armour
## diagram, speedometer, weapon list, target brackets, beacons) are drawn
## each frame by the Gauges control.

var level: Level
var root: Control
var gauges: Gauges
var _objs: VBoxContainer
var _obj_items: Dictionary = {}
var _obj_panel: PanelContainer
var _obj_timer := 0.0
var _msg_title: Label
var _msg_sub: Label
var _msg_t := 0.0
var _sub_box: PanelContainer
var _sub_name: Label
var _sub_text: Label
var _sub_hide := 0.0
var _hint: Label
var _hint_t := 0.0
var _timer: Label
var _timer_end := -1.0
var _timer_label := ""
var _letter_top: ColorRect
var _letter_bot: ColorRect
var _skip: Label
var _flash: ColorRect
var _pause: Control
var _fail: Control
var tracked: Array = []

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	add_child(root)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(0.8, 0.05, 0.02, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)
	gauges = Gauges.new()
	gauges.hud = self
	gauges.set_anchors_preset(Control.PRESET_FULL_RECT)
	gauges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(gauges)
	# objectives (top-left)
	_obj_panel = PanelContainer.new()
	_obj_panel.position = Vector2(18, 16)
	_obj_panel.custom_minimum_size = Vector2(360, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.03, 0.55)
	sb.border_color = Color(0.9, 0.7, 0.3, 0.6)
	sb.border_width_left = 3
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_obj_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(_obj_panel)
	_objs = VBoxContainer.new()
	_obj_panel.add_child(_objs)
	var head := UiKit.label("OBJECTIVES", "bebasneue", 22, UiKit.GOLD)
	_objs.add_child(head)
	# centre message
	_msg_title = UiKit.label("", "rye", 54, UiKit.GOLD)
	_msg_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_msg_title.position = Vector2(-500, 150)
	_msg_title.size = Vector2(1000, 70)
	_msg_title.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	_msg_title.add_theme_constant_override("outline_size", 10)
	root.add_child(_msg_title)
	_msg_sub = UiKit.label("", "specialelite", 26, UiKit.CREAM)
	_msg_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_msg_sub.position = Vector2(-500, 220)
	_msg_sub.size = Vector2(1000, 40)
	_msg_sub.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	_msg_sub.add_theme_constant_override("outline_size", 8)
	root.add_child(_msg_sub)
	# subtitles
	_sub_box = PanelContainer.new()
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Color(0.03, 0.02, 0.02, 0.62)
	sb2.set_corner_radius_all(4)
	sb2.content_margin_left = 18
	sb2.content_margin_right = 18
	sb2.content_margin_top = 8
	sb2.content_margin_bottom = 10
	_sub_box.add_theme_stylebox_override("panel", sb2)
	_sub_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sub_box.position = Vector2(-420, -205)
	_sub_box.custom_minimum_size = Vector2(840, 0)
	_sub_box.visible = false
	root.add_child(_sub_box)
	var vb := VBoxContainer.new()
	_sub_box.add_child(vb)
	_sub_name = UiKit.label("", "bebasneue", 24, UiKit.GOLD)
	vb.add_child(_sub_name)
	_sub_text = UiKit.label("", "specialelite", 24, UiKit.CREAM)
	_sub_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_text.custom_minimum_size = Vector2(800, 0)
	vb.add_child(_sub_text)
	Audio.line_started.connect(_on_line)
	Audio.line_finished.connect(_on_line_done)
	# hint
	_hint = UiKit.label("", "bebasneue", 26, Color(1, 0.95, 0.8))
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position = Vector2(-500, -262)
	_hint.size = Vector2(1000, 36)
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hint.add_theme_constant_override("outline_size", 6)
	root.add_child(_hint)
	# timer
	_timer = UiKit.label("", "bebasneue", 44, Color(1, 0.9, 0.6))
	_timer.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.position = Vector2(-300, 18)
	_timer.size = Vector2(600, 50)
	_timer.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_timer.add_theme_constant_override("outline_size", 8)
	root.add_child(_timer)
	# letterbox
	_letter_top = ColorRect.new()
	_letter_top.color = Color.BLACK
	_letter_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_letter_top.size.y = 0
	root.add_child(_letter_top)
	_letter_bot = ColorRect.new()
	_letter_bot.color = Color.BLACK
	_letter_bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	root.add_child(_letter_bot)
	_skip = UiKit.label("", "bebasneue", 22, Color(0.8, 0.75, 0.65))
	_skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip.position = Vector2(-260, -48)
	root.add_child(_skip)
	letterbox(false, true)

# ------------------------------------------------------------ objectives

func objective_add(id: String, text: String) -> void:
	if _obj_items.has(id):
		return
	var l := UiKit.label("□  " + text, "specialelite", 21, UiKit.CREAM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(340, 0)
	_objs.add_child(l)
	_obj_items[id] = l
	flash_objectives()
	Audio.play("objective", -8.0, 0.8)

func objective_done(id: String) -> void:
	if not _obj_items.has(id):
		return
	var l: Label = _obj_items[id]
	l.text = "■  " + l.text.substr(3)
	l.add_theme_color_override("font_color", Color(0.55, 0.8, 0.45))
	flash_objectives()
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_callback(func():
		if is_instance_valid(l):
			l.queue_free()
		_obj_items.erase(id))

func flash_objectives() -> void:
	_obj_timer = 8.0

func message(title: String, sub: String = "", dur: float = 3.5) -> void:
	_msg_title.text = title
	_msg_sub.text = sub
	_msg_t = dur

func hint(text: String, dur: float = 6.0) -> void:
	_hint.text = text
	_hint_t = dur

func timer_start(sec: float, label: String) -> void:
	_timer_end = Time.get_ticks_msec() / 1000.0 + sec
	_timer_label = label

func timer_stop() -> void:
	_timer_end = -1.0
	_timer.text = ""

func timer_left() -> float:
	if _timer_end < 0.0:
		return INF
	return maxf(0.0, _timer_end - Time.get_ticks_msec() / 1000.0)

func whiteout(dur: float) -> void:
	var w := ColorRect.new()
	w.color = Color(1, 0.98, 0.92, 1.0)
	w.set_anchors_preset(Control.PRESET_FULL_RECT)
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(w)
	var tw := create_tween()
	tw.tween_property(w, "color:a", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(w.queue_free)

func track(c: Car) -> void:
	tracked.append(c)

func letterbox(on: bool, instant: bool = false) -> void:
	var h := 90.0 if on else 0.0
	_skip.text = ("[%s] SKIP" % InputSetup.prompt("skip")) if on else ""
	if instant:
		_letter_top.size.y = h
		_letter_bot.offset_top = -h
		return
	var tw := create_tween()
	tw.tween_property(_letter_top, "size:y", h, 0.6)
	tw.parallel().tween_property(_letter_bot, "offset_top", -h, 0.6)
	gauges.visible = not on
	_obj_panel.visible = not on

func _on_line(_id: String, speaker: String, text: String) -> void:
	if not Game.settings.subtitles:
		return
	_sub_name.text = Audio.speaker_name(speaker)
	_sub_name.add_theme_color_override("font_color", Audio.speaker_color(speaker))
	_sub_text.text = text
	_sub_box.visible = true
	_sub_hide = 0.0

func _on_line_done(_id: String) -> void:
	_sub_hide = 0.6

func _process(dt: float) -> void:
	_msg_t -= dt
	var ma := clampf(_msg_t / 0.6, 0.0, 1.0)
	_msg_title.modulate.a = ma
	_msg_sub.modulate.a = ma
	_hint_t -= dt
	_hint.modulate.a = clampf(_hint_t / 0.5, 0.0, 1.0)
	if _sub_hide > 0.0:
		_sub_hide -= dt
		if _sub_hide <= 0.0:
			_sub_box.visible = false
	_obj_timer -= dt
	_obj_panel.modulate.a = lerpf(_obj_panel.modulate.a, 1.0 if (_obj_timer > 0.0 or Input.is_action_pressed("objectives")) else 0.45, dt * 4.0)
	if _timer_end > 0.0:
		var left := timer_left()
		_timer.text = "%s  %d:%02d" % [_timer_label, int(left) / 60, int(left) % 60]
		_timer.add_theme_color_override("font_color", Color(1, 0.3, 0.2) if left < 20.0 and fmod(left, 1.0) > 0.5 else Color(1, 0.9, 0.6))
	var p := level.player if level else null
	if p and is_instance_valid(p):
		var fa := clampf(p._hit_flash / 0.15, 0.0, 1.0) * 0.25
		if p.health_frac() < 0.3 and not p.dead:
			fa = maxf(fa, 0.08 + 0.06 * sin(Time.get_ticks_msec() * 0.008))
		_flash.color.a = fa
	gauges.queue_redraw()

# ---------------------------------------------------------------- menus

func _menu(title: String, items: Array) -> Control:
	var cover := ColorRect.new()
	cover.color = Color(0, 0, 0, 0.6)
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(cover)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(460, 0)
	cover.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var t := UiKit.label(title, "rye", 40, UiKit.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var first: Button = null
	for it in items:
		if it[0] == "":
			var l := UiKit.label(it[1], "specialelite", 20, UiKit.CREAM)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(420, 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vb.add_child(l)
			continue
		var b := UiKit.button(it[0], it[1])
		vb.add_child(b)
		if not first:
			first = b
	await get_tree().process_frame
	panel.position = -panel.size * 0.5
	if first:
		first.grab_focus()
	return cover

func pause_menu(on: bool) -> void:
	if on:
		if _pause:
			return
		get_tree().paused = true
		var ctl := "Controls: %s throttle, %s brake, %s steer, %s guns, %s special, %s cycle, %s handbrake, %s camera, %s look back" % [
			InputSetup.prompt("accelerate"), InputSetup.prompt("brake"), InputSetup.prompt("steer"),
			InputSetup.prompt("fire_primary"), InputSetup.prompt("fire_special"), InputSetup.prompt("cycle_special"),
			InputSetup.prompt("handbrake"), InputSetup.prompt("camera"), InputSetup.prompt("look_back")]
		_pause = await _menu("PAUSED", [
			["RESUME", func(): pause_menu(false)],
			["RESTART MISSION", func():
				get_tree().paused = false
				Game.goto("res://scenes/level.tscn")],
			["QUIT TO MAIN MENU", func():
				get_tree().paused = false
				Game.goto("res://scenes/main_menu.tscn")],
			["", ctl],
		])
	else:
		if _pause:
			_pause.queue_free()
			_pause = null
		get_tree().paused = false

func _unhandled_input(event: InputEvent) -> void:
	if _pause and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		pause_menu(false)
		get_viewport().set_input_as_handled()

func fail_menu(reason: String) -> void:
	if _fail:
		return
	_fail = await _menu("MISSION FAILED", [
		["", reason],
		["RETRY", func(): Game.goto("res://scenes/level.tscn")],
		["BACK TO BRIEFING", func(): Game.goto("res://scenes/briefing.tscn")],
		["QUIT TO MAIN MENU", func(): Game.goto("res://scenes/main_menu.tscn")],
	])
