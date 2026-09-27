class_name Locations
## Hand-placed set pieces. Each location is built in its own local frame
## (origin at the pad centre) into merged meshes plus box colliders.

const WOOD := Color(0.62, 0.5, 0.38)
const OLDWOOD := Color(0.55, 0.47, 0.4)
const TIN := Color(0.78, 0.78, 0.76)
const RED := Color(0.62, 0.16, 0.12)

class Site:
	var root: Node3D
	var mb := MeshBuilder.new()
	var body := StaticBody3D.new()
	var xf := Transform3D.IDENTITY
	var night := false

	func solid(center: Vector3, size: Vector3, yaw: float = 0.0) -> void:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = size
		cs.shape = b
		cs.transform = xf * Transform3D(Basis(Vector3.UP, yaw), center)
		body.add_child(cs)

	func box(mat: String, center: Vector3, size: Vector3, col: Color, collide: bool = true, yaw: float = 0.0, uvs: float = 0.25, top = null) -> void:
		mb.box(mat, Transform3D(Basis(Vector3.UP, yaw), center), size, col, uvs, top)
		if collide:
			solid(center, size, yaw)

	func light(p: Vector3, col: Color, energy: float = 2.0, rng: float = 25.0) -> void:
		if not night:
			return
		var l := OmniLight3D.new()
		l.light_color = col
		l.light_energy = energy
		l.omni_range = rng
		l.omni_attenuation = 1.2
		l.position = xf * p
		root.add_child(l)

	func label(text: String, p: Vector3, yaw: float, size: float, col: Color, font: String = "rye", neon: bool = false) -> Label3D:
		var l := Label3D.new()
		l.text = text
		l.font = Lib.font(font)
		l.font_size = 96
		l.pixel_size = size / 96.0
		l.modulate = col * (2.2 if neon and night else 1.0)
		l.outline_size = 12 if neon else 0
		l.outline_modulate = Color(col.r * 0.4, col.g * 0.4, col.b * 0.4, 1) if neon else Color(0, 0, 0, 0)
		l.shaded = not neon
		l.double_sided = true
		l.transform = xf * Transform3D(Basis(Vector3.UP, yaw), p)
		l.visibility_range_end = 1500.0
		root.add_child(l)
		return l

	func finish(name: String) -> void:
		var mi := MeshInstance3D.new()
		mi.name = name
		mi.mesh = mb.commit()
		mi.transform = xf
		mi.visibility_range_end = 4000.0
		root.add_child(mi)
		body.name = name + "Body"
		root.add_child(body)

static func _site(root: Node3D, world: WorldData, key: String, yaw: float, time: String) -> Site:
	var s := Site.new()
	var c: Vector2 = WorldData.PADS[key].c
	s.root = root
	s.xf = Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, world.height(c.x, c.y), c.y))
	s.night = time in ["night", "dusk", "dawn"]
	return s

static func build_all(root: Node3D, world: WorldData, br: Breakables, time: String) -> void:
	boneyard(root, world, time)
	hals(root, world, time)
	gold_creek(root, world, time)
	depot(root, world, time)
	mine(root, world, time)
	airstrip(root, world, time)
	frenchman(root, world, time)
	if time in ["night", "dusk", "dawn"]:
		vegas_glow(root)

# -------------------------------------------------------------- primitives

static func house(s: Site, c: Vector3, w: float, d: float, h: float, mat: String, col: Color, roof_col: Color, yaw: float = 0.0, gable: bool = true) -> void:
	s.box(mat, c + Vector3(0, h * 0.5, 0), Vector3(w, h, d), col, true, yaw, 0.25)
	var b := Basis(Vector3.UP, yaw)
	var t := Transform3D(b, c)
	if gable:
		var rh := w * 0.35
		var o := 0.4
		var p1 := t * Vector3(-w * 0.5 - o, h, -d * 0.5 - o)
		var p2 := t * Vector3(w * 0.5 + o, h, -d * 0.5 - o)
		var p3 := t * Vector3(w * 0.5 + o, h, d * 0.5 + o)
		var p4 := t * Vector3(-w * 0.5 - o, h, d * 0.5 + o)
		var r1 := t * Vector3(0, h + rh, -d * 0.5 - o)
		var r2 := t * Vector3(0, h + rh, d * 0.5 + o)
		# two roof slopes (CCW from outside)
		s.mb.quad("metal", p2, r1, r2, p3, roof_col)
		s.mb.quad("metal", p4, r2, r1, p1, roof_col)
		# gable ends
		s.mb.tri(mat, t * Vector3(-w * 0.5, h, d * 0.5), t * Vector3(w * 0.5, h, d * 0.5), t * Vector3(0, h + rh, d * 0.5), col)
		s.mb.tri(mat, t * Vector3(w * 0.5, h, -d * 0.5), t * Vector3(-w * 0.5, h, -d * 0.5), t * Vector3(0, h + rh, -d * 0.5), col)
	else:
		s.mb.box("metal", Transform3D(b, c + Vector3(0, h + 0.1, 0)), Vector3(w + 0.6, 0.2, d + 0.6), roof_col)
	# door + windows on the -Z face
	s.mb.box("plain", Transform3D(b, c + b * Vector3(0, 1.05, -d * 0.5 - 0.03)), Vector3(1.1, 2.1, 0.05), Color(0.2, 0.15, 0.12))
	for x in [-w * 0.3, w * 0.3]:
		if w > 5.0:
			s.mb.box("glass", Transform3D(b, c + b * Vector3(x, 1.6, -d * 0.5 - 0.03)), Vector3(1.2, 1.0, 0.05), Color(0.12, 0.14, 0.16))

