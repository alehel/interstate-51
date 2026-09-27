extends MissionBase
## Mission 3 -- Sheriff's Welcome. Harlan's roadblock in the Gold Creek canyon.

var harlan: Car
var _taunted := false

func setup() -> void:
	player_start = p(-980, 790)
	player_yaw = yaw_to(player_start, p(-1300, 520))

func run() -> void:
	var block_c := world.road("goldcreek").pts[world.road_index("goldcreek", Vector2(-1560, 260))]
	var toward := p(-1300, 520)
	var yaw := yaw_to(block_c, toward)
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := fwd.cross(Vector3.UP)
	structure("barricade", block_c + fwd * 6.0, yaw)
	var deputies: Array = []
	var c1 := spawn("cruiser", block_c + fwd * 14.0 + right * 2.8, yaw + PI * 0.5, Defs.Team.ENEMY, "park", {"skill": 0.6, "barks": "deputy", "name": "Deputy"})
	var c2 := spawn("cruiser", block_c + fwd * 21.0 - right * 2.8, yaw - PI * 0.5, Defs.Team.ENEMY, "park", {"skill": 0.6, "barks": "deputy", "name": "Deputy"})
	harlan = spawn("judge", block_c - fwd * 12.0, yaw, Defs.Team.ENEMY, "park", {"skill": 0.8, "barks": "deputy", "name": "Sheriff Harlan", "boss": true})
	deputies = [c1, c2]
	harlan.damaged.connect(_on_harlan_hurt)
	pickup("repair", p(-1200, 600))
	objective("canyon", "Drive west into the canyon toward Gold Creek")
	await wait_until(func(): return dist_to_player(harlan) < 190.0)
	complete("canyon")
	# stand-off
	if not Game.skip_cinematics:
		cinematic_start()
		shot(harlan.global_position + fwd * 30.0 + right * 10.0 + Vector3(0, 4, 0), harlan.global_position,
			harlan.global_position + fwd * 20.0 - right * 12.0 + Vector3(0, 2.5, 0), harlan.global_position, 16.0, harlan)
		for id in ["m3_harlan_01", "m3_deacon_01", "m3_harlan_02", "m3_deacon_02", "m3_harlan_03"]:
			if level.skip_requested:
				break
			await say(id)
		cinematic_end()
	else:
		sayn("m3_harlan_03")
	for c in deputies + [harlan]:
		var ai := Level.ai_of(c)
		ai.mode = "attack"
		ai.aggro = 500.0
	objective("harlan", "Destroy Sheriff Harlan's cruiser")
	objective("deps", "Take out his deputies")
	sayn("m3_rosa_01")
	hint("%s drops road mines behind you. %s switches special weapons." % [InputSetup.prompt("fire_special"), InputSetup.prompt("cycle_special")], 8.0)
	# pincer from behind after a while
	await wait_until(func(): return alive(deputies) < 2 or t > 70.0, 25.0)
	var behind := p(-980, 790)
	for i in 2:
		var c := spawn_road("cruiser", "goldcreek", Vector2(-800, 900), Vector2(-1300, 520), Defs.Team.ENEMY, "attack", {"skill": 0.65, "barks": "deputy", "name": "Deputy"}, i * 4.0 - 2.0)
		c.global_position += Vector3(0, 0, i * 10.0)
		deputies.append(c)
	sayn("m3_deputy_01")
	await wait_until(func(): return harlan.dead)
	complete("harlan")
	await say("m3_harlan_05")
	await say("m3_deacon_03")
	await wait_dead(deputies)
	complete("deps")
	salvage("mg50")
	await wait(1.0)
	await say_all(["m3_rosa_02", "m3_rosa_03"])
	win()

func _on_harlan_hurt(c: Car, _amount: float, _src: Node) -> void:
	if not _taunted and c.health_frac() < 0.6:
		_taunted = true
		sayn("m3_harlan_04")
