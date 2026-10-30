extends Control
## VANQUISHED! / PERISHED! results: score breakdown, time and records, taunts and
## ranking, over a looping 4× replay of the actual run.

var result := {}
var summary := {}
var replay_player: ReplayPlayer
var _scream_t := 2.0
var _dark: ColorRect
var _online_label: Label

func setup(p_result: Dictionary) -> void:
	result = p_result
	summary = result["summary"]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var won: bool = summary["vanquished"]
	# Replay world, rendered behind the UI.
	replay_player = ReplayPlayer.new()
	replay_player.setup(result["replay"])
	# Keep the replayed investigator centred in the area left of the results panel.
	replay_player.camera_offset = Vector2(get_viewport_rect().size.x * (0.5 - 0.5 * 0.62) / replay_player.zoom, 0.0)
	var world_holder := Node2D.new()
	add_child(world_holder)
	world_holder.add_child(replay_player)
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(root)
	_dark = ColorRect.new()
	_dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dark.color = Color(0.0, 0.0, 0.0, 0.25) if won else Color(0.12, 0.0, 0.0, 0.0)
	_dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_dark)
	var vig := TextureRect.new()
	vig.texture = Art.tex("ui/vignette.png")
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.modulate = Color(1, 1, 1, 0.9)
	root.add_child(vig)
	if not won:
		# The house darkens; screams surround the investigator.
		create_tween().tween_property(_dark, "color", Color(0.1, 0.0, 0.0, 0.55), 3.0)
		Sfx.play("results_lose", 0.0)
	else:
		Sfx.play("results_win", 0.0)
	_build_panel(root, won)

func _build_panel(root: Control, won: bool) -> void:
	var banner := TextureRect.new()
	banner.texture = Art.tex("ui/banner_vanquished.png" if won else "ui/banner_perished.png")
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	banner.anchor_left = 0.0
	banner.anchor_right = 0.62
	banner.offset_top = 14
	banner.offset_bottom = 190
	root.add_child(banner)
	banner.pivot_offset = Vector2(500, 90)
	banner.scale = Vector2(1.25, 1.25)
	banner.modulate.a = 0.0
	var tw := banner.create_tween().set_parallel(true)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(banner, "modulate:a", 1.0, 0.4)
	var reveal := Art.label(_reveal_text(), 24, Color(0.93, 0.87, 0.72), Art.font_italic)
	reveal.anchor_right = 0.62
	reveal.offset_top = 188
	reveal.offset_bottom = 222
	reveal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reveal.add_theme_color_override("font_outline_color", Color.BLACK)
	reveal.add_theme_constant_override("outline_size", 8)
	root.add_child(reveal)
	var taunt := Art.label("“" + _taunt() + "”", 21, Color(0.86, 0.8, 0.66), Art.font_italic)
	taunt.anchor_right = 0.62
	taunt.anchor_top = 1.0
	taunt.anchor_bottom = 1.0
	taunt.offset_left = 40
	taunt.offset_right = -20
	taunt.offset_top = -110
	taunt.offset_bottom = -30
	taunt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	taunt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	taunt.add_theme_color_override("font_outline_color", Color.BLACK)
	taunt.add_theme_constant_override("outline_size", 7)
	root.add_child(taunt)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.62
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 0
	panel.offset_right = -18
	panel.offset_top = 18
	panel.offset_bottom = -18
	root.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	var recs: Dictionary = result["records"]
	var time_row := HBoxContainer.new()
	v.add_child(time_row)
	time_row.add_child(Art.icon_rect("icons/ui_clock.png", 34))
	var tl := Art.label(Journal.format_time_precise(summary["time"]), 40, Art.INK, Art.font_heading)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_row.add_child(tl)
	if won and recs.get("new_best_time", false):
		time_row.add_child(Art.label("NEW RECORD", 20, Art.BLOOD, Art.font_heading))
	var prev_t: float = recs.get("prev_best_time", 0.0)
	var pb_line := "%s%s  ·  previous best %s" % [summary["house_name"], "" if summary.get("difficulty", "normal") == "normal" else "  ·  " + str(summary["difficulty"]).to_upper(), Journal.format_time_precise(prev_t) if prev_t > 0.0 else "—"]
	v.add_child(Art.label(pb_line, 15, Color(0.3, 0.22, 0.15), Art.font_italic))
	v.add_child(_rule())
	var score_row := HBoxContainer.new()
	v.add_child(score_row)
	score_row.add_child(Art.icon_rect("icons/ui_trophy.png", 34))
	var sl := Art.label("%d" % summary["score"], 46, Art.INK, Art.font_heading)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_row.add_child(sl)
	score_row.add_child(Art.label("points", 18, Color(0.3, 0.22, 0.15), Art.font_heading))
	if won and recs.get("new_best_score", false):
		v.add_child(Art.label("New personal best score for this house!", 16, Art.BLOOD, Art.font_heading))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	v.add_child(grid)
	for line in summary["score_lines"]:
		var name_l := Art.label(str(line[0]), 17, Art.INK)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_l)
		var val := int(line[1])
		var val_l := Art.label(("+%d" % val) if val > 0 else str(val), 17, Art.BLOOD if val < 0 else Art.INK, Art.font_heading)
		val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(val_l)
	v.add_child(Art.label("Score rules v" + summary["rules_version"], 12, Color(0.4, 0.32, 0.24)))
	v.add_child(_rule())
	v.add_child(Art.label("Journal", 20, Art.INK, Art.font_heading))
	var any := false
	for e in summary["evidence"]:
		any = true
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var ic := Art.icon_rect(Defs.EVIDENCE[e["id"]]["icon"], 24)
		h.add_child(ic)
		var txt := "%s  —  %s · %s" % [Defs.evidence_name(e["id"]), Journal.format_time(e["time"]), e["room_name"]]
		var el := Art.label(txt, 15, Art.INK if not e["void"] else Color(0.45, 0.4, 0.36))
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		el.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(el)
		if e["void"]:
			h.modulate.a = 0.6
		v.add_child(h)
	if not any:
		v.add_child(Art.label("No evidence recorded.", 15, Color(0.35, 0.27, 0.2), Art.font_italic))
	var facts := "Wounds %d  ·  Hunts %d  ·  Wrong attempts %d" % [summary["wounds"], summary["hunts"], summary["incorrect_attempts"]]
	v.add_child(Art.label(facts, 15, Color(0.3, 0.22, 0.15)))
	v.add_child(_rule())
	if won:
		var rank := Rankings.rank_for(summary["score"])
		var rl := Art.label("Rank #%d among the Legendary Hunters" % rank, 18, Art.INK, Art.font_heading)
		v.add_child(rl)
		var rival := Rankings.next_rival(summary["score"])
		var rtext := "You stand above every legend. For now." if rival.is_empty() else "Next: %s — %d pts" % [rival["name"], rival["score"]]
		v.add_child(Art.label(rtext, 15, Color(0.3, 0.22, 0.15), Art.font_italic))
		v.add_child(Art.label("(The legendary hunters are fictional.)", 12, Color(0.4, 0.32, 0.24)))
	_online_label = Art.label(Online.last_status, 13, Color(0.35, 0.28, 0.22), Art.font_italic)
	_online_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_online_label)
	Online.submit_finished.connect(func(_ok, msg): _online_label.text = msg)
	var buttons := GridContainer.new()
	buttons.columns = 2
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 8)
	v.add_child(buttons)
	var again := Art.button("Hunt Again", func(): Game.start_setup(preload("res://scripts/ui/house_select.gd").saved_setup()), 230)
	buttons.add_child(again)
	buttons.add_child(Art.button("New Setup", func(): Game.goto_house_select(), 230))
	buttons.add_child(Art.button("Rankings", func(): Game.goto_rankings(), 230))
	buttons.add_child(Art.button("Main Menu", func(): Game.goto_menu(), 230))
	again.grab_focus()

