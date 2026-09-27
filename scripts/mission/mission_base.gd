class_name MissionBase
extends Node
## Base class for mission scripts. A mission sets its start conditions in
## setup() and tells its story in run(), a coroutine built from the helpers
## below (say / wait / wait_reach / wait_dead / spawn ...). Every wait is
## driven by this node's own `tick` signal, so when the level ends or is
## freed the coroutine simply stops.

signal tick

var level: Node        # Level
var world: WorldData
var t := 0.0
var running := false

# --- configured in setup()
var player_start := Vector3.ZERO
var player_yaw := 0.0            # radians, 0 = facing north (-Z)
var skip_intro := false

func setup() -> void:
	pass

func run() -> void:
	pass

func _physics_process(dt: float) -> void:
	if running:
		t += dt
		tick.emit()

# ------------------------------------------------------------------ timing

func wait(sec: float) -> void:
	var end := t + sec
	while t < end:
		await tick

func wait_until(cond: Callable, timeout: float = -1.0) -> bool:
	var end := t + timeout
	while not cond.call():
		if timeout > 0.0 and t > end:
			return false
		await tick
	return true

# ---------------------------------------------------------------- dialogue

func say(id: String) -> void:
	Audio.say(id)
	await tick
	while Audio.pending(id):
		await tick

func say_all(ids: Array) -> void:
	for id in ids:
		await say(id)

func sayn(id: String) -> void:
	Audio.say(id)

# ------------------------------------------------------------------- world

func p(x: float, z: float, lift: float = 0.0) -> Vector3:
	return world.pos(x, z, lift)

func road(name: String, from: Vector2, to: Vector2, lane: float = 0.0) -> PackedVector3Array:
	return world.road_path(name, from, to, lane)

func join(paths: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for pp in paths:
		out.append_array(pp)
	return out

func yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z)

## Spawn a car. ai: "attack" | "idle" | "park" | "path" | "escort" | "none"
func spawn(key: String, pos: Vector3, yaw: float, team: int = Defs.Team.ENEMY, ai: String = "attack", opts: Dictionary = {}) -> Car:
	return level.spawn_car(key, pos, yaw, team, ai, opts)

func spawn_road(key: String, road_name: String, at: Vector2, heading_to: Vector2, team: int = Defs.Team.ENEMY, ai: String = "attack", opts: Dictionary = {}, lane: float = 0.0) -> Car:
	var r := world.road(road_name)
	var i := world.road_index(road_name, at)
	var j := world.road_index(road_name, heading_to)
	var step := 1 if j >= i else -1
	var a := r.pts[i]
	var b := r.pts[clampi(i + step * 3, 0, r.pts.size() - 1)]
	var dir := (b - a)
	dir.y = 0
	var right := dir.normalized().cross(Vector3.UP)
	var pos := a + right * lane
	pos.y = world.height(pos.x, pos.z)
	return spawn(key, pos, yaw_to(a, b), team, ai, opts)

func structure(kind: String, pos: Vector3, yaw: float = 0.0, name_: String = "") -> Structure:
	return level.spawn_structure(kind, pos, yaw, name_)

func pickup(kind: String, pos: Vector3) -> Pickup:
	return level.spawn_pickup(kind, pos)

func alive(list: Array) -> int:
	var n := 0
	for c in list:
		if is_instance_valid(c) and not c.dead:
			n += 1
	return n

func wait_dead(list: Array, keep: int = 0) -> void:
	while alive(list) > keep:
		await tick

func wait_reach(pos: Vector3, radius: float = 18.0, label: String = "") -> void:
	var b: Node3D = level.set_beacon(pos, label)
	var t0 := t
	while level.player and level.player.global_position.distance_to(pos) > radius:
		if Game.autoplay and t - t0 > 2.0:
			teleport_player(pos)
		await tick
	level.clear_beacon(b)
	Audio.play("objective", -6.0)

## Testing aid: make the autopilot concentrate on the mission's key target.
func autoplay_focus(n: Node3D) -> void:
	if Game.autoplay and level.player:
		var a := Level.ai_of(level.player)
		if a:
			a.focus = n

## Testing aid: the autopilot shadows an escort target and guards it.
func autoplay_escort(c: Car) -> void:
	if Game.autoplay and level.player:
		var a := Level.ai_of(level.player)
		if a:
			a.mode = "escort"
			a.leader = c
			a.leader_offset = Vector3(0, 0, 12)
			a.guard_radius = 160.0

func teleport_player(pos: Vector3) -> void:
	var pl: Car = level.player
	pl.global_position = Vector3(pos.x, world.height(pos.x, pos.z) + 1.5, pos.z)
	pl.linear_velocity = Vector3.ZERO
	pl.angular_velocity = Vector3.ZERO

func dist_to_player(n: Node3D) -> float:
	if not is_instance_valid(n) or not level.player:
		return INF
	return n.global_position.distance_to(level.player.global_position)

# -------------------------------------------------------------- objectives

func objective(id: String, text: String) -> void:
	if Game.autoplay:
		print("[%.1f] OBJECTIVE: %s" % [t, text])
	level.hud.objective_add(id, text)

func complete(id: String) -> void:
	if Game.autoplay:
		print("[%.1f] COMPLETE: %s" % [t, id])
	level.hud.objective_done(id)
	Audio.play("objective", -4.0)

func msg(title: String, sub: String = "", dur: float = 3.5) -> void:
	level.hud.message(title, sub, dur)

func salvage(item: String) -> void:
	var nm: String = Defs.WEAPONS[item].name if Defs.WEAPONS.has(item) else Defs.UPGRADES.get(item, {}).get("name", item)
	level.hud.message("SALVAGE", nm, 4.0)

func hint(text: String, dur: float = 6.0) -> void:
	level.hud.hint(text, dur)

func timer(sec: float, label: String) -> void:
	level.hud.timer_start(sec, label)

func timer_stop() -> void:
	level.hud.timer_stop()

func timer_left() -> float:
	return level.hud.timer_left()

## Fail the mission if this car dies.
func protect(c: Car, reason: String) -> void:
	c.destroyed.connect(func(_c): level.fail(reason, "fail_escort"))
	level.hud.track(c)

func fail(reason: String, line: String = "fail_escape") -> void:
	level.fail(reason, line)

func win() -> void:
	level.win()

func music(name: String) -> void:
	Audio.music(name)

## Letterboxed camera move while lines play. shots: [[from, to, dur, follow?], ...]
func cinematic_start() -> void:
	level.set_cinematic(true)

func cinematic_end() -> void:
	level.set_cinematic(false)

func shot(from: Vector3, look_from: Vector3, to: Vector3, look_to: Vector3, dur: float, follow: Node3D = null) -> void:
	var a := Transform3D.IDENTITY.looking_at(look_from - from, Vector3.UP)
	a.origin = from
	var b := Transform3D.IDENTITY.looking_at(look_to - to, Vector3.UP)
	b.origin = to
	level.cam.cinematic(a, b, dur, follow)

## Orbiting shot around a node.
func orbit_shot(n: Node3D, radius: float, height: float, a0: float, a1: float, dur: float) -> void:
	var c := n.global_position
	shot(c + Vector3(sin(a0), 0, cos(a0)) * radius + Vector3(0, height, 0), c, c + Vector3(sin(a1), 0, cos(a1)) * radius + Vector3(0, height, 0), c, dur, n)

## Wait that ends early if the player presses skip (for cinematics).
func wait_skippable(sec: float) -> bool:
	var end := t + sec
	while t < end:
		if level.skip_requested:
			return true
		await tick
	return false
