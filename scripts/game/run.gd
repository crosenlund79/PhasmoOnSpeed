class_name Run
extends Node2D
## One investigation run: builds the house, spawns actors, owns the run state
## (time, threat, wounds, attempts), resolves vanquishing, records the replay
## and hands a summary to Game when the run ends.

const GRACE_PERIOD := 40.0         # no ordinary hunts before this (seconds)
const THREAT_PER_SECOND := 0.22
const MEANINGFUL_INVESTIGATION := 4
const HARBINGER_AFTER_RECKLESS := 2
const HARBINGER_AFTER_WRONG := 3
const STRIKE_REACH := 62.0
const CAMERA_ZOOM := 1.55

var house_id := ""
var run_seed := 0
var creature_override := ""
var rng := RandomNumberGenerator.new()
var map: HouseMap
var world: Node2D
var view: HouseView
var world_text: CanvasLayer
var camera: Camera2D
var hud: Node
var player: Player
var creature: Creature
var occupants: Array = []
var phenomena: Phenomena
var equipment: EquipmentController
var journal := Journal.new()
var recorder: ReplayRecorder

var state := "playing"     # playing, ending
var elapsed := 0.0
var threat := 0.0
var original_creature := ""
var suspect := ""
var investigation := 0
var wrong_attempts := 0
var reckless_attempts := 0
var incomplete_attempts := 0
var attempts: Array = []
var hunts_total := 0
var clean_hunts := 0
var harbinger_summoned := false
var hunt_roll_t := 2.0
var forced_hunt_t := -1.0
var forced_hunt_reckless := false
var occupants_fled := false
var pickups: Array = []        # {kind, res, node, pos, label, hold}
var placed: Array = []         # {type, node, pos, room, burns}
var sigils: Array = []         # {node, light, lit, room}
var _uid := 0
var _garlic_warned_hunt := -1
var _end_t := 0.0
var _outcome := ""
var _paused := false

func setup(p_house: String, p_seed: int, p_override: String) -> void:
	house_id = p_house
	run_seed = p_seed if p_seed >= 0 else int(Time.get_unix_time_from_system() * 1000.0) % 2147483647
	creature_override = p_override
	rng.seed = run_seed

func next_uid() -> int:
	_uid += 1
	return _uid

func _ready() -> void:
	map = HouseMap.from_data(Game.house(house_id))
	recorder = ReplayRecorder.new(house_id, run_seed)
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	view = HouseView.new()
	view.build(map, true, true)
	world.add_child(view)
	world_text = CanvasLayer.new()
	world_text.layer = 1
	world_text.follow_viewport_enabled = true
	add_child(world_text)
	phenomena = Phenomena.new()
	phenomena.setup(self)
	world.add_child(phenomena)
	_spawn_player()
	_choose_creature()
	_place_resources()
	_spawn_occupants()
	equipment = EquipmentController.new()
	add_child(equipment)
	equipment.setup(self, player)
	hud = preload("res://scripts/ui/hud.gd").new()
	add_child(hud)
	hud.setup(self)
	journal.discovered.connect(hud.on_discovered)
	Sfx.stop_loop("music", 0.8)
	Sfx.start_loop("ambience", "ambience_house", -6.0, 1.5)
	recorder.event(0.0, "start", {"house": house_id})
	hud.toast(map.name + " — something is here.", "icons/ui_house.png")
	if int(SaveData.data.get("runs_started", 0)) <= 3:
		# Brief onboarding for the first few runs; never blocks play.
		var tw := create_tween()
		tw.tween_interval(3.0)
		tw.tween_callback(func(): toast("Evidence you observe is written in your journal automatically.", "icons/ui_quill.png", true))
		tw.tween_interval(3.0)
		tw.tween_callback(func(): toast("Press H for controls. Two wounds and you perish.", "icons/ui_skull.png", true))

