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
const THREAT_PER_SECOND := 0.176   # 0.11.0: 80% of the former 0.22; difficulty multipliers on top
const MEANINGFUL_INVESTIGATION := 4
const HARBINGER_AFTER_RECKLESS := 2
const HARBINGER_AFTER_WRONG := 3
const STRIKE_REACH := 62.0
const DOOR_REACH := 56.0
const ESCALATE_AT := 65.0          # dread at which a werewolf's moon rises / a vampire's mist comes
const STAIR_REACH := 40.0
const CAMERA_ZOOM := 1.55
const SNAPSHOT_HZ := 20.0
const PRIVATE_HZ := 10.0

var house_id := ""
var run_seed := 0
var creature_override := ""
var roster: Array = []             # [{peer_id, name}] — empty means solo
var multiplayer_match := false
var difficulty := "normal"         # a Defs.DIFFICULTIES id; Defs.rules() gives its rule set
var blood_moon := false            # atmosphere only (no gameplay effect yet)
var setup_info := {}               # the resolved setup: mode and which parts were rolled
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
var _env_t := 0.0
var escalated := false
var _haunt_t := 14.0
var _dread_noise_t := 12.0

## roster empty → solo. Otherwise [{peer_id, name}], the host first.
func setup(p_house: String, p_seed: int, p_override: String, p_roster: Array = [], p_difficulty: String = "normal", p_blood_moon: bool = false, p_setup: Dictionary = {}) -> void:
	house_id = p_house
	difficulty = p_difficulty
	blood_moon = p_blood_moon
	setup_info = p_setup
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
	recorder.data["blood_moon"] = blood_moon
	recorder.data["setup"] = {"mode": setup_info.get("mode", "custom"), "rolled": setup_info.get("rolled", {})}
	world = Node2D.new()
	world.name = "World"
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
	phenomena = Phenomena.new()
	phenomena.setup(self)
	world.add_child(phenomena)
	_spawn_hunters()
	cast = Occupants.cast_for(map, rng, int(map.data.get("npcs", 2)))
	disguise = Occupants.disguise_for(rng, cast)
	_choose_creature()
	_place_resources()
	_place_keepsakes()
	_spawn_occupants()
	if Defs.rules(difficulty) == "nightmare":
		critters = Critters.new()
		view.actor_layer.add_child(critters)
		critters.setup(self, run_seed)
	hud = preload("res://scripts/ui/hud.gd").new()
	add_child(hud)
	hud.setup(self)
	player.journal.discovered.connect(hud.on_discovered)
	if setup_info.get("ghost_marker", false):
		var gm := WorldFx.GhostMarker.new()
		gm.z_index = 50
		gm.source = func(): return [] if creature == null or creature.state == "banished" else [creature.position, creature.is_hunting()]
		world_text.add_child(gm)
	if Defs.rules(difficulty) == "beginner":
		var guide := BeginnerGuide.new()
		guide.setup(self)
		add_child(guide)
	Sfx.stop_loop("music", 0.8)
	Sfx.start_loop("ambience", "ambience_house", -6.0, 1.5)
	record_event("start", {"house": house_id})
	tell_all(map.name + " — something is here.", "icons/ui_house.png")
	# Reveal what was rolled (never the entity).
	if setup_info.get("rolled", {}).get("difficulty", false):
		tell_all("The dice chose %s." % Defs.difficulty_name(difficulty), "icons/ui_skull.png")
	if blood_moon:
		announce("BLOOD MOON", "The moon hangs red over %s." % map.name, Color(0.8, 0.12, 0.08), 2.2)
	if not multiplayer_match and Defs.rules(difficulty) != "beginner" and int(SaveData.data.get("runs_started", 0)) <= 3:
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
	var b := AbyssArena.rect().grow(420.0) if AbyssArena.contains(pos) else map.floor_bounds(map.floor_at(pos))
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
	if type_id == "mimic" and not cast.is_empty():
		disguise = cast[rng.randi_range(0, cast.size() - 1)].duplicate()   # a real resident, twice
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
	record_event("creature_meta", {"actor": _creature_actor_id(), "disguise": disguise.get("name", ""),
		"disguise_id": int(disguise.get("name_id", -1)), "size": creature.token.diameter})

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
			pickups.append({"kind": "resource", "res": res, "node": node, "pos": pos, "icon": Defs.EQUIPMENT[res]["icon"],
				"label": "Pick Up " + Defs.EQUIPMENT[res]["name"], "hold": 0.0})
	# A location without a stove, hearth or furnace cannot melt silver: leave a
	# ready-made silver stake instead, so a werewolf is always beatable.
	if map.furniture_with("melt").is_empty():
		var rooms := map.indoor_rooms()
		var cell := map.random_free_cell(rooms[rng.randi_range(0, rooms.size() - 1)]["id"], rng, used)
		var pos := HouseMap.cell_center(cell)
		pickups.append({"kind": "resource", "res": "silver_stake", "node": _item_sprite("items/silver_stake.png", pos, 26.0), "pos": pos,
			"icon": Defs.EQUIPMENT["silver_stake"]["icon"], "label": "Pick Up " + Defs.EQUIPMENT["silver_stake"]["name"], "hold": 0.0})

