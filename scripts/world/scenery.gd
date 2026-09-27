class_name Scenery
## Desert dressing: Joshua trees, creosote bushes, boulders, telephone lines,
## billboards, mile markers and road closures. Deterministic per session.

static var _m: Dictionary = {}

static func build(root: Node3D, world: WorldData, br: Breakables, time: String) -> void:
	_make_meshes()
	var rng := RandomNumberGenerator.new()
	rng.seed = 19510417
	_vegetation(root, world, br, rng)
	_telephone(root, world, br)
	_signs(root, world, br, time)
	Locations.build_all(root, world, br, time)
	br.finalize()

# ------------------------------------------------------------------ meshes

static func _make_meshes() -> void:
	if not _m.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for v in 4:
		_m["joshua%d" % v] = _joshua(rng, v)
	_m["bush0"] = _bush(1.9, 1.2)
	_m["bush1"] = _bush(1.3, 0.9)
	_m["bush2"] = _bush(2.6, 1.5)
	for v in 3:
		_m["rock%d" % v] = _rock(rng, v)
	_m["pole"] = _pole()
	_m["marker"] = _marker()

static func mesh(name: String) -> Mesh:
	_make_meshes()
	return _m.get(name)

static func _joshua(rng: RandomNumberGenerator, variant: int) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var bark := Color(0.4, 0.34, 0.27)
	var shag := Color(0.5, 0.43, 0.32)
	var h := 2.2 + variant * 0.5 + rng.randf() * 0.6
	mb.cyl("plain", Transform3D.IDENTITY, 0.28, 0.2, h, 7, bark, false)
	mb.cyl("plain", Transform3D(Basis.IDENTITY, Vector3(0, h * 0.35, 0)), 0.34, 0.26, h * 0.5, 7, shag, false)
	var tips: Array = []
	var branches := 2 + variant % 3
	for b in branches:
		var ang := TAU * b / branches + rng.randf() * 0.8
		var start := Vector3(0, h * rng.randf_range(0.75, 1.0), 0)
		var p := start
		var dir := Vector3(cos(ang), rng.randf_range(0.8, 1.4), sin(ang)).normalized()
		for s in 2:
			var nxt := p + dir * rng.randf_range(0.9, 1.5)
			mb.cyl_between("plain", p, nxt, 0.14 - s * 0.03, 6, shag if s == 1 else bark)
			p = nxt
			dir = (dir + Vector3(rng.randf_range(-0.4, 0.4), 0.5, rng.randf_range(-0.4, 0.4))).normalized()
		tips.append(p)
	if branches < 3:
		tips.append(Vector3(0, h + 0.2, 0))
	for t in tips:
		# spiky leaf rosette: three crossed quads + a dark core
		var s := 0.75
		var tt: Vector3 = t
		mb.cyl("plain", Transform3D(Basis.IDENTITY, tt - Vector3(0, 0.2, 0)), 0.22, 0.05, 0.6, 6, Color(0.3, 0.38, 0.2))
		for k in 3:
			var a := PI * k / 3.0
			var dx := Vector3(cos(a), 0, sin(a)) * s
			var c := Color(0.8, 0.85, 0.7)
			mb.quad("spikes", tt - dx - Vector3(0, s, 0), tt + dx - Vector3(0, s, 0), tt + dx + Vector3(0, s, 0), tt - dx + Vector3(0, s, 0), c, [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
		var dz := s
		mb.quad("spikes", tt + Vector3(-dz, 0, -dz), tt + Vector3(-dz, 0, dz), tt + Vector3(dz, 0, dz), tt + Vector3(dz, 0, -dz), Color(0.8, 0.85, 0.7), [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)])
	return mb.commit()

static func _bush(w: float, h: float) -> ArrayMesh:
	var mb := MeshBuilder.new()
	for k in 3:
		var a := PI * k / 3.0
		var dx := Vector3(cos(a), 0, sin(a)) * w * 0.5
		var c := Color(0.95, 0.95, 0.9)
		mb.quad("bush", -dx, dx, dx + Vector3(0, h, 0), -dx + Vector3(0, h, 0), c, [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	return mb.commit()

static func _rock(rng: RandomNumberGenerator, variant: int) -> ArrayMesh:
	var mb := MeshBuilder.new()
	var lat := 5
	var lon := 7
	var pts: Array = []
	var noise := FastNoiseLite.new()
	noise.seed = 300 + variant
	noise.frequency = 1.2
	for i in lat + 1:
		var row: Array = []
		var th := PI * i / lat
		for j in lon:
			var ph := TAU * j / lon
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var r := 1.0 + noise.get_noise_3dv(d * 2.0) * 0.35
			var p := d * r
			p.y = p.y * 0.7 + 0.25
			row.append(p)
		pts.append(row)
	var base := Color(0.62, 0.48, 0.38) if variant != 1 else Color(0.5, 0.42, 0.37)
	for i in lat:
		for j in lon:
			var j2 := (j + 1) % lon
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i][j2]
			var c: Vector3 = pts[i + 1][j]
			var d: Vector3 = pts[i + 1][j2]
			var shade := 0.85 + 0.15 * float(lat - i) / lat
			var col := base * shade
			col.a = 1
			# ring runs +phi; outward CCW: a, c, d, b
			mb.tri("rock", a, b, c, col)
			mb.tri("rock", b, d, c, col)
	return mb.commit()

static func _pole() -> ArrayMesh:
	var mb := MeshBuilder.new()
	var wood := Color(0.42, 0.33, 0.25)
	mb.cyl("wood", Transform3D.IDENTITY, 0.15, 0.12, 9.5, 6, wood, true, true, 0.5)
	mb.boxp("wood", Vector3(0, 8.9, 0), Vector3(2.4, 0.14, 0.14), wood, 0.5)
	mb.boxp("wood", Vector3(0, 8.2, 0), Vector3(1.4, 0.12, 0.12), wood, 0.5)
	for x in [-1.05, -0.45, 0.45, 1.05]:
		mb.cyl("glass", Transform3D(Basis.IDENTITY, Vector3(x, 8.97, 0)), 0.05, 0.04, 0.16, 5, Color(0.3, 0.55, 0.45))
	return mb.commit()

static func _marker() -> ArrayMesh:
	var mb := MeshBuilder.new()
	mb.boxp("paint", Vector3(0, 0.6, 0), Vector3(0.1, 1.2, 0.04), Color(0.9, 0.9, 0.85))
	mb.boxp("paint", Vector3(0, 1.1, -0.021), Vector3(0.1, 0.12, 0.01), Color(0.1, 0.3, 0.7))
	return mb.commit()

# ------------------------------------------------------------- vegetation

static func _near_pad(p: Vector2, margin: float) -> bool:
	for k in WorldData.PADS:
		var pad: Dictionary = WorldData.PADS[k]
		if p.distance_to(pad.c) < pad.r + margin:
			return true
	return false

static func _vegetation(root: Node3D, world: WorldData, br: Breakables, rng: RandomNumberGenerator) -> void:
	var region := 768.0
	var groups: Dictionary = {}   # "kind|rx|rz" -> Array[Transform3D]
	var rock_body := StaticBody3D.new()
	rock_body.name = "Boulders"
	root.add_child(rock_body)
	var tries := 26000
	for t in tries:
		var x := rng.randf_range(-WorldData.BOUND + 40, WorldData.BOUND - 40)
		var z := rng.randf_range(-WorldData.BOUND + 40, WorldData.BOUND - 40)
		var p2 := Vector2(x, z)
		var rd := world.road_dist(x, z)
		if rd < 13.0:
			continue
		var fm := world.flat_mask(x, z)
		var sl := world.slope(x, z)
		var h := world.height(x, z)
		if _near_pad(p2, 15.0):
			continue
		var roll := rng.randf()
		var kind := ""
		if fm > 0.2:
			if roll < 0.08:
				kind = "bush1"
			else:
				continue
		elif sl > 0.45:
			if roll < 0.25:
				kind = "rock%d" % rng.randi_range(0, 2)
			else:
				continue
		elif h > 170.0:
			kind = "bush1" if roll < 0.5 else "rock%d" % rng.randi_range(0, 2)
		else:
			if roll < 0.2:
				kind = "joshua%d" % rng.randi_range(0, 3)
			elif roll < 0.86:
				kind = "bush%d" % rng.randi_range(0, 2)
			else:
				kind = "rock%d" % rng.randi_range(0, 2)
		var yaw := rng.randf() * TAU
		var s := rng.randf_range(0.75, 1.3)
		if kind.begins_with("rock"):
			s = rng.randf_range(0.4, 1.3) if rng.randf() < 0.85 else rng.randf_range(2.0, 4.0)
		var n := world.normal(x, z)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
		if kind.begins_with("bush") or kind.begins_with("rock"):
			basis = _align(n) * basis
		var xf := Transform3D(basis, Vector3(x, h - (0.15 * s if kind.begins_with("rock") else 0.05), z))
		if kind.begins_with("joshua"):
			var rx := floori((x + WorldData.HALF) / region)
			var rz := floori((z + WorldData.HALF) / region)
			br.add("%s_%d_%d" % [kind, rx, rz], _m[kind], xf, 0.55 * s, "tree", 2600.0)
			continue
		if kind.begins_with("rock") and s > 1.9:
			var cs := CollisionShape3D.new()
			var sp := SphereShape3D.new()
			sp.radius = s * 0.85
			cs.shape = sp
			cs.position = xf.origin + Vector3(0, s * 0.2, 0)
			rock_body.add_child(cs)
		var rx2 := floori((x + WorldData.HALF) / region)
		var rz2 := floori((z + WorldData.HALF) / region)
		var key := "%s|%d|%d" % [kind, rx2, rz2]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(xf)
	for key in groups:
		var kind: String = key.split("|")[0]
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _m[kind]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = 1100.0 if kind.begins_with("bush") else 2400.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)

static func _align(n: Vector3) -> Basis:
	var y := n.normalized()
	var x := (Vector3.RIGHT - y * y.dot(Vector3.RIGHT)).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)

