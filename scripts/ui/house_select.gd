extends Screen
## Choose one of the five houses. The entity is always unknown.

func _ready() -> void:
	add_backdrop("ui/menu_background.png", 0.55)
	var v := centered_column(1460, 30)
	var t := Art.heading("Choose a House", 46, Color(0.93, 0.85, 0.65))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_outline_color", Color.BLACK)
	t.add_theme_constant_override("outline_size", 8)
	v.add_child(t)
	var sub := Art.label("Each visit, something different waits inside. Or so you hope.", 19, Color(0.82, 0.78, 0.7), Art.font_italic)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	_build_difficulty(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var first: Button = null
	for id in Game.house_ids:
		var h: Dictionary = Game.house(id)
		var card := parchment_box(row, Vector2(280, 0))
		var title := Art.heading(h["name"], 22)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(title)
		var plan := FloorplanThumb.new()
		plan.house = HouseMap.from_data(h)
		plan.custom_minimum_size = Vector2(250, 190)
		card.add_child(plan)
		var blurb := Art.label(h["blurb"], 15, Color(0.25, 0.18, 0.12), Art.font_italic)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.custom_minimum_size = Vector2(250, 60)
		card.add_child(blurb)
		var rec: Dictionary = SaveData.house_record(id, _difficulty())
		# No exact occupant count: a shapeshifter posing as one more person
		# must never be exposed by the menu.
		var info := "Rooms: %d  ·  Floors: %d" % [plan.house.rooms.size(), plan.house.floors().size()]
		card.add_child(Art.label(info, 14, Color(0.3, 0.22, 0.15)))
		var pb := ("Best: —" if _difficulty() == "normal" else _difficulty().capitalize() + " best: —") if rec["best_time"] <= 0.0 else "Best: %s  ·  %d pts" % [Journal.format_time_precise(rec["best_time"]), int(rec["best_score"])]
		card.add_child(Art.label(pb, 15, Color(0.3, 0.22, 0.15), Art.font_heading))
		card.add_child(Art.label("Entity: unknown", 15, Art.BLOOD, Art.font_heading))
		var hid: String = id
		var b := Art.button("Enter", func(): Game.start_run(hid), 240)
		card.add_child(b)
		if first == null:
			first = b
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(bottom)
	bottom.add_child(Art.button("Random House", func(): Game.start_run(Game.house_ids[randi() % Game.house_ids.size()]), 260))
	back_button(bottom)
	if first:
		first.grab_focus()

func _difficulty() -> String:
	return str(SaveData.settings().get("difficulty", "normal"))

## Beginner / Normal / Nightmare, chosen before entering. Remembered between visits.
func _build_difficulty(v: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var group := ButtonGroup.new()
	var desc := Art.label("", 16, Color(0.82, 0.78, 0.7), Art.font_italic)
	for d in [["beginner", "Beginner"], ["normal", "Normal"], ["nightmare", "Nightmare"]]:
		var did: String = d[0]
		var b := Art.button(d[1], func():
			SaveData.set_setting("difficulty", did)
			Game.goto_house_select(), 200)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = _difficulty() == did
		if did == "nightmare":
			b.add_theme_color_override("font_color", Color(0.75, 0.1, 0.07))
			b.add_theme_color_override("font_pressed_color", Color(0.85, 0.12, 0.08))
		row.add_child(b)
	desc.text = {
		"beginner": "A guided first investigation: tips as you go, and gentler hunts. Records kept separately.",
		"normal": "The suspect panel shows each entity's evidence and what it takes to vanquish it.",
		"nightmare": "The suspect panel shows only a name and a description. Terrified occupants, vermin underfoot, blood and noises in the walls. Records kept separately.",
	}.get(_difficulty(), "")
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)


## Inked miniature floorplan drawn from the house data.
class FloorplanThumb extends Control:
	var house: HouseMap

	func _draw() -> void:
		if house == null:
			return
		var s := minf(size.x / house.w, size.y / house.h)
		var off := (size - Vector2(house.w, house.h) * s) * 0.5
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.15, 0.1, 0.12))
		for y in house.h:
			for x in house.w:
				var v := house.at(Vector2i(x, y))
				var r := Rect2(off + Vector2(x, y) * s, Vector2(s, s))
				if v == HouseMap.WALL:
					draw_rect(r, Color(0.1, 0.08, 0.07))
				elif v == HouseMap.DOOR:
					draw_rect(r, Color(0.6, 0.45, 0.25))
				elif v >= 0:
					var room: Dictionary = house.rooms[v]
					var c := Color(0.55, 0.6, 0.45, 0.5) if room["outdoor"] else Color(0.72, 0.62, 0.45, 0.55)
					if room["lit"] and not room["outdoor"]:
						c = Color(0.85, 0.7, 0.42, 0.65)
					draw_rect(r, c)
		for f in house.furniture:
			if f["def"].get("solid", false):
				var fr: Rect2 = f["rect"]
				draw_rect(Rect2(off + fr.position / Defs.CELL * s, fr.size / Defs.CELL * s).grow(-0.5), Color(0.3, 0.22, 0.15, 0.6))
