class_name Car
extends RigidBody3D
## Arcade raycast vehicle shared by the player and the AI.
## Four suspension rays with spring/damper forces, per-tyre grip with a
## friction circle, rear-wheel drive with a three-speed box, handbrake
## slides, directional armour (front/rear/left/right + chassis) and
## ram damage derived from sudden velocity changes.

signal destroyed(car: Car)
signal damaged(car: Car, amount: float, source: Node)

const SIDES := ["front", "rear", "left", "right"]

var def_key := ""
var def: Dictionary = {}
var team := 1
var display_name := ""
var is_player := false
var boss := false

# controls (written by PlayerInput / AIDriver)
var throttle := 0.0
var brake := 0.0
var steer := 0.0
var handbrake := false
var fire_primary := false
var fire_special := false
var aim_target: Node3D = null

# damage model
var armor := {"front": 100.0, "rear": 100.0, "left": 100.0, "right": 100.0}
var armor_max := 100.0
var chassis := 100.0
var chassis_max := 100.0
var dead := false
var invulnerable := false
var damage_mult := 1.0
var last_attacker: Node = null
var burn_time := 0.0
var burn_source: Node = null

# weapons
var guns: Array = []
var specials: Array = []
var special_index := 0
var turret: Node3D = null
var turret_weapon: Weapon = null

# physics
var wheels: Array = []
var wheel_radius := 0.36
var suspension := 0.5
var spring_k := 18000.0
var damp_c := 1800.0
var power := 15000.0
var top_speed := 50.0
var grip := 1.0
var grip_mod := 1.0
var oil_time := 0.0
var max_steer := 0.58
var steer_smooth := 0.0
var speed := 0.0
var rpm := 0.0
var gear := 1
var grounded := 0
var slip := 0.0
var upside_time := 0.0
var stuck_time := 0.0
var _prev_vel := Vector3.ZERO
var _ray := PhysicsRayQueryParameters3D.new()
var _dims := Vector3(2, 1.4, 5)
var _body_mesh: MeshInstance3D
var _shadow: MeshInstance3D
var _engine: AudioStreamPlayer3D
var _skid: AudioStreamPlayer3D
var _siren: AudioStreamPlayer3D
var _siren_light: OmniLight3D
var _headlight: SpotLight3D
var _smoke_acc := 0.0
var _hit_flash := 0.0
var _breakables: Breakables
var _world: WorldData
var _ram_cooldown := 0.0
var stats := {"kills": 0, "damage_taken": 0.0, "shots": 0}