func _item_sprite(path: String, pos: Vector2, size: float, rot: float = 0.0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Art.tex(path)
	s.position = pos
	s.rotation = rot
	var k := size / maxf(1.0, s.texture.get_size().x)
	s.scale = Vector2(k, k)
	s.name = "item_%d" % next_uid()
	view.decal_layer.add_child(s)
	record_event("decal", {"id": s.name, "sprite": path, "x": pos.x, "y": pos.y, "rot": snappedf(rot, 0.01), "size": size})
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
		o.fear = Defs.tune(difficulty, "panic")
		view.actor_layer.add_child(o)
		occupants.append(o)
		recorder.register_actor(o.actor_id, "npc", o.token_path, 36.0)
		recorder.data["actors"][o.actor_id]["name"] = o.person["name"]
		record_event("npc", {"actor": o.actor_id, "name": o.person["name"], "name_id": int(o.person.get("name_id", -1)), "token": o.token_path})

# --- Queries used by actors ---------------------------------------------------------

func living_hunters() -> Array:
	return hunters.filter(func(h): return not h.dead)

## Living hunters who are actually in the house (not away in the Abyss).
func hunters_in_house() -> Array:
	return hunters.filter(func(h): return not h.dead and not h.has_meta("abyss"))

func nearest_hunter(pos: Vector2) -> Player:
	var best: Player = null
	var bd := INF
	for h: Player in hunters:
		if h.dead or h.has_meta("abyss"):
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
		if h.equipment:
			h.equipment.process_input(delta)
			h.equipment.update_tools(delta)
		h.input.consume()
		if h.is_local and h.global_position.distance_to(before) > 90.0:
			camera.reset_smoothing()
	_update_threat(delta)
	_update_defences(delta)
	_environment_tick(delta)
	_hostile_tick(delta)
	_keepsake_tick(delta)
	_hazard_tick(delta)
	if Defs.rules(difficulty) == "nightmare":
		_nightmare_noises(delta)
	_phantom_steps(delta)
	_relocation_tick(delta)
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

## The anticipation cue: the grandfather clock nearest the entity ticks, tolls
## once and stops, just before a hunt breaks loose (heard by everyone nearby).
func _clock_toll(near: Vector2) -> void:
	var best: Dictionary = {}
	var bd := 900.0
	for f in map.furniture:
		if f["type"] != "grandfather_clock":
			continue
		var d: float = (f["rect"] as Rect2).get_center().distance_to(near)
		if d < bd:
			bd = d
			best = f
	if best.is_empty():
		return
	sound_at("clock_toll", (best["rect"] as Rect2).get_center(), -2.0, 1.0, 1300.0)
	if best.has("index"):
		view.shake_furniture(best["index"])
		record_event("shake", {"index": best["index"]})

# --- Home-room relocation ------------------------------------------------------------------
# At most two per investigation, never early, rarely twice: most 3–5 minute
# runs see none or one. The new room is never revealed.
const MAX_RELOCATIONS := 2
var relocations := 0
var _relocate_t := 0.0

func _relocation_tick(delta: float) -> void:
	if _relocate_t == 0.0:
		_relocate_t = rng.randf_range(100.0, 160.0)
	var c := creature
	if c == null or c.state != "roam" or is_harbinger() or in_abyss(c) or c.type_id == "lost_one" or relocations >= MAX_RELOCATIONS:
		return   # (the Lost One stays bound to its keepsake's room)
	_relocate_t -= delta
	if _relocate_t > 0.0:
		return
	_relocate_t = rng.randf_range(90.0, 140.0)
	if rng.randf() < (0.5 if relocations == 0 else 0.3):
		relocate_home()

func relocate_home() -> void:
	var c := creature
	var options: Array = map.indoor_rooms().filter(func(r): return r["id"] != c.lair_room and map.free_cells(r["id"]).size() >= 10)
	if options.is_empty():
		return
	var old := c.lair_room
	var new_room: String = options[rng.randi_range(0, options.size() - 1)]["id"]
	relocations += 1
	c.relocate_home(new_room)
	phenomena.move_lair(old, new_room)
	record_event("relocate", {"room": new_room})   # replay only: never sent to rivals' clients
	tell_all("The haunting has shifted…", "icons/ui_skull.png")

var _phantom_t := 40.0

## Footsteps that belong to nobody: a few paces somewhere behind a hunter once
## dread has built a little. Atmosphere only — never evidence, never a threat.
func _phantom_steps(delta: float) -> void:
	_phantom_t -= delta
	if _phantom_t > 0.0:
		return
	_phantom_t = rng.randf_range(35.0, 60.0)
	if Defs.rules(difficulty) == "beginner" or threat < 30.0 or (creature and creature.is_hunting()):
		return
	var here := hunters_in_house().filter(func(h): return not h.dead)
	if here.is_empty():
		return
	var h: Player = here[rng.randi_range(0, here.size() - 1)]
	var back := Vector2.from_angle(h.aim_angle + PI + rng.randf_range(-0.5, 0.5))
	var side := back.orthogonal()
	var tw := create_tween()
	for k in 4:
		var pos := h.global_position + back * (300.0 - k * 30.0) + side * (8.0 if k % 2 == 0 else -8.0)
		tw.tween_callback(func(): sound_at("footstep", pos, -9.0, rng.randf_range(0.8, 0.9), 700.0))
		tw.tween_interval(0.48)

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
	threat = minf(100.0, threat + THREAT_PER_SECOND * delta * Defs.tune(difficulty, "dread"))
	if not escalated and threat >= ESCALATE_AT and creature and creature.type_id in ["werewolf", "vampire"] and creature.state != "banished":
		_escalate()
	if creature == null or creature.state != "roam" or creature.cooldown_t > 0.0:
		return
	if in_abyss(creature):
		return   # away in the Abyss: even a forced hunt waits for its return
	if forced_hunt_t > 0.0:
		forced_hunt_t -= delta
		if forced_hunt_t <= 0.0:
			trigger_hunt(forced_hunt_reckless)
		return
	if not is_harbinger() and elapsed < GRACE_PERIOD * Defs.tune(difficulty, "grace"):
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
		refit_suspect(p)

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
	var candidates: Array = occupants.filter(func(o): return o.state != "flee" and o.state != "gone" and not o.bitten and not o in _abyss_npcs)
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
# --- Doors and lights ---------------------------------------------------------------

func set_door(i: int, open: bool, loud: bool = false) -> void:
	if i < 0 or i >= view.doors.size() or view.doors[i]["open"] == open:
		return
	view.set_door(i, open)
	var pos := HouseMap.cell_center(view.doors[i]["cell"])
	if loud and not open:
		sound_at("door_slam", pos, -2.0, rng.randf_range(0.9, 1.1))
	else:
		sound_at("door_creak", pos, -12.0 if not loud else -4.0, rng.randf_range(0.9, 1.2), 900.0)
	record_event("door", {"i": i, "open": open})

func set_light(i: int, on: bool) -> void:
	if not view.can_extinguish(i) or view.lights[i]["on"] == on:
		return
	view.set_light(i, on)
	sound_at("candle_light" if on else "flame_snuff", view.lights[i]["pos"], -6.0)
	record_event("light", {"i": i, "on": on})

func _someone_in_doorway(i: int) -> bool:
	var pos := HouseMap.cell_center(view.doors[i]["cell"])
	for h: Player in hunters:
		if not h.dead and h.global_position.distance_to(pos) < 30.0:
			return true
	return false

## Occupants and creatures of flesh open the doors they pass through. Ghosts
## simply drift through.
func _environment_tick(delta: float) -> void:
	_env_t -= delta
	if _env_t > 0.0:
		return
	_env_t = 0.12
	# Hunters open doors deliberately ([E] / [Space]); walking into one does nothing.
	var movers: Array = []
	for o in occupants:
		if o.state != "gone":
			movers.append(o.position)
	if creature and creature.state != "banished" and not creature.is_ghost_like() and not (creature.type_id == "shapeshifter" and creature.form == "ghost"):
		movers.append(creature.position)
	for pos: Vector2 in movers:
		var i := view.door_index_at(pos, 23.0)
		if i >= 0 and not view.doors[i]["open"]:
			set_door(i, true)
	# Supernatural meddling with doors and flames, more often while it hunts.
	if creature and creature.state != "banished" and not in_abyss(creature):
		_haunt_t -= 0.12 * (2.5 if creature.is_hunting() else 1.0)
		if _haunt_t <= 0.0:
			_haunt_t = rng.randf_range(12.0, 24.0) * Defs.tune(difficulty, "haunt_every")
			haunt_near(creature.position)
			if Defs.hostile(difficulty) == "hellbound":
				shake_furniture_near(creature.position)   # the house itself lashes out

# --- Hellbound & Abyssal ------------------------------------------------------------------
# Hellbound: the house turns openly hostile — faster dread, constant slams and
# snuffed flames, quicker hunts, and Hellfire: a patch of floor glows red, then
# erupts in flame a moment later. Abyssal: reality tears — portals swallow a whole
# room and drag everyone in it to Abyssal Hell (AbyssArena) for a minute.

const HELLFIRE_WARN := 1.6
const HELLFIRE_BURN := 3.5
const HELLFIRE_RADIUS := 34.0
const PORTAL_WARN := 2.5
var _hellfire_t := 25.0
var _portal_t := 50.0
var abyss_room := ""
var abyss_until := -1.0
var _abyss_npcs: Array = []

func _hostile_tick(delta: float) -> void:
	if Defs.hostile(difficulty) == "hellbound":
		_hellfire_t -= delta
		if _hellfire_t <= 0.0:
			_hellfire_t = rng.randf_range(8.0, 14.0)
			var targets := hunters_in_house()
			if not targets.is_empty():
				var h: Player = targets[rng.randi_range(0, targets.size() - 1)]
				spawn_hellfire(h.global_position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 90.0))
	elif Defs.hostile(difficulty) == "abyssal":
		if abyss_until > 0.0:
			_abyss_tick()
		else:
			_portal_t -= delta
			if _portal_t <= 0.0:
				_portal_t = rng.randf_range(80.0, 120.0)
				_portal_warning()