static func facade(s: Site, c: Vector3, w: float, h: float, col: Color, yaw: float, sign_text: String = "") -> void:
	var b := Basis(Vector3.UP, yaw)
	house(s, c, w, 9.0, h * 0.7, "wood", col, OLDWOOD * 0.8, yaw, false)
	s.box("wood", c + b * Vector3(0, h * 0.5 + 0.5, -4.6), Vector3(w + 0.4, h + 1.0, 0.25), col, false, yaw)
	# porch roof on posts
	s.mb.box("wood", Transform3D(b, c + b * Vector3(0, 3.0, -6.0)), Vector3(w, 0.15, 2.8), OLDWOOD)
	for x in [-w * 0.45, w * 0.45]:
		s.mb.box("wood", Transform3D(b, c + b * Vector3(x, 1.5, -7.2)), Vector3(0.18, 3.0, 0.18), OLDWOOD)
	if sign_text != "":
		s.label(sign_text, c + b * Vector3(0, h * 0.8, -4.8), yaw + PI, 0.9, Color(0.95, 0.9, 0.75), "rye")

static func quonset(s: Site, c: Vector3, length: float, r: float, yaw: float = 0.0, col: Color = TIN) -> void:
	var b := Basis(Vector3.UP, yaw)
	var seg := 10
	var rings: Array = []
	var cols: Array = []
	for zi in 2:
		var z := -length * 0.5 + zi * length
		var ring := PackedVector3Array()
		# loft convention: top first, then +X down to the ground, floor, -X back up
		var half := seg / 2
		for k in half + 1:
			var a := PI * 0.5 - PI * 0.5 * k / half
			ring.append(Vector3(cos(a) * r, sin(a) * r, z))
		for k in range(1, 4):
			ring.append(Vector3(r - 2.0 * r * k / 4.0, 0.0, z))
		for k in half:
			var a := PI - PI * 0.5 * k / half
			ring.append(Vector3(cos(a) * r, sin(a) * r, z))
		rings.append(ring)
		cols.append(col)
	var old := s.mb.xf
	s.mb.xf = s.mb.xf * Transform3D(b, c)
	# rotate so the ring starts at top: our ring is ordered from right side upward; fine for quonset
	s.mb.loft("metal", rings, cols, true, true, 0.2)
	s.mb.box("plain", Transform3D(Basis.IDENTITY, Vector3(0, r * 0.4, -length * 0.5 - 0.05)), Vector3(r * 1.1, r * 0.8, 0.1), Color(0.15, 0.13, 0.12))
	s.mb.xf = old
	s.solid(c + Vector3(0, r * 0.5, 0), Vector3(r * 2.0, r, length), yaw)

static func water_tower(s: Site, c: Vector3, h: float, r: float, mat: String = "wood", col: Color = WOOD) -> void:
	for a in 4:
		var ang := PI * 0.25 + a * PI * 0.5
		var bot := c + Vector3(cos(ang), 0, sin(ang)) * r * 1.1
		var tp := c + Vector3(cos(ang), 0, sin(ang)) * r * 0.8 + Vector3(0, h, 0)
		s.mb.cyl_between("wood", bot, tp, 0.2, 5, OLDWOOD * 0.8)
		s.solid(bot + Vector3(0, 2, 0), Vector3(0.5, 4, 0.5))
	for k in 3:
		var y := h * (0.3 + k * 0.25)
		for a in 4:
			var a0 := PI * 0.25 + a * PI * 0.5
			var a1 := a0 + PI * 0.5
			var f := lerpf(1.1, 0.8, y / h)
			s.mb.cyl_between("wood", c + Vector3(cos(a0), 0, sin(a0)) * r * f + Vector3(0, y, 0), c + Vector3(cos(a1), 0, sin(a1)) * r * f + Vector3(0, y, 0), 0.08, 4, OLDWOOD * 0.8)
	s.mb.cyl(mat, Transform3D(Basis.IDENTITY, c + Vector3(0, h, 0)), r, r, r * 1.3, 12, col, true, true, 0.3)
	s.mb.cyl("metal", Transform3D(Basis.IDENTITY, c + Vector3(0, h + r * 1.3, 0)), r * 1.08, 0.1, r * 0.6, 12, Color(0.45, 0.4, 0.35))