func setup(key: String, team_: int, opts: Dictionary = {}) -> void:
	def_key = key
	def = Defs.CARS[key].duplicate()
	for k in opts:
		def[k] = opts[k]
	team = team_
	display_name = opts.get("name", def.name)
	boss = opts.get("boss", false)
	add_to_group("cars")
	add_to_group("damageable")
	if team == Defs.Team.ENEMY:
		add_to_group("enemies")
	elif team == Defs.Team.PLAYER:
		add_to_group("friends")
	var vis := CarBuilder.build(key, opts.get("look", {}))
	_dims = vis.size
	wheel_radius = vis.wheel_radius
	mass = def.mass
	power = def.power * opts.get("power_mult", 1.0)
	top_speed = def.top + opts.get("top_bonus", 0.0)
	grip = def.grip
	var am: float = opts.get("armor_mult", 1.0)
	armor_max = def.armor * am
	chassis_max = def.chassis * am
	for s in SIDES:
		armor[s] = armor_max
	chassis = chassis_max
	spring_k = mass * 12.5
	damp_c = mass * 1.35
	collision_layer = 2
	collision_mask = 3
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.42 if _dims.y < 2.0 else 0.8, 0)
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.9
	linear_damp = 0.0
	continuous_cd = true
	can_sleep = false
	var pm := PhysicsMaterial.new()
	pm.friction = 0.35
	pm.bounce = 0.1
	physics_material_override = pm
	# collision box (clear of the ground)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var clearance := wheel_radius * 0.95
	box.size = Vector3(_dims.x * 0.94, maxf(_dims.y - clearance, 0.6), _dims.z * 0.96)
	cs.shape = box
	cs.position = Vector3(0, clearance + box.size.y * 0.5, 0)
	add_child(cs)
	# visuals
	_body_mesh = MeshInstance3D.new()
	_body_mesh.mesh = vis.body
	_body_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_body_mesh)
	var mount_y := wheel_radius + suspension * 0.6
	for wp in vis.wheels:
		var wm := MeshInstance3D.new()
		wm.mesh = vis.wheel
		wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pivot := Node3D.new()
		add_child(pivot)
		pivot.add_child(wm)
		if wp.x < 0:
			wm.rotation.y = PI
		pivot.position = wp
		wheels.append({
			"mount": Vector3(wp.x, mount_y, wp.z), "pivot": pivot, "mesh": wm,
			"front": wp.z < 0, "comp": 0.0, "hit": false, "spin": 0.0, "left": wp.x < 0,
			"contact": Vector3.ZERO, "normal": Vector3.UP,
		})
	for wp in vis.extra_wheels:
		var wm := MeshInstance3D.new()
		wm.mesh = vis.wheel
		wm.position = wp
		if wp.x < 0:
			wm.rotation.y = PI
		add_child(wm)
	_shadow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(_dims.x * 1.5, _dims.z * 1.25)
	q.orientation = PlaneMesh.FACE_Y
	_shadow.mesh = q
	_shadow.material_override = Lib.mat("blob")
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	add_child(_shadow)
	# weapons
	var wlist: Array = opts.get("weapons", def.get("weapons", []))
	var muzzles: Array = vis.gun_muzzles
	for wkey in wlist:
		var wd: Dictionary = Defs.WEAPONS[wkey]
		if wd.slot == "gun":
			var w := Weapon.new(wkey, self)
			w.mounts = muzzles if not muzzles.is_empty() else [Vector3(0, 1.0, -_dims.z * 0.5 - 0.3)]
			if guns.is_empty():
				guns.append(w)
			else:
				# a second gun of the same type just adds a mount; otherwise new weapon
				var same := false
				for g in guns:
					if g.key == wkey:
						same = true
				if not same:
					guns.append(w)
		else:
			var w := Weapon.new(wkey, self)
			if wd.kind == "rocket":
				w.mounts = [vis.special + Vector3(0, 0.15, -0.6)]
				var pod := MeshInstance3D.new()
				pod.mesh = CarBuilder.rocket_pod_mesh()
				pod.position = vis.special
				add_child(pod)
			else:
				w.mounts = [Vector3(0, 0.5, _dims.z * 0.5 + 0.6)]
			specials.append(w)
	if def.has("turret"):
		turret = Node3D.new()
		turret.position = vis.turret
		add_child(turret)
		var tm := MeshInstance3D.new()
		tm.mesh = CarBuilder.turret_mesh(def.turret == "mg50")
		turret.add_child(tm)
		turret_weapon = Weapon.new(def.turret, self)
		turret_weapon.turret = turret
		turret_weapon.mounts = [Vector3(-0.12, 0.47, -1.3), Vector3(0.12, 0.47, -1.3)]
	# sounds
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = Audio.looped("engine_heavy_loop" if mass > 3000.0 else "engine_loop")
	_engine.bus = "SFX"
	_engine.unit_size = 6.0 if not is_player else 12.0
	_engine.max_distance = 180.0
	_engine.volume_db = -6.0
	add_child(_engine)
	_ray.collision_mask = 3
	_ray.exclude = [get_rid()]
	_ray.hit_back_faces = false
	if def.style == "police":
		_siren_light = OmniLight3D.new()
		_siren_light.light_color = Color(1, 0.1, 0.05)
		_siren_light.omni_range = 12.0
		_siren_light.position = Vector3(0, _dims.y + 0.3, 0)
		add_child(_siren_light)

func _ready() -> void:
	if _engine and _engine.stream:
		_engine.play(randf() * 0.5)

var _flares: Array = []

func _flare(pos: Vector3, col: Color, size: float) -> void:
	var sp := Sprite3D.new()
	sp.texture = Lib.tex.flare
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.transparent = true
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sp.modulate = col
	sp.pixel_size = size / 64.0
	sp.position = pos
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = Lib.tex.flare
	m.albedo_color = col
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.disable_fog = true
	sp.material_override = m
	add_child(sp)
	_flares.append(sp)

