class_name MeshBuilder
extends RefCounted
## Small procedural-geometry toolkit. Accumulates triangles per material key,
## then commits an ArrayMesh with one surface per material (from Lib.mat()).
## All quads are given counter-clockwise as seen from the front face.

var surfaces: Dictionary = {}
var xf := Transform3D.IDENTITY   # applied to everything that gets added

class Surf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()

func _s(mat: String) -> Surf:
	if not surfaces.has(mat):
		surfaces[mat] = Surf.new()
	return surfaces[mat]

func tri(mat: String, a: Vector3, b: Vector3, c: Vector3, col: Color, ua := Vector2.ZERO, ub := Vector2(1, 0), uc := Vector2(1, 1)) -> void:
	var s := _s(mat)
	a = xf * a
	b = xf * b
	c = xf * c
	var nrm := (b - a).cross(c - a).normalized()
	var base := s.v.size()
	s.v.append_array([a, b, c])
	s.n.append_array([nrm, nrm, nrm])
	s.c.append_array([col, col, col])
	s.uv.append_array([ua, ub, uc])
	# Godot front faces are clockwise
	s.idx.append_array([base, base + 2, base + 1])

func quad(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, uvs: Array = []) -> void:
	var s := _s(mat)
	a = xf * a
	b = xf * b
	c = xf * c
	d = xf * d
	var nrm := (b - a).cross(c - a)
	if nrm.length_squared() < 1e-10:
		nrm = (c - a).cross(d - a)
	nrm = nrm.normalized()
	var base := s.v.size()
	s.v.append_array([a, b, c, d])
	s.n.append_array([nrm, nrm, nrm, nrm])
	s.c.append_array([col, col, col, col])
	if uvs.size() == 4:
		s.uv.append_array(uvs)
	else:
		s.uv.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	s.idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])

## Axis-aligned box in local transform t. UVs are box-projected in meters * uvs.
func box(mat: String, t: Transform3D, size: Vector3, col: Color, uvs: float = 0.25, top_col = null) -> void:
	var h := size * 0.5
	var p := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	for i in 8:
		p[i] = t * p[i]
	var tc: Color = top_col if top_col != null else col
	var sx := size.x * uvs
	var sy := size.y * uvs
	var sz := size.z * uvs
	# front (+z)
	quad(mat, p[4], p[5], p[6], p[7], col, [Vector2(0, sy), Vector2(sx, sy), Vector2(sx, 0), Vector2(0, 0)])
	# back (-z)
	quad(mat, p[1], p[0], p[3], p[2], col, [Vector2(0, sy), Vector2(sx, sy), Vector2(sx, 0), Vector2(0, 0)])
	# right (+x)
	quad(mat, p[5], p[1], p[2], p[6], col, [Vector2(0, sy), Vector2(sz, sy), Vector2(sz, 0), Vector2(0, 0)])
	# left (-x)
	quad(mat, p[0], p[4], p[7], p[3], col, [Vector2(0, sy), Vector2(sz, sy), Vector2(sz, 0), Vector2(0, 0)])
	# top
	quad(mat, p[7], p[6], p[2], p[3], tc, [Vector2(0, sz), Vector2(sx, sz), Vector2(sx, 0), Vector2(0, 0)])
	# bottom
	quad(mat, p[0], p[1], p[5], p[4], col, [Vector2(0, 0), Vector2(sx, 0), Vector2(sx, sz), Vector2(0, sz)])

func boxp(mat: String, center: Vector3, size: Vector3, col: Color, uvs: float = 0.25, top_col = null) -> void:
	box(mat, Transform3D(Basis.IDENTITY, center), size, col, uvs, top_col)

## Cylinder / cone / frustum along +Y from y=0 to y=h in transform t.
func cyl(mat: String, t: Transform3D, r0: float, r1: float, h: float, seg: int, col: Color, caps: bool = true, smooth: bool = true, uvs: float = 0.25) -> void:
	var s := _s(mat)
	var base := s.v.size()
	var circ := TAU * maxf(r0, r1) * uvs
	for i in seg + 1:
		var a := TAU * float(i) / seg
		var dir := Vector3(cos(a), 0, sin(a))
		var n0 := (t.basis * (dir * h + Vector3(0, r0 - r1, 0))).normalized()
		var p0 := xf * (t * (dir * r0))
		var p1 := xf * (t * (dir * r1 + Vector3(0, h, 0)))
		var nn := (xf.basis * n0).normalized()
		s.v.append_array([p0, p1])
		s.n.append_array([nn, nn])
		s.c.append_array([col, col])
		var u := float(i) / seg * circ
		s.uv.append_array([Vector2(u, h * uvs), Vector2(u, 0)])
	for i in seg:
		var a := base + i * 2
		# outward-facing, clockwise for Godot
		s.idx.append_array([a, a + 2, a + 1, a + 2, a + 3, a + 1])
	if not smooth:
		pass
	if caps:
		for top in [false, true]:
			var r := r1 if top else r0
			if r <= 0.001:
				continue
			var y := h if top else 0.0
			var cen := t * Vector3(0, y, 0)
			for i in seg:
				var a0 := TAU * float(i) / seg
				var a1 := TAU * float(i + 1) / seg
				var q0 := t * Vector3(cos(a0) * r, y, sin(a0) * r)
				var q1 := t * Vector3(cos(a1) * r, y, sin(a1) * r)
				if top:
					tri(mat, cen, q1, q0, col, Vector2(0.5, 0.5), Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5), Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5))
				else:
					tri(mat, cen, q0, q1, col, Vector2(0.5, 0.5), Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5), Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5))

