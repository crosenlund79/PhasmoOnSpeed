class_name SetupForm
extends VBoxContainer
## Normal Game / Custom Game setup, shared by the solo setup screen and the
## multiplayer lobby (where only the host may edit it). Houses, entities and
## difficulties come straight from the game data, so new ones appear here
## automatically. Emits `changed` with the full setup dictionary
## (see Game.DEFAULT_SETUP).

signal changed(setup: Dictionary)

const INK_SOFT := Color(0.3, 0.22, 0.15)

var setup := {}
var editable := true
var on_parchment := false
var marker_in_normal := true   # solo: the Ghost Marker is offered for both game types
var _marker_row: HBoxContainer
var _marker_buttons := {}      # dark ink labels (lobby panel) instead of pale ones (backdrop)
var _mode_buttons := {}
var _diff_buttons := {}
var _moon_buttons := {}
var _custom_rows: Array = []
var _house_pick: OptionButton
var _entity_pick: OptionButton
var _summary: Label
var _house_ids: Array = []
var _entity_ids: Array = []

func _init(p_setup: Dictionary = {}, p_editable: bool = true) -> void:
	setup = Game.DEFAULT_SETUP.duplicate()
	setup.merge(p_setup, true)
	editable = p_editable
	add_theme_constant_override("separation", 10)

func _ready() -> void:
	_row("Game", func(row):
		for m in [["normal", "Normal Game"], ["custom", "Custom Game"]]:
			_mode_buttons[m[0]] = _toggle(row, m[1], "mode", m[0], 230))
	_row("Difficulty", func(row):
		for d in Defs.DIFFICULTIES + ["random"]:
			var label: String = "Random" if d == "random" else Defs.difficulty_name(d)
			var b := _toggle(row, label, "difficulty", d, 140)
			if Defs.rules(d) == "nightmare":
				b.add_theme_color_override("font_color", Color(0.75, 0.1, 0.07))
			_diff_buttons[d] = b)
	_custom_rows.append(_row("House", func(row):
		_house_pick = OptionButton.new()
		_house_pick.custom_minimum_size = Vector2(360, 44)
		_house_pick.add_item("Random house")
		_house_ids = ["random"]
		for id in Game.house_ids:
			_house_pick.add_item(Game.house(id)["name"])
			_house_ids.append(id)
		_house_pick.item_selected.connect(func(i): _choose("house", _house_ids[i]))
		row.add_child(_house_pick)))
	_custom_rows.append(_row("Entity", func(row):
		_entity_pick = OptionButton.new()
		_entity_pick.custom_minimum_size = Vector2(360, 44)
		_entity_pick.add_item("Random entity")
		_entity_ids = ["random"]
		for id in Defs.ORDINARY_CREATURES:
			_entity_pick.add_item(Defs.creature_name(id))
			_entity_ids.append(id)
		_entity_pick.item_selected.connect(func(i): _choose("entity", _entity_ids[i]))
		row.add_child(_entity_pick)))
	_custom_rows.append(_row("Blood Moon", func(row):
		for m in [["on", "On"], ["off", "Off"], ["random", "Random"]]:
			_moon_buttons[m[0]] = _toggle(row, m[1], "blood_moon", m[0], 140)))
	_marker_row = _row("Ghost Marker", func(row):
		for m in [["off", "Off"], ["on", "Always Show"]]:
			_marker_buttons[m[0]] = _toggle(row, m[1], "ghost_marker", m[0], 180)
		var note := Art.label("playtesting aid", 14, INK_SOFT if on_parchment else Color(0.7, 0.66, 0.6), Art.font_italic)
		row.add_child(note))
	_summary = Art.label("", 16, INK_SOFT if on_parchment else Color(0.82, 0.78, 0.7), Art.font_italic)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.custom_minimum_size = Vector2(900, 0)
	add_child(_summary)
	refresh()

func _row(title: String, build: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := Art.heading(title, 20, Art.INK if on_parchment else Color(0.93, 0.85, 0.65))
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	build.call(row)
	add_child(row)
	return row

func _toggle(row: HBoxContainer, label: String, key: String, value: String, width: int) -> Button:
	var b := Art.button(label, func(): _choose(key, value), width)
	b.add_theme_font_size_override("font_size", 17)
	b.toggle_mode = true
	row.add_child(b)
	return b

func _choose(key: String, value: String) -> void:
	if not editable:
		return
	setup[key] = value
	refresh()
	changed.emit(setup.duplicate())

## Shows `s` (e.g. the host's setup arriving in the lobby).
func show_setup(s: Dictionary) -> void:
	setup = Game.DEFAULT_SETUP.duplicate()
	setup.merge(s, true)
	if is_inside_tree():
		refresh()

func refresh() -> void:
	if _summary == null:
		return
	var custom: bool = setup["mode"] == "custom"
	for k in _mode_buttons:
		_mode_buttons[k].set_pressed_no_signal(setup["mode"] == k)
	for k in _diff_buttons:
		_diff_buttons[k].set_pressed_no_signal(setup["difficulty"] == k)
	for k in _moon_buttons:
		_moon_buttons[k].set_pressed_no_signal(setup["blood_moon"] == k)
	for r in _custom_rows:
		r.visible = custom
	_marker_row.visible = custom or marker_in_normal
	for k in _marker_buttons:
		_marker_buttons[k].set_pressed_no_signal(str(setup.get("ghost_marker", "off")) == k)
		_marker_buttons[k].disabled = not editable
	_house_pick.select(maxi(0, _house_ids.find(setup["house"])))
	_entity_pick.select(maxi(0, _entity_ids.find(setup["entity"])))
	for b in _mode_buttons.values() + _diff_buttons.values() + _moon_buttons.values():
		b.disabled = not editable
	_house_pick.disabled = not editable
	_entity_pick.disabled = not editable
	_summary.text = summary_text(setup)

## One line saying what is fixed and what the dice will decide.
static func summary_text(s: Dictionary) -> String:
	var fixed: Array = []
	var rolled: Array = []
	var custom: bool = s["mode"] == "custom"
	if custom and s["house"] != "random":
		fixed.append(Game.house(s["house"])["name"])
	else:
		rolled.append("the house")
	if custom and s["entity"] != "random":
		fixed.append(Defs.creature_name(s["entity"]))
	else:
		rolled.append("the entity")
	if s["difficulty"] == "random":
		rolled.append("the difficulty (never Beginner)")
	else:
		fixed.append(Defs.difficulty_name(s["difficulty"]))
	if custom and s["blood_moon"] == "on":
		fixed.append("Blood Moon")
	elif custom and s["blood_moon"] == "off":
		fixed.append("no Blood Moon")
	else:
		rolled.append("whether a Blood Moon rises")
	var text := ""
	if not fixed.is_empty():
		text = "Chosen: " + ", ".join(fixed) + ".  "
	if not rolled.is_empty():
		text += "Left to chance: " + ", ".join(rolled) + "."
	if str(s.get("ghost_marker", "off")) == "on":
		text += "  The entity is always marked."
	if s["difficulty"] != "random":
		text += "\n" + Defs.DIFFICULTY_INFO[s["difficulty"]]["desc"]
	return text
