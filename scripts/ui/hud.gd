extends CanvasLayer
## Gameplay HUD: the compact automatic journal on the right (timer, survival,
## discoveries, unconfirmed evidence), the hotbar, prompts, notifications,
## dramatic messages, hunt/wound overlays and the pause / controls panels.

const JOURNAL_WIDTH := 288.0
const INK := Color(0.09, 0.07, 0.06)
const INK_SOFT := Color(0.27, 0.2, 0.14)
const BONE := Color(0.93, 0.88, 0.76)

var run: Run
var timer_label: Label
var pb_label: Label
var hearts: Array = []
var dread_fill: ColorRect
var entries_box: VBoxContainer
var entries_scroll: ScrollContainer
var void_label: Label
var unconfirmed_label: Label
var unconfirmed_title: Label
var suspect_label: Label
var location_label: Label
var hotbar: HBoxContainer
var stamina_fill: ColorRect
var readout_label: Label
var prompt_label: Label
var hold_bar: ProgressBar
var toast_box: VBoxContainer
var big_title: Label
var big_sub: Label
var big_box: VBoxContainer
var hunt_overlay: TextureRect
var wound_overlay: ColorRect
var pause_panel: Control
var help_panel: Control
var _hunting := false
var _t := 0.0
var _shake := 0.0
var _toast_recent := {}
var _slot_nodes: Array = []
var _entry_count := 0

func setup(p_run: Run) -> void:
	run = p_run
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_overlays(root)
	_build_journal(root)
	_build_hotbar(root)
	_build_toasts(root)
	_build_big_message(root)
	_build_pause(root)
	_build_help(root)
	run.equipment.changed.connect(_rebuild_hotbar)
	_rebuild_hotbar()
	refresh()

# --- Construction ------------------------------------------------------------------------

func _build_overlays(root: Control) -> void:
	hunt_overlay = TextureRect.new()
	hunt_overlay.texture = Art.tex("ui/vignette.png")
	hunt_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	hunt_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hunt_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	hunt_overlay.modulate = Color(0.7, 0.0, 0.0, 0.0)
	hunt_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hunt_overlay)
	var vig := TextureRect.new()
	vig.texture = Art.tex("ui/vignette.png")
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.modulate = Color(0, 0, 0, 0.55)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vig)
	wound_overlay = ColorRect.new()
	wound_overlay.color = Color(0.6, 0.0, 0.0, 0.0)
	wound_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	wound_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(wound_overlay)

func _small(text: String, size: int, color: Color = INK, font: Font = null) -> Label:
	var l := Art.label(text, size, color, font)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.2, 0.14, 0.08, 0.55)
	r.custom_minimum_size = Vector2(0, 2)
	return r

func _build_journal(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Art.parchment_panel())
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -JOURNAL_WIDTH - 10
	panel.offset_right = -10
	panel.offset_top = 10
	panel.offset_bottom = -10
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	panel.add_child(v)
	# Timer + survival.
	var top := HBoxContainer.new()
	v.add_child(top)
	top.add_child(Art.icon_rect("icons/ui_clock.png", 26))
	timer_label = Art.label("00:00.00", 30, INK, Art.font_heading)
	timer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(timer_label)
	for i in 2:
		var h := Art.icon_rect("icons/ui_heart.png", 26)
		top.add_child(h)
		hearts.append(h)
	var rec: Dictionary = SaveData.house_record(run.house_id)
	var pb_text := "No record yet" if rec["best_time"] <= 0.0 else "Best  " + Journal.format_time_precise(rec["best_time"])
	pb_label = _small(pb_text + "  ·  " + run.map.name, 13, INK_SOFT, Art.font_italic)
	v.add_child(pb_label)
	var dread_row := HBoxContainer.new()
	v.add_child(dread_row)
	dread_row.add_child(Art.label("Dread", 13, INK_SOFT, Art.font_heading))
	var bar := ColorRect.new()
	bar.color = Color(0.2, 0.15, 0.1, 0.3)
	bar.custom_minimum_size = Vector2(0, 7)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dread_row.add_child(bar)
	dread_fill = ColorRect.new()
	dread_fill.color = Color(0.5, 0.1, 0.07)
	dread_fill.size = Vector2(0, 7)
	bar.add_child(dread_fill)
	v.add_child(_rule())
	var jt := Art.label("Journal", 20, INK, Art.font_heading)
	v.add_child(jt)
	entries_scroll = ScrollContainer.new()
	entries_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entries_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(entries_scroll)
	entries_box = VBoxContainer.new()
	entries_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entries_box.add_theme_constant_override("separation", 4)
	entries_scroll.add_child(entries_box)
	var empty := _small("Nothing confirmed yet. Observe, measure, listen.", 14, INK_SOFT, Art.font_italic)
	empty.name = "Empty"
	entries_box.add_child(empty)
	void_label = _small("", 13, Color(0.35, 0.28, 0.25), Art.font_italic)
	void_label.visible = false
	v.add_child(void_label)
	v.add_child(_rule())
	unconfirmed_title = Art.label("Unconfirmed", 14, INK_SOFT, Art.font_heading)
	v.add_child(unconfirmed_title)
	unconfirmed_label = _small("", 15, INK)
	v.add_child(unconfirmed_label)
	v.add_child(_rule())
	suspect_label = _small("", 14, INK)
	v.add_child(suspect_label)
	location_label = _small("", 14, INK_SOFT, Art.font_italic)
	v.add_child(location_label)

