extends Node3D
## Dev: AI driving diagnostics. Spawns cars in attack/path mode and logs speed.
var world: WorldData
var player: Car
var cars: Array = []
var t := 0.0
var next_log := 0.0
var cam: Camera3D

func _ready() -> void:
	world = Lib.ensure_world()
	add_child(Fx.new())
	var wb := WorldBuilder.new()
	add_child(wb)
	wb.build(world, "noon")
	EnvSetup.build(self, "noon")
	cam = Camera3D.new()
	cam.far = 20000.0
	add_child(cam)
	cam.current = true
	# static target far away on the lake
	player = Car.new()
	player.setup("merc", Defs.Team.PLAYER, {})
	add_child(player)
	player.global_position = world.pos(-700, 1100, 1.0)
	player.invulnerable = true
	# attack from 900 m across flat ground
	_spawn("cruiser", world.pos(-700, 200, 1), "attack")
	# attack via the canyon road
	var c2 := _spawn("cruiser", world.pos(-1800, 50, 1), "attack")
	c2.rotation.y = atan2(300.0, 250.0)
	# path along us95
	var c := _spawn("raider", world.road("us95").pts[200], "path")
	c.get_meta("ai").set_path(world.road("us95").pts, 40.0)

func _spawn(key: String, p: Vector3, mode: String) -> Car:
	var c := Car.new()
	c.setup(key, Defs.Team.ENEMY, {})
	add_child(c)
	c.global_position = p + Vector3(0, 1, 0)
	var a := AIDriver.new()
	a.mode = mode
	c.add_child(a)
	c.set_meta("ai", a)
	cars.append(c)
	return c

func _physics_process(dt: float) -> void:
	t += dt
	if t >= next_log:
		next_log += 2.0
		var s := "t=%.0f" % t
		for c in cars:
			var a: AIDriver = c.get_meta("ai")
			s += " | %s spd=%.1f st=%.2f gr=%d p=%s d=%.0f av=%.2f rt=%d/%d rev=%.1f" % [c.def_key, c.speed, c.steer, c.grounded, c.global_position.snapped(Vector3.ONE), c.global_position.distance_to(player.global_position), a._avoid, a._route_i, a._route.size(), a._reverse_t]
		print(s)
	if cam:
		var c: Car = cars[1]
		cam.global_position = c.global_transform * Vector3(0, 6, 14)
		cam.look_at(c.global_position + c.forward() * 10.0, Vector3.UP)
		if int(t * 60) % 180 == 0 and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png("/tmp/claude-0/-home-user-interstate-51/700515ae-4f57-55df-b04d-9af7e3603cf9/scratchpad/ai_%02d.png" % int(t))
	if t > 40.0:
		get_tree().quit()
