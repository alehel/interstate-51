class_name ChaseCam
extends Camera3D
## Third-person chase camera with a bumper view, look-back, right-stick
## orbit, speed-based FOV and explosion shake. Can be driven by scripted
## cinematic shots instead.

var car: Car
var mode := 0                  # 0 near chase, 1 far chase, 2 bumper
var _yaw := 0.0
var _orbit := 0.0
var _shake := 0.0
var _pos := Vector3.ZERO
var cine_active := false
var cine_from := Transform3D.IDENTITY
var cine_to := Transform3D.IDENTITY
var cine_t := 0.0
var cine_len := 1.0
var cine_follow: Node3D = null
var cine_offset := Vector3.ZERO
var _world: WorldData

const MODES := [
	{"dist": 8.5, "height": 2.9, "look": 1.3},
	{"dist": 14.0, "height": 4.8, "look": 1.6},
]

func _ready() -> void:
	far = 30000.0
	near = 0.15
	fov = 70.0
	_world = Lib.world
	var fx := Fx.get_fx()
	if fx:
		fx.shake.connect(_on_shake)

func _on_shake(amount: float, pos: Vector3) -> void:
	var d := pos.distance_to(global_position)
	_shake = minf(_shake + amount * clampf(1.0 - d / 120.0, 0.0, 1.0), 1.5)

func snap() -> void:
	if car:
		_yaw = atan2(-car.forward().x, -car.forward().z)
		_pos = _target_pos()

func cinematic(from: Transform3D, to: Transform3D, dur: float, follow: Node3D = null) -> void:
	cine_active = true
	cine_from = from
	cine_to = to
	cine_t = 0.0
	cine_len = maxf(dur, 0.01)
	cine_follow = follow

func end_cinematic() -> void:
	cine_active = false
	snap()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera") and not cine_active:
		mode = (mode + 1) % 3
		Audio.ui("ui_move")

func _target_pos() -> Vector3:
	var m: Dictionary = MODES[min(mode, 1)]
	var back := Vector3(sin(_yaw + _orbit), 0, cos(_yaw + _orbit))
	return car.global_position + back * m.dist + Vector3(0, m.height, 0)

func _process(dt: float) -> void:
	if cine_active:
		cine_t += dt
		var t := smoothstep(0.0, 1.0, clampf(cine_t / cine_len, 0.0, 1.0))
		var xf := cine_from.interpolate_with(cine_to, t)
		global_transform = xf
		if cine_follow and is_instance_valid(cine_follow):
			look_at(cine_follow.global_position + Vector3(0, 1.0, 0), Vector3.UP)
		fov = lerpf(fov, 55.0, dt * 2.0)
		_apply_shake(dt)
		return
	if not car or not is_instance_valid(car):
		return
	var fwd := car.forward()
	fwd.y = 0
	if fwd.length() > 0.01:
		var target_yaw := atan2(-fwd.x, -fwd.z)
		var rate := 6.0 if mode != 2 else 30.0
		_yaw = lerp_angle(_yaw, target_yaw, clampf(dt * rate, 0, 1))
	var ox := Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
	_orbit = lerpf(_orbit, ox * PI * 0.75, dt * 5.0)
	var look_back := Input.is_action_pressed("look_back")
	if look_back:
		_orbit = PI
	var spd := absf(car.speed)
	if mode == 2:
		var bxf := car.global_transform
		var d := car.dims()
		var p := bxf * Vector3(0, d.y * 0.72, -d.z * 0.12)
		global_position = p
		var dirv := -bxf.basis.z if not look_back else bxf.basis.z
		look_at(p + dirv.rotated(bxf.basis.y, -_orbit if not look_back else 0.0) * 10.0, bxf.basis.y)
		fov = lerpf(fov, 72.0 + spd * 0.2, dt * 3.0)
		_apply_shake(dt)
		return
	var m: Dictionary = MODES[mode]
	var want := _target_pos()
	_pos = _pos.lerp(want, clampf(dt * 9.0, 0, 1))
	if _pos.distance_to(want) > 30.0:
		_pos = want
	var p2 := _pos
	if _world:
		var gh := _world.height(p2.x, p2.z) + 1.2
		p2.y = maxf(p2.y, gh)
	global_position = p2
	var ahead := Vector3(-sin(_yaw + _orbit), 0, -cos(_yaw + _orbit))
	look_at(car.global_position + Vector3(0, m.look, 0) + ahead * 4.0, Vector3.UP)
	fov = lerpf(fov, 68.0 + clampf(spd * 0.3, 0.0, 16.0), dt * 3.0)
	_apply_shake(dt)

func _apply_shake(dt: float) -> void:
	if _shake > 0.01:
		var s := _shake * 0.25
		rotate_object_local(Vector3.RIGHT, randf_range(-s, s) * 0.2)
		rotate_object_local(Vector3.UP, randf_range(-s, s) * 0.2)
		global_position += Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s)) * 0.5
		_shake = move_toward(_shake, 0.0, dt * 1.8)