func enable_headlights(on: bool) -> void:
	if on and _flares.is_empty():
		var vis := CarBuilder.build(def_key)
		for h in vis.head:
			_flare(h + Vector3(0, 0, -0.12), Color(1.0, 0.9, 0.65, 0.9), 1.6)
		for tl in vis.tail:
			_flare(tl + Vector3(0, 0, 0.1), Color(1.0, 0.15, 0.08, 0.8), 0.7)
	elif not on:
		for f in _flares:
			f.queue_free()
		_flares.clear()
	if on and not _headlight:
		_headlight = SpotLight3D.new()
		_headlight.light_color = Color(1.0, 0.92, 0.75)
		_headlight.light_energy = 4.0 if is_player else 2.5
		_headlight.spot_range = 70.0 if is_player else 45.0
		_headlight.spot_angle = 32.0
		_headlight.spot_attenuation = 0.8
		_headlight.position = Vector3(0, 0.9, -_dims.z * 0.5)
		_headlight.rotation_degrees = Vector3(-6, 0, 0)
		add_child(_headlight)
	elif not on and _headlight:
		_headlight.queue_free()
		_headlight = null

func enable_siren(on: bool) -> void:
	if on and not _siren:
		_siren = AudioStreamPlayer3D.new()
		_siren.stream = Audio.looped("siren_loop")
		_siren.bus = "SFX"
		_siren.unit_size = 10.0
		_siren.max_distance = 300.0
		_siren.volume_db = -8.0
		add_child(_siren)
		_siren.play(randf() * 2.0)
	elif not on and _siren:
		_siren.queue_free()
		_siren = null

## Put the car on the ground already settled on its suspension (no drop),
## aligned to the slope, optionally already rolling forward.
func place(p: Vector3, yaw: float, spd: float = 0.0) -> void:
	var w: WorldData = Lib.world
	var h := p.y
	var n := Vector3.UP
	if w:
		h = w.height(p.x, p.z)
		n = w.normal(p.x, p.z)
	var b := Basis(Vector3.UP, yaw)
	var x := (b.x - n * b.x.dot(n)).normalized()
	var z := x.cross(n).normalized()
	global_transform = Transform3D(Basis(x, n, z), Vector3(p.x, h + 0.02, p.z))
	var comp := mass * 9.8 / 4.0 / spring_k
	for wh in wheels:
		wh.comp = comp
		(wh.pivot as Node3D).position.y = wh.mount.y - (suspension - comp)
	linear_velocity = -global_transform.basis.z * spd
	angular_velocity = Vector3.ZERO
	_prev_vel = linear_velocity

func forward() -> Vector3:
	return -global_transform.basis.z

func dims() -> Vector3:
	return _dims

func health_frac() -> float:
	return clampf(chassis / chassis_max, 0.0, 1.0)

func armor_frac(side: String) -> float:
	return clampf(armor[side] / armor_max, 0.0, 1.0) if armor_max > 0 else 0.0

func current_special() -> Weapon:
	if specials.is_empty():
		return null
	return specials[special_index % specials.size()]

func cycle_special() -> void:
	if specials.size() > 1:
		special_index = (special_index + 1) % specials.size()
		Audio.ui("ui_move")

# ---------------------------------------------------------------- physics

