class_name Screen
extends Control
## Shared base for menu-style screens: illustrated backdrop + vignette.

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

## The same world as the houses and the menu desk: candlelit, grimy floorboards.
func add_backdrop(_path: String = "", dim: float = 0.35) -> void:
	var bg := TextureRect.new()
	bg.texture = Art.tex("floors/wood_dark.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.modulate = Color(0.42, 0.4, 0.44)
	add_child(bg)
	if Art.has("decor/grime.png"):
		var g := TextureRect.new()
		g.texture = Art.tex("decor/grime.png")
		g.set_anchors_preset(Control.PRESET_FULL_RECT)
		g.stretch_mode = TextureRect.STRETCH_TILE
		g.modulate = Color(1, 1, 1, 0.8)
		add_child(g)
	var warm := TextureRect.new()
	warm.texture = Art.tex("lights/soft.png")
	warm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	warm.set_anchors_preset(Control.PRESET_FULL_RECT)
	warm.offset_left = 200
	warm.offset_right = -200
	warm.offset_top = -120
	warm.offset_bottom = 120
	warm.modulate = Color(1.0, 0.72, 0.4, 0.22)
	warm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(warm)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, dim * 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var vig := TextureRect.new()
	vig.texture = Art.tex("ui/vignette.png")
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)

## Visible canvas size: at a larger Menu UI scale the canvas is smaller than the
## 1600x900 design size, so wide layouts must shrink to fit.
func canvas_size() -> Vector2:
	var vp := get_viewport()
	return vp.get_visible_rect().size if vp else Vector2(1600, 900)

func fit_width(width: float, margin: float = 80.0) -> float:
	return minf(width, canvas_size().x - margin)

func fit_height(height: float, margin: float = 200.0) -> float:
	return minf(height, canvas_size().y - margin)

func centered_column(width: float, top: float = 40.0) -> VBoxContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_top", int(top))
	m.add_theme_constant_override("margin_bottom", 30)
	add_child(m)
	var cc := CenterContainer.new()
	cc.use_top_left = false
	m.add_child(cc)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(fit_width(width), 0)
	v.add_theme_constant_override("separation", 12)
	cc.add_child(v)
	return v

func parchment_box(parent: Control, min_size: Vector2 = Vector2.ZERO) -> VBoxContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	return v

func back_button(parent: Control) -> void:
	parent.add_child(Art.button("Back", func(): Game.goto_menu(), 200))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		on_escape()

func on_escape() -> void:
	Game.goto_menu()
