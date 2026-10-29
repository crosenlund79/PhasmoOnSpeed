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

func setup(p_house: String, p_seed: int, p_roster: Array, p_my_peer: int) -> void:
	house_id = p_house
	run_seed = p_seed
	roster = p_roster
	my_peer = p_my_peer

func _ready() -> void:
	map = HouseMap.from_data(Game.house(house_id))
	world = Node2D.new()
	add_child(world)
	view = HouseView.new()
	view.build(map, true, true)
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
	camera.offset = Vector2(145.0 / CAMERA_ZOOM, 0.0)
	player.add_child(camera)
	_apply_camera_limits(player.global_position)
	hud = preload("res://scripts/ui/hud.gd").new()
	add_child(hud)
	hud.setup(self)
	player.journal.discovered.connect(hud.on_discovered)
	Sfx.stop_loop("music", 0.8)
	Sfx.start_loop("ambience", "ambience_house", -6.0, 1.5)

func _apply_camera_limits(pos: Vector2) -> void:
	var b := map.floor_bounds(map.floor_at(pos))
	camera.limit_left = int(b.position.x) - 60
	camera.limit_top = int(b.position.y) - 60
	camera.limit_right = int(b.end.x) + 60 + int(300.0 / CAMERA_ZOOM)
	camera.limit_bottom = int(b.end.y) + 110

# --- HUD read interface (mirrors Run) ---------------------------------------------------

func is_harbinger() -> bool:
	return _harbinger

func sigils_lit() -> int:
	return _sigils_lit

func set_paused(_p: bool) -> void:
	pass   # the world never stops in a match

func restart() -> void:
	pass

# --- Local hunter --------------------------------------------------------------------------

func _process(delta: float) -> void:
	elapsed += delta
	fx.tick(delta)
	player.input.poll_local(player.input_enabled and not player.dead and state == "playing")
	player.room_id = map.room_at(player.global_position, player.room_id)
	_local_stairs()
	_send_acc += delta
	if _send_acc >= 1.0 / 60.0 and not player.dead:
		_send_acc = 0.0
		var flags := (1 if player.flashlight_on else 0) | (2 if player.sprinting else 0)
		Net.client_send_input(player.global_position, player.aim_angle, flags, player.input.held_mask(), player.input.counters())
	if player.input.just_pressed("flashlight"):
		player.flashlight_on = not player.flashlight_on
		Sfx.play("flashlight_click", -4.0)
	_update_puppets(delta)

func _local_stairs() -> void:
	var dest := map.stair_destination(player.global_position, player.get_meta("stair_lock", Vector2i(-99, -99)))
	if dest == Vector2.INF:
		if player.has_meta("stair_lock") and HouseMap.to_cell(player.global_position) != player.get_meta("stair_lock"):
			player.remove_meta("stair_lock")
		return
	player.global_position = dest
	player.set_meta("stair_lock", HouseMap.to_cell(dest))
	_apply_camera_limits(dest)
	camera.reset_smoothing()
	Sfx.play("footstep", -2.0, 0.7)
	view.set_basement_view(map.floor_at(dest) < 0)
	Sfx.set_loop_pitch("ambience", 0.78 if map.floor_at(dest) < 0 else 1.0)

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
			_npc_names[d["actor"]] = d["name"]
			if _npc_tags.has(d["actor"]):
				_npc_tags[d["actor"]].set_name(d["name"])
		"creature_meta":
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
		"correct":
			player.global_position = Vector2(d["x"], d["y"])
			_apply_camera_limits(player.global_position)
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
