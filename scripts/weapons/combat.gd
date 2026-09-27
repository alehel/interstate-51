class_name Combat
## Shared combat helpers.

## Area damage with linear falloff plus a physical shove on rigid bodies.
static func explode(pos: Vector3, radius: float, dmg: float, source: Node, visual: bool = true, size: float = 1.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if visual:
		var fx := Fx.get_fx()
		if fx:
			fx.explosion(pos, size)
	for n in tree.get_nodes_in_group("damageable"):
		if not is_instance_valid(n):
			continue
		var c: Vector3 = n.global_position + Vector3(0, 0.7, 0)
		var d := c.distance_to(pos)
		if n is Car:
			d = maxf(0.0, d - n.dims().x * 0.4)
		if d > radius:
			continue
		var f := clampf(1.0 - d / radius, 0.25, 1.0)
		n.take_damage(dmg * f, pos.lerp(c, 0.7), source, "explosion")
		if n is RigidBody3D:
			var dir := (c - pos).normalized() + Vector3(0, 0.6, 0)
			n.apply_central_impulse(dir.normalized() * dmg * f * 55.0)
			if n is Car and n.is_player:
				InputSetup.rumble(0.8, 0.8 * f, 0.4)

## Best target in front of a car for lock-on (enemies of its team).
static func pick_target(car: Car, max_dist: float = 350.0, cone_deg: float = 40.0) -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var fwd := car.forward()
	var group := "enemies" if car.team == Defs.Team.PLAYER else "friends"
	var tree := car.get_tree()
	var cands: Array = tree.get_nodes_in_group(group)
	if car.team == Defs.Team.PLAYER:
		cands.append_array(tree.get_nodes_in_group("targets"))
	for n in cands:
		if n == car or not is_instance_valid(n):
			continue
		if n is Car and n.dead:
			continue
		var to: Vector3 = n.global_position - car.global_position
		var dist := to.length()
		if dist > max_dist:
			continue
		var ang := rad_to_deg(fwd.angle_to(to))
		if ang > cone_deg:
			continue
		var score := dist * (1.0 + ang / 12.0)
		if score < best_score:
			best_score = score
			best = n
	return best
