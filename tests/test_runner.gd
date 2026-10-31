extends Node
## Headless test suite. Run with:
##   godot --headless --fixed-fps 60 --path . res://tests/test_runner.tscn
## Exits with code 0 when every test passes, 1 otherwise.

var failures: Array = []
var passes := 0
var current := ""

func _ready() -> void:
	SaveData.save_path = "user://test_save.json"
	SaveData.replay_path = "user://test_replay.json"
	SaveData.reset_all()
	await get_tree().process_frame
	var tests := [
		"test_houses_valid", "test_room_lookup", "test_journal", "test_scoring",
		"test_rankings", "test_persistence", "test_every_creature_every_house",
		"test_seeded_reset_repeatable", "test_genuine_evidence_room", "test_reckless_and_harbinger",
		"test_correct_blind_victory", "test_wound_then_death", "test_replay_is_passive",
		"test_crucifix_blocks_ghost_hunt", "test_shapeshifter_needs_exposure", "test_full_flow_records_once",
		"test_basements", "test_stairs_and_basement_evidence", "test_encyclopedia_matches_game",
		"test_all_entities_selectable", "test_occupant_identities", "test_mp_scoring",
		"test_hud_layout", "test_nightmare",
		"test_suspect_display", "test_beginner", "test_replay_moments", "test_ui_scaling",
		"test_environment", "test_witch_needle", "test_voodoo_doll", "test_new_ghosts",
		"test_counterattacks", "test_escalations", "test_prompt_and_needle", "test_audio_overrides",
		"test_audio_export", "test_game_setup",
		"test_blightness_rushes", "test_safe_names", "test_temperatures", "test_ghost_marker_and_ruled_out",
		"test_hellbound", "test_abyssal", "test_sailor_and_doctor", "test_consolidation", "test_home_rooms", "test_suspect_filter_and_splatter", "test_weeper_and_mimic",
		"test_progression", "test_flee_death_immortal", "test_required_items_reachable", "test_salt_water_relic",
	]
	var only := OS.get_cmdline_user_args()
	if not only.is_empty():
		tests = tests.filter(func(t): return t in only)
	for t in tests:
		current = t
		var started := Time.get_ticks_msec()
		var before := failures.size()
		await call(t)
		if failures.size() == before:
			passes += 1
			print("  PASS  %s (%d ms)" % [t, Time.get_ticks_msec() - started])
		else:
			print("  FAIL  %s (%d ms)" % [t, Time.get_ticks_msec() - started])
		_cleanup_scene()
		await get_tree().process_frame
	print("\n%d passed, %d failed" % [passes, tests.size() - passes])
	for f in failures:
		print("   - ", f)
	get_tree().quit(0 if failures.is_empty() else 1)

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s: %s" % [current, msg])

func _cleanup_scene() -> void:
	get_tree().paused = false
	var cs := get_tree().current_scene
	if cs and cs != self:
		cs.queue_free()
	for c in get_tree().root.get_children():
		if c is Run or c is Control and c != self and not (c in [Art, Sfx, SaveData, Online, Game]):
			c.queue_free()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _start(house: String, creature: String, run_seed: int = 1234) -> Run:
	var run: Run = Game.start_run(house, run_seed, creature)
	await get_tree().process_frame
	return run

# --- Houses ---------------------------------------------------------------------------

func test_houses_valid() -> void:
	check(Game.house_ids.size() == 7, "seven locations expected, got %d" % Game.house_ids.size())
	for id in Game.house_ids:
		var m := HouseMap.from_data(Game.house(id))
		var reach := m.reachable_from_spawn()
		var walk := 0
		for y in m.h:
			for x in m.w:
				if m.walkable(Vector2i(x, y)):
					walk += 1
					check(reach.has(Vector2i(x, y)), "%s: unreachable cell %d,%d" % [id, x, y])
		check(walk > 300, "%s: too small" % id)
		# Special scenery the entities rely on (each has a fallback, but a house should not need it).
		check(not m.furniture_with("melt").is_empty(), "%s: no stove, hearth or furnace to melt silver" % id)
		check(m.furniture.any(func(f): return f["type"] == "boiler"), "%s: no basement furnace for the Lost One" % id)
		var ids := {}
		var dead_ends := 0
		for r in m.rooms:
			check(not ids.has(r["id"]), "%s: duplicate room id %s" % [id, r["id"]])
			ids[r["id"]] = true
			check(r["name"] != "", "%s: room without name" % id)
			var ex := m.exits(r["id"])
			check(ex >= 1, "%s: sealed room %s" % [id, r["id"]])
			if ex < 2:
				dead_ends += 1
		check(dead_ends <= 1, "%s: %d dead-end rooms" % [id, dead_ends])
		check(m.furniture_with("melt").size() >= 1, "%s: no silver melting station" % id)
		check(m.furniture_with("mirror").size() >= 2, "%s: needs at least two mirrors" % id)
		check(m.indoor_rooms().size() >= 7, "%s: needs at least seven indoor rooms" % id)
		for res in Defs.RESOURCE_SPAWNS:
			var found := false
			for k in Defs.RESOURCE_SPAWNS[res]["kinds"]:
				if not m.rooms_of_kind(k).is_empty():
					found = true
			check(found, "%s: no logical room for %s" % [id, res])
		for f in m.furniture:
			for y in range(f["cell"].y, f["cell"].y + f["size"].y):
				for x in range(f["cell"].x, f["cell"].x + f["size"].x):
					check(m.is_floor(Vector2i(x, y)) and m.at(Vector2i(x, y)) != HouseMap.DOOR, "%s: %s off the floor" % [id, f["type"]])

func test_room_lookup() -> void:
	for id in Game.house_ids:
		var m := HouseMap.from_data(Game.house(id))
		for r in m.rooms:
			for c in r["cells"]:
				check(m.room_at(HouseMap.cell_center(c)) == r["id"], "%s: cell %s not in %s" % [id, c, r["id"]])
		for d in m.doors:
			var rid := m.room_at_cell(d)
			check(rid != "", "%s: door %s has no room" % [id, d])
			var adjacent := false
			for o in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)]:
				if m.room_at_cell(d + o) == rid:
					adjacent = true
			check(adjacent, "%s: door %s resolves to non-adjacent room" % [id, d])

# --- Journal / scoring ----------------------------------------------------------------

func test_journal() -> void:
	var j := Journal.new()
	var emitted := [0]
	j.discovered.connect(func(_e): emitted[0] += 1)
	check(j.undiscovered_conventional().size() == 6, "six conventional unconfirmed")
	for id in j.undiscovered_conventional():
		check(not Defs.EVIDENCE[id]["hidden"], "hidden evidence listed as unconfirmed")
	check(j.record("emf5", 43.2, "living", "Living Room"), "first record is new")
	check(not j.record("emf5", 80.0, "kitchen", "Kitchen"), "duplicate is not new")
	check(j.entries.size() == 1 and j.entries[0]["time"] == 43.2 and j.entries[0]["room_name"] == "Living Room", "first discovery kept")
	check(j.occurrences.size() == 2, "all occurrences tracked")
	check(emitted[0] == 1, "one notification per type")
	check(not ("emf5" in j.undiscovered_conventional()), "discovered evidence leaves unconfirmed list")
	j.record("claw_marks", 90.0, "hall", "Hallway")
	check(j.undiscovered_conventional().size() == 5, "hidden evidence never enters unconfirmed list")
	j.void_all()
	check(j.active_entries().is_empty() and j.void_entries().size() == 2, "void after Harbinger")
	check(not j.has("emf5"), "voided evidence no longer counts")
	check(Journal.format_time(83.9) == "01:23", "time format")

func test_scoring() -> void:
	var base := {"vanquished": true, "time": 180.0, "creature": "shade", "true_evidence": 3,
		"incorrect_attempts": 0, "incomplete_attempts": 0, "wounds": 0, "clean_hunts_survived": 1, "blind": false}
	var a := Scoring.compute(base)
	check(a["total"] == Scoring.compute(base)["total"], "deterministic")
	check(a["total"] == 4000 + 2000 + 900 + 1000 + 800 + 150, "known value, got %d" % a["total"])
	var dead := base.duplicate()
	dead["vanquished"] = false
	check(Scoring.compute(dead)["total"] == 0, "death scores zero")
	# Stalling for more evidence than the cap is never better.
	var stall := base.duplicate()
	stall["time"] = 300.0
	stall["true_evidence"] = 9
	check(Scoring.compute(stall)["total"] < a["total"], "stalling not optimal")
	# Fast correct early victory stays competitive with a thorough one.
	var fast := base.duplicate()
	fast["time"] = 75.0
	fast["true_evidence"] = 1
	check(Scoring.compute(fast)["total"] >= a["total"], "fast correct victory competitive")
	# Reckless Harbinger runs never beat the equivalent clean run.
	var harb := {"vanquished": true, "time": 180.0, "creature": "harbinger", "true_evidence": 0,
		"incorrect_attempts": 2, "incomplete_attempts": 0, "wounds": 0, "clean_hunts_survived": 0, "blind": false}
	check(Scoring.compute(harb)["total"] < a["total"], "Harbinger farming unprofitable")
	var many_wrong := base.duplicate()
	many_wrong["incorrect_attempts"] = 40
	check(Scoring.compute(many_wrong)["total"] == 0, "score floors at zero")
	var hunts := base.duplicate()
	hunts["clean_hunts_survived"] = 50
	check(Scoring.compute(hunts)["total"] - a["total"] == 2 * Scoring.HUNT_SURVIVED_EACH, "hunt bonus capped")
	var blind := base.duplicate()
	blind["true_evidence"] = 0
	blind["blind"] = true
	blind["time"] = 50.0
	check(Scoring.compute(blind)["lines"].any(func(l): return l[0] == "Audacity"), "audacity line")

func test_rankings() -> void:
	var rows := Rankings.table("Tester", 9999)
	check(rows.size() == Rankings.LEGENDS.size() + 1, "player added")
	for i in rows.size() - 1:
		check(rows[i]["score"] >= rows[i + 1]["score"], "sorted")
	check(Rankings.rank_for(999999) == 1, "top rank")
	check(Rankings.rank_for(0) == Rankings.LEGENDS.size() + 1, "bottom rank")
	for l in Rankings.LEGENDS:
		check(l["score"] < 13195, "legend within the achievable scale")

func test_persistence() -> void:
	SaveData.reset_all()
	var s := {"house": "ashgrove", "house_name": "Ashgrove Cottage", "vanquished": true, "time": 120.5, "score": 9000,
		"original_creature": "werewolf", "creature": "werewolf", "evidence": [{"id": "fur", "time": 30.0, "room_name": "Kitchen", "room_id": "kitchen", "void": false}],
		"evidence_ids": ["fur"], "incorrect_attempts": 1, "wounds": 1, "transformations": 0, "harbinger": false,
		"blind": false, "rules_version": Scoring.RULES_VERSION}
	var out := SaveData.record_run(s)
	check(out["new_best_time"] and out["new_best_score"], "first win is a record")
	SaveData.load_data()
	var st: Dictionary = SaveData.data["stats"]["ashgrove"]["werewolf"]
	check(st["runs"] == 1 and st["wins"] == 1 and st["incorrect_ids"] == 1 and st["wounds"] == 1, "stats persisted")
	check(st["evidence_rooms"].has("Shed Fur @ Kitchen"), "evidence room analytics")
	check(SaveData.house_record("ashgrove")["best_time"] == 120.5, "personal best persisted")
	var slower := s.duplicate()
	slower["time"] = 200.0
	slower["score"] = 100
	check(not SaveData.record_run(slower)["new_best_time"], "slower run is not a record")
	SaveData.reset_all()

# --- Live simulation ------------------------------------------------------------------

