class_name AtomicBlast
extends Node3D
## A distant atomic test, built from several hundred soft smoke billboards so
## it reads as a real cloud rather than a set of solid balls:
##   * blinding flash that lights the sky and the land,
##   * a white-hot fireball that rises and cools through yellow, orange and red,
##   * a toroidal cap whose smoke rolls in a vortex (up the middle, out over
##     the top, down the outside) with a glowing core that slowly dies,
##   * a narrow stem sucking dust up from a spreading base surge,
##   * a brief condensation (Wilson) ring, then the rumble and shock wave.
## Sizes are real-world scale (the cap climbs to ~7 km), so place it 10+ km away.

const N_CAP := 190
const N_DOME := 60
const N_STEM := 110
const N_SKIRT := 70
const N_RING := 40
const N_GLOW := 46

var level: Node
var time_scale := 1.0
var light: DirectionalLight3D
var sky: ShaderMaterial

var _t := 0.0
var _live := false
var _smoke: MultiMesh
var _glow: MultiMesh
var _p: Array = []       # per smoke puff: [kind, a, b, c, size, shade, frame, rot]
var _g: Array = []       # per glow puff:  [a, b, c, size]
var _buf := PackedFloat32Array()
var _gbuf := PackedFloat32Array()
var _order: Array = []
var _sound_done := false
var _wave_done := false
var _light_e := 1.0
var _light_c := Color.WHITE
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	visible = false
	_rng.seed = 1951
	_smoke = _make_mm(N_CAP + N_DOME + N_STEM + N_SKIRT + N_RING, "blend_mix")
	_glow = _make_mm(N_GLOW, "blend_add")
	for i in N_CAP:
		# u: around the vertical axis, v: around the torus tube, r: depth into the tube
		_p.append(["cap", _rng.randf() * TAU, _rng.randf() * TAU, sqrt(_rng.randf()), _rng.randf_range(0.75, 1.15), _rng.randf_range(0.85, 1.1), [0, 6, 0, 8][_rng.randi() % 4], _rng.randf() * TAU])
	for i in N_DOME:
		_p.append(["dome", _rng.randf() * TAU, _rng.randf_range(0.0, 1.0), _rng.randf(), _rng.randf_range(0.7, 1.0), _rng.randf_range(0.9, 1.1), [0, 6][_rng.randi() % 2], _rng.randf() * TAU])
	for i in N_STEM:
		_p.append(["stem", _rng.randf() * TAU, float(i) / N_STEM, _rng.randf(), _rng.randf_range(0.8, 1.2), _rng.randf_range(0.8, 1.05), [0, 6][_rng.randi() % 2], _rng.randf() * TAU])
	for i in N_SKIRT:
		_p.append(["skirt", _rng.randf() * TAU, _rng.randf(), _rng.randf(), _rng.randf_range(0.7, 1.3), _rng.randf_range(0.75, 0.95), 6, _rng.randf() * TAU])
	for i in N_RING:
		_p.append(["ring", TAU * i / N_RING + _rng.randf() * 0.1, _rng.randf(), _rng.randf(), _rng.randf_range(0.8, 1.2), 1.0, 8, _rng.randf() * TAU])
	for i in N_GLOW:
		_g.append([_rng.randf() * TAU, _rng.randf() * TAU, sqrt(_rng.randf()), _rng.randf_range(0.7, 1.2)])
	_buf.resize(_p.size() * 20)
	_gbuf.resize(_g.size() * 20)
	for i in _p.size():
		_order.append(i)

func _make_mm(count: int, blend: String) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = count
	mm.visible_instance_count = 0
	var sh := Shader.new()
	sh.code = Lib.PARTICLE_SHADER.replace("BLEND_MODE", blend + ", fog_disabled")
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("atlas", Lib.tex.particles)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = m
	mi.custom_aabb = AABB(Vector3(-20000, -2000, -20000), Vector3(40000, 30000, 40000))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mm

func detonate() -> void:
	visible = true
	_live = true
	_t = 0.0
	if light:
		_light_e = light.light_energy
		_light_c = light.light_color
	var hud = level.get("hud") if level else null
	if hud and hud.has_method("whiteout"):
		hud.whiteout(1.6)
	InputSetup.rumble(0.4, 0.2, 1.5)

# ------------------------------------------------------------------- shape

