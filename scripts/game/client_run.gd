class_name ClientRun
extends Node2D
## Multiplayer CLIENT view of a match. The host owns every decision; this node
## moves the local hunter (client-predicted, host-validated), sends its input,
## and mirrors the shared world from host snapshots and events. The local
## hunter's journal and HUD state arrive privately from the host.

const CAMERA_ZOOM := 1.55

var house_id := ""
var run_seed := 0
var roster: Array = []
var my_peer := 0
var multiplayer_match := true
var difficulty := "normal"
var blood_moon := false
var setup_info := {}
var map: HouseMap
var world: Node2D
var view: HouseView
var world_text: CanvasLayer
var camera: Camera2D
var hud: Node
var fx: WorldFx
var player: Player
var hunters: Array = []
var state := "playing"
var elapsed := 0.0
var threat := 0.0
var _sigils_lit := 0
var _harbinger := false
var _hunting := false
var _actors := {}            # actor id -> Node2D (puppets: Player / TokenSprite holder)
var _targets := {}           # actor id -> [pos, rot, alpha, token, flags]
var _npc_tags := {}          # actor id -> SpeechTag
var _npc_names := {}
var _creature_meta := {}     # actor id -> {disguise, size}
var _send_acc := 0.0
var _last_snapshot_t := 0.0

func setup(p_house: String, p_seed: int, p_roster: Array, p_my_peer: int, p_difficulty: String = "normal", p_blood_moon: bool = false, p_setup: Dictionary = {}) -> void:
	house_id = p_house
	difficulty = p_difficulty
	blood_moon = p_blood_moon
	setup_info = p_setup
	run_seed = p_seed
	roster = p_roster
	my_peer = p_my_peer

func _ready() -> void:
	map = HouseMap.from_data(Game.house(house_id))
	world = Node2D.new()
	add_child(world)
	view = HouseView.new()
	view.build(map, true, true)
	if Defs.rules(difficulty) == "nightmare":
		view.build_nightmare()
	if blood_moon:
		view.set_blood_moon(true)
	if Defs.hostile(difficulty) != "":
		view.set_hostile(Defs.hostile(difficulty))
		if Defs.hostile(difficulty) == "abyssal":
			view.ensure_abyss()
	world.add_child(view)
	world_text = CanvasLayer.new()
	world_text.layer = 1
	world_text.follow_viewport_enabled = true
	add_child(world_text)
	fx = WorldFx.new(view, world_text)
	var offsets := [Vector2(0, 0), Vector2(34, 0), Vector2(-34, 0), Vector2(0, 34)]
	for i in roster.size():
		var e: Dictionary = roster[i]
		var p := Player.new()
		p.run = self
		p.index = i
		p.peer_id = int(e["peer_id"])
		p.display_name = str(e["name"])
		p.actor_id = "player_%d" % (i + 1)
		p.position = HouseMap.cell_center(map.spawn_cell) + offsets[i % offsets.size()]
		if not map.walkable(HouseMap.to_cell(p.position)):
			p.position = HouseMap.cell_center(map.spawn_cell)
		p.is_local = p.peer_id == my_peer
		p.remote = false
		view.actor_layer.add_child(p)
		p.attach_name_label(world_text)
		if p.is_local:
			player = p
			p.equipment = EquipmentMirror.new()
		else:
			p.make_puppet()
		hunters.append(p)
		_actors[p.actor_id] = p
	camera = Camera2D.new()
	camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 9.0
	camera.offset = Vector2.ZERO
	player.add_child(camera)
	_apply_camera_limits(player.global_position)
	if Defs.rules(difficulty) == "nightmare":
		# Cosmetic and local to this machine, like everyone's own vermin.
		var critters := Critters.new()
		view.actor_layer.add_child(critters)
		critters.setup(self, run_seed)
	hud = preload("res://scripts/ui/hud.gd").new()
	add_child(hud)
	hud.setup(self)
	player.journal.discovered.connect(hud.on_discovered)
	if setup_info.get("ghost_marker", false):
		var gm := WorldFx.GhostMarker.new()
		gm.z_index = 50
		gm.source = func():
			for id in _actors:
				if str(id).begins_with("creature"):
					return [_actors[id].global_position, hud != null and hud._hunting]
			return []
		world_text.add_child(gm)
	if Defs.rules(difficulty) == "beginner":
		var guide := BeginnerGuide.new()
		guide.setup(self)
		add_child(guide)
	Sfx.stop_loop("music", 0.8)
	Sfx.start_loop("ambience", "ambience_house", -6.0, 1.5)