func _spawn_player() -> void:
	player = Player.new()
	player.run = self
	player.position = HouseMap.cell_center(map.spawn_cell)
	player.room_id = map.room_at(player.position)
	view.actor_layer.add_child(player)
	camera = Camera2D.new()
	camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 9.0
	# Centre the investigator in the area left of the journal panel.
	camera.offset = Vector2(145.0 / CAMERA_ZOOM, 0.0)
	camera.limit_left = -60
	camera.limit_top = -60
	camera.limit_right = int(map.world_size().x) + 60 + int(300.0 / CAMERA_ZOOM)
	camera.limit_bottom = int(map.world_size().y) + 110
	player.add_child(camera)
	recorder.register_actor(player.actor_id, "player", "tokens/investigator.png", 40.0)

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
	recorder.register_actor(creature.actor_id + ("h" if type_id == "harbinger" else ""), "creature", creature.current_token(), creature.token.diameter)
	recorder.event(elapsed, "creature", {"actor": _creature_actor_id(), "type": type_id, "lair": lair})

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
	recorder.event(elapsed, "decal", {"id": s.name, "sprite": path, "x": pos.x, "y": pos.y, "rot": 0.0, "size": size})
	return s

func _remove_sprite(s: Node) -> void:
	if is_instance_valid(s):
		recorder.event(elapsed, "decal_remove", {"id": s.name})
		s.queue_free()

func _spawn_occupants() -> void:
	var tokens := ["tokens/occupant_a.png", "tokens/occupant_b.png", "tokens/occupant_c.png"]
	var rooms: Array = map.indoor_rooms().filter(func(r): return r["id"] != creature.lair_room)
	for i in int(map.data.get("npcs", 2)):
		var o := Occupant.new()
		var r: Dictionary = rooms[rng.randi_range(0, rooms.size() - 1)]
		o.setup(self, "npc_%d" % (i + 1), tokens[i % tokens.size()], HouseMap.cell_center(map.random_free_cell(r["id"], rng)))
		view.actor_layer.add_child(o)
		occupants.append(o)
		recorder.register_actor(o.actor_id, "npc", o.token_path, 36.0)

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
	player.room_id = map.room_at(player.global_position, player.room_id)
	equipment.process_input(delta)
	equipment.update_tools(delta)
	_update_threat(delta)
	_update_defences(delta)
	_record(delta)

func _record(delta: float) -> void:
	var actors := {}
	actors[player.actor_id] = [player.global_position, player.token.facing, 0.0 if player.dead else 1.0, "tokens/investigator.png"]
	if creature:
		actors[_creature_actor_id()] = [creature.position, creature.token.facing, creature.modulate.a, creature.current_token()]
	for o in occupants:
		actors[o.actor_id] = [o.position, o.token.facing, o.modulate.a, o.token_path]
	recorder.tick(elapsed, delta, actors)

func _update_threat(delta: float) -> void:
	threat = minf(100.0, threat + THREAT_PER_SECOND * delta)
	if creature == null or creature.state != "roam" or creature.cooldown_t > 0.0:
		return
	if forced_hunt_t > 0.0:
		forced_hunt_t -= delta
		if forced_hunt_t <= 0.0:
			trigger_hunt(forced_hunt_reckless)
		return
	var is_harbinger := creature.type_id == "harbinger"
	if not is_harbinger and elapsed < GRACE_PERIOD:
		return
	hunt_roll_t -= delta
	if hunt_roll_t > 0.0:
		return
	hunt_roll_t = 2.0
	var threshold: float = creature.def["hunt_threshold"]
	if threat < threshold:
		return
	var p := 0.6 if is_harbinger else 0.22 + (threat - threshold) / 120.0
	if rng.randf() < p:
		trigger_hunt(false)

func _update_defences(delta: float) -> void:
	if creature == null or not creature.is_hunting():
		return
	if creature.is_ghost_like():
		for it in placed:
			if it["type"] == "salt" and creature.position.distance_to(it["pos"]) < 30.0:
				creature.slowed_t = 2.0
	if creature.type_id == "vampire" and player.has_resource("garlic") and creature.position.distance_to(player.global_position) < 105.0:
		creature.weakened_t = 1.5
		var away := (creature.position - player.global_position).normalized()
		creature.position += away * 90.0 * delta
		if _garlic_warned_hunt != creature.hunt_count:
			_garlic_warned_hunt = creature.hunt_count
			toast("It recoils from the garlic!", "icons/eq_garlic.png")
			Sfx.play_at("vampire_hiss", creature.position, world)

