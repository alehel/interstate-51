class_name Gauges
extends Control
## Immediate-mode HUD instruments: radar, armour diagram, 1950s speedometer,
## weapon list, target lock brackets, objective beacons and escort bars.

var hud: Hud
var _font: Font
var _font2: Font

const RADAR_RANGE := 320.0

func _ready() -> void:
	_font = Lib.font("bebasneue")
	_font2 = Lib.font("specialelite")

func _draw() -> void:
	var lvl: Level = hud.level
	if not lvl or not lvl.player or not is_instance_valid(lvl.player):
		return
	var p: Car = lvl.player
	var sz := size
	_draw_radar(lvl, p, Vector2(sz.x - 130, 130), 105.0)
	_draw_armor(p, Vector2(110, sz.y - 120))
	_draw_speedo(p, Vector2(sz.x - 120, sz.y - 115), 92.0)
	_draw_weapons(p, Vector2(sz.x - 470, sz.y - 150))
	_draw_target(lvl, p)
	_draw_beacons(lvl)
	_draw_tracked(Vector2(sz.x * 0.5 - 150, 136))
	_draw_crosshair(lvl, p)

func _txt(pos: Vector2, s: String, size_: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, f: Font = null) -> void:
	var fnt := f if f else _font
	draw_string_outline(fnt, pos, s, align, width, size_, 5, Color(0, 0, 0, 0.8 * col.a))
	draw_string(fnt, pos, s, align, width, size_, col)

static func health_color(f: float) -> Color:
	if f <= 0.001:
		return Color(0.15, 0.12, 0.1)
	if f > 0.5:
		return Color(1.0, 0.85, 0.2).lerp(Color(0.35, 0.85, 0.3), (f - 0.5) * 2.0)
	return Color(0.9, 0.15, 0.08).lerp(Color(1.0, 0.85, 0.2), f * 2.0)

# ------------------------------------------------------------------- radar

func _radar_xy(p: Car, world_pos: Vector3, c: Vector2, r: float) -> Array:
	var f := p.forward()
	f.y = 0
	f = f.normalized()
	var right := Vector3(-f.z, 0, f.x)
	var rel := world_pos - p.global_position
	var v := Vector2(rel.dot(right), -rel.dot(f)) * (r / RADAR_RANGE)
	var edge := false
	if v.length() > r - 6:
		v = v.normalized() * (r - 6)
		edge = true
	return [c + v, edge]

func _draw_radar(lvl: Level, p: Car, c: Vector2, r: float) -> void:
	draw_circle(c, r + 6, Color(0.55, 0.45, 0.3, 0.85))
	draw_circle(c, r, Color(0.04, 0.08, 0.06, 0.82))
	for k in [0.33, 0.66]:
		draw_arc(c, r * k, 0, TAU, 48, Color(0.3, 0.7, 0.45, 0.35), 1.0)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(0.3, 0.7, 0.45, 0.25))
	draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(0.3, 0.7, 0.45, 0.25))
	# sweep
	var a := fmod(Time.get_ticks_msec() * 0.0025, TAU)
	draw_line(c, c + Vector2(cos(a), sin(a)) * r, Color(0.4, 1.0, 0.6, 0.35), 2.0)
	# north marker
	var n := _radar_xy(p, p.global_position + Vector3(0, 0, -RADAR_RANGE * 2.0), c, r + 14)
	_txt(n[0] + Vector2(-5, 7), "N", 20, Color(1, 0.9, 0.6))
	for car in lvl.get_tree().get_nodes_in_group("cars"):
		if car == p or car.dead:
			continue
		var res := _radar_xy(p, car.global_position, c, r)
		var col := Color(1, 0.25, 0.15) if car.team == Defs.Team.ENEMY else (Color(0.4, 1, 0.45) if car.team == Defs.Team.PLAYER else Color(0.8, 0.8, 0.8))
		var s := 4.5 if not car.boss else 7.5
		if res[1] and not car.boss and not hud.tracked.has(car):
			continue
		draw_rect(Rect2(res[0] - Vector2(s, s) * 0.5, Vector2(s, s)), col)
		if car.boss:
			draw_arc(res[0], 8, 0, TAU, 16, col, 1.5)
	for s2 in lvl.get_tree().get_nodes_in_group("targets"):
		var res2 := _radar_xy(p, s2.global_position, c, r)
		if not res2[1]:
			draw_rect(Rect2(res2[0] - Vector2(4, 4), Vector2(8, 8)), Color(1, 0.6, 0.1), false, 2.0)
	for b in lvl.beacons():
		var res3 := _radar_xy(p, b.get_meta("target"), c, r)
		_star(res3[0], 7.0, Color(1, 0.85, 0.2))
	# player arrow
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(6, 7), c + Vector2(0, 3), c + Vector2(-6, 7)]), Color(1, 1, 0.9))

