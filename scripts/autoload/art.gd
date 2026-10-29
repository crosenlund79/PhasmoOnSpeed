extends Node
## Artwork lookup. Every texture is requested by a relative path (see
## docs/ASSET_MANIFEST.md). Creator art in res://assets/creator/ overrides the
## provisional art in res://assets/provisional/ without touching gameplay code.

const CREATOR_DIR := "res://assets/creator/"
const PROVISIONAL_DIR := "res://assets/provisional/"

const INK := Color(0.07, 0.06, 0.06)
const PARCHMENT := Color(0.86, 0.80, 0.66)
const PARCHMENT_DARK := Color(0.72, 0.64, 0.49)
const GOLD := Color(0.78, 0.63, 0.30)
const BLOOD := Color(0.62, 0.08, 0.06)
const SPECTRAL := Color(0.70, 0.90, 0.95)
const AMBER := Color(1.0, 0.72, 0.38)

var font_heading: Font
var font_body: Font
var font_italic: Font
var font_numeric: Font   # lining numerals for instant-read equipment values
var theme: Theme

var _cache := {}
var _missing_warned := {}

func _ready() -> void:
	font_heading = _load_font("res://assets/fonts/IMFellEnglishSC-Regular.ttf")
	font_body = _load_font("res://assets/fonts/IMFellEnglish-Regular.ttf")
	font_italic = _load_font("res://assets/fonts/IMFellEnglish-Italic.ttf")
	var bask := _load_font("res://assets/fonts/LibreBaskerville-Variable.ttf")
	var fv := FontVariation.new()
	fv.base_font = bask
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	font_numeric = fv
	theme = _build_theme()
	get_tree().root.theme = theme
	# CanvasLayers do not inherit the root theme, so also merge it into the
	# engine default theme used by every Control.
	ThemeDB.get_default_theme().merge_with(theme)
	ThemeDB.fallback_font = font_body

func _load_font(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path)
	return ThemeDB.fallback_font

## Returns true when a texture exists in creator or provisional art.
func has(path: String) -> bool:
	return ResourceLoader.exists(CREATOR_DIR + path) or ResourceLoader.exists(PROVISIONAL_DIR + path)

func tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var t: Texture2D = null
	for base in [CREATOR_DIR, PROVISIONAL_DIR]:
		if ResourceLoader.exists(base + path):
			t = load(base + path)
			if t:
				break
	if t == null:
		if not _missing_warned.has(path):
			_missing_warned[path] = true
			push_warning("Art missing: " + path)
		t = _placeholder(path)
	_cache[path] = t
	return t

func _placeholder(path: String) -> Texture2D:
	var size := 64
	if path.begins_with("tokens/"):
		size = 128
	elif path.begins_with("icons/"):
		size = 48
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(c)
			if d < size * 0.45:
				img.set_pixel(x, y, Color(0.3, 0.28, 0.3) if d < size * 0.4 else INK)
	return ImageTexture.create_from_image(img)

# --- Theme ----------------------------------------------------------------------

func stylebox(path: String, margin: int, fallback_bg: Color, fallback_border: Color) -> StyleBox:
	if has(path):
		var sb := StyleBoxTexture.new()
		sb.texture = tex(path)
		sb.texture_margin_left = margin
		sb.texture_margin_right = margin
		sb.texture_margin_top = margin
		sb.texture_margin_bottom = margin
		# Tile (not stretch) the illustrated centre so parchment grain stays crisp.
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		sb.content_margin_left = margin * 0.6
		sb.content_margin_right = margin * 0.6
		sb.content_margin_top = margin * 0.45
		sb.content_margin_bottom = margin * 0.45
		return sb
	var f := StyleBoxFlat.new()
	f.bg_color = fallback_bg
	f.border_color = fallback_border
	f.set_border_width_all(3)
	f.set_corner_radius_all(4)
	f.set_content_margin_all(margin * 0.5)
	return f

func parchment_panel() -> StyleBox:
	return stylebox("ui/panel_frame.png", 24, PARCHMENT, INK)

func dark_panel() -> StyleBox:
	return stylebox("ui/panel_dark.png", 24, Color(0.1, 0.09, 0.1, 0.95), GOLD)

func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font_body
	t.default_font_size = 20
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("panel", "PanelContainer", parchment_panel())
	t.set_stylebox("panel", "Panel", parchment_panel())
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var file := "ui/button.png"
		if state == "hover" or state == "focus":
			file = "ui/button_hover.png"
		elif state == "pressed":
			file = "ui/button_pressed.png"
		var sb := stylebox(file, 16, Color(0.18, 0.16, 0.16), GOLD)
		if state == "focus":
			sb = sb.duplicate()
		t.set_stylebox(state, "Button", sb)
	t.set_font("font", "Button", font_heading)
	t.set_font_size("font_size", "Button", 24)
	t.set_color("font_color", "Button", Color(0.93, 0.88, 0.76))
	t.set_color("font_hover_color", "Button", Color(1.0, 0.86, 0.5))
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_focus_color", "Button", Color(1.0, 0.86, 0.5))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.47, 0.42))
	var sbar := StyleBoxFlat.new()
	sbar.bg_color = Color(0.25, 0.2, 0.15, 0.25)
	t.set_stylebox("scroll", "VScrollBar", sbar)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.35, 0.27, 0.18, 0.7)
	grab.set_corner_radius_all(3)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	var line := StyleBoxFlat.new()
	line.bg_color = Color(0.12, 0.1, 0.09, 0.9)
	line.border_color = GOLD
	line.set_border_width_all(2)
	line.set_content_margin_all(6)
	t.set_stylebox("normal", "LineEdit", line)
	t.set_stylebox("focus", "LineEdit", line)
	t.set_color("font_color", "LineEdit", Color(0.93, 0.88, 0.76))
	var slider := StyleBoxFlat.new()
	slider.bg_color = Color(0.2, 0.17, 0.14)
	slider.content_margin_top = 4
	slider.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", slider)
	var area := StyleBoxFlat.new()
	area.bg_color = GOLD
	area.content_margin_top = 4
	area.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", area)
	t.set_stylebox("grabber_area_highlight", "HSlider", area)
	t.set_color("font_color", "CheckBox", Color(0.93, 0.88, 0.76))
	t.set_color("font_hover_color", "CheckBox", Color(1.0, 0.86, 0.5))
	t.set_color("font_pressed_color", "CheckBox", Color(0.93, 0.88, 0.76))
	return t

# --- Small UI factories shared by screens ----------------------------------------

func label(text: String, size: int = 20, color: Color = INK, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	return l

func heading(text: String, size: int = 30, color: Color = INK) -> Label:
	return label(text, size, color, font_heading)

func button(text: String, callback: Callable, min_width: int = 260) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 50)
	b.pressed.connect(func():
		Sfx.play("ui_click")
		callback.call())
	b.mouse_entered.connect(func(): Sfx.play("ui_hover", -14.0))
	return b

func icon_rect(path: String, size: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(path)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	return r