# ---------------------------------------------------------- telephone lines

static func _telephone(root: Node3D, world: WorldData, br: Breakables) -> void:
	var wires := MeshBuilder.new()
	for rname in ["us95", "mercury", "tonopah"]:
		var r: WorldData.Road = world.road(rname)
		var spacing := 55.0
		var next := 20.0
		var tops: Array = []
		for k in r.pts.size():
			if r.dist[k] < next:
				continue
			next += spacing
			var p := r.pts[k]
			var k2 := mini(k + 1, r.pts.size() - 1)
			var dir := r.pts[k2] - r.pts[maxi(k - 1, 0)]
			dir.y = 0
			if dir.length() < 0.01:
				continue
			dir = dir.normalized()
			var right := dir.cross(Vector3.UP)
			var q := p + right * (r.width * 0.5 + 6.0)
			if not world.in_bounds(q.x, q.z, 30.0):
				tops.append(null)
				continue
			q.y = world.height(q.x, q.z) - 0.2
			var basis := Basis.looking_at(dir, Vector3.UP)
			var xf := Transform3D(basis, q)
			var rx := floori((q.x + WorldData.HALF) / 768.0)
			var rz := floori((q.z + WorldData.HALF) / 768.0)
			br.add("pole_%d_%d" % [rx, rz], _m["pole"], xf, 0.35, "pole", 2400.0)
			tops.append(xf)
		# wires between consecutive poles, with a little sag
		for i in tops.size() - 1:
			if tops[i] == null or tops[i + 1] == null:
				continue
			var a: Transform3D = tops[i]
			var b: Transform3D = tops[i + 1]
			for x in [-1.05, -0.45, 0.45, 1.05]:
				var pa := a * Vector3(x, 9.05, 0)
				var pb := b * Vector3(x, 9.05, 0)
				var prev := pa
				for s in range(1, 5):
					var t := s / 4.0
					var p := pa.lerp(pb, t) - Vector3(0, sin(t * PI) * 0.7, 0)
					_wire(wires, prev, p)
					prev = p
	var mi := MeshInstance3D.new()
	mi.mesh = wires.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 900.0
	root.add_child(mi)

