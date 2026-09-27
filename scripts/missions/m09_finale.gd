extends MissionBase
## Mission 9 -- Atomic Dawn. Vale's Silver Duchess runs for the airstrip while
## the Army lights up Yucca Flat.

var vale: Car
var _escaped := false
var _taunt := false

func setup() -> void:
	player_start = p(1480, -680)
	player_yaw = yaw_to(player_start, p(1900, -600))

func run() -> void:
	var r := road("mercury", Vector2(1920, -560), Vector2(1950, 1250))
	var loop: Array = [Vector2(1700, 1450), Vector2(1420, 1250), Vector2(1450, 850), Vector2(1800, 700), Vector2(2250, 950), Vector2(2430, 1400), Vector2(2330, 1800), Vector2(2210, 2000), Vector2(2280, 2110)]
	var route := PackedVector3Array(r)
	for q in loop:
		route.append(p(q.x, q.y))
	# densify the cross-country legs so the AI follows smoothly
	var dense := PackedVector3Array()
	for i in route.size() - 1:
		var a := route[i]
		var b := route[i + 1]
		var n := maxi(1, int(a.distance_to(b) / 20.0))
		for k in n:
			var q := a.lerp(b, float(k) / n)
			dense.append(p(q.x, q.z))
	dense.append(route[route.size() - 1])
	vale = spawn("duchess", dense[0], yaw_to(dense[0], dense[4]), Defs.Team.ENEMY, "path", {"name": "Augustus Vale", "boss": true, "skill": 0.85})
	var vai := Level.ai_of(vale)
	vai.set_path(dense, 24.0)
	vai.fire_range = 160.0
	vai.arrived.connect(func(_c): _escaped = true)
	vale.damaged.connect(_on_vale_hurt)
	level.hud.track(vale)
	var enemies: Array = []
	for i in 2:
		var c := spawn("bruiser", dense[0] + Vector3(-5 + i * 10, 0, 22), 0.0, Defs.Team.ENEMY, "escort", {"skill": 0.75})
		var ai := Level.ai_of(c)
		ai.leader = vale
		ai.leader_offset = Vector3(-6.0 + i * 12.0, 0, 16.0)
		ai.guard_radius = 100.0
		enemies.append(c)
	for i in 3:
		var c := spawn("raider", dense[0] + Vector3(-8 + i * 8, 0, -25), 0.0, Defs.Team.ENEMY, "attack", {"skill": 0.75})
		Level.ai_of(c).aggro = 900.0
		enemies.append(c)
	# friends
	var bessie := spawn("semi", p(2050, 1760), PI * 0.5, Defs.Team.PLAYER, "none", {"name": "Bessie"})
	bessie.invulnerable = true
	var hearse := spawn("hearse", player_start + Vector3(-10, 0, 12), player_yaw, Defs.Team.PLAYER, "attack", {"name": "Glory Wagon", "skill": 0.9, "barks": "preacher"})
	hearse.damage_mult = 0.5
	for pk in [[2030, 100, "repair"], [1990, 900, "ammo"], [1500, 1250, "repair"], [2300, 1200, "repair"], [2400, 1650, "ammo"]]:
		pickup(pk[2], p(pk[0], pk[1]))
	# the test shot, far to the east beyond the ranges
	var blast := AtomicBlast.new()
	blast.level = level
	blast.light = level.env.light
	blast.sky = level.env.sky
	level.add_child(blast)
	blast.global_position = Vector3(10600, 0, -2850)
	await say("m9_control_01")
	await say("m9_vale_01")
	await say("m9_deacon_01")
	sayn("m9_vale_02")
	objective("vale", "Destroy Vale's Silver Duchess before it reaches the airstrip")
	var stage := 0
	var wave_t := t + 55.0
	var boom_t := t + 150.0
	while not vale.dead:
		if _escaped:
			fail("Vale reached his plane. The bomb is gone.")
			return
		if stage == 0 and t > 25.0:
			stage = 1
			sayn("m9_preacher_01")
		if stage == 1 and vale.global_position.distance_to(p(1950, 1300)) < 200.0:
			stage = 2
			sayn("m9_hollis_01")
		if t > boom_t - 62.0 and stage < 3:
			stage = 3
			sayn("m9_control_02")
		if t > boom_t - 6.0 and stage < 4:
			stage = 4
			Audio.stop_voice()
			sayn("m9_control_03")
		if t > boom_t and stage < 5:
			stage = 5
			blast.detonate()
			_after_flash()
		if t > wave_t:
			wave_t = t + 50.0
			for i in 3:
				var key: String = ["raider", "jeep", "bruiser"][i]
				var ang := randf() * TAU
				var c := spawn(key, level.player.global_position + Vector3(cos(ang), 0, sin(ang)) * 260.0, ang + PI, Defs.Team.ENEMY, "attack", {"skill": 0.75})
				Level.ai_of(c).aggro = 900.0
				enemies.append(c)
		await tick
	complete("vale")
	for c in enemies:
		var ai := Level.ai_of(c)
		if ai and is_instance_valid(c) and not c.dead:
			ai.hold = true
	await say("m9_vale_04")
	await wait(1.5)
	await say_all(["m9_deacon_03", "m9_miriam_01", "m9_rosa_02"])
	if stage < 5:
		blast.detonate()
		await wait(9.0)
	win()

func _after_flash() -> void:
	await wait(1.2)
	await say("m9_rosa_01")
	await say("m9_deacon_02")

func _on_vale_hurt(c: Car, _a: float, _s: Node) -> void:
	if not _taunt and c.health_frac() < 0.6:
		_taunt = true
		sayn("m9_vale_03")
