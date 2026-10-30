extends Node
## Balance playtest: a scripted investigator plays real runs (walking speed,
## path-following, fleeing hunts) for every creature in every house and reports
## times, survival and evidence. It knows the answer (it is a test bot) but has
## to physically do everything a player does.
##   godot --headless --fixed-fps 60 --path . res://tests/bot_playtest.tscn [-- seeds]

const MAX_TIME := 480.0

var results: Array = []
var run: Run
var _path := PackedVector2Array()
var _pi := 0

func _ready() -> void:
	SaveData.save_path = "user://bot_save.json"
	SaveData.reset_all()
	await get_tree().process_frame
	var seeds := [101]
	for a in OS.get_cmdline_user_args():
		seeds.append(int(a))
	for house in Game.house_ids:
		for cr in Defs.ORDINARY_CREATURES:
			for sd in seeds:
				await _play(house, cr, sd)
	var wins := results.filter(func(r): return r["won"])
	print("\n=== BOT PLAYTEST: %d runs, %d won ===" % [results.size(), wins.size()])
	for cr in Defs.ORDINARY_CREATURES:
		var rs := results.filter(func(r): return r["creature"] == cr)
		var w := rs.filter(func(r): return r["won"])
		var avg := 0.0
		for r in w:
			avg += r["time"]
		avg = avg / maxf(1.0, w.size())
		var wounds := 0
		for r in rs:
			wounds += r["wounds"]
		print("%-13s won %d/%d  avg %s  wounds %d" % [cr, w.size(), rs.size(), Journal.format_time(avg), wounds])
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _alive() -> bool:
	return is_instance_valid(run) and run.state == "playing" and run.elapsed < MAX_TIME

## Walk to a point at walking speed, fleeing if a hunt starts. Returns false if the run ended.
func _walk_to(target: Vector2, tolerance: float = 20.0) -> bool:
	_path = run.map.path(run.player.global_position, target)
	_pi = 0
	while _alive():
		if run.creature.is_hunting():
			await _flee()
			_path = run.map.path(run.player.global_position, target)
			_pi = 0
			continue
		if run.player.global_position.distance_to(target) <= tolerance or _pi >= _path.size():
			return true
		_step_along(Player.WALK_SPEED)
		await get_tree().process_frame
	return false

func _step_along(speed: float) -> void:
	var p := run.player
	var d := speed / 60.0
	while _pi < _path.size() and d > 0.0:
		var to := _path[_pi] - p.global_position
		if to.length() > 90.0:
			p.global_position = _path[_pi]   # take the staircase
			_pi += 1
			continue
		if to.length() <= d:
			p.global_position = _path[_pi]
			d -= to.length()
			_pi += 1
		else:
			p.global_position += to.normalized() * d
			p.aim_angle = to.angle()
			d = 0.0

func _flee() -> void:
	# Run to the reachable room centre farthest from the creature, sprinting while stamina lasts.
	var best := run.player.global_position
	var bd := -1.0
	for r in run.map.indoor_rooms() + run.map.rooms.filter(func(x): return x["outdoor"]):
		var cells := run.map.free_cells(r["id"])
		if cells.is_empty():
			continue
		var c := HouseMap.cell_center(cells[cells.size() / 2])
		var d := c.distance_to(run.creature.position) - c.distance_to(run.player.global_position) * 0.3
		if d > bd:
			bd = d
			best = c
	_path = run.map.path(run.player.global_position, best)
	_pi = 0
	var stamina := 3.6
	while _alive() and run.creature.is_hunting():
		var spd := Player.SPRINT_SPEED if stamina > 0.0 else Player.WALK_SPEED
		stamina -= 1.0 / 60.0
		if _pi >= _path.size():
			_path = run.map.path(run.player.global_position, HouseMap.cell_center(run.map.random_free_cell(run.map.indoor_rooms()[randi() % run.map.indoor_rooms().size()]["id"], run.rng)))
			_pi = 0
		_step_along(spd)
		await get_tree().process_frame

func _equip(id: String) -> void:
	run.player.equipment.select(run.player.equipment.slots.find(id))

func _use() -> void:
	run.player.equipment._cooldown = 0.0
	run.player.equipment.use_current()

func _wait(seconds: float) -> bool:
	var t := 0.0
	while _alive() and t < seconds:
		if run.creature.is_hunting():
			await _flee()
		await get_tree().process_frame
		t += 1.0 / 60.0
	return _alive()

func _collect(res: String) -> bool:
	while _alive():
		var items := run.pickups.filter(func(p): return p.get("res", "") == res)
		if items.is_empty():
			return true
		var it: Dictionary = items[0]
		if not await _walk_to(it["pos"], 12.0):
			return false
		run.do_interact(run.player, it)
	return false

func _lair_point() -> Vector2:
	var cells := run.map.free_cells(run.creature.lair_room)
	return HouseMap.cell_center(cells[cells.size() / 2])

