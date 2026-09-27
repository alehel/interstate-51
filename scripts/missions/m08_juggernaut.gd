extends MissionBase
## Mission 8 -- Broken Arrow. Stop the Juggernaut before Indian Springs.

var jug: Car
var _hit_line := false
var _arrived := false

func setup() -> void:
	player_start = p(1470, -690)
	player_yaw = yaw_to(player_start, p(1900, -600))

func run() -> void:
	var route := road("mercury", Vector2(1920, -560), Vector2(2150, 2100))
	jug = spawn("juggernaut", route[0], yaw_to(route[0], route[5]), Defs.Team.ENEMY, "path", {"name": "The Juggernaut", "boss": true, "skill": 0.75})
	var jai := Level.ai_of(jug)
	jai.set_path(route, 19.0)
	jai.fire_range = 170.0
	jai.arrived.connect(func(_c): _arrived = true)
	jug.damaged.connect(_on_jug_hurt)
	var escorts: Array = []
	for i in 2:
		var c := spawn("bruiser", route[0] + Vector3(-6 + i * 12, 0, -18), 0.0, Defs.Team.ENEMY, "escort", {"skill": 0.7})
		var ai := Level.ai_of(c)
		ai.leader = jug
		ai.leader_offset = Vector3(-6.0 + i * 12.0, 0, -20.0)
		ai.guard_radius = 120.0
		escorts.append(c)
	for i in 2:
		var c := spawn("raider", route[0] + Vector3(-4 + i * 8, 0, 30), 0.0, Defs.Team.ENEMY, "attack", {"skill": 0.7})
		Level.ai_of(c).aggro = 900.0
		escorts.append(c)
	for i in 2:
		var c := spawn("jeep", route[0] + Vector3(-4 + i * 8, 0, 18), 0.0, Defs.Team.ENEMY, "escort", {"skill": 0.7})
		var ai2 := Level.ai_of(c)
		ai2.leader = jug
		ai2.leader_offset = Vector3(-5.0 + i * 10.0, 0, 16.0)
		escorts.append(c)
	pickup("repair", p(2040, 200))
	pickup("ammo", p(1990, 900))
	pickup("repair", p(1980, 1600))
	level.hud.track(jug)
	autoplay_focus(jug)
	await say("m8_rosa_01")
	objective("jug", "Destroy the Juggernaut before it reaches Indian Springs")
	sayn("m8_legion_01")
	var ambushed := false
	var flat_line := false
	while not jug.dead:
		if _arrived:
			fail("The Juggernaut reached the airstrip. The core is gone.")
			return
		if not ambushed and jug.global_position.distance_to(p(2050, 300)) < 200.0:
			ambushed = true
			for i in 3:
				var c := spawn("raider", p(2350 + i * 14, 350 + i * 10), -PI * 0.5, Defs.Team.ENEMY, "attack", {"skill": 0.7})
				Level.ai_of(c).aggro = 900.0
				escorts.append(c)
		if not flat_line and jug.global_position.distance_to(p(1950, 1300)) < 220.0:
			flat_line = true
			sayn("m8_rosa_02")
		await tick
	complete("jug")
	for c in escorts:
		var ai := Level.ai_of(c)
		if ai and is_instance_valid(c) and not c.dead:
			ai.hold = true
	await wait(2.5)
	await say_all(["m8_deacon_01", "m8_vale_01", "m8_miriam_02", "m8_hollis_01", "m8_deacon_02"])
	win()

func _on_jug_hurt(c: Car, _a: float, _s: Node) -> void:
	if not _hit_line and c.armor_frac("rear") < 0.9:
		_hit_line = true
		sayn("m8_miriam_01")
