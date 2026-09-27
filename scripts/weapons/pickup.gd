class_name Pickup
extends Node3D
## Floating crate: repair kit, ammo, or a mission item.

signal collected(p: Pickup)

var kind := "repair"
var radius := 4.0
var _t := randf() * 10.0
var _mesh: Node3D
var taken := false

func setup(k: String) -> void:
	kind = k
	var mb := MeshBuilder.new()
	var col: Color = {"repair": Color(0.2, 0.75, 0.3), "ammo": Color(0.95, 0.75, 0.15), "item": Color(0.95, 0.9, 0.8)}.get(k, Color.WHITE)
	if k == "item":
		mb.boxp("paint", Vector3.ZERO, Vector3(0.8, 0.15, 1.0), Color(0.55, 0.35, 0.2))
		mb.boxp("paint", Vector3(0, 0.08, 0), Vector3(0.7, 0.05, 0.9), Color(0.95, 0.92, 0.8))
	else:
		mb.boxp("wood", Vector3.ZERO, Vector3(1.1, 1.1, 1.1), Color(0.6, 0.48, 0.32), 1.0)
		mb.boxp("paint", Vector3.ZERO, Vector3(1.14, 0.3, 1.14), col)
		if k == "repair":
			mb.boxp("lamp", Vector3(0, 0, -0.58), Vector3(0.6, 0.18, 0.02), Color(1, 1, 1))
			mb.boxp("lamp", Vector3(0, 0, -0.58), Vector3(0.18, 0.6, 0.02), Color(1, 1, 1))
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mb.commit()
	add_child(_mesh)
	var glow := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 6.0
	cm.radial_segments = 12
	glow.mesh = cm
	var m: ShaderMaterial = Lib.mat("beacon").duplicate()
	m.set_shader_parameter("color", Color(col.r, col.g, col.b, 0.5))
	glow.material_override = m
	glow.position = Vector3(0, 2.0, 0)
	add_child(glow)

func _process(dt: float) -> void:
	_t += dt
	_mesh.position.y = 1.2 + sin(_t * 2.0) * 0.25
	_mesh.rotation.y = _t * 1.5
	if taken:
		return
	var lvl := get_tree().current_scene
	var p: Car = lvl.get("player") if lvl else null
	if p and not p.dead and p.global_position.distance_to(global_position) < radius:
		taken = true
		match kind:
			"repair":
				p.repair(0.45)
				Audio.play("repair", -2.0)
			"ammo":
				for w in p.guns + p.specials:
					w.refill(0.5)
				Audio.play("pickup", -2.0)
			_:
				Audio.play("pickup", -2.0)
		var fx := Fx.get_fx()
		if fx:
			fx.emit(true, global_position + Vector3(0, 1.2, 0), Vector3.ZERO, 0.4, 1.0, 6.0, Color(1, 1, 0.8, 0.8), Color(1, 1, 1, 0), Fx.F_RING)
		collected.emit(self)
		queue_free()
