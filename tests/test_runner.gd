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
	check(Game.house_ids.size() == 5, "five houses expected, got %d" % Game.house_ids.size())
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
				check(reach.has(HouseMap.to_cell(p["pos"])), "%s/%s: %s unreachable" % [house, cr, p["res"]])
			var silver := run.pickups.filter(func(p): return p["res"] == "silverware").size()
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
