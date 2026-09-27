extends Node3D
## Dev tool: renders screenshots of the world from preset viewpoints.
## godot --path . res://scenes/dev/shot_world.tscn -- --time=noon --out=/tmp/x

var shots: Array = []
var out := "user://shots"
var time := "afternoon"
var cam: Camera3D
var frame := 0
var idx := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--time="): time = a.substr(7)
		if a.begins_with("--out="): out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var w := Lib.ensure_world()
	var fx := Fx.new()
	add_child(fx)
	var wb := WorldBuilder.new()
	add_child(wb)
	wb.build(w, time)
	EnvSetup.build(self, time)
	cam = Camera3D.new()
	cam.far = 30000.0
	cam.fov = 65
	add_child(cam)
	# cars lined up at the Boneyard
	var keys := ["merc", "raider", "bruiser", "hauler", "cruiser", "duchess", "hearse", "wagon", "semi", "supply", "juggernaut", "jeep"]
	var base := Vector3(-620, 0, 1000)
	for i in keys.size():
		var d := CarBuilder.build(keys[i])
		var p := base + Vector3(i * 7.0, 0, 0)
		p.y = w.height(p.x, p.z)
		var mi := MeshInstance3D.new()
		mi.mesh = d.body
		add_child(mi)
		mi.global_position = p
		mi.rotation.y = 0.5
		for wp in d.wheels + d.extra_wheels:
			var wm := MeshInstance3D.new()
			wm.mesh = d.wheel
			mi.add_child(wm)
			wm.position = wp
			if wp.x < 0: wm.rotation.y = PI
	var h := func(x, z, o): return Vector3(x, w.height(x, z) + o, z)
	shots = [
		["cars", h.call(-600, 1018, 3.5), h.call(-585, 1000, 0.8)],
		["cars2", h.call(-560, 990, 2.5), h.call(-575, 1000, 1.0)],
		["boneyard", h.call(-620, 1060, 25), h.call(-700, 950, 0)],
		["hals", h.call(-330, -1650, 18), h.call(-180, -1700, 0)],
		["highway", h.call(-120, -900, 3), h.call(-200, -1500, 0)],
		["canyon", h.call(-1300, 520, 6), h.call(-1550, 280, 2)],
		["goldcreek", h.call(-2180, -300, 15), h.call(-2330, -300, 0)],
		["depot", h.call(1760, -560, 25), h.call(1950, -600, 0)],
		["mine", h.call(1650, -1950, 30), h.call(1700, -2180, 0)],
		["airstrip", h.call(1950, 2000, 30), h.call(2250, 2100, 0)],
		["aerial", Vector3(0, 900, 2500), Vector3(0, 0, 0)],
		["flat", h.call(1600, 1000, 12), h.call(1800, 1200, 0)],
	]

func _process(_d: float) -> void:
	frame += 1
	if frame < 3:
		return
	if idx > 0 and frame % 3 == 0:
		get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, time, shots[idx - 1][0]])
	if frame % 3 == 0:
		if idx >= shots.size():
			get_tree().quit()
			return
		cam.global_position = shots[idx][1]
		cam.look_at(shots[idx][2], Vector3.UP)
		idx += 1