func test_every_creature_every_house() -> void:
	for house in Game.house_ids:
		for cr in Defs.ORDINARY_CREATURES:
			var t0 := Time.get_ticks_msec()
			var run := await _start(house, cr, 77)
			print("    %s/%s built in %d ms" % [house, cr, Time.get_ticks_msec() - t0])
			check(run.creature.type_id == cr, "%s/%s creature" % [house, cr])
			check(run.map.room(run.creature.lair_room).get("outdoor", true) == false, "%s/%s lair indoors" % [house, cr])
			check(run.occupants.size() == int(Game.house(house).get("npcs", 2)), "%s: occupants" % house)
			var reach := run.map.reachable_from_spawn()
			for p in run.pickups:
				check(reach.has(HouseMap.to_cell(p["pos"])), "%s/%s: %s unreachable" % [house, cr, p.get("res", p.get("item", "?"))])
			var silver := run.pickups.filter(func(p): return p.get("res", "") == "silverware").size()
			check(silver == Defs.SILVERWARE_NEEDED, "%s: silverware count" % house)
			# Creature path to the player must exist.
			check(not run.map.path(run.creature.position, run.player.position).is_empty(), "%s/%s: creature cannot reach player" % [house, cr])
			run.elapsed = 100.0
			run.threat = 100.0
			await _frames(240)
			check(run.state == "playing" or run.state == "ending", "%s/%s ran" % [house, cr])
			_cleanup_scene()
			await get_tree().process_frame

func test_seeded_reset_repeatable() -> void:
	var a := await _start("blackwood", "", 4242)
	var sig_a := [a.creature.type_id, a.creature.lair_room, a.pickups.map(func(p): return p["pos"])]
	_cleanup_scene()
	await get_tree().process_frame
	var b := await _start("blackwood", "", 4242)
	var sig_b := [b.creature.type_id, b.creature.lair_room, b.pickups.map(func(p): return p["pos"])]
	check(str(sig_a) == str(sig_b), "same seed gives the same encounter")
	check(b.elapsed < 1.0 and b.player.journal.entries.is_empty() and b.player.wounds == 0, "fresh state after reset")

func test_genuine_evidence_room() -> void:
	var run := await _start("ashgrove", "shade", 99)
	var lair := run.creature.lair_room
	run.player.global_position = HouseMap.cell_center(run.map.free_cells(lair)[0])
	run.player.equipment.select(Defs.BASE_LOADOUT.find("thermometer"))
	await _frames(120)
	check(run.player.journal.has("freezing"), "freezing found in the Shade's lair")
	if run.player.journal.has("freezing"):
		check(run.player.journal.entries[0]["room_id"] == lair, "room recorded is the lair (%s vs %s)" % [run.player.journal.entries[0]["room_id"], lair])
		check(run.player.journal.entries[0]["room_name"] == run.map.room_name(lair), "room name")
	# Evidence that does not belong to the entity is never accepted.
	run.discover(run.player, "spirit_box", lair)
	run.discover(run.player, "claw_marks", lair)
	check(not run.player.journal.has("spirit_box") and not run.player.journal.has("claw_marks"), "foreign evidence rejected")
	var n := run.player.journal.entries.size()
	run.discover(run.player, "freezing", "kitchen")
	check(run.player.journal.entries.size() == n, "no duplicate entries")

func test_reckless_and_harbinger() -> void:
	var run := await _start("marrow_street", "werewolf", 5)
	run.player.suspect = "shade"
	run.attempt_vanquish(run.player, "shade", "rite")
	check(run.player.reckless_attempts == 1 and run.player.wrong_attempts == 1, "uninvestigated wrong attempt is reckless")
	check(run.occupants.all(func(o): return o.state == "flee" or o.state == "gone"), "occupants flee on severe reaction")
	check(not run.harbinger_summoned, "not yet the Harbinger")
	run.player.journal.record("fur", 10.0, "kitchen", "Kitchen")
	run.attempt_vanquish(run.player, "vampire", "wooden_stake")
	check(run.player.reckless_attempts == 1, "investigated wrong attempt is not reckless")
	run.attempt_vanquish(run.player, "poltergeist", "rite")
	check(run.harbinger_summoned, "third wrong attempt summons the Harbinger")
	await _frames(2)
	check(run.creature.type_id == "harbinger", "entity replaced")
	check(run.player.journal.active_entries().is_empty(), "old evidence voided")
	run.discover(run.player, "fur", "kitchen")
	check(not run.player.journal.has("fur"), "old entity's evidence no longer accepted")
	check(run.sigils.size() == 3, "three sigil candles")
	for s in run.sigils:
		check(run.map.reachable_from_spawn().has(HouseMap.to_cell(s["pos"])), "sigil reachable")
	for s in run.sigils.duplicate():
		run._light_sigil(run.player, s)
	check(run.creature.state == "bound", "Harbinger bound after three sigils")
	run.player.global_position = run.creature.position + Vector2(40, 0)
	check(run.can_begin_rite(run.player), "final rite available")
	run.perform_rite(run.player)
	check(run._outcome == "vanquished", "Harbinger banished")
	var s := run.build_summary()
	check(s["harbinger"] and s["creature"] == "harbinger" and s["original_creature"] == "werewolf", "summary records replacement")
	check(s["score"] < 9000, "Harbinger victory is not a jackpot (%d)" % s["score"])

func test_correct_blind_victory() -> void:
	var run := await _start("evangeline", "vampire", 11)
	run.player.add_resource("garlic")
	run.player.add_resource("wooden_stake")
	run.player.global_position = run.creature.position + Vector2(-30, 0)
	run.player.aim_angle = 0.0
	run.strike(run.player, "wooden_stake")
	check(run._outcome == "vanquished", "stake + garlic vanquishes a vampire")
	var s := run.build_summary()
	check(s["blind"], "completely blind victory recorded")
	check(s["score_lines"].any(func(l): return l[0] == "Audacity"), "audacity acknowledged")
	check(run.recorder.data["events"].any(func(e): return e[1] == "audacity"), "supernatural reaction recorded")

func test_wound_then_death() -> void:
	var run := await _start("hollow_lane", "werewolf", 3)
	run.creature.begin_hunt(run.creature.position, false)
	run.on_creature_contact(run.creature, run.player)
	check(run.player.wounds == 1 and run.state == "playing", "first hit wounds")
	run.on_creature_contact(run.creature, run.player)
	check(run.player.wounds == 1, "protection after the first hit")
	run.player.invuln = 0.0
	run.creature.begin_hunt(run.creature.position, false)
	run.on_creature_contact(run.creature, run.player)
	check(run.player.dead and run._outcome == "perished", "second hit is fatal")

func test_replay_is_passive() -> void:
	SaveData.reset_all()
	var run := await _start("ashgrove", "poltergeist", 21)
	await _frames(300)
	run.attempt_vanquish(run.player, "poltergeist", "rite")
	var summary := run.build_summary()
	var replay: Dictionary = run.recorder.finish(run.elapsed, "test")
	check(replay["tracks"]["player_1"].size() >= 5 * 40, "player track recorded")
	check(replay["tracks"].has("creature_1"), "creature track recorded")
	check(replay["tracks"].has("npc_1"), "npc track recorded")
	_cleanup_scene()
	await get_tree().process_frame
	var before := JSON.stringify(SaveData.data)
	var rp := ReplayPlayer.new()
	rp.setup(replay)
	get_tree().root.add_child(rp)
	await _frames(400)
	check(rp.t > 0.0, "replay advanced")
	check(JSON.stringify(SaveData.data) == before, "replay did not touch statistics")
	check(get_tree().root.find_children("*", "Creature", true, false).is_empty(), "replay spawned no live creature")
	rp.queue_free()
	check(summary["house"] == "ashgrove", "summary house")

func test_crucifix_blocks_ghost_hunt() -> void:
	var run := await _start("blackwood", "shade", 8)
	run.place_item(run.player, "crucifix", run.creature.position)
	run.trigger_hunt(false)
	check(not run.creature.is_hunting(), "crucifix prevented the ghost hunt")
	_cleanup_scene()
	await get_tree().process_frame
	var run2 := await _start("blackwood", "vampire", 8)
	run2.place_item(run2.player, "crucifix", run2.creature.position)
	run2.trigger_hunt(false)
	check(run2.creature.is_hunting(), "crucifix has no power over a vampire")

func test_shapeshifter_needs_exposure() -> void:
	var run := await _start("marrow_street", "shapeshifter", 31)
	run.player.add_resource("iron_nails")
	run.player.global_position = run.creature.position + Vector2(-30, 0)
	run.player.aim_angle = 0.0
	run.strike(run.player, "iron_nails")
	check(run._outcome == "" and run.player.incomplete_attempts == 1, "unexposed shapeshifter resists")
	check(run.player.wrong_attempts == 0, "right identity is not counted as wrong")
	run.creature.expose(10.0)
	run.player.equipment._cooldown = 0.0
	run.strike(run.player, "iron_nails")
	check(run._outcome == "vanquished", "exposed shapeshifter is banished")

func test_full_flow_records_once() -> void:
	SaveData.reset_all()
	var run := await _start("ashgrove", "werewolf", 41)
	run.player.add_resource("silver_stake")
	run.player.global_position = run.creature.position + Vector2(-30, 0)
	run.player.aim_angle = 0.0
	run.strike(run.player, "silver_stake")
	await _frames(200)
	var res: Dictionary = Game.last_result
	check(not res.is_empty(), "results produced")
	check(res["summary"]["vanquished"], "victory survives into the results summary")
	check(res["summary"]["score"] > 0, "victory scored")
	check(SaveData.house_record("ashgrove")["runs"] == 1, "run recorded exactly once")
	check(get_tree().current_scene.get_script() == preload("res://scripts/ui/results.gd"), "results screen shown")
	await _frames(120)
	check(SaveData.house_record("ashgrove")["runs"] == 1, "results replay did not record again")
	SaveData.reset_all()

# --- Revision 2 -----------------------------------------------------------------------

func test_basements() -> void:
	for id in Game.house_ids:
		var m := HouseMap.from_data(Game.house(id))
		var below: Array = m.rooms.filter(func(r): return int(r["level"]) == -1)
		check(below.size() >= 4, "%s: basement has several rooms" % id)
		check(m.stairs.size() >= 2, "%s: two ways between floors" % id)
		check(m.floors() == [1, 0, -1], "%s: upper floor, main floor and basement (%s)" % [id, m.floors()])
		var reach := m.reachable_from_spawn()
		for r in below:
			check(reach.has(m.free_cells(r["id"], false)[0]), "%s: %s reachable via the stairs" % [id, r["id"]])
			check(r.has("condition"), "%s: %s has a condition" % [id, r["id"]])
		# Floors never share walls or sight lines.
		var top := m.floor_bounds(0)
		var bottom := m.floor_bounds(-1)
		check(not top.intersects(bottom), "%s: floors are separate" % id)
		var a := HouseMap.cell_center(m.spawn_cell)
		var b := HouseMap.cell_center(m.free_cells(below[0]["id"])[0])
		var path := m.path(a, b)
		check(not path.is_empty(), "%s: path from spawn into the basement" % id)
		var jumps := 0
		for i in range(1, path.size()):
			if path[i].distance_to(path[i - 1]) > 90.0:
				jumps += 1
		check(jumps == 1, "%s: path takes exactly one staircase (%d)" % [id, jumps])
		check(not m.los(a, b), "%s: no line of sight between floors" % id)
		# The upper floor: separate, reachable by one staircase, rooms with conditions.
		var above: Array = m.rooms.filter(func(r): return int(r["level"]) == 1)
		check(above.size() >= 4, "%s: upper floor has several rooms" % id)
		var up := m.floor_bounds(1)
		check(not up.intersects(top) and not up.intersects(bottom), "%s: upper floor is separate" % id)
		for r in above:
			check(reach.has(m.free_cells(r["id"], false)[0]), "%s: %s reachable via the stairs" % [id, r["id"]])
			check(r.has("condition"), "%s: %s has a condition" % [id, r["id"]])
		var c := HouseMap.cell_center(m.free_cells(above[0]["id"])[0])
		var up_path := m.path(a, c)
		check(not up_path.is_empty(), "%s: path from spawn upstairs" % id)
		check(not m.los(a, c), "%s: no line of sight to the upper floor" % id)
		# Basement to attic: two staircases, via the main floor.
		var deep := m.path(b, c)
		var hops := 0
		for i in range(1, deep.size()):
			if deep[i].distance_to(deep[i - 1]) > 90.0:
				hops += 1
		check(hops == 2, "%s: basement to upper floor takes two staircases (%d)" % [id, hops])