static func _wire(mb: MeshBuilder, a: Vector3, b: Vector3) -> void:
	var c := Color(0.08, 0.08, 0.08)
	var w := 0.025
	mb.quad("plain", a + Vector3(0, -w, 0), b + Vector3(0, -w, 0), b + Vector3(0, w, 0), a + Vector3(0, w, 0), c)
	mb.quad("plain", a + Vector3(0, w, 0), b + Vector3(0, w, 0), b + Vector3(0, -w, 0), a + Vector3(0, -w, 0), c)

# ------------------------------------------------------------------- signs

## Billboard specs: road, distance along road (m), side (+1 right), lines, colours.
const BILLBOARDS := [
	["us95", 900.0, 1, ["ATOMIC COLA", "It's a BLAST!"], Color(0.85, 0.15, 0.12), Color(1, 0.95, 0.85)],
	["us95", 2300.0, -1, ["HAL'S EATS  2 MI", "STEAKS - PIE - DIESEL"], Color(0.15, 0.3, 0.55), Color(1, 0.9, 0.5)],
	["us95", 3600.0, 1, ["STARLIGHT CROWN", "LAS VEGAS - 72 MI"], Color(0.1, 0.08, 0.12), Color(1, 0.8, 0.3)],
	["us95", 5200.0, -1, ["CIVIL DEFENSE", "IN A FLASH - DUCK & COVER"], Color(0.9, 0.85, 0.7), Color(0.1, 0.1, 0.1)],
	["us95", 6400.0, 1, ["SEE THE BOMB!", "Atomic View Motel - Pool"], Color(0.2, 0.55, 0.6), Color(1, 1, 0.9)],
	["mercury", 700.0, -1, ["U.S. GOVERNMENT PROPERTY", "NEVADA PROVING GROUNDS - NO TRESPASSING"], Color(0.95, 0.95, 0.9), Color(0.7, 0.1, 0.08)],
	["mercury", 2600.0, 1, ["VALE FREIGHT LINES", "We Haul Anything. Anything."], Color(0.3, 0.3, 0.32), Color(1, 0.85, 0.3)],
	["tonopah", 500.0, 1, ["TONOPAH  38", "GOLDFIELD  64"], Color(0.1, 0.35, 0.18), Color(1, 1, 1)],
]