## A red warning glow, then flames that burn anyone standing in them.
func spawn_hellfire(at: Vector2) -> void:
	var cell := map.nearest_walkable(HouseMap.to_cell(at))
	var pos := HouseMap.cell_center(cell)
	view.hellfire_warning(pos, HELLFIRE_RADIUS, HELLFIRE_WARN)
	sound_at("flame_snuff", pos, -2.0, 0.5)
	record_event("hellfire", {"phase": "warn", "x": pos.x, "y": pos.y})
	var tw := create_tween()
	tw.tween_interval(HELLFIRE_WARN)
	tw.tween_callback(func():
		if state != "playing":
			return
		view.burst_flames(pos, HELLFIRE_BURN, 1.9)
		sound_at("ignite", pos, 2.0, 0.8)
		hazards.append({"pos": pos, "until": elapsed + HELLFIRE_BURN, "radius": HELLFIRE_RADIUS, "node": null, "light": null, "kind": "hellfire"})
		record_event("hellfire", {"phase": "erupt", "x": pos.x, "y": pos.y}))

## Hellbound: starting a rite is noticed — fire near you and a surge of dread.
func on_rite_begun(p: Player) -> void:
	if Defs.hostile(difficulty) != "hellbound":
		return
	add_threat(6.0, "hellbound_rite")
	spawn_hellfire(p.global_position + Vector2.from_angle(rng.randf() * TAU) * 80.0)
	tell(p, "The house knows what you are doing.", "icons/ui_skull.png", true)

func _portal_warning() -> void:
	var occupied: Array = []
	for h: Player in hunters_in_house():
		if h.room_id != "" and not occupied.has(h.room_id) and not map.room(h.room_id).get("outdoor", true):
			occupied.append(h.room_id)
	var rooms := map.indoor_rooms()
	var room: String = occupied[rng.randi_range(0, occupied.size() - 1)] if not occupied.is_empty() and rng.randf() < 0.75 else rooms[rng.randi_range(0, rooms.size() - 1)]["id"]
	view.portal_warning(room, PORTAL_WARN)
	sound_all("blight_ping", -4.0, 0.45)
	sound_at("nm_drag", map.room_center(room), 2.0, 0.5)
	record_event("portal", {"phase": "warn", "room": room})
	for h: Player in hunters_in_house():
		if h.room_id == room:
			announce_to(h, "THE AIR TEARS OPEN", "Get out of this room!", Color(0.8, 0.45, 1.0), PORTAL_WARN)
	var tw := create_tween()
	tw.tween_interval(PORTAL_WARN)
	tw.tween_callback(func():
		if state == "playing":
			open_abyss(room))

## Everyone in `room` — hunters, occupants and the entity — is pulled into Abyssal Hell.
func open_abyss(room: String) -> void:
	var arena := view.ensure_abyss()
	abyss_room = room
	abyss_until = elapsed + AbyssArena.DURATION
	var seed_v := rng.randi()
	arena.open(seed_v)
	record_event("abyss", {"phase": "open", "seed": seed_v, "room": room})
	WorldFx.ring(view.overlay_layer, map.room_center(room), Color(0.7, 0.3, 1.0), 220.0, 1.4)
	sound_at("harbinger_arrival", map.room_center(room), 0.0, 1.3)
	var k := 0
	for h: Player in hunters_in_house():
		if map.room_at(h.global_position, h.room_id) != room:
			continue
		h.set_meta("abyss", true)
		h.set_meta("abyss_trips", int(h.get_meta("abyss_trips", 0)) + 1)
		_move_hunter(h, AbyssArena.spawn_point(k))
		h.invuln = maxf(h.invuln, 1.5)
		k += 1
		record_event("abyss_pull", {"actor": h.actor_id})
		announce_to(h, "DRAGGED INTO THE ABYSS", "Survive one minute.", Color(0.8, 0.45, 1.0), 2.4)
		for o: Player in hunters_in_house():
			tell(o, "%s vanished into a portal." % h.display_name, "icons/ui_skull.png", true)
	# Occupants and the entity go too: frozen and drifting at the far end of the
	# realm, seen by everyone there but unable to act on the house or the hunters.
	_abyss_npcs.clear()
	for o in occupants:
		if o.state != "gone" and o.room_id == room:
			o.set_process(false)
			o.tag.set_visible(false)
			o.modulate.a = 1.0
			_abyss_npcs.append(o)
	if creature and creature.state != "banished" and creature.state != "bound" and creature.room_id == room:
		if creature.is_hunting():
			creature.end_hunt()
		creature.set_meta("abyss", true)
		creature.set_process(false)
		creature.alpha = 0.85
		creature.modulate.a = 0.85
		record_event("abyss_pull", {"actor": _creature_actor_id(), "entity": true})
	_abyss_drift()

## Where the occupants and the entity hang in the realm (out of the hunters' way).
func _abyss_drift() -> void:
	var t := view.abyss.t if view.abyss else 0.0
	var k := 0
	for o in _abyss_npcs:
		o.position = AbyssArena.far_point(k, t)
		k += 1
	if in_abyss(creature):
		creature.position = AbyssArena.far_point(k, t)

func in_abyss(n: Node) -> bool:
	return n != null and is_instance_valid(n) and n.has_meta("abyss")

func _move_hunter(h: Player, to: Vector2) -> void:
	h.global_position = to
	h.velocity = Vector2.ZERO
	if h.is_local:
		_apply_camera_limits(to)
		camera.reset_smoothing()
		view.set_basement_view(map.floor_at(to) < 0 and not AbyssArena.contains(to))
	elif h.remote:
		Net.host_private(h.peer_id, "correct", {"x": to.x, "y": to.y})

func _abyss_tick() -> void:
	var arena := view.abyss
	for h: Player in hunters:
		if not h.has_meta("abyss") or h.dead or h.invuln > 0.0:
			continue
		var what := arena.hazard_at(h.global_position)
		if what != "":
			sound_at("player_hurt", h.global_position, -6.0)
			tell(h, "The %s tear at you!" % what, "icons/ui_skull.png")
			_wound(h, null, "abyss")
	_abyss_drift()
	if elapsed >= abyss_until:
		close_abyss()

## The portal spits its survivors back into the room they were taken from.
func close_abyss() -> void:
	if abyss_until < 0.0:
		return
	abyss_until = -1.0
	var room := abyss_room
	var used := {}
	for h: Player in hunters:
		if not h.has_meta("abyss"):
			continue
		h.remove_meta("abyss")
		var cell := map.random_free_cell(room, rng, used)
		used[cell] = true
		_move_hunter(h, HouseMap.cell_center(cell))
		h.room_id = room
		if not h.dead:
			h.invuln = maxf(h.invuln, 2.0)
			h.set_meta("abyss_escapes", int(h.get_meta("abyss_escapes", 0)) + 1)
			announce_to(h, "SPAT BACK OUT", "The portal returns you to %s." % map.room_name(room), Color(0.8, 0.45, 1.0), 1.8)
		record_event("abyss_return", {"actor": h.actor_id, "alive": not h.dead})
	for o in _abyss_npcs:
		if is_instance_valid(o) and o.state != "gone":
			o.position = HouseMap.cell_center(map.random_free_cell(room, rng, used))
			o.visible = true
			o.modulate.a = 1.0
			o.set_process(true)
			o.tag.set_visible(true)
			o.say("Where— where was I?")
	_abyss_npcs.clear()
	if creature and creature.has_meta("abyss"):
		creature.remove_meta("abyss")
		creature.position = HouseMap.cell_center(map.random_free_cell(room, rng, used))
		creature.room_id = room
		creature.visible = true
		creature.set_process(true)
		creature.cooldown_t = maxf(creature.cooldown_t, 8.0)
	view.abyss.close()
	WorldFx.ring(view.overlay_layer, map.room_center(room), Color(0.7, 0.3, 1.0), 220.0, 1.0)
	sound_at("harbinger_arrival", map.room_center(room), -4.0, 1.5)
	record_event("abyss", {"phase": "close", "room": room})

