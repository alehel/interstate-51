extends Control
## Epilogue narration followed by rolling credits.

var _scroll: VBoxContainer
var _rolling := false
var _t := 0.0

const CREDITS := [
	["rye", 72, "INTERSTATE '51"],
	["bebasneue", 30, "NEVADA  ·  1951"],
	["", 0, ""],
	["bebasneue", 34, "THE CAST"],
	["specialelite", 24, "Wade \"Deacon\" Calloway  ·  Rosa Delgado  ·  Elijah \"Preacher\" Tate"],
	["specialelite", 24, "Dr. Miriam Holt  ·  Hollis Calloway  ·  Hal"],
	["specialelite", 24, "Augustus Vale  ·  Sheriff Boyd Harlan  ·  Colonel Rusk"],
	["specialelite", 24, "and the Chrome Legion"],
	["", 0, ""],
	["bebasneue", 34, "MADE WITH"],
	["specialelite", 24, "Godot Engine 4.4 (Compatibility renderer, Jolt Physics)"],
	["specialelite", 24, "Every model, texture, road and mountain generated in code"],
	["specialelite", 24, "Music & sound effects synthesized from scratch in Python"],
	["specialelite", 24, "Voices: Piper neural text-to-speech (rhasspy/piper voice models)"],
	["specialelite", 24, "Fonts: Rye (Sorkin Type), Special Elite (Astigmatic), Bebas Neue (Dharma Type)"],
	["", 0, ""],
	["bebasneue", 34, "INSPIRED BY"],
	["specialelite", 24, "Interstate '76 (Activision, 1997) - with love for the funk and the flares"],
	["", 0, ""],
	["specialelite", 24, "Written and built with Claude Code"],
	["", 0, ""],
	["rye", 40, "Drive safe. Duck & cover."],
]

func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.backdrop(Color(0.05, 0.03, 0.06), Color(0.2, 0.08, 0.05)))
	Audio.music("menu_theme", 2.0)
	var finished_campaign: bool = Game.progress.completed.has("m9")
	if finished_campaign:
		await _epilogue()
	_roll()

func _epilogue() -> void:
	var l := UiKit.label("", "specialelite", 30, UiKit.CREAM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.custom_minimum_size = Vector2(1000, 0)
	l.position = Vector2(-500, -120)
	add_child(l)
	for id in ["epi_1", "epi_2", "epi_3"]:
		l.text = Audio.line_text(id)
		l.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(l, "modulate:a", 1.0, 0.8)
		Audio.say(id)
		await get_tree().create_timer(0.3).timeout
		while Audio.pending(id):
			await get_tree().process_frame
			if _skip:
				break
		if _skip:
			Audio.stop_voice()
			break
		await get_tree().create_timer(0.8).timeout
	l.queue_free()

var _skip := false

func _roll() -> void:
	_scroll = VBoxContainer.new()
	_scroll.add_theme_constant_override("separation", 12)
	_scroll.custom_minimum_size = Vector2(1200, 0)
	add_child(_scroll)
	for c in CREDITS:
		if c[0] == "":
			var s := Control.new()
			s.custom_minimum_size = Vector2(0, 40)
			_scroll.add_child(s)
			continue
		var l := UiKit.label(c[2], c[0], c[1], UiKit.GOLD if c[0] == "rye" else UiKit.CREAM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(1200, 0)
		_scroll.add_child(l)
	await get_tree().process_frame
	var vw := get_viewport_rect().size
	_scroll.position = Vector2((vw.x - 1200) * 0.5, vw.y * 0.55)
	_rolling = true

func _process(dt: float) -> void:
	if _rolling:
		_scroll.position.y -= dt * 55.0
		if _scroll.position.y + _scroll.size.y < -40:
			_rolling = false
			Game.goto("res://scenes/main_menu.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept") or event.is_action_pressed("pause"):
		if not _rolling:
			_skip = true
		else:
			Game.goto("res://scenes/main_menu.tscn")
