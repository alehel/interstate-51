class_name Rocket
extends Node3D
## Zuni rocket: fast, mildly homing toward the launcher's locked target.

var vel := Vector3.ZERO
var shooter: Car
var target: Node3D
var dmg := 60.0
var splash := 7.0
var life := 4.0
var _ray := PhysicsRayQueryParameters3D.new()
var _mesh: MeshInstance3D

func launch(p: Vector3, v: Vector3, s: Car, t: Node3D, damage: float, radius: float) -> void:
	global_position = p
	vel = v
	shooter = s
	target = t
	dmg = damage
	splash = radius
	_ray.collision_mask = 3
	if is_instance_valid(s):
		_ray.exclude = [s.get_rid()]
	_mesh = MeshInstance3D.new()
	var mb := MeshBuilder.new()
	var b := Basis.from_euler(Vector3(-PI / 2, 0, 0))
	mb.cyl("paint", Transform3D(b, Vector3(0, 0, 0.6)), 0.07, 0.07, 1.2, 6, Color(0.85, 0.85, 0.8))
	mb.cyl("paint", Transform3D(b, Vector3(0, 0, -0.6)), 0.07, 0.0, 0.25, 6, Color(0.6, 0.15, 0.1))
	_mesh.mesh = mb.commit()
	add_child(_mesh)
	look_at(p + v, Vector3.UP)

func _physics_process(dt: float) -> void:
	life -= dt
	if target and is_instance_valid(target) and not (target is Car and target.dead):
		var to := (target.global_position + Vector3(0, 0.8, 0) - global_position)
		var sp := vel.length()
		var want := to.normalized() * sp
		vel = vel.lerp(want, clampf(dt * 1.4, 0, 1)).normalized() * sp
	vel.y -= 1.5 * dt
	var from := global_position
	var to2 := from + vel * dt
	_ray.from = from
	_ray.to = to2
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if not hit.is_empty():
		var col: Object = hit.collider
		if col and col.has_method("take_damage"):
			col.take_damage(dmg * 0.5, hit.position, shooter if is_instance_valid(shooter) else null, "rocket")
		_boom(hit.position)
		return
	global_position = to2
	if vel.length() > 0.1:
		look_at(to2 + vel, Vector3.UP)
	var fx := Fx.get_fx()
	if fx:
		fx.emit(true, from, Vector3.ZERO, 0.08, 0.9, 0.3, Color(1, 0.8, 0.4, 1), Color(1, 0.4, 0.1, 0), Fx.F_FLARE)
		fx.smoke(from, 0.4, 0.65, -vel * 0.05)
	if life <= 0.0:
		_boom(global_position)

func _boom(p: Vector3) -> void:
	Combat.explode(p, splash, dmg, shooter if is_instance_valid(shooter) else null, true, 0.7)
	queue_free()
