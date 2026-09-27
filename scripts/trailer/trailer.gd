extends Node3D
## In-engine trailer director. Runs a 90-second shot list on the real game
## systems (world, cars, AI, weapons, effects, voices) cut to the trailer
## theme, with title cards. Render with Godot's Movie Maker:
##   godot --path . --write-movie trailer.avi --fixed-fps 30 --resolution 1280x720 -- --trailer

const LENGTH := 90.0

var world: WorldData
var player: Car
var fx: Fx
var cam: Camera3D
var chase: ChaseCam
var env_nodes: Array = []
var env: Dictionary = {}
var time_preset := ""
var night := false
var t := 0.0
var _shot := -1
var _shot_nodes: Array = []
var _events: Array = []        # [time, callable]
var _cam_fn: Callable
var _card: Label
var _card2: Label
var _logo: Label
var _tag: Label
var _feat: Label
var _black: ColorRect
var _started := false
var blast: AtomicBlast
var hud: Node = null   # for AtomicBlast.whiteout
var _white: ColorRect

var SHOTS: Array = []

func _ready() -> void:
	world = Lib.ensure_world()
	fx = Fx.new()
	add_child(fx)
	var wb := WorldBuilder.new()
	add_child(wb)
	wb.build(world, "dusk")
	cam = Camera3D.new()
	cam.far = 30000.0
	cam.fov = 60.0
	add_child(cam)
	cam.current = true
	_build_overlay()
	hud = self
	SHOTS = [
		[0.0, "dawn", _shot_aerial],
		[6.0, "dawn", _shot_highway],
		[11.0, "night", _shot_convoy],
		[15.0, "dusk", _shot_boneyard],
		[18.0, "afternoon", _shot_boom],
		[20.0, "afternoon", _shot_dogfight],
		[26.0, "golden", _shot_canyon],
		[31.0, "dusk", _shot_police],
		[36.0, "morning", _shot_mine],
		[41.0, "night", _shot_depot],
		[45.0, "dusk", _shot_juggernaut],
		[50.0, "night", _shot_flame],
		[55.0, "afternoon", _shot_mines],
		[60.0, "dawn", _shot_duchess],
		[66.0, "dawn", _shot_atomic],
		[72.0, "dawn", _shot_finale],
		[80.0, "", _shot_logo],
	]

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_white = ColorRect.new()
	_white.color = Color(1, 0.98, 0.92, 0)
	_white.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_white)
	# letterbox for the cinematic feel
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		if top:
			bar.size.y = 72
		else:
			bar.offset_top = -72
		root.add_child(bar)
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 1)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_black)
	_card = _mk_label(root, "rye", 46, Color(0.97, 0.88, 0.62), 0.74)
	_card2 = _mk_label(root, "bebasneue", 30, Color(0.95, 0.9, 0.8), 0.82)
	_logo = _mk_label(root, "rye", 124, Color(0.97, 0.75, 0.28), 0.36)
	_logo.add_theme_color_override("font_outline_color", Color(0.5, 0.08, 0.05))
	_logo.add_theme_constant_override("outline_size", 22)
	_tag = _mk_label(root, "specialelite", 32, Color(0.95, 0.9, 0.8), 0.56)
	_feat = _mk_label(root, "bebasneue", 30, Color(0.9, 0.75, 0.45), 0.66)

func _mk_label(root: Control, font: String, size: int, col: Color, y: float) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", Lib.font(font))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = y
	l.anchor_bottom = y
	l.offset_top = -size * 0.7
	l.offset_bottom = size * 0.7
	l.modulate.a = 0.0
	root.add_child(l)
	return l

func card(text: String, sub: String = "", dur: float = 3.0) -> void:
	_card.text = text
	_card2.text = sub
	for l in [_card, _card2]:
		var tw := create_tween()
		l.modulate.a = 0.0
		tw.tween_property(l, "modulate:a", 1.0, 0.35)
		tw.tween_interval(dur)
		tw.tween_property(l, "modulate:a", 0.0, 0.35)