func add_threat(amount: float, reason: String) -> void:
	threat = clampf(threat + amount, 0.0, 100.0)
	recorder.event(elapsed, "threat", {"amount": amount, "reason": reason})

func add_investigation(points: int, reason: String) -> void:
	investigation += points
	recorder.event(elapsed, "investigate", {"points": points, "reason": reason})

func meaningful_investigation() -> bool:
	return investigation >= MEANINGFUL_INVESTIGATION or not journal.active_entries().is_empty()

func record_event(type: String, payload: Dictionary = {}) -> void:
	recorder.event(elapsed, type, payload)

# --- Evidence ------------------------------------------------------------------------

## Registers a genuine discovery. Only the current entity's phenomena call this.
func discover(evidence_id: String, room_id: String) -> void:
	if state != "playing" or room_id == "" or not (evidence_id in phenomena.evidence):
		return
	if journal.has(evidence_id):
		return
	if journal.record(evidence_id, elapsed, room_id, map.room_name(room_id)):
		Sfx.play("pencil_scribble", 0.0, 1.0, 0.4)
		add_threat(4.0, "evidence")
		add_investigation(3, "evidence")
		recorder.event(elapsed, "evidence", {"id": evidence_id, "room": room_id, "room_name": map.room_name(room_id)})

func placed_book() -> Node2D:
	for it in placed:
		if it["type"] == "ghost_book":
			return it["node"]
	return null

func on_book_written(book: Sprite2D) -> void:
	book.texture = Art.tex("items/ghost_book_written.png")
	recorder.event(elapsed, "decal_swap", {"id": book.name, "sprite": "items/ghost_book_written.png"})

func vampire_bite() -> void:
	var candidates: Array = occupants.filter(func(o): return o.state != "flee" and o.state != "gone" and not o.bitten)
	if candidates.is_empty():
		return
	var o: Occupant = candidates[rng.randi_range(0, candidates.size() - 1)]
	o.bite()
	recorder.event(elapsed, "bite", {"actor": o.actor_id})

func on_transform(c: Creature, f: String) -> void:
	recorder.event(elapsed, "transform", {"form": f})

func on_occupant_gone(o: Occupant) -> void:
	recorder.event(elapsed, "npc_gone", {"actor": o.actor_id})

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
	var s: Sprite2D = best["sprite"]
	var base_rot := s.rotation
	var tw := create_tween()
	for i in 4:
		tw.tween_property(s, "rotation", base_rot + rng.randf_range(-0.08, 0.08), 0.05)
	tw.tween_property(s, "rotation", base_rot, 0.05)
	recorder.event(elapsed, "shake", {"index": best["index"]})

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
				player.crucifix_burns = it["burns"]
				Sfx.play_at("crucifix_burn", it["pos"], world, 2.0)
				toast("A crucifix flares and scorches — a hunt was prevented.", "icons/eq_crucifix.png")
				recorder.event(elapsed, "crucifix_burn", {"x": it["pos"].x, "y": it["pos"].y})
				if it["burns"] <= 0:
					it["node"].modulate = Color(0.35, 0.3, 0.3)
				creature.cooldown_t = 20.0
				add_threat(-15.0, "crucifix")
				return
	creature.begin_hunt(_fair_hunt_start(), reckless)

