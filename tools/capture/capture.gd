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
		run.journal.record("emf5", 43.0, "living", "Living Room")
		run.journal.record("freezing", 81.0, "kitchen", "Kitchen")
		run.journal.record("footprints", 128.0, "hallway", "Hallway")
		run.elapsed = 151.3
		await _wait(90)
		await _save(s.replace(":", "_"))
	elif s.begins_with("overview_"):
		var run: Run = Game.start_run(s.substr(9), 5, "shade")
		await _wait(10)
		run.hud.visible = false
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
		c.begin_hunt(c.position, false)
		await _wait(200)
		await _save(s.replace(":", "_"))
	elif s == "harbinger":
		var run: Run = Game.start_run("blackwood", 9, "vampire")
		await _wait(20)
		run.attempt_vanquish("shade", "rite")
		run.attempt_vanquish("werewolf", "silver_stake")
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
	elif s == "results":
		var run: Run = Game.start_run("ashgrove", 5, "poltergeist")
		await _wait(200)
		run.journal.record("uv", 20.0, "kitchen", "Kitchen")
		run.player.global_position = run.creature.position + Vector2(20, 0)
		run.player.room_id = run.creature.lair_room
		run.attempt_vanquish("poltergeist", "rite")
		await _wait(60)
		await _save("victory_moment")
		await _wait(200)
		await _save("results")
