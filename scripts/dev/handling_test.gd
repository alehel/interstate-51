extends Node3D
## Dev: scripted inputs on Sally, prints acceleration / top speed / cornering / stability.
var world: WorldData
var car: Car
var t := 0.0
var phase := ""
var t60 := -1.0
var log_t := 0.0
var player: Car

func _ready() -> void:
	world = Lib.ensure_world()
	add_child(Fx.new())
	var wb := WorldBuilder.new()
	add_child(wb)
	wb.build(world, "noon")
	car = Car.new()
	car.is_player = true
	car.setup("merc", Defs.Team.PLAYER, {"weapons": ["mg30", "mg30"]})
	add_child(car)
	player = car
	car.global_transform = Transform3D(Basis(Vector3.UP, PI * 0.5), world.pos(-150, 1250, 1.0))

func _physics_process(dt: float) -> void:
	t += dt
	var up := car.global_transform.basis.y.dot(Vector3.UP)
	if t < 8.0:
		phase = "accel"
		car.throttle = 1.0
		car.steer = 0.0
		if t60 < 0 and car.speed > 26.8:
			t60 = t
			print("0-60 mph: %.2fs" % t)
	elif t < 14.0:
		phase = "turn full lock at speed"
		car.throttle = 1.0
		car.steer = 1.0
	elif t < 18.0:
		phase = "handbrake turn"
		car.steer = -1.0
		car.handbrake = true
		car.throttle = 0.6
	elif t < 23.0:
		phase = "brake"
		car.handbrake = false
		car.steer = 0.0
		car.throttle = 0.0
		car.brake = 1.0
	else:
		get_tree().quit()
	if t >= log_t:
		log_t += 1.0
		print("%s pos=%s t=%.0f speed=%.1f m/s (%.0f mph) up=%.2f grounded=%d slip=%.2f yawrate=%.2f" % [phase, car.global_position.snapped(Vector3.ONE), t, car.speed, car.speed * 2.237, up, car.grounded, car.slip, car.angular_velocity.y])
