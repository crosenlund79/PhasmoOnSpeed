class_name Phenomena
extends Node2D
## Everything the entity leaves behind (EMF hotspots, temperatures, handprints,
## writing, orbs, physical clues, reflections, voices) and the observation checks
## that turn them into genuine journal discoveries. Only the CURRENT entity's
## phenomena exist; replacement by the Harbinger clears them.

const DETECT_HZ := 10.0
const CLUE_RANGE := 150.0
const FLASH_RANGE := 310.0
const FLASH_HALF_ANGLE := 0.42
const UV_RANGE := 290.0
const UV_HALF_ANGLE := 0.36

var run: Run
var map: HouseMap
var rng: RandomNumberGenerator
var source := ""               # creature type these phenomena belong to
var evidence: Array = []       # evidence ids of the source creature
var temps := {}
var hotspots: Array = []       # {pos, level, ttl, room}
var uv_prints: Array = []      # {pos, node, room}
var clues: Array = []          # {evidence, pos, node, room}
var orbs: Array = []           # Sprite2D on the unlit layer
var mirror_ttl := {}           # mirror index -> seconds remaining
var voices: Array = []         # {pos, room, ttl}
var book_write_t := -1.0
var book_written := false     # any book written (books keep their pages when moved)
var written_books := {}        # book Sprite2D -> true
var _interact_t := 0.0
var _drop_t := 0.0
var _fur_t := 0.0
var _claw_t := 0.0
var _voice_t := 0.0
var _skin_t := 0.0
var _bite_t := -1.0
var _detect_acc := 0.0
var _uv_material: CanvasItemMaterial
var _t := 0.0

func setup(p_run: Run) -> void:
	run = p_run
	map = run.map
	rng = run.rng
	_uv_material = CanvasItemMaterial.new()
	_uv_material.light_mode = CanvasItemMaterial.LIGHT_MODE_LIGHT_ONLY

func start_for(c: Creature) -> void:
	clear()
	source = c.type_id
	evidence = Defs.CREATURES[source]["evidence"]
	for r in map.rooms:
		# Ordinary rooms and the outdoors sit close together (12–15 °C) so the entity's
		# cold room stands out; only freezing ghosts drop it below zero.
		temps[r["id"]] = rng.randf_range(12.0, 14.5) if r["outdoor"] else rng.randf_range(12.5, 15.0)
	if source != "harbinger":
		temps[c.lair_room] = rng.randf_range(-7.0, -2.5) if "freezing" in evidence else rng.randf_range(4.0, 8.0)
	_interact_t = rng.randf_range(4.0, 8.0)
	_drop_t = rng.randf_range(4.0, 7.0)
	_fur_t = rng.randf_range(15.0, 25.0)
	_claw_t = rng.randf_range(12.0, 20.0)
	_voice_t = rng.randf_range(18.0, 30.0)
	_skin_t = rng.randf_range(20.0, 30.0)
	if Defs.is_ghost(source) and "orbs" in evidence:
		for i in 5:
			_add_orb(c.lair_room)
	match source:
		"vampire":
			for i in 2:
				_add_clue("coffin_soil", c.lair_room, false)
			_bite_t = rng.randf_range(22.0, 50.0)
		"werewolf":
			for i in 2:
				_add_clue("claw_marks", c.lair_room, true)
			for i in 2:
				_add_clue("fur", c.lair_room, false)
		"shapeshifter":
			for i in 2:
				_add_clue("shed_skin", c.lair_room, false)

## Removes every phenomenon (used when the Harbinger replaces the entity).
func clear() -> void:
	for list in [uv_prints, clues]:
		for item in list:
			if is_instance_valid(item["node"]):
				run.record_event("decal_remove", {"id": item["node"].name})
				item["node"].queue_free()
		list.clear()
	for o in orbs:
		o.queue_free()
	orbs.clear()
	run.record_event("orb_clear", {})
	hotspots.clear()
	voices.clear()
	for idx in mirror_ttl:
		run.view.show_mirror_overlay(idx, null, 0.0)
	mirror_ttl.clear()
	temps.clear()
	book_write_t = -1.0
	written_books.clear()
	_bite_t = -1.0
	source = ""
	evidence = []

const CLUE_SPRITES := {
	"coffin_soil": "items/coffin_soil.png", "claw_marks": "items/claw_marks.png", "fur": "items/fur_tuft.png",
	"footprints": "items/paw_print.png", "blood_drops": "items/blood_drops.png", "shed_skin": "items/shed_skin.png",
}