## Cylinder between two points.
func cyl_between(mat: String, a: Vector3, b: Vector3, r: float, seg: int, col: Color, caps: bool = false) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.9 else Vector3.UP).normalized()
	var z := x.cross(y)
	cyl(mat, Transform3D(Basis(x, y, z), a), r, r, l, seg, col, caps)

## Loft through a list of rings (each ring a PackedVector3Array of equal size).
## Rings progress along +Z (car front is -Z); each ring starts at the top and
## runs toward +X (the car's right), then bottom, then -X.
## Smooth normals. Optional end caps (fan).
func loft(mat: String, rings: Array, cols: Array, cap_start: bool = true, cap_end: bool = true, uvs: float = 0.3) -> void:
	var s := _s(mat)
	var m: int = rings[0].size()
	var base := s.v.size()
	var nrm := []
	nrm.resize(rings.size() * m)
	for i in nrm.size():
		nrm[i] = Vector3.ZERO
	# accumulate face normals
	for r in rings.size() - 1:
		var A: PackedVector3Array = rings[r]
		var B: PackedVector3Array = rings[r + 1]
		for k in m:
			var k2 := (k + 1) % m
			var fn := (B[k] - A[k]).cross(A[k2] - A[k])
			for id in [r * m + k, r * m + k2, (r + 1) * m + k, (r + 1) * m + k2]:
				nrm[id] += fn
	for r in rings.size():
		var ring: PackedVector3Array = rings[r]
		for k in m:
			s.v.append(xf * ring[k])
			var nn: Vector3 = nrm[r * m + k]
			s.n.append((xf.basis * nn).normalized() if nn.length_squared() > 0 else Vector3.UP)
			s.c.append(cols[r] if cols[r] is Color else cols[r][k])
			s.uv.append(Vector2(float(k) / m * 2.0, ring[k].z * uvs))
	for r in rings.size() - 1:
		for k in m:
			var k2 := (k + 1) % m
			var a := base + r * m + k
			var b := base + r * m + k2
			var c := base + (r + 1) * m + k
			var d := base + (r + 1) * m + k2
			s.idx.append_array([a, b, c, b, d, c])
	if cap_start:
		_cap(mat, rings[0], cols[0], false)
	if cap_end:
		_cap(mat, rings[rings.size() - 1], cols[rings.size() - 1], true)

func _cap(mat: String, ring: PackedVector3Array, col, flip: bool) -> void:
	var cen := Vector3.ZERO
	for p in ring:
		cen += p
	cen /= ring.size()
	var cc: Color = col if col is Color else col[0]
	for k in ring.size():
		var a := ring[k]
		var b := ring[(k + 1) % ring.size()]
		if flip:
			tri(mat, cen, b, a, cc)
		else:
			tri(mat, cen, a, b, cc)

func append_mesh_arrays(mat: String, arrays: Array) -> void:
	var s := _s(mat)
	var base := s.v.size()
	var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for p in vv:
		s.v.append(xf * p)
	for nn in arrays[Mesh.ARRAY_NORMAL]:
		s.n.append((xf.basis * nn).normalized())
	if arrays[Mesh.ARRAY_COLOR]:
		s.c.append_array(arrays[Mesh.ARRAY_COLOR])
	else:
		for i in vv.size():
			s.c.append(Color.WHITE)
	if arrays[Mesh.ARRAY_TEX_UV]:
		s.uv.append_array(arrays[Mesh.ARRAY_TEX_UV])
	else:
		for i in vv.size():
			s.uv.append(Vector2.ZERO)
	for i in arrays[Mesh.ARRAY_INDEX]:
		s.idx.append(base + i)

func is_empty() -> bool:
	return surfaces.is_empty()

func commit(mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	for key in surfaces:
		var s: Surf = surfaces[key]
		if s.idx.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = s.v
		arr[Mesh.ARRAY_NORMAL] = s.n
		arr[Mesh.ARRAY_COLOR] = s.c
		arr[Mesh.ARRAY_TEX_UV] = s.uv
		arr[Mesh.ARRAY_INDEX] = s.idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, Lib.mat(key))
		mesh.surface_set_name(mesh.get_surface_count() - 1, key)
	return mesh