static func lattice(s: Site, c: Vector3, h: float, w0: float, w1: float, col: Color, levels: int = 6) -> void:
	var corners := [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3(-1, 0, 1)]
	for k in 4:
		s.mb.cyl_between("metal", c + corners[k] * w0 * 0.5, c + corners[k] * w1 * 0.5 + Vector3(0, h, 0), 0.09, 4, col)
	for l in levels:
		var y0 := h * l / levels
		var y1 := h * (l + 1) / levels
		var f0 := lerpf(w0, w1, float(l) / levels) * 0.5
		var f1 := lerpf(w0, w1, float(l + 1) / levels) * 0.5
		for k in 4:
			var a: Vector3 = corners[k]
			var b: Vector3 = corners[(k + 1) % 4]
			s.mb.cyl_between("metal", c + a * f0 + Vector3(0, y0, 0), c + b * f1 + Vector3(0, y1, 0), 0.05, 3, col)
			s.mb.cyl_between("metal", c + a * f1 + Vector3(0, y1, 0), c + b * f1 + Vector3(0, y1, 0), 0.05, 3, col)
	s.solid(c + Vector3(0, 3, 0), Vector3(w0, 6, w0))

static func windmill(s: Site, c: Vector3) -> void:
	lattice(s, c, 11.0, 3.0, 0.6, Color(0.5, 0.5, 0.48), 5)
	var hub := c + Vector3(0, 11.3, -0.4)
	for k in 12:
		var a := TAU * k / 12.0
		s.mb.cyl_between("metal", hub, hub + Vector3(cos(a), sin(a), 0) * 2.2, 0.12, 3, Color(0.7, 0.7, 0.68))
	s.mb.box("metal", Transform3D(Basis.IDENTITY, c + Vector3(0, 11.3, 1.4)), Vector3(0.05, 1.2, 2.2), Color(0.7, 0.2, 0.15))

static func pump(s: Site, c: Vector3, col: Color = RED) -> void:
	s.box("paint", c + Vector3(0, 0.9, 0), Vector3(0.6, 1.8, 0.45), col)
	s.mb.cyl("glass", Transform3D(Basis.IDENTITY, c + Vector3(0, 1.8, 0)), 0.25, 0.25, 0.45, 8, Color(0.95, 0.9, 0.8))

static func barrel(s: Site, c: Vector3, col: Color) -> void:
	s.mb.cyl("paint", Transform3D(Basis.IDENTITY, c), 0.32, 0.32, 0.9, 8, col)

static func tire_pile(s: Site, c: Vector3, n: int) -> void:
	for i in n:
		var p := c + Vector3((i % 3) * 0.3 - 0.3, int(i / 3) * 0.26, (i % 2) * 0.2)
		s.mb.cyl("rubber", Transform3D(Basis.IDENTITY, p), 0.38, 0.38, 0.24, 8, Color(0.08, 0.08, 0.08))
	s.solid(c + Vector3(0, 0.5, 0), Vector3(1.4, 1.0, 1.2))

static func wreck(s: Site, key: String, p: Vector3, yaw: float, roll: float = 0.0, burnt: bool = false, rusty: bool = true) -> void:
	var d := CarBuilder.build(key, {"rusty": rusty} if not burnt else {"rusty": true, "paint": Color(0.18, 0.16, 0.15), "paint2": Color(0.2, 0.17, 0.15)})
	var mi := MeshInstance3D.new()
	mi.mesh = d.body
	var t := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, roll), p)
	mi.transform = s.xf * t
	mi.visibility_range_end = 900.0
	s.root.add_child(mi)
	if not burnt:
		for wp in d.wheels:
			var wm := MeshInstance3D.new()
			wm.mesh = d.wheel
			wm.transform = s.xf * t * Transform3D(Basis(Vector3.UP, PI if wp.x < 0 else 0.0), wp)
			wm.visibility_range_end = 400.0
			s.root.add_child(wm)
	var sz: Vector3 = d.size
	s.solid(p + Vector3(0, 0.7, 0), Vector3(sz.x, 1.4, sz.z), yaw)

static func fence_posts(s: Site, pts: Array, gap: float = 3.0) -> void:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var n := int(a.distance_to(b) / gap)
		for k in n:
			var p := a.lerp(b, float(k) / n)
			s.mb.box("wood", Transform3D(Basis.IDENTITY, p + Vector3(0, 0.75, 0)), Vector3(0.14, 1.5, 0.14), OLDWOOD, 0.5)
		for y in [0.6, 1.2]:
			s.mb.cyl_between("plain", a + Vector3(0, y, 0), b + Vector3(0, y, 0), 0.015, 3, Color(0.3, 0.3, 0.3))

static func floodlight(s: Site, p: Vector3, target: Vector3) -> void:
	s.mb.cyl("wood", Transform3D(Basis.IDENTITY, p), 0.14, 0.12, 8.0, 5, OLDWOOD)
	s.mb.box("metal", Transform3D(Basis.IDENTITY, p + Vector3(0, 8.0, 0)), Vector3(1.2, 0.5, 0.5), Color(0.3, 0.3, 0.3))
	s.mb.box("lamp", Transform3D(Basis.IDENTITY, p + Vector3(0, 7.9, -0.01)), Vector3(1.0, 0.3, 0.52), Color(1, 0.95, 0.8))
	if s.night:
		var sl := SpotLight3D.new()
		sl.light_color = Color(1, 0.9, 0.7)
		sl.light_energy = 6.0
		sl.spot_range = 55.0
		sl.spot_angle = 45.0
		s.root.add_child(sl)
		sl.global_position = s.xf * (p + Vector3(0, 7.8, 0))
		sl.look_at(s.xf * target, Vector3.UP)