## The entity snuffs a flame or swings a door near pos.
func haunt_near(pos: Vector2) -> void:
	if rng.randf() < 0.55:
		var doors_near: Array = []
		for i in view.doors.size():
			if HouseMap.cell_center(view.doors[i]["cell"]).distance_to(pos) < 260.0 and not _someone_in_doorway(i):
				doors_near.append(i)
		if not doors_near.is_empty():
			var i: int = doors_near[rng.randi_range(0, doors_near.size() - 1)]
			set_door(i, not view.doors[i]["open"], true)
			disturbance(HouseMap.cell_center(view.doors[i]["cell"]))
			return
	var lit: Array = []
	for i in view.lights.size():
		if view.can_extinguish(i) and view.lights[i]["on"] and view.lights[i]["pos"].distance_to(pos) < 300.0:
			lit.append(i)
	if not lit.is_empty():
		set_light(lit[rng.randi_range(0, lit.size() - 1)], false)
	else:
		shake_furniture_near(pos)   # nothing to slam or snuff: a chair shifts, a book shelf rattles

var _shimmer_t := {}

## Evidence beginning to appear: the room's air warps briefly (at most every 15 s
## per room). Purely atmospheric — it fires for any entity's phenomena.
func shimmer(room_id: String) -> void:
	if room_id == "" or elapsed < float(_shimmer_t.get(room_id, -99.0)) + 15.0:
		return
	_shimmer_t[room_id] = elapsed
	view.shimmer_room(room_id)
	record_event("shimmer", {"room": room_id})

## Dread has peaked: the full moon (the werewolf turns, for good) or the blood mist.
func _escalate() -> void:
	escalated = true
	var kind := "moon" if creature.type_id == "werewolf" else "mist"
	view.set_mood(kind)
	record_event("escalate", {"kind": kind})
	if kind == "moon":
		tell_all("The full moon breaks through the clouds.", "icons/ui_skull.png")
		creature.transform_to_wolf()
	else:
		sound_all("nm_drag", -10.0, 0.6)
		tell_all("A thick red mist rises through the house.", "icons/ui_skull.png")

func creature_fx(kind: String, pos: Vector2, extra: Dictionary = {}) -> void:
	var d := {"kind": kind, "x": snappedf(pos.x, 0.1), "y": snappedf(pos.y, 0.1)}
	d.merge(extra)
	match kind:
		"ping": WorldFx.ring(view.overlay_layer, pos, Color(0.75, 0.9, 0.45), 70.0, 0.9)
		"rage": WorldFx.ring(view.overlay_layer, pos, Color(1.0, 0.25, 0.15), 110.0, 1.2)
		"dust": WorldFx.dust(view.overlay_layer, pos)
		"transform": WorldFx.ring(view.overlay_layer, pos, Color(0.75, 0.85, 1.0), 120.0, 1.4)
		"revert": WorldFx.ring(view.overlay_layer, pos, Color(1.0, 0.95, 0.8), 90.0, 1.2)
		"counter": WorldFx.ring(view.overlay_layer, pos, Art.GOLD, 80.0, 0.7)
		"lights": view.flicker_near(pos, 170.0, 1.2)
		"emerge": view.emerge_splash(pos)
		"miasma": view.miasma(pos, float(d.get("r", 70.0)), float(d.get("dur", 9.0)))
	record_event("creature_fx", d)

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
## Stairs are taken deliberately ([E] / [Space]); walking onto them does nothing.
func _take_stairs(h: Player, cell: Vector2i) -> void:
	if h.dead:
		return
	var dest := map.stair_target(cell)
	h.global_position = dest
	h.room_id = map.room_at(dest)
	if h.remote:
		Net.host_private(h.peer_id, "correct", {"x": dest.x, "y": dest.y, "floor": map.floor_at(dest)})
	if h == player:
		_apply_camera_limits(dest)
		camera.reset_smoothing()
		_on_local_floor(map.floor_at(dest))
	sound_to(h, "footstep", -2.0, 0.7)
	tell(h, map.room_name(h.room_id), "icons/ui_house.png", true)
	record_event("floor", {"actor": h.actor_id, "floor": map.floor_at(dest)})

# --- Hunts ---------------------------------------------------------------------------

func trigger_hunt(reckless: bool) -> void:
	if creature == null or creature.state != "roam" or state != "playing" or in_abyss(creature) or hunters_in_house().is_empty():
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
	_clock_toll(creature.position)
	creature.begin_hunt(_fair_hunt_start(), reckless)

## Chooses where a hunt begins so that it is never unavoidable for any hunter.
func _fair_hunt_start() -> Vector2:
	var alive := living_hunters()
	var cpos := creature.position
	if creature.type_id == "drowned_sailor" and rng.randf() < 0.7:
		var from := _fair_puddle(alive)
		if from != Vector2.INF:
			creature_fx("emerge", from)
			sound_at("water_splash", from, 2.0)
			return from
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
		"blightness": sound_at("blight_ping", c.position, 4.0, 0.8)
		"crawler": sound_at("crawl_drag", c.position, 0.0)
		"drowned_sailor": sound_at("sea_whisper", c.position, 2.0, 0.8)
		"plague_doctor": sound_at("plague_breath", c.position, 2.0, 0.85)
		"weeper": sound_at("weeper_sob", c.position, 4.0, 0.85)
		"mimic":
			sound_at("whisper_mimic", c.position, 2.0, 0.5)
			sound_at("ghost_wail", c.position, -4.0, 0.8)
		"lost_one":
			if c.wrath:
				sound_at("ghost_wail", c.position, 2.0, 1.4)
			else:
				sound_at("music_box", c.position, -4.0, 0.9)
	Sfx.start_loop("hunt", "hunt_loop", -2.0, 1.0)
	hud.set_hunting(true)
	# The flames nearest each hunter gutter out as it begins.
	for h: Player in living_hunters():
		haunt_near(h.global_position)
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
		if in_abyss(h):
			continue   # it hunted a house they were not in
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
	# Counterattack: caught with the right stake in hand, you strike first.
	var counter_item: String = {"vampire": "wooden_stake", "werewolf": "silver_stake"}.get(c.type_id, "")
	if counter_item != "" and p.equipment and p.equipment.current() == counter_item and p.has_resource(counter_item):
		_counterattack(p, c, counter_item)
		return
	match c.type_id:
		"lost_one":
			if c.wrath:
				_furnace_drag(p, c)
			else:
				# Its ordinary hunts cannot hurt anyone: small cold hands, and a fright.
				p.invuln = 2.0
				_push(p, (p.global_position - c.position).normalized() * 380.0)
				add_threat(3.0, "lost_one_touch")
				tell(p, "Small, cold hands pass right through you. It only wants to frighten.", "tokens/lost_one.png")
			return
		"crawler":
			# It rises out of the floor and drags its victim under: a wound, never an instant death.
			c.set_meta("rising", true)
			var tw := create_tween()   # bound to the run: never fires after it is gone
			tw.tween_interval(1.2)
			tw.tween_callback(func():
				if is_instance_valid(c):
					c.remove_meta("rising"))
			_push(p, (c.position - p.global_position).normalized() * 420.0)
			sound_at("crawl_drag", p.global_position, 0.0)
			announce_to(p, "DRAGGED UNDER", "Something rose out of the floor.", Color(0.6, 0.5, 0.75), 1.6)
	c.hunt_hit = true
	_wound(p, c, "creature")
	if not p.dead:
		c.end_hunt()

func _counterattack(p: Player, c: Creature, item: String) -> void:
	p.invuln = 1.5
	record_event("counter", {"actor": p.actor_id, "creature": c.type_id, "x": c.position.x, "y": c.position.y})
	creature_fx("counter", c.position)
	sound_at("stake_strike", c.position, 6.0, 0.85)
	fx_shake(0.7)
	announce_to(p, "COUNTERATTACK!", "You drive the %s home as it lunges." % Defs.EQUIPMENT[item]["name"].to_lower(), Art.GOLD, 1.6)
	attempt_vanquish(p, c.type_id, item)

