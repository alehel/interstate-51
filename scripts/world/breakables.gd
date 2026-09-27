class_name Breakables
extends Node3D
## Knock-down scenery (Joshua trees, telephone poles, signs, fence posts).
## Instances live in MultiMeshes; a spatial hash lets vehicles find nearby
## items cheaply. When hit, the instance topples over and a puff of dust flies.

const CELL := 32.0

var _items: Array = []          # [mmi, index, pos(Vector3), radius, broken, kind, xform]
var _grid: Dictionary = {}      # Vector2i -> Array[int]
var _groups: Dictionary = {}    # key -> {mesh, xforms:Array, mmi}

func add(group: String, mesh: Mesh, xform: Transform3D, radius: float, kind: String, vis_end: float = 1800.0) -> void:
	if not _groups.has(group):
		_groups[group] = {"mesh": mesh, "xforms": [], "ids": [], "vis": vis_end}
	var g: Dictionary = _groups[group]
	var id := _items.size()
	_items.append([group, g.xforms.size(), xform.origin, radius, false, kind, xform])
	g.xforms.append(xform)
	g.ids.append(id)
	var c := Vector2i(floori(xform.origin.x / CELL), floori(xform.origin.z / CELL))
	if not _grid.has(c):
		_grid[c] = []
	_grid[c].append(id)

## Call once after all add() calls.
func finalize() -> void:
	for key in _groups:
		var g: Dictionary = _groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = g.mesh
		mm.instance_count = g.xforms.size()
		for i in g.xforms.size():
			mm.set_instance_transform(i, g.xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = g.vis
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		g["mmi"] = mmi

## Returns total "mass" of things knocked down (0 if none) so cars can slow a little.
func hit_test(p: Vector3, radius: float, vel: Vector3) -> float:
	var c := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	var hit := 0.0
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var arr = _grid.get(c + Vector2i(dx, dz))
			if arr == null:
				continue
			for id in arr:
				var it: Array = _items[id]
				if it[4]:
					continue
				var q: Vector3 = it[2]
				var r: float = it[3] + radius
				if absf(q.x - p.x) > r or absf(q.z - p.z) > r:
					continue
				if Vector2(q.x - p.x, q.z - p.z).length() < r and absf(q.y - p.y) < 6.0:
					_break(id, vel)
					hit += 1.0 if it[5] != "pole" else 1.5
	return hit

func _break(id: int, vel: Vector3) -> void:
	var it: Array = _items[id]
	it[4] = true
	var g: Dictionary = _groups[it[0]]
	var xf: Transform3D = it[6]
	var dir := vel
	dir.y = 0
	if dir.length() < 0.1:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var axis := Vector3.UP.cross(dir).normalized()
	var fallen := Transform3D(Basis(axis, 1.35) * xf.basis, xf.origin + Vector3(0, 0.1, 0))
	(g.mmi as MultiMeshInstance3D).multimesh.set_instance_transform(it[1], fallen)
	var fx := Fx.get_fx()
	if fx:
		fx.dust(xf.origin + Vector3(0, 1.0, 0), 1.6, Color(0.7, 0.6, 0.48))
		if it[5] == "tree":
			fx.debris(xf.origin + Vector3(0, 2.0, 0), vel * 0.4, 5, Color(0.4, 0.45, 0.25))
	Audio.play_at("crash_light", xf.origin, -6.0, 1.3)