static func roadblock(root: Node3D, p: Vector3, dir: Vector3, width: float, text: String) -> void:
	var s := Site.new()
	s.root = root
	dir.y = 0
	dir = dir.normalized()
	s.xf = Transform3D(Basis.looking_at(dir, Vector3.UP), p)
	for k in 5:
		var x := -width * 0.5 + (k + 0.5) * width / 5.0
		s.mb.box("paint", Transform3D(Basis.IDENTITY, Vector3(x, 1.0, 0)), Vector3(width / 5.0 - 0.4, 0.3, 0.15), Color(0.95, 0.95, 0.9) if k % 2 == 0 else Color(0.85, 0.2, 0.1))
		s.mb.box("wood", Transform3D(Basis.IDENTITY, Vector3(x - 0.9, 0.5, 0)), Vector3(0.1, 1.0, 0.6), OLDWOOD)
		s.mb.box("wood", Transform3D(Basis.IDENTITY, Vector3(x + 0.9, 0.5, 0)), Vector3(0.1, 1.0, 0.6), OLDWOOD)
	s.solid(Vector3(0, 1.0, 0), Vector3(width + 4.0, 2.0, 1.0))
	s.label(text, Vector3(0, 2.1, 0.1), PI, 0.5, Color(0.9, 0.2, 0.1), "bebasneue")
	s.finish("Roadblock")

# --------------------------------------------------------------- locations

static func boneyard(root: Node3D, world: WorldData, time: String) -> void:
	var s := _site(root, world, "boneyard", 0.0, time)
	quonset(s, Vector3(0, 0, -45), 26.0, 7.0, 0.0)
	s.label("DELGADO SALVAGE & REPAIR", Vector3(0, 8.2, -58.5), PI, 1.4, Color(0.95, 0.75, 0.3), "rye", true)
	# Airstream-style trailer home
	var tr := [
		[-0.5, 0.35, 0.3, 1.0], [-0.44, 0.5, 0.2, 2.6], [0.44, 0.5, 0.2, 2.6], [0.5, 0.35, 0.3, 1.0],
	]
	var old := s.mb.xf
	s.mb.xf = old * Transform3D(Basis(Vector3.UP, 0.3), Vector3(34, 0.6, -30))
	CarBuilder.loft_body(s.mb, "chrome", 8.0, 2.5, tr, Color(0.8, 0.8, 0.82), Color(0.8, 0.8, 0.82), 9.0, 2.2, 0.8)
	s.mb.box("glass", Transform3D(Basis.IDENTITY, Vector3(1.26, 1.8, 0)), Vector3(0.02, 0.6, 3.0), Color(0.15, 0.18, 0.2))
	s.mb.xf = old
	s.solid(Vector3(34, 1.8, -30), Vector3(2.6, 3.0, 8.0), 0.3)
	water_tower(s, Vector3(-36, 0, -48), 11.0, 3.5, "metal", Color(0.72, 0.7, 0.66))
	s.label("BONEYARD", Vector3(-36, 14.5, -44.3), 0.0, 2.2, Color(0.25, 0.2, 0.18), "rye")
	windmill(s, Vector3(-52, 0, 8))
	lattice(s, Vector3(46, 0, -56), 26.0, 3.0, 0.5, Color(0.7, 0.2, 0.15), 9)
	pump(s, Vector3(12, 0, -34))
	pump(s, Vector3(15, 0, -34), Color(0.2, 0.35, 0.6))
	s.label("GAS", Vector3(13.5, 2.9, -34), PI, 0.8, Color(1, 0.9, 0.6), "bebasneue", true)
	for i in 6:
		barrel(s, Vector3(-14 + (i % 3) * 0.7, 0, -36 + int(i / 3) * 0.7), [Color(0.6, 0.2, 0.1), Color(0.3, 0.35, 0.25), Color(0.2, 0.3, 0.5)][i % 3])
	tire_pile(s, Vector3(-20, 0, -30), 9)
	tire_pile(s, Vector3(22, 0, -20), 7)
	# engine hoist A-frame
	for sx in [-1.5, 1.5]:
		s.mb.cyl_between("metal", Vector3(8 + sx, 0, -52), Vector3(8, 6, -52), 0.12, 4, Color(0.4, 0.4, 0.4))
	# ring of stacked wrecks with a gap to the east (toward the access road)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var keys := ["sedan", "coupe_junk", "wagon", "pickup_junk"]
	for k in 40:
		var a := TAU * k / 40.0
		if absf(wrapf(a + 0.5, -PI, PI)) < 0.3 or absf(wrapf(a + 2.7, -PI, PI)) < 0.3:
			continue   # gaps for the two roads
		var p := Vector3(cos(a) * 64.0, 0, sin(a) * 64.0 - 10.0)
		var key: String = ["sedan", "wagon", "sedan", "pickup"][k % 4]
		wreck(s, key if key != "pickup" else "hauler", p, -a + PI * 0.5 + rng.randf_range(-0.2, 0.2))
		if k % 3 == 0:
			wreck(s, "sedan", p + Vector3(0, 1.45, 0), -a + PI * 0.5 + rng.randf_range(-0.3, 0.3))
	s.light(Vector3(0, 8, -35), Color(1, 0.8, 0.55), 3.0, 45.0)
	s.light(Vector3(30, 5, -25), Color(1, 0.8, 0.55), 2.0, 25.0)
	s.finish("Boneyard")