## Everything below is a function of time since detonation (seconds).
func _cap_height(t: float) -> float:
	return 500.0 + 6800.0 * (1.0 - exp(-t / 16.0))

func _cap_radius(t: float) -> float:
	return 350.0 + 1500.0 * (1.0 - exp(-t / 11.0))

## 1 = white-hot, 0 = cold smoke.
func _heat(t: float) -> float:
	return clampf(1.0 - t / 16.0, 0.0, 1.0)

func _stem_radius(y01: float, R: float) -> float:
	# flared foot, narrow waist, widening into the cap
	var foot := exp(-y01 * 14.0) * 0.55
	var neck := smoothstep(0.7, 1.0, y01) * 0.35
	return R * (0.16 + foot + neck)

func _smoke_color(shade: float, height01: float, heat: float, core: float) -> Color:
	# dawn-lit dust cloud: salmon highlights up top, dusky brown underneath
	var top := Color(1.0, 0.82, 0.72)
	var bottom := Color(0.42, 0.32, 0.3)
	var c := bottom.lerp(top, clampf(height01, 0.0, 1.0)) * shade
	# fire showing through the young cloud, strongest in the core
	var fire := Color(1.0, 0.45, 0.12).lerp(Color(1.0, 0.85, 0.5), heat)
	c = c.lerp(fire * 1.4, clampf(heat * (0.35 + core * 0.9), 0.0, 1.0))
	return c

