extends MissionBase
## Mission 7 -- The Silver Queen. Storm the mine and escort Hollis out.

var bessie: Car
var hearse: Car
var _warned := false
var _arrived := false

func setup() -> void:
	player_start = p(1500, -1080)
	player_yaw = yaw_to(player_start, p(1650, -1450))

func run() -> void:
	var center := p(1700, -2150)
	var gate_p := p(1670, -2044)
	var gyaw := yaw_to(gate_p, center)
	var gate := structure("gate", gate_p, gyaw)
	var right := Vector3(-cos(gyaw), 0, sin(gyaw))
	var towers: Array = [structure("guard_tower", gate_p + right * 17.0, gyaw), structure("guard_tower", gate_p - right * 17.0, gyaw)]
	var guards: Array = []
	for s in [[1700, -2100, "raider"], [1720, -2130, "hauler"], [1680, -2170, "raider"], [1740, -2090, "jeep"], [1650, -2110, "hauler"]]:
		var c := spawn(s[2], p(s[0], s[1]), randf() * TAU, Defs.Team.ENEMY, "idle", {"skill": 0.65})
		Level.ai_of(c).aggro = 200.0
		guards.append(c)
	hearse = spawn("hearse", player_start + Vector3(8, 0, 14), player_yaw, Defs.Team.PLAYER, "escort", {"name": "Glory Wagon", "skill": 0.85, "barks": "preacher"})
	var hai := Level.ai_of(hearse)
	hai.leader = level.player
	hai.leader_offset = Vector3(7, 0, 14)
	hai.guard_radius = 140.0
	hearse.damage_mult = 0.6
	pickup("repair", p(1620, -1600))
	pickup("ammo", p(1600, -1820))
	await say("m7_preacher_01")
	await say("m7_deacon_01")
	objective("towers", "Knock down the guard towers (2)")
	objective("gate", "Break down the mine gate")
	var yelled := false
	while not (towers[0].dead and towers[1].dead and gate.dead):
		if not yelled and dist_to_player(gate) < 220.0:
			yelled = true
			sayn("m7_legion_01")
		if towers[0].dead and towers[1].dead:
			complete("towers")
		await tick
	complete("towers")
	complete("gate")
	await wait(1.0)
	await say("m7_hollis_01")
	await say("m7_deacon_02")
	await say("m7_hollis_02")
	var r1 := road("mine", Vector2(1700, -2150), Vector2(1450, -700))
	var r2 := road("mercury", Vector2(1450, -700), Vector2(400, -760))
	var shed := p(1684, -2128)
	var route := join([PackedVector3Array([shed, p(1680, -2095)]), r1, r2])
	bessie = spawn("semi", shed, yaw_to(shed, center + Vector3(0, 0, 60)), Defs.Team.PLAYER, "path", {"name": "Hollis (Bessie)"})
	var bai := Level.ai_of(bessie)
	bai.set_path(route, 16.0)
	bai.path_i = 0
	bai.shoot_on_path = false
	bessie.damage_mult = 0.8
	protect(bessie, "Hollis didn't make it.")
	bessie.damaged.connect(_on_hurt)
	bai.arrived.connect(func(_c): _arrived = true)
	hai.leader = bessie
	hai.leader_offset = Vector3(0, 0, -20)
	objective("escort", "Escort Hollis's rig out to the Mercury road")
	var w1: Array = []
	for i in 3:
		var c := spawn("raider", p(1800 + i * 12, -2230), PI, Defs.Team.ENEMY, "attack", {"skill": 0.65})
		Level.ai_of(c).focus = bessie
		Level.ai_of(c).aggro = 800.0
		w1.append(c)
	await wait(14.0)
	await say("m7_vale_01")
	await wait_until(func(): return bessie.global_position.distance_to(p(1450, -700)) < 260.0 or _arrived)
	var w2: Array = []
	for i in 4:
		var key: String = ["bruiser", "raider", "bruiser", "jeep"][i]
		var c := spawn_road(key, "mercury", Vector2(1850, -610), Vector2(1450, -700), Defs.Team.ENEMY, "attack", {"skill": 0.7}, (i % 2) * 4.0 - 2.0)
		c.global_position += Vector3(i * 12.0, 0, 0)
		var ai := Level.ai_of(c)
		ai.aggro = 900.0
		if i % 2 == 0:
			ai.focus = bessie
		w2.append(c)
	await wait_until(func(): return _arrived)
	complete("escort")
	for c in guards + w1 + w2:
		var ai := Level.ai_of(c)
		if ai and is_instance_valid(c):
			ai.hold = true
	await say_all(["m7_hollis_04", "m7_deacon_03", "m7_hollis_05", "m7_miriam_01"])
	win()

func _on_hurt(c: Car, _a: float, _s: Node) -> void:
	if not _warned and c.health_frac() < 0.6:
		_warned = true
		sayn("m7_hollis_03")