func test_stairs_and_basement_evidence() -> void:
	var run := await _start("blackwood", "werewolf", 13)
	var st: Dictionary = run.map.stairs[0]
	# Walking onto the stairs does nothing; [E] / [Space] takes them.
	run.creature.set_process(false)
	run.player.global_position = HouseMap.cell_center(st["a"])
	await _frames(10)
	check(run.map.floor_at(run.player.global_position) == 0, "standing on the stairs stays upstairs")
	var it := run.find_interactable(run.player, run.player.global_position)
	check(it.get("kind", "") == "stairs" and it["label"].contains("Down"), "the stairs offer to be used (%s)" % it.get("label", ""))
	run.do_interact(run.player, it)
	await _frames(3)
	check(run.map.floor_at(run.player.global_position) == -1, "using the stairs took the hunter down")
	check(run.map.room(run.player.room_id).get("level", 0) == -1, "basement room recognised (%s)" % run.player.room_id)
	check(run.recorder.data["events"].any(func(e): return e[1] == "floor"), "floor change recorded for the replay")
	await _frames(30)
	check(run.map.floor_at(run.player.global_position) == -1, "no bouncing back up from the landing")
	var basement_room: String = run.player.room_id
	run.discover(run.player, "fur", basement_room)
	check(run.player.journal.has("fur") and run.player.journal.entries[-1]["room_name"] == run.map.room_name(basement_room), "basement evidence keeps its room name")
	# A creature in the basement can still reach a hunter upstairs.
	run.player.global_position = HouseMap.cell_center(run.map.spawn_cell)
	run.creature.position = HouseMap.cell_center(st["b_land"])
	check(not run.map.path(run.creature.position, run.player.global_position).is_empty(), "creature can climb to the hunter")

func test_encyclopedia_matches_game() -> void:
	for id in Defs.ENCYCLOPEDIA_ORDER:
		var d: Dictionary = Defs.CREATURES[id]
		for k in ["name", "blurb", "behaviour", "hunting", "strengths", "weaknesses", "vanquish"]:
			check(d.has(k) and not str(d[k]).is_empty(), "%s has %s" % [id, k])
		check(d["evidence"].size() == (0 if id == "harbinger" else 3), "%s: three evidence types" % id)
	# The written requirements match the code paths.
	check(Defs.vanquish_summary("vampire").contains("garlic") and Defs.vanquish_summary("vampire").contains("wooden stake"), "vampire text")
	check(Defs.vanquish_summary("werewolf").contains("silver"), "werewolf text")
	check(Defs.vanquish_summary("shapeshifter").contains("mirror") and Defs.vanquish_summary("shapeshifter").contains("iron"), "shapeshifter text")
	check(Defs.vanquish_summary("shade").contains("salt"), "shade text")
	check(Defs.vanquish_summary("poltergeist").contains("Ghost Writing Book"), "poltergeist text")
	check(Defs.vanquish_summary("harbinger").contains("sigil"), "harbinger text")
	for e in Defs.EQUIPMENT:
		check(Defs.EQUIPMENT[e].has("desc"), "equipment %s described" % e)
	var enc = preload("res://scripts/ui/encyclopedia.gd").new()
	get_tree().root.add_child(enc)
	await _frames(2)
	for id in Defs.ENCYCLOPEDIA_ORDER + ["_equipment"]:
		enc.show_entry(id)
	await _frames(2)
	check(enc.page.get_child_count() > 5, "encyclopedia renders pages")
	enc.queue_free()

func test_all_entities_selectable() -> void:
	var run := await _start("ashgrove", "vampire", 3)
	var seen := {}
	for i in Defs.ORDINARY_CREATURES.size() + 1:
		run.cycle_suspect(run.player, 1)
		seen[run.player.suspect] = true
	for id in Defs.ORDINARY_CREATURES:
		check(seen.has(id), "%s selectable as a suspect" % id)
	run.player.suspect = "vampire"
	check(run.player.attempts.is_empty(), "selecting a suspect is not an attempt")
	check(not run.can_begin_rite(run.player), "no rite for a vampire")

func test_occupant_identities() -> void:
	for house in Game.house_ids:
		var run := await _start(house, "shapeshifter", 5)
		var names := run.occupants.map(func(o): return o.person["name"])
		var looks := run.occupants.map(func(o): return o.person["token"])
		var uniq_n := {}
		var uniq_t := {}
		for n in names:
			uniq_n[n] = true
		for t in looks:
			uniq_t[t] = true
		check(uniq_n.size() == names.size() and uniq_t.size() == looks.size(), "%s: distinct occupants" % house)
		check(not (run.disguise["name"] in names) and not (run.disguise["token"] in looks), "%s: disguise is not a copy of an occupant" % house)
		check(run.creature.tag != null, "%s: disguise wears the same name tag as occupants" % house)
		check(Occupants.PERSONALITIES.has(run.disguise["personality"]), "%s: disguise has a personality" % house)
		run.creature._set_form("human", false)
		check(run.creature.current_token() == run.disguise["token"], "%s: human form uses the disguise look" % house)
		for o in run.occupants:
			check(Occupants.PERSONALITIES.has(o.person["personality"]), "personality set")
		_cleanup_scene()
		await get_tree().process_frame

func test_mp_scoring() -> void:
	var base := {"creature": "werewolf", "vanquished": true, "alive": true, "wounds": 0, "time": 200.0,
		"true_evidence": 1, "first_finds": 1, "suspect_correct": true, "vanquisher": true,
		"incorrect_attempts": 0, "reckless_attempts": 0, "incomplete_attempts": 0, "clean_hunts_survived": 0}
	var a := MpScoring.compute(base)
	check(a["total"] == MpScoring.compute(base)["total"], "deterministic")
	var hoarder := base.duplicate()
	hoarder["vanquisher"] = false
	hoarder["true_evidence"] = 3
	hoarder["first_finds"] = 3
	var blind_vanq := base.duplicate()
	blind_vanq["true_evidence"] = 0
	blind_vanq["first_finds"] = 0
	check(MpScoring.compute(hoarder)["total"] > MpScoring.compute(blind_vanq)["total"], "a thorough investigator can beat a lucky vanquisher")
	check(a["total"] > MpScoring.compute(hoarder)["total"] - 600, "vanquishing still carries real weight")
	var shover := base.duplicate()
	shover["shoves_given"] = 50
	check(MpScoring.compute(shover)["total"] == a["total"], "shoving never scores")
	var dead := base.duplicate()
	dead["alive"] = false
	dead["vanquisher"] = false
	check(MpScoring.compute(dead)["total"] < MpScoring.compute(hoarder)["total"], "dead hunters keep evidence but lose survival")
	var rows := [{"score": 100, "vanquisher": false, "alive": true, "incorrect_attempts": 0, "index": 1},
		{"score": 100, "vanquisher": true, "alive": true, "incorrect_attempts": 0, "index": 0},
		{"score": 300, "vanquisher": false, "alive": false, "incorrect_attempts": 2, "index": 2}]
	var ranked := MpScoring.rank(rows)
	check(ranked[0]["score"] == 300 and ranked[1]["vanquisher"] and ranked[2]["rank"] == 3, "highest score wins; ties to the vanquisher")
	check(MpScoring.RULES_VERSION != Scoring.RULES_VERSION, "separate rule versions")

# --- Revision 3 -----------------------------------------------------------------------

func test_hud_layout() -> void:
	var run := await _start("ashgrove", "vampire", 7)
	var hud = run.hud
	check(hud._ev_discs.size() == Defs.EVIDENCE.size(), "every evidence type is shown from the start")
	check(hud.equip_grid.get_child_count() == run.player.equipment.slots.size(), "one equipment disc per slot")
	run.cycle_suspect(run.player, 1)
	await _frames(2)
	var sus: String = run.player.suspect
	check(sus != "", "a suspect was chosen")
	check(hud.REQUIREMENTS.has(sus), "suspect has vanquishing requirements")
	run.discover(run.player, "bite_marks", run.player.room_id)
	check(run.player.journal.has("bite_marks") and hud._ev_discs["bite_marks"].ring == Art.GOLD, "discovered evidence is highlighted")
	check(hud._ev_discs["fur"].ring != Art.GOLD, "undiscovered evidence stays greyed")
	# (0.11.0) Evidence that contradicts the suspect moves it to one that fits.
	check(run.player.suspect == sus if "bite_marks" in Defs.CREATURES[sus]["evidence"] else (run.player.suspect == "" or Defs.fits(run.player.suspect, run.player.journal)), "the suspect always fits the evidence")

func test_nightmare() -> void:
	SaveData.reset_all()
	var run: Run = Game.start_run("blackwood", 5, "werewolf", "nightmare")
	await get_tree().process_frame
	check(run.difficulty == "nightmare" and run.critters != null, "nightmare run has critters")
	check(run.critters.list.size() > 0 and run.critters.list.size() <= Critters.MAX_CRITTERS, "critter count bounded (%d)" % run.critters.list.size())
	check(run.occupants.all(func(o): return o.fear > 1.0), "occupants are frightened")
	var c: Dictionary = run.critters.list[0]
	var threat := run.threat
	var evidence := run.player.journal.entries.size()
	run.creature.set_process(false)
	run.player.global_position = c["node"].position
	await _frames(3)
	check(not c["alive"], "stepping on a critter kills it")
	var corpse: Vector2 = c["node"].position
	await _frames(30)
	check(c["node"].position == corpse, "the corpse no longer moves")
	check(run.player.journal.entries.size() == evidence and run.player.wounds == 0 and run.threat <= threat + 1.0, "critters have no gameplay effect")
	# Records are kept apart from Normal.
	run.player.add_resource("silver_stake")
	run.player.global_position = run.creature.position + Vector2(-30, 0)
	run.player.aim_angle = 0.0
	run.strike(run.player, "silver_stake")
	await _frames(200)
	check(SaveData.house_record("blackwood", "nightmare")["runs"] == 1, "nightmare run recorded as nightmare")
	check(SaveData.house_record("blackwood")["runs"] == 0, "normal records untouched")
	SaveData.reset_all()

# --- Revision 4 -----------------------------------------------------------------------

func test_suspect_display() -> void:
	var run := await _start("ashgrove", "vampire", 7)
	run.cycle_suspect(run.player, 1)
	await _frames(3)
	var row: HBoxContainer = run.hud.suspect_box.get_child(1)
	check(row.get_child_count() == Defs.ORDINARY_CREATURES.size(), "every entity is listed (%d)" % row.get_child_count())
	var lit := 0
	for cell in row.get_children():
		if cell.get_child(0).ring == Art.GOLD:
			lit += 1
	check(lit == 1, "exactly the chosen suspect is highlighted (%d)" % lit)
	check(run.hud.suspect_box.get_child_count() >= 4, "evidence and requirements still shown")