func _apply_camera_limits(pos: Vector2) -> void:
	var b := AbyssArena.rect().grow(420.0) if AbyssArena.contains(pos) else map.floor_bounds(map.floor_at(pos))
	# Room to scroll past the edges so the corner HUD panels never hide the house.
	camera.limit_left = int(b.position.x) - 60 - int(180.0 / CAMERA_ZOOM)
	camera.limit_top = int(b.position.y) - 60 - int(100.0 / CAMERA_ZOOM)
	camera.limit_right = int(b.end.x) + 60 + int(180.0 / CAMERA_ZOOM)
	camera.limit_bottom = int(b.end.y) + 60 + int(110.0 / CAMERA_ZOOM)

# --- HUD read interface (mirrors Run) ---------------------------------------------------

func is_harbinger() -> bool:
	return _harbinger

func sigils_lit() -> int:
	return _sigils_lit

func set_paused(p: bool) -> void:
	Net.request_pause(p)   # only the host can pause the match

## The host paused or resumed the match for everyone.
func apply_shared_pause(on: bool, who: String, remaining: float) -> void:
	get_tree().paused = on
	hud.show_shared_pause(on, who, remaining)

func restart() -> void:
	pass

# --- Local hunter --------------------------------------------------------------------------

func _process(delta: float) -> void:
	elapsed += delta
	fx.tick(delta)
	player.input.poll_local(player.input_enabled and not player.dead and state == "playing")
	player.room_id = map.room_at(player.global_position, player.room_id)
	_send_acc += delta
	if _send_acc >= 1.0 / 60.0 and not player.dead:
		_send_acc = 0.0
		var flags := (1 if player.flashlight_on else 0) | (2 if player.sprinting else 0)
		Net.client_send_input(player.global_position, player.aim_angle, flags, player.input.held_mask(), player.input.counters())
	if player.input.just_pressed("flashlight"):
		player.flashlight_on = not player.flashlight_on
		Sfx.play("flashlight_click", -4.0)
	_update_puppets(delta)

# --- Host → client ---------------------------------------------------------------------------

func apply_snapshot(t: float, p_threat: float, actors: Array, sigils: int, harb: bool, hunting: bool) -> void:
	if t < _last_snapshot_t:
		return
	_last_snapshot_t = t
	elapsed = t
	threat = p_threat
	_sigils_lit = sigils
	_harbinger = harb
	if hunting != _hunting:
		_hunting = hunting
		hud.set_hunting(hunting)
		if hunting:
			Sfx.start_loop("hunt", "hunt_loop", -2.0, 1.0)
		else:
			Sfx.stop_loop("hunt", 1.2)
	if harb:
		hud.refresh()
	for a in actors:
		var id: String = a[0]
		_targets[id] = [Vector2(a[1], a[2]), float(a[3]), float(a[4]), str(a[5]), int(a[6])]
		if not _actors.has(id):
			_spawn_puppet(id, str(a[5]))