## A wound from any source (the entity, embers, the furnace). Two wounds kill.
func _wound(p: Player, c: Creature, source: String) -> void:
	if p.dead or state != "playing":
		return
	p.wounds += 1
	if creature and creature.is_hunting():
		p.set_meta("hit_this_hunt", true)
	record_event("attack", {"actor": p.actor_id, "wounds": p.wounds, "source": source})
	if p.wounds >= 2:
		_hunter_dies(p, c)
		return
	p.invuln = Player.INVULN_AFTER_HIT * Defs.tune(difficulty, "wound_grace")
	sound_to(p, "player_hurt", 0.0)
	if p.is_local:
		hud.wound()
	elif multiplayer_match:
		Net.host_private(p.peer_id, "wound", {})
	tell(p, "You are wounded. Once more and you are finished.", "icons/ui_heart_wounded.png")
	_maybe_quip_shove_victim(p)

func _push(p: Player, impulse: Vector2) -> void:
	if p.is_local:
		p.knockback(impulse)
	elif multiplayer_match:
		Net.host_private(p.peer_id, "knockback", {"x": impulse.x, "y": impulse.y})

# --- The Lost One: keepsakes and the furnace ------------------------------------------

const KEEPSAKES := {
	"music_box": ["the music box", "A little music box. The dancer inside has lost an arm."],
	"locket": ["the locket", "A tarnished locket. The photograph inside has been scratched out."],
	"child_shoe": ["the little shoe", "One small buttoned shoe. Its pair is nowhere to be seen."],
}
var keepsakes: Array = []

