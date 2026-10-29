extends Screen
## Title screen.

var settings_panel: Control
var help_panel: Control

func _ready() -> void:
	add_backdrop("ui/menu_background.png", 0.15)
	Sfx.stop_loop("ambience")
	Sfx.stop_loop("hunt")
	Sfx.start_loop("music", "music_menu", -4.0, 1.5)
	var left := VBoxContainer.new()
	left.anchor_left = 0.0
	left.anchor_top = 0.0
	left.anchor_bottom = 1.0
	left.offset_left = 70
	left.offset_top = 50
	left.offset_right = 700
	left.offset_bottom = -40
	left.add_theme_constant_override("separation", 12)
	add_child(left)
	var logo := TextureRect.new()
	logo.texture = Art.tex("ui/title_logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.custom_minimum_size = Vector2(600, 150)
	left.add_child(logo)
	var tag := Art.label("A supernatural investigation speedrun", 22, Color(0.85, 0.8, 0.68), Art.font_italic)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_constant_override("outline_size", 6)
	left.add_child(tag)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	left.add_child(spacer)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	left.add_child(buttons)
	var begin := Art.button("Begin Investigation", func(): Game.goto_house_select(), 340)
	buttons.add_child(begin)
	buttons.add_child(Art.button("Rankings", func(): Game.goto_rankings(), 340))
	buttons.add_child(Art.button("Controls", func(): help_panel.visible = true, 340))
	buttons.add_child(Art.button("Settings", func(): settings_panel.visible = true, 340))
	if SaveData.settings().get("dev_mode", true) or OS.is_debug_build():
		var dev := Art.button("DEV STATISTICS", func(): Game.goto_stats(), 340)
		dev.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		buttons.add_child(dev)
	buttons.add_child(Art.button("Quit", func(): get_tree().quit(), 340))
	var best: int = SaveData.data["records"]["best_score"]
	if best > 0:
		var b := Art.label("Personal best: %d points" % best, 18, Art.GOLD, Art.font_heading)
		b.add_theme_color_override("font_outline_color", Color.BLACK)
		b.add_theme_constant_override("outline_size", 6)
		left.add_child(b)
	var ver := Art.label("v%s · score rules %s" % [ProjectSettings.get_setting("application/config/version"), Scoring.RULES_VERSION], 14, Color(0.6, 0.58, 0.55))
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.anchor_left = 1.0
	ver.anchor_right = 1.0
	ver.offset_left = -260
	ver.offset_top = -30
	add_child(ver)
	_build_settings()
	_build_help()
	begin.grab_focus()

func _modal(width: float) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.visible = false
	add_child(cc)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.show_behind_parent = true
	cc.add_child(dim)
	var v := parchment_box(cc, Vector2(width, 0))
	v.add_theme_constant_override("separation", 10)
	return v

func _build_settings() -> void:
	var v := _modal(520)
	settings_panel = v.get_parent().get_parent()
	v.add_child(Art.heading("Settings", 34))
	var s: Dictionary = SaveData.settings()
	v.add_child(Art.label("Investigator name", 18))
	var name_edit := LineEdit.new()
	name_edit.text = s.get("player_name", "Investigator")
	name_edit.max_length = 24
	name_edit.text_changed.connect(func(t): SaveData.set_setting("player_name", t.strip_edges() if t.strip_edges() != "" else "Investigator"))
	v.add_child(name_edit)
	for pair in [["Master volume", "master"], ["Music volume", "music"], ["Interface scale", "ui_scale"]]:
		v.add_child(Art.label(pair[0], 18))
		var sl := HSlider.new()
		sl.min_value = 0.75 if pair[1] == "ui_scale" else 0.0
		sl.max_value = 1.5 if pair[1] == "ui_scale" else 1.0
		sl.step = 0.05
		sl.value = float(s.get(pair[1], 1.0))
		var key: String = pair[1]
		sl.value_changed.connect(func(val):
			SaveData.set_setting(key, val)
			if key != "ui_scale":
				Game.apply_settings())
		sl.drag_ended.connect(func(_c): Game.apply_settings())
		v.add_child(sl)
	var fs := CheckBox.new()
	fs.text = "Fullscreen (F11)"
	fs.add_theme_color_override("font_color", Art.INK)
	fs.button_pressed = s.get("fullscreen", false)
	fs.toggled.connect(func(on):
		SaveData.set_setting("fullscreen", on)
		Game.apply_settings())
	v.add_child(fs)
	v.add_child(Art.button("Close", func(): settings_panel.visible = false))

func _build_help() -> void:
	var v := _modal(600)
	help_panel = v.get_parent().get_parent()
	v.add_child(Art.heading("Controls", 34))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	v.add_child(grid)
	for row in Controls.HELP:
		grid.add_child(Art.label(row[0], 18, Art.INK, Art.font_heading))
		grid.add_child(Art.label(row[1], 18))
	var how := Art.label("Find evidence — it is recorded in your journal automatically. Identify the entity, prepare, and vanquish it. You may try at any time. Two wounds and you perish.", 16, Color(0.27, 0.2, 0.14), Art.font_italic)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size = Vector2(540, 0)
	v.add_child(how)
	v.add_child(Art.button("Close", func(): help_panel.visible = false))

func on_escape() -> void:
	settings_panel.visible = false
	help_panel.visible = false