func _build_hotbar(root: Control) -> void:
	var holder := VBoxContainer.new()
	holder.anchor_left = 0.0
	holder.anchor_right = 1.0
	holder.anchor_top = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_right = -JOURNAL_WIDTH - 20
	holder.offset_top = -168
	holder.offset_bottom = -10
	holder.alignment = BoxContainer.ALIGNMENT_END
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_constant_override("separation", 3)
	root.add_child(holder)
	prompt_label = Art.label("", 19, Color(1.0, 0.87, 0.55), Art.font_heading)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt_label.add_theme_constant_override("outline_size", 6)
	holder.add_child(prompt_label)
	hold_bar = ProgressBar.new()
	hold_bar.custom_minimum_size = Vector2(220, 6)
	hold_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hold_bar.show_percentage = false
	hold_bar.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Art.GOLD
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	hold_bar.add_theme_stylebox_override("fill", fill)
	hold_bar.add_theme_stylebox_override("background", bg)
	hold_bar.modulate.a = 0.0
	holder.add_child(hold_bar)
	readout_label = Art.label("", 17, BONE)
	readout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	readout_label.add_theme_color_override("font_outline_color", Color.BLACK)
	readout_label.add_theme_constant_override("outline_size", 5)
	holder.add_child(readout_label)
	var bar_panel := PanelContainer.new()
	bar_panel.add_theme_stylebox_override("panel", Art.dark_panel())
	bar_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.add_child(bar_panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 3)
	bar_panel.add_child(inner)
	hotbar = HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 3)
	inner.add_child(hotbar)
	var sbar := ColorRect.new()
	sbar.color = Color(0.1, 0.1, 0.1, 0.8)
	sbar.custom_minimum_size = Vector2(0, 4)
	inner.add_child(sbar)
	stamina_fill = ColorRect.new()
	stamina_fill.color = Color(0.62, 0.72, 0.78)
	stamina_fill.size = Vector2(0, 4)
	sbar.add_child(stamina_fill)

func _rebuild_hotbar() -> void:
	for c in hotbar.get_children():
		c.queue_free()
	_slot_nodes.clear()
	var eq: EquipmentController = run.equipment
	for i in eq.slots.size():
		var id: String = eq.slots[i]
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(46, 46)
		var frame := TextureRect.new()
		frame.texture = Art.tex("ui/slot_selected.png" if i == eq.selected else "ui/slot.png")
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.add_child(frame)
		var icon := Art.icon_rect(Defs.EQUIPMENT[id]["icon"], 34)
		icon.position = Vector2(6, 6)
		icon.size = Vector2(34, 34)
		if Defs.EQUIPMENT[id].get("resource", false):
			icon.modulate = Color(1.0, 0.95, 0.8)
		slot.add_child(icon)
		var key := Art.label(str(i + 1) if i < 9 else "Q", 12, Color(0.95, 0.85, 0.6), Art.font_heading)
		key.position = Vector2(3, 0)
		key.add_theme_color_override("font_outline_color", Color.BLACK)
		key.add_theme_constant_override("outline_size", 4)
		slot.add_child(key)
		var ch := eq.charge_text(id)
		if ch != "":
			var cl := Art.label(ch, 12, BONE)
			cl.position = Vector2(26, 29)
			cl.add_theme_color_override("font_outline_color", Color.BLACK)
			cl.add_theme_constant_override("outline_size", 4)
			slot.add_child(cl)
		if i == eq.selected:
			slot.scale = Vector2(1.0, 1.0)
		hotbar.add_child(slot)
		_slot_nodes.append(slot)

func _build_toasts(root: Control) -> void:
	toast_box = VBoxContainer.new()
	toast_box.anchor_left = 0.0
	toast_box.anchor_right = 1.0
	toast_box.offset_right = -JOURNAL_WIDTH - 20
	toast_box.offset_top = 14
	toast_box.offset_bottom = 200
	toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_theme_constant_override("separation", 4)
	root.add_child(toast_box)