func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.2, 0.14, 0.08, 0.5)
	r.custom_minimum_size = Vector2(0, 2)
	return r

func _reveal_text() -> String:
	var orig: String = summary["original_creature"]
	var fin: String = summary["creature"]
	var name := Defs.creature_name(fin)
	var verb := "vanquished" if summary["vanquished"] else "claimed you"
	if summary["harbinger"]:
		return "The Harbinger %s — it replaced %s." % ["was banished" if summary["vanquished"] else "claimed you", _article(Defs.creature_name(orig))]
	if summary["vanquished"]:
		return "%s %s in %s." % [_cap_article(name), verb, summary["house_name"]]
	return "It was %s. It %s in %s." % [_article(name), verb, summary["house_name"]]

func _article(n: String) -> String:
	return n if n.begins_with("The ") else "a " + n

func _cap_article(n: String) -> String:
	return n if n.begins_with("The ") else "A " + n

func _taunt() -> String:
	var r := RandomNumberGenerator.new()
	r.seed = int(summary["seed"])
	var lines: Array
	var orig: String = summary["original_creature"]
	if summary["vanquished"]:
		if summary["blind"]:
			lines = ["Not a single clue. Not a single doubt. The house will tell stories about you.",
				"Pure audacity. Somewhere, a scholar of the occult weeps."]
		elif summary["harbinger"]:
			lines = ["You summoned the end of all things and then asked it, politely, to leave. It worked.",
				"Most people learn from their mistakes. You banished yours."]
		elif summary["time"] < 90.0:
			lines = ["Was that a haunting or a social call?", "The ghost hadn't even finished unpacking."]
		elif summary["wounds"] > 0:
			lines = ["Bleeding, but victorious. The laundress will not be.", "Half alive counts as alive. Technically."]
		else:
			lines = ["The occupants may now resume their perfectly ordinary lives.", "Another house, another soul sent packing.",
				"Neat, methodical, and only slightly screaming."]
	else:
		if summary["harbinger"]:
			lines = ["You were warned. Repeatedly. By the house itself.", "The Harbinger thanks you for your enthusiasm."]
		elif orig in ["vampire", "werewolf", "shapeshifter"] and summary["evidence_ids"].is_empty():
			lines = ["Whisper Box? Witch's Needle? It was never a ghost. It found that very funny.",
				"You brought ghost-hunting gear to something with teeth."]
		else:
			lines = ["Your journal will make a fine ghost story. Narrated by you, from the other side.",
				"The occupants send their regards. From the carriage.", "On the bright side, you can haunt this place now."]
	return lines[r.randi_range(0, lines.size() - 1)]

func _process(delta: float) -> void:
	if not summary.get("vanquished", true):
		_scream_t -= delta
		if _scream_t <= 0.0:
			_scream_t = randf_range(3.5, 7.0)
			Sfx.play("scream_%d" % randi_range(1, 3), randf_range(-14.0, -6.0), randf_range(0.85, 1.15), 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Game.goto_menu()
		elif event.keycode == KEY_R:
			Game.start_setup(preload("res://scripts/ui/house_select.gd").saved_setup())