func _spawn_puppet(id: String, token: String) -> void:
	var holder := Node2D.new()
	var size := 36.0
	if id.begins_with("creature"):
		size = 58.0 if id.ends_with("h") else 44.0
	var tk := TokenSprite.new(token, size)
	holder.add_child(tk)
	holder.set_meta("token", tk)
	if id.begins_with("creature"):
		var glow := PointLight2D.new()
		glow.texture = Art.tex("lights/soft.png")
		glow.texture_scale = 0.5
		glow.color = Art.SPECTRAL
		glow.energy = 0.0
		holder.add_child(glow)
		holder.set_meta("glow", glow)
		var meta: Dictionary = _creature_meta.get(id, {})
		holder.set_meta("tag", SpeechTag.new(world_text, meta.get("disguise", "")))
	elif id.begins_with("npc"):
		var tag := SpeechTag.new(world_text, _npc_names.get(id, ""))
		_npc_tags[id] = tag
		holder.set_meta("tag", tag)
	holder.modulate.a = 0.0
	view.actor_layer.add_child(holder)
	_actors[id] = holder

func _update_puppets(delta: float) -> void:
	var k := clampf(delta * 14.0, 0.0, 1.0)
	for id in _targets:
		var tgt: Array = _targets[id]
		var node: Node2D = _actors.get(id)
		if node == null or node == player:
			if node == player:
				_apply_self_flags(tgt[4])
			continue
		var pos: Vector2 = tgt[0]
		if node.position.distance_to(pos) > 140.0:
			node.position = pos   # teleport (stairs) or a fresh puppet
		else:
			node.position = node.position.lerp(pos, k)
		if node is Player:
			var h: Player = node
			h.aim_angle = lerp_angle(h.aim_angle, tgt[1], k)
			h.token.face_now(h.aim_angle)
			h.light_pivot.rotation = h.aim_angle
			var flags: int = tgt[4]
			h.flashlight_on = flags & 1 == 1
			h.flashlight.visible = h.flashlight_on and not h.dead
			h.uv_light.visible = flags & 2 == 2
			h.dead = flags & 4 == 4
			h.wounds = 2 if h.dead else (1 if flags & 16 == 16 else 0)
			h.modulate.a = 0.4 if h.dead else 1.0
			continue
		var tk: TokenSprite = node.get_meta("token")
		tk.set_token(tgt[3])
		tk.face_now(lerp_angle(tk.facing, tgt[1], k))
		node.modulate.a = lerpf(node.modulate.a, tgt[2], k)
		if node.has_meta("glow"):
			var silhouette: bool = tgt[4] & 1 == 1
			tk.sprite.modulate = Color(0.12, 0.11, 0.13) if silhouette else Color.WHITE
			node.get_meta("glow").energy = 0.0 if silhouette else node.modulate.a * 0.9
			# The same unnatural looks the host draws: a warping blot, a floor shadow.
			if tk.token_path == "tokens/shapeshifter_human.png" and tk.sprite.material == null:
				tk.sprite.material = Creature.glisten_material()
			if tk.token_path == "tokens/blightness.png" and tk.sprite.material == null:
				tk.sprite.material = WorldFx.distort_material(0.016, Color(0.78, 0.92, 0.55), 0.5)
			if tk.sprite.material:
				tk.sprite.material.set_shader_parameter("t", elapsed)
			if tk.token_path == "tokens/crawler.png":
				tk.sprite.modulate = Color(0.06, 0.04, 0.08)
				tk.scale = Vector2(1.35 + sin(elapsed * 7.0) * 0.1, 0.5)
		if node.has_meta("tag"):
			var tag: SpeechTag = node.get_meta("tag")
			var show_tag: bool = id.begins_with("npc") or tgt[4] & 2 == 2
			tag.set_visible(show_tag and node.modulate.a > 0.05)
			if show_tag:
				tag.update(node.position, node.modulate.a, delta)

func _apply_self_flags(_flags: int) -> void:
	pass   # the local hunter's own state comes from apply_hud / private messages

