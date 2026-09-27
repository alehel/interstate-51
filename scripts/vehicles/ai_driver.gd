class_name AIDriver
extends Node
## Drives a Car: dogfighting (pursuit, lead, strafing, ramming, mines behind),
## road following for convoys/fugitives, escorting a leader, obstacle and
## steep-slope avoidance, and un-sticking.

signal arrived(car: Car)

var car: Car
var mode := "attack"          # idle | attack | path | escort | park
var target: Node3D = null
var path := PackedVector3Array()
var path_i := 0
var path_loop := false
var cruise := 28.0
var leader: Car = null
var leader_offset := Vector3(0, 0, 14)
var aggro := 260.0
var skill := 0.7
var fire_range := 150.0
var rammer := false
var shoot_on_path := true     # turret / guns at targets of opportunity while pathing
var guard_radius := 90.0      # escorts peel off to fight within this radius
var stop_at_end := true
var done := false
var hold := false             # frozen until released (cutscenes, triggers)
var barks := "legion"
var focus: Node3D = null      # preferred target (e.g. the convoy truck)

var _reverse_t := 0.0
var _stuck_t := 0.0
var _avoid := 0.0
var _think := 0.0
var _burst := 0.0
var _burst_on := true
var _special_cd := 2.0
var _retarget := 0.0
var _circle_side := 1.0
var _ray := PhysicsRayQueryParameters3D.new()
var _world: WorldData
var _last_bark := -100.0
var _route := PackedVector3Array()
var _route_i := 0
var _route_t := 0.0

func _ready() -> void:
	car = get_parent()
	_ray.collision_mask = 3
	_ray.exclude = [car.get_rid()]
	_world = Lib.world
	_circle_side = 1.0 if randf() < 0.5 else -1.0
	skill = clampf(skill * Game.difficulty_mult(), 0.2, 1.2)
	_think = randf() * 0.2

func set_path(p: PackedVector3Array, speed: float = -1.0, loop: bool = false) -> void:
	path = p
	path_loop = loop
	mode = "path"
	done = false
	if speed > 0.0:
		cruise = speed
	# start at the nearest point ahead
	var best := 0
	var bd := INF
	for i in p.size():
		var d := p[i].distance_squared_to(car.global_position)
		if d < bd:
			bd = d
			best = i
	path_i = best

func _hostile_group() -> String:
	return "friends" if car.team == Defs.Team.ENEMY else "enemies"

func _find_target(radius: float) -> Node3D:
	if focus and is_instance_valid(focus) and not (focus is Car and focus.dead):
		var lvl := get_tree().current_scene
		var pl = lvl.get("player") if lvl else null
		if pl and pl is Car and pl != car and not pl.dead and pl.global_position.distance_to(car.global_position) < 35.0:
			return pl
		return focus
	var best: Node3D = null
	var bd := radius
	var cands: Array = get_tree().get_nodes_in_group(_hostile_group())
	if car.is_player:
		cands.append_array(get_tree().get_nodes_in_group("targets"))
	for n in cands:
		if n is Car and n.dead:
			continue
		var d: float = n.global_position.distance_to(car.global_position)
		# prefer the player a bit
		if n is Car and n.is_player:
			d *= 0.7
		if d < bd:
			bd = d
			best = n
	return best

func _physics_process(dt: float) -> void:
	if not is_instance_valid(car) or car.dead:
		return
	if hold:
		car.throttle = 0.0
		car.brake = 1.0
		car.steer = 0.0
		car.fire_primary = false
		car.fire_special = false
		return
	_think -= dt
	_special_cd -= dt
	_retarget -= dt
	if target and (not is_instance_valid(target) or (target is Car and target.dead)):
		target = null
	var goal := car.global_position + car.forward() * 20.0
	var want := 0.0
	var fire := false
	var special := false
	match mode:
		"idle", "park":
			if _retarget <= 0.0:
				_retarget = 0.5
				var t := _find_target(aggro)
				if t and mode == "idle":
					target = t
					mode = "attack"
					_bark()
			want = 0.0
		"attack":
			if not target or _retarget <= 0.0:
				_retarget = 2.0
				var t := _find_target(6000.0)
				if t:
					target = t
			if not target:
				want = 0.0
			else:
				var res := _attack_goal(dt)
				goal = res[0]
				want = res[1]
				fire = res[2]
				special = res[3]
		"path":
			if path.is_empty():
				want = 0.0
			else:
				goal = _path_goal()
				want = cruise
				if done and stop_at_end:
					want = 0.0
			if shoot_on_path and _retarget <= 0.0:
				_retarget = 1.0
				target = _find_target(fire_range)
		"escort":
			if not is_instance_valid(leader) or leader.dead:
				mode = "attack"
			else:
				var threat := _find_target(guard_radius)
				if threat and threat.global_position.distance_to(leader.global_position) < guard_radius:
					target = threat
					var res := _attack_goal(dt)
					goal = res[0]
					want = res[1]
					fire = res[2]
				else:
					goal = leader.global_transform * leader_offset + leader.forward() * 10.0
					var d := car.global_position.distance_to(leader.global_transform * leader_offset)
					want = maxf(leader.speed, 0.0) + clampf(d - 5.0, -10.0, 20.0)
	car.aim_target = target
	# turret / opportunistic fire
	if car.turret_weapon and target and target.global_position.distance_to(car.global_position) < fire_range * 1.2:
		fire = true
	if mode == "path" and shoot_on_path and target:
		var to := target.global_position - car.global_position
		var ang := car.forward().angle_to(to)
		if car.turret_weapon == null and ang < 0.2 and to.length() < fire_range:
			fire = true
		if _special_cd <= 0.0:
			for sp in car.specials:
				var k: String = sp.kind()
				if (k == "mine" or k == "oil") and ang > 2.2 and to.length() < 45.0:
					car.special_index = car.specials.find(sp)
					special = true
					_special_cd = randf_range(2.0, 4.0)
				elif k == "rocket" and ang < 0.15 and to.length() < 180.0:
					car.special_index = car.specials.find(sp)
					special = true
					_special_cd = randf_range(3.0, 5.0)
	_drive_to(goal, want, dt)
	# burst fire so the AI isn't a laser
	_burst -= dt
	if _burst <= 0.0:
		_burst_on = not _burst_on
		_burst = randf_range(1.0, 2.2) * (0.6 + skill * 0.6) if _burst_on else randf_range(0.5, 1.4) / (0.5 + skill)
	car.fire_primary = fire and _burst_on
	car.fire_special = special

