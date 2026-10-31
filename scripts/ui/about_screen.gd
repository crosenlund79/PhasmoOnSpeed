extends Screen
## About: one short parchment page on what The Witchening Tales is.

const SECTIONS := [
	["icons/ui_house.png", "Gothic Noir hauntings",
		"Lamplit cottages, rectories, inns and harbours stand silent under the moon, and something lives in every one. Each visit is a different house and a different entity — a shade, a poltergeist, a drowned sailor, a vampire, a werewolf, worse. Runs are brief: three to five minutes of dread."],
	["icons/eq_emf.png", "The old instruments",
		"You carry the tools of the occult trade: the Witch's Needle twitching in its glass, the Wraithlight Lantern that shows what hands have touched, the Whisper Box, the Scrying Mirror, the thermometer, salt, crucifix and holy water."],
	["icons/ui_quill.png", "Evidence, then the vanquishing",
		"What you observe is written into your journal. Read the signs, name the entity, gather what it fears — garlic, a stake, silver, iron — and finish it before it finishes you. Two wounds and you perish."],
	["icons/ui_tavern.png", "Renown, ducats and the Forest Tavern",
		"Every hunt earns Renown, which raises your hunter's rank, and Gold Ducats, spent at the Forest Tavern where the Witch keeps finer instruments for those who can pay."],
	["icons/ui_crown.png", "Alone, or against rivals",
		"Investigate solo and chase your best time on the rankings, or call two to four hunters into a Competitive Hunt: one house, one entity, and every journal kept private until someone strikes the final blow."],
]

func _ready() -> void:
	add_backdrop("ui/menu_background.png", 0.6)
	var v := centered_column(860, 34)
	var t := Art.heading("About The Witchening Tales", 40, Color(0.93, 0.85, 0.65))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_outline_color", Color.BLACK)
	t.add_theme_constant_override("outline_size", 8)
	v.add_child(t)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(panel)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16 if side != "top" else 10)
	panel.add_child(pad)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, fit_height(580, 220))
	pad.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)
	scroll.add_child(page)
	var intro := Art.label("A supernatural investigation in the Gothic Noir tradition: walk into a haunted house with a lantern and a notebook, learn what waits there, and send it back where it came from.", 18, Color(0.27, 0.2, 0.14), Art.font_italic)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(intro)
	for s in SECTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		page.add_child(row)
		var ic := Art.icon_rect(s[0], 44)
		ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(ic)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		row.add_child(col)
		col.add_child(Art.heading(s[1], 21, Color(0.35, 0.22, 0.12)))
		var body := Art.label(s[2], 17)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(body)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(bottom)
	back_button(bottom)
	bottom.get_child(0).grab_focus()
