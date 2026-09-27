extends MissionBase
## Mission 5 -- Chain Reaction. Save Dr. Holt from her pursuers, escort her home.

var wagon: Car
var _warned := false
var _arrived := false

func setup() -> void:
	player_start = p(-120, -760)
	player_yaw = yaw_to(player_start, p(-160, -1000))

func run() -> void:
	var r1 := road("us95", Vector2(-200, -2330), Vector2(150, 300))
	var r2 := road("boneyard", Vector2(150, 300), Vector2(-700, 950))
	var route := join([r1, r2])
	wagon = spawn("wagon", route[0], yaw_to(route[0], route[4]), Defs.Team.PLAYER, "path", {"name": "Dr. Holt"})
	var wai := Level.ai_of(wagon)
	wai.set_path(route, 23.0)
	wai.shoot_on_path = false
	wagon.damage_mult = 0.7
	protect(wagon, "Dr. Holt was killed.")
	wagon.damaged.connect(_on_hurt)
	wai.arrived.connect(func(_c): _arrived = true)
	var chasers: Array = []
	for i in 3:
		var c := spawn("raider", route[0] + Vector3(0, 0, -25.0 - i * 12.0), PI, Defs.Team.ENEMY, "attack", {"skill": 0.55})
		var ai := Level.ai_of(c)
		ai.focus = wagon
		ai.aggro = 600.0
		chasers.append(c)
	pickup("repair", p(-230, -1300))
	await say("m5_miriam_01")
	await say("m5_deacon_01")
	objective("chasers", "Stop the Legion cars chasing Dr. Holt's wagon")
	sayn("m5_miriam_02")
	await wait(6.0)
	sayn("m5_legion_01")
	hint("%s drops an oil slick - anything behind you loses its grip." % InputSetup.prompt("fire_special"), 7.0)
	await wait_dead(chasers)
	complete("chasers")
	wai.cruise = 18.0
	await say("m5_miriam_04")
	await say("m5_deacon_02")
	objective("escort", "Escort Dr. Holt to the Boneyard")
	await wait_until(func(): return wagon.global_position.distance_to(p(80, 360)) < 150.0 or _arrived)
	var amb: Array = []
	for i in 4:
		var key := "hauler" if i == 0 else "raider"
		var c := spawn(key, p(260 + i * 15, 720 + i * 10), PI * 0.8, Defs.Team.ENEMY, "attack", {"skill": 0.6})
		var ai := Level.ai_of(c)
		ai.aggro = 600.0
		if i % 2 == 1:
			ai.focus = wagon
		amb.append(c)
	sayn("m5_legion_02")
	objective("amb", "Break up the ambush on the Boneyard road")
	await wait_until(func(): return alive(amb) == 0 or _arrived)
	if alive(amb) == 0:
		complete("amb")
	await wait_until(func(): return _arrived)
	await wait_dead(amb)
	complete("amb")
	complete("escort")
	await say_all(["m5_miriam_05", "m5_rosa_01", "m5_miriam_06", "m5_deacon_03", "m5_miriam_07"])
	win()

func _on_hurt(c: Car, _a: float, _s: Node) -> void:
	if not _warned and c.health_frac() < 0.65:
		_warned = true
		sayn("m5_miriam_03")
