extends Node
## Screen flow and shared session data (selected house, last result).

const HOUSE_DIR := "res://data/houses/"

var house_ids: Array = []
var _houses := {}
var last_result := {}
var _current: Node = null

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
	get_tree().root.content_scale_factor = clampf(float(s.get("ui_scale", 1.0)), 0.75, 1.5)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if s.get("fullscreen", false) else DisplayServer.WINDOW_MODE_WINDOWED)

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

## Starts a run. creature_override is only for tests/dev; normal play is random.
func start_run(house_id: String, run_seed: int = -1, creature_override: String = "") -> Node:
	var run = preload("res://scripts/game/run.gd").new()
	run.setup(house_id, run_seed, creature_override)
	SaveData.note_run_started()
	_switch(run)
	return run

## Called once by a run when it ends. Persists stats exactly once, then shows results.
func finish_run(summary: Dictionary, replay: Dictionary) -> void:
	var records := SaveData.record_run(summary)
	SaveData.save_replay(replay)
	Online.submit(summary, SaveData.settings().get("player_name", "Investigator"))
	last_result = {"summary": summary, "replay": replay, "records": records}
	var res = preload("res://scripts/ui/results.gd").new()
	res.setup(last_result)
	_switch(res)