static func hals(root: Node3D, world: WorldData, time: String) -> void:
	var s := _site(root, world, "hals", 0.0, time)
	# diner: stucco with big windows, facing west toward the highway
	house(s, Vector3(52, 0, -12), 16.0, 10.0, 4.2, "stucco", Color(0.9, 0.86, 0.78), Color(0.6, 0.15, 0.12), PI * 0.5, false)
	for z in [-16.0, -12.0, -8.0]:
		s.mb.box("glass", Transform3D(Basis.IDENTITY, Vector3(46.9, 2.0, z)), Vector3(0.05, 1.6, 3.2), Color(0.95, 0.85, 0.55) if s.night else Color(0.15, 0.18, 0.2))
	s.mb.box("paint", Transform3D(Basis.IDENTITY, Vector3(46.8, 3.6, -12)), Vector3(0.1, 0.35, 16.2), Color(0.1, 0.55, 0.55))
	# neon pole sign
	s.mb.cyl("metal", Transform3D(Basis.IDENTITY, Vector3(30, 0, -26)), 0.25, 0.2, 11.0, 6, Color(0.6, 0.6, 0.6))
	s.box("paint", Vector3(30, 11.5, -26), Vector3(0.4, 3.0, 7.0), Color(0.15, 0.2, 0.3), false)
	s.label("HAL'S EATS", Vector3(29.7, 12.2, -26), -PI * 0.5, 1.5, Color(1.0, 0.3, 0.35), "rye", true)
	s.label("DIESEL - STEAKS - PIE", Vector3(29.7, 10.8, -26), -PI * 0.5, 0.6, Color(0.4, 0.9, 1.0), "bebasneue", true)
	s.label("HAL'S EATS", Vector3(30.3, 12.2, -26), PI * 0.5, 1.5, Color(1.0, 0.3, 0.35), "rye", true)
	# pump island + canopy
	for z in [12.0, 20.0]:
		pump(s, Vector3(26, 0, z))
		pump(s, Vector3(26, 0, z + 2.5), Color(0.9, 0.85, 0.2))
	for p in [Vector3(22, 0, 8), Vector3(30, 0, 8), Vector3(22, 0, 27), Vector3(30, 0, 27)]:
		s.box("metal", p + Vector3(0, 2.4, 0), Vector3(0.3, 4.8, 0.3), Color(0.9, 0.9, 0.88))
	s.mb.box("paint", Transform3D(Basis.IDENTITY, Vector3(26, 5.0, 17.5)), Vector3(12, 0.5, 23), Color(0.92, 0.9, 0.85), 0.25, Color(0.6, 0.15, 0.12))
	# motel row
	for i in 6:
		house(s, Vector3(72, 0, 30 + i * 6.5), 8.0, 6.2, 3.2, "stucco", Color(0.88, 0.8, 0.62), Color(0.3, 0.55, 0.5), PI * 0.5, false)
	s.label("MOTEL - VACANCY", Vector3(62, 4.5, 26), -PI * 0.5, 0.9, Color(1.0, 0.6, 0.2), "bebasneue", true)
	# parked rigs
	wreck(s, "semi", Vector3(90, 0, -20), 0.1, 0.0, false, false)
	# Hollis's burned-out rig behind the diner
	wreck(s, "semi", Vector3(80, 0, -52), -1.2, 0.05, true)
	s.light(Vector3(26, 4.6, 17), Color(1, 0.9, 0.7), 3.0, 30.0)
	s.light(Vector3(46, 3.0, -12), Color(1, 0.7, 0.5), 2.0, 20.0)
	s.finish("HalsTruckStop")

