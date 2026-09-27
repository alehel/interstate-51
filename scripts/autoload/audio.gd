extends Node
## Music, sound effects and voiced dialogue.

signal line_started(id: String, speaker: String, text: String)
signal line_finished(id: String)

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const VOICE_DIR := "res://assets/voice/"

var lines: Dictionary = {}
var speakers: Dictionary = {}
var barks: Dictionary = {}

var _cache: Dictionary = {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_cur: AudioStreamPlayer
var _music_name := ""
var _voice: AudioStreamPlayer
var _voice_queue: Array = []
var _voice_id := ""
var _voice_is_bark := false
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _duck := 0.0
var _last_bark_time := -100.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX", "Voice", "UI"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")
	# Gentle limiter on master so explosions don't clip.
	var mi := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(mi) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(mi, lim)
	_music_a = _mk_player("Music")
	_music_b = _mk_player("Music")
	_voice = _mk_player("Voice")
	_voice.finished.connect(_on_voice_finished)
	for i in 12:
		_pool2d.append(_mk_player("SFX"))
	for i in 40:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 12.0
		p.max_distance = 600.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		_pool3d.append(p)
	_load_dialogue()
	apply_volumes()

func _mk_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p

func _load_dialogue() -> void:
	var f := FileAccess.open("res://data/dialogue.json", FileAccess.READ)
	if not f:
		push_error("dialogue.json missing")
		return
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	lines = d.get("lines", {})
	speakers = d.get("speakers", {})
	barks = d.get("barks", {})

func apply_volumes() -> void:
	var s: Dictionary = Game.settings
	_set_bus("Master", s.master)
	_set_bus("Music", s.music)
	_set_bus("SFX", s.sfx)
	_set_bus("Voice", s.voice)
	_set_bus("UI", s.sfx)

func _set_bus(bus: String, lin: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(lin, 0.0001)))

# ------------------------------------------------------------------ streams

func stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_cache[path] = s
	return s

func sfx(name: String) -> AudioStream:
	return stream(SFX_DIR + name + ".ogg")

func looped(name: String) -> AudioStream:
	var key := "loop:" + name
	if _cache.has(key):
		return _cache[key]
	var s := sfx(name)
	if s:
		s = s.duplicate()
		if s is AudioStreamOggVorbis:
			s.loop = true
	_cache[key] = s
	return s

func play(name: String, vol_db: float = 0.0, pitch: float = 1.0, bus: String = "SFX") -> void:
	var s := sfx(name)
	if not s:
		return
	for p in _pool2d:
		if not p.playing:
			p.stream = s
			p.volume_db = vol_db
			p.pitch_scale = pitch
			p.bus = bus
			p.play()
			return

func ui(name: String) -> void:
	play(name, -4.0, 1.0, "UI")

func play_at(name: String, pos: Vector3, vol_db: float = 0.0, pitch: float = 1.0, size: float = 12.0) -> void:
	var s := sfx(name)
	if not s:
		return
	var best: AudioStreamPlayer3D = null
	for p in _pool3d:
		if not p.playing:
			best = p
			break
	if not best:
		# steal the one furthest along
		best = _pool3d[randi() % _pool3d.size()]
	best.stream = s
	best.global_position = pos
	best.volume_db = vol_db
	best.pitch_scale = pitch * randf_range(0.95, 1.05)
	best.unit_size = size
	best.play()

# --------------------------------------------------------------- ambience

var _amb: Array[AudioStreamPlayer] = []

## Desert wind all day, crickets after dark. Pass "" to stop.
func ambience(time: String) -> void:
	for p in _amb:
		var tw := create_tween()
		tw.tween_property(p, "volume_db", -60.0, 1.0)
		tw.tween_callback(p.queue_free)
	_amb.clear()
	if time == "":
		return
	var layers := [["wind_loop", -17.0 if time != "night" else -22.0]]
	if time in ["night", "dusk", "dawn"]:
		layers.append(["crickets_loop", -12.0 if time == "night" else -17.0])
	for l in layers:
		var p := _mk_player("SFX")
		p.stream = looped(l[0])
		p.volume_db = -60.0
		p.play(randf() * 3.0)
		var tw := create_tween()
		tw.tween_property(p, "volume_db", l[1], 2.0)
		_amb.append(p)

# ------------------------------------------------------------------- music

