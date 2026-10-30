class_name Run
extends Node2D
## One investigation: builds the house, spawns hunters, the entity and the
## occupants, owns the authoritative state (time, dread, attempts), resolves
## vanquishing, records the replay and produces the results.
##
## Solo play is a run with one local hunter. In competitive multiplayer this node
## runs only on the host; clients run ClientRun, which mirrors the world from
## the host's snapshots and events (see scripts/autoload/net.gd).

const GRACE_PERIOD := 40.0         # no ordinary hunts before this (seconds)
const THREAT_PER_SECOND := 0.22
const MEANINGFUL_INVESTIGATION := 4
const HARBINGER_AFTER_RECKLESS := 2
const HARBINGER_AFTER_WRONG := 3
const STRIKE_REACH := 62.0
const CAMERA_ZOOM := 1.55
const SNAPSHOT_HZ := 20.0
const PRIVATE_HZ := 10.0

var house_id := ""
var run_seed := 0
var creature_override := ""
var roster: Array = []             # [{peer_id, name}] — empty means solo
var multiplayer_match := false
var difficulty := "normal"         # "beginner", "normal" or "nightmare"
var rng := RandomNumberGenerator.new()
var map: HouseMap
var world: Node2D
var view: HouseView
var world_text: CanvasLayer
var camera: Camera2D
var hud: Node
var hunters: Array = []            # Array[Player]
var player: Player                 # the hunter controlled on this machine
var creature: Creature
var occupants: Array = []
var phenomena: Phenomena
var recorder: ReplayRecorder

var state := "playing"     # playing, ending
var elapsed := 0.0
var threat := 0.0
var original_creature := ""
var hunts_total := 0
var harbinger_summoned := false
var hunt_roll_t := 2.0
var forced_hunt_t := -1.0
var forced_hunt_reckless := false
var occupants_fled := false
var pickups: Array = []        # {kind, res, node, pos, label, hold}
var placed: Array = []         # {type, node, pos, room, burns, owner}
var sigils: Array = []         # {node, light, lit, room}
var vanquisher: Player = null
var cast: Array = []           # occupant identities for this run
var disguise := {}             # the shapeshifter's borrowed identity (never a real occupant's)
var first_finder := {}         # evidence id -> actor id of the first hunter to record it
var _uid := 0
var _garlic_warned_hunt := -1
var _end_t := 0.0
var _outcome := ""
var _paused := false
var _snap_acc := 0.0
var _priv_acc := 0.0
var _quip_t := 0.0
var critters: Critters = null
var _dread_noise_t := 12.0

## roster empty → solo. Otherwise [{peer_id, name}], the host first.
func setup(p_house: String, p_seed: int, p_override: String, p_roster: Array = [], p_difficulty: String = "normal") -> void:
	house_id = p_house
	difficulty = p_difficulty
	run_seed = p_seed if p_seed >= 0 else int(Time.get_unix_time_from_system() * 1000.0) % 2147483647
	creature_override = p_override
	roster = p_roster
	multiplayer_match = roster.size() > 1
	rng.seed = run_seed

func next_uid() -> int:
	_uid += 1
	return _uid

func _ready() -> void:
	map = HouseMap.from_data(Game.house(house_id))
	recorder = ReplayRecorder.new(house_id, run_seed)
	recorder.data["multiplayer"] = multiplayer_match
	recorder.data["difficulty"] = difficulty
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	view = HouseView.new()
	view.build(map, true, true)
	if difficulty == "nightmare":
		view.build_nightmare()
	world.add_child(view)
	world_text = CanvasLayer.new()
	world_text.layer = 1
	world_text.follow_viewport_enabled = true
	add_child(world_text)
	phenomena = Phenomena.new()
	phenomena.setup(self)
	world.add_child(phenomena)
	_spawn_hunters()
	cast = Occupants.cast_for(map, rng, int(map.data.get("npcs", 2)))
	disguise = Occupants.disguise_for(rng, cast)
	_choose_creature()
	_place_resources()
	_spawn_occupants()
	if difficulty == "nightmare":
		critters = Critters.new()
		view.actor_layer.add_child(critters)
		critters.setup(self, run_seed)
	hud = preload("res://scripts/ui/hud.gd").new()
	add_child(hud)
	hud.setup(self)
	player.journal.discovered.connect(hud.on_discovered)
	if difficulty == "beginner":
		var guide := BeginnerGuide.new()
		guide.setup(self)
		add_child(guide)
	Sfx.stop_loop("music", 0.8)
	Sfx.start_loop("ambience", "ambience_house", -6.0, 1.5)
	record_event("start", {"house": house_id})
	tell_all(map.name + " — something is here.", "icons/ui_house.png")
	if not multiplayer_match and difficulty != "beginner" and int(SaveData.data.get("runs_started", 0)) <= 3:
		# Brief onboarding for the first few runs; never blocks play.
		var tw := create_tween()
		tw.tween_interval(3.0)
		tw.tween_callback(func(): tell(player, "Evidence you observe is written in your journal automatically.", "icons/ui_quill.png", true))
		tw.tween_interval(3.0)
		tw.tween_callback(func(): tell(player, "Press H for controls. Two wounds and you perish.", "icons/ui_skull.png", true))

func _spawn_hunters() -> void:
	var entries := roster if not roster.is_empty() else [{"peer_id": 1, "name": SaveData.settings().get("player_name", "Investigator")}]
	var offsets := [Vector2(0, 0), Vector2(34, 0), Vector2(-34, 0), Vector2(0, 34)]
	var my_peer := Net.my_peer_id() if multiplayer_match else 1
	for i in entries.size():
		var e: Dictionary = entries[i]
		var p := Player.new()
		p.run = self
		p.index = i
		p.peer_id = int(e["peer_id"])
		p.display_name = str(e["name"])
		p.actor_id = "player_%d" % (i + 1)
		p.is_local = p.peer_id == my_peer
		p.remote = not p.is_local
		p.position = HouseMap.cell_center(map.spawn_cell) + offsets[i % offsets.size()]
		if not map.walkable(HouseMap.to_cell(p.position)):
			p.position = HouseMap.cell_center(map.spawn_cell)
		p.room_id = map.room_at(p.position)
		view.actor_layer.add_child(p)
		if p.remote:
			p.collision_layer = 0   # positions come from the owning client
		if multiplayer_match:
			p.attach_name_label(world_text)
		var eq := EquipmentController.new()
		add_child(eq)
		eq.setup(self, p)
		hunters.append(p)
		recorder.register_actor(p.actor_id, "player", "tokens/investigator.png", 40.0)
		recorder.data["actors"][p.actor_id]["name"] = p.display_name
		recorder.data["actors"][p.actor_id]["index"] = i
		if p.is_local:
			player = p
	camera = Camera2D.new()
	camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 9.0
	# Centre the investigator in the area left of the journal panel.
	camera.offset = Vector2.ZERO
	_apply_camera_limits(player.global_position)
	player.add_child(camera)

## Oppressive basement presentation for the local viewer (darker, deeper ambience).
func _on_local_floor(level: int) -> void:
	view.set_basement_view(level < 0)
	Sfx.set_loop_pitch("ambience", 0.78 if level < 0 else 1.0)

