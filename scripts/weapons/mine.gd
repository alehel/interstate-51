class_name Mine
extends Node3D
## Proximity road mine with a blinking arming light.

var owner_car: Car
var dmg := 80.0
var splash := 8.0
var t := 0.0
var _light: MeshInstance3D

func place(p: Vector3, owner_: Car, damage: float, radius: float) -> void:
	owner_car = owner_
	dmg = damage
	splash = radius
	var w := Lib.world
	if w:
		p.y = w.height(p.x, p.z) + 0.1
	global_position = p
	var mb := MeshBuilder.new()
	mb.cyl("paint", Transform3D.IDENTITY, 0.4, 0.3, 0.16, 10, Color(0.25, 0.28, 0.2))
	mb.cyl("chrome", Transform3D(Basis.IDENTITY, Vector3(0, 0.16, 0)), 0.08, 0.06, 0.06, 6, Color(0.6, 0.6, 0.6))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	add_child(mi)
	_light = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.07
	s.height = 0.14
	_light.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(3, 0.2, 0.1)
	_light.material_override = m
	_light.position = Vector3(0, 0.24, 0)
	add_child(_light)

func _physics_process(dt: float) -> void:
	t += dt
	_light.visible = fmod(t, 0.5) < 0.15
	if t < 0.8:
		return
	if t > 90.0:
		queue_free()
		return
	for c in get_tree().get_nodes_in_group("cars"):
		if c.dead:
			continue
		if c == owner_car and t < 3.0:
			continue
		var d: float = c.global_position.distance_to(global_position)
		if d < 3.4:
			Combat.explode(global_position + Vector3(0, 0.3, 0), splash, dmg, owner_car if is_instance_valid(owner_car) else null, true, 0.9)
			queue_free()
			return
	if t > 0.8 and t - dt <= 0.8:
		Audio.play_at("mine_beep", global_position, -6.0)
