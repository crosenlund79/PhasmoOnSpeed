extends Screen
## The Hunters' Registry: offline rankings against fictional legends on a carved
## guild board (brass nameplates, wax seals for the top three), personal bests per
## house, the competitive record and the optional server-verified leaderboard.

const WOOD_EDGE := Color(0.07, 0.04, 0.02)
const SEALS := [Color(0.86, 0.66, 0.2), Color(0.74, 0.76, 0.8), Color(0.72, 0.44, 0.22)]
const SOFT_INK := Color(0.32, 0.23, 0.15)

var global_box: VBoxContainer

func _ready() -> void:
	add_backdrop("ui/menu_background.png", 0.7)
	var total := fit_width(1440.0, 60.0)
	var v := centered_column(total, 18)
	v.add_theme_constant_override("separation", 8)
	var t := Art.heading("The Hunters' Registry", 46, Color(0.95, 0.86, 0.62))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_outline_color", Color.BLACK)
	t.add_theme_constant_override("outline_size", 9)
	v.add_child(t)
	var info := Progression.level_info(int(SaveData.progress()["renown"]))
	var sub := Art.label("Ledger of the Guild of the Veil  ·  you stand as %s, Level %d" % [info["title"], info["level"]], 18, Color(0.86, 0.8, 0.68), Art.font_italic)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_outline_color", Color.BLACK)
	sub.add_theme_constant_override("outline_size", 6)
	v.add_child(sub)
	var height := fit_height(700.0, 190.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	v.add_child(row)
	var left_w := floorf(total * 0.56)
	row.add_child(_board(left_w, height, info))
	row.add_child(_side(total - left_w - 18.0, height))
	var b := HBoxContainer.new()
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(b)
	back_button(b)

# --- The board of legends ----------------------------------------------------------

func _wood_frame() -> PanelContainer:
	# Dark-stained boards (the houses' own floor art) inside a carved edge.
	var f := WoodFrame.new()
	var sb := StyleBoxTexture.new()
	sb.texture = Art.tex("floors/wood_dark.png")
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.modulate_color = Color(0.5, 0.4, 0.36)
	sb.set_content_margin_all(22)
	sb.content_margin_top = 18
	f.add_theme_stylebox_override("panel", sb)
	return f

func _board(width: float, height: float, info: Dictionary) -> Control:
	var frame := _wood_frame()
	frame.custom_minimum_size = Vector2(width, height)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	frame.add_child(col)
	var plaque := PanelContainer.new()
	plaque.add_theme_stylebox_override("panel", RankPlate.brass_style())
	plaque.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(plaque)
	plaque.add_child(Art.heading("Legendary Hunters", 26, RankPlate.ENGRAVE))
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", Art.parchment_panel())
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sheet)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 5)
	scroll.add_child(list)
	var rec: Dictionary = SaveData.data["records"]
	var rows := Rankings.table(SaveData.settings().get("player_name", "Investigator"), int(rec["best_score"]), float(rec.get("best_score_time", 0.0)), str(rec.get("best_score_house", "")))
	for i in rows.size():
		list.add_child(_entry(i + 1, rows[i], info))
	var foot := "These hunters are fictional; their scores follow the same rules (v%s)." % Scoring.RULES_VERSION
	if int(rec["best_score"]) <= 0:
		foot = "Vanquish something to sign the registry.  " + foot
	var fl := Art.label(foot, 14, SOFT_INK, Art.font_italic)
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(fl)
	return frame