## Chooses where a hunt begins so that it is never unavoidable.
func _fair_hunt_start() -> Vector2:
	var pp := player.global_position
	var cpos := creature.position
	var vampire := creature.type_id == "vampire"
	if not vampire and cpos.distance_to(pp) >= 300.0:
		return cpos
	var best := cpos
	var best_score := -INF
	var rooms := map.indoor_rooms()
	for i in 48:
		var r: Dictionary = rooms[rng.randi_range(0, rooms.size() - 1)]
		var cells := map.free_cells(r["id"])
		if cells.is_empty():
			continue
		var p := HouseMap.cell_center(cells[rng.randi_range(0, cells.size() - 1)])
		var d := p.distance_to(pp)
		if d < 300.0 or d > 620.0:
			continue
		var score := -absf(d - 380.0)
		if vampire:
			# Ambush: from behind the investigator, out of the flashlight.
			var behind := absf(angle_difference(player.aim_angle, (p - pp).angle()))
			score += behind * 120.0
			if phenomena.is_lit(p, player):
				score -= 300.0
		if score > best_score:
			best_score = score
			best = p
	return best

func _on_hunt_started(c: Creature) -> void:
	hunts_total += 1
	view.flicker(Creature.WARN_TIME + 1.0, 1.0)
	view.set_darkness(HouseView.DARKNESS_HUNT, 1.2)
	Sfx.play("hunt_start", 0.0)
	match c.type_id:
		"werewolf": Sfx.play_at("werewolf_howl", c.position, world, 2.0)
		"vampire": Sfx.play_at("vampire_hiss", c.position, world, 0.0)
		"poltergeist", "shade": Sfx.play_at("ghost_wail", c.position, world, -2.0)
	Sfx.start_loop("hunt", "hunt_loop", -2.0, 1.0)
	hud.set_hunting(true)
	hud.toast("It is hunting! Break its line of sight.", "icons/ui_skull.png")
	recorder.event(elapsed, "hunt_start", {"reckless": c.hunt_reckless})
	if not occupants_fled:
		_occupants_flee()

func _on_hunt_ended(c: Creature, hit: bool) -> void:
	view.set_darkness(HouseView.DARKNESS_HARBINGER if harbinger_summoned else HouseView.DARKNESS, 1.5)
	Sfx.stop_loop("hunt", 1.2)
	hud.set_hunting(false)
	if not hit and not player.dead:
		if not c.hunt_reckless and c.type_id != "harbinger":
			clean_hunts += 1
		hud.toast("The hunt is over… for now.", "icons/ui_clock.png", true)
	threat = maxf(0.0, threat - 25.0)
	recorder.event(elapsed, "hunt_end", {"hit": hit})

func _occupants_flee() -> void:
	occupants_fled = true
	for o in occupants:
		o.flee()
	recorder.event(elapsed, "npc_flee", {})

func on_creature_contact(c: Creature, p: Player) -> void:
	if p.invuln > 0.0 or p.dead or state != "playing":
		return
	if p.blessed > 0.0 and c.is_ghost_like():
		c.stun(4.0 if c.type_id != "harbinger" else 2.5)
		p.invuln = 1.0
		toast("The blessing holds — it recoils from you!", "icons/eq_holy_water.png")
		Sfx.play("crucifix_burn", 0.0)
		recorder.event(elapsed, "blessing_repel", {})
		return
	p.wounds += 1
	c.hunt_hit = true
	recorder.event(elapsed, "attack", {"wounds": p.wounds})
	if p.wounds >= 2:
		_die()
		return
	p.invuln = Player.INVULN_AFTER_HIT
	Sfx.play("player_hurt", 0.0)
	hud.wound()
	toast("You are wounded. Once more and you are finished.", "icons/ui_heart_wounded.png")
	c.end_hunt()

# --- Defences & placement ---------------------------------------------------------------

func place_item(type: String, at: Vector2) -> bool:
	var cell := HouseMap.to_cell(at)
	if not map.walkable(cell):
		cell = HouseMap.to_cell(player.global_position)
	var pos := at if map.walkable(HouseMap.to_cell(at)) else player.global_position
	var sprite_path: String = {"ghost_book": "items/ghost_book_written.png" if phenomena.book_written else "items/ghost_book.png",
		"salt": "items/salt_pile.png", "crucifix": "items/crucifix_placed.png"}[type]
	var node := _item_sprite(sprite_path, pos, 28.0 if type != "salt" else 30.0)
	var room := map.room_at(pos, player.room_id)
	placed.append({"type": type, "node": node, "pos": pos, "room": room, "burns": player.crucifix_burns if type == "crucifix" else 0})
	Sfx.play("place_item", -4.0)
	add_investigation(1, "place:" + type)
	if room == (creature.lair_room if creature else ""):
		add_threat(1.0, "place_in_lair")
	return true