func whiteout(dur: float) -> void:
	_white.color.a = 1.0
	var tw := create_tween()
	tw.tween_property(_white, "color:a", 0.0, dur).set_ease(Tween.EASE_IN)

func at(time: float, fn: Callable) -> void:
	_events.append([time, fn])

# ------------------------------------------------------------------ helpers

func set_env(preset: String) -> void:
	if preset == time_preset or preset == "":
		return
	for n in env_nodes:
		n.queue_free()
	env_nodes.clear()
	var before := get_child_count()
	env = EnvSetup.build(self, preset)
	for i in range(before, get_child_count()):
		env_nodes.append(get_child(i))
	time_preset = preset
	night = preset in ["night", "dusk", "dawn"]

func P(x: float, z: float, lift: float = 0.0) -> Vector3:
	return world.pos(x, z, lift)

func yaw_to(a: Vector3, b: Vector3) -> float:
	var d := b - a
	return atan2(-d.x, -d.z)

func spawn(key: String, pos: Vector3, yaw: float, team: int, ai: String, opts: Dictionary = {}) -> Car:
	var c := Car.new()
	c.is_player = opts.get("player", false)
	c.setup(key, team, opts)
	add_child(c)
	c.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, world.height(pos.x, pos.z) + 0.8, pos.z))
	c.linear_velocity = -c.global_transform.basis.z * opts.get("speed", 0.0)
	if ai != "none":
		var a := AIDriver.new()
		a.mode = ai
		a.skill = opts.get("skill", 0.8)
		a.aggro = 800.0
		c.add_child(a)
		c.set_meta("ai", a)
	if night:
		c.enable_headlights(true)
	if c.def.style == "police":
		c.enable_siren(true)
	_shot_nodes.append(c)
	return c

func ai(c: Car) -> AIDriver:
	return c.get_meta("ai")

func road(name: String, a: Vector2, b: Vector2, lane: float = 0.0) -> PackedVector3Array:
	return world.road_path(name, a, b, lane)

func sally(pos: Vector3, yaw: float, weapons: Array = ["mg30", "mg30", "rockets"], mode: String = "attack", speed: float = 0.0) -> Car:
	player = spawn("merc", pos, yaw, Defs.Team.PLAYER, mode, {"weapons": weapons, "player": false, "speed": speed, "skill": 1.0})
	player.invulnerable = true
	player.is_player = false
	return player

func cam_static(pos: Vector3, look: Vector3) -> void:
	_cam_fn = func(_lt: float):
		cam.global_position = pos
		cam.look_at(look, Vector3.UP)

func cam_move(a: Vector3, b: Vector3, look_a: Vector3, look_b: Vector3, dur: float) -> void:
	_cam_fn = func(lt: float):
		var k := smoothstep(0.0, 1.0, clampf(lt / dur, 0, 1))
		cam.global_position = a.lerp(b, k)
		cam.look_at(look_a.lerp(look_b, k), Vector3.UP)

func cam_follow(n: Node3D, offset: Vector3, look_off: Vector3 = Vector3(0, 1, 0), stiff: float = 6.0) -> void:
	var state := {"p": Vector3.ZERO, "init": false}
	_cam_fn = func(_lt: float):
		if not is_instance_valid(n):
			return
		var yaw := atan2(n.global_transform.basis.z.x, n.global_transform.basis.z.z)
		var target: Vector3 = n.global_position + Basis(Vector3.UP, yaw) * offset
		target.y = maxf(target.y, world.height(target.x, target.z) + 0.8)
		if not state.init:
			state.p = target
			state.init = true
		state.p = state.p.lerp(target, clampf(get_process_delta_time() * stiff, 0, 1))
		cam.global_position = state.p
		cam.look_at(n.global_position + Basis(Vector3.UP, yaw) * look_off, Vector3.UP)

func cam_track(pos: Vector3, n: Node3D, look_off: Vector3 = Vector3(0, 1, 0)) -> void:
	_cam_fn = func(_lt: float):
		cam.global_position = pos
		if is_instance_valid(n):
			cam.look_at(n.global_position + look_off, Vector3.UP)