## Serial rhyming signs spaced along the road.
const SERIAL := ["DON'T RACE THE ATOM", "YOU'LL LOSE THE BET", "IT'S BEEN AROUND", "A WHOLE LOT LONGER YET", "- KOOL-TOP HAIR TONIC -"]

static func _signs(root: Node3D, world: WorldData, br: Breakables, time: String) -> void:
	var night := time in ["night", "dusk", "dawn"]
	for b in BILLBOARDS:
		var r: WorldData.Road = world.road(b[0])
		var k := _index_at(r, b[1])
		var p := r.pts[k]
		var dir := (r.pts[mini(k + 2, r.pts.size() - 1)] - r.pts[maxi(k - 2, 0)])
		dir.y = 0
		dir = dir.normalized()
		var right := dir.cross(Vector3.UP)
		var q: Vector3 = p + right * float(b[2]) * (r.width * 0.5 + 16.0)
		q.y = world.height(q.x, q.z)
		var node := billboard(b[3], b[4], b[5], night)
		root.add_child(node)
		node.global_position = q
		# face oncoming traffic (angled slightly toward the road)
		node.look_at(q - dir * 10.0 - right * b[2] * 4.0, Vector3.UP)
	# serial signs near the Boneyard turn-off
	var r95: WorldData.Road = world.road("us95")
	for i in SERIAL.size():
		var k := _index_at(r95, 4300.0 + i * 70.0)
		var p := r95.pts[k]
		var dir := (r95.pts[mini(k + 2, r95.pts.size() - 1)] - r95.pts[maxi(k - 2, 0)])
		dir.y = 0
		dir = dir.normalized()
		var right := dir.cross(Vector3.UP)
		var q := p + right * (r95.width * 0.5 + 3.5)
		q.y = world.height(q.x, q.z)
		var n := small_sign(SERIAL[i], Color(0.8, 0.12, 0.1), Color(1, 1, 1))
		root.add_child(n)
		n.global_position = q
		n.look_at(q - dir * 10.0, Vector3.UP)
	# mile markers
	for rname in ["us95", "mercury"]:
		var r: WorldData.Road = world.road(rname)
		var d := 400.0
		while d < r.dist[r.dist.size() - 1]:
			var k := _index_at(r, d)
			var p := r.pts[k]
			var dir := (r.pts[mini(k + 2, r.pts.size() - 1)] - r.pts[maxi(k - 2, 0)])
			dir.y = 0
			dir = dir.normalized()
			var q := p + dir.cross(Vector3.UP) * (r.width * 0.5 + 2.0)
			if world.in_bounds(q.x, q.z, 20):
				q.y = world.height(q.x, q.z)
				br.add("marker", _m["marker"], Transform3D(Basis.looking_at(dir), q), 0.3, "sign", 700.0)
			d += 1609.0
	# road closures where roads leave the basin
	for rname in world.roads:
		var r: WorldData.Road = world.road(rname)
		for end in [0, r.pts.size() - 1]:
			var p := r.pts[end]
			if world.in_bounds(p.x, p.z, 60.0):
				continue
			# walk inward until inside bounds
			var k: int = end
			var step := 1 if end == 0 else -1
			while not world.in_bounds(r.pts[k].x, r.pts[k].z, 70.0) and k > 0 and k < r.pts.size() - 1:
				k += step
			var q := r.pts[k]
			var dir := (r.pts[k + step] - q).normalized() if k + step >= 0 and k + step < r.pts.size() else Vector3.FORWARD
			Locations.roadblock(root, q, dir, r.width, "ROAD CLOSED - U.S. ATOMIC TEST AREA")

