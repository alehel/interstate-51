extends Node3D
## Dev: spawns every vehicle with place() and reports vertical motion in the first second.
var cars: Array = []
var t := 0.0
var maxv := {}

func _ready() -> void:
	var w := Lib.ensure_world()
	var wb := WorldBuilder.new()
	add_child(wb)
	wb.build(w, "noon")
	var i := 0
	for k in Defs.CARS:
		var c := Car.new()
		c.setup(k, 1, {})
		add_child(c)
		c.place(w.pos(-900 + i * 15, 1300), 0.3 * i, 0.0)
		cars.append(c)
		maxv[k] = 0.0
		i += 1

func _physics_process(dt: float) -> void:
	t += dt
	for c in cars:
		maxv[c.def_key] = maxf(maxv[c.def_key], absf(c.linear_velocity.y))
	if t > 1.5:
		for k in maxv:
			print("%-11s max vertical speed %.3f m/s" % [k, maxv[k]])
		get_tree().quit()
