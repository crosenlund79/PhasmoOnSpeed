extends Node
## Screen flow and shared session data (selected house, last result).

const HOUSE_DIR := "res://data/houses/"

var house_ids: Array = []
var _houses := {}
var last_result := {}
var _current: Node = null
const MENU_SCALE_MIN := 0.8
const MENU_SCALE_MAX := 1.25
const GAME_SCALE_MIN := 0.7
const GAME_SCALE_MAX := 1.3

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Controls.register()
	var f := FileAccess.open(HOUSE_DIR + "index.json", FileAccess.READ)
	if f:
		house_ids = JSON.parse_string(f.get_as_text())
	_apply_display_settings()

func house(id: String) -> Dictionary:
	if not _houses.has(id):
		var f := FileAccess.open(HOUSE_DIR + id + ".json", FileAccess.READ)
		_houses[id] = JSON.parse_string(f.get_as_text()) if f else {}
	return _houses[id]

func _apply_display_settings() -> void:
	var s: Dictionary = SaveData.settings()
	_apply_ui_scale()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if s.get("fullscreen", false) else DisplayServer.WINDOW_MODE_WINDOWED)

func _apply_ui_scale() -> void:
	var s: Dictionary = SaveData.settings()
	# Menu UI scale applies to menu screens only; in a run the world and HUD stay at
	# 1.0 and the HUD uses its own Gameplay UI scale (hud_scale).
	var in_game := _current is Run or _current is ClientRun
	get_tree().root.content_scale_factor = 1.0 if in_game else clampf(float(s.get("ui_scale", 1.0)), MENU_SCALE_MIN, MENU_SCALE_MAX)

func apply_settings() -> void:
	_apply_display_settings()
	Sfx.apply_volumes(SaveData.settings()["master"], SaveData.settings()["music"])

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		SaveData.set_setting("fullscreen", not SaveData.settings().get("fullscreen", false))
		_apply_display_settings()

func _switch(node: Node) -> void:
	get_tree().paused = false
	if _current and is_instance_valid(_current):
		_current.queue_free()
	_current = node
	_apply_ui_scale()
	get_tree().root.add_child(node)
	get_tree().current_scene = node

func goto_menu() -> void:
	_switch(preload("res://scripts/ui/main_menu.gd").new())

func goto_house_select() -> void:
	_switch(preload("res://scripts/ui/house_select.gd").new())

func goto_stats() -> void:
	_switch(preload("res://scripts/ui/stats_screen.gd").new())

func goto_rankings() -> void:
	_switch(preload("res://scripts/ui/rankings_screen.gd").new())

func goto_encyclopedia() -> void:
	_switch(preload("res://scripts/ui/encyclopedia.gd").new())

func goto_lobby(message: String = "") -> void:
	var l = preload("res://scripts/ui/lobby.gd").new()
	l.message = message
	_switch(l)

## Host: build the authoritative run for a competitive match.
func start_match_host(house_id: String, run_seed: int, creature_override: String, roster: Array, difficulty: String = "normal", blood_moon: bool = false, setup: Dictionary = {}) -> Node:
	var run = preload("res://scripts/game/run.gd").new()
	run.setup(house_id, run_seed, creature_override, roster, difficulty, blood_moon, setup)
	_switch(run)
	return run

## Client: build the mirrored view of the host's match.
func start_match_client(house_id: String, run_seed: int, roster: Array, my_peer: int, difficulty: String = "normal", blood_moon: bool = false, setup: Dictionary = {}) -> Node:
	var cr = preload("res://scripts/game/client_run.gd").new()
	cr.setup(house_id, run_seed, roster, my_peer, difficulty, blood_moon, setup)
	_switch(cr)
	return cr

## Host: the match ended. Send everyone the results and the replay.
func finish_match(results: Dictionary, replay: Dictionary) -> void:
	Net.host_send_results(results, replay)
	show_match_results(results, replay)