func _decal(sprite_path: String, pos: Vector2, rot: float, size: float, uv: bool = false) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Art.tex(sprite_path)
	s.position = pos
	s.rotation = rot
	var k := size / maxf(1.0, s.texture.get_size().x)
	s.scale = Vector2(k, k)
	s.name = "decal_%d" % run.next_uid()
	run.view.decal_layer.add_child(s)
	if uv:
		s.material = _uv_material
		s.light_mask = 2
	run.record_event("decal", {"id": s.name, "sprite": sprite_path, "x": pos.x, "y": pos.y, "rot": rot, "size": size, "uv": uv})
	return s

func _add_clue(ev: String, room_id: String, wall_side: bool, at: Vector2 = Vector2.INF, rot: float = INF) -> void:
	var pos := at
	if pos == Vector2.INF:
		var cand: Array = map.wall_adjacent_cells(room_id) if wall_side else map.free_cells(room_id)
		if cand.is_empty():
			cand = map.free_cells(room_id, false)
		if cand.is_empty():
			return
		pos = HouseMap.cell_center(cand[rng.randi_range(0, cand.size() - 1)]) + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
	if rot == INF:
		rot = rng.randf() * TAU
	var size := 26.0 if ev == "footprints" else 30.0
	var node := _decal(CLUE_SPRITES[ev], pos, rot, size)
	clues.append({"evidence": ev, "pos": pos, "node": node, "room": room_id})
	if ev != "footprints" and ev != "blood_drops":
		run.shimmer(room_id)

func _count(ev: String) -> int:
	var n := 0
	for c in clues:
		if c["evidence"] == ev:
			n += 1
	return n

func _drop_oldest(ev: String) -> void:
	for i in clues.size():
		if clues[i]["evidence"] == ev:
			run.record_event("decal_remove", {"id": clues[i]["node"].name})
			clues[i]["node"].queue_free()
			clues.remove_at(i)
			return

func _add_orb(room_id: String) -> void:
	var s := Sprite2D.new()
	s.texture = Art.tex("items/orb.png")
	var cells := map.free_cells(room_id, false)
	if cells.is_empty():
		return
	s.position = HouseMap.cell_center(cells[rng.randi_range(0, cells.size() - 1)])
	s.scale = Vector2(0.35, 0.35)
	s.visible = false
	s.set_meta("base", s.position)
	s.set_meta("phase", rng.randf() * TAU)
	s.set_meta("room", room_id)
	run.world_text.add_child(s)
	orbs.append(s)
	run.record_event("orb", {"x": s.position.x, "y": s.position.y, "phase": s.get_meta("phase")})

func _add_uv_print(c: Creature) -> void:
	if uv_prints.size() >= 10:
		return
	var cand := map.wall_adjacent_cells(c.room_id)
	var near: Array = cand.filter(func(cell): return HouseMap.cell_center(cell).distance_to(c.position) < 160.0)
	if near.is_empty():
		near = cand
	if near.is_empty():
		return
	var pos := HouseMap.cell_center(near[rng.randi_range(0, near.size() - 1)])
	var s := _decal("items/uv_handprint.png", pos, rng.randf() * TAU, 30.0, true)
	uv_prints.append({"pos": pos, "node": s, "room": c.room_id})
	run.shimmer(c.room_id)

# --- Entity-driven production ------------------------------------------------------

