class_name PlayerInput
extends Node
## Reads keyboard / Xbox controller input into the player's Car and handles
## target lock (automatic, with manual cycling).

var car: Car
var level: Node
var locked: Node3D = null
var manual_lock := false
var _auto_t := 0.0
var _low_warned := false

func _ready() -> void:
	car = get_parent()
	level = get_tree().current_scene

func _physics_process(dt: float) -> void:
	if not car or car.dead:
		return
	var blocked: bool = level.get("input_locked") == true
	if blocked:
		car.throttle = 0.0
		car.brake = 0.4
		car.steer = 0.0
		car.fire_primary = false
		car.fire_special = false
		car.handbrake = false
		return
	car.throttle = Input.get_action_strength("accelerate")
	car.brake = Input.get_action_strength("brake")
	car.steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	car.handbrake = Input.is_action_pressed("handbrake")
	car.fire_primary = Input.is_action_pressed("fire_primary")
	car.fire_special = Input.is_action_pressed("fire_special")
	# target lock
	if locked and (not is_instance_valid(locked) or (locked.get("dead") == true) or locked.global_position.distance_to(car.global_position) > 420.0):
		locked = null
		manual_lock = false
	_auto_t -= dt
	if not manual_lock and _auto_t <= 0.0:
		_auto_t = 0.25
		var t := Combat.pick_target(car, 360.0, 35.0)
		if t:
			locked = t
	car.aim_target = locked
	# low armour nag
	var worst := 1.0
	for s in Car.SIDES:
		worst = minf(worst, car.armor_frac(s))
	if car.health_frac() < 0.35 or worst <= 0.0:
		if not _low_warned:
			_low_warned = true
			Audio.bark("lowarmor", 1.0)
	elif car.health_frac() > 0.6:
		_low_warned = false

func _unhandled_input(event: InputEvent) -> void:
	if not car or car.dead or level.get("input_locked") == true:
		return
	if event.is_action_pressed("cycle_special"):
		car.cycle_special()
	elif event.is_action_pressed("horn"):
		Audio.play_at("horn", car.global_position, 2.0)
	elif event.is_action_pressed("target_next"):
		_cycle(1)
	elif event.is_action_pressed("target_prev"):
		_cycle(-1)

func _cycle(dir: int) -> void:
	var list: Array = []
	for n in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("targets"):
		if n.get("dead") == true:
			continue
		if n.global_position.distance_to(car.global_position) < 450.0:
			list.append(n)
	if list.is_empty():
		return
	var fwd := car.forward()
	list.sort_custom(func(a, b):
		var ta: Vector3 = a.global_position - car.global_position
		var tb: Vector3 = b.global_position - car.global_position
		return atan2(ta.x * fwd.z - ta.z * fwd.x, ta.dot(fwd)) < atan2(tb.x * fwd.z - tb.z * fwd.x, tb.dot(fwd)))
	var i := list.find(locked)
	i = (i + dir + list.size()) % list.size() if i >= 0 else 0
	locked = list[i]
	manual_lock = true
	Audio.ui("ui_move")
