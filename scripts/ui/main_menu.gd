extends Control
## Title screen: a live, overhead investigation desk in the same art, light and
## shadow as the houses — case files, photographs, the journal and tools under
## a guttering candle — with tactile brass-and-parchment plaques for navigation.

const DESK_ZOOM := 1.0

var settings_panel: Control
var help_panel: Control
var world: Node2D
var camera: Camera2D
var _t := 0.0
var _candles: Array = []
var _orbs: Array = []
var _sweep: PointLight2D
var _shadow: Sprite2D
var _shadow_t := 6.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Sfx.stop_loop("ambience")
	Sfx.stop_loop("hunt")
	Sfx.start_loop("music", "music_menu", -4.0, 1.5)
	_build_scene()
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	_build_ui(root)
	_build_settings(root)
	_build_help(root)

# --- The desk scene ---------------------------------------------------------------------

func _sprite(path: String, pos: Vector2, size: float, rot: float = 0.0, parent: Node = null) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Art.tex(path)
	s.position = pos
	s.rotation = rot
	var k := size / maxf(1.0, s.texture.get_size().x)
	s.scale = Vector2(k, k)
	(parent if parent else world).add_child(s)
	return s

func _shadowed(path: String, pos: Vector2, size: float, rot: float = 0.0) -> Sprite2D:
	var sh := _sprite(path, pos + Vector2(5, 7), size * 1.02, rot)
	sh.modulate = Color(0, 0, 0, 0.5)
	return _sprite(path, pos, size, rot)

func _build_scene() -> void:
	world = Node2D.new()
	add_child(world)
	var cm := CanvasModulate.new()
	cm.color = Color(0.2, 0.2, 0.27)
	world.add_child(cm)
	# Floorboards and a worn rug under the desk (exactly the gameplay floor art).
	var floor_tex := Art.tex("floors/wood_dark.png")
	var poly := Polygon2D.new()
	poly.texture = floor_tex
	poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var r := Rect2(-1400, -900, 2800, 1800)
	poly.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	poly.uv = PackedVector2Array([r.position * 2.0, Vector2(r.end.x, r.position.y) * 2.0, r.end * 2.0, Vector2(r.position.x, r.end.y) * 2.0])
	world.add_child(poly)
	if Art.has("decor/grime.png"):
		var g := Polygon2D.new()
		g.texture = Art.tex("decor/grime.png")
		g.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		g.polygon = poly.polygon
		g.uv = poly.uv
		g.color = Color(1, 1, 1, 0.45)
		world.add_child(g)
	_sprite("furniture/rug_rect.png", Vector2(170, 40), 900, 0.04)
	# The desk and what is on it.
	var desk_path := "furniture/desk_large.png" if Art.has("furniture/desk_large.png") else "furniture/desk.png"
	_shadowed(desk_path, Vector2(190, 30), 760)
	_shadowed("furniture/armchair.png", Vector2(200, 330), 190, PI)
	_shadowed("furniture/bookshelf.png", Vector2(-260, -430), 420)
	_shadowed("furniture/grandfather_clock.png", Vector2(690, -420), 100)
	_shadowed("furniture/floor_lamp.png", Vector2(-120, 300), 70)
	_shadowed("furniture/covered_armchair.png" if Art.has("furniture/covered_armchair.png") else "furniture/armchair.png", Vector2(780, 300), 210, 0.4)
	var props := [
		["menu/case_file.png", Vector2(20, -40), 190, -0.12],
		["menu/journal_open.png", Vector2(250, 60), 300, 0.05],
		["menu/map_pinned.png", Vector2(420, -110), 220, 0.14],
		["menu/case_photo_1.png", Vector2(90, -150), 96, -0.3],
		["menu/case_photo_2.png", Vector2(500, 120), 92, 0.25],
		["menu/case_photo_3.png", Vector2(-40, 120), 90, 0.18],
		["menu/pocket_watch.png", Vector2(390, 160), 64, 0.0],
		["menu/magnifier.png", Vector2(150, 160), 84, 0.7],
		["menu/inkwell.png", Vector2(480, 10), 56, 0.0],
	]
	for p in props:
		if Art.has(p[0]):
			_shadowed(p[0], p[1], p[2], p[3])
	for it in [["icons/eq_emf.png", Vector2(-30, 20), 54, 0.4], ["icons/eq_thermometer.png", Vector2(560, -60), 48, -0.9],
			["items/garlic.png", Vector2(330, -160), 40, 0.0], ["items/silverware.png", Vector2(-60, -100), 44, 1.1],
			["items/hand_mirror.png", Vector2(600, 170), 46, -0.4], ["icons/eq_spirit_box.png", Vector2(60, 60), 50, -0.2]]:
		_shadowed(it[0], it[1], it[2], it[3])
	# Warm candles against the cold room, and a pale presence.
	for cpos in [Vector2(-10, -170), Vector2(560, -170)]:
		_shadowed("furniture/candelabra.png", cpos, 62)
		var l := PointLight2D.new()
		l.texture = Art.tex("lights/candle.png")
		l.position = cpos
		l.color = Color(1.0, 0.68, 0.34)
		l.energy = 1.05
		l.texture_scale = 3.2
		world.add_child(l)
		_candles.append(l)
	var lamp := PointLight2D.new()
	lamp.texture = Art.tex("lights/soft.png")
	lamp.position = Vector2(-120, 300)
	lamp.color = Color(1.0, 0.78, 0.5)
	lamp.energy = 0.55
	lamp.texture_scale = 1.6
	world.add_child(lamp)
	var moon := PointLight2D.new()
	moon.texture = Art.tex("lights/soft.png")
	moon.position = Vector2(-700, -500)
	moon.color = Color(0.55, 0.65, 0.95)
	moon.energy = 0.5
	moon.texture_scale = 4.0
	world.add_child(moon)
	# A flashlight left on the desk, slowly swept by an unseen hand.
	_sweep = Lighting.make_cone(Color(1.0, 0.92, 0.75), 0.9, 0.9)
	_sweep.position = Vector2(-40, 230)
	_sweep.shadow_enabled = false
	world.add_child(_sweep)
	for i in 4:
		var o := _sprite("items/orb.png", Vector2(randf_range(-500, 800), randf_range(-400, 400)), 26)
		o.modulate = Color(0.8, 0.95, 1.0, 0.0)
		o.set_meta("phase", randf() * TAU)
		o.set_meta("base", o.position)
		_orbs.append(o)
	_shadow = _sprite("tokens/shade.png", Vector2(-900, 260), 120, 0.0)
	_shadow.modulate = Color(0.6, 0.75, 0.85, 0.0)
	camera = Camera2D.new()
	camera.zoom = Vector2(DESK_ZOOM, DESK_ZOOM)
	camera.position = Vector2(-80, 0)
	world.add_child(camera)
	camera.make_current()