func creature_tick(c: Creature, delta: float) -> void:
	if c.type_id != source or c.state == "banished":
		return
	_t += delta
	for hs in hotspots:
		hs["ttl"] -= delta
	hotspots = hotspots.filter(func(h): return h["ttl"] > 0.0)
	for v in voices:
		v["ttl"] -= delta
	voices = voices.filter(func(v): return v["ttl"] > 0.0)
	for idx in mirror_ttl.keys():
		mirror_ttl[idx] -= delta
		if mirror_ttl[idx] <= 0.0:
			mirror_ttl.erase(idx)
			run.view.show_mirror_overlay(idx, null, 0.0)
			run.record_event("mirror", {"index": idx, "on": false})
	var indoors: bool = not map.room(c.room_id).get("outdoor", true)
	match source:
		"shade", "poltergeist", "blightness", "crawler", "lost_one", "drowned_sailor", "plague_doctor":
			_interact_t -= delta
			if _interact_t <= 0.0:
				_interact_t = float(c.def["interaction_interval"]) * rng.randf_range(0.6, 1.4)
				_ghost_interaction(c)
			_tick_book(c, delta)
			if source == "drowned_sailor":
				run.sailor_tick(c, delta)
			elif source == "plague_doctor":
				run.plague_tick(c, delta)
		"vampire":
			_drop_t -= delta
			if _drop_t <= 0.0 and indoors and c.state != "warn":
				_drop_t = rng.randf_range(6.0, 9.0)
				if _count("blood_drops") >= 14:
					_drop_oldest("blood_drops")
				_add_clue("blood_drops", c.room_id, false, c.position + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8)))
			if _bite_t > 0.0:
				_bite_t -= delta
				if _bite_t <= 0.0:
					run.vampire_bite()
		"werewolf":
			_drop_t -= delta
			if _drop_t <= 0.0 and indoors and c.path_i < c.path.size():
				_drop_t = 1.6
				if _count("footprints") >= 26:
					_drop_oldest("footprints")
				_add_clue("footprints", c.room_id, false, c.position, c.token.facing + PI * 0.5)
			_claw_t -= delta
			if _claw_t <= 0.0 and indoors:
				_claw_t = rng.randf_range(18.0, 28.0)
				if _count("claw_marks") < 7:
					_add_clue("claw_marks", c.room_id, true)
			_fur_t -= delta
			if _fur_t <= 0.0 and indoors:
				_fur_t = rng.randf_range(20.0, 30.0)
				if _count("fur") < 6:
					_add_clue("fur", c.room_id, false, c.position)
		"shapeshifter":
			_voice_t -= delta
			if _voice_t <= 0.0:
				_voice_t = rng.randf_range(24.0, 38.0)
				_mimic_voice(c)
			_skin_t -= delta
			if _skin_t <= 0.0 and indoors:
				_skin_t = rng.randf_range(26.0, 40.0)
				if _count("shed_skin") < 5:
					_add_clue("shed_skin", c.room_id, false, c.position)
			for i in run.view.mirrors.size():
				var m: Dictionary = run.view.mirrors[i]
				if (m["furniture"]["rect"] as Rect2).grow(70.0).has_point(c.position) and not mirror_ttl.has(i):
					mirror_ttl[i] = 26.0
					run.view.show_mirror_overlay(i, Art.tex(Defs.FORM_TOKENS["true"]), 0.85)
					run.record_event("mirror", {"index": i, "on": true})

func _ghost_interaction(c: Creature) -> void:
	var level := rng.randi_range(2, 4)
	if "emf5" in evidence and rng.randf() < 0.45:
		level = 5
	var pos := c.position + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20))
	hotspots.append({"pos": pos, "level": level, "ttl": 22.0, "room": c.room_id})
	run.record_event("emf", {"x": pos.x, "y": pos.y, "level": level})
	if level == 5:
		run.shimmer(c.room_id)
	if "uv" in evidence and rng.randf() < 0.55:
		_add_uv_print(c)
	if source == "poltergeist":
		run.sound_at("poltergeist_bang" if rng.randf() < 0.6 else "door_creak", c.position, -3.0)
		run.disturbance(c.position)
		run.shake_furniture_near(c.position)
	elif rng.randf() < 0.3:
		run.sound_at("door_creak", c.position, -8.0)

func _tick_book(c: Creature, delta: float) -> void:
	if not ("writing" in evidence):
		return
	# The ghost writes in the first unwritten book laid near it.
	for book in run.placed_books():
		if written_books.has(book):
			continue
		var near: bool = map.room_at(book.position) == c.lair_room or book.position.distance_to(c.position) < 140.0
		if not near:
			continue
		if book_write_t < 0.0:
			book_write_t = rng.randf_range(6.0, 13.0)
		book_write_t -= delta
		if book_write_t <= 0.0:
			book_write_t = -1.0
			written_books[book] = true
			book_written = true
			run.on_book_written(book)
			run.shimmer(map.room_at(book.position))
		return

func _mimic_voice(c: Creature) -> void:
	# The voice comes from where the creature is, wearing an occupant's voice.
	var pos := c.position
	voices.append({"pos": pos, "room": c.room_id, "ttl": 14.0})
	run.shimmer(c.room_id)
	run.sound_at("whisper_mimic", pos, 2.0, rng.randf_range(0.9, 1.1), 1100.0)
	run.record_event("voice", {"x": pos.x, "y": pos.y})

# --- Readings for equipment ---------------------------------------------------------