func _physics_process(dt: float) -> void:
	if not _world:
		_world = Lib.world
		var lvl := get_tree().current_scene
		if lvl and lvl.has_node("World/Breakables"):
			_breakables = lvl.get_node("World/Breakables")
	var gt := global_transform
	var up := gt.basis.y
	var fwd := -gt.basis.z
	var com := gt * center_of_mass
	speed = linear_velocity.dot(fwd)
	var aspeed := absf(speed)
	# input shaping
	var st := 0.0 if dead else steer
	steer_smooth = move_toward(steer_smooth, st, dt * (5.0 if absf(st) > absf(steer_smooth) else 7.0))
	var speed_factor := clampf(aspeed / top_speed, 0.0, 1.0)
	var steer_ang := steer_smooth * max_steer * lerpf(1.0, 0.32, speed_factor)
	var thr := 0.0 if dead else throttle
	var brk := 0.0 if dead else brake
	var hb := handbrake and not dead
	if oil_time > 0.0:
		oil_time -= dt
		grip_mod = 0.22
	else:
		grip_mod = move_toward(grip_mod, 1.0, dt * 2.0)
	# engine / gearbox (visual + audio)
	var ratio := aspeed / top_speed
	gear = 1 if ratio < 0.3 else (2 if ratio < 0.62 else 3)
	var lo: float = [0.0, 0.0, 0.3, 0.62][gear]
	var hi: float = [0.0, 0.3, 0.62, 1.0][gear]
	var target_rpm := clampf((ratio - lo) / (hi - lo), 0.0, 1.0)
	if grounded == 0 or hb:
		target_rpm = thr
	rpm = lerpf(rpm, target_rpm * 0.8 + thr * 0.2, dt * 8.0)
	# drive force
	var drive := 0.0
	if thr > 0.01:
		var curve := clampf(1.0 - pow(ratio, 2.4), 0.0, 1.0) if speed >= 0.0 else 1.0
		drive = power * thr * (0.35 + 0.65 * curve)
		if speed < 0.0:
			drive += power * 0.5 * thr   # help stop reversing
	var braking := 0.0
	if brk > 0.01:
		if speed > 1.5 or speed < -16.0:
			braking = mass * 9.0 * brk
		else:
			var rcurve := clampf(1.0 - pow(maxf(-speed, 0.0) / 14.0, 2.0), 0.0, 1.0)
			drive -= power * 0.55 * brk * rcurve
	var per_mass := mass * 0.25
	grounded = 0
	slip = 0.0
	for w in wheels:
		var mount: Vector3 = gt * w.mount
		var down := -up
		_ray.from = mount
		_ray.to = mount + down * (suspension + wheel_radius)
		var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
		var pivot: Node3D = w.pivot
		if hit.is_empty():
			w.hit = false
			w.comp = 0.0
			pivot.position.y = lerpf(pivot.position.y, w.mount.y - suspension, dt * 10.0)
			continue
		grounded += 1
		w.hit = true
		var dist := mount.distance_to(hit.position)
		var comp: float = suspension + wheel_radius - dist
		var comp_v: float = (comp - w.comp) / dt
		w.comp = comp
		var n: Vector3 = hit.normal
		w.contact = hit.position
		w.normal = n
		var fs := maxf(0.0, spring_k * comp + damp_c * comp_v)
		fs = minf(fs, mass * 9.8 * 3.0)
		apply_force(up * fs, hit.position - global_position)
		# tyre frame
		var wf := fwd
		if w.front:
			wf = fwd.rotated(up, -steer_ang)
		wf = (wf - n * wf.dot(n)).normalized()
		var right := wf.cross(n).normalized()
		var pv := linear_velocity + angular_velocity.cross(hit.position - com)
		var v_long := pv.dot(wf)
		var v_lat := pv.dot(right)
		var mu := 1.55 * grip * grip_mod
		var rear: bool = not w.front
		if hb and rear:
			mu *= 0.42
		var load := maxf(fs, mass * 9.8 * 0.1)
		var max_f := mu * load
		var f_lat := -v_lat * per_mass * 16.0
		var f_long := 0.0
		if rear:
			f_long += drive * 0.5
		if braking > 0.0:
			f_long -= signf(v_long) * braking * 0.25
		if hb and rear:
			f_long -= signf(v_long) * minf(absf(v_long) * per_mass * 4.0, mass * 3.0)
		f_long -= v_long * 12.0   # rolling resistance
		if thr < 0.01 and brk < 0.01:
			f_long -= v_long * mass * 0.03
		var total := Vector2(f_long, f_lat)
		var tl := total.length()
		if tl > max_f:
			total *= max_f / tl
			slip = maxf(slip, clampf((tl - max_f) / max_f, 0.0, 1.0))
		slip = maxf(slip, clampf(absf(v_lat) / 8.0, 0.0, 1.0) if aspeed > 6.0 else 0.0)
		var lift := up * 0.35
		apply_force(wf * total.x + right * total.y, hit.position + lift - global_position)
		# visuals
		pivot.position.y = w.mount.y - (dist - wheel_radius)
		if w.front:
			pivot.rotation.y = -steer_ang
		w.spin += v_long / wheel_radius * dt
		pivot.rotation.x = -w.spin if not w.left else -w.spin
	# arcade yaw assist: lets cars carve tighter lines at speed than raw tyre grip allows
	if grounded >= 2 and aspeed > 4.0 and absf(steer_smooth) > 0.05 and not hb:
		var target_yaw := -steer_smooth * lerpf(1.5, 0.75, speed_factor) * signf(speed)
		var cur_yaw := angular_velocity.dot(up)
		var k := clampf(aspeed / 12.0, 0.0, 1.0)
		apply_torque(up * (target_yaw - cur_yaw) * mass * 3.0 * k)
	# aerodynamic drag
	var v := linear_velocity
	apply_central_force(-v * v.length() * 0.35)
	# airborne / upside-down handling
	if grounded == 0:
		apply_torque(up.cross(Vector3.UP) * mass * 2.0 - angular_velocity * mass * 0.3)
	var tilt := up.dot(Vector3.UP)
	if tilt < 0.3 and aspeed < 4.0:
		upside_time += dt
		apply_torque(up.cross(Vector3.UP).normalized() * mass * 6.0 if up.cross(Vector3.UP).length() > 0.01 else fwd * mass * 6.0)
		if upside_time > 2.5 and not dead:
			_right_the_car()
	else:
		upside_time = 0.0
	# ram / collision damage from sudden velocity changes
	_ram_cooldown -= dt
	var dv := linear_velocity - _prev_vel
	dv.y = 0.0
	var dvl := dv.length()
	if dvl > 7.0 and _ram_cooldown <= 0.0:
		var impact_dir := -dv.normalized()
		var p := global_position + impact_dir * _dims.z * 0.4 + Vector3(0, 0.8, 0)
		var dmg := (dvl - 7.0) * 3.0
		_ram_cooldown = 0.25
		take_damage(dmg, p, null, "ram")
		Audio.play_at("crash_heavy" if dvl > 14.0 else "crash_light", p, 0.0, randf_range(0.9, 1.1))
		var fx := Fx.get_fx()
		if fx:
			fx.sparks(p, -impact_dir, 10)
		if is_player:
			InputSetup.rumble(0.6, minf(dvl / 20.0, 1.0), 0.3)
	_prev_vel = linear_velocity
	# safety net against physics blow-ups and falling out of the world
	if linear_velocity.length() > 110.0:
		linear_velocity = linear_velocity.normalized() * 60.0
		angular_velocity = angular_velocity.limit_length(3.0)
	var gp := global_position
	if _world and (absf(gp.x) > WorldData.BOUND + 40.0 or absf(gp.z) > WorldData.BOUND + 40.0 or gp.y < _world.height(gp.x, gp.z) - 6.0 or gp.y > 2500.0):
		if dead:
			queue_free()
			return
		var cx := clampf(gp.x, -WorldData.BOUND + 60.0, WorldData.BOUND - 60.0)
		var cz := clampf(gp.z, -WorldData.BOUND + 60.0, WorldData.BOUND - 60.0)
		global_position = Vector3(cx, _world.height(cx, cz) + 2.0, cz)
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_prev_vel = Vector3.ZERO
	# knock down scenery
	if _breakables and aspeed > 3.0:
		var front_p := global_position + fwd * _dims.z * 0.45
		var hits := _breakables.hit_test(front_p, _dims.x * 0.5, linear_velocity)
		if hits > 0.0:
			linear_velocity *= 1.0 - minf(0.04 * hits * (2000.0 / mass), 0.3)
	# weapons
	if not dead:
		for g in guns:
			g.update(dt, fire_primary)
		var sp := current_special()
		if sp:
			sp.update(dt, fire_special)
		for s2 in specials:
			if s2 != sp:
				s2.update(dt, false)
		if turret_weapon:
			_update_turret(dt)
	# burning damage over time
	if burn_time > 0.0:
		burn_time -= dt
		take_damage(9.0 * dt, global_position + Vector3(0, 1, 0), burn_source, "fire")
		var fx2 := Fx.get_fx()
		if fx2 and randf() < 0.5:
			fx2.fire(global_position + Vector3(randf_range(-0.8, 0.8), 1.2, randf_range(-1.5, 1.5)), 0.9)