func music(name: String, fade: float = 1.5, loop: bool = true) -> void:
	if name == _music_name and _music_cur and _music_cur.playing:
		return
	_music_name = name
	var s := stream(MUSIC_DIR + name + ".ogg")
	var old := _music_cur
	if s:
		s = s.duplicate()
		if s is AudioStreamOggVorbis:
			s.loop = loop
	var nxt := _music_b if _music_cur == _music_a else _music_a
	_music_cur = nxt
	if s:
		nxt.stream = s
		nxt.volume_db = -40.0
		nxt.play()
		var tw := create_tween()
		tw.tween_property(nxt, "volume_db", 0.0, fade)
	if old and old.playing:
		var tw2 := create_tween()
		tw2.tween_property(old, "volume_db", -60.0, fade)
		tw2.tween_callback(old.stop)

func stop_music(fade: float = 1.0) -> void:
	_music_name = ""
	for p in [_music_a, _music_b]:
		if p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -60.0, fade)
			tw.tween_callback(p.stop)

# ------------------------------------------------------------------- voice

func line_text(id: String) -> String:
	return lines.get(id, {}).get("t", "")

func line_speaker(id: String) -> String:
	return lines.get(id, {}).get("s", "")

func speaker_name(s: String) -> String:
	return speakers.get(s, {}).get("name", s)

func speaker_color(s: String) -> Color:
	return Color(speakers.get(s, {}).get("color", "#ffffff"))

func line_length(id: String) -> float:
	var st := stream(VOICE_DIR + id + ".ogg")
	if st:
		return st.get_length()
	return 1.0 + line_text(id).length() * 0.06

## Queue a story line. Story lines interrupt barks.
func say(id: String) -> void:
	if not lines.has(id):
		push_warning("Unknown line " + id)
		return
	if _voice_is_bark and _voice.playing:
		_voice.stop()
		_finish_current()
	_voice_queue.append(id)
	if not _voice.playing and _voice_id == "":
		_next_voice()

## Combat bark: only plays if nothing else is being said.
func bark(group: String, min_gap: float = 6.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _voice.playing or not _voice_queue.is_empty() or now - _last_bark_time < min_gap:
		return
	var ids: Array = barks.get(group, [])
	if ids.is_empty():
		return
	_last_bark_time = now
	_voice_queue.append(ids[randi() % ids.size()])
	_voice_is_bark = true
	_next_voice(true)

func pending(id: String) -> bool:
	return _voice_id == id or _voice_queue.has(id)

func is_speaking() -> bool:
	return _voice_id != "" or not _voice_queue.is_empty()

func stop_voice() -> void:
	_voice_queue.clear()
	_voice.stop()
	if _voice_id != "":
		_finish_current()

func _next_voice(is_bark: bool = false) -> void:
	if _voice_queue.is_empty():
		return
	var id: String = _voice_queue.pop_front()
	_voice_id = id
	_voice_is_bark = is_bark
	var spk := line_speaker(id)
	if spk != "DEACON":
		play("radio_on", -8.0, 1.0, "Voice")
	var st := stream(VOICE_DIR + id + ".ogg")
	line_started.emit(id, spk, line_text(id))
	if st:
		_voice.stream = st
		_voice.play()
	else:
		# no audio file: fake the duration so subtitles still work
		get_tree().create_timer(line_length(id), true, false, true).timeout.connect(_on_voice_finished)

func _finish_current() -> void:
	var id := _voice_id
	_voice_id = ""
	if id != "":
		if line_speaker(id) != "DEACON":
			play("radio_off", -10.0, 1.0, "Voice")
		line_finished.emit(id)

func _on_voice_finished() -> void:
	_finish_current()
	_voice_is_bark = false
	if not _voice_queue.is_empty():
		# small breath between lines
		await get_tree().create_timer(0.25, true, false, true).timeout
		if _voice_id == "" and not _voice.playing:
			_next_voice()

func _process(delta: float) -> void:
	var target := 1.0 if (_voice.playing and not _voice_is_bark) else 0.0
	_duck = move_toward(_duck, target, delta * 3.0)
	var mi := AudioServer.get_bus_index("Music")
	if mi >= 0:
		AudioServer.set_bus_volume_db(mi, linear_to_db(maxf(Game.settings.music, 0.0001)) - 7.0 * _duck)
