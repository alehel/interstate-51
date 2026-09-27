class_name CarBuilder
## Procedural low-poly 1950s vehicles. Bodies are lofted cross-sections
## (superellipse rings) so fenders, hoods and trunks get that rounded
## post-war silhouette; wheel arches come from raising the underside around
## each axle. Car faces -Z, origin at ground level under the centre.

static var _cache: Dictionary = {}

const DARK := Color(0.07, 0.065, 0.06)
const GLASS := Color(0.16, 0.2, 0.24)
const CHROME := Color(0.85, 0.86, 0.88)
const RUBBER := Color(0.08, 0.08, 0.085)

static func build(key: String, opts: Dictionary = {}) -> Dictionary:
	var ck := key + str(opts)
	if _cache.has(ck):
		return _cache[ck]
	var d: Dictionary = Defs.CARS[key].duplicate()
	for k in opts:
		d[k] = opts[k]
	var r := _build(d)
	_cache[ck] = r
	return r

static func ring(z: float, hw: float, yb: float, yt: float, n: float = 3.2, taper: float = 0.86, pts: int = 16) -> PackedVector3Array:
	var out := PackedVector3Array()
	var mid := (yb + yt) * 0.5
	var hh := (yt - yb) * 0.5
	for k in pts:
		var th := TAU * k / pts
		var sx := sin(th)
		var cy := cos(th)
		var x := hw * signf(sx) * pow(absf(sx), 2.0 / n)
		var y := mid + hh * signf(cy) * pow(absf(cy), 2.0 / n)
		var t := clampf((y - yb) / maxf(yt - yb, 0.01), 0, 1)
		x *= lerpf(1.0, taper, t * t)
		out.append(Vector3(x, y, z))
	return out

## Colours for a body ring: underside dark, rest paint (optionally two-tone above `split`).
static func body_cols(r: PackedVector3Array, paint: Color, upper: Color, split: float, yb: float) -> PackedColorArray:
	var out := PackedColorArray()
	for p in r:
		var c := paint
		if p.y > split:
			c = upper
		if p.y < yb + 0.04:
			c = DARK
		out.append(c)
	return out

static func cabin_cols(r: PackedVector3Array, roof: Color, glass_all: bool, roof_y: float) -> PackedColorArray:
	var out := PackedColorArray()
	for p in r:
		out.append(GLASS if glass_all or p.y < roof_y else roof)
	return out

## Generic lofted body from station list [z, hw, yb, yt] (fractions: z of L, hw of W; y in m).
static func loft_body(mb: MeshBuilder, mat: String, L: float, W: float, st: Array, paint: Color, upper: Color, split: float, n: float = 3.2, taper: float = 0.86) -> void:
	var rings := []
	var cols := []
	for s in st:
		var rr := ring(s[0] * L, s[1] * W, s[2], s[3], n, taper)
		rings.append(rr)
		var pc: Color = paint if s.size() < 5 else s[4]
		var uc: Color = upper if s.size() < 5 else s[4]
		cols.append(body_cols(rr, pc, uc, split, s[2]))
	mb.loft(mat, rings, cols)

static func loft_cabin(mb: MeshBuilder, L: float, W: float, st: Array, roof: Color, n: float = 2.6, taper: float = 0.8) -> void:
	# st entries: [z, hw, yb, yt, glass_all(bool)]
	var rings := []
	var cols := []
	for s in st:
		var rr := ring(s[0] * L, s[1] * W, s[2], s[3], n, taper)
		rings.append(rr)
		cols.append(cabin_cols(rr, roof, s[4], s[3] - (s[3] - s[2]) * 0.22))
	mb.loft("paint", rings, cols)

