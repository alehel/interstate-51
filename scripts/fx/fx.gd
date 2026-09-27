class_name Fx
extends Node3D
## One-stop particle system. Two big MultiMeshes (additive + alpha-blended)
## of camera-facing billboards sampling a 4x4 atlas, plus a tracer MultiMesh
## of axial billboards. Everything is simulated in script and uploaded as a
## single buffer per frame -- cheap even with hundreds of cars fighting.

signal shake(amount: float, pos: Vector3)

static var _inst: Fx

const F_SMOKE := 0
const F_SPARK := 1
const F_FIRE := 2
const F_FLARE := 3
const F_DEBRIS := 4
const F_RING := 5
const F_DUST := 6
const F_STAR := 7
const F_SOFT := 8
const F_PAPER := 9

class Pool:
	var cap := 0
	var n := 0
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	var life := PackedFloat32Array()
	var maxl := PackedFloat32Array()
	var s0 := PackedFloat32Array()
	var s1 := PackedFloat32Array()
	var c0 := PackedColorArray()
	var c1 := PackedColorArray()
	var frame := PackedFloat32Array()
	var rot := PackedFloat32Array()
	var rotv := PackedFloat32Array()
	var grav := PackedFloat32Array()
	var drag := PackedFloat32Array()
	var buf := PackedFloat32Array()
	var mm: MultiMesh

	func _init(c: int) -> void:
		cap = c
		for a in [pos, vel]:
			a.resize(c)
		for a in [life, maxl, s0, s1, frame, rot, rotv, grav, drag]:
			a.resize(c)
		c0.resize(c)
		c1.resize(c)
		buf.resize(c * 20)

var _add: Pool
var _mix: Pool
var _tr_mm: MultiMesh
var _tracers: Array = []     # [from, dir, len, speed, dist, maxdist, color, width]
var _tr_buf := PackedFloat32Array()
var _lights: Array[OmniLight3D] = []
var _light_t: Array[float] = []
var _emitters: Array = []    # [node or pos, kind, rate, acc, until, size]
var _time := 0.0

static func get_fx() -> Fx:
	if is_instance_valid(_inst):
		return _inst
	return null

func _ready() -> void:
	_inst = self
	_add = _make_pool(2200, "fx_add")
	_mix = _make_pool(2200, "fx_mix")
	_tr_mm = MultiMesh.new()
	_tr_mm.transform_format = MultiMesh.TRANSFORM_3D
	_tr_mm.use_colors = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_tr_mm.mesh = q
	_tr_mm.instance_count = 600
	_tr_mm.visible_instance_count = 0
	_tr_buf.resize(600 * 16)
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = _tr_mm
	tmi.material_override = Lib.mat("tracer")
	tmi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tmi)
	for i in 10:
		var l := OmniLight3D.new()
		l.visible = false
		l.omni_range = 18.0
		l.light_energy = 0.0
		add_child(l)
		_lights.append(l)
		_light_t.append(0.0)

func _exit_tree() -> void:
	if _inst == self:
		_inst = null

func _make_pool(cap: int, mat: String) -> Pool:
	var p := Pool.new(cap)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = cap
	mm.visible_instance_count = 0
	p.mm = mm
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = Lib.mat(mat)
	mi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return p

# ------------------------------------------------------------------ emit

func emit(additive: bool, p: Vector3, v: Vector3, life: float, size0: float, size1: float, col0: Color, col1: Color, frame: int, gravity: float = 0.0, drag: float = 0.0, spin: float = 0.0) -> void:
	var pl := _add if additive else _mix
	var i := pl.n
	if i >= pl.cap:
		i = randi() % pl.cap   # overwrite a random one when full
	else:
		pl.n += 1
	pl.pos[i] = p
	pl.vel[i] = v
	pl.life[i] = life
	pl.maxl[i] = life
	pl.s0[i] = size0
	pl.s1[i] = size1
	pl.c0[i] = col0
	pl.c1[i] = col1
	pl.frame[i] = frame
	pl.rot[i] = randf() * TAU
	pl.rotv[i] = spin * randf_range(-1.0, 1.0)
	pl.grav[i] = gravity
	pl.drag[i] = drag