func _build_big_message(root: Control) -> void:
	big_box = VBoxContainer.new()
	big_box.anchor_left = 0.0
	big_box.anchor_right = 1.0
	big_box.anchor_top = 0.28
	big_box.anchor_bottom = 0.28
	big_box.offset_right = -JOURNAL_WIDTH - 20
	big_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big_box.modulate.a = 0.0
	root.add_child(big_box)
	big_title = Art.label("", 58, Art.GOLD, Art.font_heading)
	big_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_title.add_theme_color_override("font_outline_color", Color.BLACK)
	big_title.add_theme_constant_override("outline_size", 12)
	big_box.add_child(big_title)
	big_sub = Art.label("", 22, BONE, Art.font_italic)
	big_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	big_sub.add_theme_color_override("font_outline_color", Color.BLACK)
	big_sub.add_theme_constant_override("outline_size", 8)
	big_box.add_child(big_sub)

func _centered_panel(root: Control, width: float) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.visible = false
	root.add_child(cc)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.show_behind_parent = true
	cc.add_child(dim)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(width, 0)
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	return v

func _build_pause(root: Control) -> void:
	var v := _centered_panel(root, 380)
	pause_panel = v.get_parent().get_parent()
	var t := Art.heading("Paused", 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(Art.button("Resume", func(): toggle_pause()))
	v.add_child(Art.button("Restart run", func(): run.set_paused(false); run.restart()))
	v.add_child(Art.button("Controls", func(): help_panel.visible = true))
	v.add_child(Art.button("Abandon to menu", func(): run.set_paused(false); Sfx.stop_all_loops(); Game.goto_menu()))

func _build_help(root: Control) -> void:
	var v := _centered_panel(root, 560)
	help_panel = v.get_parent().get_parent()
	help_panel.z_index = 5
	var t := Art.heading("Controls", 34)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	v.add_child(grid)
	for row in Controls.HELP:
		grid.add_child(Art.label(row[0], 18, INK, Art.font_heading))
		grid.add_child(Art.label(row[1], 18, INK))
	var tip := _small("Evidence is recorded automatically. You may attempt to vanquish at any time — but recklessness has consequences.", 15, INK_SOFT, Art.font_italic)
	v.add_child(tip)
	v.add_child(Art.button("Close", func(): help_panel.visible = false))

# --- Updates ------------------------------------------------------------------------------

func on_discovered(entry: Dictionary) -> void:
	var empty := entries_box.get_node_or_null("Empty")
	if empty:
		empty.queue_free()
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.55, 0.42, 0.22, 0.16)
	sb.border_color = Art.GOLD
	sb.border_width_left = 3
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 6
	sb.content_margin_right = 4
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	row.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	row.add_child(h)
	h.add_child(Art.icon_rect(entry["icon"], 30))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(Art.label(entry["name"], 17, INK, Art.font_heading))
	v.add_child(Art.label("%s · %s" % [Journal.format_time(entry["time"]), entry["room_name"]], 14, INK_SOFT))
	entries_box.add_child(row)
	_entry_count += 1
	row.modulate = Color(1.6, 1.3, 0.8)
	create_tween().tween_property(row, "modulate", Color.WHITE, 1.2)
	# Keep the newest discovery visible.
	await get_tree().process_frame
	await get_tree().process_frame
	entries_scroll.scroll_vertical = int(entries_scroll.get_v_scroll_bar().max_value)
	toast("Recorded: %s — %s" % [entry["name"], entry["room_name"]], entry["icon"], true)
	refresh()

func refresh() -> void:
	var j: Journal = run.journal
	var harb: bool = run.creature != null and run.creature.type_id == "harbinger"
	var voids := j.void_entries()
	void_label.visible = not voids.is_empty()
	if not voids.is_empty():
		void_label.text = "Prior presence — %d record%s disregarded." % [voids.size(), "" if voids.size() == 1 else "s"]
		for row in entries_box.get_children():
			if row is PanelContainer and row.get_meta("void", false) == false:
				row.set_meta("void", true)
				row.modulate = Color(1, 1, 1, 0.35)
	if harb:
		unconfirmed_title.text = "The Harbinger"
		var lit: int = run.sigils.filter(func(s): return s["lit"]).size()
		unconfirmed_label.text = "No earthly evidence remains. Sigil candles lit: %d / %d" % [lit, run.sigils.size()]
		suspect_label.text = "Light the sigils, then perform the Final Rite beside it (hold V)."
	else:
		unconfirmed_title.text = "Unconfirmed"
		var names: Array = j.undiscovered_conventional().map(func(id): return Defs.EVIDENCE[id]["short"])
		unconfirmed_label.text = " · ".join(names) if not names.is_empty() else "—"
		if run.suspect == "":
			suspect_label.text = "Suspect: none  ·  Tab to choose"
		else:
			var d: Dictionary = Defs.CREATURES[run.suspect]
			suspect_label.text = "Suspect: %s  ·  %s" % [d["name"], "salt + rite here (V)" if run.suspect == "shade" else "book + rite here (V)"]