static func _wheel_mesh(radius: float, width: float, whitewall: bool, hub: String) -> ArrayMesh:
	var key := "wheel_%.2f_%.2f_%s_%s" % [radius, width, whitewall, hub]
	if _cache.has(key):
		return _cache[key]
	var mb := MeshBuilder.new()
	var rot := Basis.from_euler(Vector3(0, 0, -PI / 2))
	mb.cyl("rubber", Transform3D(rot, Vector3(-width / 2, 0, 0)), radius, radius, width, 14, RUBBER, true)
	var face := Transform3D(rot, Vector3(width / 2, 0, 0))
	if whitewall:
		mb.cyl("paint", face, radius * 0.78, radius * 0.7, 0.012, 14, Color(0.92, 0.9, 0.85), true)
	match hub:
		"chrome":
			mb.cyl("chrome", face.translated_local(Vector3(0, 0.013, 0)), radius * 0.5, radius * 0.18, 0.06, 12, CHROME, true)
		"steel":
			mb.cyl("paint", face, radius * 0.62, radius * 0.5, 0.03, 10, Color(0.55, 0.12, 0.1), true)
			mb.cyl("chrome", face.translated_local(Vector3(0, 0.03, 0)), radius * 0.2, radius * 0.12, 0.04, 8, CHROME, true)
		_:
			mb.cyl("paint", face, radius * 0.55, radius * 0.45, 0.03, 10, Color(0.25, 0.27, 0.22), true)
	var m := mb.commit()
	_cache[key] = m
	return m

static func _headlight(mb: MeshBuilder, p: Vector3, r: float, facing: float = 1.0) -> void:
	# cylinder pointing along -Z (front) or +Z (rear)
	var b := Basis.from_euler(Vector3(-PI / 2 * facing, 0, 0))
	mb.cyl("chrome", Transform3D(b, p), r * 1.15, r * 1.1, 0.06, 10, CHROME, false)
	mb.cyl("lamp", Transform3D(b, p + Vector3(0, 0, -0.05 * facing)), r, r * 0.9, 0.02, 10, Color(1.0, 0.95, 0.75), true)

static func _bumper(mb: MeshBuilder, z: float, y: float, w: float, depth: float = 0.16, h: float = 0.14) -> void:
	var rot := Basis.from_euler(Vector3(0, 0, -PI / 2))
	mb.cyl("chrome", Transform3D(rot, Vector3(-w / 2, y, z)), h * 0.6, h * 0.6, w, 8, CHROME, true)
	mb.boxp("chrome", Vector3(0, y + 0.01, z), Vector3(w * 0.96, h, depth * 0.6), CHROME, 0.25)

static func _gun(mb: MeshBuilder, p: Vector3, big: bool) -> void:
	var len := 1.2 if big else 0.95
	var r := 0.045 if big else 0.032
	mb.boxp("paint", p + Vector3(0, 0.02, 0.18), Vector3(0.16, 0.14, 0.42), Color(0.12, 0.12, 0.12))
	var b := Basis.from_euler(Vector3(-PI / 2, 0, 0))
	mb.cyl("chrome", Transform3D(b, p + Vector3(0, 0.03, 0)), r, r, len, 6, Color(0.25, 0.25, 0.27), true)
	mb.cyl("paint", Transform3D(b, p + Vector3(0, 0.03, -len + 0.15)), r * 1.8, r * 1.5, 0.15, 6, Color(0.1, 0.1, 0.1), true)