func splash_holy_water() -> void:
	Sfx.play("holy_water_splash", 0.0)
	player.blessed = 3.0
	recorder.event(elapsed, "holy_water", {"x": player.global_position.x, "y": player.global_position.y})
	var c := creature
	if c == null or c.state == "banished":
		return
	var to := c.position - player.global_position
	if to.length() < 125.0 and absf(angle_difference(player.aim_angle, to.angle())) < 0.9:
		if c.is_ghost_like():
			c.stun(6.0 if c.type_id != "harbinger" else 3.0)
			Sfx.play_at("crucifix_burn", c.position, world, 2.0)
			if c.is_visible_now() or c.is_hunting():
				toast("The holy water hisses — it recoils!", "icons/eq_holy_water.png")
			recorder.event(elapsed, "stun", {})
		elif c.is_visible_now():
			toast("It doesn't even flinch.", "icons/eq_holy_water.png")

func strike(item: String) -> void:
	Sfx.play("stake_strike", -2.0, rng.randf_range(0.9, 1.1), 0.2)
	recorder.event(elapsed, "strike", {"item": item})
	var identity: String = {"wooden_stake": "vampire", "silver_stake": "werewolf", "iron_nails": "shapeshifter"}[item]
	if item == "wooden_stake" and not player.has_resource("garlic"):
		toast("You'll need garlic to weaken it before the stake can bite.", "icons/eq_garlic.png", true)
		return
	var c := creature
	if c == null or c.state == "banished":
		return
	var to := c.position - player.global_position
	var reach := to.length() < STRIKE_REACH and (absf(angle_difference(player.aim_angle, to.angle())) < 1.2 or to.length() < 30.0)
	if not reach:
		toast("You strike at empty air.", Defs.EQUIPMENT[item]["icon"], true)
		return
	attempt_vanquish(identity, item)

func cycle_suspect() -> void:
	if creature and creature.type_id == "harbinger":
		return
	var options := [""] + Defs.PUBLIC_SUSPECTS
	suspect = options[(options.find(suspect) + 1) % options.size()]
	Sfx.play("ui_click", -8.0)
	recorder.event(elapsed, "suspect", {"id": suspect})
	hud.refresh()

# --- Rites ---------------------------------------------------------------------------

func _room_has(type: String, room_id: String) -> bool:
	for it in placed:
		if it["type"] == type and it["room"] == room_id:
			return true
	return false

func _rite_requirement_met() -> bool:
	match suspect:
		"shade": return _room_has("salt", player.room_id)
		"poltergeist": return _room_has("ghost_book", player.room_id)
	return false

func rite_prompt() -> String:
	if creature == null:
		return ""
	if creature.type_id == "harbinger":
		if creature.state == "bound" and player.global_position.distance_to(creature.position) < 175.0:
			return "[V] Hold to perform the Final Rite"
		return ""
	if suspect != "" and _rite_requirement_met():
		return "[V] Hold: " + ("Rite of Stillness" if suspect == "shade" else "Rite of Binding")
	return ""

func rite_hold_time() -> float:
	return 2.5 if creature and creature.type_id == "harbinger" else 1.5

func can_begin_rite() -> bool:
	if creature and creature.type_id == "harbinger":
		if creature.state != "bound":
			toast("The Harbinger cannot be banished until all three sigil candles burn.", "items/sigil_candle_lit.png", true)
			return false
		if player.global_position.distance_to(creature.position) >= 175.0:
			toast("Stand beside the bound Harbinger to perform the Final Rite.", "icons/ui_skull.png", true)
			return false
		return true
	if suspect == "":
		toast("Choose which ghost you suspect first (Tab).", "icons/ui_quill.png", true)
		return false
	if not _rite_requirement_met():
		if suspect == "shade":
			toast("The Rite of Stillness needs salt poured in this room.", "icons/eq_salt.png", true)
		else:
			toast("The Rite of Binding needs the Ghost Writing Book laid in this room.", "icons/eq_ghost_book.png", true)
		return false
	return true

