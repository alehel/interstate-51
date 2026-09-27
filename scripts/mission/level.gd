class_name Level
extends Node3D
## A playable mission: generates/instantiates the world, spawns the player,
## runs the mission script and owns HUD, camera and win/fail flow.

var world: WorldData
var mission: MissionBase
var player: Car
var cam: ChaseCam
var hud: Hud
var fx: Fx
var env: Dictionary
var input_locked := false
var state := "loading"
var skip_requested := false
var time_preset := "noon"
var mission_def: Dictionary
var night := false
var _beacons: Array = []
var _loading: CanvasLayer
var _start_ms := 0
var kills := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mission_def = Game.mission_def()
	time_preset = mission_def.time
	night = time_preset in ["night", "dusk", "dawn"]
	_show_loading()
	await get_tree().process_frame
	await get_tree().process_frame
	Lib.start_world_thread()
	while not Lib.world_ready():
		await get_tree().process_frame
	world = Lib.world
	_build()

func _show_loading() -> void:
	_loading = CanvasLayer.new()
	_loading.layer = 50
	add_child(_loading)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.05, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var l := Label.new()
	l.text = mission_def.title.to_upper()
	l.add_theme_font_override("font", Lib.font("rye"))
	l.add_theme_font_size_override("font_size", 56)
	l.add_theme_color_override("font_color", Color(0.95, 0.75, 0.3))
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(-400, -60)
	l.size = Vector2(800, 80)
	_loading.add_child(l)
	var s := Label.new()
	s.text = "Loading Nye County..."
	s.add_theme_font_override("font", Lib.font("specialelite"))
	s.add_theme_font_size_override("font_size", 22)
	s.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
	s.set_anchors_preset(Control.PRESET_CENTER)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.position = Vector2(-400, 30)
	s.size = Vector2(800, 40)
	_loading.add_child(s)

func _build() -> void:
	fx = Fx.new()
	fx.name = "Fx"
	add_child(fx)
	var wb := WorldBuilder.new()
	add_child(wb)
	wb.build(world, time_preset)
	env = EnvSetup.build(self, time_preset)
	# mission script
	var script: GDScript = load(mission_def.script)
	mission = script.new()
	mission.name = "Mission"
	mission.level = self
	mission.world = world
	add_child(mission)
	mission.setup()
	# player
	var lo := Game.loadout()
	var weapons: Array = [lo.gun, lo.gun]
	for s in lo.special:
		if s != "":
			weapons.append(s)
	var opts := {"weapons": weapons}
	if Game.has_item("engine_tune"):
		opts["power_mult"] = 1.12
		opts["top_bonus"] = 2.0
	if Game.has_item("boiler_plate"):
		opts["armor_mult"] = 1.35
	player = spawn_car("merc", mission.player_start, mission.player_yaw, Defs.Team.PLAYER, "player", opts)
	player.destroyed.connect(func(_c): fail("Black Sally was destroyed.", "fail_dead"))
	cam = ChaseCam.new()
	cam.car = player
	add_child(cam)
	cam.current = true
	cam.snap()
	hud = Hud.new()
	hud.level = self
	add_child(hud)
	_loading.queue_free()
	Audio.music(mission_def.music)
	Audio.ambience(time_preset)
	state = "playing"
	_start_ms = Time.get_ticks_msec()
	mission.running = true
	mission.run()

var _shot_dir := ""
var _shot_t := 0.0
var _shot_n := 0

func _process(dt: float) -> void:
	if _shot_dir == "":
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--shots="):
				_shot_dir = a.substr(8)
				DirAccess.make_dir_recursive_absolute(_shot_dir)
		if _shot_dir == "":
			_shot_dir = "-"
	if _shot_dir != "-" and state == "playing":
		_shot_t += dt
		if _shot_t > 4.0:
			_shot_t = 0.0
			_shot_n += 1
			if DisplayServer.get_name() != "headless":
				get_viewport().get_texture().get_image().save_png("%s/%s_%03d.png" % [_shot_dir, mission_def.id, _shot_n])
			if player:
				var info := "t=%.0f player hp=%.2f pos=%s spd=%.1f" % [mission.t, player.health_frac(), player.global_position.snapped(Vector3.ONE), player.speed]
				for c in get_tree().get_nodes_in_group("enemies"):
					info += " | %s %.2f d=%.0f" % [c.def_key, c.health_frac(), c.global_position.distance_to(player.global_position)]
				print(info)

