extends MissionBase
## Mission 6 -- Lights Out at Mercury. Night raid on Vale's freight depot.

var alarm: AudioStreamPlayer3D
var _called := false

func setup() -> void:
	player_start = p(1100, -760)
	player_yaw = yaw_to(player_start, p(1450, -700))

func run() -> void:
	var mast := structure("radio_mast", p(1960, -695), 0.3)
	var tanks: Array = [structure("fuel_tank", p(1868, -522), 0.0), structure("fuel_tank", p(1893, -512), 0.2), structure("fuel_tank", p(1918, -503), 0.4)]
	var shack := structure("shack", p(1842, -640), 1.2)
	structure("crate_stack", p(1880, -600), 0.3)
	var guards: Array = []
	var spots := [[1850, -580, "raider"], [1930, -560, "raider"], [1980, -620, "hauler"], [1900, -650, "raider"], [2000, -560, "bruiser"], [1820, -540, "hauler"]]
	for s in spots:
		var c := spawn(s[2], p(s[0], s[1]), randf() * TAU, Defs.Team.ENEMY, "idle", {"skill": 0.6})
		Level.ai_of(c).aggro = 170.0
		guards.append(c)
	pickup("repair", p(1600, -720))
	pickup("ammo", p(1760, -700))
	await say("m6_rosa_01")
	objective("mast", "Destroy the radio mast before they call for help")
	timer(80.0, "ALARM")
	hint("The Dragon's Breath flamethrower is short range - get close. %s cycles specials." % InputSetup.prompt("cycle_special"), 8.0)
	var noticed := false
	while not mast.dead:
		if not noticed and (dist_to_player(mast) < 230.0 or alive(guards) < guards.size()):
			noticed = true
			sayn("m6_legion_01")
			_alarm_on()
		if timer_left() <= 0.0 and not _called:
			_called = true
			timer_stop()
			sayn("m6_rosa_02b")
			guards.append_array(_reinforce(4))
		await tick
	timer_stop()
	complete("mast")
	await say("m6_rosa_02")
	objective("tanks", "Blow up the fuel tanks (3)")
	while alive_structs(tanks) > 0:
		await tick
	complete("tanks")
	await say("m6_deacon_01")
	await say("m6_rosa_03")
	objective("shack", "Wreck the dispatch shack")
	while not shack.dead:
		await tick
	complete("shack")
	var papers := pickup("item", shack.global_position + Vector3(6, 0, 0))
	objective("papers", "Grab Vale's shipping records")
	var got := [false]
	papers.collected.connect(func(_p): got[0] = true)
	var b: Node3D = level.set_beacon(papers.global_position, "RECORDS")
	var t0 := t
	while not got[0]:
		if Game.autoplay and t - t0 > 3.0:
			teleport_player(papers.global_position)
		await tick
	level.clear_beacon(b)
	complete("papers")
	await say_all(["m6_deacon_02", "m6_rosa_04"])
	var chase := _reinforce(5)
	await say_all(["m6_rusk_01", "m6_vale_01", "m6_rosa_05"])
	objective("escape", "Escape west along the Mercury road")
	await wait_reach(p(560, -765), 35.0, "ESCAPE")
	complete("escape")
	for c in chase + guards:
		var ai := Level.ai_of(c)
		if ai and is_instance_valid(c):
			ai.hold = true
	win()

func alive_structs(list: Array) -> int:
	var n := 0
	for s in list:
		if not s.dead:
			n += 1
	return n

func _alarm_on() -> void:
	if alarm:
		return
	alarm = AudioStreamPlayer3D.new()
	alarm.stream = Audio.looped("klaxon")
	alarm.bus = "SFX"
	alarm.unit_size = 40.0
	alarm.max_distance = 900.0
	level.add_child(alarm)
	alarm.global_position = p(1930, -600, 8)
	alarm.play()

func _reinforce(n: int) -> Array:
	var out: Array = []
	for i in n:
		var key: String = ["jeep", "raider", "bruiser", "raider", "jeep"][i % 5]
		var c := spawn_road(key, "mercury", Vector2(2050, -250), Vector2(1900, -600), Defs.Team.ENEMY, "attack", {"skill": 0.65}, (i % 2) * 4.0 - 2.0)
		c.global_position += Vector3(0, 0, i * 12.0)
		Level.ai_of(c).aggro = 900.0
		out.append(c)
	return out