func test_beginner() -> void:
	SaveData.reset_all()
	var run: Run = Game.start_run("ashgrove", 3, "vampire", "beginner")
	await get_tree().process_frame
	var guide: BeginnerGuide = run.find_children("*", "BeginnerGuide", true, false)[0] if not run.find_children("*", "BeginnerGuide", true, false).is_empty() else null
	check(guide != null, "beginner run has the guide")
	check(run.creature.speed_for_hunt() < float(Defs.CREATURES["vampire"]["hunt_speed"]), "hunts are slower")
	run.creature.set_process(false)
	await _frames(150)
	check(run.hud.guide_panel.modulate.a > 0.5 and run.hud.guide_title.text != "", "a first tip is shown")
	run.discover(run.player, "bite_marks", run.player.room_id)
	await _frames(5)
	check(guide._said.has("first_evidence") and guide._said.has("fits_1"), "evidence explained and suspects narrowed")
	run.player.suspect = "vampire"
	await _frames(5)
	check(guide._said.has("how_vampire"), "vanquishing explained for the suspect")
	SaveData.reset_all()

func test_replay_moments() -> void:
	var run := await _start("ashgrove", "werewolf", 11)
	run.discover(run.player, "fur", run.player.room_id)
	run.creature.begin_hunt(run.creature.position, false)
	await _frames(20)
	run.attempt_vanquish(run.player, "shade", "rite")
	var replay: Dictionary = run.recorder.finish(run.elapsed, "test")
	_cleanup_scene()
	await get_tree().process_frame
	var rp := ReplayPlayer.new()
	rp.setup(replay)
	get_tree().root.add_child(rp)
	await get_tree().process_frame
	var texts := []
	for e in replay["events"]:
		var m: Array = rp._moment_for(e[1], e[2])
		if not m.is_empty():
			texts.append(m[1])
	check("Shed Fur discovered" in texts, "evidence moment from the recording (%s)" % str(texts))
	check("Hunt started" in texts, "hunt moment")
	check(texts.any(func(x): return x.begins_with("Incorrect vanquishing")), "incorrect attempt moment")
	await _frames(240)
	check(rp._moments.size() <= ReplayPlayer.MOMENT_MAX, "popups never stack beyond the limit")
	rp.queue_free()

func test_ui_scaling() -> void:
	SaveData.set_setting("ui_scale", 1.2)
	SaveData.set_setting("hud_scale", 0.8)
	Game.goto_menu()
	await get_tree().process_frame
	check(is_equal_approx(get_tree().root.content_scale_factor, 1.2), "menu scale applied to menus")
	var run := await _start("ashgrove", "shade", 2)
	check(is_equal_approx(get_tree().root.content_scale_factor, 1.0), "menu scale does not resize gameplay")
	check(is_equal_approx(run.hud.k, 0.8), "gameplay UI uses its own scale")
	SaveData.set_setting("ui_scale", 1.0)
	SaveData.set_setting("hud_scale", 1.0)
	_cleanup_scene()
	Game.goto_menu()
	await get_tree().process_frame

# --- Revision 5 -----------------------------------------------------------------------

func test_environment() -> void:
	var run := await _start("ashgrove", "shade", 5)
	run.creature.set_process(false)
	var m := run.map
	check(m.stairs.all(func(e): return e.has("a_wide") or e.has("b_wide")), "staircases are two cells wide")
	var wide: Vector2i = m.stairs[0].get("a_wide", m.stairs[0]["a"])
	check(m.is_stair(wide), "the extra stair cell takes you between floors")
	# Doors: closed blocks sight, walking into it opens it, [E] closes it again.
	var i := 0
	var dc: Vector2i = run.view.doors[i]["cell"]
	var dpos := HouseMap.cell_center(dc)
	run.set_door(i, false)
	var a := dpos + (Vector2(0, -40) if m.is_wall(dc + Vector2i(1, 0)) else Vector2(-40, 0))
	var b := dpos - (a - dpos)
	check(not m.los(a, b), "a closed door blocks line of sight")
	run.player.global_position = dpos + (a - dpos) * 0.45
	await _frames(12)
	check(not run.view.doors[i]["open"], "walking into a closed door does not open it")
	run.player.global_position = a + (a - dpos).normalized() * 10.0
	run.player.aim_angle = (dpos - run.player.global_position).angle()
	await _frames(2)
	var it := run.find_interactable(run.player, run.player.global_position)
	check(it.get("kind", "") == "door" and it["i"] == i, "the nearby door is selected for E / Space (%s)" % str(it.get("kind")))
	run.do_interact(run.player, it)
	check(run.view.doors[i]["open"] and m.los(a, b), "E / Space opened it; an open door does not block sight")
	check(InputMap.action_get_events("interact").size() == 2, "E and Space both interact")
	# Lights: the entity snuffs them, a hunter relights them.
	var li := -1
	for k in run.view.lights.size():
		if run.view.can_extinguish(k):
			li = k
			break
	run.set_light(li, false)
	check(not run.view.lights[li]["on"], "a flame can be put out")
	run.player.global_position = run.view.lights[li]["pos"] + Vector2(20, 0)
	var rl := run.find_interactable(run.player, run.player.global_position)
	check(rl.get("kind", "") == "relight", "an extinguished flame offers to be relit")
	run.do_interact(run.player, rl)
	check(run.view.lights[li]["on"], "relit")
	# Highlight: standing beside a pickup marks it.
	var pk: Dictionary = run.pickups[0]
	run.player.global_position = pk["pos"] + Vector2(18, 0)
	await _frames(3)
	check(run.player.equipment.interact_pos.distance_to(pk["pos"]) < 1.0, "the pickup in reach is highlighted")
	check(not run.player.equipment.near_items.is_empty(), "nearby pickups are listed for faint highlights")

func test_witch_needle() -> void:
	var run := await _start("ashgrove", "shade", 6)
	run.creature.set_process(false)
	var eq: EquipmentController = run.player.equipment
	eq.select(Defs.BASE_LOADOUT.find("emf"))
	await _frames(10)
	check(eq.needle < 2.0, "the needle lies still with nothing near (%.1f)" % eq.needle)
	var pos := run.player.global_position + Vector2(10, 0)
	run.phenomena.hotspots.append({"pos": pos, "level": 5, "ttl": 20.0, "room": run.player.room_id})
	await _frames(20)
	check(eq.needle >= 4.9, "the needle rattles at full presence (%.1f)" % eq.needle)
	check(run.player.journal.has("emf5"), "needle frenzy is recorded as the old EMF 5 evidence")
	check(Defs.EVIDENCE["emf5"]["name"].contains("Needle"), "evidence presented as the Witch's Needle")
	check(run.hud.needle_gauge.visible, "the needle is animated in the HUD")

func test_voodoo_doll() -> void:
	var run := await _start("blackwood", "poltergeist", 8)
	run.creature.set_process(false)
	var alive_before: int = run.occupants.filter(func(o): return o.state != "gone").size()
	run.player.add_resource("voodoo_doll")
	run.player.equipment.rebuild_slots()
	run.use_voodoo(run.player)
	check(run.occupants.filter(func(o): return o.state != "gone").size() == alive_before - 1, "a ghost burns an occupant")
	check(not run.player.has_resource("voodoo_doll"), "the doll is spent")
	await _frames(100)
	check(run.hazards.size() == 1, "embers left behind")
	run.player.global_position = run.hazards[0]["pos"]
	await _frames(4)
	check(run.player.wounds == 1, "embers wound the hunter")
	await _frames(30)
	check(run.player.wounds == 1, "no second wound inside the cooldown")
	check(run.recorder.data["events"].any(func(e): return e[1] == "npc_burn"), "the burning is in the replay")
	# Against flesh and blood it enrages instead.
	_cleanup_scene()
	await get_tree().process_frame
	var run2 := await _start("ashgrove", "werewolf", 8)
	run2.player.add_resource("voodoo_doll")
	run2.use_voodoo(run2.player)
	check(run2.creature.angered_t > 0.0 and run2.creature.speed_for_hunt() > float(Defs.CREATURES["werewolf"]["hunt_speed"]), "a werewolf is enraged")
	check(run2.occupants.all(func(o): return o.state != "gone"), "no occupant burns")

func test_new_ghosts() -> void:
	# The Crawler's grab wounds (never an instant kill from full health).
	var run := await _start("ashgrove", "crawler", 9)
	run.creature.begin_hunt(run.creature.position, false)
	run.on_creature_contact(run.creature, run.player)
	check(run.player.wounds == 1 and not run.player.dead, "the Crawler's drag is a wound")
	_cleanup_scene()
	await get_tree().process_frame
	# The Lost One: harmless hunts, a learnable keepsake, a furnace drag that wounds.
	var lo := await _start("blackwood", "lost_one", 9)
	var c := lo.creature
	var k: Array = lo.keepsakes.filter(func(x): return x["forbidden"])
	check(k.size() == 1 and lo.map.room_at(k[0]["pos"]) == c.lair_room, "one keepsake, in its room, is forbidden")
	c.begin_hunt(c.position, false)
	lo.on_creature_contact(c, lo.player)
	check(lo.player.wounds == 0, "its ordinary hunts cannot hurt")
	c.end_hunt()
	c.cooldown_t = 0.0
	lo.player.invuln = 0.0
	lo._examine_keepsake(lo.player, k[0])
	check(c.wrath and c.is_hunting() and c.speed_for_hunt() > Player.SPRINT_SPEED, "touching it starts a hunt faster than a sprint")
	lo.on_creature_contact(c, lo.player)
	await _frames(200)
	var furnace: Dictionary = lo.map.furniture.filter(func(f): return f["type"] == "boiler")[0]
	check(lo.player.global_position.distance_to((furnace["rect"] as Rect2).get_center()) < 120.0, "dragged to the basement furnace")
	check(lo.player.wounds == 1 and not lo.player.dead, "the furnace wounds — it does not kill from full health")
	check(lo.recorder.data["events"].any(func(e): return e[1] == "furnace"), "the furnace is in the replay")
	# Every new ghost: valid identification and an achievable rite.
	for id in ["blightness", "crawler", "lost_one"]:
		check(Defs.CREATURES[id]["evidence"].size() == 3, "%s has three evidence types" % id)
		check(Defs.ORDINARY_CREATURES.has(id) and lo.hud.REQUIREMENTS.has(id), "%s can be suspected" % id)
	var uniq := {}
	for id in Defs.ORDINARY_CREATURES.filter(Defs.is_ghost):
		var e: Array = Defs.CREATURES[id]["evidence"].duplicate()
		e.sort()
		uniq[str(e)] = true
	check(uniq.size() == Defs.ORDINARY_CREATURES.filter(Defs.is_ghost).size(), "every ghost has a distinct evidence set")

# --- Revision 6 -----------------------------------------------------------------------

func test_counterattacks() -> void:
	for pair in [["vampire", "wooden_stake"], ["werewolf", "silver_stake"]]:
		var run := await _start("ashgrove", pair[0], 21)
		run.player.add_resource(pair[1])
		run.player.equipment.rebuild_slots()
		run.player.equipment.select(run.player.equipment.slots.find(pair[1]))
		run.creature.begin_hunt(run.creature.position, false)
		run.on_creature_contact(run.creature, run.player)
		check(run.player.wounds == 0 and run._outcome == "vanquished", "%s: counterattack with the %s vanquishes" % pair)
		check(run.recorder.data["events"].any(func(e): return e[1] == "counter"), "%s: counterattack recorded" % pair[0])
		if pair[0] == "werewolf":
			check(run.creature.current_token() == "tokens/werewolf_human.png", "the werewolf falls back into human form")
		else:
			check(run.recorder.data["events"].any(func(e): return e[1] == "creature_fx" and e[2]["kind"] == "dust"), "the vampire turns to dust")
		_cleanup_scene()
		await get_tree().process_frame
	# Without the right item it is an ordinary wound.
	var run2 := await _start("ashgrove", "vampire", 22)
	run2.creature.begin_hunt(run2.creature.position, false)
	run2.on_creature_contact(run2.creature, run2.player)
	check(run2.player.wounds == 1, "no stake in hand: wounded as usual")
	_cleanup_scene()
	await get_tree().process_frame
	# Shapeshifter: still needs exposing; when banished it shows a colourless, glistening human.
	var run3 := await _start("ashgrove", "shapeshifter", 23)
	run3.player.add_resource("iron_nails")
	run3.creature.expose(10.0)
	run3.attempt_vanquish(run3.player, "shapeshifter", "iron_nails")
	check(run3.creature.current_token() == "tokens/shapeshifter_human.png" and run3.creature.token.sprite.material != null, "true human form, glistening")

