class_name UiKit
## Shared look for menus: 1950s road-map / dashboard styling.

const INK := Color(0.12, 0.09, 0.07)
const CREAM := Color(0.96, 0.9, 0.76)
const GOLD := Color(0.95, 0.72, 0.25)
const RED := Color(0.75, 0.16, 0.1)
const TEAL := Color(0.25, 0.62, 0.6)

static var _theme: Theme

static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = Lib.font("bebasneue")
	t.default_font_size = 30
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.08, 0.07, 0.85)
	normal.border_color = Color(0.55, 0.42, 0.25)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 22
	normal.content_margin_right = 22
	normal.content_margin_top = 6
	normal.content_margin_bottom = 4
	var hover := normal.duplicate()
	hover.bg_color = Color(0.55, 0.14, 0.09, 0.95)
	hover.border_color = GOLD
	var pressed := hover.duplicate()
	pressed.bg_color = Color(0.35, 0.09, 0.06, 1)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.1, 0.1, 0.1, 0.5)
	disabled.border_color = Color(0.3, 0.3, 0.3)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		pass
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", hover)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", Color(1, 0.95, 0.8))
	t.set_color("font_focus_color", "Button", Color(1, 0.95, 0.8))
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.5))
	t.set_color("font_color", "Label", CREAM)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.08, 0.06, 0.05, 0.88)
	panel.border_color = Color(0.55, 0.42, 0.25)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.content_margin_left = 24
	panel.content_margin_right = 24
	panel.content_margin_top = 18
	panel.content_margin_bottom = 18
	t.set_stylebox("panel", "PanelContainer", panel)
	var sl := StyleBoxFlat.new()
	sl.bg_color = Color(0.25, 0.2, 0.15)
	sl.content_margin_top = 4
	sl.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", sl)
	var grab := StyleBoxFlat.new()
	grab.bg_color = GOLD
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)
	_theme = t
	return t

static func label(text: String, font: String = "bebasneue", size: int = 28, col: Color = CREAM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Lib.font(font))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

static func button(text: String, cb: Callable, size: int = 30) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(func():
		Audio.ui("ui_select")
		cb.call())
	b.focus_entered.connect(func(): Audio.ui("ui_move"))
	b.mouse_entered.connect(func(): b.grab_focus())
	return b

static func full_rect(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	return c

## Vertical gradient background (desert dusk).
static func backdrop(top: Color, bottom: Color) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 256
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	full_rect(tr)
	return tr