static func _build(d: Dictionary) -> Dictionary:
	var mb := MeshBuilder.new()
	var L: float = d.len
	var W: float = d.wid
	var paint: Color = d.paint
	var paint2: Color = d.paint2
	var stripe: Color = d.stripe
	var style: String = d["style"]
	var mat := "rusty" if d.get("rusty", false) else "paint"
	var wr := 0.36
	var ww := 0.24
	var fz := -L * 0.33
	var rz := L * 0.30
	var track := W * 0.41
	var whitewall := true
	var hub := "chrome"
	var gun_mounts: Array = []
	var special_mount := Vector3(0, 1.5, 0.3)
	var rear_mount := Vector3(0, 0.6, L * 0.5 + 0.3)
	var turret_mount := Vector3.ZERO
	var has_turret := d.has("turret")
	var head := [Vector3(-W * 0.36, 0.78, -L * 0.49), Vector3(W * 0.36, 0.78, -L * 0.49)]
	var tail := [Vector3(-W * 0.4, 0.8, L * 0.5), Vector3(W * 0.4, 0.8, L * 0.5)]
	var top := 1.45
	var extra_wheels: Array = []

	match style:
		"coupe", "sedan", "police", "caddy", "wagon", "hearse":
			var long_cab := style in ["wagon", "hearse"]
			var sedan := style in ["sedan", "police"]
			var fins := style == "caddy"
			var two_tone_split := 0.9 if style in ["sedan", "caddy"] else 9.0
			var a := wr / L
			var st := [
				[-0.5, 0.38, 0.42, 0.72],
				[-0.48, 0.45, 0.33, 0.86],
				[fz / L - a * 1.3, 0.5, 0.3, 0.95],
				[fz / L - a * 0.7, 0.5, 0.58, 0.98],
				[fz / L, 0.5, 0.7, 1.0],
				[fz / L + a * 0.7, 0.5, 0.58, 1.0],
				[fz / L + a * 1.3, 0.5, 0.3, 1.0],
				[0.0, 0.5, 0.28, 1.0],
				[rz / L - a * 1.3, 0.5, 0.3, 0.99],
				[rz / L - a * 0.6, 0.5, 0.52 if style != "coupe" else 0.44, 0.98],
				[rz / L, 0.5, 0.6 if style != "coupe" else 0.48, 0.97],
				[rz / L + a * 0.7, 0.5, 0.5, 0.95],
				[rz / L + a * 1.4, 0.48, 0.36, 0.92 if not fins else 1.0],
				[0.5, 0.42, 0.42, 0.8 if not fins else 0.95],
			]
			if style == "police":
				# white doors
				for i in range(6, 9):
					st[i] = st[i].duplicate()
					st[i].append(paint2)
			loft_body(mb, mat, L, W, st, paint, paint2, two_tone_split)
			# cabin / greenhouse
			var roof := paint2 if style in ["sedan", "caddy", "police"] else paint
			if style == "coupe":
				roof = paint
			var cab_top := 1.38 if style == "coupe" else (1.5 if sedan or long_cab else 1.42)
			top = cab_top
			var cs: Array
			if long_cab:
				cs = [
					[-0.16, 0.42, 0.97, 1.0, true],
					[-0.06, 0.43, 0.97, cab_top, true],
					[-0.06, 0.43, 0.97, cab_top, false],
					[0.46, 0.43, 0.97, cab_top, false],
					[0.46, 0.43, 0.97, cab_top, true],
					[0.49, 0.42, 0.95, 1.0, true],
				]
			else:
				var back := 0.3 if style == "coupe" else 0.28
				cs = [
					[-0.14, 0.41, 0.97, 1.0, true],
					[-0.04, 0.42, 0.97, cab_top, true],
					[-0.04, 0.42, 0.97, cab_top, false],
					[0.14 if style == "coupe" else 0.2, 0.42, 0.97, cab_top, false],
					[0.14 if style == "coupe" else 0.2, 0.42, 0.97, cab_top, true],
					[back + 0.06, 0.4, 0.95, 1.0, true],
				]
			loft_cabin(mb, L, W, cs, roof)
			if style == "wagon":
				# woody side panels
				for sx in [-1.0, 1.0]:
					mb.boxp("wood", Vector3(sx * W * 0.505, 0.72, L * 0.18), Vector3(0.02, 0.36, L * 0.52), Color(0.72, 0.5, 0.3), 0.8)
			if style == "hearse":
				for sx in [-1.0, 1.0]:
					# landau bars and curtained windows
					mb.boxp("paint", Vector3(sx * W * 0.43, 1.25, L * 0.3), Vector3(0.02, 0.35, L * 0.28), Color(0.3, 0.1, 0.35))
					mb.boxp("chrome", Vector3(sx * W * 0.435, 1.2, L * 0.38), Vector3(0.03, 0.05, 0.6), CHROME)
				mb.boxp("chrome", Vector3(0, 0.93, L * 0.505), Vector3(W * 0.5, 0.05, 0.03), CHROME)
			if fins:
				for sx in [-1.0, 1.0]:
					var bx: float = sx * W * 0.46
					var fa := Vector3(bx, 0.95, L * 0.26)
					var fb := Vector3(bx, 0.95, L * 0.5)
					var fc := Vector3(bx, 1.22, L * 0.5)
					var fd := Vector3(bx, 0.98, L * 0.3)
					mb.quad("paint", fa, fb, fc, fd, paint)
					mb.quad("paint", fa, fd, fc, fb, paint)
					mb.boxp("lamp", Vector3(bx, 1.1, L * 0.5), Vector3(0.08, 0.2, 0.04), Color(1, 0.1, 0.05))
				# hood ornament
				mb.cyl("chrome", Transform3D(Basis.from_euler(Vector3(-1.2, 0, 0)), Vector3(0, 0.98, -L * 0.45)), 0.05, 0.0, 0.3, 4, CHROME)
				# side chrome spear
				for sx in [-1.0, 1.0]:
					mb.boxp("chrome", Vector3(sx * W * 0.502, 0.72, 0.0), Vector3(0.02, 0.04, L * 0.8), CHROME)
			if style == "police":
				mb.cyl("lamp", Transform3D(Basis.IDENTITY, Vector3(0, cab_top - 0.02, L * 0.02)), 0.14, 0.1, 0.18, 8, Color(1.0, 0.1, 0.05))
				mb.cyl("chrome", Transform3D(Basis.IDENTITY, Vector3(0, cab_top + 0.16, L * 0.02)), 0.05, 0.0, 0.05, 6, CHROME)
				mb.boxp("paint", Vector3(0, cab_top - 0.02, -L * 0.08), Vector3(0.5, 0.08, 0.1), Color(0.9, 0.75, 0.2))
			# grille & bumpers
			mb.boxp("chrome", Vector3(0, 0.6, -L * 0.502), Vector3(W * 0.56, 0.22, 0.04), CHROME)
			for gx in 7:
				mb.boxp("plain", Vector3((gx - 3) * W * 0.075, 0.6, -L * 0.506), Vector3(0.03, 0.18, 0.02), DARK)
			_bumper(mb, -L * 0.515, 0.42, W * 0.95)
			_bumper(mb, L * 0.515, 0.44, W * 0.9)
			for h in head:
				_headlight(mb, h, 0.12)
			for t in tail:
				mb.boxp("lamp", t, Vector3(0.14, 0.1, 0.05), Color(1, 0.08, 0.04))
			# stripe down the hood
			if style == "coupe":
				for sx in [-1.0, 1.0]:
					mb.boxp("paint", Vector3(sx * W * 0.503, 0.86, -L * 0.05), Vector3(0.01, 0.03, L * 0.82), stripe)
					mb.boxp("paint", Vector3(sx * 0.09, 1.005, -L * 0.3), Vector3(0.05, 0.01, L * 0.38), stripe)
			gun_mounts = [Vector3(-W * 0.3, 1.02, -L * 0.28), Vector3(W * 0.3, 1.02, -L * 0.28)]
			special_mount = Vector3(0, cab_top + 0.02, L * 0.06)
			turret_mount = Vector3(0, cab_top, L * 0.1)
			if style == "hearse":
				wr = 0.38
			if style == "caddy":
				hub = "chrome"
		"roadster":
			# chopped highboy hot rod: narrow body, exposed front wheels, engine up front
			var body_w := 0.36
			var st := [
				[-0.5, 0.2, 0.45, 0.8],
				[-0.3, 0.22, 0.42, 0.85],
				[-0.12, body_w, 0.4, 0.95],
				[0.1, body_w + 0.02, 0.4, 0.95],
				[0.28, body_w + 0.02, 0.45, 0.93],
				[0.42, body_w, 0.5, 0.88],
				[0.5, body_w - 0.05, 0.55, 0.75],
			]
			loft_body(mb, mat, L, W, st, paint, paint, 9.0, 3.5, 0.9)
			# engine block + chrome headers + blower
			mb.boxp("paint", Vector3(0, 0.95, -L * 0.3), Vector3(0.55, 0.45, 0.8), Color(0.25, 0.25, 0.27))
			mb.boxp("chrome", Vector3(0, 1.25, -L * 0.3), Vector3(0.35, 0.2, 0.45), CHROME)
			for sx in [-1.0, 1.0]:
				for k in 4:
					mb.cyl_between("chrome", Vector3(sx * 0.28, 0.9, -L * 0.42 + k * 0.18), Vector3(sx * 0.5, 0.55, -L * 0.35 + k * 0.15), 0.04, 5, CHROME)
			# radiator shell
			mb.boxp("chrome", Vector3(0, 0.95, -L * 0.49), Vector3(0.5, 0.55, 0.1), CHROME)
			mb.boxp("plain", Vector3(0, 0.95, -L * 0.5), Vector3(0.4, 0.45, 0.04), DARK)
			# windshield frame
			mb.boxp("chrome", Vector3(0, 1.2, -L * 0.08), Vector3(W * 0.66, 0.04, 0.04), CHROME)
			mb.boxp("glass", Vector3(0, 1.08, -L * 0.08), Vector3(W * 0.62, 0.22, 0.02), GLASS)
			# driver
			mb.boxp("plain", Vector3(-0.25, 1.1, L * 0.05), Vector3(0.4, 0.4, 0.3), Color(0.2, 0.17, 0.15))
			mb.cyl("paint", Transform3D(Basis.IDENTITY, Vector3(-0.25, 1.3, L * 0.05)), 0.12, 0.11, 0.24, 8, Color(0.75, 0.55, 0.42))
			mb.cyl("paint", Transform3D(Basis.IDENTITY, Vector3(-0.25, 1.5, L * 0.05)), 0.14, 0.02, 0.1, 8, Color(0.1, 0.1, 0.1))
			# front axle beam, exposed
			mb.boxp("chrome", Vector3(0, wr, fz), Vector3(W * 0.8, 0.08, 0.08), CHROME)
			mb.boxp("plain", Vector3(0, wr + 0.1, fz), Vector3(0.08, 0.2, 0.1), DARK)
			# flames on the flanks
			for sx in [-1.0, 1.0]:
				mb.boxp("paint", Vector3(sx * W * body_w * 1.01, 0.75, -L * 0.1), Vector3(0.02, 0.12, L * 0.4), stripe)
			head = [Vector3(-0.35, 0.95, -L * 0.45), Vector3(0.35, 0.95, -L * 0.45)]
			for h in head:
				_headlight(mb, h, 0.1)
			tail = [Vector3(-0.3, 0.7, L * 0.5), Vector3(0.3, 0.7, L * 0.5)]
			for t in tail:
				mb.boxp("lamp", t, Vector3(0.1, 0.1, 0.05), Color(1, 0.08, 0.04))
			track = W * 0.46
			hub = "steel"
			whitewall = false
			gun_mounts = [Vector3(0.3, 1.0, -L * 0.1)]
			top = 1.5
		"pickup", "stakebed", "semi", "jeep", "armored":
			var truck := style in ["stakebed", "semi"]
			var cab_z0: float
			var cab_z1: float
			var hood_h := 1.1
			match style:
				"pickup":
					cab_z0 = -0.12
					cab_z1 = 0.1
					hood_h = 1.05
				"stakebed":
					cab_z0 = -0.1
					cab_z1 = 0.08
					hood_h = 1.35
					wr = 0.48
					ww = 0.3
				"semi":
					cab_z0 = -0.22
					cab_z1 = -0.08
					hood_h = 1.6
					wr = 0.55
					ww = 0.32
				"jeep":
					cab_z0 = -0.05
					cab_z1 = 0.35
					hood_h = 0.95
					wr = 0.38
				"armored":
					cab_z0 = -0.38
					cab_z1 = -0.16
					hood_h = 1.5
					wr = 0.55
					ww = 0.34
			fz = -L * (0.33 if style != "semi" else 0.38)
			rz = L * (0.3 if style != "semi" else 0.36)
			if style == "armored":
				fz = -L * 0.3
				rz = L * 0.3
			var a := wr / L
			# hood + front fenders
			var front := [
				[-0.5, 0.36, 0.45, hood_h - 0.25],
				[-0.48, 0.42, wr * 0.9, hood_h - 0.08],
				[fz / L - a * 1.2, 0.46, wr * 0.9, hood_h - 0.02],
				[fz / L, 0.46, wr * 1.75, hood_h],
				[fz / L + a * 1.2, 0.46, wr * 0.9, hood_h],
				[cab_z0, 0.44, wr * 0.9, hood_h],
			]
			if style == "jeep":
				front = [[-0.5, 0.42, 0.42, hood_h - 0.1], [cab_z0, 0.46, 0.42, hood_h]]
			if style == "armored":
				front = [[-0.5, 0.44, 0.5, hood_h - 0.3], [-0.46, 0.48, 0.5, hood_h], [cab_z0, 0.48, 0.5, hood_h]]
			loft_body(mb, mat, L, W, front, paint, paint, 9.0, 4.5 if style in ["jeep", "armored"] else 3.0, 0.9)
			# cab box
			var cab_top := hood_h + (0.85 if style != "jeep" else 0.0)
			top = cab_top
			if style != "jeep":
				var cz := (cab_z0 + cab_z1) * 0.5 * L
				var cl := (cab_z1 - cab_z0) * L
				mb.boxp(mat, Vector3(0, (wr * 0.9 + hood_h) * 0.5, cz), Vector3(W * 0.9, hood_h - wr * 0.9, cl), paint)
				var cs := [
					[cab_z0 - 0.005, 0.43, hood_h - 0.02, hood_h + 0.02, true],
					[cab_z0 + 0.02, 0.44, hood_h - 0.02, cab_top, true],
					[cab_z0 + 0.02, 0.44, hood_h - 0.02, cab_top, false],
					[cab_z1 - 0.01, 0.44, hood_h - 0.02, cab_top, false],
					[cab_z1, 0.43, hood_h - 0.02, hood_h + 0.1, false],
				]
				loft_cabin(mb, L, W, cs, paint2 if style == "semi" else paint, 5.0, 0.95)
			else:
				# jeep: windshield frame and roll bar
				mb.boxp("glass", Vector3(0, hood_h + 0.3, cab_z0 * L), Vector3(W * 0.85, 0.5, 0.03), GLASS)
				mb.boxp("paint", Vector3(0, hood_h + 0.56, cab_z0 * L), Vector3(W * 0.88, 0.05, 0.05), paint)
				mb.boxp(mat, Vector3(0, 0.75, L * 0.15), Vector3(W * 0.92, 0.55, L * 0.66), paint)
				mb.cyl("rubber", Transform3D(Basis.from_euler(Vector3(PI / 2, 0, 0)), Vector3(0, 0.85, L * 0.5)), 0.33, 0.33, 0.2, 10, RUBBER)
				# gunner
				mb.boxp("plain", Vector3(0, 1.25, L * 0.18), Vector3(0.4, 0.45, 0.3), Color(0.3, 0.3, 0.22))
				mb.cyl("paint", Transform3D(Basis.IDENTITY, Vector3(0, 1.48, L * 0.18)), 0.12, 0.11, 0.22, 8, Color(0.75, 0.55, 0.42))
			# grille
			if style != "jeep":
				mb.boxp("chrome", Vector3(0, hood_h * 0.62, -L * 0.502), Vector3(W * 0.5, hood_h * 0.5, 0.04), CHROME if style != "armored" else paint * 0.7)
				for gx in 6:
					mb.boxp("plain", Vector3((gx - 2.5) * W * 0.07, hood_h * 0.62, -L * 0.506), Vector3(0.03, hood_h * 0.42, 0.02), DARK)
			else:
				for gx in 7:
					mb.boxp("plain", Vector3((gx - 3) * W * 0.06, 0.7, -L * 0.502), Vector3(0.04, 0.3, 0.02), DARK)
			_bumper(mb, -L * 0.515, wr * 1.1, W * 0.95, 0.2, 0.18)
			head = [Vector3(-W * 0.34, hood_h * 0.72, -L * 0.49), Vector3(W * 0.34, hood_h * 0.72, -L * 0.49)]
			for h in head:
				_headlight(mb, h, 0.13)
			# rear section
			match style:
				"pickup":
					var bz0 := cab_z1 * L
					var bl := L * 0.5 - bz0
					mb.boxp(mat, Vector3(0, 0.62, bz0 + bl * 0.5), Vector3(W * 0.92, 0.12, bl), paint)
					for sx in [-1.0, 1.0]:
						mb.boxp(mat, Vector3(sx * W * 0.44, 0.9, bz0 + bl * 0.5), Vector3(0.08, 0.5, bl), paint)
						# rear fenders
						mb.cyl(mat, Transform3D(Basis.from_euler(Vector3(0, 0, -PI / 2)), Vector3(sx * W * 0.44 - (0.2 if sx > 0 else -0.0), wr, rz)), wr * 1.35, wr * 1.35, 0.2, 10, paint, true)
					mb.boxp(mat, Vector3(0, 0.9, L * 0.49), Vector3(W * 0.92, 0.5, 0.08), paint)
					turret_mount = Vector3(0, 1.0, L * 0.28)
				"stakebed":
					var bz0 := cab_z1 * L + 0.1
					var bl := L * 0.5 - bz0
					mb.boxp("wood", Vector3(0, wr * 2.0 + 0.1, bz0 + bl * 0.5), Vector3(W * 0.98, 0.15, bl), Color(0.6, 0.45, 0.3), 0.5)
					for sx in [-1.0, 1.0]:
						for k in 6:
							mb.boxp("wood", Vector3(sx * W * 0.48, wr * 2.0 + 0.6, bz0 + 0.15 + k * (bl - 0.3) / 5.0), Vector3(0.08, 0.9, 0.1), Color(0.55, 0.42, 0.3), 0.5)
						mb.boxp("wood", Vector3(sx * W * 0.48, wr * 2.0 + 0.95, bz0 + bl * 0.5), Vector3(0.06, 0.12, bl), Color(0.55, 0.42, 0.3), 0.5)
					# tarped cargo and barrels
					mb.boxp("plain", Vector3(0, wr * 2.0 + 0.7, bz0 + bl * 0.45), Vector3(W * 0.85, 1.0, bl * 0.8), Color(0.45, 0.43, 0.3))
					for k in 3:
						mb.cyl("paint", Transform3D(Basis.IDENTITY, Vector3(-0.6 + k * 0.6, wr * 2.0 + 0.2, L * 0.46)), 0.28, 0.28, 0.85, 8, Color(0.3, 0.33, 0.2))
					extra_wheels.append(Vector3(track, wr, rz - wr * 2.2))
					extra_wheels.append(Vector3(-track, wr, rz - wr * 2.2))
				"semi":
					# sleeper + trailer
					var tz0 := cab_z1 * L + 0.4
					var tl := L * 0.5 - tz0
					mb.boxp(mat, Vector3(0, wr * 2.0 + 0.05, tz0 + tl * 0.5 - 0.5), Vector3(W * 0.5, 0.2, tl), DARK)
					mb.boxp("metal", Vector3(0, wr * 2.0 + 1.55, tz0 + tl * 0.5), Vector3(W, 2.6, tl), Color(0.85, 0.85, 0.85), 0.3)
					mb.boxp("paint", Vector3(0, wr * 2.0 + 1.6, tz0 + tl * 0.5), Vector3(W * 1.005, 0.5, tl * 0.9), paint)
					for sx in [-1.0, 1.0]:
						mb.cyl("chrome", Transform3D(Basis.IDENTITY, Vector3(sx * W * 0.52, 1.0, cab_z1 * L - 0.1)), 0.08, 0.08, cab_top + 0.6, 6, CHROME)
					extra_wheels.append(Vector3(track, wr, rz - wr * 2.2))
					extra_wheels.append(Vector3(-track, wr, rz - wr * 2.2))
					extra_wheels.append(Vector3(track, wr, -L * 0.05))
					extra_wheels.append(Vector3(-track, wr, -L * 0.05))
				"armored":
					var bz0 := cab_z1 * L
					var bl := L * 0.5 - bz0
					mb.boxp("metal", Vector3(0, 1.75, bz0 + bl * 0.5), Vector3(W, 2.5, bl), paint, 0.3)
					for k in 5:
						mb.boxp("paint", Vector3(0, 1.75, bz0 + 0.3 + k * (bl - 0.6) / 4.0), Vector3(W * 1.01, 2.4, 0.08), paint2)
					for sx in [-1.0, 1.0]:
						mb.boxp("plain", Vector3(sx * W * 0.505, 2.3, bz0 + bl * 0.5), Vector3(0.02, 0.12, bl * 0.8), DARK)
					mb.boxp("paint", Vector3(0, 2.1, L * 0.505), Vector3(W * 0.7, 1.4, 0.05), paint2)
					mb.boxp("chrome", Vector3(0, 2.1, L * 0.51), Vector3(0.2, 0.2, 0.05), Color(0.9, 0.8, 0.3))
					turret_mount = Vector3(0, 3.0, L * 0.12)
					extra_wheels.append(Vector3(track, wr, rz - wr * 2.2))
					extra_wheels.append(Vector3(-track, wr, rz - wr * 2.2))
					top = 3.0
				"jeep":
					turret_mount = Vector3(0, 1.2, L * 0.05)
			tail = [Vector3(-W * 0.44, 0.9, L * 0.5), Vector3(W * 0.44, 0.9, L * 0.5)]
			for t in tail:
				mb.boxp("lamp", t, Vector3(0.12, 0.12, 0.05), Color(1, 0.08, 0.04))
			whitewall = false
			hub = "plain"
			track = W * 0.42
			gun_mounts = [Vector3(-W * 0.3, hood_h + 0.04, -L * 0.3), Vector3(W * 0.3, hood_h + 0.04, -L * 0.3)]
			special_mount = Vector3(0, cab_top + 0.05, (cab_z0 + cab_z1) * 0.5 * L)

	# hood-mounted guns
	var guns: int = d.get("guns", 0)
	var big := false
	var w_list: Array = d.get("weapons", [])
	if not w_list.is_empty() and w_list[0] == "mg50":
		big = true
	var gm := []
	for i in mini(guns, gun_mounts.size()):
		_gun(mb, gun_mounts[i], big)
		gm.append(gun_mounts[i] + Vector3(0, 0.03, -1.0))
	if guns == 1 and gun_mounts.size() == 1:
		pass
	var body := mb.commit()
	var wheels := [
		Vector3(-track, wr, fz), Vector3(track, wr, fz),
		Vector3(-track, wr, rz), Vector3(track, wr, rz),
	]
	var wheel_mesh := _wheel_mesh(wr, ww * (1.25 if style == "roadster" else 1.0), whitewall, hub)
	return {
		"body": body, "wheel": wheel_mesh, "wheels": wheels, "extra_wheels": extra_wheels,
		"wheel_radius": wr, "gun_muzzles": gm, "special": special_mount, "rear": rear_mount,
		"turret": turret_mount, "has_turret": has_turret, "head": head, "tail": tail,
		"size": Vector3(W, top, L), "top": top,
	}