func spawn_car(key: String, pos: Vector3, yaw: float, team: int, ai: String, opts: Dictionary = {}) -> Car:
	var c := Car.new()
	c.is_player = ai == "player"
	c.setup(key, team, opts)
	add_child(c)
	var y := world.height(pos.x, pos.z)
	c.place(Vector3(pos.x, y, pos.z), yaw, opts.get("speed", 0.0))
	if ai == "player":
		if Game.autoplay:
			var a := AIDriver.new()
			a.mode = "attack"
			a.aggro = 600.0
			a.skill = 1.0
			c.add_child(a)
			c.set_meta("ai", a)
		else:
			c.add_child(PlayerInput.new())
	elif ai != "none":
		var a := AIDriver.new()
		a.mode = ai
		a.skill = opts.get("skill", 0.65)
		a.rammer = opts.get("rammer", false)
		if opts.has("barks"):
			a.barks = opts.barks
		c.add_child(a)
		c.set_meta("ai", a)
	if night or opts.get("lights", false):
		c.enable_headlights(true)
	if c.def.style == "police" and opts.get("siren", true):
		c.enable_siren(true)
	if team == Defs.Team.ENEMY:
		c.destroyed.connect(_on_enemy_destroyed)
	return c

static func ai_of(c: Car) -> AIDriver:
	return c.get_meta("ai") if c and c.has_meta("ai") else null

func _on_enemy_destroyed(c: Car) -> void:
	if c.last_attacker == player:
		kills += 1
		if randf() < 0.35:
			Audio.bark("kill", 4.0)
	# chance of a pickup
	if randf() < 0.28:
		var k := "repair" if randf() < 0.6 else "ammo"
		spawn_pickup(k, c.global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))

func spawn_structure(kind: String, pos: Vector3, yaw: float, name_: String = "") -> Structure:
	var s := Structure.new()
	s.setup(kind, Defs.Team.ENEMY, name_)
	add_child(s)
	var y := world.height(pos.x, pos.z)
	s.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, y - 0.05, pos.z))
	return s

func spawn_pickup(kind: String, pos: Vector3) -> Pickup:
	var pk := Pickup.new()
	pk.setup(kind)
	add_child(pk)
	pk.global_position = Vector3(pos.x, world.height(pos.x, pos.z), pos.z)
	return pk

# ------------------------------------------------------------- beacons

func set_beacon(pos: Vector3, label: String = "") -> Node3D:
	var b := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 4.0
	cm.bottom_radius = 4.0
	cm.height = 80.0
	cm.radial_segments = 16
	cm.cap_top = false
	cm.cap_bottom = false
	b.mesh = cm
	var m: ShaderMaterial = Lib.mat("beacon").duplicate()
	m.set_shader_parameter("color", Color(1.0, 0.78, 0.25, 0.9))
	b.material_override = m
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(b)
	b.global_position = Vector3(pos.x, world.height(pos.x, pos.z) + 40.0, pos.z)
	b.set_meta("label", label)
	b.set_meta("target", Vector3(pos.x, world.height(pos.x, pos.z), pos.z))
	_beacons.append(b)
	return b

func clear_beacon(b: Node3D) -> void:
	_beacons.erase(b)
	if is_instance_valid(b):
		b.queue_free()

func beacons() -> Array:
	return _beacons

# ----------------------------------------------------------- cinematics

func set_cinematic(on: bool) -> void:
	input_locked = on
	skip_requested = false
	hud.letterbox(on)
	if not on:
		cam.end_cinematic()

func _unhandled_input(event: InputEvent) -> void:
	if state != "playing":
		return
	if input_locked and event.is_action_pressed("skip"):
		skip_requested = true
		Audio.stop_voice()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and not get_tree().paused:
		hud.pause_menu(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("objectives"):
		hud.flash_objectives()

# -------------------------------------------------------------- endings

func elapsed() -> float:
	return (Time.get_ticks_msec() - _start_ms) / 1000.0

func win() -> void:
	if state != "playing":
		return
	state = "won"
	mission.running = false
	input_locked = false
	Audio.music("victory", 0.3, false)
	hud.message("MISSION COMPLETE", mission_def.title, 6.0)
	for c in get_tree().get_nodes_in_group("enemies"):
		var a := ai_of(c)
		if a:
			a.hold = true
	Game.last_result = {
		"title": mission_def.title, "time": elapsed(), "kills": kills,
		"damage": player.stats.damage_taken if player else 0.0, "shots": player.stats.shots if player else 0,
		"won": true,
	}
	Game.mission_completed(Game.last_result)
	if Game.autoplay:
		print("AUTOTEST WIN %s in %.1fs kills=%d" % [mission_def.id, elapsed(), kills])
		await get_tree().create_timer(1.0, false).timeout
		get_tree().quit(0)
		return
	await get_tree().create_timer(6.5, false).timeout
	Game.goto("res://scenes/debrief.tscn")

func fail(reason: String, line: String = "fail_dead") -> void:
	if state != "playing":
		return
	state = "failed"
	mission.running = false
	input_locked = true
	Audio.stop_voice()
	Audio.say(line)
	Audio.music("defeat", 0.3, false)
	hud.message("MISSION FAILED", reason, 8.0)
	if Game.autoplay:
		print("AUTOTEST FAIL %s: %s at %.1fs" % [mission_def.id, reason, elapsed()])
		await get_tree().create_timer(1.0, false).timeout
		get_tree().quit(1)
		return
	await get_tree().create_timer(3.5, false).timeout
	hud.fail_menu(reason)