func _rv(s: float) -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * s

func sparks(p: Vector3, n: Vector3, count: int = 6, col := Color(1.0, 0.8, 0.4)) -> void:
	for k in count:
		var v := (n * randf_range(2, 8) + _rv(6.0))
		emit(true, p, v, randf_range(0.15, 0.45), 0.35, 0.05, col, Color(1, 0.3, 0.1, 0), F_SOFT, 12.0, 1.0)
	emit(true, p, Vector3.ZERO, 0.08, 1.2, 0.4, Color(1, 0.9, 0.6, 0.9), Color(1, 0.5, 0.2, 0), F_STAR)

func dust(p: Vector3, size: float = 1.0, col := Color(0.75, 0.65, 0.5)) -> void:
	emit(false, p + _rv(0.5 * size), _rv(1.0) + Vector3(0, 0.8, 0), randf_range(1.0, 2.2), size, size * 3.5, Color(col.r, col.g, col.b, 0.55), Color(col.r, col.g, col.b, 0.0), F_DUST, -0.3, 1.2, 0.5)

func smoke(p: Vector3, size: float = 1.0, dark: float = 0.2, v := Vector3.ZERO) -> void:
	var c := Color(dark, dark * 0.95, dark * 0.9, 0.7)
	emit(false, p + _rv(0.3), v + Vector3(0, randf_range(1.5, 3.0), 0) + _rv(0.6), randf_range(2.0, 3.5), size, size * 4.0, c, Color(dark * 1.4, dark * 1.4, dark * 1.4, 0.0), F_SMOKE, -0.4, 0.6, 0.6)

func fire(p: Vector3, size: float = 1.0, v := Vector3.ZERO) -> void:
	emit(true, p + _rv(0.3 * size), v + Vector3(0, randf_range(2.0, 4.0), 0) + _rv(0.8), randf_range(0.35, 0.7), size, size * 0.3, Color(1.0, 0.75, 0.3, 0.9), Color(0.9, 0.2, 0.05, 0.0), F_FIRE, -2.0, 1.0, 2.0)

func muzzle(p: Vector3, dir: Vector3, size: float = 0.7) -> void:
	emit(true, p + dir * 0.2, dir * 3.0, 0.06, size, size * 1.4, Color(1, 0.85, 0.5, 1), Color(1, 0.5, 0.1, 0), F_STAR, 0, 0, 0)
	if randf() < 0.3:
		emit(false, p + dir * 0.4, dir * 2.0 + Vector3(0, 0.5, 0), 0.6, 0.4, 1.5, Color(0.6, 0.6, 0.6, 0.3), Color(0.6, 0.6, 0.6, 0), F_SMOKE, -0.2, 1.0)

func debris(p: Vector3, v: Vector3, count: int = 8, col := Color(0.2, 0.18, 0.16)) -> void:
	for k in count:
		emit(false, p, v + _rv(9.0) + Vector3(0, randf_range(4, 12), 0), randf_range(1.2, 2.5), randf_range(0.25, 0.7), 0.2, col, Color(col.r, col.g, col.b, 0.8), F_DEBRIS, 18.0, 0.2, 10.0)

func tracer(from: Vector3, to: Vector3, col: Color, width: float = 0.12, speed: float = 600.0) -> void:
	var d := to - from
	var dist := d.length()
	if dist < 0.5:
		return
	if _tracers.size() >= 590:
		_tracers.pop_front()
	_tracers.append([from, d / dist, minf(dist, 12.0), speed, 0.0, dist, col, width])

func flash(p: Vector3, col: Color, energy: float, range_: float, dur: float) -> void:
	for i in _lights.size():
		if not _lights[i].visible:
			var l := _lights[i]
			l.visible = true
			l.global_position = p
			l.light_color = col
			l.light_energy = energy
			l.omni_range = range_
			_light_t[i] = dur
			l.set_meta("e0", energy)
			l.set_meta("d0", dur)
			return