func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var rr := r if k % 2 == 0 else r * 0.45
		var a := -PI / 2 + k * PI / 5
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, col)

# ------------------------------------------------------------------ armour

func _draw_armor(p: Car, c: Vector2) -> void:
	var w := 58.0
	var h := 118.0
	draw_rect(Rect2(c - Vector2(w + 34, h * 0.5 + 34), Vector2(w * 2 + 68 + 26, h + 78)), Color(0.05, 0.04, 0.03, 0.6))
	var t := 13.0
	var hw := w * 0.5
	var hh := h * 0.5
	var polys := {
		"front": [c + Vector2(-hw, -hh), c + Vector2(hw, -hh), c + Vector2(hw - t, -hh + t), c + Vector2(-hw + t, -hh + t)],
		"rear": [c + Vector2(-hw + t, hh - t), c + Vector2(hw - t, hh - t), c + Vector2(hw, hh), c + Vector2(-hw, hh)],
		"left": [c + Vector2(-hw, -hh), c + Vector2(-hw + t, -hh + t), c + Vector2(-hw + t, hh - t), c + Vector2(-hw, hh)],
		"right": [c + Vector2(hw - t, -hh + t), c + Vector2(hw, -hh), c + Vector2(hw, hh), c + Vector2(hw - t, hh - t)],
	}
	for side in polys:
		var col := health_color(p.armor_frac(side))
		draw_colored_polygon(PackedVector2Array(polys[side]), col)
	# body
	draw_rect(Rect2(c - Vector2(hw - t - 2, hh - t - 2), Vector2((hw - t - 2) * 2, (hh - t - 2) * 2)), Color(0.1, 0.1, 0.1, 0.9))
	var hf := p.health_frac()
	var bh := (hh - t - 6) * 2 * hf
	draw_rect(Rect2(Vector2(c.x - 8, c.y + hh - t - 4 - bh), Vector2(16, bh)), health_color(hf))
	# windshield / wheels for silhouette
	draw_rect(Rect2(c + Vector2(-hw - 5, -hh + 12), Vector2(5, 20)), Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(c + Vector2(hw, -hh + 12), Vector2(5, 20)), Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(c + Vector2(-hw - 5, hh - 32), Vector2(5, 20)), Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(c + Vector2(hw, hh - 32), Vector2(5, 20)), Color(0.2, 0.2, 0.2))
	_txt(c + Vector2(-hw - 30, hh + 30), "ARMOR", 20, Color(0.95, 0.85, 0.6))
	_txt(c + Vector2(hw - 10, hh + 30), "CHASSIS %d%%" % int(hf * 100), 20, health_color(hf))

# --------------------------------------------------------------- speedometer