func perform_rite() -> void:
	if not can_begin_rite():
		return
	if creature.type_id == "harbinger":
		recorder.event(elapsed, "final_rite", {})
		_victory()
		return
	attempt_vanquish(suspect, "rite")

## Resolves a genuine vanquishing attempt (identity guess + method).
func attempt_vanquish(identity: String, method: String) -> void:
	if state != "playing":
		return
	var truth := creature.type_id
	var informed := meaningful_investigation()
	var outcome := "wrong"
	if identity == truth:
		outcome = "success"
		if method == "rite" and player.room_id != creature.lair_room and player.global_position.distance_to(creature.position) > 140.0:
			outcome = "incomplete_room"
		elif truth == "shapeshifter" and creature.exposed_t <= 0.0:
			outcome = "incomplete_exposure"
	attempts.append({"time": elapsed, "identity": identity, "method": method, "outcome": outcome, "informed": informed, "room": player.room_id})
	recorder.event(elapsed, "attempt", {"identity": identity, "method": method, "outcome": outcome, "informed": informed})
	match outcome:
		"success":
			_victory()
		"incomplete_room":
			incomplete_attempts += 1
			add_threat(10.0, "incomplete")
			Sfx.play("ghost_wail", -6.0)
			toast("The rite echoes through empty rooms. It does not dwell here.", "icons/ui_quill.png")
		"incomplete_exposure":
			incomplete_attempts += 1
			add_threat(10.0, "incomplete")
			Sfx.play("shapeshift", 0.0)
			toast("The iron slides off borrowed skin. Expose its true form first.", "icons/eq_iron_nails.png")
		"wrong":
			wrong_attempts += 1
			if informed:
				add_threat(20.0, "wrong_attempt")
				Sfx.play("reckless_reaction", -6.0)
				view.flicker(1.5, 0.7)
				hud.toast("Wrong. Something in the house is angered.", "icons/ui_skull.png")
			else:
				_severe_reaction()
			if not harbinger_summoned and (reckless_attempts >= HARBINGER_AFTER_RECKLESS or wrong_attempts >= HARBINGER_AFTER_WRONG):
				_summon_harbinger()

func _severe_reaction() -> void:
	reckless_attempts += 1
	add_threat(40.0, "reckless")
	Sfx.play("reckless_reaction", 2.0)
	view.flicker(3.5, 1.0)
	hud.shake(0.6)
	hud.big_message("THE HOUSE NOTICED", "Something inhabiting this place saw what you did. The madness deepens.", Art.BLOOD, 3.2)
	recorder.event(elapsed, "reckless", {"count": reckless_attempts})
	if not occupants_fled:
		_occupants_flee()
	if creature.state == "roam":
		forced_hunt_t = 5.0
		forced_hunt_reckless = true
		creature.cooldown_t = 0.0

func _summon_harbinger() -> void:
	harbinger_summoned = true
	var old := creature
	recorder.event(elapsed, "harbinger", {"replaced": old.type_id})
	old.banish()
	old.set_process(false)
	var tw := create_tween()
	tw.tween_interval(1.7)
	tw.tween_callback(old.queue_free)
	phenomena.clear()
	journal.void_all()
	suspect = ""
	forced_hunt_t = -1.0
	Sfx.stop_loop("hunt", 0.3)
	Sfx.play("harbinger_arrival", 3.0)
	view.flicker(5.0, 1.0)
	view.set_darkness(HouseView.DARKNESS_HARBINGER, 2.0)
	hud.set_hunting(false)
	hud.shake(1.0)
	hud.big_message("THE HARBINGER HAS COME", "Your recklessness called something worse. All prior evidence is meaningless now.", Color(0.75, 0.88, 1.0), 4.5)
	if not occupants_fled:
		_occupants_flee()
	# The Harbinger appears far from the investigator and hunts almost immediately.
	var far: Array = map.indoor_rooms().filter(func(r): return map.room_center(r["id"]).distance_to(player.global_position) > 420.0)
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