func _entry(rank: int, r: Dictionary, info: Dictionary) -> Control:
	var mine: bool = r["is_player"]
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.55, 0.08, 0.05, 0.16) if mine else Color(0.3, 0.2, 0.1, 0.07 if rank % 2 else 0.0)
	sb.border_color = Art.BLOOD if mine else Color(0, 0, 0, 0)
	sb.set_border_width_all(2 if mine else 0)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(3)
	sb.content_margin_right = 10
	box.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	box.add_child(h)
	var badge := Seal.new()
	badge.rank = rank
	badge.color = SEALS[rank - 1] if rank <= 3 else Color(0, 0, 0, 0)
	badge.custom_minimum_size = Vector2(46, 46)
	h.add_child(badge)
	# The brass nameplate.
	var plate := PanelContainer.new()
	var psb := RankPlate.brass_style(RankPlate.BRASS.lightened(0.08) if rank <= 3 else RankPlate.BRASS.darkened(0.08))
	psb.shadow_size = 3
	psb.set_content_margin_all(4)
	psb.content_margin_left = 12
	psb.content_margin_right = 12
	if mine:
		psb.border_color = Art.BLOOD
	plate.add_theme_stylebox_override("panel", psb)
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plate.tooltip_text = r["note"]
	h.add_child(plate)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", -2)
	plate.add_child(pv)
	var name_row := HBoxContainer.new()
	pv.add_child(name_row)
	var nl := Art.label(r["name"], 21 if rank <= 3 else 19, RankPlate.ENGRAVE, Art.font_heading)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_row.add_child(nl)
	if mine:
		name_row.add_child(Art.label("YOU", 15, Art.BLOOD, Art.font_heading))
	var rt := "%s  ·  %s" % [Journal.format_time_precise(r["time"]), r["house"]] if r["time"] > 0.0 else str(r["house"])
	if mine:
		rt = "%s, Level %d  ·  %s" % [info["title"], info["level"], rt]
	pv.add_child(Art.label(rt, 13, Color(0.24, 0.16, 0.08), Art.font_italic))
	var pts := Art.label("%d" % int(r["score"]), 26 if rank <= 3 else 22, Art.BLOOD if mine else Art.INK, Art.font_numeric)
	pts.custom_minimum_size = Vector2(92, 0)
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pts.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(pts)
	return box

# --- Your ledger, competitive record and the global board -----------------------------

func _side(width: float, height: float) -> Control:
	var frame := _wood_frame()
	frame.custom_minimum_size = Vector2(width, height)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	scroll.add_child(col)
	var plate := RankPlate.new()
	plate.custom_minimum_size = Vector2(0, 0)
	col.add_child(plate)
	var pbs := _sheet(col, "Your Records")
	for id in Game.house_ids:
		var hr: Dictionary = SaveData.house_record(id)
		var line := HBoxContainer.new()
		pbs.add_child(line)
		var hn := Art.label(Game.house(id)["name"], 16, Art.INK, Art.font_heading)
		hn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(hn)
		line.add_child(Art.label("%s  ·  %s pts  ·  %d/%d won" % [Journal.format_time_precise(hr["best_time"]) if hr["best_time"] > 0.0 else "—",
			str(hr["best_score"]) if hr["best_score"] > 0 else "—", int(hr["wins"]), int(hr["runs"])], 15, SOFT_INK))
		for diff in Defs.DIFFICULTIES.filter(func(d): return d != "normal"):
			var nr: Dictionary = SaveData.house_record(id, diff)
			if int(nr["runs"]) > 0:
				pbs.add_child(Art.label("      " + Defs.difficulty_name(diff) + " — %s · %s pts · %d/%d won" % [Journal.format_time_precise(nr["best_time"]) if nr["best_time"] > 0.0 else "—",
				str(nr["best_score"]) if nr["best_score"] > 0 else "—", int(nr["wins"]), int(nr["runs"])], 14, Art.BLOOD if Defs.rules(diff) == "nightmare" else Color(0.25, 0.35, 0.2)))
	# Competitive results are kept apart from solo rankings and legends.
	var mp: Dictionary = SaveData.data.get("mp", {})
	var comp := _sheet(col, "Competitive (local record)")
	if int(mp.get("matches", 0)) == 0:
		comp.add_child(Art.label("No competitive matches yet. Rules %s." % MpScoring.RULES_VERSION, 15, SOFT_INK, Art.font_italic))
	else:
		_wrap(comp, "Matches %d  ·  Wins %d  ·  Vanquishes %d  ·  Best %d pts  ·  Nightmare best %d" % [int(mp["matches"]), int(mp["wins"]), int(mp["vanquishes"]), int(mp["best_score"]), int(mp.get("nightmare_best_score", 0))], 15, Art.INK)
		_wrap(comp, "Shoves given %d  ·  taken %d  ·  deaths %d" % [int(mp["shoves_given"]), int(mp["shoves_taken"]), int(mp["deaths"])], 14, SOFT_INK)
	global_box = _sheet(col, "Global Leaderboard")
	_wrap(global_box, Online.last_status, 14, SOFT_INK, Art.font_italic)
	if Online.is_configured():
		Online.top_received.connect(_on_global, CONNECT_ONE_SHOT)
		Online.fetch_top(10)
	else:
		_wrap(global_box, "Local records are never presented as a verified global ranking. See docs/LEADERBOARD.md to connect a server.", 14, SOFT_INK)
	return frame