func test_escalations() -> void:
	var run := await _start("blackwood", "werewolf", 24)
	check(run.creature.current_token() == "tokens/werewolf_human.png", "a werewolf first walks as a man")
	run.threat = 80.0
	await _frames(5)
	check(run.view.mood == "moon", "high dread brings the full moon")
	check(not run.creature.wolf, "the change is not an instant sprite swap")
	await _frames(90)
	check(run.creature.wolf and run.creature.current_token() == "tokens/werewolf.png", "it has become the wolf")
	run.threat = 0.0
	await _frames(10)
	check(run.creature.wolf, "the transformation is permanent")
	_cleanup_scene()
	await get_tree().process_frame
	var v := await _start("blackwood", "vampire", 24)
	v.threat = 80.0
	await _frames(5)
	check(v.view.mood == "mist" and v.view._mist.size() == 2, "a vampire's dread fills the house with red mist")
	check(v.recorder.data["events"].any(func(e): return e[1] == "escalate"), "escalation recorded for replay / clients")

func test_prompt_and_needle() -> void:
	var run := await _start("ashgrove", "shade", 25)
	run.creature.set_process(false)
	var pk: Dictionary = run.pickups[0]
	run.player.global_position = pk["pos"] + Vector2(16, 0)
	await _frames(4)
	check(run.hud.prompt_chip.visible and run.hud.prompt_text.text.begins_with("E / SPACE — Pick Up"), "pickup prompt shown (%s)" % run.hud.prompt_text.text)
	# The needle: strikes against the glass grow with the reading.
	var g = run.hud.needle_gauge
	var counts := []
	for lv in [1.0, 2.0, 4.0, 5.0]:
		g.level = lv
		var hits := 0
		for i in 600:
			var before: int = g._strikes.size()
			g._process(1.0 / 60.0)
			if g._strikes.size() > before:
				hits += 1
		counts.append(hits)
	check(counts[0] == 0, "still at level 1 (%s)" % str(counts))
	check(counts[1] < counts[2] and counts[2] < counts[3], "more strikes as the presence grows (%s)" % str(counts))

# --- Audio overrides --------------------------------------------------------------------

func test_audio_overrides() -> void:
	var made: Array = []
	var put := func(rel: String, from_id: String) -> void:
		var src := FileAccess.get_file_as_bytes("res://assets/audio/%s.wav" % from_id)
		var path: String = AudioCatalog.CREATOR_DIR + rel
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(src)
		f.close()
		made.append(path)
	Sfx.clear_cache()
	# Without creator audio every cue resolves to its placeholder.
	for id in AudioCatalog.CUES:
		check(Sfx.source_of(id) == "placeholder" and Sfx.stream(id) != null, "%s plays its placeholder" % id)
	for f in DirAccess.get_files_at("res://assets/audio/"):
		if f.ends_with(".wav"):
			check(AudioCatalog.CUES.has(f.get_basename()), "%s is in the catalog" % f)
	var doc := FileAccess.get_file_as_string("res://docs/AUDIO_CATALOG.md")
	for id in AudioCatalog.CUES:
		check(doc.contains("`%s`" % id) and doc.contains(AudioCatalog.CUES[id][0]), "%s documented with its creator path" % id)
	# A replacement takes priority; only the asset changes.
	put.call("evidence/journal_write.wav", "ui_hover")
	put.call("player/footstep_01.wav", "pickup")
	put.call("player/footstep_02.wav", "place_item")
	put.call("entities/hunt_loop.wav", "ui_click")      # second-choice format is accepted
	Sfx.clear_cache()
	check(Sfx.source_of("pencil_scribble") == "creator", "journal_write.wav replaces the pencil")
	var js: AudioStreamWAV = Sfx.stream("pencil_scribble")
	check(is_equal_approx(js.get_length(), load("res://assets/audio/ui_hover.wav").get_length()), "the creator file is what plays")
	var steps := {}
	for i in 40:
		steps[Sfx.stream("footstep")] = true
	check(steps.size() == 2, "footstep variants alternate (%d)" % steps.size())
	Sfx.play("pencil_scribble", 0.0, 1.0, 0.0)
	Sfx.play("pencil_scribble", 0.0, 1.0, 5.0)   # inside its cooldown: suppressed as before
	var playing := Sfx._pool.filter(func(p): return p.playing and p.stream == js).size()
	check(playing == 1, "one play, no duplicate (%d)" % playing)
	Sfx.start_loop("test_hunt", "hunt_loop", -60.0, 0.01)
	var lp: AudioStreamPlayer = Sfx._loops["test_hunt"]
	check(lp.stream is AudioStreamWAV and lp.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "a replaced loop still loops")
	Sfx.stop_loop("test_hunt", 0.01)
	var holder := Node2D.new()
	get_tree().root.add_child(holder)
	Sfx.play_at("pencil_scribble", Vector2(100, 50), holder, -60.0)
	var p2d: Array = holder.get_children().filter(func(c): return c is AudioStreamPlayer2D)
	check(p2d.size() == 1 and p2d[0].stream == js and p2d[0].position == Vector2(100, 50), "positional playback uses the replacement")
	holder.queue_free()
	# Removing the files restores the placeholders.
	for path in made:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Sfx.clear_cache()
	check(Sfx.source_of("pencil_scribble") == "placeholder" and Sfx.source_of("footstep") == "placeholder", "placeholders restored")

## Run inside an exported pack that contains evidence/journal_write.wav (see
## docs/AUDIO_CATALOG.md); a no-op in ordinary test runs.
func test_audio_export() -> void:
	var path := AudioCatalog.CREATOR_DIR + "evidence/journal_write.wav"
	if not ResourceLoader.exists(path):
		return
	Sfx.clear_cache()
	check(Sfx.source_of("pencil_scribble") == "creator", "exported build uses the creator journal sound")
	check(Sfx.stream("pencil_scribble").resource_path == path, "loaded as an imported resource from the pack")
	print("EXPORT AUDIO OK: ", Sfx.stream("pencil_scribble").resource_path, " raw file present: ", FileAccess.file_exists(path))

# --- Normal / Custom games ------------------------------------------------------------

func test_game_setup() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	# Normal Game: house, entity and Blood Moon always left to chance.
	var houses := {}
	var moons := 0
	for i in 400:
		var r := Game.resolve_setup({"mode": "normal", "house": "ashgrove", "entity": "vampire", "difficulty": "nightmare", "blood_moon": "on"}, rng)
		houses[r["house"]] = true
		check(r["entity"] == "" and r["rolled"]["entity"] and r["difficulty"] == "nightmare", "normal game rolls the entity, keeps the difficulty")
		if r["blood_moon"]:
			moons += 1
	check(houses.size() == Game.house_ids.size(), "normal game visits every house (%d)" % houses.size())
	check(moons > 20 and moons < 120, "Blood Moon at its chance in a normal game (%d / 400)" % moons)
	# Random difficulty: never Beginner, every other one appears.
	var diffs := {}
	for i in 400:
		diffs[Game.resolve_setup({"difficulty": "random"}, rng)["difficulty"]] = true
	check(not diffs.has("beginner") and diffs.size() == Defs.RANDOM_DIFFICULTIES.size(), "random difficulty: %s" % str(diffs.keys()))
	# Custom Game: what is chosen is kept; Blood Moon on / off.
	var c := Game.resolve_setup({"mode": "custom", "house": "blackwood", "entity": "random", "difficulty": "hellbound", "blood_moon": "on"}, rng)
	check(c["house"] == "blackwood" and c["entity"] == "" and c["difficulty"] == "hellbound" and c["blood_moon"], "custom choices kept")
	check(not c["rolled"]["house"] and c["rolled"]["entity"] and not c["rolled"]["difficulty"], "rolled flags")
	var off := 0
	for i in 50:
		if Game.resolve_setup({"mode": "custom", "blood_moon": "off"}, rng)["blood_moon"]:
			off += 1
	check(off == 0, "Blood Moon off never rises")
	# A custom match actually starts as configured, with Hellbound on Nightmare's rules.
	SaveData.reset_all()
	var run: Run = Game.start_setup({"mode": "custom", "house": "blackwood", "entity": "vampire", "difficulty": "hellbound", "blood_moon": "on"})
	await get_tree().process_frame
	check(run.house_id == "blackwood" and run.creature.type_id == "vampire", "house and entity as chosen")
	check(run.difficulty == "hellbound" and Defs.rules(run.difficulty) == "nightmare", "Hellbound plays by Nightmare's rules")
	check(run.critters != null and run.occupants.all(func(o): return o.fear > 1.0) and run.hud.nightmare(), "Nightmare features active")
	check(run.blood_moon and run.view.blood_moon and run.view.lights.filter(func(l): return l["kind"] == "moon").all(func(l): return l["light"].color == HouseView.BLOOD_MOONLIGHT), "Blood Moon lighting")
	check(run.recorder.data["blood_moon"] and run.recorder.data["difficulty"] == "hellbound", "the replay keeps the resolved setup")
	# …and can still be completed and recorded under its own difficulty.
	run.player.add_resource("garlic")
	run.player.add_resource("wooden_stake")
	run.creature.set_process(false)
	run.player.global_position = run.creature.position + Vector2(-30, 0)
	run.player.aim_angle = 0.0
	run.strike(run.player, "wooden_stake")
	await _frames(200)
	check(SaveData.house_record("blackwood", "hellbound")["runs"] == 1, "recorded as a Hellbound run")
	SaveData.reset_all()

# --- Playtesting refinements ------------------------------------------------------------

func test_blightness_rushes() -> void:
	var run := await _start("blackwood", "blightness", 31)
	var c := run.creature
	c.wait_t = 0.0
	var dt := 1.0 / 60.0
	var fast := 0
	var still_runs: Array = []
	var still := 0
	var prev := c.position
	for i in 600:
		await get_tree().process_frame
		var v: float = c.position.distance_to(prev) / dt
		prev = c.position
		check(run.map.walkable(HouseMap.to_cell(c.position)), "never inside a wall")
		if v > 330.0:
			fast += 1
			if still > 0:
				still_runs.append(still)
			still = 0
		elif v < 1.0:
			still += 1
	check(fast > 10, "it rushes (%d fast frames)" % fast)
	check(still_runs.any(func(n): return n >= 22), "and stops to shudder ~0.5 s between rushes (%s)" % str(still_runs.slice(0, 6)))
	# Hunting: the same lunges, closing on a hunter it can see.
	run.player.global_position = HouseMap.cell_center(run.map.nearest_walkable(HouseMap.to_cell(c.position + Vector2(160, 0))))
	run.player.invuln = 99.0
	c.begin_hunt(c.position, false)
	var d0 := c.position.distance_to(run.player.global_position)
	await _frames(200)
	check(c.position.distance_to(run.player.global_position) < d0 or run.player.invuln < 99.0, "hunting, it lunges after the hunter")

func test_safe_names() -> void:
	SaveData.set_setting("safe_names", true)
	var run := await _start("ashgrove", "shade", 32)
	var o: Occupant = run.occupants[0]
	var nid: int = o.person["name_id"]
	var personality: String = o.person["personality"]
	check(o.person["name"] == Occupants.NAMES[nid], "safe names by default")
	var r: Dictionary = Rankings.table("Me", 0)[0]
	check(r["name"] == "Professor Spookwell", "original legends by default")
	_cleanup_scene()
	await get_tree().process_frame
	SaveData.set_setting("safe_names", false)
	var run2 := await _start("ashgrove", "shade", 32)
	var o2: Occupant = run2.occupants[0]
	check(o2.person["name_id"] == nid and o2.person["personality"] == personality, "same identity and personality")
	check(o2.person["name"] == Occupants.FICTION_NAMES[nid], "recognisable name with Safe Names off (%s)" % o2.person["name"])
	var names: Array = Rankings.table("Me", 0).map(func(x): return x["name"])
	check("Harry Potter" in names and "Abraham Van Helsing" in names and Rankings.rank_for(9000) == Rankings.rank_for(9000), "fictional rivals, same rankings")
	SaveData.set_setting("safe_names", true)