func _light_sigil(s: Dictionary) -> void:
	s["lit"] = true
	s["node"].texture = Art.tex("items/sigil_candle_lit.png")
	recorder.event(elapsed, "decal_swap", {"id": s["node"].name, "sprite": "items/sigil_candle_lit.png"})
	s["light"].energy = 1.4
	s["light"].texture_scale = 0.8
	Sfx.play("candle_light", 0.0)
	var lit := sigils.filter(func(x): return x["lit"]).size()
	recorder.event(elapsed, "sigil", {"room": s["room"], "lit": lit})
	if lit >= sigils.size():
		creature.bind_at(map.room_center(creature.lair_room) if map.walkable(HouseMap.to_cell(map.room_center(creature.lair_room))) else HouseMap.cell_center(map.random_free_cell(creature.lair_room, rng)))
		Sfx.play("harbinger_arrival", -4.0, 0.8)
		hud.big_message("THE HARBINGER IS BOUND", "It waits in the %s. Perform the Final Rite beside it." % map.room_name(creature.lair_room), Color(0.75, 0.88, 1.0), 3.5)
		recorder.event(elapsed, "bound", {})
	else:
		toast("Sigil %d of %d burns." % [lit, sigils.size()], "items/sigil_candle_lit.png")

# --- Interaction -----------------------------------------------------------------------

func find_interactable(pos: Vector2) -> Dictionary:
	var best := {}
	var bd := 46.0
	for p in pickups:
		if p["kind"] == "sigil" and p["sigil"]["lit"]:
			continue
		var d: float = pos.distance_to(p["pos"])
		if d < bd:
			bd = d
			best = p
	for it in placed:
		if it["type"] in ["ghost_book", "crucifix"]:
			var d: float = pos.distance_to(it["pos"])
			if d < bd:
				bd = d
				best = {"kind": "retrieve", "item": it, "label": "Retrieve " + Defs.EQUIPMENT[it["type"]]["name"], "hold": 0.0}
	if best.is_empty() and int(player.resources.get("silverware", 0)) >= Defs.SILVERWARE_NEEDED:
		for f in map.furniture_with("melt"):
			if (f["rect"] as Rect2).grow(28.0).has_point(pos):
				return {"kind": "melt", "label": "Hold to melt silverware into a silver stake", "hold": 2.0}
	return best

func do_interact(it: Dictionary) -> void:
	if it.is_empty():
		return
	match it["kind"]:
		"resource":
			player.add_resource(it["res"])
			_remove_sprite(it["node"])
			pickups.erase(it)
			Sfx.play("pickup", -2.0)
			toast("Picked up " + Defs.EQUIPMENT[it["res"]]["name"] + ".", Defs.EQUIPMENT[it["res"]]["icon"], true)
			recorder.event(elapsed, "pickup", {"res": it["res"]})
			equipment.rebuild_slots()
		"retrieve":
			var item: Dictionary = it["item"]
			_remove_sprite(item["node"])
			placed.erase(item)
			if item["type"] == "ghost_book":
				player.book_placed = false
			else:
				player.charges["crucifix"] = 1
				player.crucifix_burns = item["burns"]
			Sfx.play("pickup", -2.0)
			equipment.rebuild_slots()
		"melt":
			player.take_resource("silverware", Defs.SILVERWARE_NEEDED)
			player.add_resource("silver_stake")
			Sfx.play("melt_silver", 0.0)
			toast("The silver runs and sets: a Silver Stake.", "icons/eq_silver_stake.png")
			recorder.event(elapsed, "melt", {})
			add_investigation(1, "melt")
			equipment.rebuild_slots()
			equipment.select(equipment.slots.find("silver_stake"))
		"sigil":
			_light_sigil(it["sigil"])
			pickups.erase(it)