## When the target is far away over rough ground, drive the road network.
func _nav_goal(tp: Vector3, dt: float) -> Variant:
	_route_t -= dt
	var p := car.global_position
	if p.distance_to(tp) < 240.0 or not _world:
		_route = PackedVector3Array()
		return null
	if _route_t <= 0.0:
		_route_t = 4.0 + randf()
		_route = PackedVector3Array()
		var direct := p.distance_to(tp)
		var r := _world.nav_route(p, tp)
		if r.size() >= 2:
			var len := p.distance_to(r[0]) + r[r.size() - 1].distance_to(tp)
			for i in r.size() - 1:
				len += r[i].distance_to(r[i + 1])
			var blocked := _world.line_blocked(p, tp)
			if blocked or (p.distance_to(r[0]) < 120.0 and len < direct * 1.5):
				_route = r
				# start at the node after the closest one so we never turn back
				var bi := 0
				var bd := INF
				for i in r.size():
					var dd := p.distance_squared_to(r[i])
					if dd < bd:
						bd = dd
						bi = i
				_route_i = mini(bi + 1, r.size() - 1)
	if _route.is_empty():
		return null
	var look := clampf(absf(car.speed) * 0.8, 12.0, 32.0)
	while _route_i < _route.size() - 1 and Vector2(_route[_route_i].x - p.x, _route[_route_i].z - p.z).length() < look:
		_route_i += 1
	if _route_i >= _route.size() - 1:
		_route = PackedVector3Array()
		return null
	return _route[_route_i]

## Returns [goal, speed, fire_guns, fire_special].
func _attack_goal(dt: float) -> Array:
	var nav = _nav_goal(target.global_position, dt)
	if nav != null:
		return [nav, car.top_speed * 0.9, false, false]
	var tp := target.global_position
	var tv := Vector3.ZERO
	if target is RigidBody3D:
		tv = target.linear_velocity
	var to := tp - car.global_position
	var dist := to.length()
	var lead := tp + tv * clampf(dist / 70.0, 0.0, 1.5) * skill
	var fwd := car.forward()
	var ang := fwd.angle_to(to)
	var goal := lead
	var want := car.top_speed
	var fire := false
	var special := false
	if dist < 30.0 and ang > 1.9:
		# target behind and close: extend and swing around; drop a mine
		goal = car.global_position + fwd * 40.0 + car.global_transform.basis.x * _circle_side * 25.0
		want = car.top_speed
		for sp in car.specials:
			if sp.kind() in ["mine", "oil"] and _special_cd <= 0.0:
				car.special_index = car.specials.find(sp)
				special = true
				_special_cd = randf_range(3.0, 6.0)
	elif dist < 14.0 and not rammer:
		# too close: swerve past and come round again (jousting)
		goal = tp + car.global_transform.basis.x * _circle_side * 14.0 + fwd * 10.0
		want = car.top_speed * 0.7
	elif dist < 22.0 and not rammer:
		want = maxf(tv.length() - 2.0, 10.0)
	elif rammer and dist < 40.0:
		goal = tp + tv * 0.3
		want = car.top_speed
	# don't run over the target when shooting from range
	if dist < 60.0 and ang < 0.4 and not rammer:
		want = minf(want, tv.length() + 6.0)
	var aim_ok := ang < deg_to_rad(9.0 + (1.0 - skill) * 4.0)
	if aim_ok and dist < fire_range:
		fire = true
	for sp in car.specials:
		if sp.kind() == "rocket" and _special_cd <= 0.0 and aim_ok and dist > 35.0 and dist < 220.0:
			car.special_index = car.specials.find(sp)
			special = true
			_special_cd = randf_range(2.5, 5.0) / (0.5 + skill)
	if fire and randf() < 0.004:
		_bark()
	return [goal, want, fire, special]