## [level 0-5, room id] of the strongest EMF hotspot near pos.
func emf_at(pos: Vector2) -> Array:
	var best := 1
	var room := ""
	for hs in hotspots:
		var d: float = pos.distance_to(hs["pos"])
		if d < 110.0:
			var lv: int = hs["level"] if d < 70.0 else maxi(2, hs["level"] - 2)
			if lv > best:
				best = lv
				room = hs["room"]
	return [best, room]

## Continuous EMF value (1.0 – 5.0) for the near-player readout.
func emf_value(pos: Vector2) -> float:
	var v := 1.0 + 0.15 * sin(_t * 3.1 + pos.x * 0.01)
	for hs in hotspots:
		var d: float = pos.distance_to(hs["pos"])
		v = maxf(v, float(hs["level"]) * clampf(1.2 - d / 120.0, 0.0, 1.0))
	return clampf(v, 1.0, 5.0)

func temperature(room_id: String) -> float:
	return float(temps.get(room_id, 14.0)) + sin(_t * 1.7) * 0.4

# --- Observation ---------------------------------------------------------------------

func _process(delta: float) -> void:
	for o in orbs:
		var ph: float = o.get_meta("phase")
		o.position = o.get_meta("base") + Vector2(sin(_t * 0.7 + ph) * 18.0, cos(_t * 0.5 + ph * 2.0) * 14.0)
		o.modulate.a = 0.55 + 0.35 * sin(_t * 2.0 + ph)
	if source == "":
		return
	_detect_acc += delta
	if _detect_acc < 1.0 / DETECT_HZ:
		return
	_detect_acc = 0.0
	# Every living hunter observes for themselves (private journals).
	for p: Player in run.hunters:
		if not p.dead:
			_observe(p)

func is_lit(pos: Vector2, p: Player) -> bool:
	var pp := p.global_position
	if pos.distance_to(pp) < 70.0:
		return true
	if p.flashlight_on and _in_cone(pp, p.aim_angle, pos, FLASH_RANGE, FLASH_HALF_ANGLE) and map.los(pp, pos):
		return true
	for l in run.view.lights:
		var light: PointLight2D = l["light"]
		if light.energy < 0.3 or l["kind"] == "dim":
			continue
		var radius := light.texture_scale * (256.0 if l["kind"] in ["room", "moon"] else 128.0) * 0.6
		if pos.distance_to(light.position) < radius and map.los(light.position, pos):
			return true
	return false

static func _in_cone(origin: Vector2, angle: float, pos: Vector2, rng_len: float, half: float) -> bool:
	var to := pos - origin
	if to.length() > rng_len:
		return false
	return absf(angle_difference(angle, to.angle())) < half or to.length() < 26.0

func _observe(p: Player) -> void:
	var pp := p.global_position
	for c in clues:
		if p.journal.has(c["evidence"]):
			continue
		if pp.distance_to(c["pos"]) < CLUE_RANGE and map.los(pp, c["pos"]) and is_lit(c["pos"], p):
			run.discover(p, c["evidence"], c["room"])
	if p.uv_light.visible:
		for u in uv_prints:
			if _in_cone(pp, p.aim_angle, u["pos"], UV_RANGE, UV_HALF_ANGLE) and map.los(pp, u["pos"]):
				run.discover(p, "uv", u["room"])
				break
	if source == "vampire":
		for o in run.occupants:
			if o.bitten and o.state != "gone" and pp.distance_to(o.position) < 135.0 and map.los(pp, o.position) and is_lit(o.position, p):
				run.discover(p, "bite_marks", o.room_id)
	for idx in mirror_ttl:
		var m: Dictionary = run.view.mirrors[idx]
		var mp: Vector2 = m["furniture"]["rect"].get_center()
		if pp.distance_to(mp) < 175.0 and map.los(pp, mp) and is_lit(mp, p):
			run.discover(p, "wrong_reflection", m["furniture"]["room_id"])
	for v in voices:
		if p.room_id == v["room"] or pp.distance_to(v["pos"]) < 210.0:
			run.discover(p, "mimic_voice", v["room"])
	for book in written_books:
		if is_instance_valid(book) and pp.distance_to(book.position) < 170.0 and map.los(pp, book.position) and is_lit(book.position, p):
			run.discover(p, "writing", map.room_at(book.position))
	if p.equipment and p.equipment.current() == "orb_camera":
		for o in orbs:
			if _in_cone(pp, p.aim_angle, o.position, 280.0, 0.6) and map.los(pp, o.position):
				run.discover(p, "orbs", o.get_meta("room"))
				break

func set_orbs_visible(v: bool) -> void:
	for o in orbs:
		o.visible = v
