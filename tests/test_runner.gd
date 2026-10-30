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
		"test_audio_export",
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
		check(m.floors() == [0, -1], "%s: two floors" % id)
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
	check(run.player.suspect == sus, "discovering evidence never changes the suspect")

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
