extends MissionBase
## Mission 2 -- Tonopah Junction. Clear the raiders torching Hal's, find the logbook.

func setup() -> void:
	player_start = p(-150, -980)
	player_yaw = yaw_to(player_start, p(-200, -1400))

func run() -> void:
	# Hal's is burning
	for fp in [Vector3(-178, 5, -1712), Vector3(-204, 5.5, -1688), Vector3(-150, 2, -1752)]:
		var n := Node3D.new()
		level.add_child(n)
		n.global_position = Vector3(fp.x, world.height(fp.x, fp.z) + fp.y, fp.z)
		level.fx.attach(n, "fire", 10.0, 600.0, 2.0)
		level.fx.attach(n, "blacksmoke", 3.0, 600.0, 3.0, Vector3(0, 4, 0))
	var raiders: Array = []
	var spots := [Vector2(-200, -1660), Vector2(-160, -1700), Vector2(-215, -1740), Vector2(-260, -1650), Vector2(-120, -1690)]
	for i in spots.size():
		var key := "hauler" if i == 2 else "raider"
		var c := spawn(key, p(spots[i].x, spots[i].y), randf() * TAU, Defs.Team.ENEMY, "idle", {"skill": 0.55})
		Level.ai_of(c).aggro = 230.0
		raiders.append(c)
	pickup("repair", p(-300, -1600))
	pickup("ammo", p(-110, -1600))
	await say("m2_rosa_01")
	hint("%s fires Zuni rockets. They steer toward your locked target." % InputSetup.prompt("fire_special"), 8.0)
	await say("m2_deacon_01")
	objective("raiders", "Drive off the raiders torching Hal's truck stop")
	await wait_until(func(): return dist_to_player(raiders[0]) < 260.0 or alive(raiders) < spots.size())
	sayn("m2_legion_01")
	await wait(3.0)
	sayn("m2_rosa_02")
	await wait_dead(raiders)
	complete("raiders")
	await wait(1.0)
	await say("m2_hal_01")
	objective("rig", "Search Hollis's burned rig behind the diner")
	await wait_reach(p(-150, -1745), 14.0, "HOLLIS'S RIG")
	complete("rig")
	await say_all(["m2_deacon_02", "m2_deacon_03", "m2_rosa_03"])
	# second wave down 95
	var wave: Array = []
	for i in 4:
		var key := "bruiser" if i == 0 else "raider"
		var c := spawn_road(key, "us95", Vector2(-200, -2350), Vector2(-240, -1700), Defs.Team.ENEMY, "attack", {"skill": 0.6}, (i % 2) * 4.0 - 2.0)
		c.global_position += Vector3(0, 0, -i * 14.0)
		wave.append(c)
	sayn("m2_legion_02")
	await wait(2.5)
	sayn("m2_rosa_04")
	objective("wave", "Destroy the Legion reinforcements")
	await wait_dead(wave)
	complete("wave")
	await wait(1.0)
	await say("m2_rosa_05")
	win()