func _process(delta: float) -> void:
	_t += delta
	if run == null:
		return
	timer_label.text = Journal.format_time_precise(run.elapsed)
	var p: Player = run.player
	hearts[0].texture = Art.tex("icons/ui_heart_wounded.png" if p.wounds >= 2 else "icons/ui_heart.png")
	hearts[1].texture = Art.tex("icons/ui_heart_wounded.png" if p.wounds >= 1 else "icons/ui_heart.png")
	hearts[1].modulate.a = 0.45 if p.wounds >= 1 else 1.0
	var dw: float = dread_fill.get_parent().size.x
	dread_fill.size = Vector2(dw * clampf(run.threat / 100.0, 0.0, 1.0), 7)
	var sw: float = stamina_fill.get_parent().size.x
	stamina_fill.size = Vector2(sw * p.stamina, 4)
	stamina_fill.color = Color(0.62, 0.72, 0.78) if p.stamina > 0.25 else Color(0.8, 0.4, 0.3)
	location_label.text = "◆ " + run.map.room_name(p.room_id)
	var eq: EquipmentController = run.equipment
	readout_label.text = eq.readout
	readout_label.add_theme_color_override("font_color", eq.readout_color)
	prompt_label.text = eq.prompt
	var hp := eq.hold_progress()
	hold_bar.value = hp
	hold_bar.modulate.a = 1.0 if hp > 0.0 else 0.0
	if run.harbinger_summoned:
		refresh()
	var target_hunt := 0.0
	if _hunting:
		target_hunt = 0.45 + 0.2 * sin(_t * 6.0)
	hunt_overlay.modulate.a = move_toward(hunt_overlay.modulate.a, target_hunt, delta * 2.0)
	wound_overlay.color.a = move_toward(wound_overlay.color.a, 0.18 if p.wounds >= 1 and p.invuln <= 0.0 else 0.0, delta * 0.8)
	if _shake > 0.0:
		_shake -= delta
		run.camera.offset = Vector2(145.0 / run.CAMERA_ZOOM, 0) + Vector2(randf_range(-6, 6), randf_range(-6, 6)) * _shake
	else:
		run.camera.offset = Vector2(145.0 / run.CAMERA_ZOOM, 0)
	for k in _toast_recent.keys():
		_toast_recent[k] -= delta
		if _toast_recent[k] <= 0.0:
			_toast_recent.erase(k)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if help_panel.visible:
			help_panel.visible = false
		else:
			toggle_pause()
	elif event.is_action_pressed("help"):
		help_panel.visible = not help_panel.visible

func toggle_pause() -> void:
	if run.state != "playing":
		return
	pause_panel.visible = not pause_panel.visible
	run.set_paused(pause_panel.visible)

func set_hunting(on: bool) -> void:
	_hunting = on

func wound() -> void:
	wound_overlay.color.a = 0.55
	shake(0.5)

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

## Small unobtrusive notification. Identical messages within 4 s are dropped.
func toast(text: String, icon: String = "", quiet: bool = false) -> void:
	if _toast_recent.has(text):
		return
	_toast_recent[text] = 4.0
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Art.parchment_panel())
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	if icon != "":
		h.add_child(Art.icon_rect(icon, 24))
	h.add_child(Art.label(text, 17, INK))
	toast_box.add_child(p)
	while toast_box.get_child_count() > 3:
		var old := toast_box.get_child(0)
		toast_box.remove_child(old)
		old.queue_free()
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.6 if quiet else 3.4)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)
	if not quiet:
		Sfx.play("ui_hover", -12.0, 0.7, 0.3)

func big_message(title: String, sub: String, color: Color, dur: float) -> void:
	big_title.text = title
	big_title.add_theme_color_override("font_color", color)
	big_sub.text = sub
	var tw := big_box.create_tween()
	big_box.modulate.a = 0.0
	big_box.scale = Vector2.ONE
	tw.tween_property(big_box, "modulate:a", 1.0, 0.35)
	tw.tween_interval(dur)
	tw.tween_property(big_box, "modulate:a", 0.0, 0.8)