# --- Ending ----------------------------------------------------------------------------

func _victory() -> void:
	if state != "playing":
		return
	var blind := journal.active_entries().is_empty() and not meaningful_investigation() and wrong_attempts == 0
	state = "ending"
	_outcome = "vanquished"
	_end_t = 2.6
	creature.banish()
	if creature.is_hunting():
		creature.end_hunt()
	Sfx.stop_loop("hunt", 0.4)
	Sfx.play("vanquish_success", 2.0)
	view.set_darkness(Color(0.42, 0.42, 0.5), 2.0)
	if blind:
		recorder.event(elapsed, "audacity", {})
		hud.big_message("THE HOUSE FALLS SILENT", "…then something laughs. It will remember your audacity.", Art.GOLD, 2.6)
	else:
		hud.big_message("VANQUISHED", "", Art.GOLD, 2.4)
	recorder.event(elapsed, "vanquish", {"creature": creature.type_id})

func _die() -> void:
	player.dead = true
	state = "ending"
	_outcome = "perished"
	_end_t = 2.8
	Sfx.stop_loop("hunt", 0.4)
	Sfx.play("player_death", 2.0)
	view.set_darkness(Color(0.05, 0.02, 0.02), 1.5)
	player.token.modulate = Color(0.6, 0.1, 0.1)
	hud.big_message("PERISHED", "", Art.BLOOD, 2.6)
	recorder.event(elapsed, "death", {})

func build_summary() -> Dictionary:
	var final_creature := creature.type_id
	var entries := journal.active_entries()
	var true_ev := 0
	for e in entries:
		if e["id"] in Defs.CREATURES[final_creature]["evidence"]:
			true_ev += 1
	var all_entries: Array = []
	for e in journal.entries:
		all_entries.append({"id": e["id"], "time": snappedf(e["time"], 0.01), "room_id": e["room_id"], "room_name": e["room_name"], "void": e["void"]})
	var transformations := 0
	if creature.type_id == "shapeshifter":
		transformations = creature.transformations
	elif original_creature == "shapeshifter":
		for ev in recorder.data["events"]:
			if ev[1] == "transform":
				transformations += 1
	var summary := {
		"house": house_id, "house_name": map.name, "seed": run_seed,
		"original_creature": original_creature, "creature": final_creature,
		"vanquished": _outcome == "vanquished", "time": snappedf(elapsed, 0.01),
		"evidence": all_entries, "evidence_ids": entries.map(func(e): return e["id"]),
		"true_evidence": true_ev, "incorrect_attempts": wrong_attempts, "reckless_attempts": reckless_attempts,
		"incomplete_attempts": incomplete_attempts, "attempts": attempts, "wounds": player.wounds,
		"clean_hunts_survived": clean_hunts, "hunts": hunts_total, "harbinger": harbinger_summoned,
		"blind": _outcome == "vanquished" and entries.is_empty() and not meaningful_investigation() and wrong_attempts == 0,
		"transformations": transformations, "investigation": investigation,
		"occurrences": journal.occurrences, "rules_version": Scoring.RULES_VERSION,
	}
	var score := Scoring.compute(summary)
	summary["score"] = score["total"]
	summary["score_lines"] = score["lines"]
	summary["event_digest"] = recorder.digest()
	return summary

func _finish() -> void:
	if _outcome == "":
		return
	var outcome := _outcome
	Sfx.stop_all_loops()
	var summary := build_summary()
	_outcome = ""
	var replay := recorder.finish(elapsed, outcome)
	Game.finish_run(summary, replay)

func restart() -> void:
	Sfx.stop_all_loops()
	Game.start_run(house_id)

func set_paused(p: bool) -> void:
	_paused = p
	get_tree().paused = p

func toast(text: String, icon: String = "", quiet: bool = false) -> void:
	hud.toast(text, icon, quiet)

func big_message(title: String, sub: String, color: Color, dur: float) -> void:
	hud.big_message(title, sub, color, dur)