func _process(delta: float) -> void:
	_t += delta
	for i in _candles.size():
		var l: PointLight2D = _candles[i]
		l.energy = 1.0 + sin(_t * 8.0 + i * 2.0) * 0.08 + sin(_t * 21.0 + i) * 0.05
	_sweep.rotation = -1.1 + sin(_t * 0.25) * 0.55
	for o in _orbs:
		var ph: float = o.get_meta("phase")
		o.position = o.get_meta("base") + Vector2(sin(_t * 0.3 + ph) * 60.0, cos(_t * 0.22 + ph * 2.0) * 40.0)
		o.modulate.a = clampf(0.35 + 0.35 * sin(_t * 0.7 + ph), 0.0, 0.7)
	# Every so often something pale drifts past the edge of the light.
	_shadow_t -= delta
	if _shadow_t <= 0.0:
		_shadow_t = randf_range(14.0, 24.0)
		_shadow.position = Vector2(-950, randf_range(-250, 350))
		var tw := create_tween()
		tw.tween_property(_shadow, "modulate:a", 0.45, 1.5)
		tw.parallel().tween_property(_shadow, "position:x", -350.0, 6.0)
		tw.tween_property(_shadow, "modulate:a", 0.0, 1.5)
	camera.position = Vector2(-80, 0) + Vector2(sin(_t * 0.07) * 14.0, cos(_t * 0.05) * 9.0)

# --- Interface ---------------------------------------------------------------------------

