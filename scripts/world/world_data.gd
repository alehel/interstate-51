class_name WorldData
extends RefCounted
## The Nye County map: a 6 km x 6 km basin ringed by mountains, with dry lakes,
## highways, dirt roads and every location used in the campaign.
## Heights, masks and chunk geometry arrays are generated here (thread-safe, no nodes).

const SIZE := 6144.0
const HALF := 3072.0
const CELL := 8.0
const N := 769                  # samples per side
const CHUNK := 32               # cells per chunk side
const CHUNKS := 24              # chunks per side
const LODS := [1, 2, 4]
const BOUND := 2960.0           # playable half-extent
const VERSION := 9

var heights := PackedFloat32Array()
var road_d := PackedFloat32Array()   # distance to nearest road centre
var flat_m := PackedFloat32Array()   # lakebed mask 0..1
var colors := PackedColorArray()
var chunk_arrays: Array = []         # [lod][cj*CHUNKS+ci] -> Array (mesh arrays)
var roads: Dictionary = {}           # name -> Road
var ready := false
# coarse road graph for AI navigation
var nav_pos := PackedVector3Array()
var nav_adj: Array = []              # Array[PackedInt32Array]

class Road:
	var name := ""
	var width := 10.0
	var kind := "asphalt"
	var ctrl: Array = []                    # Vector2 control points
	var pts := PackedVector3Array()         # sampled centreline with heights
	var dist := PackedFloat32Array()        # cumulative distance

const FLATS := [
	{"c": Vector2(-700, 1000), "r": 720.0, "h": -1.0},     # Sarcobatus dry lake (Boneyard)
	{"c": Vector2(1900, 1300), "r": 800.0, "h": -3.0},     # Frenchman Flat
]
const RANGES := [
	{"a": Vector2(-1750, -1300), "b": Vector2(-1350, 1900), "r": 420.0, "h": 210.0},
	{"a": Vector2(900, -2950), "b": Vector2(2700, -2650), "r": 650.0, "h": 330.0},
	{"a": Vector2(650, -250), "b": Vector2(950, 800), "r": 260.0, "h": 120.0},
	{"a": Vector2(-2600, 2150), "b": Vector2(-700, 2650), "r": 420.0, "h": 220.0},
	{"a": Vector2(2700, 150), "b": Vector2(2800, 950), "r": 320.0, "h": 170.0},
	{"a": Vector2(-1100, -2650), "b": Vector2(-650, -2500), "r": 260.0, "h": 150.0},
]
const PADS := {
	"boneyard": {"c": Vector2(-700, 950), "r": 160.0},
	"hals": {"c": Vector2(-230, -1700), "r": 120.0},
	"gold_creek": {"c": Vector2(-2300, -300), "r": 170.0},
	"depot": {"c": Vector2(1900, -600), "r": 175.0},
	"mine": {"c": Vector2(1700, -2150), "r": 140.0},
	"airstrip": {"c": Vector2(2150, 2100), "r": 430.0},
}
const ROAD_DEFS := [
	{"name": "us95", "width": 13.0, "kind": "asphalt", "pts": [
		Vector2(-150, -3200), Vector2(-200, -2400), Vector2(-240, -1700), Vector2(-160, -1000),
		Vector2(-100, -700), Vector2(100, -100), Vector2(150, 300), Vector2(400, 900),
		Vector2(800, 1500), Vector2(1300, 2050), Vector2(1900, 2550), Vector2(2600, 2700), Vector2(3200, 2750)]},
	{"name": "mercury", "width": 11.0, "kind": "asphalt", "pts": [
		Vector2(-100, -700), Vector2(400, -760), Vector2(1000, -760), Vector2(1450, -700),
		Vector2(1900, -600), Vector2(2050, -200), Vector2(2050, 300), Vector2(2000, 800),
		Vector2(1950, 1300), Vector2(2050, 1800), Vector2(2150, 2100)]},
	{"name": "tonopah", "width": 11.0, "kind": "asphalt", "pts": [
		Vector2(-240, -1700), Vector2(-900, -1800), Vector2(-1700, -1850), Vector2(-2500, -2000), Vector2(-3200, -2050)]},
	{"name": "goldcreek", "width": 9.0, "kind": "dirt", "pts": [
		Vector2(-700, 950), Vector2(-1000, 800), Vector2(-1300, 520), Vector2(-1520, 300),
		Vector2(-1800, 50), Vector2(-2100, -200), Vector2(-2300, -300)]},
	{"name": "boneyard", "width": 9.0, "kind": "dirt", "pts": [
		Vector2(-700, 950), Vector2(-350, 750), Vector2(0, 450), Vector2(150, 300)]},
	{"name": "mine", "width": 8.0, "kind": "dirt", "pts": [
		Vector2(1450, -700), Vector2(1500, -1100), Vector2(1650, -1450), Vector2(1600, -1800), Vector2(1700, -2150)]},
]

