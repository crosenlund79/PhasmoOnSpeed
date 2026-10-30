class_name ReplayPlayer
extends Node2D
## Plays back a recorded run or match (ReplayRecorder data) at a fixed speed and
## loops. Purely visual: it rebuilds the house view and moves puppet tokens. It
## never creates gameplay nodes, never touches SaveData and never records stats.

const SPEED := 4.0
const LOOP_PAUSE := 1.6

var replay := {}
var map: HouseMap
var view: HouseView
var camera: Camera2D
var fx: WorldFx
var text_layer: CanvasLayer
var t := 0.0
var duration := 0.0
var _hold := 0.0
var _tokens := {}        # actor id -> TokenSprite
var _idx := {}           # actor id -> sample index (5 floats per sample)
var _event_i := 0
var _lights := {}        # player actor id -> {cone, ambient, on}
var _labels := {}        # actor id -> Label (names in multiplayer)
var follow := "player_1"
## Moment popups: shown in the replay area, driven only by recorded events.
const MOMENT_HOLD := 1.8         # real seconds on screen
const MOMENT_MAX := 2
var moments_enabled := true
var _moment_layer: CanvasLayer
var _moment_box: VBoxContainer
var _moments: Array = []         # [{node, t, text}]
var zoom := 1.25
var camera_offset := Vector2.ZERO

func setup(p_replay: Dictionary) -> void:
	replay = p_replay

func _ready() -> void:
	map = HouseMap.from_data(Game.house(replay.get("house", "ashgrove")))
	view = HouseView.new()
	view.build(map, false, true)
	if replay.get("difficulty", "normal") == "nightmare":
		view.build_nightmare()
	add_child(view)
	text_layer = CanvasLayer.new()
	text_layer.layer = 1
	text_layer.follow_viewport_enabled = true
	add_child(text_layer)
	fx = WorldFx.new(view, text_layer)
	duration = float(replay.get("duration", 0.0))
	var mp: bool = replay.get("multiplayer", false)
	for aid in replay.get("actors", {}):
		var a: Dictionary = replay["actors"][aid]
		var tk := TokenSprite.new(a["token"], float(a.get("size", 32.0)))
		tk.modulate.a = 0.0
		view.actor_layer.add_child(tk)
		_tokens[aid] = tk
		if a["kind"] == "player":
			var cone := Lighting.make_cone(Color(1.0, 0.92, 0.75), 1.2, 0.62)
			add_child(cone)
			var amb := PointLight2D.new()
			amb.texture = Art.tex("lights/soft.png")
			amb.texture_scale = 0.45
			amb.energy = 0.6
			add_child(amb)
			_lights[aid] = {"cone": cone, "ambient": amb, "on": true}
		if mp and a.has("name"):
			var l := Label.new()
			l.text = a["name"]
			l.add_theme_font_override("font", Art.font_heading)
			l.add_theme_font_size_override("font_size", 13)
			var idx := int(a.get("index", 0))
			l.add_theme_color_override("font_color", Player.COLORS[idx % 4] if a["kind"] == "player" else SpeechTag.NAME_COLOR)
			l.add_theme_color_override("font_outline_color", Color.BLACK)
			l.add_theme_constant_override("outline_size", 5)
			l.size = Vector2(160, 18)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			text_layer.add_child(l)
			_labels[aid] = l
	camera = Camera2D.new()
	camera.zoom = Vector2(zoom, zoom)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	camera.offset = camera_offset
	add_child(camera)
	camera.make_current()
	_build_moments()
	_restart()

func _restart() -> void:
	t = 0.0
	_event_i = 0
	for m in _moments:
		m["node"].queue_free()
	_moments.clear()
	for aid in _tokens:
		_idx[aid] = 0
		_tokens[aid].set_token(replay["actors"][aid]["token"])
		_tokens[aid].modulate = Color(1, 1, 1, 0)
		_tokens[aid].sprite.modulate = Color.WHITE
	for aid in _lights:
		_lights[aid]["on"] = true
	fx.clear()
	for i in view.mirrors.size():
		view.show_mirror_overlay(i, null, 0.0)
	view.set_darkness(HouseView.DARKNESS, 0.01)
	_apply(0.0)
	if camera and _tokens.has(follow):
		camera.position = _tokens[follow].position
		camera.reset_smoothing()

func _process(delta: float) -> void:
	fx.tick(delta * SPEED)
	_tick_moments(delta)
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
			var b := Vector2(tr[i + 6], tr[i + 7])
			# Never smear a staircase jump across the void between floors.
			if a.distance_to(b) < 140.0:
				var t0 := float(tr[i])
				var t1 := float(tr[i + 5])
				var k := clampf((now - t0) / maxf(0.001, t1 - t0), 0.0, 1.0)
				a = a.lerp(b, k)
				rot = lerp_angle(rot, float(tr[i + 8]), k)
				alpha = lerpf(alpha, float(tr[i + 9]), k)
		tk.position = a
		tk.face_now(rot)
		tk.modulate.a = alpha
		if _lights.has(aid):
			var L: Dictionary = _lights[aid]
			L["cone"].position = a
			L["cone"].rotation = rot
			L["cone"].visible = L["on"] and alpha > 0.5
			L["ambient"].position = a
		if _labels.has(aid):
			_labels[aid].position = a + Vector2(-80, -40)
			_labels[aid].modulate.a = alpha
	if _tokens.has(follow):
		var p: TokenSprite = _tokens[follow]
		if camera.position.distance_to(p.position) > 400.0:
			camera.position = p.position
			camera.reset_smoothing()
		camera.position = p.position