func _draw_speedo(p: Car, c: Vector2, r: float) -> void:
	draw_circle(c, r + 8, Color(0.75, 0.75, 0.72))
	draw_circle(c, r + 4, Color(0.3, 0.3, 0.3))
	draw_circle(c, r, Color(0.93, 0.88, 0.74))
	var a0 := deg_to_rad(135.0)
	var sweep := deg_to_rad(270.0)
	for mph in range(0, 121, 5):
		var a := a0 + sweep * mph / 120.0
		var d := Vector2(cos(a), sin(a))
		var big := mph % 20 == 0
		draw_line(c + d * (r - (14 if big else 8)), c + d * (r - 3), Color(0.15, 0.1, 0.08), 3.0 if big else 1.5)
		if big:
			var tp := c + d * (r - 28)
			_txt(tp + Vector2(-12, 7), str(mph), 18, Color(0.2, 0.1, 0.05, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 24)
	# red zone
	draw_arc(c, r - 5, a0 + sweep * 100.0 / 120.0, a0 + sweep, 12, Color(0.8, 0.1, 0.05), 5.0)
	var mph_now := absf(p.speed) * 2.23694
	var an := a0 + sweep * clampf(mph_now / 120.0, 0.0, 1.05)
	var dn := Vector2(cos(an), sin(an))
	draw_line(c - dn * 12, c + dn * (r - 10), Color(0.75, 0.08, 0.05), 4.0)
	draw_circle(c, 9, Color(0.2, 0.2, 0.2))
	draw_rect(Rect2(c + Vector2(-26, 26), Vector2(52, 28)), Color(0.1, 0.08, 0.06))
	_txt(c + Vector2(-26, 49), "%03d" % int(mph_now), 24, Color(1, 0.85, 0.5), HORIZONTAL_ALIGNMENT_CENTER, 52)
	_txt(c + Vector2(-8, -34), "MPH", 16, Color(0.3, 0.15, 0.1))
	var gear_s := "R" if p.speed < -0.5 and p.brake > 0.1 else str(p.gear)
	_txt(c + Vector2(r - 8, r - 4), gear_s, 30, Color(1, 0.85, 0.4))

# ------------------------------------------------------------------ weapons

func _draw_weapons(p: Car, pos: Vector2) -> void:
	var y := pos.y
	var lines: Array = []
	for g in p.guns:
		lines.append([g, false])
	var cur := p.current_special()
	for s in p.specials:
		lines.append([s, s == cur])
	draw_rect(Rect2(pos - Vector2(12, 30), Vector2(236, 34 + lines.size() * 30)), Color(0.05, 0.04, 0.03, 0.6))
	for l in lines:
		var w: Weapon = l[0]
		var sel: bool = l[1]
		var col := Color(1, 0.85, 0.4) if sel or w.d.slot == "gun" else Color(0.75, 0.7, 0.6)
		if not w.has_ammo():
			col = Color(0.5, 0.4, 0.35)
		var nm: String = w.d.name
		if sel:
			draw_colored_polygon(PackedVector2Array([Vector2(pos.x - 8, y - 16), Vector2(pos.x, y - 10), Vector2(pos.x - 8, y - 4)]), col)
		_txt(Vector2(pos.x + 4, y), nm.to_upper(), 22, col)
		_txt(Vector2(pos.x + 150, y), str(w.ammo) if not w.infinite else "--", 22, col, HORIZONTAL_ALIGNMENT_RIGHT, 70)
		y += 30

# ------------------------------------------------------------------ targets

func _screen(cam: Camera3D, wp: Vector3) -> Array:
	var behind := cam.is_position_behind(wp)
	var sp := cam.unproject_position(wp)
	return [sp, behind]

func _draw_target(lvl: Level, p: Car) -> void:
	var t: Node3D = p.aim_target
	if not t or not is_instance_valid(t):
		return
	var cam := lvl.cam
	var h := 1.0
	if t.has_method("dims"):
		h = t.dims().y
	var wp := t.global_position + Vector3(0, h * 0.5, 0)
	var res := _screen(cam, wp)
	var sp: Vector2 = res[0]
	var dist := wp.distance_to(p.global_position)
	var col := Color(1, 0.3, 0.15)
	if res[1] or not get_viewport_rect().has_point(sp):
		_edge_arrow(sp, res[1], col, "")
		return
	var s := clampf(900.0 / maxf(dist, 1.0), 14.0, 70.0)
	for k in 4:
		var sx := -1.0 if k % 2 == 0 else 1.0
		var sy := -1.0 if k < 2 else 1.0
		var corner := sp + Vector2(sx, sy) * s
		draw_line(corner, corner - Vector2(sx * s * 0.45, 0), col, 2.5)
		draw_line(corner, corner - Vector2(0, sy * s * 0.45), col, 2.5)
	var nm: String = t.get("display_name") if t.get("display_name") else "TARGET"
	_txt(sp + Vector2(-100, -s - 26), nm.to_upper(), 20, col, HORIZONTAL_ALIGNMENT_CENTER, 200)
	var hf: float = t.health_frac() if t.has_method("health_frac") else 1.0
	draw_rect(Rect2(sp + Vector2(-40, s + 8), Vector2(80, 7)), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(sp + Vector2(-40, s + 8), Vector2(80 * hf, 7)), health_color(hf))
	_txt(sp + Vector2(-40, s + 34), "%d M" % int(dist), 18, Color(1, 0.9, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 80)

func _edge_arrow(sp: Vector2, behind: bool, col: Color, label: String) -> void:
	var r := get_viewport_rect()
	var c := r.size * 0.5
	var d := sp - c
	if behind:
		d = -d
	if d.length() < 1.0:
		d = Vector2(0, 1)
	d = d.normalized()
	var m := 60.0
	var t := minf(absf((c.x - m) / d.x) if absf(d.x) > 0.001 else INF, absf((c.y - m) / d.y) if absf(d.y) > 0.001 else INF)
	var p := c + d * t
	var perp := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([p + d * 16, p - d * 8 + perp * 11, p - d * 8 - perp * 11]), col)
	if label != "":
		_txt(p - d * 30 + Vector2(-60, 6), label, 20, col, HORIZONTAL_ALIGNMENT_CENTER, 120)

func _draw_beacons(lvl: Level) -> void:
	var cam := lvl.cam
	for b in lvl.beacons():
		var wp: Vector3 = b.get_meta("target") + Vector3(0, 3, 0)
		var res := _screen(cam, wp)
		var dist := wp.distance_to(lvl.player.global_position)
		var label := "%s %dM" % [b.get_meta("label", ""), int(dist)]
		var col := Color(1, 0.85, 0.25)
		if res[1] or not get_viewport_rect().grow(-40).has_point(res[0]):
			_edge_arrow(res[0], res[1], col, label.strip_edges())
		else:
			_star(res[0], 10.0, col)
			_txt(res[0] + Vector2(-100, -18), label.strip_edges(), 20, col, HORIZONTAL_ALIGNMENT_CENTER, 200)

func _draw_tracked(pos: Vector2) -> void:
	var y := pos.y
	for c in hud.tracked:
		if not is_instance_valid(c):
			continue
		var hf: float = c.health_frac()
		_txt(Vector2(pos.x, y), String(c.display_name).to_upper(), 20, Color(0.6, 1, 0.6))
		draw_rect(Rect2(Vector2(pos.x, y + 6), Vector2(300, 8)), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(Vector2(pos.x, y + 6), Vector2(300 * hf, 8)), health_color(hf))
		y += 36

func _draw_crosshair(lvl: Level, p: Car) -> void:
	var cam := lvl.cam
	if cam.mode == 2 or cam.cine_active:
		pass
	var aim := p.global_transform * Vector3(0, 1.0, -60.0)
	var res := _screen(cam, aim)
	if res[1]:
		return
	var sp: Vector2 = res[0]
	var col := Color(1, 0.95, 0.8, 0.7)
	draw_arc(sp, 10, 0, TAU, 20, col, 1.5)
	draw_line(sp - Vector2(18, 0), sp - Vector2(12, 0), col, 1.5)
	draw_line(sp + Vector2(12, 0), sp + Vector2(18, 0), col, 1.5)
	draw_line(sp - Vector2(0, 18), sp - Vector2(0, 12), col, 1.5)
