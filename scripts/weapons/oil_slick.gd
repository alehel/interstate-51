class_name OilSlick
extends Node3D
## Puddle of motor oil: anything that drives through loses its grip.

var radius := 5.5
var life := 30.0
var owner_car: Car
var _mi: MeshInstance3D

func place(p: Vector3, owner_: Car) -> void:
	owner_car = owner_
	var w := Lib.world
	var n := Vector3.UP
	if w:
		p.y = w.height(p.x, p.z) + 0.16
		n = w.normal(p.x, p.z)
	global_position = p
	var x := (Vector3.RIGHT - n * n.x).normalized()
	global_transform.basis = Basis(x, n, x.cross(n))
	_mi = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.2, radius * 2.2)
	q.orientation = PlaneMesh.FACE_Y
	_mi.mesh = q
	_mi.material_override = Lib.mat("oil")
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	scale = Vector3(0.2, 1, 0.2)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.5)

func _physics_process(dt: float) -> void:
	life -= dt
	if life <= 0.0:
		queue_free()
		return
	if life < 3.0:
		scale = Vector3.ONE * (life / 3.0)
	for c in get_tree().get_nodes_in_group("cars"):
		if c.dead or (c == owner_car and life > 28.0):
			continue
		var d: Vector3 = c.global_position - global_position
		d.y = 0
		if d.length() < radius * scale.x and c.grounded > 0:
			if c.oil_time <= 0.0 and absf(c.speed) > 8.0:
				c.apply_torque_impulse(Vector3(0, randf_range(-1, 1), 0) * c.mass * 2.5)
				Audio.play_at("skid_loop", c.global_position, -6.0)
			c.oil_time = 1.6