func show_match_results(results: Dictionary, replay: Dictionary) -> void:
	var me := ""
	for r in results.get("rows", []):
		if int(r["peer_id"]) == Net.my_peer_id():
			me = r["actor"]
	var records := SaveData.record_match(results, me)
	last_result = {"match": results, "replay": replay, "records": records, "me": me}
	var res = preload("res://scripts/ui/match_results.gd").new()
	res.setup(last_result)
	_switch(res)

# --- Match setup ------------------------------------------------------------------
## A setup is what the player (or lobby host) chose:
##   {mode: "normal"|"custom", house: id|"random", entity: id|"random",
##    difficulty: id|"random", blood_moon: "on"|"off"|"random"}
## A Normal Game always rolls house, entity and Blood Moon; only the difficulty is chosen.
const DEFAULT_SETUP := {"mode": "normal", "house": "random", "entity": "random", "difficulty": "normal", "blood_moon": "random"}

## Resolves every "random" once. The entity stays "" when random: the run itself
## rolls it from its seed (so nobody — not even a multiplayer client — learns it early).
func resolve_setup(setup: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var s := DEFAULT_SETUP.duplicate()
	s.merge(setup, true)
	if s["mode"] != "custom":
		s["house"] = "random"
		s["entity"] = "random"
		s["blood_moon"] = "random"
	var out := {"mode": s["mode"], "rolled": {}}
	out["rolled"]["house"] = s["house"] == "random" or not house_ids.has(s["house"])
	out["house"] = house_ids[rng.randi_range(0, house_ids.size() - 1)] if out["rolled"]["house"] else s["house"]
	out["rolled"]["entity"] = s["entity"] == "random" or not Defs.ORDINARY_CREATURES.has(s["entity"])
	out["entity"] = "" if out["rolled"]["entity"] else s["entity"]
	out["rolled"]["difficulty"] = s["difficulty"] == "random" or not Defs.DIFFICULTIES.has(s["difficulty"])
	out["difficulty"] = Defs.RANDOM_DIFFICULTIES[rng.randi_range(0, Defs.RANDOM_DIFFICULTIES.size() - 1)] if out["rolled"]["difficulty"] else s["difficulty"]
	out["rolled"]["blood_moon"] = s["blood_moon"] == "random"
	out["blood_moon"] = (rng.randf() < Defs.BLOOD_MOON_CHANCE) if out["rolled"]["blood_moon"] else s["blood_moon"] == "on"
	return out

## Solo: resolve the chosen setup and start the run.
func start_setup(setup: Dictionary) -> Node:
	SaveData.set_setting("setup", setup)
	var r := resolve_setup(setup)
	return start_run(r["house"], -1, r["entity"], r["difficulty"], r["blood_moon"], r)

## Starts a run. creature_override picks the entity (Custom Game / tests); "" rolls it.
## Difficulty defaults to the one last chosen in the setup screen.
func start_run(house_id: String, run_seed: int = -1, creature_override: String = "", difficulty: String = "", blood_moon: bool = false, setup: Dictionary = {}) -> Node:
	if difficulty == "":
		difficulty = str(SaveData.settings().get("difficulty", "normal"))
	var run = preload("res://scripts/game/run.gd").new()
	run.setup(house_id, run_seed, creature_override, [], difficulty, blood_moon, setup)
	SaveData.note_run_started()
	_switch(run)
	return run

## Called once by a run when it ends. Persists stats exactly once, then shows results.
func finish_run(summary: Dictionary, replay: Dictionary) -> void:
	var records := SaveData.record_run(summary)
	SaveData.save_replay(replay)
	# The global leaderboard ranks Normal runs only; Nightmare records stay local and separate.
	if summary.get("difficulty", "normal") == "normal":
		Online.submit(summary, SaveData.settings().get("player_name", "Investigator"))
	last_result = {"summary": summary, "replay": replay, "records": records}
	var res = preload("res://scripts/ui/results.gd").new()
	res.setup(last_result)
	_switch(res)