# ---------------------------------------------------------------- sampling

static func gi(x: float) -> float:
	return (x + HALF) / CELL

func h_at(i: int, j: int) -> float:
	return heights[clampi(j, 0, N - 1) * N + clampi(i, 0, N - 1)]

## Terrain height (bilinear).
func height(x: float, z: float) -> float:
	var fx := clampf((x + HALF) / CELL, 0.0, N - 1.001)
	var fz := clampf((z + HALF) / CELL, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := heights[j * N + i]
	var b := heights[j * N + i + 1]
	var c := heights[(j + 1) * N + i]
	var d := heights[(j + 1) * N + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)

func normal(x: float, z: float) -> Vector3:
	var e := CELL
	var hl := height(x - e, z)
	var hr := height(x + e, z)
	var hd := height(x, z - e)
	var hu := height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()

func pos(x: float, z: float, lift: float = 0.0) -> Vector3:
	return Vector3(x, height(x, z) + lift, z)

func road_dist(x: float, z: float) -> float:
	var i := clampi(int(round((x + HALF) / CELL)), 0, N - 1)
	var j := clampi(int(round((z + HALF) / CELL)), 0, N - 1)
	return road_d[j * N + i]

func flat_mask(x: float, z: float) -> float:
	var i := clampi(int(round((x + HALF) / CELL)), 0, N - 1)
	var j := clampi(int(round((z + HALF) / CELL)), 0, N - 1)
	return flat_m[j * N + i]

func slope(x: float, z: float) -> float:
	return 1.0 - normal(x, z).y

func in_bounds(x: float, z: float, margin: float = 0.0) -> bool:
	return absf(x) < BOUND - margin and absf(z) < BOUND - margin

# ------------------------------------------------------------------ roads

func road(name: String) -> Road:
	return roads.get(name)

## Nearest sample index on a road to a 2D position.
func road_index(name: String, p: Vector2) -> int:
	var r: Road = roads[name]
	var best := 0
	var bd := INF
	for k in r.pts.size():
		var q := r.pts[k]
		var d := Vector2(q.x - p.x, q.z - p.y).length_squared()
		if d < bd:
			bd = d
			best = k
	return best

## Road centreline between two positions (inclusive), in travel order.
func road_path(name: String, from: Vector2, to: Vector2, lane: float = 0.0) -> PackedVector3Array:
	var r: Road = roads[name]
	var a := road_index(name, from)
	var b := road_index(name, to)
	var out := PackedVector3Array()
	var step := 1 if b >= a else -1
	var k := a
	while true:
		var p := r.pts[k]
		if lane != 0.0:
			var k2 := clampi(k + step, 0, r.pts.size() - 1)
			var k1 := clampi(k - step, 0, r.pts.size() - 1)
			var dir := (r.pts[k2] - r.pts[k1])
			dir.y = 0
			if dir.length() > 0.01:
				var right := dir.normalized().cross(Vector3.UP)
				p += right * lane
		out.append(p)
		if k == b:
			break
		k += step
	return out

# ------------------------------------------------------------- generation

func generate() -> void:
	var t0 := Time.get_ticks_msec()
	if not _load_cache():
		_gen_heights()
		_save_cache()
	else:
		_build_roads(false)
	_gen_colors()
	_gen_chunks()
	_build_nav()
	ready = true
	print("World generated in %d ms" % (Time.get_ticks_msec() - t0))

func _cache_path() -> String:
	return "user://terrain_cache_v%d.bin" % VERSION

func _load_cache() -> bool:
	if not FileAccess.file_exists(_cache_path()):
		return false
	var f := FileAccess.open(_cache_path(), FileAccess.READ)
	if not f:
		return false
	var nb := N * N * 4
	heights = f.get_buffer(nb).to_float32_array()
	road_d = f.get_buffer(nb).to_float32_array()
	flat_m = f.get_buffer(nb).to_float32_array()
	return heights.size() == N * N and road_d.size() == N * N and flat_m.size() == N * N

func _save_cache() -> void:
	var f := FileAccess.open(_cache_path(), FileAccess.WRITE)
	if not f:
		return
	f.store_buffer(heights.to_byte_array())
	f.store_buffer(road_d.to_byte_array())
	f.store_buffer(flat_m.to_byte_array())

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _gen_heights() -> void:
	var nb := FastNoiseLite.new()
	nb.seed = 1951
	nb.frequency = 1.0 / 1100.0
	nb.fractal_octaves = 4
	var nd := FastNoiseLite.new()
	nd.seed = 76
	nd.frequency = 1.0 / 140.0
	nd.fractal_octaves = 3
	var nr := FastNoiseLite.new()
	nr.seed = 51
	nr.frequency = 1.0 / 520.0
	nr.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	nr.fractal_octaves = 5
	var nm := FastNoiseLite.new()
	nm.seed = 7
	nm.frequency = 1.0 / 900.0
	heights.resize(N * N)
	flat_m.resize(N * N)
	road_d.resize(N * N)
	for j in N:
		var z := -HALF + j * CELL
		for i in N:
			var x := -HALF + i * CELL
			var p := Vector2(x, z)
			var h := nb.get_noise_2d(x, z) * 18.0 + nd.get_noise_2d(x, z) * 2.2
			# mountains: map edge + interior ranges
			var d_edge := HALF - maxf(absf(x), absf(z))
			var m := smoothstep(780.0, 120.0, d_edge + nm.get_noise_2d(x, z) * 180.0) * 430.0
			for r in RANGES:
				var ra: Vector2 = r.a
				var rb: Vector2 = r.b
				var rr: float = r.r
				if p.x < minf(ra.x, rb.x) - rr or p.x > maxf(ra.x, rb.x) + rr or p.y < minf(ra.y, rb.y) - rr or p.y > maxf(ra.y, rb.y) + rr:
					continue
				var d := _seg_dist(p, ra, rb) + nm.get_noise_2d(x * 1.7, z * 1.7) * rr * 0.35
				m = maxf(m, smoothstep(rr, rr * 0.2, d) * r.h)
			if m > 0.5:
				var ridge := nr.get_noise_2d(x, z) * 0.5 + 0.5
				h += m * (0.35 + 0.65 * ridge)
			# dry lakes
			var fm := 0.0
			for f in FLATS:
				var d2 := p.distance_to(f.c) + nd.get_noise_2d(z, x) * 60.0
				var w := smoothstep(f.r, f.r * 0.72, d2)
				if w > 0.0:
					h = lerpf(h, f.h + nd.get_noise_2d(x * 3.0, z * 3.0) * 0.25, w)
					fm = maxf(fm, w)
			flat_m[j * N + i] = fm
			heights[j * N + i] = h
	# location pads
	for k in PADS:
		var pad: Dictionary = PADS[k]
		var c: Vector2 = pad.c
		var r: float = pad.r
		var ph := _avg_height(c, r * 0.5)
		_flatten_circle(c, r, ph, 45.0)
	_build_roads(true)

func _avg_height(c: Vector2, r: float) -> float:
	var s := 0.0
	var n := 0
	for a in 12:
		for rr in [0.0, 0.5, 1.0]:
			var p: Vector2 = c + Vector2.from_angle(a * TAU / 12.0) * r * rr
			s += height(p.x, p.y)
			n += 1
	return s / n

func _flatten_circle(c: Vector2, r: float, h: float, blend: float) -> void:
	var R := r + blend
	var i0 := maxi(0, int(gi(c.x - R)))
	var i1 := mini(N - 1, int(gi(c.x + R)) + 1)
	var j0 := maxi(0, int(gi(c.y - R)))
	var j1 := mini(N - 1, int(gi(c.y + R)) + 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := Vector2(-HALF + i * CELL, -HALF + j * CELL)
			var d := p.distance_to(c)
			if d < R:
				var t := smoothstep(R, r, d)
				heights[j * N + i] = lerpf(heights[j * N + i], h, t)

## Samples road splines, builds smoothed height profiles and (when stamp) carves
## the terrain: flat roadbed, shoulders, cut canyons and embankments.
func _build_roads(stamp: bool) -> void:
	roads.clear()
	for def in ROAD_DEFS:
		var r := Road.new()
		r.name = def.name
		r.width = def.width
		r.kind = def.kind
		r.ctrl = def.pts
		var pts2 := _catmull(def.pts, 4.0)
		var hs := PackedFloat32Array()
		for p in pts2:
			hs.append(height(p.x, p.y))
		if stamp:
			for it in 3:
				hs = _smooth(hs, 10)
			# limit the grade (roads cut through ridges instead of climbing them)
			var grade := 0.045 * 4.0
			for k in range(1, hs.size()):
				hs[k] = minf(hs[k], hs[k - 1] + grade)
			for k in range(hs.size() - 2, -1, -1):
				hs[k] = minf(hs[k], hs[k + 1] + grade)
			hs = _smooth(hs, 6)
			# pin endpoints onto roads that were already built (junctions)
			for end in [0, pts2.size() - 1]:
				var ep: Vector2 = pts2[end]
				for other in roads.values():
					var o: Road = other
					var bi := -1
					var bd := 400.0
					for k in o.pts.size():
						var d := Vector2(o.pts[k].x, o.pts[k].z).distance_squared_to(ep)
						if d < bd:
							bd = d
							bi = k
					if bi >= 0:
						var target := o.pts[bi].y
						var delta := target - hs[end]
						for k in 30:
							var idx: int = end + k if end == 0 else end - k
							if idx < 0 or idx >= hs.size():
								break
							hs[idx] += delta * (1.0 - smoothstep(0.0, 30.0, k))
		else:
			# cached terrain already carved: profile is the terrain itself
			for k in hs.size():
				hs[k] = height(pts2[k].x, pts2[k].y) + 0.04
		var acc := 0.0
		for k in pts2.size():
			var p3 := Vector3(pts2[k].x, hs[k], pts2[k].y)
			if k > 0:
				acc += p3.distance_to(r.pts[k - 1])
			r.pts.append(p3)
			r.dist.append(acc)
		roads[r.name] = r
	if not stamp:
		return
	# stamp: keep nearest road per vertex
	var best_h := PackedFloat32Array()
	var best_w := PackedFloat32Array()
	best_h.resize(N * N)
	best_w.resize(N * N)
	road_d.fill(1e9)
	for rv in roads.values():
		var r: Road = rv
		var R := r.width * 0.5 + 6.0 + 30.0
		var cr := int(ceil(R / CELL))
		for p in r.pts:
			var ci := int(round(gi(p.x)))
			var cj := int(round(gi(p.z)))
			for j in range(maxi(0, cj - cr), mini(N - 1, cj + cr) + 1):
				var z := -HALF + j * CELL
				for i in range(maxi(0, ci - cr), mini(N - 1, ci + cr) + 1):
					var x := -HALF + i * CELL
					var d := Vector2(x - p.x, z - p.z).length()
					var id := j * N + i
					if d < road_d[id]:
						road_d[id] = d
						best_h[id] = p.y
						best_w[id] = r.width
	for id in N * N:
		var d := road_d[id]
		if d > 200.0:
			continue
		var w := best_w[id] * 0.5 + 6.0
		var t := smoothstep(w, w + 30.0, d)
		heights[id] = lerpf(best_h[id] - 0.06, heights[id], t)

func _smooth(a: PackedFloat32Array, w: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(a.size())
	var n := a.size()
	for k in n:
		var s := 0.0
		var c := 0
		for o in range(-w, w + 1):
			var q := clampi(k + o, 0, n - 1)
			s += a[q]
			c += 1
		out[k] = s / c
	return out

static func _catmull(ctrl: Array, spacing: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := ctrl.size()
	for s in n - 1:
		var p0: Vector2 = ctrl[maxi(s - 1, 0)]
		var p1: Vector2 = ctrl[s]
		var p2: Vector2 = ctrl[s + 1]
		var p3: Vector2 = ctrl[mini(s + 2, n - 1)]
		var seg_len := p1.distance_to(p2)
		var steps := maxi(2, int(seg_len / spacing))
		for k in steps:
			var t := float(k) / steps
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(ctrl[n - 1])
	return out

# ---------------------------------------------------------------- colours

func _gen_colors() -> void:
	colors.resize(N * N)
	var nc := FastNoiseLite.new()
	nc.seed = 99
	nc.frequency = 1.0 / 260.0
	var ns := FastNoiseLite.new()
	ns.seed = 100
	ns.frequency = 1.0 / 23.0
	var sand := Color(0.80, 0.64, 0.45)
	var red := Color(0.72, 0.5, 0.34)
	var pale := Color(0.84, 0.75, 0.58)
	var brush := Color(0.62, 0.56, 0.42)
	var lake := Color(0.88, 0.85, 0.77)
	var rock_a := Color(0.52, 0.36, 0.27)
	var rock_b := Color(0.38, 0.3, 0.27)
	var rock_c := Color(0.6, 0.47, 0.36)
	var shoulder := Color(0.64, 0.56, 0.45)
	var nb := FastNoiseLite.new()
	nb.seed = 101
	nb.frequency = 1.0 / 90.0
	for j in N:
		for i in N:
			var id := j * N + i
			var x := -HALF + i * CELL
			var z := -HALF + j * CELL
			var h := heights[id]
			var sx := h_at(i + 1, j) - h_at(i - 1, j)
			var sz := h_at(i, j + 1) - h_at(i, j - 1)
			var slope := Vector2(sx, sz).length() / (2.0 * CELL)
			var v := nc.get_noise_2d(x, z)
			var c := sand.lerp(red, clampf(v * 1.6, 0, 1)).lerp(pale, clampf(-v * 1.6, 0, 1))
			var speck := ns.get_noise_2d(x, z)
			c = c.lerp(brush, clampf(nb.get_noise_2d(x, z) * 1.5, 0, 0.55))
			c = c * (0.92 + speck * 0.08)
			var fm := flat_m[id]
			if fm > 0.0:
				c = c.lerp(lake * (0.97 + speck * 0.03), fm)
			var rockiness := smoothstep(0.18, 0.5, slope) + smoothstep(25.0, 120.0, h) * 0.8
			if rockiness > 0.0:
				var band := 0.5 + 0.5 * sin(h * 0.11 + v * 3.0 + speck * 0.8)
				var rc := rock_a.lerp(rock_b, band).lerp(rock_c, clampf(speck, 0, 1) * 0.6)
				c = c.lerp(rc, clampf(rockiness, 0, 1))
			var rd := road_d[id]
			if rd < 14.0:
				c = c.lerp(shoulder, smoothstep(14.0, 7.0, rd) * 0.8)
			c.a = 1.0
			colors[id] = c

# ----------------------------------------------------------------- chunks

func _gen_chunks() -> void:
	chunk_arrays.clear()
	for lod in LODS:
		var list: Array = []
		for cj in CHUNKS:
			for ci in CHUNKS:
				list.append(_chunk_arrays(ci, cj, lod))
		chunk_arrays.append(list)

func chunk_center(ci: int, cj: int) -> Vector3:
	var x := -HALF + (ci + 0.5) * CHUNK * CELL
	var z := -HALF + (cj + 0.5) * CHUNK * CELL
	return Vector3(x, 0, z)

func _vnormal(i: int, j: int, s: int) -> Vector3:
	var hl := h_at(i - s, j)
	var hr := h_at(i + s, j)
	var hd := h_at(i, j - s)
	var hu := h_at(i, j + s)
	return Vector3(hl - hr, 2.0 * CELL * s, hd - hu).normalized()

func _chunk_arrays(ci: int, cj: int, step: int) -> Array:
	var cen := chunk_center(ci, cj)
	var i0 := ci * CHUNK
	var j0 := cj * CHUNK
	var n := CHUNK / step + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	norms.resize(n * n)
	cols.resize(n * n)
	uvs.resize(n * n)
	for b in n:
		for a in n:
			var i := i0 + a * step
			var j := j0 + b * step
			var x := -HALF + i * CELL
			var z := -HALF + j * CELL
			var k := b * n + a
			verts[k] = Vector3(x - cen.x, h_at(i, j), z - cen.z)
			norms[k] = _vnormal(i, j, step)
			cols[k] = colors[mini(j, N - 1) * N + mini(i, N - 1)]
			uvs[k] = Vector2(x, z) / 12.0
	for b in n - 1:
		for a in n - 1:
			var p00 := b * n + a
			var p10 := p00 + 1
			var p01 := p00 + n
			var p11 := p01 + 1
			# CCW from above = (p00, p01, p11, p10); emit clockwise triangles
			idx.append_array([p00, p11, p01, p00, p10, p11])
	# skirts to hide LOD cracks
	var edges := [[], [], [], []]
	for a in n:
		edges[0].append(a)                  # north row (b=0)
		edges[1].append((n - 1) * n + a)    # south row
		edges[2].append(a * n)              # west column
		edges[3].append(a * n + n - 1)      # east column
	var drop := 3.0 * step
	for e in 4:
		var row: Array = edges[e]
		for k in row.size() - 1:
			var ia: int = row[k]
			var ib: int = row[k + 1]
			var base := verts.size()
			verts.append(verts[ia] - Vector3(0, drop, 0))
			verts.append(verts[ib] - Vector3(0, drop, 0))
			norms.append(norms[ia])
			norms.append(norms[ib])
			cols.append(cols[ia])
			cols.append(cols[ib])
			uvs.append(uvs[ia])
			uvs.append(uvs[ib])
			# double-sided skirt
			idx.append_array([ia, ib, base, ib, base + 1, base, ia, base, ib, ib, base, base + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	return arr

# -------------------------------------------------------------- navigation

func _build_nav() -> void:
	nav_pos = PackedVector3Array()
	nav_adj = []
	var road_nodes: Array = []
	for rv in roads.values():
		var r: Road = rv
		var ids := PackedInt32Array()
		var k := 0
		while k < r.pts.size():
			ids.append(nav_pos.size())
			nav_pos.append(r.pts[k])
			nav_adj.append(PackedInt32Array())
			if k == r.pts.size() - 1:
				break
			k = mini(k + 5, r.pts.size() - 1)
		for i in ids.size() - 1:
			nav_adj[ids[i]].append(ids[i + 1])
			nav_adj[ids[i + 1]].append(ids[i])
		road_nodes.append(ids)
	# junctions: connect nodes of different roads that are close together
	for a in road_nodes.size():
		for b in range(a + 1, road_nodes.size()):
			for ia in road_nodes[a]:
				for ib in road_nodes[b]:
					if nav_pos[ia].distance_to(nav_pos[ib]) < 24.0:
						nav_adj[ia].append(ib)
						nav_adj[ib].append(ia)

func nav_nearest(p: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in nav_pos.size():
		var d := Vector2(nav_pos[i].x - p.x, nav_pos[i].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = i
	return best

## Road route between two points (Dijkstra over the coarse road graph).
func nav_route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var s := nav_nearest(from)
	var g := nav_nearest(to)
	var out := PackedVector3Array()
	if s < 0 or g < 0:
		return out
	var n := nav_pos.size()
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	dist[s] = 0.0
	var open: Array = [s]
	while not open.is_empty():
		var bi := 0
		for i in range(1, open.size()):
			if dist[open[i]] < dist[open[bi]]:
				bi = i
		var u: int = open[bi]
		open.remove_at(bi)
		if done[u]:
			continue
		done[u] = 1
		if u == g:
			break
		for v in nav_adj[u]:
			var nd := dist[u] + nav_pos[u].distance_to(nav_pos[v])
			if nd < dist[v]:
				dist[v] = nd
				prev[v] = u
				open.append(v)
	var cur := g
	while cur != -1:
		out.append(nav_pos[cur])
		cur = prev[cur]
	out.reverse()
	return out

## True when the straight line between a and b crosses steep or high ground.
func line_blocked(a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := int(d / 30.0)
	if steps < 2:
		return false
	var prev_h := height(a.x, a.z)
	var base := maxf(prev_h, height(b.x, b.z))
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var x := lerpf(a.x, b.x, t)
		var z := lerpf(a.z, b.z, t)
		var h := height(x, z)
		if absf(h - prev_h) / (d / steps) > 0.22 or h > base + 22.0:
			return true
		prev_h = h
	return false