func _clear_shot() -> void:
	for n in _shot_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_shot_nodes.clear()
	player = null

# -------------------------------------------------------------------- shots

func _shot_aerial(t0: float) -> void:
	_black.color.a = 1.0
	create_tween().tween_property(_black, "color:a", 0.0, 2.5)
	cam_move(Vector3(700, 420, 2700), Vector3(1250, 300, 2050), P(1900, 1250), P(2000, 1100), 6.0)
	cam.fov = 58.0
	at(t0 + 1.0, func(): card("NEVADA, 1951.", "", 3.6))

func _shot_highway(t0: float) -> void:
	var route := road("us95", Vector2(-236, -1490), Vector2(150, 300))
	var s := sally(route[0], yaw_to(route[0], route[3]), ["mg30", "mg30", "rockets"], "path", 36.0)
	ai(s).set_path(route, 40.0)
	var cp := P(-178, -1330, 1.3)
	cam_track(cp, s, Vector3(0, 0.9, 0))
	cam.fov = 50.0
	at(t0 + 0.8, func(): card("THE ARMY IS TESTING ATOM BOMBS", "OUT ON THE FLATS.", 3.4))

func _shot_convoy(t0: float) -> void:
	var route := road("mercury", Vector2(1700, -650), Vector2(1000, -760))
	var keys := ["bruiser", "raider", "raider", "hauler", "raider"]
	var lead: Car
	for i in keys.size():
		var k := mini(i * 5, route.size() - 5)
		var c := spawn(keys[i], route[k], yaw_to(route[k + 2], route[k]) + PI, Defs.Team.ENEMY, "path", {"speed": 26.0})
		ai(c).set_path(route, 30.0)
		ai(c).shoot_on_path = false
		if i == 0:
			lead = c
	# convoy drives west toward the camera
	cam_static(P(1575, -700, 1.0), P(1700, -660, 2.0))
	cam.fov = 45.0
	at(t0 + 0.2, func(): Audio.say("m9_vale_01"))
	at(t0 + 1.0, func(): card("THE CHROME LEGION WANTS", "ONE OF THEIR OWN.", 2.6))

func _shot_boneyard(t0: float) -> void:
	var c := P(-590, 1050)
	var s := sally(c, 2.3, ["mg30", "mg30", "rockets"], "none")
	s.enable_headlights(true)
	var a0 := 0.9
	_cam_fn = func(lt: float):
		var a := a0 + lt * 0.12
		cam.global_position = c + Vector3(cos(a) * 7.5, 1.4, sin(a) * 7.5)
		cam.look_at(c + Vector3(0, 0.8, 0), Vector3.UP)
	cam.fov = 45.0
	at(t0 + 0.1, func(): Audio.say("m1_deacon_01"))

func _shot_boom(t0: float) -> void:
	var c := P(-900, 1150)
	var r := spawn("raider", c, 0.4, Defs.Team.ENEMY, "none")
	cam_static(c + Vector3(-9, 1.2, 10), c + Vector3(0, 0.8, 0))
	cam.fov = 60.0
	at(t0 + 0.08, func(): r.die())

func _shot_dogfight(t0: float) -> void:
	var c := P(-800, 1250)
	var s := sally(c, 0.0, ["mg30", "mg30", "rockets"], "attack", 30.0)
	var foes: Array = []
	for i in 3:
		var f := spawn("raider", c + Vector3(-20 + i * 20, 0, -120 - i * 25), 0.2, Defs.Team.ENEMY, "path", {"speed": 26.0, "skill": 0.5})
		var path := PackedVector3Array([f.global_position, f.global_position + Vector3(-80 + i * 60, 0, -600)])
		ai(f).set_path(path, 30.0)
		f.armor_max = 10.0
		for sd in Car.SIDES:
			f.armor[sd] = 5.0
		foes.append(f)
	cam_follow(s, Vector3(1.5, 2.3, 7.5), Vector3(0, 1.0, -8))
	cam.fov = 68.0
	at(t0 + 0.4, func(): card("ONE MAN.", "", 1.6))
	at(t0 + 2.2, func(): if is_instance_valid(foes[1]): foes[1].die())
	at(t0 + 4.4, func(): if is_instance_valid(foes[0]): foes[0].die())

