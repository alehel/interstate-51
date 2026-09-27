class_name AtomicBlast
extends Node3D
## A distant atomic test: blinding flash, rising fireball that cools into a
## mushroom cloud with a condensation ring, then the rumble and shock wave.

var _t := 0.0
var _live := false
var _fireball: MeshInstance3D
var _stem: MeshInstance3D
var _cap: Node3D
var _ring: Node3D
var _skirt: MeshInstance3D
var _fb_mat: StandardMaterial3D
var _smoke_mat: StandardMaterial3D
var _cap_mat: StandardMaterial3D
var _sound_done := false
var _wave_done := false
var level: Node
var light: DirectionalLight3D
var sky: ShaderMaterial
var _light_e := 1.0
var _light_c := Color.WHITE

func _mat(col: Color, tex: bool, lit: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if lit else BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.roughness = 1.0
	m.metallic_specular = 0.0
	if lit:
		# soft self-glow so the shadowed side isn't black against the dawn sky
		m.emission_enabled = true
		m.emission = Color(col.r, col.g, col.b) * 0.35
	m.disable_fog = true
	if col.a < 0.99 or not lit:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _sphere(r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 20
	s.rings = 12
	mi.mesh = s
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 5000.0
	return mi

func _ready() -> void:
	visible = false
	_fb_mat = _mat(Color(1.0, 0.95, 0.8, 1.0), false, false)
	_smoke_mat = _mat(Color(0.8, 0.68, 0.62, 1.0), false)
	_cap_mat = _mat(Color(0.9, 0.78, 0.7, 1.0), false)
	_fireball = _sphere(1.0, _fb_mat)
	add_child(_fireball)
	_stem = MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.6
	c.bottom_radius = 1.0
	c.height = 1.0
	c.radial_segments = 16
	_stem.mesh = c
	_stem.material_override = _smoke_mat
	_stem.extra_cull_margin = 5000.0
	add_child(_stem)
	_cap = Node3D.new()
	add_child(_cap)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1951
	for k in 26:
		var a := TAU * k / 13.0 + rng.randf() * 0.3
		var r := 0.8 if k < 13 else 0.45
		var s := _sphere(1.0, _cap_mat)
		s.position = Vector3(cos(a) * r, rng.randf_range(-0.15, 0.25) + (0.2 if k >= 13 else 0.0), sin(a) * r)
		s.scale = Vector3.ONE * rng.randf_range(0.4, 0.65)
		_cap.add_child(s)
	var top := _sphere(1.0, _cap_mat)
	top.position = Vector3(0, 0.35, 0)
	top.scale = Vector3(1.0, 0.7, 1.0)
	_cap.add_child(top)
	_ring = Node3D.new()
	add_child(_ring)
	var ring_mat := _mat(Color(0.97, 0.96, 0.95, 0.0), false)
	_ring.set_meta("mat", ring_mat)
	for k in 16:
		var a := TAU * k / 16.0
		var s := _sphere(1.0, ring_mat)
		s.position = Vector3(cos(a), 0, sin(a))
		s.scale = Vector3(0.2, 0.04, 0.2)
		_ring.add_child(s)
	for k in 6:
		var lump := _sphere(1.0, _smoke_mat)
		lump.scale = Vector3(0.9, 0.18, 0.9)
		lump.position = Vector3(0, (k + 0.5) / 6.0, 0)
		_stem.add_child(lump)
	_skirt = _sphere(1.0, _smoke_mat)
	_skirt.scale = Vector3(1, 0.15, 1)
	add_child(_skirt)

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

func _process(dt: float) -> void:
	if not _live:
		return
	_t += dt
	var t := _t
	# flash on sky and sun light
	var flash := clampf(1.0 - t / 3.0, 0.0, 1.0)
	if sky:
		sky.set_shader_parameter("flash", flash * flash * 3.0)
	if light:
		light.light_energy = _light_e + flash * 6.0
		light.light_color = _light_c.lerp(Color(1, 1, 1), flash)
	# fireball rises and cools
	var rise := 150.0 + 1500.0 * (1.0 - exp(-t / 9.0))
	var fr := 220.0 + 260.0 * (1.0 - exp(-t / 4.0))
	_fireball.position = Vector3(0, rise, 0)
	_fireball.scale = Vector3.ONE * fr
	var heat := clampf(1.0 - t / 10.0, 0.0, 1.0)
	_fb_mat.albedo_color = Color(0.55, 0.42, 0.38).lerp(Color(1.0, 0.75, 0.35), heat).lerp(Color(1, 1, 0.9), clampf(1.0 - t / 1.5, 0, 1))
	_fb_mat.albedo_color.a = 1.0
	# cap forms around the fireball
	var cap_s := clampf((t - 2.0) / 14.0, 0.0, 1.0)
	_cap.visible = t > 2.0
	_cap.position = _fireball.position + Vector3(0, fr * 0.2, 0)
	_cap.scale = Vector3(fr * (1.0 + cap_s * 1.2), fr * (0.7 + cap_s * 0.5), fr * (1.0 + cap_s * 1.2))
	_cap_mat.albedo_color = Color(0.9, 0.78, 0.7, 1.0).lerp(Color(1.0, 0.62, 0.35, 1.0), heat * 0.7)
	# stem
	var stem_h := maxf(rise - fr * 0.5, 1.0)
	_stem.scale = Vector3(90.0 + t * 4.0, stem_h, 90.0 + t * 4.0)
	_stem.position = Vector3(0, stem_h * 0.5, 0)
	_stem.visible = t > 1.2
	# condensation ring
	var rm: StandardMaterial3D = _ring.get_meta("mat")
	var ra := clampf((t - 3.0) / 2.0, 0.0, 1.0) * clampf((16.0 - t) / 5.0, 0.0, 1.0)
	rm.albedo_color.a = ra * 0.35
	_ring.position = Vector3(0, rise * 0.7, 0)
	_ring.scale = Vector3.ONE * (fr * 1.6 + t * 40.0)
	# base surge
	_skirt.scale = Vector3(300.0 + t * 90.0, 60.0 + t * 6.0, 300.0 + t * 90.0)
	# sound + shock wave, compressed from reality for drama
	if not _sound_done and t > 4.0:
		_sound_done = true
		Audio.play("atomic_blast", 4.0)
		var fx := Fx.get_fx()
		if fx:
			fx.shake.emit(0.6, global_position)
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