func apply_event(type: String, d: Dictionary) -> void:
	if fx.apply(type, d):
		return
	match type:
		"sfx":
			if d.has("x"):
				Sfx.play_at(d["name"], Vector2(d["x"], d["y"]), world, float(d.get("vol", 0.0)), float(d.get("pitch", 1.0)), float(d.get("max", 1400.0)))
			else:
				Sfx.play(d["name"], float(d.get("vol", 0.0)), float(d.get("pitch", 1.0)))
		"screen_shake":
			hud.shake(float(d["amount"]))
		"npc":
			# Names follow this player's own Safe Names setting (same identity everywhere).
			var nm: String = Occupants.display_name(int(d["name_id"])) if int(d.get("name_id", -1)) >= 0 else d["name"]
			_npc_names[d["actor"]] = nm
			if _npc_tags.has(d["actor"]):
				_npc_tags[d["actor"]].set_name(nm)
		"creature_meta":
			if int(d.get("disguise_id", -1)) >= 0:
				d["disguise"] = Occupants.display_name(int(d["disguise_id"]))
			_creature_meta[d["actor"]] = d
			if _actors.has(d["actor"]) and _actors[d["actor"]].has_meta("tag"):
				_actors[d["actor"]].get_meta("tag").set_name(d.get("disguise", ""))
		"say":
			var node = _actors.get(d["actor"])
			if node and node.has_meta("tag"):
				node.get_meta("tag").say(d["text"])
		"hunt_start":
			pass   # flicker/darkness/sounds arrive as their own events
		"vanquish":
			state = "ending"
		"left":
			if _actors.has(d["actor"]):
				_actors[d["actor"]].visible = false

## Messages for this hunter only.
func apply_private(kind: String, d: Dictionary) -> void:
	match kind:
		"toast":
			hud.toast(d["text"], d.get("icon", ""), d.get("quiet", false))
		"big":
			hud.big_message(d["title"], d["sub"], Color.html(d["color"]), float(d["dur"]))
		"sfx":
			Sfx.play(d["name"], float(d.get("vol", 0.0)), float(d.get("pitch", 1.0)), 0.05)
		"evidence":
			player.journal.record(d["id"], float(d["time"]), d["room"], d["room_name"])
		"void":
			player.journal.void_all()
			hud.refresh()
		"wound":
			hud.wound()
		"knockback":
			player.knockback(Vector2(d["x"], d["y"]))
		"drag":
			var pts: Array = d["pts"].map(func(e): return [Vector2(e[0], e[1]), float(e[2])])
			player.play_drag(pts)
			var tw := create_tween()
			tw.tween_interval(1.3)
			tw.tween_callback(func():
				var last: Vector2 = pts[-1][0]
				_apply_camera_limits(last)
				view.set_basement_view(map.floor_at(last) < 0)
				camera.reset_smoothing())
		"correct":
			var was := map.floor_at(player.global_position)
			var was_abyss := AbyssArena.contains(player.global_position)
			player.global_position = Vector2(d["x"], d["y"])
			_apply_camera_limits(player.global_position)
			if map.floor_at(player.global_position) != was or was_abyss != AbyssArena.contains(player.global_position):
				# Taken the stairs (the host moves us; walking onto steps does nothing).
				camera.reset_smoothing()
				view.set_basement_view(map.floor_at(player.global_position) < 0)
				Sfx.set_loop_pitch("ambience", 0.78 if map.floor_at(player.global_position) < 0 else 1.0)
		"dead":
			player.dead = true
			player.input_enabled = false
			player.wounds = 2
			player.token.modulate = Color(0.6, 0.1, 0.1)
			hud.begin_spectating()

func apply_hud(d: Dictionary) -> void:
	var eq: EquipmentMirror = player.equipment
	eq.apply(d)
	player.wounds = int(d["wounds"])
	player.invuln = float(d["invuln"])
	if player.suspect != str(d["suspect"]):
		player.suspect = str(d["suspect"])
		hud.refresh()
		hud.show_suspect_picker()
	player.uv_light.visible = d.get("uv", false) and not player.dead
	fx.set_orbs_visible(d.get("cam", false))
