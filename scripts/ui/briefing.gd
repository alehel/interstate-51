extends Control
## Mission briefing (road map + typewritten, voiced journal entry) and the
## garage where the player picks Sally's loadout.

var m: Dictionary
var _text: Label
var _full := ""
var _shown := 0.0
var _map: TextureRect
var _marker: Control
var _right: VBoxContainer
var _t := 0.0
var _garage := false
var _lo: Dictionary
var _items: Array

func _ready() -> void:
	theme = UiKit.theme()
	m = Game.mission_def()
	add_child(UiKit.backdrop(Color(0.16, 0.11, 0.08), Color(0.05, 0.035, 0.03)))
	var hb := HBoxContainer.new()
	UiKit.full_rect(hb)
	hb.add_theme_constant_override("separation", 40)
	var margin := MarginContainer.new()
	UiKit.full_rect(margin)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 50)
	add_child(margin)
	margin.add_child(hb)
	# map
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(560, 560)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(frame)
	_map = TextureRect.new()
	_map.custom_minimum_size = Vector2(520, 520)
	_map.stretch_mode = TextureRect.STRETCH_SCALE
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.add_child(_map)
	_marker = Control.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	_map.add_child(_marker)
	UiKit.full_rect(_marker)
	var wait := UiKit.label("Surveying Nye County...", "specialelite", 22, UiKit.CREAM)
	wait.name = "Wait"
	_map.add_child(wait)
	wait.position = Vector2(150, 250)
	# right column
	_right = VBoxContainer.new()
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.add_theme_constant_override("separation", 14)
	hb.add_child(_right)
	_show_briefing()
	Audio.music("menu_theme", 1.0)
	Lib.start_world_thread()
	_load_map()

func _load_map() -> void:
	while not Lib.world_ready():
		await get_tree().process_frame
	await get_tree().process_frame
	_map.texture = Lib.map_texture()
	var w := _map.get_node_or_null("Wait")
	if w:
		w.queue_free()

func _draw_marker() -> void:
	if not _map.texture:
		return
	var sz := _map.size
	# every campaign location, faintly
	for i in Defs.MISSIONS.size():
		var mm: Dictionary = Defs.MISSIONS[i]
		var q: Vector2 = Lib.map_uv(mm.map) * sz
		var done: bool = Game.progress.completed.has(mm.id)
		_marker.draw_circle(q, 5.0, Color(0.25, 0.2, 0.15, 0.6) if not done else Color(0.2, 0.45, 0.2, 0.8))
	var p: Vector2 = Lib.map_uv(m.map) * sz
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	_marker.draw_arc(p, 14.0 + pulse * 8.0, 0, TAU, 32, Color(0.8, 0.1, 0.05, 1.0 - pulse * 0.6), 3.0)
	_marker.draw_circle(p, 7.0, Color(0.8, 0.1, 0.05))
	var f := Lib.font("bebasneue")
	_marker.draw_string_outline(f, p + Vector2(16, -10), m.title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, Color(0.95, 0.9, 0.8))
	_marker.draw_string(f, p + Vector2(16, -10), m.title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.5, 0.08, 0.05))
	_marker.draw_string(Lib.font("rye"), Vector2(16, sz.y - 16), "NYE COUNTY, NEV.", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.35, 0.22, 0.12))

func _process(dt: float) -> void:
	_t += dt
	_marker.queue_redraw()
	if _text and _shown < _full.length():
		_shown += dt * 38.0
		_text.visible_characters = int(_shown)

func _clear() -> void:
	for c in _right.get_children():
		c.queue_free()