func _shot_canyon(t0: float) -> void:
	var route := road("goldcreek", Vector2(-1760, 70), Vector2(-700, 950))
	var truck := spawn("supply", route[0], yaw_to(route[0], route[3]), Defs.Team.PLAYER, "path", {"speed": 14.0})
	ai(truck).set_path(route, 15.0)
	ai(truck).shoot_on_path = false
	var hearse := spawn("hearse", route[8], yaw_to(route[8], route[11]), Defs.Team.PLAYER, "path", {"speed": 14.0})
	ai(hearse).set_path(route, 15.0)
	for i in 2:
		var j := spawn("jeep", route[0] + Vector3(-12 - i * 8, 0, 20 + i * 10), yaw_to(route[0], route[3]), Defs.Team.ENEMY, "attack", {"speed": 18.0})
		ai(j).target = truck
		ai(j).focus = truck
	cam_follow(hearse, Vector3(-6.5, 1.6, 4.0), Vector3(0, 1.0, -4))
	cam.fov = 60.0
	at(t0 + 0.3, func(): Audio.say("m4_preacher_03"))
	at(t0 + 2.4, func(): card("ONE MERCURY.", "", 1.6))

func _shot_police(t0: float) -> void:
	var route := road("us95", Vector2(-160, -1000), Vector2(1300, 2050))
	var s := sally(route[0], yaw_to(route[0], route[3]), ["mg30", "mg30", "mines"], "path", 34.0)
	ai(s).set_path(route, 36.0)
	for i in 3:
		var key := "judge" if i == 1 else "cruiser"
		var k := 0
		var back := route[0] - (route[3] - route[0]).normalized() * (22.0 + i * 12.0) + Vector3(-3 + i * 3, 0, 0)
		var c := spawn(key, back, yaw_to(route[0], route[3]), Defs.Team.ENEMY, "path", {"speed": 34.0})
		ai(c).set_path(route, 37.0 + i)
		ai(c).shoot_on_path = true
	cam_follow(s, Vector3(0.0, 2.2, -9.0), Vector3(0, 0.8, 18.0), 8.0)
	cam.fov = 62.0
	at(t0 + 0.2, func(): Audio.say("m3_harlan_01"))
	at(t0 + 3.2, func(): card("TWO THIRTY-CALS.", "", 1.4))
	at(t0 + 2.6, func(): if is_instance_valid(player): player.fire_special = true)

func _shot_mine(t0: float) -> void:
	var center := P(1700, -2150)
	var gate_p := P(1670, -2044)
	var gyaw := yaw_to(gate_p, center)
	var right := Vector3(cos(gyaw), 0, -sin(gyaw))
	var gate := _structure("gate", gate_p, gyaw)
	var t1 := _structure("guard_tower", gate_p + right * 17.0, gyaw)
	var t2 := _structure("guard_tower", gate_p - right * 17.0, gyaw)
	var s := sally(gate_p + Vector3(0, 0, 90), yaw_to(gate_p + Vector3(0, 0, 90), gate_p), ["mg50", "mg50", "rockets"], "none")
	s.aim_target = t1
	cam_static(gate_p + Vector3(-22, 4, 60), gate_p + Vector3(0, 5, 0))
	cam.fov = 55.0
	at(t0 + 0.3, func(): if is_instance_valid(player): player.fire_special = true)
	at(t0 + 1.4, func(): t1.take_damage(9999, t1.global_position, null))
	at(t0 + 2.2, func(): if is_instance_valid(player): player.aim_target = t2)
	at(t0 + 2.8, func(): t2.take_damage(9999, t2.global_position, null))
	at(t0 + 3.6, func(): if is_instance_valid(player): player.fire_special = false)
	at(t0 + 3.8, func(): gate.take_damage(9999, gate.global_position, null))
	at(t0 + 0.8, func(): card("NINE MISSIONS.", "ONE ATOMIC CONSPIRACY.", 2.6))