func explosion(p: Vector3, size: float = 1.0, sound: bool = true) -> void:
	for k in int(14 * size) + 4:
		emit(true, p + _rv(1.2 * size), _rv(6.0 * size) + Vector3(0, 4.0 * size, 0), randf_range(0.5, 1.0), 2.5 * size, 4.5 * size, Color(1, 0.8, 0.45, 1), Color(0.8, 0.2, 0.05, 0), F_FIRE, -2.0, 2.0, 1.5)
	for k in int(10 * size) + 3:
		emit(false, p + _rv(1.5 * size), _rv(3.0 * size) + Vector3(0, randf_range(2, 6) * size, 0), randf_range(2.5, 4.5), 3.0 * size, 9.0 * size, Color(0.15, 0.13, 0.12, 0.85), Color(0.35, 0.33, 0.32, 0.0), F_SMOKE, -0.6, 0.8, 0.8)
	for k in int(16 * size):
		emit(true, p, _rv(22.0 * size) + Vector3(0, 8.0, 0), randf_range(0.4, 1.0), 0.5, 0.1, Color(1, 0.85, 0.5), Color(1, 0.4, 0.1, 0), F_SOFT, 14.0, 0.5)
	emit(true, p + Vector3(0, 0.5, 0), Vector3.ZERO, 0.35, 2.0 * size, 14.0 * size, Color(1, 0.9, 0.7, 0.6), Color(1, 0.6, 0.3, 0), F_RING)
	emit(true, p, Vector3.ZERO, 0.15, 8.0 * size, 12.0 * size, Color(1, 0.95, 0.8, 1), Color(1, 0.6, 0.2, 0), F_FLARE)
	debris(p, Vector3.ZERO, int(8 * size))
	flash(p + Vector3(0, 2, 0), Color(1.0, 0.7, 0.4), 8.0 * size, 30.0 * size, 0.6)
	if sound:
		Audio.play_at("explosion_big" if size >= 1.0 else "explosion_small", p, 2.0 if size >= 1.0 else 0.0, 1.0, 25.0 * maxf(size, 0.6))
	shake.emit(1.2 * size, p)

## Continuous emitter attached to a node (burning wrecks, smoking cars).
func attach(node: Node3D, kind: String, rate: float, duration: float, size: float = 1.0, offset := Vector3.ZERO) -> void:
	_emitters.append([node, kind, rate, 0.0, _time + duration, size, offset])

func _process(delta: float) -> void:
	_time += delta
	delta = minf(delta, 0.05)
	# emitters
	var i := 0
	while i < _emitters.size():
		var e: Array = _emitters[i]
		if _time > e[4] or not is_instance_valid(e[0]):
			_emitters.remove_at(i)
			continue
		e[3] += e[2] * delta
		var n: Node3D = e[0]
		var base: Vector3 = n.global_transform * e[6]
		while e[3] >= 1.0:
			e[3] -= 1.0
			match e[1]:
				"fire":
					fire(base, e[5])
					if randf() < 0.5:
						smoke(base + Vector3(0, 1.5, 0), e[5] * 1.3, 0.12)
				"smoke":
					smoke(base, e[5], 0.25)
				"blacksmoke":
					smoke(base, e[5], 0.08)
				"steam":
					smoke(base, e[5] * 0.6, 0.8)
		i += 1
	_update_pool(_add, delta)
	_update_pool(_mix, delta)
	_update_tracers(delta)
	for k in _lights.size():
		if _lights[k].visible:
			_light_t[k] -= delta
			var d0: float = _lights[k].get_meta("d0", 0.5)
			_lights[k].light_energy = float(_lights[k].get_meta("e0", 1.0)) * clampf(_light_t[k] / d0, 0, 1)
			if _light_t[k] <= 0.0:
				_lights[k].visible = false