func _show_briefing() -> void:
	_garage = false
	_clear()
	var idx := Game.current_mission
	_right.add_child(UiKit.label("MISSION %d OF %d" % [idx + 1, Defs.MISSIONS.size()], "bebasneue", 28, Color(0.8, 0.6, 0.35)))
	var title := UiKit.label(m.title.to_upper(), "rye", 58, UiKit.GOLD)
	title.add_theme_color_override("font_outline_color", Color(0.3, 0.05, 0.03))
	title.add_theme_constant_override("outline_size", 10)
	_right.add_child(title)
	_right.add_child(UiKit.label(m.summary, "bebasneue", 26, UiKit.CREAM))
	var parts: Array = []
	for id in m.briefing:
		parts.append(Audio.line_text(id))
	_full = "\n\n".join(parts)
	_text = UiKit.label(_full, "specialelite", 22, Color(0.92, 0.88, 0.78))
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(560, 300)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.visible_characters = 0
	_shown = 0.0
	_right.add_child(_text)
	Audio.stop_voice()
	for id in m.briefing:
		Audio.say(id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_right.add_child(row)
	var go := UiKit.button("TO THE GARAGE  ▶", _show_garage)
	row.add_child(go)
	row.add_child(UiKit.button("MAIN MENU", func():
		Audio.stop_voice()
		Game.goto("res://scenes/main_menu.tscn")))
	await get_tree().process_frame
	go.grab_focus()

func _show_garage() -> void:
	_garage = true
	_shown = 99999.0
	_clear()
	_items = Game.items_for_mission(Game.current_mission)
	_lo = Game.loadout()
	_right.add_child(UiKit.label("ROSA'S GARAGE", "rye", 50, UiKit.GOLD))
	_right.add_child(UiKit.label("'49 Mercury \"Black Sally\" - chopped, channeled and armored.", "specialelite", 20, UiKit.CREAM))
	var guns: Array = []
	for k in ["mg30", "mg50", "flame"]:
		if _items.has(k):
			guns.append(k)
	var specials: Array = [""]
	for k in ["rockets", "mines", "oil"]:
		if _items.has(k):
			specials.append(k)
	var first := _cycler("HOOD GUNS", guns, func(): return _lo.gun, func(v): _lo.gun = v)
	_cycler("SPECIAL - ROOF / TRUNK", specials, func(): return _lo.special[0], func(v): _lo.special[0] = v)
	_cycler("SPECIAL - REAR", specials, func(): return _lo.special[1], func(v): _lo.special[1] = v)
	var up := []
	for u in Defs.UPGRADES:
		if _items.has(u):
			up.append("%s - %s" % [Defs.UPGRADES[u].name, Defs.UPGRADES[u].desc])
	if not up.is_empty():
		var ul := UiKit.label("INSTALLED:\n" + "\n".join(up), "specialelite", 18, Color(0.7, 0.9, 0.7))
		ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ul.custom_minimum_size = Vector2(560, 0)
		_right.add_child(ul)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_right.add_child(row)
	row.add_child(UiKit.button("HIT THE ROAD  ▶", func():
		Game.set_loadout(_lo)
		Audio.stop_voice()
		Game.goto("res://scenes/level.tscn")))
	row.add_child(UiKit.button("BRIEFING", _show_briefing))
	await get_tree().process_frame
	first.grab_focus()

func _cycler(label: String, options: Array, getter: Callable, setter: Callable) -> Button:
	var box := VBoxContainer.new()
	_right.add_child(box)
	box.add_child(UiKit.label(label, "bebasneue", 24, Color(0.8, 0.6, 0.35)))
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(560, 0)
	var desc := UiKit.label("", "specialelite", 18, Color(0.85, 0.8, 0.7))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(560, 0)
	var refresh := func():
		var v: String = getter.call()
		var nm: String = Defs.WEAPONS[v].name if v != "" else "(empty)"
		b.text = "◀  %s  ▶" % nm
		desc.text = Defs.WEAPONS[v].desc if v != "" else ""
	var step := func(dir: int):
		if options.size() < 2:
			return
		var i := options.find(getter.call())
		i = (i + dir + options.size()) % options.size()
		setter.call(options[i])
		Audio.ui("ui_move")
		refresh.call()
	b.pressed.connect(func(): step.call(1))
	b.gui_input.connect(func(ev: InputEvent):
		if ev.is_action_pressed("ui_left"):
			step.call(-1)
			b.accept_event()
		elif ev.is_action_pressed("ui_right"):
			step.call(1)
			b.accept_event())
	b.mouse_entered.connect(func(): b.grab_focus())
	box.add_child(b)
	box.add_child(desc)
	refresh.call()
	return b

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _garage:
			_show_briefing()
		else:
			Audio.stop_voice()
			Game.goto("res://scenes/main_menu.tscn")