func _update_turret(dt: float) -> void:
	var t := aim_target
	if t and is_instance_valid(t):
		var local := turret.global_transform.affine_inverse() * t.global_position
		var yaw := atan2(-local.x, -local.z)
		turret.rotate_y(clampf(yaw, -2.2 * dt, 2.2 * dt))
		turret_weapon.update(dt, fire_primary and absf(yaw) < 0.25)
	else:
		turret_weapon.update(dt, false)

func _right_the_car() -> void:
	upside_time = 0.0
	var p := global_position
	var h := p.y
	if _world:
		h = _world.height(p.x, p.z)
	var yaw := atan2(-forward().x, -forward().z)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, h + 1.2, p.z))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func _process(dt: float) -> void:
	# engine audio
	if _engine:
		if dead:
			_engine.volume_db = move_toward(_engine.volume_db, -60.0, dt * 30.0)
		else:
			# the loop is a real V8 recorded at a low-mid rpm: keep the shift range
			# natural (about 0.7x - 1.9x) so it never turns into a chipmunk
			var heavy := mass > 3000.0
			var base := 0.72 if heavy else 0.78
			var span := 0.8 if heavy else 1.05
			var target := base + rpm * span + (0.08 if gear > 1 else 0.0)
			_engine.pitch_scale = lerpf(_engine.pitch_scale, target, clampf(dt * 10.0, 0.0, 1.0))
			_engine.volume_db = lerpf(-15.0, -3.0, clampf(throttle * 0.8 + rpm * 0.4, 0.0, 1.0)) + (3.0 if is_player else 0.0)
	# tyre squeal
	if slip > 0.35 and grounded > 1 and not dead:
		if not _skid:
			_skid = AudioStreamPlayer3D.new()
			_skid.stream = Audio.looped("skid_loop")
			_skid.bus = "SFX"
			_skid.unit_size = 8.0
			add_child(_skid)
			_skid.play()
		_skid.volume_db = lerpf(-18.0, -4.0, clampf(slip, 0, 1))
		var fx := Fx.get_fx()
		if fx and randf() < 0.35:
			var w: Dictionary = wheels[2 + randi() % 2]
			if w.hit:
				fx.dust(w.contact + Vector3(0, 0.2, 0), 0.7)
	elif _skid:
		_skid.volume_db = move_toward(_skid.volume_db, -60.0, dt * 80.0)
		if _skid.volume_db <= -59.0:
			_skid.queue_free()
			_skid = null
	# dust trail off-road
	if grounded > 0 and absf(speed) > 12.0 and _world and randf() < 0.25 * dt * 60.0 * 0.3:
		if _world.road_dist(global_position.x, global_position.z) > 9.0:
			var fx := Fx.get_fx()
			if fx:
				fx.dust(global_position - forward() * _dims.z * 0.5 + Vector3(0, 0.3, 0), 1.0 + absf(speed) * 0.03)
	# damage smoke
	var hf := health_frac()
	if hf < 0.55 and not dead:
		_smoke_acc += dt * (4.0 if hf > 0.25 else 9.0)
		var fx := Fx.get_fx()
		while _smoke_acc > 1.0 and fx:
			_smoke_acc -= 1.0
			var hood := global_transform * Vector3(0, _dims.y * 0.7, -_dims.z * 0.3)
			fx.smoke(hood, 0.6, 0.45 if hf > 0.25 else 0.1, linear_velocity * 0.6)
			if hf < 0.2 and randf() < 0.4:
				fx.fire(hood, 0.6, linear_velocity * 0.8)
	# blob shadow
	if _shadow:
		var n := 0
		var c := Vector3.ZERO
		var nn := Vector3.ZERO
		for w in wheels:
			if w.hit:
				n += 1
				c += w.contact
				nn += w.normal
		if n > 0:
			_shadow.visible = true
			c /= n
			nn = nn.normalized()
			var yaw := atan2(-forward().x, -forward().z)
			var b := Basis(Vector3.UP, yaw)
			var x := b.x - nn * b.x.dot(nn)
			var z := x.cross(nn)
			_shadow.global_transform = Transform3D(Basis(x.normalized(), nn, z.normalized()), c + nn * 0.06)
		else:
			_shadow.visible = false
	if _siren_light:
		_siren_light.light_energy = 3.0 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.015)) if not dead else 0.0
	if _hit_flash > 0.0:
		_hit_flash -= dt