func _plaque(text: String, cb: Callable, width: int = 360, dev: bool = false) -> Button:
	var b := Art.button(text, cb, width)
	b.custom_minimum_size = Vector2(width, 58)
	var base := "menu/plaque_dev.png" if dev else "menu/plaque.png"
	if Art.has(base):
		b.add_theme_stylebox_override("normal", Art.stylebox(base, 24, Color(), Color()))
		b.add_theme_stylebox_override("hover", Art.stylebox("menu/plaque_hover.png" if not dev else base, 24, Color(), Color()))
		b.add_theme_stylebox_override("focus", Art.stylebox("menu/plaque_hover.png" if not dev else base, 24, Color(), Color()))
		b.add_theme_stylebox_override("pressed", Art.stylebox("menu/plaque_pressed.png" if not dev else base, 24, Color(), Color()))
		var ink := Color(0.16, 0.11, 0.07) if not dev else Color(0.08, 0.12, 0.2)
		b.add_theme_color_override("font_color", ink)
		b.add_theme_color_override("font_hover_color", Color(0.45, 0.12, 0.05) if not dev else Color(0.02, 0.05, 0.12))
		b.add_theme_color_override("font_focus_color", Color(0.45, 0.12, 0.05) if not dev else Color(0.02, 0.05, 0.12))
		b.add_theme_color_override("font_pressed_color", Color(0.3, 0.08, 0.03))
	# A small tactile tilt on hover.
	b.pivot_offset = Vector2(width * 0.5, 29)
	b.mouse_entered.connect(func(): b.create_tween().tween_property(b, "rotation", -0.012, 0.12))
	b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "rotation", 0.0, 0.12))
	return b

func _build_ui(root: Control) -> void:
	var shade := TextureRect.new()
	shade.texture = Art.tex("ui/vignette.png")
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var left := VBoxContainer.new()
	left.anchor_bottom = 1.0
	left.offset_left = 60
	left.offset_top = 36
	left.offset_right = 620
	left.offset_bottom = -30
	left.add_theme_constant_override("separation", 10)
	root.add_child(left)
	var logo_holder := Control.new()
	logo_holder.custom_minimum_size = Vector2(560, 150)
	left.add_child(logo_holder)
	var mist := TextureRect.new()
	mist.texture = Art.tex("lights/soft.png")
	mist.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mist.modulate = Color(0.9, 0.85, 0.72, 0.55)
	mist.position = Vector2(-60, -50)
	mist.size = Vector2(680, 260)
	mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_holder.add_child(mist)
	var logo := TextureRect.new()
	logo.texture = Art.tex("ui/title_logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.size = Vector2(560, 140)
	logo_holder.add_child(logo)
	var tag := Art.label("A supernatural investigation speedrun", 21, Color(0.92, 0.86, 0.72), Art.font_italic)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_constant_override("outline_size", 6)
	left.add_child(tag)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	left.add_child(gap)
	var begin := _plaque("Begin Investigation", func(): Game.goto_house_select())
	left.add_child(begin)
	left.add_child(_plaque("Competitive Hunt", func(): Game.goto_lobby()))
	left.add_child(_plaque("Encyclopedia", func(): Game.goto_encyclopedia()))
	left.add_child(_plaque("Rankings", func(): Game.goto_rankings()))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	left.add_child(row)
	row.add_child(_plaque("Settings", func(): settings_panel.visible = true, 176))
	row.add_child(_plaque("Controls", func(): help_panel.visible = true, 176))
	left.add_child(_plaque("Quit", func(): get_tree().quit(), 176))
	var best: int = SaveData.data["records"]["best_score"]
	if best > 0:
		var b := Art.label("Personal best: %d points" % best, 18, Art.GOLD, Art.font_heading)
		b.add_theme_color_override("font_outline_color", Color.BLACK)
		b.add_theme_constant_override("outline_size", 6)
		left.add_child(b)
	# Developer tools live apart from the player-facing menu.
	if SaveData.settings().get("dev_mode", true) or OS.is_debug_build():
		var dev := _plaque("DEV STATISTICS", func(): Game.goto_stats(), 230, true)
		dev.add_theme_font_size_override("font_size", 16)
		dev.anchor_left = 1.0
		dev.anchor_right = 1.0
		dev.anchor_top = 1.0
		dev.anchor_bottom = 1.0
		dev.offset_left = -250
		dev.offset_right = -20
		dev.offset_top = -100
		dev.offset_bottom = -46
		root.add_child(dev)
	var ver := Art.label("v%s · score rules %s / %s" % [ProjectSettings.get_setting("application/config/version"), Scoring.RULES_VERSION, MpScoring.RULES_VERSION], 13, Color(0.7, 0.68, 0.62))
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.anchor_left = 1.0
	ver.anchor_right = 1.0
	ver.offset_left = -330
	ver.offset_top = -32
	ver.add_theme_color_override("font_outline_color", Color.BLACK)
	ver.add_theme_constant_override("outline_size", 4)
	root.add_child(ver)
	begin.grab_focus()

func _modal(root: Control, width: float) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.visible = false
	root.add_child(cc)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.show_behind_parent = true
	cc.add_child(dim)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(width, 0)
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	return v

func _slider(v: VBoxContainer, title: String, key: String, lo: float, hi: float, step: float, apply_now: bool) -> void:
	var row := HBoxContainer.new()
	v.add_child(row)
	var l := Art.label(title, 17)
	l.custom_minimum_size = Vector2(250, 0)
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = float(SaveData.settings().get(key, lo))
	sl.custom_minimum_size = Vector2(300, 24)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(val):
		SaveData.set_setting(key, val)
		if apply_now:
			Game.apply_settings())
	sl.drag_ended.connect(func(_c): Game.apply_settings())
	row.add_child(sl)