static func _index_at(r: WorldData.Road, d: float) -> int:
	for k in r.dist.size():
		if r.dist[k] >= d:
			return k
	return r.dist.size() - 1

## Big roadside billboard on two posts, facing -Z.
static func billboard(lines: Array, bg: Color, fg: Color, lit: bool) -> Node3D:
	var n := Node3D.new()
	var mb := MeshBuilder.new()
	var w := 9.0
	var h := 4.0
	var y0 := 3.2
	for x in [-w * 0.33, w * 0.33]:
		mb.boxp("wood", Vector3(x, y0 * 0.5 + 1.0, 0.2), Vector3(0.3, y0 + 2.0, 0.3), Color(0.45, 0.36, 0.28), 0.5)
	mb.boxp("plain", Vector3(0, y0 + h * 0.5, 0.1), Vector3(w, h, 0.3), bg, 0.25, Color(0.5, 0.4, 0.3))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	n.add_child(mi)
	var col := CollisionShape3D.new()
	var body := StaticBody3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w * 0.7, 2.0, 0.6)
	col.shape = bs
	col.position = Vector3(0, 1.0, 0.2)
	body.add_child(col)
	n.add_child(body)
	for i in lines.size() * 2:
		var back := i >= lines.size()
		var li := i % lines.size()
		var l := Label3D.new()
		l.text = lines[li]
		l.font = Lib.font("rye") if li == 0 else Lib.font("bebasneue")
		l.font_size = 96 if li == 0 else 72
		l.pixel_size = 0.012 if li == 0 else 0.009
		l.modulate = fg
		l.outline_size = 0
		l.position = Vector3(0, y0 + h * (0.68 if li == 0 else 0.28), 0.26 if back else -0.06)
		l.rotation.y = 0.0 if back else PI
		l.double_sided = false
		l.shaded = true
		l.width = 780.0
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.visibility_range_end = 1200.0
		n.add_child(l)
	if lit:
		for x in [-w * 0.3, w * 0.3]:
			var sl := SpotLight3D.new()
			sl.position = Vector3(x, y0 - 0.5, -1.5)
			sl.rotation_degrees = Vector3(70, 180, 0)
			sl.spot_range = 8.0
			sl.spot_angle = 50.0
			sl.light_energy = 3.0
			sl.light_color = Color(1, 0.85, 0.6)
			n.add_child(sl)
	return n

static func small_sign(text: String, bg: Color, fg: Color) -> Node3D:
	var n := Node3D.new()
	var mb := MeshBuilder.new()
	mb.boxp("wood", Vector3(0, 1.0, 0.05), Vector3(0.12, 2.0, 0.12), Color(0.45, 0.36, 0.28), 0.5)
	mb.boxp("plain", Vector3(0, 1.75, 0), Vector3(2.2, 0.55, 0.05), bg)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	n.add_child(mi)
	var l := Label3D.new()
	l.text = text
	l.font = Lib.font("bebasneue")
	l.font_size = 64
	l.pixel_size = 0.0055
	l.modulate = fg
	l.outline_size = 0
	l.position = Vector3(0, 1.75, -0.03)
	l.rotation.y = PI
	l.shaded = true
	l.visibility_range_end = 400.0
	n.add_child(l)
	return n