func _structure(kind: String, pos: Vector3, yaw: float) -> Structure:
	var s := Structure.new()
	s.setup(kind, Defs.Team.ENEMY)
	add_child(s)
	s.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, world.height(pos.x, pos.z), pos.z))
	_shot_nodes.append(s)
	return s

func _shot_depot(t0: float) -> void:
	var tanks: Array = [_structure("fuel_tank", P(1868, -522), 0.0), _structure("fuel_tank", P(1893, -512), 0.2), _structure("fuel_tank", P(1918, -503), 0.4)]
	var mast := _structure("radio_mast", P(1960, -695), 0.3)
	cam_move(P(1800, -420, 14), P(1830, -440, 10), P(1890, -520, 4), P(1900, -530, 6), 4.0)
	cam.fov = 60.0
	at(t0 + 0.2, func(): Audio.say("m6_rosa_02"))
	at(t0 + 0.9, func(): tanks[0].take_damage(9999, tanks[0].global_position, null))
	at(t0 + 1.7, func(): tanks[1].take_damage(9999, tanks[1].global_position, null))
	at(t0 + 2.5, func(): tanks[2].take_damage(9999, tanks[2].global_position, null))
	at(t0 + 3.0, func(): mast.take_damage(9999, mast.global_position, null))

func _shot_juggernaut(t0: float) -> void:
	var route := road("mercury", Vector2(2050, 200), Vector2(2150, 2100))
	var jug := spawn("juggernaut", route[0], yaw_to(route[0], route[3]), Defs.Team.ENEMY, "path", {"speed": 20.0})
	ai(jug).set_path(route, 22.0)
	var start := route[0] - (route[3] - route[0]).normalized() * 30.0 + Vector3(4, 0, 0)
	var s := sally(start, yaw_to(route[0], route[3]), ["mg50", "mg50", "rockets"], "attack", 24.0)
	ai(s).target = jug
	cam_follow(jug, Vector3(-9.0, 2.2, -4.0), Vector3(0, 1.5, 8.0), 5.0)
	cam.fov = 64.0
	at(t0 + 0.3, func(): card("", "", 0.1))
	at(t0 + 1.0, func(): Audio.say("m8_rosa_01"))
	for k in 4:
		at(t0 + 0.8 + k * 1.0, func():
			if is_instance_valid(jug):
				Combat.explode(jug.global_position + Vector3(randf_range(-2, 2), 2.0, randf_range(-3, 3)), 3.0, 20.0, null, true, 0.8))

func _shot_flame(t0: float) -> void:
	var c := P(1500, -720)
	var r := spawn("raider", c + Vector3(0, 0, -18), PI * 0.5 + 0.2, Defs.Team.ENEMY, "path", {"speed": 18.0})
	var path := PackedVector3Array([r.global_position, r.global_position + Vector3(-400, 0, -60)])
	ai(r).set_path(path, 20.0)
	var s := sally(c + Vector3(8, 0, -14), PI * 0.5 + 0.2, ["flame", "flame"], "attack", 20.0)
	ai(s).target = r
	ai(s).rammer = true
	cam_follow(s, Vector3(2.5, 1.6, 6.0), Vector3(0, 1.0, -10.0), 7.0)
	cam.fov = 66.0
	at(t0 + 0.2, func(): card("DRAGON'S BREATH.", "", 1.6))
	at(t0 + 0.3, func(): if is_instance_valid(player): player.fire_primary = true)
	at(t0 + 3.5, func(): if is_instance_valid(r): r.die())