# ----------------------------------------------------------------- damage

func side_of(world_pos: Vector3) -> String:
	var l := to_local(world_pos)
	var nx := l.x / (_dims.x * 0.5)
	var nz := l.z / (_dims.z * 0.5)
	if absf(nz) >= absf(nx):
		return "front" if nz < 0.0 else "rear"
	return "right" if nx > 0.0 else "left"

func take_damage(amount: float, world_pos: Vector3, source: Node = null, kind: String = "bullet") -> void:
	if dead or amount <= 0.0:
		return
	if invulnerable or (is_player and Game.god_mode):
		return
	amount *= damage_mult
	if source is Car and source != self:
		if source.team == team:
			amount *= 0.2
		if is_player and source.team != team:
			amount *= Game.difficulty_mult()
		elif not is_player and team == Defs.Team.PLAYER and source.team != team:
			# escorts and allies are the player's job to protect: AI fire on them is softened
			amount *= 0.3 * Game.difficulty_mult()
		last_attacker = source
	var side := side_of(world_pos)
	var a: float = armor[side]
	if a > 0.0:
		a -= amount
		var overflow := maxf(0.0, -a)
		armor[side] = maxf(a, 0.0)
		chassis -= overflow + amount * 0.06
	else:
		chassis -= amount
	stats.damage_taken += amount
	_hit_flash = 0.15
	damaged.emit(self, amount, source)
	if chassis <= 0.0:
		die()

