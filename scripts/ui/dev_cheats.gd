class_name DevCheats
extends PanelContainer
## Developer-only progression panel (F10 in the main menu and the Forest Tavern).
## Debug builds or the dev setting only; never available during a match, and it
## never touches scores, records or leaderboard submissions.

signal changed()

var _amount: LineEdit
var _status: Label

func _init() -> void:
	visible = false
	z_index = 50
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.12, 0.95)
	sb.border_color = Color(0.4, 0.6, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -340
	offset_right = -20
	offset_top = 140
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	v.add_child(Art.label("DEV · Progression (F10)", 16, Color(0.6, 0.8, 1.0), Art.font_heading))
	_amount = LineEdit.new()
	_amount.text = "500"
	_amount.placeholder_text = "amount"
	v.add_child(_amount)
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(_btn("+ Ducats", func(): _add("ducats")))
	row.add_child(_btn("+ Renown", func(): _add("renown")))
	v.add_child(_btn("Reset test progression", _reset))
	# Immortal: the local hunter cannot die (solo; never in a match). Session only.
	var imm := CheckBox.new()
	imm.text = "Immortal (cannot die)"
	imm.button_pressed = Progression.immortal
	imm.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	imm.toggled.connect(func(on):
		Progression.immortal = on
		_status.text = "Immortal is ON — fatal blows are ignored." if on else "Immortal is off.")
	v.add_child(imm)
	_status = Art.label("Scores and leaderboards are untouched.", 12, Color(0.7, 0.75, 0.85), Art.font_italic)
	v.add_child(_status)

func _btn(t: String, cb: Callable) -> Button:
	var b := Art.button(t, cb, 140)
	b.custom_minimum_size = Vector2(140, 34)
	b.add_theme_font_size_override("font_size", 16)
	return b

func _add(key: String) -> void:
	var p := SaveData.progress()
	if not Progression.cheat_add(p, key, int(_amount.text)):
		return
	SaveData.save()
	_status.text = "%s now %d." % ["Ducats" if key == "ducats" else "Renown", int(p[key])]
	changed.emit()

func _reset() -> void:
	if not Progression.cheats_allowed():
		return
	Progression.reset_progress(SaveData.progress())
	SaveData.save()
	_status.text = "Ducats, Renown and wares reset."
	changed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10 and Progression.cheats_allowed():
		visible = not visible
		get_viewport().set_input_as_handled()