static func gold_creek(root: Node3D, world: WorldData, time: String) -> void:
	var s := _site(root, world, "gold_creek", 0.0, time)
	# main street runs east-west; facades on both sides
	var names := ["SALOON", "ASSAY OFFICE", "", "GENERAL STORE", "HOTEL", "", "BANK"]
	for i in names.size():
		var x := -60.0 + i * 16.0
		var col: Color = [Color(0.62, 0.5, 0.38), Color(0.55, 0.52, 0.48), Color(0.66, 0.46, 0.34)][i % 3]
		facade(s, Vector3(x, 0, -22), 11.0, 6.5 + (i % 3), col, PI, names[i])
		if i % 2 == 0:
			facade(s, Vector3(x + 6, 0, 24), 10.0, 6.0 + (i % 2) * 2.0, col * 0.9, 0.0, names[(i + 3) % names.size()])
	# church at the west end
	var cx := -95.0
	house(s, Vector3(cx, 0, 0), 12.0, 20.0, 6.0, "wood", Color(0.85, 0.82, 0.76), Color(0.35, 0.3, 0.28), PI * 0.5)
	s.box("wood", Vector3(cx + 11.0, 5.5, 0), Vector3(4.0, 11.0, 4.0), Color(0.85, 0.82, 0.76), true)
	s.mb.cyl("metal", Transform3D(Basis.IDENTITY, Vector3(cx + 11.0, 11.0, 0)), 3.0, 0.05, 5.0, 4, Color(0.35, 0.3, 0.28))
	s.mb.box("wood", Transform3D(Basis.IDENTITY, Vector3(cx + 11.0, 17.0, 0)), Vector3(0.2, 2.0, 0.2), Color(0.9, 0.9, 0.85))
	s.mb.box("wood", Transform3D(Basis.IDENTITY, Vector3(cx + 11.0, 17.4, 0)), Vector3(0.2, 0.2, 1.2), Color(0.9, 0.9, 0.85))
	# cemetery
	for i in 14:
		var p := Vector3(cx - 8 + (i % 5) * 3.0, 0, 18 + int(i / 5) * 3.0)
		s.mb.box("wood", Transform3D(Basis(Vector3.UP, (i % 3) * 0.1), p + Vector3(0, 0.6, 0)), Vector3(0.12, 1.2, 0.12), OLDWOOD)
		s.mb.box("wood", Transform3D(Basis(Vector3.UP, (i % 3) * 0.1), p + Vector3(0, 0.9, 0)), Vector3(0.12, 0.12, 0.7), OLDWOOD)
	water_tower(s, Vector3(40, 0, -45), 9.0, 3.0)
	s.label("GOLD CREEK", Vector3(40, 11.2, -41.9), 0.0, 1.6, Color(0.3, 0.2, 0.15), "rye")
	windmill(s, Vector3(55, 0, 40))
	wreck(s, "supply", Vector3(20, 0, 42), 1.9)
	s.light(Vector3(cx + 8, 4, 0), Color(1, 0.75, 0.45), 2.5, 30.0)
	s.finish("GoldCreek")

static func depot(root: Node3D, world: WorldData, time: String) -> void:
	var s := _site(root, world, "depot", 0.0, time)
	# garage / motor pool
	s.box("metal", Vector3(70, 5, -50), Vector3(30, 10, 18), Color(0.6, 0.62, 0.6))
	s.mb.box("plain", Transform3D(Basis.IDENTITY, Vector3(70, 3.5, -40.95)), Vector3(8, 7, 0.1), Color(0.12, 0.12, 0.12))
	s.mb.box("plain", Transform3D(Basis.IDENTITY, Vector3(58, 3.5, -40.95)), Vector3(6, 7, 0.1), Color(0.12, 0.12, 0.12))
	s.label("VALE FREIGHT LINES", Vector3(70, 11.5, -40.9), PI, 2.0, Color(1.0, 0.8, 0.25), "rye", true)
	# barracks
	for i in 3:
		house(s, Vector3(100, 0, -10 + i * 16), 8.0, 14.0, 3.5, "wood", Color(0.5, 0.55, 0.42), Color(0.3, 0.3, 0.3), PI * 0.5)
	# fence (posts + wire) around the compound, gap at the west gate
	var r := 128.0
	var pts: Array = []
	for k in 21:
		var a := -PI * 0.78 + k * (PI * 1.56 * 1.18) / 20.0
		pts.append(Vector3(cos(a) * r + 30, 0, sin(a) * r))
	fence_posts(s, pts, 4.0)
	for p in [Vector3(-40, 0, -60), Vector3(40, 0, 70), Vector3(90, 0, -80), Vector3(-10, 0, 60)]:
		floodlight(s, p, Vector3(20, 0, 0))
	wreck(s, "semi", Vector3(100, 0, -60), 0.0, 0.0, false, false)
	wreck(s, "semi", Vector3(40, 0, 75), 1.57, 0.0, false, false)
	for i in 8:
		barrel(s, Vector3(20 + (i % 4) * 0.7, 0, 60 + int(i / 4) * 0.7), Color(0.3, 0.33, 0.25))
	s.light(Vector3(70, 9, -38), Color(1, 0.85, 0.6), 3.0, 40.0)
	s.finish("ValeDepot")