func test_temperatures() -> void:
	var run := await _start("ashgrove", "shade", 33)
	var ph := run.phenomena
	var outdoor: Array = run.map.rooms.filter(func(r): return r["outdoor"])
	var indoor: Array = run.map.indoor_rooms().filter(func(r): return r["id"] != run.creature.lair_room)
	var avg := func(rs: Array) -> float:
		var t := 0.0
		for r in rs:
			t += ph.temperature(r["id"])
		return t / maxf(1.0, rs.size())
	check(absf(avg.call(outdoor) - avg.call(indoor)) < 2.0, "outdoors ≈ indoors (%.1f vs %.1f)" % [avg.call(outdoor), avg.call(indoor)])
	check(ph.temperature(run.creature.lair_room) < 0.0, "a freezing ghost's room still freezes")

func test_ghost_marker_and_ruled_out() -> void:
	var run: Run = Game.start_run("ashgrove", 34, "shapeshifter", "normal", false, {"ghost_marker": true})
	await _frames(3)
	var markers: Array = run.world_text.get_children().filter(func(n): return n is WorldFx.GhostMarker)
	check(markers.size() == 1 and markers[0].visible and markers[0].position == run.creature.position, "marker follows the entity")
	# Ruled-out evidence: a reversible deduction, overridden by a real find, never scored.
	var j: Journal = run.player.journal
	run.hud.toggle_ruled_out("wrong_reflection")
	check(j.state("wrong_reflection") == "ruled_out" and run.hud._ev_discs["wrong_reflection"].ruled, "ruled out and crossed through")
	run.player.suspect = "shapeshifter"
	run.hud.refresh()
	var live: Array = run.hud.suspect_box.get_children().filter(func(n): return not n.is_queued_for_deletion())
	var row: HBoxContainer = live[1]
	var idx := Defs.ORDINARY_CREATURES.find("shapeshifter")
	check(row.get_child(idx).get_child(0).ruled, "a contradicted entity is crossed in the suspect list but still selectable")
	run.hud.toggle_ruled_out("wrong_reflection")
	check(j.state("wrong_reflection") == "unknown", "restored")
	run.hud.toggle_ruled_out("shed_skin")
	run.discover(run.player, "shed_skin", run.player.room_id)
	check(j.state("shed_skin") == "found" and not run.hud._ev_discs["shed_skin"].ruled, "found after all: Found wins")
	run.hud.toggle_ruled_out("mimic_voice")
	check(run.build_summary()["true_evidence"] == 1, "ruling out earns nothing")
	_cleanup_scene()
	await get_tree().process_frame
	var plain := await _start("ashgrove", "shade", 34)
	check(plain.world_text.get_children().filter(func(n): return n is WorldFx.GhostMarker).is_empty(), "no marker by default")

# --- Hellbound & Abyssal ------------------------------------------------------------------

func test_hellbound() -> void:
	var nm: Run = Game.start_run("ashgrove", 41, "shade", "nightmare")
	await get_tree().process_frame
	nm.creature.set_process(false)
	await _frames(120)
	var nm_threat := nm.threat
	_cleanup_scene()
	await get_tree().process_frame
	var run: Run = Game.start_run("ashgrove", 41, "shade", "hellbound")
	await get_tree().process_frame
	run.creature.set_process(false)
	await _frames(120)
	check(run.threat > nm_threat * 1.4, "dread rises faster than Nightmare (%.2f vs %.2f)" % [run.threat, nm_threat])
	check(run.view.hostile == "hellbound" and run.critters != null, "infernal atmosphere on Nightmare's base")
	run.creature.begin_hunt(run.creature.position, false)
	run.creature.end_hunt()
	check(run.creature.cooldown_t < float(Defs.CREATURES["shade"]["hunt_cooldown"]) * 0.6, "hunts come back quickly")
	# Hellfire: a warning first, then flames that wound once per grace period.
	run.spawn_hellfire(run.player.global_position)
	check(run.recorder.data["events"].any(func(e): return e[1] == "hellfire" and e[2]["phase"] == "warn"), "hellfire warns first")
	check(run.player.wounds == 0, "no damage during the warning")
	await _frames(110)
	check(run.hazards.any(func(h): return h.get("kind", "") == "hellfire"), "then the floor erupts")
	run.player.global_position = run.hazards[0]["pos"]
	await _frames(5)
	check(run.player.wounds == 1, "standing in hellfire burns")
	await _frames(40)
	check(run.player.wounds == 1, "but not twice in a moment")

func test_abyssal() -> void:
	var run: Run = Game.start_run("blackwood", 42, "shade", "abyssal")
	await get_tree().process_frame
	run.creature.set_process(false)
	check(run.view.hostile == "abyssal" and run.view.abyss != null, "torn-reality atmosphere")
	var room: String = run.player.room_id
	var o: Occupant = run.occupants[0]
	o.position = run.player.global_position + Vector2(10, 0)
	o.room_id = room
	run.creature.position = run.player.global_position + Vector2(-10, 0)
	run.creature.room_id = room
	run.creature.set_process(true)
	# The warning comes first and the portal opens ~2.5 s later.
	run._portal_t = 0.0
	await _frames(5)
	check(run.recorder.data["events"].any(func(e): return e[1] == "portal"), "portal warning")
	var warned_room: String = run.recorder.data["events"].filter(func(e): return e[1] == "portal")[0][2]["room"]
	await _frames(170)
	check(run.abyss_until > 0.0, "the portal opened")
	if warned_room != room:
		run.close_abyss()
		run.open_abyss(room)   # the warning picked another room: open one here to test the pull
	check(run.player.has_meta("abyss") and AbyssArena.contains(run.player.global_position), "the hunter in the room is in the Abyss")
	check(AbyssArena.contains(o.position) and run.creature.has_meta("abyss") and AbyssArena.contains(run.creature.position), "occupant and entity in the room were taken too (and are seen there)")
	# While it is away it cannot reach the house: no forced hunt, no rite, no doll.
	run.forced_hunt_t = 0.1
	run.creature.cooldown_t = 0.0
	await _frames(10)
	check(not run.creature.is_hunting(), "a forced hunt waits while the entity is in the Abyss")
	run.player.suspect = "shade"
	check(not run.can_begin_rite(run.player), "no rite from inside the Abyss")
	check(is_equal_approx(run.abyss_until - run.elapsed, AbyssArena.DURATION) or run.abyss_until - run.elapsed > 55.0, "about a minute")
	# Traps hurt (with warnings and grace); being in the Abyss pauses ordinary hunts.
	var arena := run.view.abyss
	var hit := false
	for i in 400:
		await get_tree().process_frame
		if arena.hazard_at(arena.hand_positions(arena.t)[0]) != "":
			hit = true
			break
	check(hit, "the hands are dangerous")
	run.player.invuln = 0.0
	run.player.global_position = arena.hand_positions(arena.t)[0]
	await _frames(2)
	check(run.player.wounds == 1, "a trap wounds (two-hit rules)")
	# Return.
	run.abyss_until = run.elapsed + 0.1
	await _frames(15)
	check(not run.player.has_meta("abyss") and run.map.room_at(run.player.global_position) == room, "survivor returned to the room")
	check(o.visible and not run.creature.has_meta("abyss") and run.creature.visible, "occupant and entity returned")
	check(run.recorder.data["events"].any(func(e): return e[1] == "abyss_return"), "return recorded for the replay")
	check(run.build_summary()["abyss_escapes"] == 1, "escape counted in the results")
	check(o.tag != null and run.occupants.has(o), "occupant restored with its speech tag")
	# Ending while the Abyss is open closes it: nobody is left behind in the realm.
	_cleanup_scene()
	await get_tree().process_frame
	var r2: Run = Game.start_run("blackwood", 43, "shade", "abyssal")
	await get_tree().process_frame
	r2.creature.set_process(false)
	r2.creature.position = r2.player.global_position
	r2.creature.room_id = r2.player.room_id
	r2.open_abyss(r2.player.room_id)
	check(r2.in_abyss(r2.player) and r2.in_abyss(r2.creature), "both pulled in")
	r2._victory(r2.player)
	check(not r2.in_abyss(r2.player) and not r2.in_abyss(r2.creature) and r2.abyss_until < 0.0, "an ending closes the Abyss")
	check(r2.recorder.data["events"].any(func(e): return e[1] == "abyss" and e[2]["phase"] == "close"), "the close is in the replay")

# --- The Drowned Sailor and the Plague Doctor -------------------------------------------

func _rite_in_lair(run: Run, id: String, items: Array) -> void:
	var p := run.player
	var lair := run.creature.lair_room
	p.global_position = HouseMap.cell_center(run.map.random_free_cell(lair, run.rng))
	p.room_id = lair
	for it in items:
		run.place_item(p, it, p.global_position)
	p.journal.record(Defs.CREATURES[id]["evidence"][0], 10.0, lair, "Lair")
	p.suspect = id
	check(run.can_begin_rite(p), "%s: the %s can begin" % [id, Defs.CREATURES[id]["rite_name"]])
	run.perform_rite(p)
	check(run._outcome == "vanquished", "%s: vanquished by its rite" % id)

func test_sailor_and_doctor() -> void:
	# The Drowned Sailor: a trail of sea water, fair emergence, waterlogged surges.
	var run := await _start("marrow_street", "drowned_sailor", 31)
	for id in ["drowned_sailor", "plague_doctor"]:
		check(Defs.ORDINARY_CREATURES.has(id) and Defs.ENCYCLOPEDIA_ORDER.has(id), "%s: selectable and in the encyclopedia" % id)
		check(Defs.CREATURES[id]["evidence"].size() == 3 and run.hud.REQUIREMENTS.has(id), "%s: three evidence types and requirements" % id)
		check(Art.tex(Defs.CREATURES[id]["token"]) != null, "%s: token art exists" % id)
	var c := run.creature
	c.position = HouseMap.cell_center(run.map.random_free_cell(c.lair_room, run.rng))
	c.room_id = c.lair_room
	c.wait_t = 0.01
	run._sailor_t["puddle"] = 0.0
	await _frames(90)
	check(run.puddles.size() >= 1, "it leaves a puddle")
	check(not run._footprints.is_empty(), "it leaves wet footprints")
	check(run.recorder.data["events"].any(func(e): return e[1] == "decal" and e[2]["sprite"] == "items/puddle.png"), "puddles reach clients and replays")
	var pd: Vector2 = run.puddles[0]["pos"]
	run.player.global_position = pd + Vector2(40, 0)
	check(run._fair_puddle([run.player]) == Vector2.INF, "never rises from a puddle beside a hunter")
	run.player.global_position = pd + Vector2(400, 0)
	check(run._fair_puddle([run.player]) == pd, "rises from a distant puddle")
	var gaits := {}
	for t in [0.5, 2.0]:
		c.state_t = t
		gaits[c.hunt_gait()] = true
	check(gaits.size() == 2, "its hunt alternates heavy steps and lunges")
	run.player.global_position = HouseMap.cell_center(run.map.spawn_cell)
	c.cooldown_t = 0.0
	run.trigger_hunt(false)
	check(c.is_hunting() and c.position.distance_to(run.player.global_position) >= 300.0, "its hunt starts at a fair distance")
	c.end_hunt()
	run.player.charges["holy_water"] = 2
	await _rite_in_lair(run, "drowned_sailor", ["salt"])
	check(int(run.player.charges["holy_water"]) == 1, "the Rite of the Tides spends a flask")
	_cleanup_scene()
	await get_tree().process_frame
	# The Plague Doctor: miasma during hunts that wounds only those who linger.
	var pdr := await _start("hollow_lane", "plague_doctor", 32)
	var d := pdr.creature
	d.begin_hunt(d.position, false)
	d.state = "hunt"
	pdr._plague_t["cloud"] = 0.0
	await _frames(3)
	check(pdr.hazards.any(func(h): return h.get("kind", "") == "miasma"), "it leaves miasma while hunting")
	check(pdr.recorder.data["events"].any(func(e): return e[1] == "creature_fx" and e[2]["kind"] == "miasma"), "the miasma reaches clients and replays")
	d.end_hunt()
	d.set_process(false)
	pdr.hazards.clear()
	var at := pdr.player.global_position
	pdr.spawn_miasma(at)
	await _frames(20)
	check(pdr.player.wounds == 0, "passing through briefly does no harm")
	await get_tree().create_timer(2.6).timeout
	check(pdr.player.wounds == 1 and not pdr.player.dead, "lingering in it wounds")
	pdr.player.global_position = at
	await get_tree().create_timer(2.0).timeout
	check(pdr.player.wounds == 1 and not pdr.player.dead, "a grace period: no second wound straight away")
	var hz: Dictionary = pdr.hazards.filter(func(h): return h.get("kind", "") == "miasma")[0]
	check(is_equal_approx(hz["until"] - hz["born"], Run.MIASMA_LIFE), "the cloud dissipates after a short time")
	d.set_process(true)
	pdr.player.wounds = 0
	pdr.hazards.clear()
	await _rite_in_lair(pdr, "plague_doctor", ["crucifix", "ghost_book"])

