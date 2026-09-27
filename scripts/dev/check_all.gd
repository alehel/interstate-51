extends Node
## Dev tool: loads every script so parse/compile errors show up with autoloads present.
func _ready() -> void:
	var n := 0
	for f in _scan("res://scripts"):
		var s = load(f)
		if s == null:
			printerr("FAILED: ", f)
		n += 1
	print("checked %d scripts" % n)
	get_tree().quit()

func _scan(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		out.append_array(_scan(dir + "/" + sub))
	return out
