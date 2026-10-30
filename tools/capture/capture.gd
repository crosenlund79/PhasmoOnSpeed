extends Node
## Renders screenshots of game screens for visual review.
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tools/capture/capture.tscn -- OUT_DIR [shots...]
## Shots: menu, houses, run_<house>, results

var out_dir := "user://captures"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var shots: Array = args.slice(1) if args.size() > 1 else ["menu", "houses", "run_ashgrove", "results"]
	SaveData.save_path = "user://capture_save.json"
	await get_tree().process_frame
	for s in shots:
		await _shot(s)
	get_tree().quit()

func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)

func _shot(s: String) -> void:
	if s == "menu":
		Game.goto_menu()
		await _wait(20)
		await _save("menu")
	elif s == "settings":
		Game.goto_menu()
		await _wait(10)
		get_tree().current_scene.settings_panel.visible = true
		await _wait(10)
		await _save("settings")
	elif s == "houses":
		Game.goto_house_select()
		await _wait(20)
		await _save("houses")
	elif s.begins_with("run_"):
		var parts := s.split(":")
		var house := parts[0].substr(4)
		var creature := parts[1] if parts.size() > 1 else "shade"
		var run: Run = Game.start_run(house, 5, creature)
		await _wait(30)
		run.player.journal.record("emf5", 43.0, "living", "Living Room")
		run.player.journal.record("freezing", 81.0, "kitchen", "Kitchen")
		run.player.equipment.select(1)
		run.elapsed = 151.3
		await _wait(50)
		run.player.journal.record("footprints", 128.0, "hallway", "Hallway")
		await _wait(25)
		await _save(s.replace(":", "_"))
	elif s.begins_with("suspect_"):
		# SUSPECTED panel with a chosen entity, some evidence and one requirement held.
		var parts := s.substr(8).split(":")
		var run: Run = Game.start_run(parts[0], 5, "shade", parts[2] if parts.size() > 2 else "normal")
		await _wait(20)
		run.creature.set_process(false)
		run.player.suspect = parts[1] if parts.size() > 1 else "vampire"
		run.player.journal.record("bite_marks", 64.0, "kitchen", "Kitchen")
		run.player.journal.record("emf5", 90.0, "living", "Living Room")
		run.player.add_resource("garlic")
		run.player.equipment.rebuild_slots()
		run.elapsed = 97.6
		run.hud.refresh()
		run.hud.show_suspect_picker()
		await _wait(30)
		await _save(s.replace(":", "_"))
	elif s.begins_with("nightmare_"):
		# Nightmare atmosphere: blood, vermin (one freshly squashed), a frightened occupant.
		var run: Run = Game.start_run(s.substr(10), 5, "werewolf", "nightmare")
		await _wait(5)
		run.creature.set_process(false)
		var grim: Array = run.map.rooms.filter(func(r): return not r["outdoor"] and int(r.get("level", 0)) == 0 and r.get("condition", "") in ["neglected", "abandoned"])
		var room: Dictionary = grim[0] if not grim.is_empty() else run.map.indoor_rooms()[0]
		run.player.global_position = run.map.room_center(room["id"])
		run._apply_camera_limits(run.player.global_position)
		run.camera.reset_smoothing()
		run.player.flashlight_on = true
		run.player.aim_override = 0.3
		run.player.input_enabled = false
		run.player.suspect = "werewolf"
		run.hud.refresh()
		var live: Array = run.critters.list
		for i in mini(5, live.size()):
			live[i]["node"].position = run.player.global_position + Vector2(60 + i * 26, -40 + (i % 2) * 70)
			live[i]["room"] = run.map.room_at(live[i]["node"].position)
		if run.occupants.size() > 0:
			var o: Occupant = run.occupants[0]
			o.position = run.player.global_position + Vector2(-90, -30)
			o.say("Something's crawling on me — get it off!")
		await _wait(20)
		if live.size() > 0:
			run.critters._squash(live[0])
		run.elapsed = 212.4
		await _wait(40)
		await _save(s)
	elif s.begins_with("env_"):
		# Doors, wide stairs, living flames and the interact highlight, brightly lit for review.
		var run: Run = Game.start_run(s.substr(4), 5, "shade")
		await _wait(5)
		run.creature.set_process(false)
		var st: Dictionary = run.map.stairs[0]
		print("wide stairs: ", run.map.stairs.map(func(e): return [e.has("a_wide"), e.has("b_wide")]))
		run.player.global_position = HouseMap.cell_center(st["a_land"]) + Vector2(0, 0)
		run._apply_camera_limits(run.player.global_position)
		run.camera.reset_smoothing()
		run.player.flashlight_on = true
		run.player.input_enabled = false
		run.view.set_darkness(Color(0.55, 0.55, 0.6), 0.01)
		await _wait(40)
		print("near: ", run.player.equipment.near_items, " target ", run.player.equipment.interact_pos, " hl ", run.hud.highlighter.near)
		await _save(s)
	elif s == "needle":
		# Witch's Needle near a strong presence, beside a pickup (highlight) and a closed door.
		var run: Run = Game.start_run("ashgrove", 5, "shade")
		await _wait(5)
		run.creature.set_process(false)
		var pk: Dictionary = run.pickups[0]
		run.player.global_position = pk["pos"] + Vector2(22, 0)
		run._apply_camera_limits(run.player.global_position)
		run.camera.reset_smoothing()
		run.player.input_enabled = false
		run.player.flashlight_on = true
		run.player.equipment.select(Defs.BASE_LOADOUT.find("emf"))
		run.phenomena.hotspots.append({"pos": run.player.global_position + Vector2(40, 0), "level": 4, "ttl": 99.0, "room": run.player.room_id})
		await _wait(45)
		await _save("needle")
	elif s == "voodoo":
		var run: Run = Game.start_run("blackwood", 8, "poltergeist")
		await _wait(5)
		run.creature.set_process(false)
		var o: Occupant = run.occupants[0]
		o.set_process(false)
		run.player.global_position = o.position + Vector2(-70, 10)
		run._apply_camera_limits(run.player.global_position)
		run.camera.reset_smoothing()
		run.player.input_enabled = false
		run.player.aim_override = 0.0
		run.player.add_resource("voodoo_doll")
		run.player.equipment.rebuild_slots()
		run.player.equipment.select(run.player.equipment.slots.find("voodoo_doll"))
		run.occupants = [o]
		run.use_voodoo(run.player)
		await _wait(22)
		await _save("voodoo_burning")
		await _wait(110)
		await _save("voodoo_embers")
	elif s == "furnace":
		var run: Run = Game.start_run("blackwood", 9, "lost_one")
		await _wait(5)
		var k: Dictionary = run.keepsakes.filter(func(x): return x["forbidden"])[0]
		run.player.global_position = k["pos"] + Vector2(24, 0)
		run._apply_camera_limits(run.player.global_position)
		run.camera.reset_smoothing()
		await _wait(10)
		await _save("lost_one_keepsake")
		run._examine_keepsake(run.player, k)
		await _wait(50)
		await _save("lost_one_wrath")
		run.on_creature_contact(run.creature, run.player)
		await _wait(150)
		await _save("furnace")
	elif s.begins_with("ency:"):
		Game.goto_encyclopedia()
		await _wait(10)
		get_tree().current_scene.show_entry(s.substr(5))
		await _wait(10)
		await _save("encyclopedia_" + s.substr(5))
	elif s == "prompt":
		# Standing at a closed door: highlight ring and the E / SPACE prompt chip.
		var run: Run = Game.start_run("ashgrove", 5, "shade")
		await _wait(5)
		run.creature.set_process(false)
		var dc: Vector2i = run.view.doors[1]["cell"]
		run.set_door(1, false)
		var side := Vector2(0, 38) if run.map.is_wall(dc + Vector2i(1, 0)) else Vector2(38, 0)
		if not run.map.walkable(HouseMap.to_cell(HouseMap.cell_center(dc) + side)):
			side = -side
		run.player.global_position = HouseMap.cell_center(dc) + side
		run.player.aim_override = (-side).angle()
		run._apply_camera_limits(run.player.global_position)
		run.camera.reset_smoothing()
		run.player.equipment.select(Defs.BASE_LOADOUT.find("emf"))
		run.phenomena.hotspots.append({"pos": run.player.global_position + Vector2(30, 0), "level": 4, "ttl": 99.0, "room": run.player.room_id})
		await _wait(40)
		await _save("prompt_door")
	elif s.begins_with("escalate_"):
		var cr := s.substr(9)
		var run: Run = Game.start_run("blackwood", 24, cr)
		await _wait(5)
		run.creature.set_process(false)
		run.creature.position = run.player.global_position + Vector2(110, -10)
		run.threat = 80.0
		run.creature.set_process(true)
		run.creature.state = "stunned"
		run.creature.stunned_t = 99.0
		await _wait(22 if cr == "werewolf" else 120)
		await _save("escalate_%s" % cr)
		if cr == "werewolf":
			await _wait(80)
			await _save("escalate_werewolf_done")
	elif s.begins_with("defeat_"):
		var cr := s.substr(7)
		var run: Run = Game.start_run("ashgrove", 21, cr)
		await _wait(5)
		run.creature.set_process(false)
		run.creature.position = run.player.global_position + Vector2(60, 0)
		run.creature.alpha = 1.0
		run.creature.modulate.a = 1.0
		var item: String = {"vampire": "wooden_stake", "werewolf": "silver_stake", "shapeshifter": "iron_nails"}[cr]
		run.player.add_resource(item)
		run.player.equipment.rebuild_slots()
		run.player.equipment.select(run.player.equipment.slots.find(item))
		if cr == "shapeshifter":
			run.creature.expose(10.0)
			run.attempt_vanquish(run.player, cr, item)
		else:
			run.creature.begin_hunt(run.creature.position, false)
			run.on_creature_contact(run.creature, run.player)
		await _wait(28)
		await _save("defeat_%s" % cr)
	elif s == "custom_setup":
		SaveData.set_setting("setup", {"mode": "custom", "house": "blackwood", "entity": "random", "difficulty": "nightmare", "blood_moon": "on"})
		Game.goto_house_select()
		await _wait(20)
		await _save("custom_setup")
		SaveData.set_setting("setup", {})
	elif s.begins_with("bloodmoon_"):
		var run: Run = Game.start_run(s.substr(10), 5, "shade", "normal", true)
		await _wait(5)
		run.creature.set_process(false)
		await _wait(60)
		await _save(s)
	elif s == "deduction":
		# Ruled-out evidence, a found one, the crossed-out suspects and the ghost marker.
		var run: Run = Game.start_run("ashgrove", 5, "blightness", "normal", false, {"ghost_marker": true})
		await _wait(5)
		run.creature.position = run.player.global_position + Vector2(130, -30)
		run.discover(run.player, "writing", run.player.room_id)
		for ev in ["freezing", "orbs", "bite_marks"]:
			run.hud.toggle_ruled_out(ev)
		run.player.suspect = "blightness"
		run.hud.refresh()
		await _wait(60)
		await _save("deduction")
	elif s == "hellfire":
		var run: Run = Game.start_run("ashgrove", 41, "shade", "hellbound")
		await _wait(5)
		run.creature.set_process(false)
		run.player.input_enabled = false
		run.spawn_hellfire(run.player.global_position + Vector2(70, -10))
		run.spawn_hellfire(run.player.global_position + Vector2(-80, 20))
		await get_tree().create_timer(0.9).timeout
		await _save("hellfire_warning")
		await get_tree().create_timer(1.3).timeout
		await _save("hellfire_erupting")
	elif s == "abyss":
		var run: Run = Game.start_run("blackwood", 42, "shade", "abyssal")
		await _wait(5)
		run.creature.set_process(false)
		run._portal_t = 9999.0
		var indoor: Dictionary = run.map.indoor_rooms()[0]
		run.player.global_position = HouseMap.cell_center(run.map.random_free_cell(indoor["id"], run.rng))
		run.player.room_id = indoor["id"]
		run._apply_camera_limits(run.player.global_position)
		run.camera.reset_smoothing()
		run.view.portal_warning(run.player.room_id, 2.5)
		await get_tree().create_timer(1.8).timeout
		await _save("portal_warning")
		run.open_abyss(run.player.room_id)
		run.player.invuln = 999.0
		await _wait(220)
		await _save("abyssal_hell")
	elif s.begins_with("overview_"):
		var run: Run = Game.start_run(s.substr(9), 5, "shade")
		await _wait(10)
		run.hud.visible = false
		run.world_text.visible = false
		for c in run.hud.get_children():
			c.visible = false
		run.camera.zoom = Vector2(0.62, 0.62)
		run.camera.offset = Vector2.ZERO
		run.camera.limit_right = 100000
		run.camera.limit_bottom = 100000
		run.player.global_position = run.map.world_size() * 0.5
		run.hud.set_process(false)
		await _wait(60)
		await _save(s)
	elif s.begins_with("hunt_"):
		var run: Run = Game.start_run(s.substr(5).split(":")[0], 9, s.split(":")[1] if ":" in s else "werewolf")
		await _wait(20)
		var c := run.creature
		c.position = run.player.global_position + Vector2(140, -20)
		run.player.invuln = 999.0   # keep the hunt going for the photograph
		c.begin_hunt(c.position, false)
		for i in 400:
			if c.is_hunting() and run.hud._hunting:
				break
			await get_tree().process_frame
		print("hunting: ", c.is_hunting(), " state ", c.state)
		await _wait(40)
		await _save(s.replace(":", "_"))
	elif s == "harbinger":
		var run: Run = Game.start_run("blackwood", 9, "vampire")
		await _wait(20)
		run.attempt_vanquish(run.player, "shade", "rite")
		run.attempt_vanquish(run.player, "werewolf", "silver_stake")
		await _wait(100)
		await _save("harbinger")
	elif s == "gallery":
		var run: Run = Game.start_run("blackwood", 3, "shade")
		await _wait(5)
		run.creature.set_process(false)
		var base := run.map.room_center("foyer") + Vector2(-170, -40)
		run.player.global_position = base + Vector2(0, 90)
		var tokens := ["tokens/shade.png", "tokens/poltergeist.png", "tokens/vampire.png", "tokens/werewolf.png", "tokens/shapeshifter.png", "tokens/cat.png", "tokens/harbinger.png", "tokens/occupant_bitten.png"]
		for i in tokens.size():
			var t := TokenSprite.new(tokens[i], 36.0 if i != 6 else 46.0)
			t.position = base + Vector2(i * 48, 0)
			run.view.actor_layer.add_child(t)
		var items := ["items/garlic.png", "items/wooden_stake.png", "items/silverware.png", "items/hand_mirror.png", "items/iron_nails.png", "items/blood_drops.png", "items/claw_marks.png", "items/paw_print.png", "items/fur_tuft.png", "items/shed_skin.png", "items/ghost_book_written.png", "items/sigil_candle_lit.png"]
		for i in items.size():
			run._item_sprite(items[i], base + Vector2(i * 30 - 10, 45), 26.0)
		await _wait(40)
		await _save("gallery")
	elif s.begins_with("flash_"):
		# Flashlight integrity: stand near walls/doorways and aim along them.
		var run: Run = Game.start_run("ashgrove", 5, "shade")
		await _wait(5)
		run.creature.set_process(false)
		var spots := {"flash_wall": [Vector2(10, 15), 0.15], "flash_door": [Vector2(9, 15), -1.45], "flash_corner": [Vector2(6, 11), -0.6]}
		var spot: Array = spots.get(s, spots["flash_wall"])
		run.player.global_position = HouseMap.cell_center(spot[0])
		run.player.input_enabled = false
		run.player.aim_angle = spot[1]
		await _wait(60)
		await _save(s)
	elif s.begins_with("basement_"):
		var run: Run = Game.start_run(s.substr(9), 5, "werewolf")
		await _wait(5)
		run.creature.set_process(false)
		var st: Dictionary = run.map.stairs[0]
		run.player.global_position = HouseMap.cell_center(st["b_land"]) + Vector2(40, 30)
		run._apply_camera_limits(run.player.global_position)
		run._on_local_floor(-1)
		run.camera.reset_smoothing()
		run.player.aim_override = 0.3
		await _wait(60)
		await _save(s)
	elif s.begins_with("room_"):
		# room_<house>:<room id> — stand in the middle of a room at game zoom.
		var parts := s.substr(5).split(":")
		var run: Run = Game.start_run(parts[0], 5, "werewolf")
		await _wait(5)
		run.creature.set_process(false)
		for o in run.occupants:
			o.set_process(false)
		var cells := run.map.free_cells(parts[1], false)
		run.player.global_position = HouseMap.cell_center(cells[cells.size() / 2])
		run._apply_camera_limits(run.player.global_position)
		run._on_local_floor(run.map.floor_at(run.player.global_position))
		run.camera.reset_smoothing()
		run.player.aim_override = 1.2
		await _wait(60)
		await _save(s.replace(":", "_"))
	elif s.begins_with("mp:"):
		# mp:<port> — join a running host (tests/net_test.gd "shot" scenario) and photograph the client view.
		var port := int(s.split(":")[1])
		Net.join("127.0.0.1", port, "Mina")
		var t := 0.0
		while not Net.lobby.has(Net.my_peer_id()) and t < 10.0:
			await get_tree().process_frame
			t += get_process_delta_time()
		Net.set_ready(true)
		t = 0.0
		while Net.client_run == null and t < 20.0:
			await get_tree().process_frame
			t += get_process_delta_time()
		var cr: ClientRun = Net.client_run
		await _wait(10)
		await get_tree().process_frame
		Input.action_press("move_right")
		await _wait(25)
		Input.action_release("move_right")
		cr.player.aim_override = -0.4
		await _wait(60)
		cr.player.journal.record("claw_marks", 41.0, cr.player.room_id, cr.map.room_name(cr.player.room_id))
		await _wait(20)
		await _save("multiplayer_client")
		if s.ends_with(":pause"):
			cr.hud.toggle_pause()   # as Esc: the host pauses everyone
			await _wait(45)
			await _save("multiplayer_pause")
		Net.leave()
	elif s == "lobby":
		Net.host(24799, "Host")
		Game.goto_lobby()
		await _wait(20)
		await _save("lobby")
		Net.leave()
	elif s == "encyclopedia":
		Game.goto_encyclopedia()
		await _wait(10)
		var enc = get_tree().current_scene
		enc.show_entry("werewolf")
		await _wait(10)
		await _save("encyclopedia")
	elif s.begins_with("beginner_"):
		# Beginner Mode: the guide note after the first evidence, with the full suspect row.
		var run: Run = Game.start_run(s.substr(9), 5, "vampire", "beginner")
		await _wait(20)
		run.creature.set_process(false)
		run.discover(run.player, "bite_marks", run.player.room_id)
		run.elapsed = 84.2
		await _wait(400)
		run.player.suspect = "vampire"
		run.hud.refresh()
		await _wait(20)
		await _save(s)
	elif s == "replay_moment":
		# Results replay with a moment popup taken from the recorded events.
		var run: Run = Game.start_run("ashgrove", 5, "poltergeist")
		await _wait(30)
		run.discover(run.player, "uv", run.player.room_id)
		await _wait(60)
		run.attempt_vanquish(run.player, "shade", "rite")
		await _wait(60)
		run.player.global_position = run.creature.position + Vector2(20, 0)
		run.player.room_id = run.creature.lair_room
		run.attempt_vanquish(run.player, "poltergeist", "rite")
		await _wait(260)
		var res = get_tree().current_scene
		for i in 600:
			if res.replay_player and not res.replay_player._moments.is_empty() and res.replay_player._moments[-1]["t"] > 0.3 and res.replay_player._moments[-1]["t"] < 1.2:
				break
			await get_tree().process_frame
		await _save("replay_moment")
	elif s == "results":
		var run: Run = Game.start_run("ashgrove", 5, "poltergeist")
		await _wait(200)
		run.player.journal.record("uv", 20.0, "kitchen", "Kitchen")
		run.player.global_position = run.creature.position + Vector2(20, 0)
		run.player.room_id = run.creature.lair_room
		run.attempt_vanquish(run.player, "poltergeist", "rite")
		await _wait(60)
		await _save("victory_moment")
		await _wait(200)
		await _save("results")