func _sheet(parent: Control, title: String) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Art.parchment_panel())
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	v.add_child(Art.heading(title, 23))
	var rule := ColorRect.new()
	rule.color = Color(0.25, 0.15, 0.08, 0.45)
	rule.custom_minimum_size = Vector2(0, 2)
	v.add_child(rule)
	return v

func _wrap(parent: Control, text: String, size: int, color: Color, font: Font = null) -> Label:
	var l := Art.label(text, size, color, font)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(200, 0)
	parent.add_child(l)
	return l

func _on_global(rows: Array, ok: bool, message: String) -> void:
	_wrap(global_box, message, 14, SOFT_INK, Art.font_italic)
	if not ok:
		return
	for i in rows.size():
		var r: Dictionary = rows[i]
		var line := HBoxContainer.new()
		global_box.add_child(line)
		line.add_child(Art.label("%d." % (i + 1), 16, SEALS[i].darkened(0.3) if i < 3 else Art.INK, Art.font_heading))
		var n := Art.label("  " + str(r.get("name", "?")), 16, Art.INK, Art.font_heading)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(n)
		line.add_child(Art.label("%d pts · %s" % [int(r.get("score", 0)), r.get("house", "")], 15, SOFT_INK))

## Carved board: brass rivets in the corners and a gilt inner line.
class WoodFrame extends PanelContainer:
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		for i in 5:
			draw_rect(r.grow(-i * 1.0), Color(0, 0, 0, 0.75 - i * 0.12), false, 1.0)
		draw_rect(r.grow(-4.0), WOOD_EDGE, false, 2.0)
		draw_rect(r.grow(-9.0), Color(0.62, 0.48, 0.24, 0.5), false, 1.5)
		draw_rect(r.grow(-13.0), Color(0, 0, 0, 0.35), false, 1.0)
		for c in [Vector2(10, 10), Vector2(size.x - 10, 10), Vector2(10, size.y - 10), size - Vector2(10, 10)]:
			draw_circle(c + Vector2(1, 1), 5.0, Color(0, 0, 0, 0.6))
			draw_circle(c, 5.0, Color(0.7, 0.55, 0.28))
			draw_circle(c - Vector2(1.5, 1.5), 1.8, Color(1, 0.9, 0.6, 0.8))

## Rank badge: a wax seal stamped in gold, silver or bronze for the top three,
## otherwise an inked numeral.
class Seal extends Control:
	var rank := 1
	var color := Color(0, 0, 0, 0)
	func _draw() -> void:
		var c := size * 0.5
		var font: Font = Art.font_heading
		if color.a <= 0.0:
			var s := str(rank)
			var fs := 22
			var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(c.x - w * 0.5, c.y + fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.25, 0.17, 0.1))
			return
		var r := minf(size.x, size.y) * 0.46
		# Ribbon tails beneath the seal.
		var ribbon := Color(0.5, 0.06, 0.05)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.6, 0), c + Vector2(-r * 0.15, 0), c + Vector2(-r * 0.4, r * 1.15), c + Vector2(-r * 0.7, r * 0.95)]), ribbon)
		draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.15, 0), c + Vector2(r * 0.6, 0), c + Vector2(r * 0.7, r * 0.95), c + Vector2(r * 0.4, r * 1.15)]), ribbon)
		# The wobbly disc of the seal itself.
		var pts := PackedVector2Array()
		for i in 28:
			var a := TAU * i / 28.0
			pts.append(c + Vector2.from_angle(a) * r * (1.0 + 0.06 * sin(a * 5.0 + rank) + 0.03 * sin(a * 11.0)))
		draw_colored_polygon(pts, color.darkened(0.35))
		draw_circle(c, r * 0.8, color)
		draw_arc(c, r * 0.8, 0.0, TAU, 32, color.darkened(0.45), 1.5, true)
		draw_arc(c, r * 0.62, 0.0, TAU, 32, color.lightened(0.3), 1.0, true)
		draw_circle(c - Vector2(r * 0.3, r * 0.3), r * 0.18, Color(1, 1, 1, 0.25))
		var s := str(rank)
		var fs := 20
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(c.x - w * 0.5 + 1, c.y + fs * 0.36 + 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.35))
		draw_string(font, Vector2(c.x - w * 0.5, c.y + fs * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color.darkened(0.7))