func _event(ev: Array) -> void:
	var type: String = ev[1]
	var d: Dictionary = ev[2]
	var m := _moment_for(type, d)
	if not m.is_empty():
		_show_moment(m[0], m[1])
	if fx.apply(type, d):
		return
	match type:
		"token":
			if _tokens.has(d["actor"]):
				_tokens[d["actor"]].set_token(d["token"])
		"flashlight":
			var aid: String = d.get("actor", "player_1")
			if _lights.has(aid):
				_lights[aid]["on"] = d.get("on", true)
		"death":
			var aid: String = d.get("actor", "player_1")
			if _tokens.has(aid):
				_tokens[aid].sprite.modulate = Color(0.6, 0.1, 0.1)
		"vanquish":
			view.set_darkness(Color(0.42, 0.42, 0.5), 0.6)

# --- Moment notifications ------------------------------------------------------------------

func _build_moments() -> void:
	_moment_layer = CanvasLayer.new()
	_moment_layer.layer = 6      # above the world and the results screen's shading; kept within the replay area
	add_child(_moment_layer)
	_moment_box = VBoxContainer.new()
	_moment_box.alignment = BoxContainer.ALIGNMENT_END
	_moment_box.add_theme_constant_override("separation", 6)
	_moment_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_moment_layer.add_child(_moment_box)

func _who(d: Dictionary) -> String:
	var aid: String = d.get("actor", "")
	var a: Dictionary = replay.get("actors", {}).get(aid, {})
	if replay.get("multiplayer", false) and a.has("name"):
		return str(a["name"])
	return "The investigator"

## Icon and words for the recorded moments worth explaining; [] for the rest.
func _moment_for(type: String, d: Dictionary) -> Array:
	match type:
		"evidence":
			var e: Dictionary = Defs.EVIDENCE.get(d.get("id", ""), {})
			if e.is_empty():
				return []
			var who := "" if not replay.get("multiplayer", false) else _who(d) + ": "
			return [e["icon"], "%s%s discovered" % [who, e["name"]]]
		"attack":
			if int(d.get("wounds", 1)) >= 2:
				return []    # the death moment follows
			return ["icons/ui_heart_wounded.png", "%s wounded" % _who(d)]
		"death":
			return ["icons/ui_skull.png", "%s perished" % _who(d)]
		"hunt_start":
			return ["icons/ui_skull.png", "Reckless hunt started" if d.get("reckless", false) else "Hunt started"]
		"crucifix_burn":
			return ["icons/eq_crucifix.png", "Crucifix prevented a hunt"]
		"attempt":
			match str(d.get("outcome", "")):
				"wrong":
					return [Defs.CREATURES.get(d.get("identity", ""), {}).get("token", "icons/ui_skull.png"), "Incorrect vanquishing attempted (%s)" % Defs.creature_name(d.get("identity", ""))]
				"incomplete_room", "incomplete_exposure":
					return ["icons/ui_quill.png", "Vanquishing attempt incomplete"]
			return []
		"npc_flee":
			return ["tokens/occupant_a.png", "The occupants fled the house"]
		"transform":
			return ["tokens/shapeshifter.png", "Shapeshifter transformed"]
		"expose":
			return ["icons/eq_hand_mirror.png", "Shapeshifter unmasked in the mirror"]
		"harbinger":
			return ["tokens/harbinger.png", "The Harbinger appeared"]
		"counter":
			return ["icons/%s.png" % ("eq_wooden_stake" if d.get("creature", "") == "vampire" else "eq_silver_stake"), "%s counterattacked!" % _who(d)]
		"escalate":
			return ["icons/ui_skull.png", "The full moon rose" if d.get("kind", "") == "moon" else "A blood-red mist filled the house"]
		"voodoo":
			return ["icons/eq_voodoo_doll.png", "%s stabbed the voodoo doll" % _who(d)]
		"npc_burn":
			return ["items/embers.png", "An occupant burst into flames"]
		"wrath":
			return ["tokens/lost_one.png", "%s touched the Lost One's keepsake" % _who(d)]
		"furnace":
			return ["items/embers.png", "Dragged to the furnace"]
		"vanquish":
			return [Defs.CREATURES.get(d.get("creature", ""), {}).get("token", "icons/ui_trophy.png"), "%s vanquished" % Defs.creature_name(d.get("creature", "")).capitalize()]
	return []

func _show_moment(icon: String, text: String) -> void:
	if not moments_enabled:
		return
	for m in _moments:
		if m["text"] == text:
			m["t"] = 0.0     # same moment again: keep the one already shown
			return
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.05, 0.86)
	sb.border_color = Color(Art.GOLD.r, Art.GOLD.g, Art.GOLD.b, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	sb.content_margin_right = 12
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	h.add_child(Art.icon_rect(icon, 30))
	var l := Art.label(text, 17, Color(0.95, 0.9, 0.78), Art.font_heading)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	_moment_box.add_child(p)
	p.modulate.a = 0.0
	p.create_tween().tween_property(p, "modulate:a", 1.0, 0.15)
	_moments.append({"node": p, "t": 0.0, "text": text})
	while _moments.size() > MOMENT_MAX:
		var old: Dictionary = _moments.pop_front()
		old["node"].queue_free()

func _tick_moments(delta: float) -> void:
	if _moment_box == null:
		return
	# Centred at the bottom of the replay area (the screen minus the camera offset).
	var vs := get_viewport().get_visible_rect().size
	var cx := vs.x * 0.5 - camera_offset.x * zoom
	_moment_box.position = Vector2(cx - 300.0, vs.y - 330.0)   # under the investigator, clear of the taunt line
	_moment_box.size = Vector2(600.0, 150.0)
	for m in _moments.duplicate():
		m["t"] += delta
		if m["t"] > MOMENT_HOLD:
			m["node"].modulate.a -= delta * 3.0
			if m["node"].modulate.a <= 0.0:
				_moments.erase(m)
				m["node"].queue_free()