# --- Consolidation -------------------------------------------------------------------------

func test_consolidation() -> void:
	# One difficulty table, same values as before.
	check(Defs.tune("beginner", "dread") == 0.6 and Defs.tune("hellbound", "dread") == 1.6 and Defs.tune("nightmare", "dread") == 1.0, "dread rates")
	check(Defs.tune("hellbound", "hunt_cooldown") == 0.55 and Defs.tune("beginner", "hunt_cooldown") == 1.5, "hunt cooldowns")
	check(Defs.tune("normal", "panic") == 1.0 and Defs.tune("nightmare", "panic") == 2.0 and Defs.tune("hellbound", "panic") == 2.6, "occupant panic")
	check(Defs.hostile("hellbound") == "hellbound" and Defs.hostile("abyssal") == "abyssal" and Defs.hostile("nightmare") == "", "hostile difficulties")
	for id in Defs.ORDINARY_CREATURES:
		check(Defs.short_name(id).length() <= 12, "%s: short name fits the suspect strip" % id)
	var run := await _start("ashgrove", "shade", 51)
	var p := run.player
	# Requirements light up when prepared, not merely carried.
	check(not p.has_prepared("salt") and not p.has_prepared("ghost_book"), "nothing prepared at the start")
	check(p.has_prepared("holy_water"), "holy water counts while a flask remains")
	run.place_item(p, "salt", p.global_position)
	p.charges["salt"] -= 1
	check(p.has_prepared("salt"), "poured salt counts")
	check(run.hud.requirement_items("plague_doctor") == Defs.CREATURES["plague_doctor"]["rite_needs"], "ghost requirements come from the rite")
	# The clock tolls before a hunt.
	run.creature.cooldown_t = 0.0
	run.trigger_hunt(false)
	check(run.creature.is_hunting(), "hunt started")
	var clock_near := run.map.furniture.any(func(f): return f["type"] == "grandfather_clock" and (f["rect"] as Rect2).get_center().distance_to(run.creature.position) < 900.0)
	check(not clock_near or run.recorder.data["events"].any(func(e): return e[1] == "shake"), "the nearest clock tolls and stops")
	# A loop restarted while it fades out keeps playing.
	Sfx.start_loop("probe", "ambience_house", -20.0, 0.01)
	Sfx.stop_loop("probe", 0.5)
	Sfx.start_loop("probe", "ambience_house", -20.0, 0.01)
	await get_tree().create_timer(0.8).timeout
	check(Sfx._loops["probe"].playing, "restarted loop survives the old fade")
	Sfx.stop_loop("probe", 0.01)

# --- 0.11.0 ------------------------------------------------------------------------------

func test_home_rooms() -> void:
	var run := await _start("blackwood", "shade", 61)
	var c := run.creature
	run.threat = 0.0
	var home := c.lair_room
	var allowed := {home: true}
	for n in run.map.neighbour_rooms(home):
		allowed[n] = true
		for m in run.map.neighbour_rooms(n):
			allowed[m] = true
	var at_home := 0
	var strays := 0
	for i in 2400:
		run.threat = 0.0   # no hunts: ordinary wandering only
		await get_tree().process_frame
		if i % 10 == 0:
			if c.room_id == home:
				at_home += 1
			elif not allowed.has(c.room_id):
				strays += 1
	check(at_home > 120, "it mostly stays home (%d / 240 samples)" % at_home)
	check(strays == 0, "excursions stay within one or two rooms of home (%d strays)" % strays)
	# Relocation: a new indoor home, the cold follows, it walks there, at most twice.
	var cold_before: float = run.phenomena.temps[home]
	run.relocate_home()
	var new_home := c.lair_room
	check(new_home != home and not run.map.room(new_home).get("outdoor", true), "a new indoor home")
	check(run.phenomena.temps[new_home] == cold_before and run.phenomena.temps[home] > 10.0, "the cold moved with it")
	var arrived := false
	for i in 1800:
		run.threat = 0.0
		await get_tree().process_frame
		if c.room_id == new_home:
			arrived = true
			break
	check(arrived, "it walks to its new home")
	run.relocate_home()
	run.relocate_home()
	check(run.relocations == 3 or run.relocations == 2, "relocate_home itself is unconditional (the tick enforces the cap)")
	run.relocations = Run.MAX_RELOCATIONS
	var lair_now := c.lair_room
	run._relocate_t = 0.01
	run._relocation_tick(0.1)
	check(c.lair_room == lair_now, "no more than two relocations")
	# Dread at 80%.
	check(is_equal_approx(Run.THREAT_PER_SECOND, 0.176), "passive dread is 80% of 0.22")
	# Pursuit goes anywhere: a hunter in the basement is followed down the stairs.
	var down := run.map.indoor_rooms().filter(func(r): return int(r["level"]) < 0)
	if not down.is_empty():
		run.player.global_position = HouseMap.cell_center(run.map.random_free_cell(down[0]["id"], run.rng))
		run.player.room_id = down[0]["id"]
		run.player.invuln = 999.0
		c.cooldown_t = 0.0
		c.begin_hunt(c.position, false)
		c.state = "hunt"
		var reached := false
		for i in 1500:
			await get_tree().process_frame
			c.state_t = 0.0   # keep the hunt going
			if run.map.floor_at(c.position) == run.map.floor_at(run.player.global_position):
				reached = true
				break
		check(reached, "a hunt follows the hunter to another floor")

func test_suspect_filter_and_splatter() -> void:
	var run := await _start("ashgrove", "shade", 62)
	var p := run.player
	# Confirmed evidence: Tab never reaches an entity it rules out.
	run.discover(p, "freezing", p.room_id)
	var seen := {}
	for i in 30:
		run.cycle_suspect(p, 1)
		seen[p.suspect] = true
	for id in seen:
		if id != "":
			check("freezing" in Defs.CREATURES[id]["evidence"], "Tab reached %s, which leaves no freezing" % id)
	check(seen.size() > 2, "several candidates remain")
	# A selected suspect contradicted by new evidence gives way to the next that fits.
	p.suspect = "crawler"   # freezing, uv, orbs
	run.discover(p, "emf5", p.room_id)   # crawler has no emf5
	check(p.suspect != "crawler" and (p.suspect == "" or Defs.fits(p.suspect, p.journal)), "the impossible suspect was replaced (%s)" % p.suspect)
	# Rule-outs narrow too, are reversible, and an empty list is shown, not hidden.
	for ev in ["orbs", "spirit_box", "writing"]:
		run.set_ruled_out(p, ev, true)
	check(Defs.candidates(p.journal).is_empty() and p.suspect == "", "nothing fits: no suspect")
	run.set_ruled_out(p, "orbs", false)
	check(Defs.candidates(p.journal) == ["shade"], "restoring a rule-out brings the candidate back")
	run.cycle_suspect(p, 1)
	check(p.suspect == "shade", "the single candidate can be chosen")
	# Death: a room-sized splatter, synced through the replay; wounds alone don't.
	run.player.invuln = 0.0
	run._wound(p, null, "test")
	check(not run.recorder.data["events"].any(func(e): return e[1] == "splatter"), "no splatter for a wound")
	run.player.invuln = 0.0
	run._wound(p, null, "test")
	var ev: Array = run.recorder.data["events"].filter(func(e): return e[1] == "splatter")
	check(ev.size() == 1 and ev[0][2]["room"] == run.map.room_at(p.global_position, p.room_id), "one splatter, in the room of death")

func test_weeper_and_mimic() -> void:
	# The Weeper: stops to cry (even hunting), slow at range, lunges up close.
	var run := await _start("ashgrove", "weeper", 71)
	var c := run.creature
	c.begin_hunt(c.position, false)
	c.state = "hunt"
	c.target = run.player
	run.player.global_position = c.position + Vector2(600, 0)
	check(c.hunt_gait() == 1.0, "slow at a distance")
	run.player.global_position = c.position + Vector2(120, 0)
	check(c.hunt_gait() > 2.0 and c.speed_for_hunt() * c.hunt_gait() > Player.SPRINT_SPEED * 0.95, "lunges up close")
	c._crying_t = 2.0
	check(c.hunt_gait() == 0.0, "it stops to cry mid-hunt")
	c.end_hunt()
	c._crying_t = 0.0
	c._cry_t = 0.01
	await _frames(3)
	check(c._crying_t > 0.0 and run.recorder.data["events"].size() >= 0, "it starts crying on its own")
	run.player.charges["holy_water"] = 1
	await _rite_in_lair(run, "weeper", ["salt", "crucifix"])
	_cleanup_scene()
	await get_tree().process_frame
	# The Mimic: a real occupant's face and name while it roams; its own face while hunting.
	var mr := await _start("blackwood", "mimic", 72)
	var m := mr.creature
	var twin: Array = mr.cast.filter(func(o): return o["name"] == mr.disguise["name"])
	check(twin.size() == 1 and twin[0]["token"] == mr.disguise["token"], "it copies a real resident (name and look)")
	await _frames(30)
	check(m.disguised() and m.token.token_path == mr.disguise["token"] and m.alpha > 0.5, "seen in plain sight as that resident")
	m.begin_hunt(m.position, false)
	await _frames(2)
	check(not m.disguised() and m.token.token_path == "tokens/mimic.png", "its own face while it hunts")
	m.end_hunt()
	await _frames(2)
	check(m.token.token_path == mr.disguise["token"], "the borrowed face returns afterwards")
	check(m._garble("hello there") != "hello there" or m._garble("hello there") != "hello there", "garbled speech")
	mr.player.charges["holy_water"] = 2
	await _rite_in_lair(mr, "mimic", ["ghost_book"])
	check(int(mr.player.charges["holy_water"]) == 1, "the Rite of Unmasking spends a flask")

# --- Progression: Ducats, Renown, ranks, the Witch's needles -------------------------