## Three keepsakes in every house. With the Lost One present, one of them — always
## in its own room — is its treasure: it twitches and hums a lullaby, and touching it
## is the worst thing you can do.
func _place_keepsakes() -> void:
	var rooms: Array = map.indoor_rooms().map(func(r): return r["id"])
	for i in range(rooms.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = rooms[i]
		rooms[i] = rooms[j]
		rooms[j] = tmp
	var names := KEEPSAKES.keys()
	var forbidden := rng.randi_range(0, names.size() - 1) if creature.type_id == "lost_one" else -1
	for i in names.size():
		var rid: String = creature.lair_room if i == forbidden else rooms[i % rooms.size()]
		if i != forbidden and rid == creature.lair_room:
			rid = rooms[(i + 3) % rooms.size()]
		var pos := HouseMap.cell_center(map.random_free_cell(rid, rng))
		var node := _item_sprite("items/%s.png" % names[i], pos, 24.0)
		var k := {"kind": "keepsake", "item": names[i], "node": node, "pos": pos, "forbidden": i == forbidden,
			"label": "Examine " + KEEPSAKES[names[i]][0].replace("the ", "").capitalize(), "hold": 0.0, "icon": "items/%s.png" % names[i], "twitch_t": rng.randf_range(4.0, 8.0)}
		keepsakes.append(k)
		pickups.append(k)

func _keepsake_tick(delta: float) -> void:
	if creature == null or creature.type_id != "lost_one" or creature.state == "banished":
		return
	for k in keepsakes:
		if not k["forbidden"]:
			continue
		k["twitch_t"] -= delta
		if k["twitch_t"] <= 0.0:
			k["twitch_t"] = rng.randf_range(6.0, 11.0)
			WorldFx.twitch(k["node"])
			creature_fx("twitch", k["pos"], {"id": k["node"].name})
			for h: Player in living_hunters():
				if h.global_position.distance_to(k["pos"]) < 260.0:
					sound_at("music_box", k["pos"], -12.0, rng.randf_range(0.97, 1.03), 500.0)
					break

func _examine_keepsake(p: Player, k: Dictionary) -> void:
	record_event("keepsake", {"actor": p.actor_id, "item": k["item"], "forbidden": k["forbidden"] and creature.type_id == "lost_one"})
	if not (k["forbidden"] and creature.type_id == "lost_one" and creature.state in ["roam", "stunned"]) or in_abyss(creature):
		WorldFx.twitch(k["node"])
		tell(p, KEEPSAKES[k["item"]][1], "items/%s.png" % k["item"], true)
		return
	# You touched what was theirs.
	var c := creature
	c.stunned_t = 0.0
	c.state = "roam"
	var away := p.global_position + Vector2.from_angle(rng.randf() * TAU) * 220.0
	c.position = HouseMap.cell_center(map.nearest_walkable(HouseMap.to_cell(away)))
	c.wrath = true
	c.wrath_target = p
	c.cooldown_t = 0.0
	sound_all("scream_3", -4.0, 1.25)
	announce_to(p, "YOU TOOK WHAT WAS THEIRS", "The Lost One is coming for you. Run.", Color(0.85, 0.85, 1.0), 2.4)
	tell_all("A child screams somewhere in the house.", "tokens/lost_one.png")
	record_event("wrath", {"actor": p.actor_id})
	c.begin_hunt(c.position, true)

## The Lost One's catch: dragged down to the basement furnace and burned.
func _furnace_drag(p: Player, c: Creature) -> void:
	var furnace: Dictionary = {}
	for f in map.furniture:
		if f["type"] == "boiler":
			furnace = f
	var fpos: Vector2 = (furnace["rect"] as Rect2).get_center() if not furnace.is_empty() else HouseMap.cell_center(map.spawn_cell)
	var land := HouseMap.cell_center(map.nearest_walkable(HouseMap.to_cell(fpos + Vector2(0, Defs.CELL * 1.6).rotated(int(furnace.get("rot", 0)) * PI * 0.5))))
	var near := land + (fpos - land).normalized() * 12.0
	p.invuln = 99.0
	c.end_hunt()
	c.stun(4.0)
	record_event("dragged", {"actor": p.actor_id, "x": fpos.x, "y": fpos.y})
	sound_at("crawl_drag", p.global_position, 0.0, 0.8)
	announce_to(p, "DRAGGED BELOW", "Down, down, to the furnace…", Color(1.0, 0.5, 0.2), 2.2)
	var pts := [[p.global_position + (c.position - p.global_position).limit_length(30.0), 0.35], [p.global_position, 0.9],
		[land, 0.05], [near, 1.1]]
	if p.is_local:
		p.play_drag(pts)
	elif multiplayer_match:
		p.set_meta("dragged_until", elapsed + 3.0)
		Net.host_private(p.peer_id, "drag", {"pts": pts.map(func(e): return [e[0].x, e[0].y, e[1]])})
	var tw := create_tween()
	tw.tween_interval(1.3)
	tw.tween_callback(func():
		if p.is_local:
			_apply_camera_limits(land)
			_on_local_floor(map.floor_at(land))
			camera.reset_smoothing())
	tw.tween_interval(1.1)
	tw.tween_callback(func():
		sound_at("furnace_roar", fpos, 4.0)
		view.burst_flames(fpos, 2.2, 2.0)
		WorldFx.ring(view.overlay_layer, fpos, Color(1.0, 0.5, 0.15), 140.0, 1.4)
		record_event("furnace", {"x": fpos.x, "y": fpos.y})
		fx_shake(0.6)
		p.invuln = 0.0
		_wound(p, c, "furnace"))

# --- The voodoo doll -------------------------------------------------------------------

var hazards: Array = []        # {pos, until, radius, node, light}
var npcs_burned := 0

## Stabbing the doll. Ghosts answer with an occupant's fiery death; creatures of
## flesh are enraged. Either way the house remembers.
func use_voodoo(p: Player) -> void:
	if not p.has_resource("voodoo_doll") or state != "playing" or creature == null or creature.state == "banished":
		return
	if in_abyss(creature):
		tell(p, "The pins stay cold. Whatever haunts this house is not here right now.", "icons/eq_voodoo_doll.png", true)
		return
	p.take_resource("voodoo_doll", 1)
	p.set_meta("voodoo_uses", int(p.get_meta("voodoo_uses", 0)) + 1)
	p.equipment.rebuild_slots()
	sound_at("stake_strike", p.global_position, -4.0, 1.5)
	var c := creature
	var ghostly: bool = c.is_ghost_like() or (c.type_id == "shapeshifter" and c.form == "ghost")
	if not ghostly:
		c.angered_t = 45.0
		add_threat(25.0, "voodoo")
		sound_at({"vampire": "vampire_hiss", "werewolf": "werewolf_growl"}.get(c.type_id, "reckless_reaction"), c.position, 4.0)
		creature_fx("rage", c.position)
		fx_shake(0.4)
		tell_all("Something in the house howls with rage.", "icons/ui_skull.png")
		record_event("voodoo", {"actor": p.actor_id, "effect": "rage"})
		if c.state == "roam":
			c.cooldown_t = 0.0
			forced_hunt_t = 4.0
			forced_hunt_reckless = true
		return
	var victims: Array = occupants.filter(func(o): return o.state != "gone" and not o in _abyss_npcs)
	if victims.is_empty():
		tell(p, "The doll's pins grow hot. Something turns its attention to you.", "icons/eq_voodoo_doll.png")
		record_event("voodoo", {"actor": p.actor_id, "effect": "turned"})
		c.cooldown_t = 0.0
		forced_hunt_t = 3.0
		forced_hunt_reckless = true
		return
	var o: Occupant = victims[rng.randi_range(0, victims.size() - 1)]
	record_event("voodoo", {"actor": p.actor_id, "effect": "burn", "npc": o.actor_id})
	_burn_occupant(o)

func _burn_occupant(o: Occupant) -> void:
	var pos := o.position
	npcs_burned += 1
	o.say("AAAAH!")
	sound_at(["scream_1", "scream_2", "scream_3"][rng.randi_range(0, 2)], pos, 2.0)
	sound_at("ignite", pos, 2.0)
	view.burst_flames(pos, 1.6)
	record_event("npc_burn", {"actor": o.actor_id, "x": pos.x, "y": pos.y})
	tell_all("%s burst into flames!" % o.person["name"], "icons/ui_skull.png")
	fx_shake(0.3)
	o.combust()
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_callback(func():
		var node := _item_sprite("items/embers.png", pos, 40.0)
		var l := PointLight2D.new()
		l.texture = Art.tex("lights/candle.png")
		l.color = Color(1.0, 0.45, 0.15)
		l.energy = 0.9
		l.texture_scale = 0.5
		l.position = pos
		view.add_child(l)
		hazards.append({"pos": pos, "until": elapsed + 25.0, "radius": 26.0, "node": node, "light": l})
		for oo in occupants:
			oo.react(pos))

func _hazard_tick(delta: float) -> void:
	for h: Player in living_hunters():
		h.set_meta("ember_cd", maxf(0.0, float(h.get_meta("ember_cd", 0.0)) - delta))
	_miasma_tick(delta)
	for hz in hazards.duplicate():
		if elapsed >= hz["until"]:
			hazards.erase(hz)
			if is_instance_valid(hz["node"]):
				hz["node"].texture = Art.tex("items/ashes.png")
				record_event("decal_swap", {"id": hz["node"].name, "sprite": "items/ashes.png"})
			if is_instance_valid(hz["light"]):
				hz["light"].queue_free()
			continue
		if hz.get("kind", "") == "miasma":
			continue
		if is_instance_valid(hz["light"]):
			hz["light"].energy = 0.8 + sin(elapsed * 9.0 + hz["pos"].x) * 0.15
		for h: Player in living_hunters():
			if h.global_position.distance_to(hz["pos"]) < hz["radius"] and h.invuln <= 0.0 and float(h.get_meta("ember_cd", 0.0)) <= 0.0:
				# Burned: a wound, with a grace period so one step never counts twice.
				h.set_meta("ember_cd", 4.0)
				sound_at("ignite", h.global_position, -8.0, 1.4)
				var hell: bool = hz.get("kind", "") == "hellfire"
				tell(h, "Hellfire! You are burned." if hell else "The embers sear you!", "items/embers.png")
				if hell:
					h.set_meta("hellfire_burns", int(h.get_meta("hellfire_burns", 0)) + 1)
				_wound(h, null, "hellfire" if hell else "embers")

# --- The Drowned Sailor and the Plague Doctor ---------------------------------------------

const PUDDLE_MAX := 6
const MIASMA_RADIUS := 70.0
const MIASMA_LIFE := 9.0
const MIASMA_GROW := 1.6       # (matches HouseView.Miasma.GROW)
const MIASMA_EXPOSURE := 1.2   # seconds inside a cloud before it wounds
var puddles: Array = []        # [{node, pos, until}]
var _footprints: Array = []    # [{node, until}]
var _sailor_t := {"step": 0.0, "puddle": 6.0, "drip": 2.0, "whisper": 25.0, "creak": 8.0, "lights": 0.0}
var _plague_t := {"breath": 3.0, "bottle": 7.0, "cloud": 0.0}

## Salt water follows it: wet footprints, puddles, drips, creaking timbers, and
## lights that stutter as it passes. None of it is evidence.
func sailor_tick(c: Creature, delta: float) -> void:
	for k in _sailor_t:
		_sailor_t[k] -= delta
	for f in _footprints.duplicate():
		if elapsed >= f["until"]:
			_footprints.erase(f)
			_remove_sprite(f["node"])
	for pd in puddles.duplicate():
		if elapsed >= pd["until"]:
			puddles.erase(pd)
			_remove_sprite(pd["node"])
	if c.state == "banished" or c.state == "bound":
		return
	var indoors: bool = not map.room(c.room_id).get("outdoor", true)
	var moving := c.path_i < c.path.size()
	if moving and indoors and _sailor_t["step"] <= 0.0:
		_sailor_t["step"] = 0.6 if c.is_hunting() else 1.3
		var side := Vector2.from_angle(c.token.facing + PI * 0.5) * (5.0 if _footprints.size() % 2 == 0 else -5.0)
		var node := _item_sprite("items/wet_footprint.png", c.position + side, 18.0, c.token.facing + PI * 0.5)
		_footprints.append({"node": node, "until": elapsed + 26.0})
		if _footprints.size() > 24:
			_remove_sprite(_footprints.pop_front()["node"])
	if indoors and _sailor_t["puddle"] <= 0.0 and c.state == "roam":
		_sailor_t["puddle"] = rng.randf_range(9.0, 15.0)
		var cell := map.nearest_walkable(HouseMap.to_cell(c.position))
		var pos := HouseMap.cell_center(cell) + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
		puddles.append({"node": _item_sprite("items/puddle.png", pos, 36.0), "pos": pos, "until": elapsed + 70.0})
		if puddles.size() > PUDDLE_MAX:
			_remove_sprite(puddles.pop_front()["node"])
	if _sailor_t["drip"] <= 0.0:
		_sailor_t["drip"] = rng.randf_range(2.5, 4.5)
		sound_at("water_drip", c.position, -10.0, rng.randf_range(0.9, 1.1), 700.0)
	if _sailor_t["creak"] <= 0.0 and moving:
		_sailor_t["creak"] = rng.randf_range(7.0, 12.0)
		sound_at("wood_creak", c.position, -8.0, rng.randf_range(0.85, 1.05), 900.0)
	if _sailor_t["whisper"] <= 0.0:
		_sailor_t["whisper"] = rng.randf_range(28.0, 45.0)
		sound_at("sea_whisper", c.position, -6.0, 1.0, 1000.0)
	if _sailor_t["lights"] <= 0.0:
		for l in view.lights:
			if l["on"] and l["kind"] != "moon" and l["pos"].distance_to(c.position) < 170.0:
				_sailor_t["lights"] = 2.4
				creature_fx("lights", c.position)
				break

## A fair place for the Drowned Sailor to rise from: one of its puddles, far
## enough from every hunter (the same rule as any hunt start). INF if none.
func _fair_puddle(alive: Array) -> Vector2:
	var fair: Array = []
	for pd in puddles:
		var ok := true
		for h: Player in alive:
			if pd["pos"].distance_to(h.global_position) < 300.0:
				ok = false
		if ok:
			fair.append(pd["pos"])
	return Vector2.INF if fair.is_empty() else fair[rng.randi_range(0, fair.size() - 1)]

## Rasping breath and clinking glass while it makes its rounds; while it hunts,
## a cloud of miasma every few seconds where it has just walked.
func plague_tick(c: Creature, delta: float) -> void:
	for k in _plague_t:
		_plague_t[k] -= delta
	if c.state == "banished" or c.state == "bound":
		return
	if _plague_t["breath"] <= 0.0:
		_plague_t["breath"] = rng.randf_range(5.0, 8.0) if not c.is_hunting() else 2.5
		sound_at("plague_breath", c.position, -8.0, rng.randf_range(0.9, 1.05), 800.0)
	if _plague_t["bottle"] <= 0.0:
		_plague_t["bottle"] = rng.randf_range(9.0, 15.0)
		sound_at("bottle_clink", c.position, -8.0, rng.randf_range(0.9, 1.15), 800.0)
	if c.state == "hunt" and _plague_t["cloud"] <= 0.0:
		_plague_t["cloud"] = 3.2
		spawn_miasma(c.position)

func spawn_miasma(pos: Vector2) -> void:
	hazards.append({"pos": pos, "born": elapsed, "until": elapsed + MIASMA_LIFE, "radius": MIASMA_RADIUS, "node": null, "light": null, "kind": "miasma"})
	creature_fx("miasma", pos, {"r": MIASMA_RADIUS, "dur": MIASMA_LIFE})
	sound_at("plague_breath", pos, -4.0, 0.7, 900.0)

## Lingering in a cloud (it swells over 1.6 s) wounds after a moment, with the
## same grace period as fire so a single cloud never counts twice.
func _miasma_tick(delta: float) -> void:
	for h: Player in living_hunters():
		var inside := false
		for hz in hazards:
			if hz.get("kind", "") != "miasma" or elapsed >= hz["until"]:
				continue
			var r: float = hz["radius"] * clampf((elapsed - hz["born"]) / MIASMA_GROW, 0.15, 1.0)
			if h.global_position.distance_to(hz["pos"]) < r:
				inside = true
				break
		var t := float(h.get_meta("miasma_t", 0.0))
		t = t + delta if inside else maxf(0.0, t - delta * 2.0)
		h.set_meta("miasma_t", t)
		if inside and t >= MIASMA_EXPOSURE and h.invuln <= 0.0 and float(h.get_meta("ember_cd", 0.0)) <= 0.0:
			h.set_meta("ember_cd", 4.0)
			h.set_meta("miasma_t", 0.0)
			sound_to(h, "plague_breath", 0.0, 1.3)
			tell(h, "The miasma burns your lungs!", "tokens/plague_doctor.png")
			_wound(h, null, "miasma")

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
	if in_abyss(p):
		tell(p, "Nothing you set down here would stay. Wait for the way back.", "icons/ui_skull.png", true)
		return false
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
	if c == null or c.state == "banished" or in_abyss(c):
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
	if in_abyss(c) or in_abyss(p):
		tell(p, "Your blow passes through it like smoke. Nothing can be ended in the Abyss.", Defs.EQUIPMENT[item]["icon"], true)
		return
	var to := c.position - p.global_position
	var reach := to.length() < STRIKE_REACH and (absf(angle_difference(p.aim_angle, to.angle())) < 1.2 or to.length() < 30.0)
	if not reach:
		tell(p, "You strike at empty air.", Defs.EQUIPMENT[item]["icon"], true)
		return
	attempt_vanquish(p, identity, item)

## Choosing a suspect is never an attempt. Tab only cycles through the entities
## the hunter's own notes still allow (found evidence and their rule-outs).
func cycle_suspect(p: Player, dir: int = 1) -> void:
	if is_harbinger():
		return
	var options := [""] + Defs.candidates(p.journal)
	var i := options.find(p.suspect)
	if i < 0:
		i = 0
	p.suspect = options[(i + dir + options.size()) % options.size()]
	sound_to(p, "ui_click", -8.0)
	record_event("suspect", {"actor": p.actor_id, "id": p.suspect})
	if p.is_local:
		hud.refresh()
		hud.show_suspect_picker()

## The hunter's notes changed. A suspect they now contradict gives way to the next
## entity that still fits (or to none, if nothing does).
func refit_suspect(p: Player) -> void:
	if p.suspect == "" or is_harbinger() or Defs.fits(p.suspect, p.journal):
		return
	var was := p.suspect
	var order := Defs.ORDINARY_CREATURES
	var start := order.find(was)
	p.suspect = ""
	for k in range(1, order.size() + 1):
		var id: String = order[(start + k) % order.size()]
		if Defs.fits(id, p.journal):
			p.suspect = id
			break
	record_event("suspect", {"actor": p.actor_id, "id": p.suspect})
	tell(p, "Your notes rule out %s. %s" % [Defs.creature_name(was), ("Now suspecting %s." % Defs.creature_name(p.suspect)) if p.suspect != "" else "No entity fits what you have noted."], "icons/ui_quill.png", true)
	if p.is_local:
		hud.refresh()

## A hunter marked / unmarked evidence as ruled out (the local HUD, or a client's
## message): keep the host's copy of their notes in step and refit the suspect.
func set_ruled_out(p: Player, id: String, on: bool) -> void:
	if p == null or p.journal.has(id) or not Defs.EVIDENCE.has(id):
		return
	if on:
		p.journal.ruled_out[id] = true
	else:
		p.journal.ruled_out.erase(id)
	refit_suspect(p)

func on_ruled_out_changed(id: String) -> void:
	refit_suspect(player)

func apply_remote_rule_out(peer: int, id: String, on: bool) -> void:
	var h := hunter_by_peer(peer)
	if h and not h.is_local:
		set_ruled_out(h, id, on)

# --- Rites ---------------------------------------------------------------------------

func _room_has(type: String, room_id: String) -> bool:
	for it in placed:
		if it["type"] == type and it["room"] == room_id:
			return true
	return false

## Every ghost's rite needs certain things laid in its room (holy water: carried).
func _rite_requirement_met(p: Player) -> bool:
	var needs: Array = Defs.CREATURES.get(p.suspect, {}).get("rite_needs", [])
	if needs.is_empty():
		return false
	for n in needs:
		if n == "holy_water":
			if int(p.charges.get("holy_water", 0)) <= 0:
				return false
		elif not _room_has(n, p.room_id):
			return false
	return true

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
	if in_abyss(p):
		tell(p, "No rite can be finished in the Abyss.", "icons/ui_skull.png", true)
		return false
	if in_abyss(creature):
		tell(p, "The rite finds nothing to bind — it has been torn away into the Abyss.", "icons/ui_skull.png", true)
		return false
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
		var d: Dictionary = Defs.CREATURES[p.suspect]
		var needs: Array = d["rite_needs"]
		var words: Array = needs.map(func(n): return "a flask of holy water" if n == "holy_water" else ("salt" if n == "salt" else "the " + Defs.EQUIPMENT[n]["name"]) + " in this room")
		tell(p, "The %s needs %s." % [d["rite_name"], " and ".join(words)], Defs.EQUIPMENT[needs[0]]["icon"], true)
		return false
	return true

func perform_rite(p: Player) -> void:
	if not can_begin_rite(p):
		return
	if is_harbinger():
		record_event("final_rite", {"actor": p.actor_id})
		_victory(p)
		return
	if "holy_water" in Defs.CREATURES[p.suspect].get("rite_needs", []):
		p.charges["holy_water"] = maxi(0, int(p.charges["holy_water"]) - 1)   # rites of water spend a flask
		p.equipment.changed.emit()
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
		pickups.append({"kind": "sigil", "sigil": s, "node": node, "pos": pos, "label": "Light Sigil Candle (hold)", "icon": "items/sigil_candle_unlit.png", "hold": 1.0})
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

## What [E] / [Space] would act on: the nearest candidate, slightly favouring what
## the hunter faces, so the same door / item is chosen every time.
func find_interactable(p: Player, pos: Vector2) -> Dictionary:
	var cands: Array = []
	for it in pickups:
		if it["kind"] == "sigil" and it["sigil"]["lit"]:
			continue
		cands.append([it, 46.0])
	for it in placed:
		if it["type"] in ["ghost_book", "crucifix"] and it["owner"] == p:
			cands.append([{"kind": "retrieve", "item": it, "pos": it["pos"], "icon": Defs.EQUIPMENT[it["type"]]["icon"],
				"label": "Retrieve " + Defs.EQUIPMENT[it["type"]]["name"], "hold": 0.0}, 46.0])
	for i in view.lights.size():
		if view.can_extinguish(i) and not view.lights[i]["on"]:
			var what: String = {"candle": "Candle", "lamp": "Lamp", "hearth": "Fire", "room": "Lamp"}.get(view.lights[i]["kind"], "Flame")
			cands.append([{"kind": "relight", "i": i, "pos": view.lights[i]["pos"], "icon": "items/sigil_candle_lit.png",
				"label": "Relight " + what, "hold": 0.7}, 64.0])
	for i in view.doors.size():
		var dc: Vector2 = HouseMap.cell_center(view.doors[i]["cell"])
		var dopen: bool = view.doors[i]["open"]
		if dopen and _someone_in_doorway(i) and pos.distance_to(dc) < 30.0:
			continue   # never close a door on yourself
		cands.append([{"kind": "door", "i": i, "pos": dc, "icon": "icons/ui_house.png",
			"label": "Close Door" if dopen else "Open Door", "hold": 0.0}, DOOR_REACH])
	var sc := map.nearest_stair(pos, STAIR_REACH)
	if sc != Vector2i(-99, -99):
		var dest := map.stair_target(sc)
		var down := map.floor_at(dest) < map.floor_at(HouseMap.cell_center(sc))
		cands.append([{"kind": "stairs", "cell": sc, "pos": HouseMap.cell_center(sc), "icon": "icons/ui_house.png",
			"label": "Use Stairs (Down)" if down else "Use Stairs (Up)", "hold": 0.0}, STAIR_REACH])
	var best := {}
	var bs := INF
	for c in cands:
		var it: Dictionary = c[0]
		var to: Vector2 = it["pos"] - pos
		var d := to.length()
		if d >= float(c[1]):
			continue
		var score := d - (10.0 * cos(angle_difference(p.aim_angle, to.angle())) if d > 4.0 else 10.0)
		if score < bs:
			bs = score
			best = it
	if best.is_empty() and int(p.resources.get("silverware", 0)) >= Defs.SILVERWARE_NEEDED:
		for f in map.furniture_with("melt"):
			if (f["rect"] as Rect2).grow(28.0).has_point(pos):
				return {"kind": "melt", "pos": (f["rect"] as Rect2).get_center(), "icon": "icons/eq_silver_stake.png",
					"label": "Melt Silverware (hold)", "hold": 2.0}
	return best

## Positions of pickups near pos (faint highlight), nearest first.
func nearby_pickups(pos: Vector2, radius: float = 140.0) -> Array:
	var out: Array = []
	for it in pickups:
		if it["kind"] == "sigil" and it["sigil"]["lit"]:
			continue
		if pos.distance_to(it["pos"]) < radius:
			out.append(it["pos"])
	out.sort_custom(func(a, b): return a.distance_to(pos) < b.distance_to(pos))
	return out.slice(0, 5)

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
		"relight":
			set_light(it["i"], true)
			add_investigation(p, 0, "relight")
		"door":
			set_door(it["i"], not view.doors[it["i"]]["open"])
		"stairs":
			_take_stairs(p, it["cell"])
		"keepsake":
			_examine_keepsake(p, it)

# --- Ending ----------------------------------------------------------------------------

func _victory(p: Player) -> void:
	if state != "playing":
		return
	vanquisher = p
	var blind := p.journal.active_entries().is_empty() and not meaningful_investigation(p) and p.wrong_attempts == 0
	state = "ending"
	_outcome = "vanquished"
	_end_t = 2.6
	close_abyss()
	if creature.is_hunting():
		creature.end_hunt()   # before banishing: the hunt is ended (and recorded) like any other
	creature.banish()
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

func _hunter_dies(p: Player, c: Creature = null) -> void:
	p.dead = true
	p.input_enabled = false
	p.token.modulate = Color(0.6, 0.1, 0.1)
	sound_to(p, "player_death", 2.0)
	record_event("death", {"actor": p.actor_id})
	var death_room := map.room_at(p.global_position, p.room_id)
	if death_room != "" and not AbyssArena.contains(p.global_position):
		var sd := rng.randi()
		view.blood_splatter(death_room, p.global_position, sd)
		record_event("splatter", {"room": death_room, "x": p.global_position.x, "y": p.global_position.y, "seed": sd})
	_maybe_quip_shove_victim(p)
	if c:
		c.end_hunt()
	if not multiplayer_match:
		state = "ending"
		_outcome = "perished"
		_end_t = 2.8
		close_abyss()
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
		close_abyss()
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
		"voodoo_uses": int(p.get_meta("voodoo_uses", 0)), "npcs_burned": npcs_burned,
		"abyss_trips": int(p.get_meta("abyss_trips", 0)), "abyss_escapes": int(p.get_meta("abyss_escapes", 0)),
		"hellfire_burns": int(p.get_meta("hellfire_burns", 0)),
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
	Game.start_run(house_id, -1, creature_override, difficulty, blood_moon, setup_info)   # same resolved setup

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
		"cam": eq.current() == "orb_camera", "nd": snappedf(eq.needle, 0.01), "pi": eq.interact_icon,
		"ip": [] if eq.interact_pos == Vector2.INF else [snappedf(eq.interact_pos.x, 0.1), snappedf(eq.interact_pos.y, 0.1)],
		"near": eq.near_items.map(func(v): return [snappedf(v.x, 0.1), snappedf(v.y, 0.1)])}

## A client's own movement report. Positions are client-predicted; the host
## rejects impossible jumps (teleports, speed hacks) and corrects the client.
func apply_remote_input(peer: int, pos: Vector2, aim: float, flags: int, mask: int, counters: PackedByteArray) -> void:
	var h := hunter_by_peer(peer)
	if h == null or h.dead or _paused:
		return   # (press counters are cumulative, so nothing is lost)
	if h.has_meta("abyss"):
		if AbyssArena.contains(pos) and pos.distance_to(h.global_position) < 120.0:
			h.global_position = pos
		h.aim_angle = aim
		h.flashlight_on = flags & 1 == 1
		h.sprinting = flags & 2 == 2
		h.input.apply_remote(mask, counters)
		return
	if float(h.get_meta("dragged_until", -1.0)) > elapsed:
		h.global_position = pos   # being dragged by the host's own sequence
		h.aim_angle = aim
		return
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
		close_abyss()
