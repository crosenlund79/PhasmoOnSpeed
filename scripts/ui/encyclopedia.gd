extends Screen
## The Hunter's Encyclopedia: every entity, its evidence, behaviour, hunting,
## strengths, weaknesses and exact vanquishing requirements — plus an equipment
## reference. All text comes from Defs (the data that drives the game) and a few
## facts are derived from the gameplay numbers themselves.

var list_box: VBoxContainer
var page: VBoxContainer
var _buttons := {}

func _ready() -> void:
	add_backdrop("ui/menu_background.png", 0.65)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40
	root.offset_right = -40
	root.offset_top = 30
	root.offset_bottom = -30
	root.add_theme_constant_override("separation", 18)
	add_child(root)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	left.add_theme_constant_override("separation", 8)
	root.add_child(left)
	var t := Art.heading("Encyclopedia", 40, Color(0.93, 0.85, 0.65))
	t.add_theme_color_override("font_outline_color", Color.BLACK)
	t.add_theme_constant_override("outline_size", 8)
	left.add_child(t)
	left.add_child(Art.label("Everything a hunter needs to know.", 16, Color(0.82, 0.78, 0.7), Art.font_italic))
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 6)
	left.add_child(list_box)
	for id in Defs.ENCYCLOPEDIA_ORDER:
		_add_entry_button(id, Defs.creature_name(id), Defs.CREATURES[id]["token"])
	_add_entry_button("_equipment", "Equipment", "icons/eq_emf.png")
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	left.add_child(Art.button("Back", func(): Game.goto_menu(), 330))
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	page = VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	scroll.add_child(page)
	show_entry(Defs.ENCYCLOPEDIA_ORDER[0])
	_buttons[Defs.ENCYCLOPEDIA_ORDER[0]].grab_focus()

func _add_entry_button(id: String, title: String, icon: String) -> void:
	var b := Button.new()
	b.text = "  " + title
	b.icon = Art.tex(icon)
	b.expand_icon = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(330, 56)
	b.add_theme_constant_override("icon_max_width", 40)
	b.pressed.connect(func():
		Sfx.play("ui_click")
		show_entry(id))
	b.focus_entered.connect(func(): show_entry(id))
	list_box.add_child(b)
	_buttons[id] = b

func _para(text: String, size: int = 18, italic: bool = false) -> Label:
	var l := Art.label(text, size, Art.INK, Art.font_italic if italic else null)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _section(title: String) -> void:
	var l := Art.heading(title, 22, Color(0.35, 0.22, 0.12))
	page.add_child(l)

func _bullets(items: Array) -> void:
	for it in items:
		page.add_child(_para("•  " + str(it), 17))

func show_entry(id: String) -> void:
	for c in page.get_children():
		c.queue_free()
	if id == "_equipment":
		_show_equipment()
		return
	var d: Dictionary = Defs.CREATURES[id]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	page.add_child(head)
	head.add_child(Art.icon_rect(d["token"], 128))
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(Art.heading(d["name"], 40))
	hv.add_child(_para(d["blurb"], 19, true))
	var kind: String = {"ghost": "Ghost — conventional ghost-hunting equipment works on it.",
		"physical": "Not a ghost — conventional ghost-hunting equipment tells you nothing.",
		"harbinger": "Something worse — called by recklessness."}[d["kind"]]
	hv.add_child(Art.label(kind, 16, Art.BLOOD, Art.font_heading))
	_section("Evidence")
	if d["evidence"].is_empty():
		page.add_child(_para("None. Whatever you found before it came no longer matters."))
	for ev in d["evidence"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(Art.icon_rect(Defs.EVIDENCE[ev]["icon"], 32))
		row.add_child(Art.label(Defs.EVIDENCE[ev]["name"], 19, Art.INK, Art.font_heading))
		if Defs.EVIDENCE[ev]["hidden"]:
			row.add_child(Art.label("(not listed in the journal until found)", 14, Color(0.35, 0.27, 0.2), Art.font_italic))
		page.add_child(row)
	_section("Behaviour")
	page.add_child(_para(d["behaviour"]))
	_section("Hunting")
	page.add_child(_para(d["hunting"]))
	page.add_child(_para(_derived_hunt_facts(d), 16, true))
	_section("Strengths")
	_bullets(d["strengths"])
	_section("Weaknesses")
	_bullets(d["weaknesses"])
	_section("How to vanquish it")
	var steps: Array = d["vanquish"]
	for i in steps.size():
		page.add_child(_para("%d.  %s" % [i + 1, steps[i]], 18))

## Facts computed from the same numbers the game uses.
func _derived_hunt_facts(d: Dictionary) -> String:
	var spd: float = d["hunt_speed"]
	var speed_text := "slower than a walking investigator" if spd < Player.WALK_SPEED else ("faster than walking but slower than sprinting" if spd < Player.SPRINT_SPEED else "faster than a sprint")
	var lead := "Hunts at a pace %s." % speed_text
	if d["name"] == "Werewolf":
		lead = "Starts a hunt %s and speeds up while it sees you." % speed_text
	var how_often := "often" if float(d["hunt_cooldown"]) <= 22.0 else ("regularly" if float(d["hunt_cooldown"]) <= 28.0 else "rarely")
	if d["kind"] == "harbinger":
		how_often = "relentlessly"
	return "%s Hunts %s, for about %d seconds at a time." % [lead, how_often, int(d["hunt_duration"])]

func _show_equipment() -> void:
	page.add_child(Art.heading("Equipment", 40))
	page.add_child(_para("Every hunter carries the full kit from the start. House resources must be found.", 18, true))
	_section("Your kit")
	for id in Defs.BASE_LOADOUT:
		_equip_row(id)
	_section("Found in the house")
	for id in Defs.RESOURCE_ORDER:
		_equip_row(id)

func _equip_row(id: String) -> void:
	var e: Dictionary = Defs.EQUIPMENT[id]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(Art.icon_rect(e["icon"], 40))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", -2)
	v.add_child(Art.label(e["name"], 19, Art.INK, Art.font_heading))
	v.add_child(_para(e.get("desc", ""), 16))
	row.add_child(v)
	page.add_child(row)
