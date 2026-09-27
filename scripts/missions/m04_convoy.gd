extends MissionBase
## Mission 4 -- Glory Wagon. Escort Preacher's convoy from Gold Creek to the Boneyard.

var truck: Car
var hearse: Car
var _warned := false

func setup() -> void:
	player_start = p(-2215, -250)
	player_yaw = yaw_to(player_start, p(-1900, 0))

func run() -> void:
	var route := road("goldcreek", Vector2(-2300, -300), Vector2(-700, 950))
	truck = spawn("supply", route[6], yaw_to(route[6], route[12]), Defs.Team.PLAYER, "path", {"name": "Supply Truck"})
	hearse = spawn("hearse", route[16], yaw_to(route[16], route[22]), Defs.Team.PLAYER, "escort", {"name": "Glory Wagon", "skill": 0.8, "barks": "preacher"})
	var tai := Level.ai_of(truck)
	tai.set_path(route, 13.0)
	tai.hold = true
	var hai := Level.ai_of(hearse)
	hai.leader = truck
	hai.leader_offset = Vector3(0, 0, -18)
	hai.guard_radius = 110.0
	hai.hold = true
	protect(truck, "The supply truck was destroyed.")
	protect(hearse, "Preacher's Glory Wagon was destroyed.")
	truck.damaged.connect(_on_truck_hurt)
	pickup("repair", p(-1500, 330))
	pickup("ammo", p(-1050, 790))
	if not Game.skip_cinematics:
		cinematic_start()
		orbit_shot(hearse, 11.0, 2.5, 2.4, 3.8, 18.0)
		for id in ["m4_preacher_01", "m4_deacon_01", "m4_preacher_02"]:
			if level.skip_requested:
				break
			await say(id)
		cinematic_end()
	else:
		sayn("m4_preacher_02")
	tai.hold = false
	hai.hold = false
	objective("escort", "Escort Preacher's convoy to the Boneyard")
	tai.arrived.connect(func(_c): _arrived = true)
	# wave 1: ahead in the pass
	await wait(14.0)
	var w1 := _wave(["raider", "raider", "raider"], Vector2(-1650, 180), Vector2(-2000, -120))
	sayn("m4_legion_01")
	await wait(3.0)
	sayn("m4_preacher_03")
	await wait_until(func(): return alive(w1) == 0 or truck.global_position.distance_to(p(-1520, 300)) < 90.0)
	# wave 2: pincer at the canyon
	var w2 := _wave(["raider", "hauler"], Vector2(-2050, -170), Vector2(-1520, 300))
	w2.append_array(_wave(["jeep", "jeep"], Vector2(-1250, 560), Vector2(-1520, 300)))
	sayn("m4_preacher_05")
	await wait_until(func(): return truck.global_position.distance_to(p(-1000, 800)) < 160.0 or _arrived)
	sayn("m4_rosa_01")
	# wave 3: off the lakebed
	var w3: Array = []
	for i in 2:
		var c := spawn("bruiser", p(-850 + i * 30, 1250), PI, Defs.Team.ENEMY, "attack", {"skill": 0.6})
		Level.ai_of(c).focus = truck
		w3.append(c)
	await wait_until(func(): return _arrived)
	complete("escort")
	for c in w1 + w2 + w3:
		var ai := Level.ai_of(c)
		if ai and is_instance_valid(c) and not c.dead:
			ai.hold = true
	await say_all(["m4_preacher_06", "m4_rosa_02"])
	win()

var _arrived := false

func _wave(keys: Array, at: Vector2, toward: Vector2) -> Array:
	var out: Array = []
	for i in keys.size():
		var c := spawn_road(keys[i], "goldcreek", at, toward, Defs.Team.ENEMY, "attack", {"skill": 0.6}, (i % 2) * 4.0 - 2.0)
		var dir := (p(toward.x, toward.y) - c.global_position).normalized()
		c.global_position -= dir * i * 12.0
		var ai := Level.ai_of(c)
		ai.aggro = 500.0
		if i % 2 == 0:
			ai.focus = truck
		out.append(c)
	return out

func _on_truck_hurt(c: Car, _a: float, _s: Node) -> void:
	if not _warned and c.health_frac() < 0.6:
		_warned = true
		sayn("m4_preacher_04")
