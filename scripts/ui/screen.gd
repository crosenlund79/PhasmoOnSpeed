class_name Screen
extends Control
## Shared base for menu-style screens: illustrated backdrop + vignette.

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

func add_backdrop(path: String = "ui/menu_background.png", dim: float = 0.35) -> void:
	var bg := TextureRect.new()
	bg.texture = Art.tex(path)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, dim)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var vig := TextureRect.new()
	vig.texture = Art.tex("ui/vignette.png")
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)

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
	v.custom_minimum_size = Vector2(width, 0)
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
