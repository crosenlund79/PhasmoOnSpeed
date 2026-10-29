class_name SpeechTag
extends RefCounted
## Name label + speech line for an occupant-looking figure, drawn on the unlit
## world-text layer. Occupants and the shapeshifter's human disguise use exactly
## the same tag so the UI never betrays the disguise.

const NAME_COLOR := Color(0.88, 0.84, 0.74)

var name_label: Label
var bubble: Label
var _bubble_t := 0.0

func _init(layer: CanvasLayer, display_name: String) -> void:
	name_label = Label.new()
	name_label.text = display_name
	name_label.add_theme_font_override("font", Art.font_body)
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", NAME_COLOR)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	name_label.add_theme_constant_override("outline_size", 4)
	name_label.size = Vector2(160, 16)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(name_label)
	bubble = Label.new()
	bubble.add_theme_font_override("font", Art.font_italic)
	bubble.add_theme_font_size_override("font_size", 13)
	bubble.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	bubble.add_theme_color_override("font_outline_color", Color.BLACK)
	bubble.add_theme_constant_override("outline_size", 5)
	bubble.size = Vector2(260, 20)
	bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble.modulate.a = 0.0
	layer.add_child(bubble)

func set_name(n: String) -> void:
	name_label.text = n

func say(text: String) -> void:
	bubble.text = tr(text)
	_bubble_t = 3.2

func update(pos: Vector2, alpha: float, delta: float) -> void:
	_bubble_t -= delta
	name_label.position = pos + Vector2(-80, 17)
	name_label.visible = SaveData.settings().get("npc_names", true)
	name_label.modulate.a = alpha
	bubble.position = pos + Vector2(-130, -44)
	bubble.modulate.a = clampf(_bubble_t, 0.0, 1.0) * alpha

func set_visible(v: bool) -> void:
	name_label.visible = v and SaveData.settings().get("npc_names", true)
	bubble.visible = v

func free_labels() -> void:
	name_label.queue_free()
	bubble.queue_free()