func _update_pool(pl: Pool, dt: float) -> void:
	var i := 0
	while i < pl.n:
		pl.life[i] -= dt
		if pl.life[i] <= 0.0:
			var last := pl.n - 1
			if i != last:
				pl.pos[i] = pl.pos[last]
				pl.vel[i] = pl.vel[last]
				pl.life[i] = pl.life[last]
				pl.maxl[i] = pl.maxl[last]
				pl.s0[i] = pl.s0[last]
				pl.s1[i] = pl.s1[last]
				pl.c0[i] = pl.c0[last]
				pl.c1[i] = pl.c1[last]
				pl.frame[i] = pl.frame[last]
				pl.rot[i] = pl.rot[last]
				pl.rotv[i] = pl.rotv[last]
				pl.grav[i] = pl.grav[last]
				pl.drag[i] = pl.drag[last]
			pl.n -= 1
			continue
		var v := pl.vel[i]
		v.y -= pl.grav[i] * dt
		v *= maxf(0.0, 1.0 - pl.drag[i] * dt)
		pl.vel[i] = v
		pl.pos[i] += v * dt
		pl.rot[i] += pl.rotv[i] * dt
		var t := 1.0 - pl.life[i] / pl.maxl[i]
		var s := lerpf(pl.s0[i], pl.s1[i], t)
		var c := pl.c0[i].lerp(pl.c1[i], t)
		var p := pl.pos[i]
		var o := i * 20
		pl.buf[o] = s
		pl.buf[o + 1] = 0.0
		pl.buf[o + 2] = 0.0
		pl.buf[o + 3] = p.x
		pl.buf[o + 4] = 0.0
		pl.buf[o + 5] = s
		pl.buf[o + 6] = 0.0
		pl.buf[o + 7] = p.y
		pl.buf[o + 8] = 0.0
		pl.buf[o + 9] = 0.0
		pl.buf[o + 10] = s
		pl.buf[o + 11] = p.z
		pl.buf[o + 12] = c.r
		pl.buf[o + 13] = c.g
		pl.buf[o + 14] = c.b
		pl.buf[o + 15] = c.a
		pl.buf[o + 16] = pl.frame[i]
		pl.buf[o + 17] = pl.rot[i]
		pl.buf[o + 18] = 0.0
		pl.buf[o + 19] = 0.0
		i += 1
	pl.mm.buffer = pl.buf
	pl.mm.visible_instance_count = pl.n

func _update_tracers(dt: float) -> void:
	var i := 0
	var n := 0
	while i < _tracers.size():
		var t: Array = _tracers[i]
		t[4] += t[3] * dt
		if t[4] - t[2] > t[5]:
			_tracers.remove_at(i)
			continue
		var head: float = minf(t[4], t[5])
		var tail: float = maxf(0.0, t[4] - t[2])
		var from: Vector3 = t[0]
		var dir: Vector3 = t[1]
		var a := from + dir * tail
		var axis := dir * maxf(head - tail, 0.01)
		var w: float = t[7]
		var c: Color = t[6]
		var o := n * 16
		# basis: x = width (scale only used for its length), y = axis, z = unused
		_tr_buf[o] = w
		_tr_buf[o + 1] = axis.x
		_tr_buf[o + 2] = 0.0
		_tr_buf[o + 3] = a.x
		_tr_buf[o + 4] = 0.0
		_tr_buf[o + 5] = axis.y
		_tr_buf[o + 6] = 0.0
		_tr_buf[o + 7] = a.y
		_tr_buf[o + 8] = 0.0
		_tr_buf[o + 9] = axis.z
		_tr_buf[o + 10] = w
		_tr_buf[o + 11] = a.z
		_tr_buf[o + 12] = c.r
		_tr_buf[o + 13] = c.g
		_tr_buf[o + 14] = c.b
		_tr_buf[o + 15] = c.a
		n += 1
		i += 1
	_tr_mm.buffer = _tr_buf
	_tr_mm.visible_instance_count = n