static func mine(root: Node3D, world: WorldData, time: String) -> void:
	var s := _site(root, world, "mine", 0.0, time)
	# headframe
	var hc := Vector3(20, 0, -50)
	for sx in [-3.0, 3.0]:
		for sz in [-3.0, 3.0]:
			s.mb.cyl_between("wood", hc + Vector3(sx, 0, sz), hc + Vector3(sx * 0.4, 22, sz * 0.4), 0.3, 4, OLDWOOD)
	for y in [6.0, 12.0, 18.0]:
		s.mb.box("wood", Transform3D(Basis.IDENTITY, hc + Vector3(0, y, 0)), Vector3(6.0 - y * 0.2, 0.3, 6.0 - y * 0.2), OLDWOOD)
	s.mb.cyl_between("wood", hc + Vector3(0, 0, 14), hc + Vector3(0, 20, 1), 0.35, 4, OLDWOOD)
	s.mb.cyl("metal", Transform3D(Basis.from_euler(Vector3(0, 0, PI / 2)), hc + Vector3(0.5, 22.5, 0)), 2.2, 2.2, 0.3, 12, Color(0.25, 0.22, 0.2))
	s.solid(hc + Vector3(0, 4, 0), Vector3(7, 8, 7))
	# mill stepping down the slope
	for i in 3:
		house(s, Vector3(-30 + i * 4, 0, -60 + i * 9), 14.0, 9.0, 6.0 + i * 1.5, "metal", Color(0.55, 0.45, 0.38), Color(0.4, 0.3, 0.25), 0.2)
	# loading shed (Hollis is held here)
	house(s, Vector3(-40, 0, 5), 16.0, 12.0, 6.0, "wood", OLDWOOD, Color(0.45, 0.3, 0.2), PI * 0.5)
	s.label("SILVER QUEEN MINING CO.", Vector3(-31.8, 5.0, 5), PI * 0.5, 0.9, Color(0.9, 0.85, 0.75), "rye")
	# ore piles & tailings
	for p in [Vector3(40, 0, -10), Vector3(50, 0, 10), Vector3(-10, 0, -80)]:
		s.mb.cyl("rock", Transform3D(Basis.IDENTITY, p), 9.0, 0.5, 6.0, 9, Color(0.55, 0.45, 0.38))
		s.solid(p + Vector3(0, 2, 0), Vector3(10, 4, 10))
	# mine cart track
	for k in 20:
		s.mb.box("wood", Transform3D(Basis.IDENTITY, hc + Vector3(-2, 0.05, 8 + k * 1.2)), Vector3(1.6, 0.1, 0.2), OLDWOOD * 0.7)
	water_tower(s, Vector3(55, 0, -40), 8.0, 2.6)
	s.light(Vector3(-40, 7, 12), Color(1, 0.75, 0.45), 2.5, 30.0)
	s.finish("SilverQueen")

static func airstrip(root: Node3D, world: WorldData, time: String) -> void:
	var s := _site(root, world, "airstrip", 0.0, time)
	# runway east-west
	var L := 620.0
	var W := 36.0
	s.mb.quad("asphalt", Vector3(-L * 0.5, 0.1, -W * 0.5), Vector3(-L * 0.5, 0.1, W * 0.5), Vector3(L * 0.5, 0.1, W * 0.5), Vector3(L * 0.5, 0.1, -W * 0.5), Color(0.9, 0.9, 0.9), [Vector2(0, 0), Vector2(1, 0), Vector2(1, L / 20.0), Vector2(0, L / 20.0)])
	for k in 12:
		var x := -L * 0.5 + 30 + k * 50.0
		s.mb.quad("plain", Vector3(x, 0.13, -0.5), Vector3(x, 0.13, 0.5), Vector3(x + 18, 0.13, 0.5), Vector3(x + 18, 0.13, -0.5), Color(0.9, 0.9, 0.85))
	# hangar + tower
	quonset(s, Vector3(120, 0, 70), 34.0, 11.0, PI * 0.5, Color(0.65, 0.66, 0.6))
	s.label("INDIAN SPRINGS AUX. FIELD", Vector3(102.5, 9.0, 70), -PI * 0.5, 1.2, Color(0.9, 0.9, 0.85), "bebasneue")
	s.box("concrete", Vector3(60, 5, 70), Vector3(6, 10, 6), Color(0.8, 0.78, 0.72))
	s.box("glass", Vector3(60, 11.5, 70), Vector3(7, 3, 7), Color(0.2, 0.25, 0.28), false)
	s.mb.box("metal", Transform3D(Basis.IDENTITY, Vector3(60, 13.2, 70)), Vector3(7.6, 0.4, 7.6), Color(0.4, 0.4, 0.4))
	# windsock
	s.mb.cyl("metal", Transform3D(Basis.IDENTITY, Vector3(-80, 0, 40)), 0.08, 0.06, 7.0, 5, Color(0.8, 0.8, 0.8))
	s.mb.cyl("paint", Transform3D(Basis.from_euler(Vector3(0, 0, -PI / 2 + 0.2)), Vector3(-80, 6.8, 40)), 0.45, 0.2, 2.4, 8, Color(1, 0.45, 0.1))
	# Vale's getaway plane (twin-engine transport)
	var pl := Vector3(160, 0, 30)
	var rings: Array = []
	var cols: Array = []
	var prof := [[-8.0, 0.2], [-7.4, 0.9], [-5.5, 1.35], [0.0, 1.4], [4.0, 1.25], [8.0, 0.6], [10.0, 0.25]]
	for p in prof:
		rings.append(CarBuilder.ring(p[0], p[1], 2.6 - p[1], 2.6 + p[1], 2.0, 1.0, 12))
		cols.append(Color(0.82, 0.83, 0.85))
	var old := s.mb.xf
	s.mb.xf = old * Transform3D(Basis(Vector3.UP, PI * 0.5 + 0.3), pl)
	s.mb.loft("chrome", rings, cols)
	s.mb.box("paint", Transform3D(Basis.IDENTITY, Vector3(0, 2.0, -1.0)), Vector3(28.0, 0.35, 3.2), Color(0.8, 0.8, 0.82))
	s.mb.box("paint", Transform3D(Basis.IDENTITY, Vector3(0, 2.8, 8.8)), Vector3(9.0, 0.25, 1.8), Color(0.8, 0.8, 0.82))
	s.mb.box("paint", Transform3D(Basis.IDENTITY, Vector3(0, 4.5, 9.0)), Vector3(0.25, 3.5, 2.0), Color(0.6, 0.1, 0.12))
	for sx in [-5.5, 5.5]:
		s.mb.cyl("paint", Transform3D(Basis.from_euler(Vector3(PI / 2, 0, 0)), Vector3(sx, 2.0, -3.8)), 0.8, 0.7, 4.2, 10, Color(0.75, 0.75, 0.78))
		s.mb.cyl("plain", Transform3D(Basis.from_euler(Vector3(PI / 2, 0, 0)), Vector3(sx, 2.0, -4.1)), 1.9, 1.9, 0.05, 3, Color(0.1, 0.1, 0.1))
		s.mb.cyl("rubber", Transform3D(Basis.from_euler(Vector3(0, 0, PI / 2)), Vector3(sx + 0.3, 0.6, -2.5)), 0.6, 0.6, 0.4, 10, Color(0.08, 0.08, 0.08))
	s.mb.xf = old
	s.solid(pl + Vector3(0, 2.4, 0), Vector3(3.0, 3.0, 18.0), PI * 0.5 + 0.3)
	s.label("VALE AIR", pl + Vector3(0, 3.6, 0), 0.3, 0.9, Color(0.6, 0.1, 0.12), "rye")
	for k in 8:
		var x := -L * 0.5 + k * L / 7.0
		for z in [-W * 0.5 - 2, W * 0.5 + 2]:
			s.mb.box("lamp", Transform3D(Basis.IDENTITY, Vector3(x, 0.3, z)), Vector3(0.3, 0.4, 0.3), Color(1, 0.7, 0.2))
	s.light(Vector3(120, 10, 50), Color(1, 0.85, 0.6), 3.0, 40.0)
	s.finish("Airstrip")