func _apply_camera_limits(pos: Vector2) -> void:
	var b := map.floor_bounds(map.floor_at(pos))
	# Room to scroll past the edges so the corner HUD panels never hide the house.
	camera.limit_left = int(b.position.x) - 60 - int(180.0 / CAMERA_ZOOM)
	camera.limit_top = int(b.position.y) - 60 - int(100.0 / CAMERA_ZOOM)
	camera.limit_right = int(b.end.x) + 60 + int(180.0 / CAMERA_ZOOM)
	camera.limit_bottom = int(b.end.y) + 60 + int(110.0 / CAMERA_ZOOM)

func _choose_creature() -> void:
	# Uniform choice from the run seed only — statistics never influence it.
	var type_id := creature_override
	if type_id == "" or not Defs.CREATURES.has(type_id):
		type_id = Defs.ORDINARY_CREATURES[rng.randi_range(0, Defs.ORDINARY_CREATURES.size() - 1)]
	original_creature = type_id
	var spawn_room := map.room_at(player.position)
	var options: Array = map.indoor_rooms().filter(func(r): return map.free_cells(r["id"]).size() >= 10 and r["id"] != spawn_room)
	var lair: Dictionary = options[rng.randi_range(0, options.size() - 1)]
	_spawn_creature(type_id, lair["id"])

func _spawn_creature(type_id: String, lair: String) -> void:
	creature = Creature.new()
	creature.setup(self, type_id, lair, HouseMap.cell_center(map.random_free_cell(lair, rng)))
	creature.hunt_started.connect(_on_hunt_started)
	creature.hunt_ended.connect(_on_hunt_ended)
	view.actor_layer.add_child(creature)
	phenomena.start_for(creature)
	recorder.register_actor(_creature_actor_id(), "creature", creature.current_token(), creature.token.diameter)
	record_event("creature", {"actor": _creature_actor_id(), "type": type_id, "lair": lair, "size": creature.token.diameter,
		"token": creature.current_token(), "disguise": disguise.get("name", "") if type_id == "shapeshifter" else ""})
	# Every entity gets a (possibly unused) disguise name so the network never hints at its type.
	record_event("creature_meta", {"actor": _creature_actor_id(), "disguise": disguise.get("name", ""), "size": creature.token.diameter})

func _creature_actor_id() -> String:
	return creature.actor_id + ("h" if creature.type_id == "harbinger" else "")