## Small rotating gun turret mesh (pedestal + twin barrels), faces -Z.
static func turret_mesh(big: bool) -> ArrayMesh:
	var key := "turret_%s" % big
	if _cache.has(key):
		return _cache[key]
	var mb := MeshBuilder.new()
	mb.cyl("paint", Transform3D.IDENTITY, 0.35, 0.3, 0.3, 10, Color(0.2, 0.21, 0.2))
	mb.boxp("paint", Vector3(0, 0.45, 0.05), Vector3(0.55, 0.3, 0.6), Color(0.25, 0.26, 0.24))
	for sx in [-0.12, 0.12]:
		var b := Basis.from_euler(Vector3(-PI / 2, 0, 0))
		mb.cyl("chrome", Transform3D(b, Vector3(sx, 0.47, -0.2)), 0.04 if big else 0.03, 0.04 if big else 0.03, 1.1, 6, Color(0.2, 0.2, 0.22))
	# shield
	mb.boxp("metal", Vector3(0, 0.6, -0.28), Vector3(0.7, 0.45, 0.04), Color(0.5, 0.5, 0.45), 0.5)
	var m := mb.commit()
	_cache[key] = m
	return m

## Roof rocket pod.
static func rocket_pod_mesh() -> ArrayMesh:
	if _cache.has("rocketpod"):
		return _cache["rocketpod"]
	var mb := MeshBuilder.new()
	mb.boxp("paint", Vector3(0, 0.12, 0), Vector3(0.7, 0.26, 0.9), Color(0.32, 0.36, 0.28))
	for ix in 3:
		for iy in 2:
			var b := Basis.from_euler(Vector3(-PI / 2, 0, 0))
			mb.cyl("plain", Transform3D(b, Vector3(-0.2 + ix * 0.2, 0.06 + iy * 0.13, -0.46)), 0.05, 0.05, 0.02, 6, DARK, true)
	var m := mb.commit()
	_cache["rocketpod"] = m
	return m
