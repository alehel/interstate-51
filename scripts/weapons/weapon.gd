class_name Weapon
extends RefCounted
## A weapon mounted on a car (or its turret). Guns are hitscan with visible
## tracers and gentle aim-assist toward the locked target; rockets, mines and
## oil spawn world objects; the flamethrower is a short cone.

var key := ""
var d: Dictionary
var car: Car
var ammo := 0
var ammo_max := 0
var infinite := false
var cooldown := 0.0
var mounts: Array = []
var mount_i := 0
var turret: Node3D = null
var _flame_snd: AudioStreamPlayer3D
var _flaming := false
var _ray := PhysicsRayQueryParameters3D.new()

func _init(k: String, c: Car) -> void:
	key = k
	d = Defs.WEAPONS[k]
	car = c
	ammo = d.ammo
	ammo_max = ammo
	infinite = not c.is_player
	_ray.collision_mask = 3
	_ray.exclude = [c.get_rid()]

func kind() -> String:
	return d.kind

func refill(frac: float) -> void:
	ammo = mini(ammo_max, ammo + int(ceil(ammo_max * frac)))

func has_ammo() -> bool:
	return infinite or ammo > 0

func update(dt: float, trigger: bool) -> void:
	cooldown = maxf(cooldown - dt, -0.05)
	if d.kind == "flame":
		_update_flame_sound(trigger and has_ammo())
	if trigger and cooldown <= 0.0 and has_ammo():
		cooldown += 1.0 / d.rate
		_fire()
		if not infinite:
			ammo -= 1

func _base() -> Transform3D:
	return turret.global_transform if turret else car.global_transform

func _muzzle() -> Vector3:
	var p: Vector3 = mounts[mount_i % mounts.size()] if not mounts.is_empty() else Vector3(0, 1, -2)
	mount_i += 1
	return _base() * p

func _aim_dir(from: Vector3, cone_deg: float) -> Vector3:
	var b := _base().basis
	var dir := -b.z.normalized()
	var t := car.aim_target
	if t and is_instance_valid(t):
		var tp := t.global_position + Vector3(0, 0.8, 0)
		if t is Car:
			tp = t.global_position + Vector3(0, t.dims().y * 0.45, 0)
		var to := tp - from
		if to.length() > 1.0 and dir.angle_to(to) < deg_to_rad(cone_deg):
			dir = to.normalized()
	return dir

func _fire() -> void:
	match d.kind:
		"gun":
			_fire_gun()
		"rocket":
			_fire_rocket()
		"mine":
			_drop_mine()
		"oil":
			_drop_oil()
		"flame":
			_flame_tick()

func _fire_gun() -> void:
	var from := _muzzle()
	var cone := 14.0 if car.is_player else (30.0 if turret else 10.0)
	var dir := _aim_dir(from, cone)
	var spread: float = d.spread * (1.0 if car.is_player else 2.2)
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
	var to: Vector3 = from + dir * float(d.range)
	# start the ray from inside our own (excluded) body so point-blank targets still register
	_ray.from = from - dir * 2.2
	_ray.to = to
	var hit := car.get_world_3d().direct_space_state.intersect_ray(_ray)
	var end := to
	var fx := Fx.get_fx()
	if not hit.is_empty():
		end = hit.position
		var col: Object = hit.collider
		if col and col.has_method("take_damage"):
			col.take_damage(d.dmg, hit.position, car, "bullet")
			if fx:
				fx.sparks(hit.position, hit.normal, 5)
			if randf() < 0.5:
				Audio.play_at("impact_metal_%d" % (1 + randi() % 3), hit.position, -4.0)
		elif fx:
			fx.dust(hit.position + hit.normal * 0.2, 0.5)
			if randf() < 0.15:
				Audio.play_at("ricochet", hit.position, -8.0)
	if fx:
		fx.tracer(from, end, d.tracer, 0.1 if d.dmg < 10.0 else 0.16)
		fx.muzzle(from, dir, 0.6 if d.dmg < 10.0 else 0.9)
	Audio.play_at(d.sound, from, -3.0 if car.is_player else -6.0, randf_range(0.95, 1.05), 14.0)
	car.stats.shots += 1
	if car.is_player:
		InputSetup.rumble(0.15, 0.0, 0.06)

func _fire_rocket() -> void:
	var from := _muzzle()
	var dir := _aim_dir(from, 25.0)
	var r := Rocket.new()
	car.get_tree().current_scene.add_child(r)
	r.launch(from, dir * float(d.speed) + car.linear_velocity * 0.8, car, car.aim_target, d.dmg, d.splash)
	Audio.play_at(d.sound, from, 0.0)
	var fx := Fx.get_fx()
	if fx:
		fx.muzzle(from, dir, 1.2)
		fx.smoke(from, 1.0, 0.6)
	if car.is_player:
		InputSetup.rumble(0.3, 0.2, 0.15)

func _drop_mine() -> void:
	var p := car.global_transform * Vector3(0, 0.4, car.dims().z * 0.5 + 1.0)
	var m := Mine.new()
	car.get_tree().current_scene.add_child(m)
	m.place(p, car, d.dmg, d.splash)
	Audio.play_at(d.sound, p, 0.0)

func _drop_oil() -> void:
	var p := car.global_transform * Vector3(0, 0.4, car.dims().z * 0.5 + 2.0)
	var o := OilSlick.new()
	car.get_tree().current_scene.add_child(o)
	o.place(p, car)
	Audio.play_at(d.sound, p, 0.0)

func _flame_tick() -> void:
	var from := _muzzle()
	var dir := _aim_dir(from, 18.0)
	var fx := Fx.get_fx()
	if fx:
		for k in 3:
			var v := dir * randf_range(20.0, 28.0) + car.linear_velocity + Vector3(randf_range(-1.5, 1.5), randf_range(-0.5, 1.5), randf_range(-1.5, 1.5))
			fx.emit(true, from + dir * 0.5, v, randf_range(0.6, 0.85), 0.6, 3.2, Color(1, 0.8, 0.4, 0.95), Color(0.9, 0.25, 0.05, 0), Fx.F_FIRE, -3.0, 1.4, 3.0)
		if randf() < 0.3:
			fx.smoke(from + dir * 14.0, 1.4, 0.15, car.linear_velocity)
	var range_: float = d.range
	for n in car.get_tree().get_nodes_in_group("damageable"):
		if n == car:
			continue
		var tp: Vector3 = n.global_position + Vector3(0, 0.8, 0)
		var to := tp - from
		var dist := to.length()
		if dist > range_ + 3.0 or dist < 0.1:
			continue
		if dir.angle_to(to) > deg_to_rad(22.0):
			continue
		n.take_damage(float(d.dmg) / float(d.rate), tp, car, "fire")
		if n is Car:
			n.burn_time = 3.0
			n.burn_source = car

func _update_flame_sound(on: bool) -> void:
	if on and not _flaming:
		_flaming = true
		if not _flame_snd:
			_flame_snd = AudioStreamPlayer3D.new()
			_flame_snd.stream = Audio.looped("flame_loop")
			_flame_snd.bus = "SFX"
			_flame_snd.unit_size = 12.0
			car.add_child(_flame_snd)
		_flame_snd.play()
	elif not on and _flaming:
		_flaming = false
		if _flame_snd:
			_flame_snd.stop()
