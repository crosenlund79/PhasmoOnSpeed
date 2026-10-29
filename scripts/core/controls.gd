class_name Controls
extends RefCounted
## Input map, registered at startup so the project file stays minimal.

const HELP := [
	["WASD / Arrows", "Move"], ["Shift", "Sprint"], ["Mouse", "Aim / facing"], ["F", "Flashlight"],
	["1 – 9", "Equipment"], ["Q / Mouse wheel", "Cycle items"], ["Left click", "Use item"],
	["E (hold)", "Interact / pick up / retrieve / melt / light"], ["Tab", "Choose suspected ghost"],
	["V (hold)", "Perform banishing rite"], ["R (hold)", "Restart run"], ["H", "Controls"], ["Esc", "Pause"],
]

static func register() -> void:
	_key("move_up", [KEY_W, KEY_UP])
	_key("move_down", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("sprint", [KEY_SHIFT])
	_key("flashlight", [KEY_F])
	_key("interact", [KEY_E])
	_key("rite", [KEY_V])
	_key("suspect", [KEY_TAB])
	_key("cycle", [KEY_Q])
	_key("restart", [KEY_R])
	_key("help", [KEY_H])
	_key("pause", [KEY_ESCAPE, KEY_P])
	for i in 9:
		_key("slot_%d" % (i + 1), [KEY_1 + i])
	if not InputMap.has_action("use"):
		InputMap.add_action("use")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("use", mb)
	for pair in [["cycle_next", MOUSE_BUTTON_WHEEL_DOWN], ["cycle_prev", MOUSE_BUTTON_WHEEL_UP]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
			var w := InputEventMouseButton.new()
			w.button_index = pair[1]
			InputMap.action_add_event(pair[0], w)

static func _key(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
