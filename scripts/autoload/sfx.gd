extends Node
## Sound playback: one-shots (with anti-spam cooldowns), positional sounds and
## named loops. Sounds are referenced by a stable id — the file stem of the
## generated placeholder in res://assets/audio/. A creator file listed in
## AudioCatalog (res://assets/creator/audio/…) replaces the placeholder's audio;
## everything about *how* the sound plays stays as below.

const AUDIO_DIR := "res://assets/audio/"
const POOL_SIZE := 12
const LOOP_NAMES := ["spirit_box_static", "hunt_loop", "ambience_house", "music_menu"]
## Per-sound default gain (dB) to balance the procedural mix.
const GAIN := {
	"stake_strike": 4.0, "camera_shutter": 5.0, "crucifix_burn": 3.0, "footstep": -10.0,
	"ambience_house": -2.0, "music_menu": -4.0, "hunt_loop": -1.0, "pencil_scribble": -1.0,
}

var _streams := {}          # id -> Array[AudioStream] (creator variants, or the placeholder)
var _sources := {}          # id -> "creator" / "placeholder" (for checks and the catalog)
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played := {}
var _loops := {}
var master_volume := 0.8
var music_volume := 0.6

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)

func apply_volumes(master: float, music: float) -> void:
	master_volume = master
	music_volume = music
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master, 0.0001)))
	for key in _loops:
		var p: AudioStreamPlayer = _loops[key]
		p.volume_db = _loop_db(key, p.get_meta("base_db", 0.0))

func _loop_db(key: String, base_db: float) -> float:
	if key == "music":
		return base_db + linear_to_db(maxf(music_volume, 0.0001))
	return base_db

## The stream to play for a cue. Creator files win; with several variants one is
## picked at random each time (loops always use their first file so they never
## restart mid-play). Missing everything → null, and callers simply stay silent.
func stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		_streams[sound] = _resolve(sound)
	var list: Array = _streams[sound]
	if list.is_empty():
		return null
	if list.size() == 1 or sound in LOOP_NAMES:
		return list[0]
	return list[randi() % list.size()]

func source_of(sound: String) -> String:
	stream(sound)
	return _sources.get(sound, "missing")

## Forget resolved streams (after adding or removing creator files at runtime).
func clear_cache() -> void:
	_streams.clear()
	_sources.clear()

func _resolve(sound: String) -> Array:
	var out: Array = []
	var seen := {}
	for path in AudioCatalog.candidates(sound):
		var base: String = path.get_basename()
		if seen.has(base):
			continue   # a cue's .wav and .ogg with the same name count once (preferred format first)
		var s := AudioCatalog.load_stream(path)
		if s:
			seen[base] = true
			out.append(_prepared(sound, s))
	if not out.is_empty():
		_sources[sound] = "creator"
		return out
	var path := AUDIO_DIR + sound + ".wav"
	if ResourceLoader.exists(path):
		_sources[sound] = "placeholder"
		return [_prepared(sound, load(path))]
	_sources[sound] = "missing"
	return []

## Looping cues loop whatever file supplies them.
func _prepared(sound: String, s: AudioStream) -> AudioStream:
	if not (sound in LOOP_NAMES):
		return s
	if s is AudioStreamWAV:
		s = s.duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	elif s is AudioStreamOggVorbis:
		s = s.duplicate()
		s.loop = true
	return s

## Plays a non-positional one-shot. min_interval suppresses spam of the same sound.
func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0, min_interval: float = 0.05) -> void:
	var s := stream(sound)
	if s == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(sound, -100.0)) < min_interval:
		return
	_last_played[sound] = now
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = s
	p.volume_db = volume_db + GAIN.get(sound, 0.0)
	p.pitch_scale = pitch
	p.play()

## Plays a sound at a world position (attached to `parent`, normally the run world).
func play_at(sound: String, pos: Vector2, parent: Node, volume_db: float = 0.0, pitch: float = 1.0, max_distance: float = 1400.0) -> void:
	var s := stream(sound)
	if s == null or parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = s
	p.position = pos
	p.volume_db = volume_db + GAIN.get(sound, 0.0)
	p.pitch_scale = pitch
	p.max_distance = max_distance
	p.attenuation = 1.4
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func start_loop(key: String, sound: String, volume_db: float = 0.0, fade: float = 0.6) -> void:
	var s := stream(sound)
	if s == null:
		return
	var p: AudioStreamPlayer = _loops.get(key)
	if p and p.stream == s and p.playing:
		return
	if p == null:
		p = AudioStreamPlayer.new()
		add_child(p)
		_loops[key] = p
	p.stream = s
	p.set_meta("base_db", volume_db + GAIN.get(sound, 0.0))
	var target := _loop_db(key, p.get_meta("base_db"))
	p.volume_db = -40.0
	p.play()
	create_tween().tween_property(p, "volume_db", target, fade)

func set_loop_pitch(key: String, pitch: float) -> void:
	var p: AudioStreamPlayer = _loops.get(key)
	if p:
		create_tween().tween_property(p, "pitch_scale", pitch, 0.8)

func stop_loop(key: String, fade: float = 0.6) -> void:
	var p: AudioStreamPlayer = _loops.get(key)
	if p == null or not p.playing:
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -50.0, fade)
	tw.tween_callback(p.stop)

func stop_all_loops() -> void:
	for key in _loops:
		stop_loop(key, 0.3)
