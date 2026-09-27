class_name Structure
extends StaticBody3D
## Destructible building / emplacement used by missions.

signal destroyed(s: Structure)

var kind := ""
var display_name := ""
var health := 100.0
var health_max := 100.0
var dead := false
var team := 1
var _vis: Node3D
var _gun: Node3D
var _gun_cd := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _dims := Vector3(4, 4, 4)

const SPECS := {
	"radio_mast": {"name": "Radio Mast", "hp": 160.0},
	"fuel_tank": {"name": "Fuel Tank", "hp": 110.0},
	"guard_tower": {"name": "Guard Tower", "hp": 150.0},
	"gate": {"name": "Mine Gate", "hp": 120.0},
	"shack": {"name": "Dispatch Shack", "hp": 90.0},
	"barricade": {"name": "Barricade", "hp": 45.0},
	"crate_stack": {"name": "Supply Crates", "hp": 50.0},
}

func setup(k: String, team_: int = 1, name_: String = "") -> void:
	kind = k
	team = team_
	var spec: Dictionary = SPECS[k]
	display_name = name_ if name_ != "" else spec.name
	health_max = spec.hp
	health = health_max
	collision_layer = 1
	collision_mask = 0
	add_to_group("damageable")
	add_to_group("structures")
	if team == Defs.Team.ENEMY:
		add_to_group("targets")
	_vis = Node3D.new()
	add_child(_vis)
	var mb := MeshBuilder.new()
	match k:
		"radio_mast":
			var col := Color(0.75, 0.15, 0.12)
			var s := Locations.Site.new()
			s.mb = mb
			s.root = self
			Locations.lattice(s, Vector3.ZERO, 30.0, 3.4, 0.6, col, 10)
			mb.boxp("lamp", Vector3(0, 30.3, 0), Vector3(0.5, 0.5, 0.5), Color(1, 0.1, 0.05))
			s.body.free()
			_dims = Vector3(3.4, 30, 3.4)
			_box(Vector3(0, 10, 0), Vector3(2.5, 20, 2.5))
		"fuel_tank":
			mb.cyl("metal", Transform3D.IDENTITY, 3.6, 3.6, 6.5, 16, Color(0.92, 0.92, 0.9), true, true, 0.2)
			mb.cyl("metal", Transform3D(Basis.IDENTITY, Vector3(0, 6.5, 0)), 3.6, 0.6, 1.0, 16, Color(0.85, 0.85, 0.82))
			mb.boxp("paint", Vector3(0, 3.2, -3.62), Vector3(3.5, 1.0, 0.05), Color(0.85, 0.65, 0.15))
			_dims = Vector3(7.2, 7.5, 7.2)
			_cyl(3.6, 7.0)
			var l := Label3D.new()
			l.text = "VALE"
			l.font = Lib.font("rye")
			l.font_size = 96
			l.pixel_size = 0.01
			l.modulate = Color(0.15, 0.12, 0.1)
			l.position = Vector3(0, 3.2, -3.7)
			l.rotation.y = PI
			_vis.add_child(l)
		"guard_tower":
			for sx in [-1.5, 1.5]:
				for sz in [-1.5, 1.5]:
					mb.cyl_between("wood", Vector3(sx, 0, sz), Vector3(sx * 0.8, 8.0, sz * 0.8), 0.18, 4, Color(0.5, 0.42, 0.34))
			mb.boxp("wood", Vector3(0, 8.1, 0), Vector3(3.4, 0.25, 3.4), Color(0.5, 0.42, 0.34))
			for i in 4:
				var a := i * PI * 0.5
				mb.box("wood", Transform3D(Basis(Vector3.UP, a), Vector3(sin(a) * 1.6, 8.8, cos(a) * 1.6)), Vector3(3.3, 1.2, 0.12), Color(0.55, 0.45, 0.36))
			mb.cyl("metal", Transform3D(Basis.IDENTITY, Vector3(0, 10.4, 0)), 2.6, 0.2, 1.2, 4, Color(0.4, 0.35, 0.3))
			_dims = Vector3(3.4, 11, 3.4)
			_box(Vector3(0, 4.5, 0), Vector3(3.2, 9.0, 3.2))
			_gun = Node3D.new()
			_gun.position = Vector3(0, 9.3, 0)
			add_child(_gun)
			var gm := MeshInstance3D.new()
			gm.mesh = CarBuilder.turret_mesh(false)
			gm.position = Vector3(0, -0.3, 0)
			_gun.add_child(gm)
		"gate":
			for sx in [-7.0, 7.0]:
				mb.boxp("wood", Vector3(sx, 3.0, 0), Vector3(0.8, 6.0, 0.8), Color(0.45, 0.36, 0.28))
			mb.boxp("wood", Vector3(0, 5.6, 0), Vector3(15.0, 0.7, 0.7), Color(0.45, 0.36, 0.28))
			for i in 9:
				mb.boxp("wood", Vector3(-6.0 + i * 1.5, 2.2, 0), Vector3(0.9, 3.8, 0.2), Color(0.55, 0.45, 0.35))
			mb.boxp("wood", Vector3(0, 1.4, -0.12), Vector3(13, 0.3, 0.12), Color(0.5, 0.4, 0.32))
			mb.boxp("wood", Vector3(0, 3.2, -0.12), Vector3(13, 0.3, 0.12), Color(0.5, 0.4, 0.32))
			_dims = Vector3(15, 6, 1)
			_box(Vector3(0, 2.5, 0), Vector3(14.0, 5.0, 1.0))
			var l2 := Label3D.new()
			l2.text = "KEEP OUT - PROPERTY OF A. VALE"
			l2.font = Lib.font("bebasneue")
			l2.font_size = 72
			l2.pixel_size = 0.012
			l2.modulate = Color(0.9, 0.2, 0.1)
			l2.position = Vector3(0, 4.6, -0.5)
			l2.rotation.y = PI
			l2.double_sided = true
			_vis.add_child(l2)
		"shack":
			mb.boxp("metal", Vector3(0, 1.6, 0), Vector3(5.0, 3.2, 4.0), Color(0.75, 0.74, 0.7), 0.3)
			mb.boxp("metal", Vector3(0, 3.3, 0), Vector3(5.6, 0.2, 4.6), Color(0.5, 0.45, 0.4))
			mb.boxp("plain", Vector3(0, 1.1, -2.02), Vector3(1.0, 2.1, 0.05), Color(0.2, 0.15, 0.1))
			mb.boxp("lamp", Vector3(1.6, 1.8, -2.02), Vector3(1.0, 0.8, 0.05), Color(1.0, 0.85, 0.5))
			_dims = Vector3(5, 3.4, 4)
			_box(Vector3(0, 1.6, 0), Vector3(5.0, 3.2, 4.0))
		"barricade":
			for i in 5:
				mb.boxp("paint", Vector3(-4.0 + i * 2.0, 1.0, 0), Vector3(1.6, 0.3, 0.15), Color(0.95, 0.95, 0.9) if i % 2 == 0 else Color(0.85, 0.2, 0.1))
				mb.boxp("wood", Vector3(-4.6 + i * 2.0, 0.5, 0), Vector3(0.1, 1.0, 0.6), Color(0.5, 0.4, 0.3))
				mb.boxp("wood", Vector3(-3.4 + i * 2.0, 0.5, 0), Vector3(0.1, 1.0, 0.6), Color(0.5, 0.4, 0.3))
			for i in 3:
				mb.cyl("paint", Transform3D(Basis.IDENTITY, Vector3(-3 + i * 3, 0, 1.0)), 0.32, 0.32, 0.9, 8, Color(0.85, 0.35, 0.1))
			_dims = Vector3(10, 1.4, 1.4)
			_box(Vector3(0, 0.7, 0.3), Vector3(10.0, 1.4, 1.6))
		"crate_stack":
			for i in 6:
				mb.boxp("wood", Vector3((i % 3) * 1.3 - 1.3, 0.6 + int(i / 3) * 1.2, 0), Vector3(1.2, 1.2, 1.2), Color(0.6, 0.48, 0.32), 0.8)
			_dims = Vector3(4, 2.4, 1.3)
			_box(Vector3(0, 1.2, 0), Vector3(3.9, 2.4, 1.3))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	_vis.add_child(mi)
	_ray.collision_mask = 3
	_ray.exclude = [get_rid()]