func _check(v: VBoxContainer, title: String, key: String) -> void:
	var c := CheckBox.new()
	c.text = title
	c.add_theme_color_override("font_color", Art.INK)
	c.add_theme_color_override("font_hover_color", Color(0.45, 0.12, 0.05))
	c.add_theme_color_override("font_pressed_color", Art.INK)
	c.button_pressed = SaveData.settings().get(key, true)
	c.toggled.connect(func(on):
		SaveData.set_setting(key, on)
		Game.apply_settings())
	v.add_child(c)

func _build_settings(root: Control) -> void:
	var v := _modal(root, 640)
	settings_panel = v.get_parent().get_parent()
	v.add_child(Art.heading("Settings", 34))
	var name_row := HBoxContainer.new()
	v.add_child(name_row)
	var nl := Art.label("Investigator name", 17)
	nl.custom_minimum_size = Vector2(250, 0)
	name_row.add_child(nl)
	var name_edit := LineEdit.new()
	name_edit.text = SaveData.settings().get("player_name", "Investigator")
	name_edit.max_length = 20
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(t): SaveData.set_setting("player_name", t.strip_edges() if t.strip_edges() != "" else "Investigator"))
	name_row.add_child(name_edit)
	v.add_child(Art.label("Sound & display", 18, Color(0.35, 0.22, 0.12), Art.font_heading))
	_slider(v, "Master volume", "master", 0.0, 1.0, 0.05, true)
	_slider(v, "Music volume", "music", 0.0, 1.0, 0.05, true)
	_slider(v, "Menu UI scale", "ui_scale", Game.MENU_SCALE_MIN, Game.MENU_SCALE_MAX, 0.05, false)
	_slider(v, "Gameplay UI scale", "hud_scale", Game.GAME_SCALE_MIN, Game.GAME_SCALE_MAX, 0.05, false)
	_check(v, "Fullscreen (F11)", "fullscreen")
	v.add_child(Art.label("Investigation HUD", 18, Color(0.35, 0.22, 0.12), Art.font_heading))
	_check(v, "Show equipment labels", "equip_labels")
	_check(v, "Show evidence labels", "ev_labels")
	_check(v, "Show suspect requirement labels", "suspect_labels")
	_slider(v, "Equipment HUD opacity", "equip_hud_opacity", 0.2, 1.0, 0.05, false)
	v.add_child(Art.label("Evidence notifications", 18, Color(0.35, 0.22, 0.12), Art.font_heading))
	_check(v, "Show 'Evidence recorded' cards", "ev_notify")
	_slider(v, "Evidence notification opacity", "ev_notify_opacity", 0.2, 1.0, 0.05, false)
	_slider(v, "Card size", "ev_notify_size", 0.6, 1.6, 0.05, false)
	v.add_child(Art.label("Occupants", 18, Color(0.35, 0.22, 0.12), Art.font_heading))
	_check(v, "Show occupant names", "npc_names")
	_check(v, "Safe names (original characters; off = famous fictional names, private use)", "safe_names")
	v.add_child(Art.button("Close", func(): settings_panel.visible = false))

func _build_help(root: Control) -> void:
	var v := _modal(root, 620)
	help_panel = v.get_parent().get_parent()
	v.add_child(Art.heading("Controls", 34))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	v.add_child(grid)
	for row in Controls.HELP:
		grid.add_child(Art.label(row[0], 17, Art.INK, Art.font_heading))
		grid.add_child(Art.label(row[1], 17))
	var how := Art.label("Find evidence — it is written into your journal automatically. Identify the entity (any entity can be chosen at any time), prepare, and vanquish it. Two wounds and you perish.", 16, Color(0.27, 0.2, 0.14), Art.font_italic)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	how.custom_minimum_size = Vector2(560, 0)
	v.add_child(how)
	v.add_child(Art.button("Close", func(): help_panel.visible = false))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		settings_panel.visible = false
		help_panel.visible = false