func _shot_mines(t0: float) -> void:
	var c := P(-700, 1300)
	var s := sally(c, PI * 0.5, ["mg30", "mg30", "mines"], "path", 28.0)
	ai(s).set_path(PackedVector3Array([c, c + Vector3(-700, 0, 0)]), 30.0)
	var chasers: Array = []
	for i in 2:
		var f := spawn("raider", c + Vector3(24 + i * 14, 0, -3 + i * 6), PI * 0.5, Defs.Team.ENEMY, "path", {"speed": 29.0})
		ai(f).set_path(PackedVector3Array([f.global_position, f.global_position + Vector3(-700, 0, 0)]), 32.0)
		chasers.append(f)
	cam_follow(s, Vector3(0.0, 2.0, -8.0), Vector3(0, 0.8, 14.0), 8.0)
	cam.fov = 66.0
	at(t0 + 0.4, func(): if is_instance_valid(player): player.fire_special = true)
	at(t0 + 1.4, func(): if is_instance_valid(player): player.fire_special = false)
	at(t0 + 1.9, func(): if is_instance_valid(chasers[0]): chasers[0].die())
	at(t0 + 3.2, func(): if is_instance_valid(chasers[1]): chasers[1].die())

func _shot_duchess(t0: float) -> void:
	var a := P(1500, 1500)
	var b := P(2300, 1150)
	var d := spawn("duchess", a, yaw_to(a, b), Defs.Team.ENEMY, "path", {"speed": 30.0})
	ai(d).set_path(PackedVector3Array([a, b]), 32.0)
	var s := sally(a + Vector3(-22, 0, 14), yaw_to(a, b), ["mg50", "mg50", "rockets"], "attack", 31.0)
	ai(s).target = d
	d.aim_target = s
	cam_follow(d, Vector3(8.0, 1.5, -3.0), Vector3(0, 1.0, 10.0), 6.0)
	cam.fov = 58.0
	at(t0 + 0.4, func(): Audio.say("m9_vale_02"))
	at(t0 + 1.0, func(): card("THE MAN WHO OWNS THE BOMB", "OWNS THE FUTURE.", 3.0))

func _shot_atomic(t0: float) -> void:
	var cp := P(1500, 1300, 2.5)
	var dir := (Vector3(10600, 0, -2850) - cp)
	dir.y = 0
	dir = dir.normalized()
	var side := Vector3(-dir.z, 0, dir.x)
	var mid := cp + dir * 32.0
	var a := mid + side * 70.0
	var b := mid - side * 200.0
	var d := spawn("duchess", a - side * 25.0, yaw_to(a, b), Defs.Team.ENEMY, "path", {"speed": 30.0})
	ai(d).set_path(PackedVector3Array([a - side * 25.0, b]), 32.0)
	var s := sally(a + side * 5.0, yaw_to(a, b), ["mg50", "mg50", "rockets"], "attack", 30.0)
	ai(s).target = d
	cam_static(cp, cp + dir * 100.0 + Vector3(0, 22, 0))
	cam.fov = 64.0
	if not blast:
		blast = AtomicBlast.new()
		blast.level = self
		add_child(blast)
		blast.global_position = Vector3(10600, 0, -2850)
		blast.scale = Vector3.ONE * 4.0
	blast.light = env.light
	blast.sky = env.sky
	at(t0 + 0.6, func(): blast.detonate())
	at(t0 + 1.8, func(): Audio.say("m9_rosa_01"))
	at(t0 + 4.0, func(): Audio.say("m9_deacon_02"))

