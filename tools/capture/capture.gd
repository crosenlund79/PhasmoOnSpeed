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
