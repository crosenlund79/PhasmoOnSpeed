class_name ReplayPlayer
extends Node2D
## Plays back a recorded run (ReplayRecorder data) at a fixed speed and loops.
## Purely visual: it rebuilds the house view and moves puppet tokens. It never
## creates gameplay nodes, never touches SaveData and never records statistics.

const SPEED := 4.0
const LOOP_PAUSE := 1.6

var replay := {}
var map: HouseMap
var view: HouseView
var camera: Camera2D
var t := 0.0
var duration := 0.0
var _hold := 0.0
var _tokens := {}        # actor id -> TokenSprite
var _idx := {}           # actor id -> sample index (5 floats per sample)
var _event_i := 0
var _decals := {}
var _flashlight: PointLight2D
var _ambient: PointLight2D
var _flash_on := true
var follow := "player_1"
var zoom := 1.25
var camera_offset := Vector2.ZERO

func setup(p_replay: Dictionary) -> void:
	replay = p_replay

func _ready() -> void:
	map = HouseMap.from_data(Game.house(replay.get("house", "ashgrove")))
	view = HouseView.new()
	view.build(map, false, true)
	add_child(view)
	duration = float(replay.get("duration", 0.0))
	for aid in replay.get("actors", {}):
		var a: Dictionary = replay["actors"][aid]
		var tk := TokenSprite.new(a["token"], float(a.get("size", 32.0)))
		tk.modulate.a = 0.0
		view.actor_layer.add_child(tk)
		_tokens[aid] = tk
	_ambient = PointLight2D.new()
	_ambient.texture = Art.tex("lights/soft.png")
	_ambient.texture_scale = 0.45
	_ambient.energy = 0.6
	add_child(_ambient)
	_flashlight = PointLight2D.new()
	var cone := Art.tex("lights/cone.png")
	_flashlight.texture = cone
	_flashlight.texture_scale = 0.62
	_flashlight.energy = 1.2
	_flashlight.color = Color(1.0, 0.92, 0.75)
	_flashlight.shadow_enabled = true
	add_child(_flashlight)
	camera = Camera2D.new()
	camera.zoom = Vector2(zoom, zoom)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	camera.offset = camera_offset
	add_child(camera)
	camera.make_current()
	_restart()

func _restart() -> void:
	t = 0.0
	_event_i = 0
	for aid in _tokens:
		_idx[aid] = 0
		_tokens[aid].set_token(replay["actors"][aid]["token"])
		_tokens[aid].modulate = Color(1, 1, 1, 0)
	for k in _decals:
		if is_instance_valid(_decals[k]):
			_decals[k].queue_free()
	_decals.clear()
	_flash_on = true
	view.set_darkness(HouseView.DARKNESS, 0.01)
	_apply(0.0)
	if camera and _tokens.has(follow):
		camera.position = _tokens[follow].position
		camera.reset_smoothing()

func _process(delta: float) -> void:
	if duration <= 0.0:
		return
	if _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			_restart()
		return
	t += delta * SPEED
	if t >= duration:
		t = duration
		_hold = LOOP_PAUSE
	_apply(t)

func _apply(now: float) -> void:
	var events: Array = replay.get("events", [])
	while _event_i < events.size() and float(events[_event_i][0]) <= now:
		_event(events[_event_i])
		_event_i += 1
	for aid in _tokens:
		var tr: Array = replay["tracks"].get(aid, [])
		if tr.is_empty():
			continue
		var i: int = _idx[aid]
		while i + 5 < tr.size() and float(tr[i + 5]) <= now:
			i += 5
		_idx[aid] = i
		var tk: TokenSprite = _tokens[aid]
		var a := Vector2(tr[i + 1], tr[i + 2])
		var rot := float(tr[i + 3])
		var alpha := float(tr[i + 4])
		if float(tr[i]) > now:
			alpha = 0.0
		elif i + 5 < tr.size():
			var t0 := float(tr[i])
			var t1 := float(tr[i + 5])
			var k := clampf((now - t0) / maxf(0.001, t1 - t0), 0.0, 1.0)
			a = a.lerp(Vector2(tr[i + 6], tr[i + 7]), k)
			rot = lerp_angle(rot, float(tr[i + 8]), k)
			alpha = lerpf(alpha, float(tr[i + 9]), k)
		tk.position = a
		tk.face_now(rot)
		tk.modulate.a = alpha
	if _tokens.has(follow):
		var p: TokenSprite = _tokens[follow]
		camera.position = p.position
		_ambient.position = p.position
		_flashlight.visible = _flash_on and p.modulate.a > 0.1
		_flashlight.rotation = p.facing
		_flashlight.position = p.position + Vector2.RIGHT.rotated(p.facing) * _flashlight.texture.get_size().x * 0.5 * _flashlight.texture_scale

func _event(ev: Array) -> void:
	var type: String = ev[1]
	var d: Dictionary = ev[2]
	match type:
		"decal":
			var s := Sprite2D.new()
			s.texture = Art.tex(d["sprite"])
			s.position = Vector2(d["x"], d["y"])
			s.rotation = float(d.get("rot", 0.0))
			var k := float(d.get("size", 28.0)) / maxf(1.0, s.texture.get_size().x)
			s.scale = Vector2(k, k)
			if str(d["sprite"]).contains("uv_handprint"):
				s.modulate = Color(0.7, 0.5, 1.0, 0.8)
			view.decal_layer.add_child(s)
			_decals[d["id"]] = s
		"decal_remove":
			if _decals.has(d["id"]) and is_instance_valid(_decals[d["id"]]):
				_decals[d["id"]].queue_free()
			_decals.erase(d["id"])
		"decal_swap":
			if _decals.has(d["id"]) and is_instance_valid(_decals[d["id"]]):
				_decals[d["id"]].texture = Art.tex(d["sprite"])
		"token":
			if _tokens.has(d["actor"]):
				_tokens[d["actor"]].set_token(d["token"])
		"flashlight":
			_flash_on = d.get("on", true)
		"hunt_start":
			view.flicker(3.5 / SPEED + 0.5, 1.0)
			view.set_darkness(HouseView.DARKNESS_HUNT, 0.3)
		"hunt_end":
			view.set_darkness(HouseView.DARKNESS, 0.4)
		"harbinger":
			view.flicker(2.0, 1.0)
			view.set_darkness(HouseView.DARKNESS_HARBINGER, 0.4)
		"reckless":
			view.flicker(1.0, 1.0)
		"mirror":
			view.show_mirror_overlay(int(d["index"]), Art.tex(Defs.FORM_TOKENS["true"]), 0.85 if d.get("on", true) else 0.0)
		"death":
			view.set_darkness(Color(0.06, 0.02, 0.02), 0.5)
		"vanquish":
			view.set_darkness(Color(0.42, 0.42, 0.5), 0.6)