func _shot_finale(t0: float) -> void:
	var a := P(2150, 1500)
	var d := spawn("duchess", a, 2.0, Defs.Team.ENEMY, "path", {"speed": 24.0})
	ai(d).set_path(PackedVector3Array([a, a + Vector3(-400, 0, 250)]), 26.0)
	var s := sally(a + Vector3(20, 0, -12), 2.0, ["mg50", "mg50", "rockets"], "attack", 26.0)
	ai(s).target = d
	blast.light = env.light
	blast.sky = env.sky
	cam_follow(s, Vector3(-3.0, 2.4, 9.0), Vector3(0, 1.0, -12.0), 6.0)
	cam.fov = 64.0
	at(t0 + 0.5, func(): Audio.say("m9_vale_03"))
	at(t0 + 3.0, func(): if is_instance_valid(d): Combat.explode(d.global_position + Vector3(0, 1.5, 2), 3.0, 30.0, null, true, 1.0))
	at(t0 + 4.2, func(): if is_instance_valid(d): Combat.explode(d.global_position + Vector3(1, 1.5, -1), 3.0, 30.0, null, true, 1.0))
	at(t0 + 5.2, func():
		if is_instance_valid(d):
			d.die()
			fx.explosion(d.global_position + Vector3(0, 2, 0), 2.2))
	at(t0 + 5.6, func(): Audio.say("m9_deacon_03"))

func _shot_logo(t0: float) -> void:
	_black.color.a = 1.0
	cam_static(cam.global_position, cam.global_position + -cam.global_transform.basis.z)
	_logo.text = "INTERSTATE '51"
	_logo.scale = Vector2(1.0, 1.0)
	_logo.modulate.a = 1.0
	_logo.pivot_offset = Vector2(640, 90)
	var tw := create_tween()
	_logo.scale = Vector2(1.6, 1.6)
	tw.tween_property(_logo, "scale", Vector2(1, 1), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	at(t0 + 1.2, func():
		_tag.text = "The atomic age has a speed limit. Nobody told them."
		create_tween().tween_property(_tag, "modulate:a", 1.0, 0.8))
	at(t0 + 4.0, func():
		_feat.text = "9-MISSION STORY CAMPAIGN  ·  FULL VOICE CAST  ·  XBOX CONTROLLER SUPPORT  ·  MADE WITH GODOT"
		create_tween().tween_property(_feat, "modulate:a", 1.0, 0.8))
	at(t0 + 8.6, func():
		var tw2 := create_tween()
		for l in [_logo, _tag, _feat]:
			tw2.parallel().tween_property(l, "modulate:a", 0.0, 1.2))

# --------------------------------------------------------------------- run

func _process(dt: float) -> void:
	if not _started:
		_started = true
		if _tstart > 0.0:
			_black.color.a = 0.0
			for i in SHOTS.size():
				if SHOTS[i][0] <= _tstart:
					_shot = i - 1
		Audio.music("trailer_theme", 0.01, false)
	t += dt
	var next := _shot + 1
	if next < SHOTS.size() and t >= SHOTS[next][0]:
		_shot = next
		_clear_shot()
		set_env(SHOTS[next][1])
		_card.modulate.a = 0.0
		_card2.modulate.a = 0.0
		var fn: Callable = SHOTS[next][2]
		fn.call(SHOTS[next][0])
		_shot_t0 = SHOTS[next][0]
	var i := 0
	while i < _events.size():
		if t >= _events[i][0]:
			var e: Callable = _events[i][1]
			_events.remove_at(i)
			e.call()
		else:
			i += 1
	if _cam_fn.is_valid():
		_cam_fn.call(t - _shot_t0)
	if _tshots != "" and _tstart > 0.0:
		if int(t * 30) % 30 == 0:
			get_viewport().get_texture().get_image().save_png("%s/t_%03d.png" % [_tshots, int(t)])
		if t > _tstart + 12.0:
			get_tree().quit()
	elif _tshots != "" and _shot >= 0 and t - _shot_t0 >= 1.8 and _last_snap != _shot:
		_last_snap = _shot
		get_viewport().get_texture().get_image().save_png("%s/shot_%02d.png" % [_tshots, _shot])
	if t > LENGTH + 0.5:
		get_tree().quit()

var _shot_t0 := 0.0
var _last_snap := -1
var _tshots := ""
var _tstart := -1.0

func _enter_tree() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tstart="):
			t = float(a.substr(9))
			for i in SHOTS.size():
				pass
			_tstart = t
		if a.begins_with("--tshots="):
			_tshots = a.substr(9)
			DirAccess.make_dir_recursive_absolute(_tshots)