func _place_resources() -> void:
	var used := {}
	for res in Defs.RESOURCE_SPAWNS:
		var spec: Dictionary = Defs.RESOURCE_SPAWNS[res]
		var rooms: Array = []
		for k in spec["kinds"]:
			for r in map.rooms_of_kind(k):
				if not rooms.has(r["id"]):
					rooms.append(r["id"])
		if rooms.is_empty():
			for r in map.indoor_rooms():
				rooms.append(r["id"])
		# Shuffle deterministically, then spread multiple pieces over different rooms.
		for i in range(rooms.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = rooms[i]
			rooms[i] = rooms[j]
			rooms[j] = tmp
		for i in int(spec["count"]):
			var rid: String = rooms[i % rooms.size()]
			var cell := map.random_free_cell(rid, rng, used)
			used[cell] = true
			var pos := HouseMap.cell_center(cell)
			var node := _item_sprite(spec["sprite"], pos, 26.0)
			pickups.append({"kind": "resource", "res": res, "node": node, "pos": pos,
				"label": "Pick up " + Defs.EQUIPMENT[res]["name"], "hold": 0.0})

func _item_sprite(path: String, pos: Vector2, size: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Art.tex(path)
	s.position = pos
	var k := size / maxf(1.0, s.texture.get_size().x)
	s.scale = Vector2(k, k)
	s.name = "item_%d" % next_uid()
	view.decal_layer.add_child(s)
	record_event("decal", {"id": s.name, "sprite": path, "x": pos.x, "y": pos.y, "rot": 0.0, "size": size})
	return s

func _remove_sprite(s: Node) -> void:
	if is_instance_valid(s):
		record_event("decal_remove", {"id": s.name})
		s.queue_free()

func _spawn_occupants() -> void:
	var rooms: Array = map.indoor_rooms().filter(func(r): return r["id"] != creature.lair_room)
	for i in cast.size():
		var o := Occupant.new()
		var r: Dictionary = rooms[rng.randi_range(0, rooms.size() - 1)]
		o.setup(self, "npc_%d" % (i + 1), cast[i], HouseMap.cell_center(map.random_free_cell(r["id"], rng)))
		o.fear = 2.0 if difficulty == "nightmare" else 1.0
		view.actor_layer.add_child(o)
		occupants.append(o)
		recorder.register_actor(o.actor_id, "npc", o.token_path, 36.0)
		recorder.data["actors"][o.actor_id]["name"] = o.person["name"]
		record_event("npc", {"actor": o.actor_id, "name": o.person["name"], "token": o.token_path})

# --- Queries used by actors ---------------------------------------------------------

func living_hunters() -> Array:
	return hunters.filter(func(h): return not h.dead)

func nearest_hunter(pos: Vector2) -> Player:
	var best: Player = null
	var bd := INF
	for h: Player in hunters:
		if h.dead:
			continue
		var d := pos.distance_to(h.global_position)
		if d < bd:
			bd = d
			best = h
	return best if best else player

func hunter_by_peer(peer: int) -> Player:
	for h: Player in hunters:
		if h.peer_id == peer:
			return h
	return null

func is_harbinger() -> bool:
	return creature != null and creature.type_id == "harbinger"

func sigils_lit() -> int:
	return sigils.filter(func(s): return s["lit"]).size()

func can_restart() -> bool:
	return not multiplayer_match

# --- Main loop -----------------------------------------------------------------------

func _process(delta: float) -> void:
	if state == "ending":
		_end_t -= delta
		_record(delta)
		if _end_t <= 0.0 and _outcome != "":
			_finish()
		return
	if _paused:
		return
	elapsed += delta
	_quip_t = maxf(0.0, _quip_t - delta)
	player.input.poll_local(player.input_enabled and not player.dead)
	for h: Player in hunters:
		var before := h.global_position
		h.room_id = map.room_at(h.global_position, h.room_id)
		_check_stairs(h)
		if h.equipment:
			h.equipment.process_input(delta)
			h.equipment.update_tools(delta)
		h.input.consume()
		if h.is_local and h.global_position.distance_to(before) > 90.0:
			camera.reset_smoothing()
	_update_threat(delta)
	_update_defences(delta)
	if difficulty == "nightmare":
		_nightmare_noises(delta)
	_record(delta)
	if multiplayer_match:
		_net_tick(delta)

## Nightmare: strange noises somewhere in the house every few seconds. Heard by
## everyone (and by the occupants, who do not take it well). Never evidence.
const NIGHTMARE_NOISES := [["nm_knock", -8.0, 1.0], ["nm_drag", -8.0, 1.0], ["door_creak", -10.0, 0.8],
	["footstep", -6.0, 0.6], ["nm_knock", -12.0, 0.75], ["scream_2", -24.0, 0.7]]

func _nightmare_noises(delta: float) -> void:
	_dread_noise_t -= delta
	if _dread_noise_t > 0.0:
		return
	_dread_noise_t = rng.randf_range(7.0, 16.0)
	var who: Player = hunters[rng.randi_range(0, hunters.size() - 1)]
	var rooms: Array = map.indoor_rooms()
	var r: Dictionary = rooms[rng.randi_range(0, rooms.size() - 1)]
	var pos := HouseMap.cell_center(map.random_free_cell(r["id"], rng))
	if pos.distance_to(who.global_position) < 200.0:
		pos = who.global_position + (pos - who.global_position).normalized() * 260.0
	var n: Array = NIGHTMARE_NOISES[rng.randi_range(0, NIGHTMARE_NOISES.size() - 1)]
	sound_at(n[0], pos, n[1], n[2] * rng.randf_range(0.9, 1.1), 1100.0)
	for o in occupants:
		o.react(pos)

func _record(delta: float) -> void:
	recorder.tick(elapsed, delta, _actor_states())

## [pos, rot, alpha, token, flags] per actor — shared by replay and network snapshots.
func _actor_states() -> Dictionary:
	var actors := {}
	for h: Player in hunters:
		var flags := (1 if h.flashlight_on else 0) | (2 if h.uv_light.visible else 0) | (4 if h.dead else 0) | (8 if h.invuln > 0.0 else 0) | (16 if h.wounds >= 1 else 0)
		actors[h.actor_id] = [h.global_position, h.aim_angle, 0.35 if h.dead else 1.0, "tokens/investigator.png", flags]
	if creature:
		var cf := (1 if creature.token.sprite.modulate.r < 0.5 else 0) | (2 if creature.disguised() else 0)   # silhouette, disguise tag
		actors[_creature_actor_id()] = [creature.position, creature.token.facing, creature.modulate.a, creature.current_token(), cf]
	for o in occupants:
		actors[o.actor_id] = [o.position, o.token.facing, o.modulate.a, o.token_path, 0]
	return actors

func _update_threat(delta: float) -> void:
	# Beginner: dread builds more slowly and the first hunt comes much later.
	threat = minf(100.0, threat + THREAT_PER_SECOND * delta * (0.6 if difficulty == "beginner" else 1.0))
	if creature == null or creature.state != "roam" or creature.cooldown_t > 0.0:
		return
	if forced_hunt_t > 0.0:
		forced_hunt_t -= delta
		if forced_hunt_t <= 0.0:
			trigger_hunt(forced_hunt_reckless)
		return
	if not is_harbinger() and elapsed < GRACE_PERIOD * (2.0 if difficulty == "beginner" else 1.0):
		return
	hunt_roll_t -= delta
	if hunt_roll_t > 0.0:
		return
	hunt_roll_t = 2.0
	var threshold: float = creature.def["hunt_threshold"]
	if threat < threshold:
		return
	var p := 0.6 if is_harbinger() else 0.22 + (threat - threshold) / 120.0
	if rng.randf() < p:
		trigger_hunt(false)

func _update_defences(delta: float) -> void:
	if creature == null or not creature.is_hunting():
		return
	if creature.is_ghost_like():
		for it in placed:
			if it["type"] == "salt" and creature.position.distance_to(it["pos"]) < 30.0:
				creature.slowed_t = 2.0
	if creature.type_id == "vampire":
		for h: Player in living_hunters():
			if h.has_resource("garlic") and creature.position.distance_to(h.global_position) < 105.0:
				creature.weakened_t = 1.5
				var away := (creature.position - h.global_position).normalized()
				creature.position += away * 90.0 * delta
				if _garlic_warned_hunt != creature.hunt_count:
					_garlic_warned_hunt = creature.hunt_count
					tell(h, "It recoils from the garlic!", "icons/eq_garlic.png")
					sound_at("vampire_hiss", creature.position)

func add_threat(amount: float, reason: String) -> void:
	threat = clampf(threat + amount, 0.0, 100.0)
	record_event("threat", {"amount": amount, "reason": reason})

func add_investigation(p: Player, points: int, reason: String) -> void:
	p.investigation += points
	record_event("investigate", {"actor": p.actor_id, "points": points, "reason": reason})

func meaningful_investigation(p: Player) -> bool:
	return p.investigation >= MEANINGFUL_INVESTIGATION or not p.journal.active_entries().is_empty()

func record_event(type: String, payload: Dictionary = {}) -> void:
	recorder.event(elapsed, type, payload)
	if multiplayer_match:
		Net.host_world_event(type, payload)

# --- Feedback channels (local HUD, or the owning client over the network) ------------

func tell(p: Player, text: String, icon: String = "", quiet: bool = false) -> void:
	if p == null:
		return
	if p.is_local:
		hud.toast(text, icon, quiet)
	elif multiplayer_match:
		Net.host_private(p.peer_id, "toast", {"text": text, "icon": icon, "quiet": quiet})

func tell_all(text: String, icon: String = "", quiet: bool = false) -> void:
	for h: Player in hunters:
		tell(h, text, icon, quiet)

func announce_to(p: Player, title: String, sub: String, color: Color, dur: float) -> void:
	if p.is_local:
		hud.big_message(title, sub, color, dur)
	elif multiplayer_match:
		Net.host_private(p.peer_id, "big", {"title": title, "sub": sub, "color": color.to_html(), "dur": dur})

func announce(title: String, sub: String, color: Color, dur: float) -> void:
	for h: Player in hunters:
		announce_to(h, title, sub, color, dur)

## Positional world sound, heard by every hunter (and kept out of the replay).
func sound_at(name: String, pos: Vector2, vol: float = 0.0, pitch: float = 1.0, max_distance: float = 1400.0) -> void:
	Sfx.play_at(name, pos, world, vol, pitch, max_distance)
	if multiplayer_match:
		Net.host_world_event("sfx", {"name": name, "x": pos.x, "y": pos.y, "vol": vol, "pitch": pitch, "max": max_distance})

func sound_all(name: String, vol: float = 0.0, pitch: float = 1.0) -> void:
	Sfx.play(name, vol, pitch)
	if multiplayer_match:
		Net.host_world_event("sfx", {"name": name, "vol": vol, "pitch": pitch})

func sound_to(p: Player, name: String, vol: float = 0.0, pitch: float = 1.0) -> void:
	if p.is_local:
		Sfx.play(name, vol, pitch, 0.05)
	elif multiplayer_match:
		Net.host_private(p.peer_id, "sfx", {"name": name, "vol": vol, "pitch": pitch})

func fx_flicker(duration: float, strength: float) -> void:
	view.flicker(duration, strength)
	record_event("flicker", {"dur": duration, "strength": strength})

func fx_darkness(c: Color, t: float) -> void:
	view.set_darkness(c, t)
	record_event("darkness", {"color": c.to_html(), "t": t})

func fx_shake(amount: float) -> void:
	hud.shake(amount)
	if multiplayer_match:
		Net.host_world_event("screen_shake", {"amount": amount})

# --- Evidence ------------------------------------------------------------------------

## Registers a genuine discovery by hunter p. Only the current entity's phenomena call this.
func discover(p: Player, evidence_id: String, room_id: String) -> void:
	if state != "playing" or p == null or p.dead or room_id == "" or not (evidence_id in phenomena.evidence):
		return
	if p.journal.has(evidence_id):
		return
	if p.journal.record(evidence_id, elapsed, room_id, map.room_name(room_id)):
		sound_to(p, "pencil_scribble", 0.0)
		add_threat(4.0 / hunters.size(), "evidence")
		add_investigation(p, 3, "evidence")
		var first := not first_finder.has(evidence_id)
		if first:
			first_finder[evidence_id] = p.actor_id
			p.first_finds += 1
		# Recorded for replay/results only; never broadcast to rivals.
		recorder.event(elapsed, "evidence", {"actor": p.actor_id, "id": evidence_id, "room": room_id, "room_name": map.room_name(room_id), "first": first})
		if not p.is_local and multiplayer_match:
			Net.host_private(p.peer_id, "evidence", {"id": evidence_id, "time": elapsed, "room": room_id, "room_name": map.room_name(room_id)})

func placed_books() -> Array:
	var out: Array = []
	for it in placed:
		if it["type"] == "ghost_book":
			out.append(it["node"])
	return out

func on_book_written(book: Sprite2D) -> void:
	book.texture = Art.tex("items/ghost_book_written.png")
	for it in placed:
		if it["node"] == book and it["owner"]:
			it["owner"].set_meta("book_written", true)
	record_event("decal_swap", {"id": book.name, "sprite": "items/ghost_book_written.png"})

func vampire_bite() -> void:
	var candidates: Array = occupants.filter(func(o): return o.state != "flee" and o.state != "gone" and not o.bitten)
	if candidates.is_empty():
		return
	var o: Occupant = candidates[rng.randi_range(0, candidates.size() - 1)]
	o.bite()
	record_event("bite", {"actor": o.actor_id})

func on_transform(c: Creature, f: String) -> void:
	record_event("transform", {"form": f})

func on_occupant_gone(o: Occupant) -> void:
	record_event("npc_gone", {"actor": o.actor_id})

## A bang, rattle or shriek: nearby occupants react according to personality.
func disturbance(pos: Vector2) -> void:
	for o in occupants:
		o.react(pos)

func on_say(actor_id: String, text: String) -> void:
	if multiplayer_match:
		Net.host_world_event("say", {"actor": actor_id, "text": text})

func shake_furniture_near(pos: Vector2) -> void:
	var best: Dictionary = {}
	var bd := 140.0
	for f in map.furniture:
		if f["def"].get("under", false) or not f.has("sprite"):
			continue
		var d: float = (f["rect"] as Rect2).get_center().distance_to(pos)
		if d < bd:
			bd = d
			best = f
	if best.is_empty():
		return
	view.shake_furniture(best["index"])
	record_event("shake", {"index": best["index"]})

# --- Floors --------------------------------------------------------------------------

## Stepping onto a staircase cell takes a hunter to the linked floor.
func _check_stairs(h: Player) -> void:
	if h.remote or h.dead:
		return
	if h.velocity.length() < 20.0:
		return
	var dest := map.stair_destination(h.global_position, h.get_meta("stair_lock", Vector2i(-99, -99)), h.velocity)
	if dest == Vector2.INF:
		if h.has_meta("stair_lock") and HouseMap.to_cell(h.global_position) != h.get_meta("stair_lock"):
			h.remove_meta("stair_lock")
		return
	h.global_position = dest
	h.set_meta("stair_lock", HouseMap.to_cell(dest))
	h.room_id = map.room_at(dest)
	if h == player:
		_apply_camera_limits(dest)
		camera.reset_smoothing()
		_on_local_floor(map.floor_at(dest))
	sound_to(h, "footstep", -2.0, 0.7)
	tell(h, map.room_name(h.room_id), "icons/ui_house.png", true)
	record_event("floor", {"actor": h.actor_id, "floor": map.floor_at(dest)})

# --- Hunts ---------------------------------------------------------------------------

func trigger_hunt(reckless: bool) -> void:
	if creature == null or creature.state != "roam" or state != "playing":
		return
	forced_hunt_t = -1.0
	# Crucifixes stop eligible ghost hunts before they begin.
	if creature.def["kind"] == "ghost":
		for it in placed:
			if it["type"] == "crucifix" and it["burns"] > 0 and creature.position.distance_to(it["pos"]) < 150.0:
				it["burns"] -= 1
				if it["owner"]:
					it["owner"].crucifix_burns = it["burns"]
				sound_at("crucifix_burn", it["pos"], 2.0)
				tell_all("A crucifix flares and scorches — a hunt was prevented.", "icons/eq_crucifix.png")
				record_event("crucifix_burn", {"x": it["pos"].x, "y": it["pos"].y})
				if it["burns"] <= 0:
					it["node"].modulate = Color(0.35, 0.3, 0.3)
				creature.cooldown_t = 20.0
				add_threat(-15.0, "crucifix")
				return
	creature.begin_hunt(_fair_hunt_start(), reckless)

## Chooses where a hunt begins so that it is never unavoidable for any hunter.
func _fair_hunt_start() -> Vector2:
	var alive := living_hunters()
	var cpos := creature.position
	var vampire := creature.type_id == "vampire"
	var victim: Player = nearest_hunter(cpos)
	var min_d := INF
	for h: Player in alive:
		min_d = minf(min_d, cpos.distance_to(h.global_position))
	if not vampire and min_d >= 300.0:
		return cpos
	var best := cpos
	var best_score := -INF
	var rooms := map.indoor_rooms()
	for i in 64:
		var r: Dictionary = rooms[rng.randi_range(0, rooms.size() - 1)]
		var cells := map.free_cells(r["id"])
		if cells.is_empty():
			continue
		var p := HouseMap.cell_center(cells[rng.randi_range(0, cells.size() - 1)])
		var nearest := INF
		for h: Player in alive:
			nearest = minf(nearest, p.distance_to(h.global_position))
		if nearest < 300.0:
			continue
		var d := p.distance_to(victim.global_position)
		if d > 620.0:
			continue
		var score := -absf(d - 380.0)
		if vampire:
			# Ambush: from behind the investigator, out of the flashlight.
			var behind := absf(angle_difference(victim.aim_angle, (p - victim.global_position).angle()))
			score += behind * 120.0
			if phenomena.is_lit(p, victim):
				score -= 300.0
		if score > best_score:
			best_score = score
			best = p
	return best

func _on_hunt_started(c: Creature) -> void:
	hunts_total += 1
	fx_flicker(Creature.WARN_TIME + 1.0, 1.0)
	fx_darkness(HouseView.DARKNESS_HUNT, 1.2)
	sound_all("hunt_start", 0.0)
	match c.type_id:
		"werewolf": sound_at("werewolf_howl", c.position, 2.0)
		"vampire": sound_at("vampire_hiss", c.position, 0.0)
		"poltergeist", "shade": sound_at("ghost_wail", c.position, -2.0)
	Sfx.start_loop("hunt", "hunt_loop", -2.0, 1.0)
	hud.set_hunting(true)
	tell_all("It is hunting! Break its line of sight.", "icons/ui_skull.png")
	record_event("hunt_start", {"reckless": c.hunt_reckless})
	if not occupants_fled:
		_occupants_flee()

func _on_hunt_ended(c: Creature, hit: bool) -> void:
	fx_darkness(HouseView.DARKNESS_HARBINGER if harbinger_summoned else HouseView.DARKNESS, 1.5)
	Sfx.stop_loop("hunt", 1.2)
	hud.set_hunting(false)
	for h: Player in living_hunters():
		if h.get_meta("hit_this_hunt", false):
			h.set_meta("hit_this_hunt", false)
			continue
		if not c.hunt_reckless and c.type_id != "harbinger":
			h.clean_hunts += 1
		tell(h, "The hunt is over… for now.", "icons/ui_clock.png", true)
	threat = maxf(0.0, threat - 25.0)
	record_event("hunt_end", {"hit": hit})

func _occupants_flee() -> void:
	occupants_fled = true
	for o in occupants:
		o.flee()
	record_event("npc_flee", {})

func on_creature_contact(c: Creature, p: Player) -> void:
	if p.invuln > 0.0 or p.dead or state != "playing":
		return
	if p.blessed > 0.0 and c.is_ghost_like():
		c.stun(4.0 if c.type_id != "harbinger" else 2.5)
		p.invuln = 1.0
		tell(p, "The blessing holds — it recoils from you!", "icons/eq_holy_water.png")
		sound_at("crucifix_burn", p.global_position)
		record_event("blessing_repel", {"actor": p.actor_id})
		return
	p.wounds += 1
	p.set_meta("hit_this_hunt", true)
	c.hunt_hit = true
	record_event("attack", {"actor": p.actor_id, "wounds": p.wounds})
	if p.wounds >= 2:
		_hunter_dies(p, c)
		return
	p.invuln = Player.INVULN_AFTER_HIT * (1.6 if difficulty == "beginner" else 1.0)
	sound_to(p, "player_hurt", 0.0)
	if p.is_local:
		hud.wound()
	elif multiplayer_match:
		Net.host_private(p.peer_id, "wound", {})
	tell(p, "You are wounded. Once more and you are finished.", "icons/ui_heart_wounded.png")
	_maybe_quip_shove_victim(p)
	c.end_hunt()

# --- Shoving (competitive) -------------------------------------------------------------

func shove(p: Player) -> void:
	if not multiplayer_match or p.dead or p.shove_cd > 0.0 or state != "playing":
		return
	var best: Player = null
	var bd := Player.SHOVE_RANGE
	for h: Player in living_hunters():
		if h == p:
			continue
		var to: Vector2 = h.global_position - p.global_position
		if to.length() < bd and (absf(angle_difference(p.aim_angle, to.angle())) < 1.05 or to.length() < 22.0):
			bd = to.length()
			best = h
	p.shove_cd = 1.0   # whiff cooldown; a landed shove sets the full cooldown
	if best == null:
		return
	p.shove_cd = Player.SHOVE_COOLDOWN
	if best.shove_immune > 0.0:
		tell(p, "%s is still steadying themselves." % best.display_name, "icons/ui_skull.png", true)
		return
	var dir := (best.global_position - p.global_position).normalized()
	if dir == Vector2.ZERO:
		dir = p.facing_vector()
	var impulse := dir * 520.0
	best.shove_immune = Player.SHOVE_IMMUNITY
	best.set_meta("shoved_by", p.actor_id)
	best.set_meta("shoved_at", elapsed)
	p.shoves_given += 1
	best.shoves_taken += 1
	if best.is_local:
		best.knockback(impulse)
	else:
		Net.host_private(best.peer_id, "knockback", {"x": impulse.x, "y": impulse.y})
	sound_at("stake_strike", best.global_position, -6.0, 1.4)
	tell(best, "%s shoved you!" % p.display_name, "icons/ui_skull.png")
	record_event("shove", {"from": p.actor_id, "to": best.actor_id, "x": best.global_position.x, "y": best.global_position.y})

const SHOVE_QUIPS := [
	"An admirable display of teamwork. For someone else.",
	"Your colleague appreciates the sudden introduction to the creature.",
	"Survival of the fittest. Friendship of the shortest.",
]

func _maybe_quip_shove_victim(p: Player) -> void:
	# A wound shortly after being shoved earns one dry remark — rarely.
	if not p.has_meta("shoved_at") or elapsed - float(p.get_meta("shoved_at")) > 4.0 or _quip_t > 0.0:
		return
	_quip_t = 45.0
	tell_all(SHOVE_QUIPS[rng.randi_range(0, SHOVE_QUIPS.size() - 1)], "icons/ui_skull.png")
	record_event("shove_consequence", {"victim": p.actor_id, "by": p.get_meta("shoved_by")})

# --- Defences & placement ---------------------------------------------------------------

func place_item(p: Player, type: String, at: Vector2) -> bool:
	var pos := at if map.walkable(HouseMap.to_cell(at)) else p.global_position
	var written: bool = type == "ghost_book" and p.get_meta("book_written", false)
	var sprite_path: String = {"ghost_book": "items/ghost_book_written.png" if written else "items/ghost_book.png",
		"salt": "items/salt_pile.png", "crucifix": "items/crucifix_placed.png"}[type]
	var node := _item_sprite(sprite_path, pos, 28.0 if type != "salt" else 30.0)
	if written:
		phenomena.written_books[node] = true
	var room := map.room_at(pos, p.room_id)
	placed.append({"type": type, "node": node, "pos": pos, "room": room, "burns": p.crucifix_burns if type == "crucifix" else 0, "owner": p})
	sound_at("place_item", pos, -4.0)
	add_investigation(p, 1, "place:" + type)
	if room == (creature.lair_room if creature else ""):
		add_threat(1.0, "place_in_lair")
	return true

func splash_holy_water(p: Player) -> void:
	sound_at("holy_water_splash", p.global_position)
	p.blessed = 3.0
	record_event("holy_water", {"actor": p.actor_id, "x": p.global_position.x, "y": p.global_position.y})
	var c := creature
	if c == null or c.state == "banished":
		return
	var to := c.position - p.global_position
	if to.length() < 125.0 and absf(angle_difference(p.aim_angle, to.angle())) < 0.9:
		if c.is_ghost_like():
			c.stun(6.0 if c.type_id != "harbinger" else 3.0)
			sound_at("crucifix_burn", c.position, 2.0)
			if c.is_visible_now() or c.is_hunting():
				tell(p, "The holy water hisses — it recoils!", "icons/eq_holy_water.png")
			record_event("stun", {"actor": p.actor_id})
		elif c.is_visible_now():
			tell(p, "It doesn't even flinch.", "icons/eq_holy_water.png")

func strike(p: Player, item: String) -> void:
	sound_at("stake_strike", p.global_position, -2.0, rng.randf_range(0.9, 1.1))
	record_event("strike", {"actor": p.actor_id, "item": item})
	var identity: String = {"wooden_stake": "vampire", "silver_stake": "werewolf", "iron_nails": "shapeshifter"}[item]
	if item == "wooden_stake" and not p.has_resource("garlic"):
		tell(p, "You'll need garlic to weaken it before the stake can bite.", "icons/eq_garlic.png", true)
		return
	var c := creature
	if c == null or c.state == "banished":
		return
	var to := c.position - p.global_position
	var reach := to.length() < STRIKE_REACH and (absf(angle_difference(p.aim_angle, to.angle())) < 1.2 or to.length() < 30.0)
	if not reach:
		tell(p, "You strike at empty air.", Defs.EQUIPMENT[item]["icon"], true)
		return
	attempt_vanquish(p, identity, item)

## Choosing a suspect is never an attempt. Every entity is selectable.
func cycle_suspect(p: Player, dir: int = 1) -> void:
	if is_harbinger():
		return
	var options := [""] + Defs.ORDINARY_CREATURES
	p.suspect = options[(options.find(p.suspect) + dir + options.size()) % options.size()]
	sound_to(p, "ui_click", -8.0)
	record_event("suspect", {"actor": p.actor_id, "id": p.suspect})
	if p.is_local:
		hud.refresh()
		hud.show_suspect_picker()

# --- Rites ---------------------------------------------------------------------------

func _room_has(type: String, room_id: String) -> bool:
	for it in placed:
		if it["type"] == type and it["room"] == room_id:
			return true
	return false

func _rite_requirement_met(p: Player) -> bool:
	match p.suspect:
		"shade": return _room_has("salt", p.room_id)
		"poltergeist": return _room_has("ghost_book", p.room_id)
	return false

func rite_prompt(p: Player) -> String:
	if creature == null:
		return ""
	if is_harbinger():
		if creature.state == "bound" and p.global_position.distance_to(creature.position) < 175.0:
			return "[V] Hold to perform the Final Rite"
		return ""
	if Defs.is_ghost(p.suspect) and _rite_requirement_met(p):
		return "[V] Hold: " + Defs.CREATURES[p.suspect]["rite_name"]
	return ""

func rite_hold_time() -> float:
	return 2.5 if is_harbinger() else 1.5

func can_begin_rite(p: Player) -> bool:
	if is_harbinger():
		if creature.state != "bound":
			tell(p, "The Harbinger cannot be banished until all three sigil candles burn.", "items/sigil_candle_lit.png", true)
			return false
		if p.global_position.distance_to(creature.position) >= 175.0:
			tell(p, "Stand beside the bound Harbinger to perform the Final Rite.", "icons/ui_skull.png", true)
			return false
		return true
	if p.suspect == "":
		tell(p, "Choose the entity you suspect first (Tab).", "icons/ui_quill.png", true)
		return false
	if not Defs.is_ghost(p.suspect):
		tell(p, "No rite banishes a %s. %s" % [Defs.creature_name(p.suspect), Defs.vanquish_summary(p.suspect)], "icons/ui_quill.png", true)
		return false
	if not _rite_requirement_met(p):
		if p.suspect == "shade":
			tell(p, "The Rite of Stillness needs salt poured in this room.", "icons/eq_salt.png", true)
		else:
			tell(p, "The Rite of Binding needs the Ghost Writing Book laid in this room.", "icons/eq_ghost_book.png", true)
		return false
	return true

func perform_rite(p: Player) -> void:
	if not can_begin_rite(p):
		return
	if is_harbinger():
		record_event("final_rite", {"actor": p.actor_id})
		_victory(p)
		return
	attempt_vanquish(p, p.suspect, "rite")

## Resolves a genuine vanquishing attempt (identity guess + method) by hunter p.
func attempt_vanquish(p: Player, identity: String, method: String) -> void:
	if state != "playing" or p.dead:
		return
	var truth := creature.type_id
	var informed := meaningful_investigation(p)
	var outcome := "wrong"
	if identity == truth:
		outcome = "success"
		if method == "rite" and p.room_id != creature.lair_room and p.global_position.distance_to(creature.position) > 140.0:
			outcome = "incomplete_room"
		elif truth == "shapeshifter" and creature.exposed_t <= 0.0:
			outcome = "incomplete_exposure"
	p.attempts.append({"time": elapsed, "identity": identity, "method": method, "outcome": outcome, "informed": informed, "room": p.room_id})
	record_event("attempt", {"actor": p.actor_id, "identity": identity, "method": method, "outcome": outcome, "informed": informed})
	match outcome:
		"success":
			_victory(p)
		"incomplete_room":
			p.incomplete_attempts += 1
			add_threat(10.0, "incomplete")
			sound_at("ghost_wail", p.global_position, -6.0)
			tell(p, "The rite echoes through empty rooms. It does not dwell here.", "icons/ui_quill.png")
		"incomplete_exposure":
			p.incomplete_attempts += 1
			add_threat(10.0, "incomplete")
			sound_at("shapeshift", creature.position, 0.0)
			tell(p, "The iron slides off borrowed skin. Expose its true form first.", "icons/eq_iron_nails.png")
		"wrong":
			p.wrong_attempts += 1
			if informed:
				add_threat(20.0, "wrong_attempt")
				sound_all("reckless_reaction", -6.0)
				fx_flicker(1.5, 0.7)
				tell(p, "Wrong. Something in the house is angered.", "icons/ui_skull.png")
			else:
				_severe_reaction(p)
			if not harbinger_summoned and (_total("reckless_attempts") >= HARBINGER_AFTER_RECKLESS or _total("wrong_attempts") >= HARBINGER_AFTER_WRONG):
				_summon_harbinger()

func _total(field: String) -> int:
	var n := 0
	for h: Player in hunters:
		n += int(h.get(field))
	return n

func _severe_reaction(p: Player) -> void:
	p.reckless_attempts += 1
	add_threat(40.0, "reckless")
	sound_all("reckless_reaction", 2.0)
	fx_flicker(3.5, 1.0)
	fx_shake(0.6)
	announce("THE HOUSE NOTICED", ("Something inhabiting this place saw what you did." if not multiplayer_match else "Something saw what %s did." % p.display_name) + " The madness deepens.", Art.BLOOD, 3.2)
	record_event("reckless", {"actor": p.actor_id, "count": p.reckless_attempts})
	if not occupants_fled:
		_occupants_flee()
	if creature.state == "roam":
		forced_hunt_t = 5.0
		forced_hunt_reckless = true
		creature.cooldown_t = 0.0

func _summon_harbinger() -> void:
	harbinger_summoned = true
	var old := creature
	record_event("harbinger", {"replaced": old.type_id})
	old.banish()
	old.set_process(false)
	var tw := create_tween()
	tw.tween_interval(1.7)
	tw.tween_callback(old.queue_free)
	phenomena.clear()
	for h: Player in hunters:
		h.journal.void_all()
		h.suspect = ""
		if not h.is_local and multiplayer_match:
			Net.host_private(h.peer_id, "void", {})
	forced_hunt_t = -1.0
	Sfx.stop_loop("hunt", 0.3)
	sound_all("harbinger_arrival", 3.0)
	fx_flicker(5.0, 1.0)
	fx_darkness(HouseView.DARKNESS_HARBINGER, 2.0)
	hud.set_hunting(false)
	fx_shake(1.0)
	announce("THE HARBINGER HAS COME", "Recklessness called something worse. All prior evidence is meaningless now.", Color(0.75, 0.88, 1.0), 4.5)
	if not occupants_fled:
		_occupants_flee()
	# The Harbinger appears far from the hunters and hunts almost immediately.
	var far: Array = map.indoor_rooms().filter(func(r):
		for h: Player in living_hunters():
			if map.room_center(r["id"]).distance_to(h.global_position) < 420.0:
				return false
		return true)
	if far.is_empty():
		far = map.indoor_rooms()
	var lair: Dictionary = far[rng.randi_range(0, far.size() - 1)]
	_spawn_creature("harbinger", lair["id"])
	creature.modulate.a = 0.0
	threat = 100.0
	forced_hunt_t = 6.0
	forced_hunt_reckless = true
	_spawn_sigils()
	hud.refresh()

func _spawn_sigils() -> void:
	var rooms: Array = map.indoor_rooms().filter(func(r): return r["id"] != creature.lair_room)
	var chosen: Array = []
	for attempt in 200:
		if chosen.size() >= 3:
			break
		var r: Dictionary = rooms[rng.randi_range(0, rooms.size() - 1)]
		var ok := true
		for c in chosen:
			if map.room_center(c).distance_to(map.room_center(r["id"])) < 260.0 - attempt:
				ok = false
		if ok and not chosen.has(r["id"]):
			chosen.append(r["id"])
	for rid in chosen:
		var pos := HouseMap.cell_center(map.random_free_cell(rid, rng))
		var node := _item_sprite("items/sigil_candle_unlit.png", pos, 30.0)
		var light := PointLight2D.new()
		light.texture = Art.tex("lights/candle.png")
		light.color = Color(0.6, 0.8, 1.0)
		light.energy = 0.5
		light.texture_scale = 0.35
		light.position = pos
		view.add_child(light)
		var s := {"node": node, "light": light, "lit": false, "room": rid, "pos": pos}
		sigils.append(s)
		pickups.append({"kind": "sigil", "sigil": s, "node": node, "pos": pos, "label": "Hold to light the sigil candle", "hold": 1.0})
		record_event("sigil_spawn", {"x": pos.x, "y": pos.y, "id": node.name})

func _light_sigil(p: Player, s: Dictionary) -> void:
	s["lit"] = true
	s["node"].texture = Art.tex("items/sigil_candle_lit.png")
	record_event("decal_swap", {"id": s["node"].name, "sprite": "items/sigil_candle_lit.png"})
	s["light"].energy = 1.4
	s["light"].texture_scale = 0.8
	sound_at("candle_light", s["pos"], 0.0)
	var lit := sigils_lit()
	record_event("sigil", {"actor": p.actor_id, "room": s["room"], "lit": lit, "id": s["node"].name})
	if lit >= sigils.size():
		creature.bind_at(map.room_center(creature.lair_room) if map.walkable(HouseMap.to_cell(map.room_center(creature.lair_room))) else HouseMap.cell_center(map.random_free_cell(creature.lair_room, rng)))
		sound_all("harbinger_arrival", -4.0, 0.8)
		announce("THE HARBINGER IS BOUND", "It waits in the %s. Perform the Final Rite beside it." % map.room_name(creature.lair_room), Color(0.75, 0.88, 1.0), 3.5)
		record_event("bound", {})
	else:
		tell_all("Sigil %d of %d burns." % [lit, sigils.size()], "items/sigil_candle_lit.png")

# --- Interaction -----------------------------------------------------------------------

func find_interactable(p: Player, pos: Vector2) -> Dictionary:
	var best := {}
	var bd := 46.0
	for it in pickups:
		if it["kind"] == "sigil" and it["sigil"]["lit"]:
			continue
		var d: float = pos.distance_to(it["pos"])
		if d < bd:
			bd = d
			best = it
	for it in placed:
		if it["type"] in ["ghost_book", "crucifix"] and it["owner"] == p:
			var d: float = pos.distance_to(it["pos"])
			if d < bd:
				bd = d
				best = {"kind": "retrieve", "item": it, "label": "Retrieve " + Defs.EQUIPMENT[it["type"]]["name"], "hold": 0.0}
	if best.is_empty() and int(p.resources.get("silverware", 0)) >= Defs.SILVERWARE_NEEDED:
		for f in map.furniture_with("melt"):
			if (f["rect"] as Rect2).grow(28.0).has_point(pos):
				return {"kind": "melt", "label": "Hold to melt silverware into a silver stake", "hold": 2.0}
	return best

func do_interact(p: Player, it: Dictionary) -> void:
	if it.is_empty() or p.dead:
		return
	match it["kind"]:
		"resource":
			if not pickups.has(it):
				return   # a rival got there first
			p.add_resource(it["res"])
			_remove_sprite(it["node"])
			pickups.erase(it)
			sound_to(p, "pickup", -2.0)
			tell(p, "Picked up " + Defs.EQUIPMENT[it["res"]]["name"] + ".", Defs.EQUIPMENT[it["res"]]["icon"], true)
			record_event("pickup", {"actor": p.actor_id, "res": it["res"]})
			p.equipment.rebuild_slots()
		"retrieve":
			var item: Dictionary = it["item"]
			if not placed.has(item):
				return
			_remove_sprite(item["node"])
			placed.erase(item)
			if item["type"] == "ghost_book":
				p.book_placed = false
			else:
				p.charges["crucifix"] = 1
				p.crucifix_burns = item["burns"]
			sound_to(p, "pickup", -2.0)
			p.equipment.rebuild_slots()
		"melt":
			p.take_resource("silverware", Defs.SILVERWARE_NEEDED)
			p.add_resource("silver_stake")
			sound_at("melt_silver", p.global_position, 0.0)
			tell(p, "The silver runs and sets: a Silver Stake.", "icons/eq_silver_stake.png")
			record_event("melt", {"actor": p.actor_id})
			add_investigation(p, 1, "melt")
			p.equipment.rebuild_slots()
			p.equipment.select(p.equipment.slots.find("silver_stake"))
		"sigil":
			if not pickups.has(it):
				return
			_light_sigil(p, it["sigil"])
			pickups.erase(it)

# --- Ending ----------------------------------------------------------------------------

func _victory(p: Player) -> void:
	if state != "playing":
		return
	vanquisher = p
	var blind := p.journal.active_entries().is_empty() and not meaningful_investigation(p) and p.wrong_attempts == 0
	state = "ending"
	_outcome = "vanquished"
	_end_t = 2.6
	creature.banish()
	if creature.is_hunting():
		creature.end_hunt()
	Sfx.stop_loop("hunt", 0.4)
	sound_all("vanquish_success", 2.0)
	fx_darkness(Color(0.42, 0.42, 0.5), 2.0)
	if blind and not multiplayer_match:
		record_event("audacity", {"actor": p.actor_id})
		announce("THE HOUSE FALLS SILENT", "…then something laughs. It will remember your audacity.", Art.GOLD, 2.6)
	elif multiplayer_match:
		announce("VANQUISHED", "by %s" % p.display_name, Art.GOLD, 2.4)
	else:
		announce("VANQUISHED", "", Art.GOLD, 2.4)
	record_event("vanquish", {"creature": creature.type_id, "actor": p.actor_id})

func _hunter_dies(p: Player, c: Creature) -> void:
	p.dead = true
	p.input_enabled = false
	p.token.modulate = Color(0.6, 0.1, 0.1)
	sound_to(p, "player_death", 2.0)
	record_event("death", {"actor": p.actor_id})
	_maybe_quip_shove_victim(p)
	c.end_hunt()
	if not multiplayer_match:
		state = "ending"
		_outcome = "perished"
		_end_t = 2.8
		Sfx.stop_loop("hunt", 0.4)
		fx_darkness(Color(0.05, 0.02, 0.02), 1.5)
		announce("PERISHED", "", Art.BLOOD, 2.6)
		return
	announce_to(p, "PERISHED", "Your score is kept. You may watch the others.", Art.BLOOD, 3.0)
	tell_all("%s has fallen." % p.display_name, "icons/ui_skull.png")
	if p.is_local:
		hud.begin_spectating()
	else:
		Net.host_private(p.peer_id, "dead", {})
	if living_hunters().is_empty():
		state = "ending"
		_outcome = "failed"
		_end_t = 3.0
		fx_darkness(Color(0.05, 0.02, 0.02), 1.5)
		announce("ALL HUNTERS PERISHED", "The house keeps them all.", Art.BLOOD, 3.0)

## Solo-format summary for one hunter (also the per-hunter basis in multiplayer).
func build_summary(p: Player = null) -> Dictionary:
	if p == null:
		p = player
	var final_creature := creature.type_id
	var entries := p.journal.active_entries()
	var true_ev := 0
	for e in entries:
		if e["id"] in Defs.CREATURES[final_creature]["evidence"]:
			true_ev += 1
	var all_entries: Array = []
	for e in p.journal.entries:
		all_entries.append({"id": e["id"], "time": snappedf(e["time"], 0.01), "room_id": e["room_id"], "room_name": e["room_name"], "void": e["void"]})
	var transformations := 0
	if original_creature == "shapeshifter":
		for ev in recorder.data["events"]:
			if ev[1] == "transform":
				transformations += 1
	var won := _outcome == "vanquished" and not p.dead
	var summary := {
		"house": house_id, "house_name": map.name, "seed": run_seed, "difficulty": difficulty,
		"original_creature": original_creature, "creature": final_creature,
		"vanquished": won, "time": snappedf(elapsed, 0.01),
		"evidence": all_entries, "evidence_ids": entries.map(func(e): return e["id"]),
		"true_evidence": true_ev, "incorrect_attempts": p.wrong_attempts, "reckless_attempts": p.reckless_attempts,
		"incomplete_attempts": p.incomplete_attempts, "attempts": p.attempts, "wounds": p.wounds,
		"clean_hunts_survived": p.clean_hunts, "hunts": hunts_total, "harbinger": harbinger_summoned,
		"blind": won and entries.is_empty() and not meaningful_investigation(p) and p.wrong_attempts == 0,
		"transformations": transformations, "investigation": p.investigation,
		"occurrences": p.journal.occurrences, "rules_version": Scoring.RULES_VERSION,
	}
	var score := Scoring.compute(summary)
	summary["score"] = score["total"]
	summary["score_lines"] = score["lines"]
	summary["event_digest"] = recorder.digest()
	return summary

## Competitive results for every hunter (host only).
func build_match_results() -> Dictionary:
	var rows: Array = []
	for h: Player in hunters:
		var facts := {
			"actor": h.actor_id, "name": h.display_name, "index": h.index, "peer_id": h.peer_id,
			"creature": creature.type_id, "original_creature": original_creature,
			"vanquished": _outcome == "vanquished", "vanquisher": vanquisher == h, "alive": not h.dead,
			"wounds": h.wounds, "time": snappedf(elapsed, 0.01),
			"true_evidence": h.journal.active_entries().filter(func(e): return e["id"] in Defs.CREATURES[creature.type_id]["evidence"]).size(),
			"first_finds": _first_finds_for(h), "evidence_count": h.journal.active_entries().size(),
			"suspect_correct": h.suspect == creature.type_id or (vanquisher == h),
			"incorrect_attempts": h.wrong_attempts, "reckless_attempts": h.reckless_attempts,
			"incomplete_attempts": h.incomplete_attempts, "clean_hunts_survived": h.clean_hunts,
			"shoves_given": h.shoves_given, "shoves_taken": h.shoves_taken, "harbinger": harbinger_summoned,
			"evidence": h.journal.entries.map(func(e): return {"id": e["id"], "time": snappedf(e["time"], 0.01), "room_name": e["room_name"], "void": e["void"]}),
		}
		var sc := MpScoring.compute(facts)
		facts["score"] = sc["total"]
		facts["score_lines"] = sc["lines"]
		rows.append(facts)
	var ranked := MpScoring.rank(rows)
	return {"house": house_id, "house_name": map.name, "seed": run_seed, "difficulty": difficulty, "outcome": _outcome,
		"creature": creature.type_id, "original_creature": original_creature, "time": snappedf(elapsed, 0.01),
		"harbinger": harbinger_summoned, "rows": ranked, "rules_version": MpScoring.RULES_VERSION}

func _first_finds_for(h: Player) -> int:
	var n := 0
	for ev in first_finder:
		if first_finder[ev] == h.actor_id and ev in Defs.CREATURES[creature.type_id]["evidence"] and h.journal.has(ev):
			n += 1
	return n

func _finish() -> void:
	if _outcome == "":
		return
	var outcome := _outcome
	Sfx.stop_all_loops()
	if multiplayer_match:
		var results := build_match_results()
		_outcome = ""
		var replay := recorder.finish(elapsed, outcome)
		Game.finish_match(results, replay)
		return
	var summary := build_summary()
	_outcome = ""
	var replay := recorder.finish(elapsed, outcome)
	Game.finish_run(summary, replay)

func restart() -> void:
	if multiplayer_match:
		return
	Sfx.stop_all_loops()
	Game.start_run(house_id)

func set_paused(p: bool) -> void:
	if multiplayer_match:
		Net.request_pause(p)   # the host decides for everyone
		return
	_paused = p
	get_tree().paused = p

## Multiplayer: the host froze (or resumed) the whole match. Simulation, timers,
## hunts, the run clock and the replay all stop together and resume together.
func apply_shared_pause(on: bool, who: String, remaining: float) -> void:
	_paused = on
	get_tree().paused = on
	hud.show_shared_pause(on, who, remaining)

# --- Network (host side) -----------------------------------------------------------------

func _net_tick(delta: float) -> void:
	_snap_acc += delta
	if _snap_acc >= 1.0 / SNAPSHOT_HZ:
		_snap_acc = 0.0
		Net.host_snapshot(elapsed, threat, _actor_states(), sigils_lit(), is_harbinger(), creature.is_hunting() if creature else false)
	_priv_acc += delta
	if _priv_acc >= 1.0 / PRIVATE_HZ:
		_priv_acc = 0.0
		for h: Player in hunters:
			if not h.is_local:
				Net.host_hud_state(h.peer_id, hud_state(h))

## Everything a client needs to draw its own HUD for hunter h.
func hud_state(h: Player) -> Dictionary:
	var eq: EquipmentController = h.equipment
	return {"reading": eq.reading, "rc": eq.reading_color.to_html(), "ra": eq.reading_active, "hint": eq.hint,
		"prompt": eq.prompt, "hold": eq.hold_progress(), "slots": eq.slots, "sel": eq.selected,
		"charges": eq.slots.map(func(id): return eq.charge_text(id)), "wounds": h.wounds, "invuln": h.invuln,
		"suspect": h.suspect, "dead": h.dead, "room": h.room_id, "shove_cd": h.shove_cd, "uv": h.uv_light.visible,
		"cam": eq.current() == "orb_camera"}

## A client's own movement report. Positions are client-predicted; the host
## rejects impossible jumps (teleports, speed hacks) and corrects the client.
func apply_remote_input(peer: int, pos: Vector2, aim: float, flags: int, mask: int, counters: PackedByteArray) -> void:
	var h := hunter_by_peer(peer)
	if h == null or h.dead or _paused:
		return   # (press counters are cumulative, so nothing is lost)
	var last: float = h.get_meta("last_input_t", elapsed)
	var dt := maxf(elapsed - last, 1.0 / 60.0)
	h.set_meta("last_input_t", elapsed)
	var allowed := (Player.SPRINT_SPEED * 1.25 + 520.0) * dt + 24.0
	var stair_dest := map.stair_destination(h.global_position, Vector2i(-99, -99))
	var ok := map.is_floor(HouseMap.to_cell(pos)) and (pos.distance_to(h.global_position) <= allowed or (stair_dest != Vector2.INF and pos.distance_to(stair_dest) < 40.0))
	if ok:
		if map.floor_at(pos) != map.floor_at(h.global_position):
			record_event("floor", {"actor": h.actor_id, "floor": map.floor_at(pos)})
		h.global_position = pos
	else:
		Net.host_private(peer, "correct", {"x": h.global_position.x, "y": h.global_position.y})
	h.aim_angle = aim
	h.flashlight_on = flags & 1 == 1
	h.sprinting = flags & 2 == 2
	h.input.apply_remote(mask, counters)

func on_peer_left(peer: int) -> void:
	var h := hunter_by_peer(peer)
	if h == null or h.dead:
		return
	tell_all("%s fled the house (disconnected)." % h.display_name, "icons/ui_skull.png")
	h.dead = true
	h.set_meta("disconnected", true)
	h.visible = false
	record_event("left", {"actor": h.actor_id})
	if living_hunters().is_empty() and state == "playing":
		state = "ending"
		_outcome = "failed"
		_end_t = 1.0
