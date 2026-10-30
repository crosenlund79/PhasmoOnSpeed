extends Screen
## Begin Investigation: Normal Game (house, entity and Blood Moon left to chance;
## pick a difficulty) or Custom Game (choose any of them, or leave them random).

var form: SetupForm

func _ready() -> void:
	add_backdrop("ui/menu_background.png", 0.55)
	var v := centered_column(1200, 60)
	var t := Art.heading("Begin Investigation", 46, Color(0.93, 0.85, 0.65))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_outline_color", Color.BLACK)
	t.add_theme_constant_override("outline_size", 8)
	v.add_child(t)
	var sub := Art.label("Each visit, something different waits inside. Or so you hope.", 19, Color(0.82, 0.78, 0.7), Art.font_italic)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	form = SetupForm.new(saved_setup(), true)
	form.changed.connect(func(s): SaveData.set_setting("setup", s))
	v.add_child(form)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 14)
	v.add_child(bottom)
	var start := Art.button("Start", func(): Game.start_setup(form.setup), 300)
	bottom.add_child(start)
	back_button(bottom)
	start.grab_focus()

## The last setup used (older saves only remember a difficulty).
static func saved_setup() -> Dictionary:
	var s: Dictionary = Game.DEFAULT_SETUP.duplicate()
	s["difficulty"] = str(SaveData.settings().get("difficulty", "normal"))
	var saved = SaveData.settings().get("setup", {})
	if typeof(saved) == TYPE_DICTIONARY:
		s.merge(saved, true)
	return s