func _approach_and_strike(item: String) -> bool:
	_equip(item)
	while _alive():
		var c := run.creature
		var to := c.position - run.player.global_position
		if to.length() < 50.0:
			run.player.aim_angle = to.angle()
			if item == "iron_nails" and c.exposed_t <= 0.0:
				_equip("hand_mirror")
				run.player.equipment._mirror_check()
				_equip(item)
			run.player.equipment._cooldown = 0.0
			run.strike(run.player, item)
			await _frames(30)
			continue
		if c.is_hunting():
			# Hold position facing it; strike when it arrives (garlic / reach).
			run.player.aim_angle = to.angle()
			await get_tree().process_frame
			continue
		_path = run.map.path(run.player.global_position, c.position)
		_pi = 1 if _path.size() > 1 else 0   # (re-planned every frame: don't snap back to this cell's centre)
		_step_along(Player.WALK_SPEED)
		await get_tree().process_frame
	return false

func _play(house: String, cr: String, sd: int) -> void:
	run = Game.start_run(house, sd, cr)
	await get_tree().process_frame
	run.player.input_enabled = false
	run.player.set_physics_process(false)
	match cr:
		"shade":
			if await _walk_to(_lair_point()):
				_equip("thermometer")
				await _wait(2.0)
				_equip("orb_camera")
				for i in 8:
					run.player.aim_angle = (run.map.room_center(run.creature.lair_room) - run.player.global_position).angle() + i * 0.8
					await _wait(0.5)
				_equip("emf")
				var t := 0.0
				while _alive() and not run.player.journal.has("emf5") and t < 45.0:
					var hs: Array = run.phenomena.hotspots.filter(func(h): return h["level"] == 5)
					if not hs.is_empty():
						await _walk_to(hs[0]["pos"], 10.0)
					await _wait(0.5)
					t += 0.5
				await _walk_to(_lair_point())
				_equip("salt")
				_use()
				run.player.suspect = "shade"
				await _wait(1.5)
				run.perform_rite(run.player)
		"poltergeist":
			if await _walk_to(_lair_point()):
				_equip("ghost_book")
				_use()
				_equip("spirit_box")
				var t := 0.0
				while _alive() and not run.player.journal.has("spirit_box") and t < 30.0:
					_use()
					await _wait(2.2)
					t += 2.2
				_equip("uv")
				while _alive() and not run.player.journal.has("writing") and t < 60.0:
					if not run.phenomena.uv_prints.is_empty() and not run.player.journal.has("uv"):
						var u: Dictionary = run.phenomena.uv_prints[0]
						await _walk_to(u["pos"] + Vector2(40, 0), 8.0)
						run.player.aim_angle = (u["pos"] - run.player.global_position).angle()
					await _wait(0.5)
					t += 0.5
				var book: Node2D = (run.placed_books()[0] if not run.placed_books().is_empty() else null)
				if book:
					# Stand beside the book, on its side of any wall.
					var spot: Vector2 = book.position
					for off: Vector2 in [Vector2(30, 0), Vector2(-30, 0), Vector2(0, 30), Vector2(0, -30)]:
						if run.map.room_at(book.position + off) == run.map.room_at(book.position) and run.map.walkable(HouseMap.to_cell(book.position + off)):
							spot = book.position + off
							break
					await _walk_to(spot, 8.0)
				run.player.suspect = "poltergeist"
				await _wait(1.5)
				run.perform_rite(run.player)
		"blightness", "crawler", "lost_one":
			# Read the room, lay what its rite needs, name it, perform the rite.
			if await _walk_to(_lair_point()):
				_equip("emf")
				await _wait(3.0)
				_equip("thermometer")
				await _wait(2.0)
				for need in Defs.CREATURES[cr]["rite_needs"]:
					if need != "holy_water":
						_equip(need)
						_use()
						await _wait(0.6)
				run.player.suspect = cr
				await _wait(1.5)
				run.perform_rite(run.player)
		"vampire":
			if await _collect("garlic") and await _collect("wooden_stake"):
				await _approach_and_strike("wooden_stake")
		"werewolf":
			if await _collect("silverware"):
				var st: Dictionary = run.map.furniture_with("melt")[0]
				await _walk_to(HouseMap.cell_center(run.map.nearest_walkable(HouseMap.to_cell((st["rect"] as Rect2).get_center() + Vector2(0, 40)))), 6.0)
				var it := run.find_interactable(run.player, run.player.global_position)
				if it.get("kind", "") == "melt":
					await _wait(2.0)
					run.do_interact(run.player, it)
				await _approach_and_strike("silver_stake")
		"shapeshifter":
			if await _collect("hand_mirror") and await _collect("iron_nails"):
				await _approach_and_strike("iron_nails")
	await _frames(5)
	var won := run._outcome == "vanquished" or (is_instance_valid(run) and run.state == "ending" and not run.player.dead)
	var r := {"house": house, "creature": cr, "seed": sd, "won": won, "time": run.elapsed, "wounds": run.player.wounds,
		"evidence": run.player.journal.active_entries().size(), "hunts": run.hunts_total}
	results.append(r)
	print("%-14s %-13s %s %s wounds=%d ev=%d hunts=%d" % [house, cr, "WON " if won else "LOST", Journal.format_time(run.elapsed), r["wounds"], r["evidence"], r["hunts"]])
	run.queue_free()
	await _frames(3)