func _process(dt: float) -> void:
	if not _live:
		return
	_t += dt * time_scale
	var t := _t
	var flash := clampf(1.0 - t / 3.0, 0.0, 1.0)
	if sky:
		sky.set_shader_parameter("flash", flash * flash * 3.0)
	if light:
		light.light_energy = _light_e + flash * 6.0
		light.light_color = _light_c.lerp(Color(1, 1, 1), flash)
	var H := _cap_height(t)
	var R := _cap_radius(t)
	var heat := _heat(t)
	# early on the fireball is a ball; it flattens into a torus over ~6 s
	var torus := smoothstep(1.5, 7.0, t)
	var tube := R * lerpf(0.9, 0.5, torus)
	var major := R * lerpf(0.05, 0.8, torus)
	var roll := t * 0.35
	var stem_top := H - tube * 0.7
	var stem_on := smoothstep(1.0, 5.0, t)
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else global_position + Vector3(0, 0, 10000)
	var inv := global_transform.affine_inverse()
	var cam_local := inv * cam_pos
	var pos := PackedVector3Array()
	pos.resize(_p.size())
	var cols := PackedColorArray()
	cols.resize(_p.size())
	var sizes := PackedFloat32Array()
	sizes.resize(_p.size())
	for i in _p.size():
		var q: Array = _p[i]
		var kind: String = q[0]
		var u: float = q[1]
		var p := Vector3.ZERO
		var size := 1.0
		var col := Color.WHITE
		var alpha := 1.0
		match kind:
			"cap":
				var v: float = q[2] - roll
				var rr: float = tube * (0.25 + 0.75 * q[3])
				var ring := major + rr * cos(v)
				p = Vector3(cos(u) * ring, H + rr * sin(v) * 0.62, sin(u) * ring)
				size = tube * 0.95 * q[4]
				var hn := clampf((p.y - (H - tube)) / (tube * 2.0), 0.0, 1.0)
				col = _smoke_color(q[5], hn, heat, 1.0 - q[3])
			"dome":
				var el: float = q[2] * PI * 0.5
				var rad: float = (major + tube) * 0.85
				p = Vector3(cos(u) * cos(el) * rad, H + tube * 0.2 + sin(el) * tube * 0.65, sin(u) * cos(el) * rad)
				size = tube * 0.9 * q[4]
				col = _smoke_color(q[5], 0.85 + q[2] * 0.15, heat * 0.8, 0.2)
				alpha = torus
			"stem":
				# material flows up the stem and loops back
				var y01: float = fmod(float(q[2]) + t * 0.02, 1.0)
				var r := _stem_radius(y01, R) * (0.4 + 0.6 * float(q[3]))
				var sway := sin(y01 * 6.0 + u) * R * 0.03
				p = Vector3(cos(u) * r + sway, y01 * stem_top, sin(u) * r)
				size = maxf(_stem_radius(y01, R) * 1.5, 220.0) * q[4]
				col = _smoke_color(q[5], 0.25 + y01 * 0.5, heat * y01, 0.0)
				alpha = stem_on * smoothstep(0.0, 0.06, y01) * (1.0 - smoothstep(0.93, 1.0, y01) * 0.5)
			"skirt":
				var spread := 900.0 + 2600.0 * (1.0 - exp(-t / 14.0))
				var rr2: float = spread * (0.35 + 0.65 * float(q[2]))
				p = Vector3(cos(u) * rr2, 80.0 + float(q[3]) * 380.0, sin(u) * rr2)
				size = 650.0 * q[4]
				col = Color(0.62, 0.5, 0.44) * q[5]
				alpha = smoothstep(2.0, 6.0, t) * 0.9
			"ring":
				var ry := H * 0.62
				var rr3 := R * (1.5 + t * 0.06)
				p = Vector3(cos(u) * rr3, ry + (float(q[2]) - 0.5) * 120.0, sin(u) * rr3)
				size = 950.0 * q[4]
				col = Color(1.0, 0.97, 0.95)
				alpha = smoothstep(3.0, 5.0, t) * (1.0 - smoothstep(9.0, 15.0, t)) * 0.3
		pos[i] = p
		cols[i] = Color(col.r, col.g, col.b, alpha)
		sizes[i] = size
	# back-to-front so the alpha blending layers correctly
	_order.sort_custom(func(a, b): return pos[a].distance_squared_to(cam_local) > pos[b].distance_squared_to(cam_local))
	var n := 0
	for idx in _order:
		var c: Color = cols[idx]
		if c.a <= 0.01:
			continue
		_write(_buf, n, pos[idx], sizes[idx], c, _p[idx][6], _p[idx][7] + t * 0.05)
		n += 1
	_smoke.buffer = _buf
	_smoke.visible_instance_count = n
	# glowing fireball / hot core
	var gn := 0
	var glow_a := clampf(1.0 - t / 14.0, 0.0, 1.0)
	if glow_a > 0.0:
		var ball := clampf(1.0 - t / 4.0, 0.0, 1.0)
		for gi in _g.size():
			var gq: Array = _g[gi]
			var rr: float = tube * 0.8 * gq[2]
			var ring2 := major + rr * cos(gq[1] - roll)
			var p2 := Vector3(cos(gq[0]) * ring2, H + rr * sin(gq[1] - roll) * 0.6, sin(gq[0]) * ring2)
			var hot := Color(1.0, 0.95, 0.8).lerp(Color(1.0, 0.45, 0.1), 1.0 - heat)
			hot.a = glow_a * (0.55 + ball * 0.45)
			_write(_gbuf, gn, p2, tube * 1.1 * gq[3] * (1.0 + ball), hot, 8, 0.0)
			gn += 1
	_glow.buffer = _gbuf
	_glow.visible_instance_count = gn
	# sound + shock wave, compressed from reality for drama
	if not _sound_done and t > 4.0:
		_sound_done = true
		Audio.play("atomic_blast", 4.0)
		var fx := Fx.get_fx()
		if fx:
			fx.shake.emit(0.6, cam_pos)
		InputSetup.rumble(0.8, 0.9, 3.0)
	if not _wave_done and t > 7.0:
		_wave_done = true
		var fx2 := Fx.get_fx()
		var pl = level.get("player") if level else null
		if fx2 and pl:
			fx2.shake.emit(1.5, pl.global_position)
			for k in 30:
				var off := Vector3(randf_range(-60, 60), 0, randf_range(-60, 60))
				fx2.dust(pl.global_position + off, 4.0, Color(0.8, 0.7, 0.55))

func _write(buf: PackedFloat32Array, i: int, p: Vector3, s: float, c: Color, frame: int, rot: float) -> void:
	var o := i * 20
	buf[o] = s
	buf[o + 1] = 0.0
	buf[o + 2] = 0.0
	buf[o + 3] = p.x
	buf[o + 4] = 0.0
	buf[o + 5] = s
	buf[o + 6] = 0.0
	buf[o + 7] = p.y
	buf[o + 8] = 0.0
	buf[o + 9] = 0.0
	buf[o + 10] = s
	buf[o + 11] = p.z
	buf[o + 12] = c.r
	buf[o + 13] = c.g
	buf[o + 14] = c.b
	buf[o + 15] = c.a
	buf[o + 16] = frame
	buf[o + 17] = rot
	buf[o + 18] = 0.0
	buf[o + 19] = 0.0