func _bark() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if car.team != Defs.Team.ENEMY or now - _last_bark < 12.0:
		return
	var lvl := get_tree().current_scene
	var p = lvl.get("player") if lvl else null
	if p and p is Car and p.global_position.distance_to(car.global_position) < 160.0:
		_last_bark = now
		Audio.bark(barks, 7.0)

func _path_goal() -> Vector3:
	var p := car.global_position
	var look := clampf(absf(car.speed) * 0.9, 10.0, 34.0)
	# advance the index while we're close to the current point
	while path_i < path.size() - 1 and Vector2(path[path_i].x - p.x, path[path_i].z - p.z).length() < look:
		path_i += 1
	if path_i >= path.size() - 1:
		var endp := path[path.size() - 1]
		if Vector2(endp.x - p.x, endp.z - p.z).length() < 14.0:
			if path_loop:
				path_i = 0
			elif not done:
				done = true
				arrived.emit(car)
	return path[path_i]

func _drive_to(goal: Vector3, want: float, dt: float) -> void:
	var local := car.to_local(goal)
	var ang := atan2(local.x, -local.z)       # + = goal is to the right
	var speed := car.speed
	# reversing out of trouble
	if _reverse_t > 0.0:
		_reverse_t -= dt
		car.throttle = 0.0
		car.brake = 1.0
		car.steer = -signf(ang) if absf(ang) > 0.1 else _circle_side
		car.handbrake = false
		return
	# obstacle avoidance (rays at bumper height)
	if _think <= 0.0:
		_think = 0.12
		_avoid = _avoid_steer()
		_avoid += _slope_steer()
	var steer := clampf(ang * 1.8 + _avoid, -1.0, 1.0)
	# cornering speed
	var corner := clampf(absf(ang) / 1.3, 0.0, 1.0)
	var vmax := lerpf(car.top_speed, 11.0, corner)
	var desired := minf(want, vmax)
	var thr := clampf((desired - speed) * 0.3 + 0.2, 0.0, 1.0) if desired > 0.5 else 0.0
	var brk := 0.0
	if speed > desired + 4.0:
		brk = clampf((speed - desired) * 0.12, 0.0, 1.0)
		thr = 0.0
	if desired <= 0.5 and absf(speed) > 0.5:
		brk = 1.0
	car.handbrake = absf(ang) > 1.25 and speed > 14.0 and mode == "attack"
	car.steer = steer
	car.throttle = thr
	car.brake = brk
	# stuck detection
	if thr > 0.4 and absf(speed) < 1.2:
		_stuck_t += dt
		if _stuck_t > 1.4:
			_stuck_t = 0.0
			_reverse_t = 1.4
	else:
		_stuck_t = maxf(0.0, _stuck_t - dt)

func _avoid_steer() -> float:
	var gt := car.global_transform
	var fwd := -gt.basis.z
	var right := gt.basis.x
	var origin := gt * Vector3(0, 0.9, -car.dims().z * 0.5)
	var len := 8.0 + absf(car.speed) * 0.8
	var space := car.get_world_3d().direct_space_state
	var dists := []
	for a in [-0.4, 0.0, 0.4]:
		var dir := fwd.rotated(Vector3.UP, a)
		_ray.from = origin
		_ray.to = origin + dir * len
		var hit := space.intersect_ray(_ray)
		var d := len
		if not hit.is_empty():
			var col: Object = hit.collider
			var is_goal := col == target and rammer
			var gentle: bool = hit.normal.y > 0.7
			if not is_goal and not gentle:
				d = origin.distance_to(hit.position)
		dists.append(d)
	# dists: [right, centre, left]
	var s := 0.0
	if dists[1] < len:
		s = -1.0 if dists[2] > dists[0] else 1.0
		s *= clampf(1.5 - dists[1] / len, 0.3, 1.5)
	if dists[0] < len * 0.6:
		s -= 0.5
	if dists[2] < len * 0.6:
		s += 0.5
	return s

func _slope_steer() -> float:
	if not _world:
		return 0.0
	var p := car.global_position
	var fwd := car.forward()
	fwd.y = 0
	fwd = fwd.normalized()
	var ahead := p + fwd * 28.0
	var h0 := _world.height(p.x, p.z)
	var h1 := _world.height(ahead.x, ahead.z)
	if (h1 - h0) / 28.0 < 0.38:
		return 0.0
	var l := p + fwd.rotated(Vector3.UP, 0.6) * 28.0
	var r := p + fwd.rotated(Vector3.UP, -0.6) * 28.0
	return 0.8 if _world.height(r.x, r.z) < _world.height(l.x, l.z) else -0.8