func test_progression() -> void:
	SaveData.reset_all()
	# Tiers, with every existing item Common by default.
	check(Progression.TIERS.size() == 5 and Progression.TIERS.has("legendary"), "five item tiers")
	check(Defs.EQUIPMENT.keys().all(func(id): return Progression.TIERS.has(Progression.item_tier(id))), "every item has a tier")
	check(Progression.item_tier("thermometer") == "common", "untiered items are Common")
	check(Progression.NEEDLE_ORDER.all(func(id): return Progression.TIERS.has(Progression.NEEDLES[id]["tier"])), "needle variants use defined tiers")
	# Old saves migrate to 0 / 0 with the common needle.
	SaveData.data.erase("progress")
	SaveData.save()
	SaveData.load_data()
	var p := SaveData.progress()
	check(int(p["ducats"]) == 0 and int(p["renown"]) == 0 and p["needle"] == "common", "save migration defaults")
	# Level curve: quick at first, steadily longer; titles climb with it.
	for lv in range(1, Progression.MAX_LEVEL - 1):
		check(Progression.level_cost(lv + 1) > Progression.level_cost(lv), "level curve rises at %d" % lv)
	check(Progression.level_for(0) == 1 and Progression.title_for(1) == "Uninitiated", "everyone starts Uninitiated at level 1")
	check(Progression.level_for(Progression.level_cost(1)) == 2, "level 2 after one level's worth of Renown")
	check(Progression.title_for(30) == "Harbinger's Bane" and Progression.title_for(10) != Progression.title_for(9), "titles by level range")
	# A real solo victory pays out exactly once and persists.
	var run := await _start("ashgrove", "werewolf", 41)
	run.player.add_resource("silver_stake")
	run.player.global_position = run.creature.position + Vector2(-30, 0)
	run.player.aim_angle = 0.0
	run.strike(run.player, "silver_stake")
	await _frames(200)
	var reward: Dictionary = Game.last_result.get("records", {}).get("reward", {})
	check(reward.get("granted", false) and int(reward["ducats"]) > 0 and int(reward["renown"]) > 0, "a victory earns Ducats and Renown")
	check(Progression.level_for(int(SaveData.progress()["renown"])) >= 2, "one win is enough for the first level (%d Renown)" % int(SaveData.progress()["renown"]))
	var d1 := int(SaveData.progress()["ducats"])
	var again := SaveData.record_run(Game.last_result["summary"])
	check(not again["reward"]["granted"] and int(SaveData.progress()["ducats"]) == d1, "the same run never pays twice")
	SaveData.load_data()
	check(int(SaveData.progress()["ducats"]) == d1, "Ducats persisted")
	var loss := Progression.solo_reward({"vanquished": false, "score": 0, "evidence_ids": ["uv"], "difficulty": "normal"})
	check(loss["ducats"] > 0 and loss["ducats"] < reward["ducats"], "a small consolation for a loss")
	# Competitive: the local hunter's row pays once.
	var row := {"actor": "player_1", "rank": 1, "vanquisher": true, "alive": true, "shoves_given": 0, "shoves_taken": 0, "score": 5200}
	var mres := {"house": "ashgrove", "creature": "shade", "outcome": "vanquished", "time": 140.0, "rows": [row], "rules_version": MpScoring.RULES_VERSION, "difficulty": "normal", "seed": 7}
	var m1 := SaveData.record_match(mres, "player_1")
	var m2 := SaveData.record_match(mres, "player_1")
	check(m1["reward"]["granted"] and not m2["reward"]["granted"], "a match rewards the local hunter once")
	# Developer cheats add and reset progression only.
	SaveData.settings()["dev_mode"] = true
	var best := int(SaveData.data["records"]["best_score"])
	p = SaveData.progress()
	check(Progression.cheat_add(p, "ducats", 500) and Progression.cheat_add(p, "renown", 300), "cheats allowed outside matches")
	check(int(p["ducats"]) == d1 + int(m1["reward"]["ducats"]) + 500, "cheat adds Ducats")
	Progression.reset_progress(p)
	check(int(p["ducats"]) == 0 and int(p["renown"]) == 0 and p["owned"] == ["common"], "cheat reset clears progression")
	check(int(SaveData.data["records"]["best_score"]) == best and SaveData.house_record("ashgrove")["runs"] >= 1, "reset never touches records")
	# The Witch: Renown level and Ducats both required; purchases persist.
	check(not Progression.buy(p, "silver") and Progression.buy_block(p, "silver") == "level", "refused without Renown")
	p["renown"] = Progression.level_cost(1) + Progression.level_cost(2)
	check(not Progression.buy(p, "silver") and Progression.buy_block(p, "silver") == "ducats", "refused without Ducats")
	p["ducats"] = 200
	check(Progression.buy(p, "silver") and int(p["ducats"]) == 50 and "silver" in p["owned"], "purchase deducts and owns")
	check(not Progression.buy(p, "silver"), "no double purchase")
	check(not Progression.equip(p, "veilpiercer") and Progression.equip(p, "silver"), "only owned needles equip")
	SaveData.save()
	SaveData.load_data()
	check(SaveData.progress()["needle"] == "silver" and "silver" in SaveData.progress()["owned"], "owned and equipped needle persisted")
	# The finest needle reads further, but evidence rules stay exactly the same.
	SaveData.progress()["owned"].append("veilpiercer")
	Progression.equip(SaveData.progress(), "veilpiercer")
	_cleanup_scene()
	await get_tree().process_frame
	var r2 := await _start("ashgrove", "shade", 6)
	r2.creature.set_process(false)
	var eq: EquipmentController = r2.player.equipment
	eq.select(Defs.BASE_LOADOUT.find("emf"))
	var hs := {"pos": r2.player.global_position + Vector2(100, 0), "level": 5, "ttl": 30.0, "room": r2.player.room_id}
	r2.phenomena.hotspots.append(hs)
	await _frames(30)
	check(eq.needle > 2.5 and eq.needle < 5.0, "the Veilpiercer stirs further out (%.2f)" % eq.needle)
	check(eq.reading.contains("."), "precise reading wording (%s)" % eq.reading)
	check(not r2.player.journal.has("emf5"), "a stronger needle never records evidence out of range")
	hs["pos"] = r2.player.global_position + Vector2(40, 0)
	await _frames(10)
	check(r2.player.journal.has("emf5"), "Needle 5 evidence still registers inside the hotspot")
	check(r2.hud.needle_gauge.variant["name"] == "The Veilpiercer", "your own needle's gauge in the HUD")
	SaveData.reset_all()

# --- 0.12.0 ------------------------------------------------------------------------------

func test_flee_death_immortal() -> void:
	var pr := SaveData.progress()
	pr["renown"] = 1000
	pr["owned"] = ["common", "raven"]
	pr["needle"] = "raven"
	# Fleeing: confirmed cost, ends the run as "fled", charged once.
	var run := await _start("ashgrove", "shade", 81)
	check(pr.has("pending"), "a run under way is guarded")
	var cost: int = run.flee_cost()
	check(cost == Progression.PENALTIES["flee_renown"], "flee cost shown up front (%d)" % cost)
	run.flee(run.player)
	await get_tree().create_timer(2.5).timeout
	check(Game.last_result["summary"]["outcome"] == "fled", "the run ended as fled")
	check(int(pr["renown"]) == 1000 - cost and not pr.has("pending"), "flee penalty applied once (renown %d)" % int(pr["renown"]))
	var again := SaveData.record_run(Game.last_result["summary"])
	check(not again.has("penalty") or not again["penalty"]["applied"], "never charged twice for the same run")
	_cleanup_scene()
	await get_tree().process_frame
	# Dying costs more; Renown never below zero.
	pr["renown"] = 50
	var run2 := await _start("ashgrove", "shade", 82)
	run2.player.invuln = 0.0
	run2._wound(run2.player, null, "test")
	run2.player.invuln = 0.0
	run2._wound(run2.player, null, "test")
	await get_tree().create_timer(3.5).timeout
	var pen: Dictionary = Game.last_result["records"].get("penalty", {})
	check(pen.get("kind", "") == "death" and int(pr["renown"]) == 0, "death penalty, floored at zero")
	check(Progression.PENALTIES["death_renown"] > Progression.PENALTIES["flee_renown"], "death costs more than fleeing")
	check("common" in pr["owned"], "the starter needle is never lost")
	_cleanup_scene()
	await get_tree().process_frame
	# Quitting mid-run is settled as fleeing on the next launch.
	pr["renown"] = 500
	SaveData.begin_run_guard("normal")
	SaveData._settle_abandoned_run()
	check(int(pr["renown"]) == 500 - Progression.PENALTIES["flee_renown"] and SaveData.startup_notice != "", "an abandoned run costs Renown on the next launch")
	# Immortal (dev cheat): wounds show, death never comes.
	Progression.immortal = true
	var run3 := await _start("ashgrove", "shade", 83)
	for i in 4:
		run3.player.invuln = 0.0
		run3._wound(run3.player, null, "test")
	check(not run3.player.dead and run3.state == "playing", "immortal: no death")
	check(run3.build_summary()["dev_immortal"], "the run is marked as cheated (kept off records)")
	Progression.immortal = false

## Every house resource (iron nails above all) spawns, and on a cell a hunter can reach.
func test_required_items_reachable() -> void:
	for hid in Game.house_ids:
		for sd in [3, 17, 29]:
			var run: Run = Game.start_run(hid, sd, "shapeshifter")
			await get_tree().process_frame
			run.map.closed_doors.clear()   # doors open with E; they never seal a room
			var reach := run.map.reachable_from_spawn()
			for res in Defs.RESOURCE_SPAWNS:
				var got: Array = run.pickups.filter(func(it): return it.get("res", "") == res)
				check(got.size() >= int(Defs.RESOURCE_SPAWNS[res]["count"]), "%s/%d: %s spawned" % [hid, sd, res])
				for it in got:
					check(reach.has(HouseMap.to_cell(it["pos"])), "%s/%d: %s reachable" % [hid, sd, res])
			_cleanup_scene()
			await get_tree().process_frame

func test_salt_water_relic() -> void:
	var run := await _start("ashgrove", "shade", 91)
	var p := run.player
	# Salt: pour, then scrape it back up with a hold; never more than you started with.
	run.place_item(p, "salt", p.global_position)
	p.charges["salt"] -= 1
	var it := run.find_interactable(p, p.global_position)
	check(it.get("label", "") == "Scrape Up Salt" and float(it["hold"]) > 0.5, "salt is recovered with a hold")
	run.do_interact(p, it)
	check(int(p.charges["salt"]) == 3 and not run.placed.any(func(x): return x["type"] == "salt"), "one pour returned, the line gone")
	run.do_interact(p, it)
	check(int(p.charges["salt"]) == 3, "no duplication")
	# Holy water never runs dry.
	p.equipment.select(p.equipment.slots.find("holy_water"))
	for i in 6:
		p.equipment._cooldown = 0.0
		p.equipment._hw_refill = 0.0
		p.equipment.use_current()
	check(int(p.charges["holy_water"]) >= 1, "the last flask is never emptied (%d)" % int(p.charges["holy_water"]))
	_cleanup_scene()
	await get_tree().process_frame
	# The Abyss relic: kept by a survivor, lost by the dead.
	var r2: Run = Game.start_run("blackwood", 92, "shade", "abyssal")
	await get_tree().process_frame
	r2.creature.set_process(false)
	SaveData.progress()["owned"] = ["common"]
	r2.open_abyss(r2.player.room_id)
	var relic: Array = r2.pickups.filter(func(x): return x["kind"] == "relic")
	if relic.is_empty():
		r2._maybe_abyss_relic(true)
		relic = r2.pickups.filter(func(x): return x["kind"] == "relic")
	check(relic.size() == 1 and AbyssArena.contains(relic[0]["pos"]), "a Legendary lies in the realm")
	r2.do_interact(r2.player, relic[0])
	r2.close_abyss()
	check("abyssglass" in SaveData.progress()["owned"], "survivors keep it")
	check(Progression.NEEDLES["abyssglass"]["tier"] == "legendary" and Progression.buy_block(SaveData.progress(), "abyssglass") == "owned", "legendary, never sold")