func _box(c: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = c
	add_child(cs)

func _cyl(r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	cs.shape = c
	cs.position = Vector3(0, h * 0.5, 0)
	add_child(cs)

func dims() -> Vector3:
	return _dims

func health_frac() -> float:
	return clampf(health / health_max, 0, 1)

func take_damage(amount: float, world_pos: Vector3, source: Node = null, _kind: String = "") -> void:
	if dead:
		return
	if source is Car and source.team == team:
		return
	if kind == "gate" and _kind == "bullet":
		amount *= 0.6
	health -= amount
	if health <= 0.0:
		_destroy()

func _destroy() -> void:
	dead = true
	remove_from_group("damageable")
	remove_from_group("targets")
	var fx := Fx.get_fx()
	var p := global_position + Vector3(0, _dims.y * 0.4, 0)
	match kind:
		"fuel_tank":
			Combat.explode(global_position + Vector3(0, 3, 0), 18.0, 70.0, self, true, 2.6)
			if fx:
				fx.attach(self, "fire", 20.0, 120.0, 3.0, Vector3(0, 2, 0))
				fx.attach(self, "blacksmoke", 6.0, 120.0, 4.0, Vector3(0, 6, 0))
			_vis.scale = Vector3(1.1, 0.35, 1.1)
			_vis.rotation.z = 0.15
		"radio_mast":
			if fx:
				fx.explosion(global_position + Vector3(0, 2, 0), 1.3)
			var tw := create_tween()
			tw.tween_property(_vis, "rotation:z", 1.45, 2.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_callback(func():
				var fx2 := Fx.get_fx()
				if fx2:
					fx2.dust(global_position + Vector3(-15, 1, 0), 6.0)
				Audio.play_at("crash_heavy", global_position + Vector3(-15, 0, 0), 4.0, 0.7))
		"guard_tower":
			if fx:
				fx.explosion(p + Vector3(0, 4, 0), 1.2)
				fx.attach(self, "fire", 10.0, 40.0, 1.5, Vector3(0, 8, 0))
			var tw2 := create_tween()
			tw2.tween_property(_vis, "rotation:x", 0.35, 1.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tw2.parallel().tween_property(_vis, "position:y", -2.5, 1.5)
			if _gun:
				_gun.visible = false
		_:
			if fx:
				fx.explosion(p, 1.0)
				fx.debris(p, Vector3.ZERO, 14, Color(0.45, 0.36, 0.28))
				if kind == "shack":
					fx.attach(self, "fire", 12.0, 60.0, 1.8, Vector3(0, 1.5, 0))
			_vis.visible = false
			for c in get_children():
				if c is CollisionShape3D:
					c.set_deferred("disabled", true)
	destroyed.emit(self)

func _physics_process(dt: float) -> void:
	if dead or not _gun:
		return
	_gun_cd -= dt
	var lvl := get_tree().current_scene
	var target: Car = lvl.get("player") if lvl else null
	if not target or target.dead:
		return
	var to := target.global_position + Vector3(0, 0.8, 0) - _gun.global_position
	if to.length() > 190.0:
		return
	var yaw := atan2(-to.x, -to.z)
	_gun.rotation.y = lerp_angle(_gun.rotation.y, yaw, dt * 3.0)
	if _gun_cd <= 0.0 and absf(angle_difference(_gun.rotation.y, yaw)) < 0.2:
		_gun_cd = 0.16
		var from := _gun.global_position + to.normalized() * 1.5
		var dir := (to.normalized() + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.035).normalized()
		_ray.from = from
		_ray.to = from + dir * 220.0
		var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
		var end := _ray.to
		var fx := Fx.get_fx()
		if not hit.is_empty():
			end = hit.position
			if hit.collider and hit.collider.has_method("take_damage"):
				hit.collider.take_damage(4.0, hit.position, self, "bullet")
				if fx:
					fx.sparks(hit.position, hit.normal, 3)
			elif fx:
				fx.dust(hit.position, 0.4)
		if fx:
			fx.tracer(from, end, Color(1, 0.8, 0.4))
			fx.muzzle(from, dir, 0.6)
		Audio.play_at("mg30_shot", from, -6.0)