func repair(frac: float) -> void:
	for s in SIDES:
		armor[s] = minf(armor_max, armor[s] + armor_max * frac)
	chassis = minf(chassis_max, chassis + chassis_max * frac * 0.7)

func die() -> void:
	if dead:
		return
	dead = true
	chassis = 0.0
	throttle = 0.0
	brake = 0.0
	fire_primary = false
	fire_special = false
	remove_from_group("enemies")
	remove_from_group("friends")
	remove_from_group("damageable")
	var fx := Fx.get_fx()
	var size := 1.0 if mass < 3000.0 else 1.8
	if fx:
		fx.explosion(global_position + Vector3(0, 1.0, 0), size)
		fx.attach(self, "fire", 14.0, 25.0, 1.2, Vector3(0, _dims.y * 0.6, 0))
	var crackle := AudioStreamPlayer3D.new()
	crackle.stream = Audio.looped("wreck_fire_loop")
	crackle.bus = "SFX"
	crackle.unit_size = 7.0
	crackle.max_distance = 120.0
	crackle.volume_db = -6.0
	add_child(crackle)
	crackle.play(randf() * 2.0)
	var tw := crackle.create_tween()
	tw.tween_interval(20.0)
	tw.tween_property(crackle, "volume_db", -60.0, 5.0)
	tw.tween_callback(crackle.queue_free)
	Combat.explode(global_position + Vector3(0, 0.8, 0), 7.0 * size, 25.0, self, false)
	apply_central_impulse(Vector3(randf_range(-1, 1), 5.5, randf_range(-1, 1)) * mass)
	apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * mass * 1.6)
	if _body_mesh:
		var burnt := Lib.mat("burnt")
		for i in _body_mesh.mesh.get_surface_count():
			_body_mesh.set_surface_override_material(i, burnt)
	enable_headlights(false)
	enable_siren(false)
	if turret:
		turret.rotation.z = 0.4
	if is_player:
		InputSetup.rumble(1.0, 1.0, 0.8)
	if last_attacker is Car and is_instance_valid(last_attacker):
		last_attacker.stats.kills += 1
	destroyed.emit(self)
	# wrecks go quiet after a while
	get_tree().create_timer(12.0, false).timeout.connect(func():
		if is_instance_valid(self):
			angular_damp = 4.0
			linear_damp = 1.0)
