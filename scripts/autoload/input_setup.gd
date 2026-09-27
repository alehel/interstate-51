extends Node
## Registers every input action in code so keyboard/mouse and Xbox-style
## controllers (XInput layout via SDL mappings) work out of the box.
##
## Controller layout (Xbox):
##   RT throttle · LT brake/reverse · Left stick steer · Right stick look
##   RB fire guns · LB fire special · Y cycle special · A handbrake
##   B look back · X change camera · D-pad left/right cycle target
##   L3 horn · View/Back objectives · Menu/Start pause

signal device_changed(using_pad: bool)

var using_pad := false
const DEADZONE := 0.15

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_define("accelerate", [KEY_W, KEY_UP], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_define("brake", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_define("steer_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_define("steer_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_define("handbrake", [KEY_SPACE], [JOY_BUTTON_A])
	_define("fire_primary", [KEY_CTRL, KEY_J], [JOY_BUTTON_RIGHT_SHOULDER], [], [MOUSE_BUTTON_LEFT])
	_define("fire_special", [KEY_SHIFT, KEY_K], [JOY_BUTTON_LEFT_SHOULDER], [], [MOUSE_BUTTON_RIGHT])
	_define("cycle_special", [KEY_Q], [JOY_BUTTON_Y])
	_define("camera", [KEY_C], [JOY_BUTTON_X])
	_define("look_back", [KEY_V, KEY_B], [JOY_BUTTON_B])
	_define("target_next", [KEY_TAB, KEY_E], [JOY_BUTTON_DPAD_RIGHT])
	_define("target_prev", [KEY_R], [JOY_BUTTON_DPAD_LEFT])
	_define("horn", [KEY_H], [JOY_BUTTON_LEFT_STICK])
	_define("objectives", [KEY_O], [JOY_BUTTON_BACK])
	_define("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])
	_define("skip", [KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_A, JOY_BUTTON_START])
	_define("look_left", [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_define("look_right", [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_define("look_up", [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_define("look_down", [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	# Menu navigation: make sure pads drive the built-in ui_* actions.
	_add_to("ui_accept", [], [JOY_BUTTON_A])
	_add_to("ui_cancel", [], [JOY_BUTTON_B])
	_add_to("ui_up", [], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_add_to("ui_down", [], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	_add_to("ui_left", [], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_add_to("ui_right", [], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	Input.joy_connection_changed.connect(_on_joy_changed)
	using_pad = Input.get_connected_joypads().size() > 0

func _define(action: String, keys: Array, buttons: Array, axes: Array = [], mouse: Array = []) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, 0.2)
	_add_to(action, keys, buttons, axes, mouse)

func _add_to(action: String, keys: Array, buttons: Array, axes: Array = [], mouse: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		e.device = -1
		InputMap.action_add_event(action, e)
	for a in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = a[0]
		e.axis_value = a[1]
		e.device = -1
		InputMap.action_add_event(action, e)
	for m in mouse:
		var e := InputEventMouseButton.new()
		e.button_index = m
		InputMap.action_add_event(action, e)

func _input(event: InputEvent) -> void:
	var pad := using_pad
	if event is InputEventJoypadButton:
		pad = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.4:
		pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false
	if pad != using_pad:
		using_pad = pad
		device_changed.emit(using_pad)

func _on_joy_changed(_device: int, connected: bool) -> void:
	if connected and not using_pad:
		using_pad = true
		device_changed.emit(true)

## Human-readable prompt for an action on the current device.
func prompt(action: String) -> String:
	var pad := {
		"accelerate": "RT", "brake": "LT", "steer": "L-Stick", "handbrake": "A",
		"fire_primary": "RB", "fire_special": "LB", "cycle_special": "Y",
		"camera": "X", "look_back": "B", "target_next": "D-Pad", "horn": "L3",
		"objectives": "View", "pause": "Menu", "skip": "A", "ui_accept": "A", "ui_cancel": "B",
	}
	var kb := {
		"accelerate": "W", "brake": "S", "steer": "A/D", "handbrake": "Space",
		"fire_primary": "Ctrl / LMB", "fire_special": "Shift / RMB", "cycle_special": "Q",
		"camera": "C", "look_back": "V", "target_next": "Tab", "horn": "H",
		"objectives": "O", "pause": "Esc", "skip": "Enter", "ui_accept": "Enter", "ui_cancel": "Esc",
	}
	return (pad if using_pad else kb).get(action, action)

## Rumble on every connected pad (no-op on keyboard).
func rumble(weak: float, strong: float, duration: float) -> void:
	if not Game.settings.get("rumble", true):
		return
	for d in Input.get_connected_joypads():
		Input.start_joy_vibration(d, clampf(weak, 0, 1), clampf(strong, 0, 1), duration)
