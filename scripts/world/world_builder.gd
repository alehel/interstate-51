class_name WorldBuilder
extends Node3D
## Instantiates the cached WorldData as scene nodes: terrain chunks with
## distance LODs, heightmap collision, road meshes, distant mountains,
## scenery and the fixed locations.

var world: WorldData
var breakables: Breakables

static var _mesh_cache: Dictionary = {}   # survives between missions

func build(w: WorldData, time: String) -> void:
	world = w
	name = "World"
	_build_terrain()
	_build_collision()
	_build_roads()
	_build_far_ring()
	_build_bounds()
	breakables = Breakables.new()
	breakables.name = "Breakables"
	add_child(breakables)
	Scenery.build(self, world, breakables, time)

func _build_terrain() -> void:
	var root := Node3D.new()
	root.name = "Terrain"
	add_child(root)
	if not _mesh_cache.has("terrain"):
		var lists: Array = []
		for lod in world.LODS.size():
			var meshes: Array = []
			for arr in world.chunk_arrays[lod]:
				var m := ArrayMesh.new()
				m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				m.surface_set_material(0, Lib.mat("terrain"))
				meshes.append(m)
			lists.append(meshes)
		_mesh_cache["terrain"] = lists
	var lists2: Array = _mesh_cache["terrain"]
	var ranges := [[0.0, 950.0], [950.0, 2200.0], [2200.0, 0.0]]
	for lod in lists2.size():
		for cj in world.CHUNKS:
			for ci in world.CHUNKS:
				var mi := MeshInstance3D.new()
				mi.mesh = lists2[lod][cj * world.CHUNKS + ci]
				mi.position = world.chunk_center(ci, cj)
				mi.visibility_range_begin = ranges[lod][0]
				mi.visibility_range_end = ranges[lod][1]
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(mi)

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = world.N
	hm.map_depth = world.N
	hm.map_data = world.heights
	cs.shape = hm
	cs.scale = Vector3(world.CELL, 1.0, world.CELL)
	body.add_child(cs)
	body.set_meta("terrain", true)
	add_child(body)

func _build_roads() -> void:
	if not _mesh_cache.has("roads"):
		var meshes: Array = []
		for r in world.roads.values():
			meshes.append_array(_road_meshes(r))
		_mesh_cache["roads"] = meshes
	var root := Node3D.new()
	root.name = "Roads"
	add_child(root)
	for m in _mesh_cache["roads"]:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)

func _road_meshes(r: WorldData.Road) -> Array:
	var out: Array = []
	var pts := r.pts
	var n := pts.size()
	var seg := 60
	var s := 0
	while s < n - 1:
		var e := mini(s + seg, n - 1)
		var mb := MeshBuilder.new()
		for k in range(s, e):
			var a := pts[k]
			var b := pts[k + 1]
			var ra := _right(pts, k)
			var rb := _right(pts, k + 1)
			var hw := r.width * 0.5
			var lift := 0.12
			var a_l := a - ra * hw + Vector3(0, lift, 0)
			var a_r := a + ra * hw + Vector3(0, lift, 0)
			var b_l := b - rb * hw + Vector3(0, lift, 0)
			var b_r := b + rb * hw + Vector3(0, lift, 0)
			var va := r.dist[k] / (r.width * 1.4)
			var vb := r.dist[k + 1] / (r.width * 1.4)
			var col := Color(1, 1, 1)
			# road surface, CCW from above -- a->b runs along the road
			mb.quad(r.kind, a_l, a_r, b_r, b_l, col, [Vector2(0, va), Vector2(1, va), Vector2(1, vb), Vector2(0, vb)])
			# shoulders sloping down into the ground
			var sh := Color(0.62, 0.54, 0.43) if r.kind == "asphalt" else Color(0.7, 0.6, 0.46)
			var so := 1.6
			var drop := Vector3(0, -0.45, 0)
			mb.quad("plain", a_l - ra * so + drop, a_l, b_l, b_l - rb * so + drop, sh)
			mb.quad("plain", a_r, a_r + ra * so + drop, b_r + rb * so + drop, b_r, sh)
		out.append(mb.commit())
		s = e
	return out

func _right(pts: PackedVector3Array, k: int) -> Vector3:
	var a := pts[maxi(k - 1, 0)]
	var b := pts[mini(k + 1, pts.size() - 1)]
	var d := b - a
	d.y = 0
	if d.length() < 0.001:
		return Vector3.RIGHT
	return d.normalized().cross(Vector3.UP)

## Ring of hazy mountains beyond the playable basin, out to the horizon.
func _build_far_ring() -> void:
	if not _mesh_cache.has("ring"):
		var n := FastNoiseLite.new()
		n.seed = 5
		n.frequency = 1.0 / 2600.0
		n.fractal_octaves = 5
		n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		var segs := 160
		var radii := [3000.0, 3600.0, 4400.0, 5500.0, 7000.0, 9000.0, 11500.0, 14500.0, 18000.0]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var grid: Array = []
		for ri in radii.size():
			var row: Array = []
			var r: float = radii[ri]
			for s in segs + 1:
				var a := TAU * s / segs
				var p := Vector3(cos(a) * r, 0, sin(a) * r)
				var ridge := n.get_noise_2d(p.x, p.z) * 0.5 + 0.5
				var env := 1.0 - absf(float(ri) / (radii.size() - 1) - 0.45) * 1.6
				var h := (180.0 + ridge * 950.0) * clampf(env, 0.15, 1.0)
				if ri == 0:
					h = 260.0 + ridge * 120.0
				if ri == radii.size() - 1:
					h = -50.0
				p.y = h
				var haze := clampf(float(ri) / (radii.size() - 1) * 1.6, 0, 1)
				var c := Color(0.5, 0.36, 0.3).lerp(Color(0.42, 0.44, 0.56), haze)
				c = c.lerp(Color(0.62, 0.5, 0.42), clampf(1.0 - h / 500.0, 0, 1) * 0.35)
				row.append([p, c])
			grid.append(row)
		for ri in radii.size() - 1:
			for s in segs:
				var q := [grid[ri][s], grid[ri + 1][s], grid[ri + 1][s + 1], grid[ri][s + 1]]
				# inner(s) -> outer(s) -> outer(s+1) -> inner(s+1) is clockwise from above (Godot front face)
				for t in [[0, 1, 2], [0, 2, 3]]:
					for vi in t:
						st.set_color(q[vi][1])
						st.set_uv(Vector2(q[vi][0].x, q[vi][0].z) / 40.0)
						st.add_vertex(q[vi][0])
		st.generate_normals()
		var m := st.commit()
		m.surface_set_material(0, Lib.mat("terrain"))
		_mesh_cache["ring"] = m
	var mi := MeshInstance3D.new()
	mi.name = "FarMountains"
	mi.mesh = _mesh_cache["ring"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 20000.0
	add_child(mi)

func _build_bounds() -> void:
	var body := StaticBody3D.new()
	body.name = "Bounds"
	for k in 4:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(world.BOUND * 2.0 + 100.0, 2000.0, 20.0)
		cs.shape = b
		var off := world.BOUND + 10.0
		match k:
			0: cs.position = Vector3(0, 0, -off)
			1: cs.position = Vector3(0, 0, off)
			2:
				cs.position = Vector3(-off, 0, 0)
				cs.rotation.y = PI / 2
			3:
				cs.position = Vector3(off, 0, 0)
				cs.rotation.y = PI / 2
		body.add_child(cs)
	add_child(body)