static func frenchman(root: Node3D, world: WorldData, time: String) -> void:
	var s := Site.new()
	s.root = root
	s.night = time in ["night", "dusk", "dawn"]
	var c := Vector2(1700, 1150)
	s.xf = Transform3D(Basis.IDENTITY, Vector3(c.x, world.height(c.x, c.y), c.y))
	# "Doom Town" test houses
	for i in 5:
		var p := Vector3(-60 + i * 30, 0, -20 + (i % 2) * 25)
		house(s, p, 8.0, 7.0, 3.2, "wood", [Color(0.85, 0.82, 0.7), Color(0.7, 0.8, 0.85), Color(0.9, 0.75, 0.7)][i % 3], Color(0.4, 0.35, 0.3), i * 0.4)
	# bunkers
	for p in [Vector3(80, 0, -60), Vector3(-90, 0, 60), Vector3(150, 0, 40)]:
		s.box("concrete", p + Vector3(0, 1.2, 0), Vector3(10, 2.4, 7), Color(0.75, 0.73, 0.68))
		s.mb.box("plain", Transform3D(Basis.IDENTITY, p + Vector3(0, 1.4, -3.55)), Vector3(4, 0.3, 0.1), Color(0.05, 0.05, 0.05))
	# instrument masts
	for k in 10:
		var p := Vector3(-150 + k * 35, 0, 90)
		s.mb.cyl("metal", Transform3D(Basis.IDENTITY, p), 0.1, 0.08, 10.0, 4, Color(0.6, 0.6, 0.6))
	# steel test tower
	lattice(s, Vector3(210, 0, -10), 32.0, 6.0, 2.0, Color(0.55, 0.55, 0.55), 8)
	s.box("metal", Vector3(210, 33.5, -10), Vector3(4, 3, 4), Color(0.7, 0.7, 0.68), false)
	var sg := Scenery.small_sign("DANGER - AEC TEST AREA", Color(0.95, 0.85, 0.1), Color(0.1, 0.1, 0.1))
	root.add_child(sg)
	sg.global_position = s.xf * Vector3(-160, 0, -40)
	sg.rotation.y = -0.6
	s.finish("FrenchmanFlat")

static func vegas_glow(root: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(9000, 2600)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = Lib.tex.flare
	m.albedo_color = Color(1.0, 0.55, 0.3, 0.55)
	m.disable_fog = true
	mi.material_override = m
	root.add_child(mi)
	mi.position = Vector3(12000, 200, 12000)
	mi.look_at(Vector3(0, 200, 0), Vector3.UP)
	mi.rotate_object_local(Vector3.UP, PI)
	mi.extra_cull_margin = 30000.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
