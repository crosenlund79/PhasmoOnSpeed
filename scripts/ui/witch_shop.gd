class_name WitchShop
extends PanelContainer
## The Witch's wares: Witch's Needle variants by tier, Renown level and price.
## Buy with Gold Ducats once your Renown allows it; equip any needle you own.

signal changed()

var _list: VBoxContainer
var _balance: Label

func _init() -> void:
	custom_minimum_size = Vector2(760, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Art.heading("Old Morwen's Needles", 30)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_balance = Art.label("", 17, Color(0.3, 0.2, 0.08), Art.font_heading)
	_balance.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_balance)
	v.add_child(Art.label("“Every needle points true. The better ones simply point sooner.”", 16, Color(0.35, 0.25, 0.18), Art.font_italic))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	v.add_child(_list)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(foot)
	foot.add_child(Art.label("Esc to leave  ", 14, Color(0.4, 0.3, 0.2), Art.font_italic))
	foot.add_child(Art.button("Leave", func(): visible = false, 180))
	refresh()

func refresh() -> void:
	var p: Dictionary = SaveData.progress()
	var info := Progression.level_info(int(p["renown"]))
	_balance.text = "%d Gold Ducats  ·  %s, Level %d" % [int(p["ducats"]), info["title"], info["level"]]
	for c in _list.get_children():
		c.queue_free()
	for id in Progression.NEEDLE_ORDER:
		_list.add_child(_row(id, p))

func _row(id: String, p: Dictionary) -> Control:
	var n: Dictionary = Progression.NEEDLES[id]
	var tc := Progression.tier_color(n["tier"])
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var equipped: bool = p["needle"] == id
	sb.bg_color = Color(0.3, 0.2, 0.1, 0.22 if equipped else 0.1)
	sb.border_color = tc.darkened(0.25)
	sb.border_width_left = 6
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(8)
	sb.content_margin_left = 14
	box.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	box.add_child(h)
	var icon := Art.icon_rect("icons/eq_emf.png", 44)
	icon.modulate = Color.WHITE.lerp(tc, 0.45)
	h.add_child(icon)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	info.add_child(top)
	top.add_child(Art.label(n["name"], 21, Art.INK, Art.font_heading))
	var tier := Art.label(Progression.tier_name(n["tier"]).to_upper(), 14, tc.darkened(0.35), Art.font_heading)
	tier.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(tier)
	var d := Art.label(n["desc"], 14, Color(0.3, 0.22, 0.15), Art.font_italic)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(330, 0)
	info.add_child(d)
	var req := "Starting needle" if int(n["price"]) == 0 else "Requires %s (Level %d)  ·  %d Ducats" % [Progression.title_for(int(n["level"])), int(n["level"]), int(n["price"])]
	var block := Progression.buy_block(p, id)
	info.add_child(Art.label(req, 14, Art.BLOOD if block in ["level", "ducats"] else Color(0.3, 0.22, 0.15), Art.font_heading))
	var b: Button
	if equipped:
		b = Art.button("Equipped", func(): pass, 150)
		b.disabled = true
	elif id in p["owned"]:
		b = Art.button("Equip", func(): _equip(id), 150)
	else:
		b = Art.button("Buy", func(): _buy(id), 150)
		b.disabled = block != ""
		b.tooltip_text = {"level": "Your Renown is not yet enough.", "ducats": "Not enough Gold Ducats."}.get(block, "")
		if block == "level":
			b.text = "Locked"
	b.custom_minimum_size = Vector2(150, 44)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	return box

func _buy(id: String) -> void:
	if Progression.buy(SaveData.progress(), id):
		Progression.equip(SaveData.progress(), id)
		SaveData.save()
		Sfx.play("needle_tap", -6.0)
		refresh()
		changed.emit()

func _equip(id: String) -> void:
	if Progression.equip(SaveData.progress(), id):
		SaveData.save()
		refresh()
		changed.emit()
