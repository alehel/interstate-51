extends MissionBase
## Mission 1 -- The Boneyard. Tutorial: flags, junkers, then Legion scouts.

func setup() -> void:
	player_start = p(-360, 760)
	player_yaw = yaw_to(player_start, p(-640, 930))

func run() -> void:
	pickup("repair", p(-690, 960))
	pickup("ammo", p(-720, 965))
	if not Game.skip_cinematics:
		cinematic_start()
		orbit_shot(level.player, 12.0, 3.0, 0.6, 2.2, 14.0)
		for id in ["m1_rosa_01", "m1_deacon_01", "m1_rosa_02"]:
			if level.skip_requested:
				break
			await say(id)
		cinematic_end()
	else:
		sayn("m1_rosa_02")
	hint("%s accelerate   %s brake / reverse   %s steer   %s handbrake" % [
		InputSetup.prompt("accelerate"), InputSetup.prompt("brake"), InputSetup.prompt("steer"), InputSetup.prompt("handbrake")], 10.0)
	objective("flags", "Run the three flags on the lakebed")
	var flags := [p(-520, 1120), p(-760, 1380), p(-1020, 1160)]
	for i in flags.size():
		await wait_reach(flags[i], 16.0, "FLAG %d" % (i + 1))
	complete("flags")
	sayn("m1_rosa_03")
	var junk: Array = []
	for pos in [p(-820, 1240), p(-780, 1290), p(-850, 1320)]:
		var c := spawn("junker", pos, randf() * TAU, Defs.Team.ENEMY, "none", {"name": "Junker"})
		junk.append(c)
	objective("junk", "Shoot the three junkers")
	await wait(1.0)
	hint("%s fire guns - they lock onto the target in front of you   %s cycle target" % [InputSetup.prompt("fire_primary"), InputSetup.prompt("target_next")], 10.0)
	await wait_dead(junk)
	complete("junk")
	await say("m1_rosa_04")
	var scouts: Array = []
	for i in 3:
		var c := spawn_road("raider", "boneyard", Vector2(80, 380), Vector2(-700, 950), Defs.Team.ENEMY, "attack", {"skill": 0.45}, (i - 1) * 3.5)
		c.global_position += (c.global_position - p(-700, 950)).normalized() * i * 12.0
		scouts.append(c)
	await say("m1_legion_01")
	await say("m1_deacon_02")
	sayn("m1_rosa_05")
	objective("scouts", "Destroy the Chrome Legion scouts")
	await wait_dead(scouts)
	complete("scouts")
	await wait(1.0)
	await say_all(["m1_rosa_06", "m1_deacon_03", "m1_rosa_07"])
	win()
