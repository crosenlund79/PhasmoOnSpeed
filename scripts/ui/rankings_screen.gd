extends Screen
## Offline rankings against fictional legends, personal bests per house, and the
## optional server-verified global leaderboard.

var global_box: VBoxContainer

func _ready() -> void:
	add_backdrop("ui/menu_background.png", 0.6)
	var v := centered_column(1300, 30)
	var t := Art.heading("Rankings", 46, Color(0.93, 0.85, 0.65))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_outline_color", Color.BLACK)
	t.add_theme_constant_override("outline_size", 8)
	v.add_child(t)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	# Legends table.
	var legends := parchment_box(row, Vector2(640, 0))
	legends.add_child(Art.heading("Legendary Hunters", 26))
	legends.add_child(Art.label("Offline rankings. These hunters are fictional characters; scores use the same rules (v%s)." % Scoring.RULES_VERSION, 14, Color(0.35, 0.27, 0.2), Art.font_italic))
	var rec: Dictionary = SaveData.data["records"]
	var rows := Rankings.table(SaveData.settings().get("player_name", "Investigator"), int(rec["best_score"]), float(rec.get("best_score_time", 0.0)), str(rec.get("best_score_house", "")))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	legends.add_child(grid)
	for h in ["#", "Hunter", "Points", "Record"]:
		grid.add_child(Art.label(h, 16, Color(0.35, 0.27, 0.2), Art.font_heading))
	for i in rows.size():
		var r: Dictionary = rows[i]
		var col := Art.BLOOD if r["is_player"] else Art.INK
		grid.add_child(Art.label(str(i + 1), 17, col, Art.font_heading))
		var name_l := Art.label(r["name"] + ("" if r["is_player"] else ""), 17, col, Art.font_heading if r["is_player"] else null)
		name_l.tooltip_text = r["note"]
		name_l.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(name_l)
		grid.add_child(Art.label(str(r["score"]), 17, col, Art.font_heading))
		var rt := "%s · %s" % [Journal.format_time_precise(r["time"]), r["house"]] if r["time"] > 0.0 else str(r["house"])
		grid.add_child(Art.label(rt, 14, Color(0.3, 0.22, 0.15)))
	if int(rec["best_score"]) <= 0:
		legends.add_child(Art.label("Vanquish something to join the table.", 15, Color(0.35, 0.27, 0.2), Art.font_italic))
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 16)
	row.add_child(right)
	var pbs := parchment_box(right, Vector2(560, 0))
	pbs.add_child(Art.heading("Your Records", 26))
	for id in Game.house_ids:
		var hr: Dictionary = SaveData.house_record(id)
		var line := "%s — %s · %s pts · %d/%d won" % [Game.house(id)["name"],
			Journal.format_time_precise(hr["best_time"]) if hr["best_time"] > 0.0 else "—",
			str(hr["best_score"]) if hr["best_score"] > 0 else "—", int(hr["wins"]), int(hr["runs"])]
		pbs.add_child(Art.label(line, 16))
		for diff in Defs.DIFFICULTIES.filter(func(d): return d != "normal"):
			var nr: Dictionary = SaveData.house_record(id, diff)
			if int(nr["runs"]) > 0:
				pbs.add_child(Art.label("      " + Defs.difficulty_name(diff) + " — %s · %s pts · %d/%d won" % [Journal.format_time_precise(nr["best_time"]) if nr["best_time"] > 0.0 else "—",
				str(nr["best_score"]) if nr["best_score"] > 0 else "—", int(nr["wins"]), int(nr["runs"])], 15, Art.BLOOD if Defs.rules(diff) == "nightmare" else Color(0.25, 0.35, 0.2)))
	# Competitive results are kept apart from solo rankings and legends.
	var mp: Dictionary = SaveData.data.get("mp", {})
	var comp := parchment_box(right, Vector2(560, 0))
	comp.add_child(Art.heading("Competitive (local record)", 24))
	if int(mp.get("matches", 0)) == 0:
		comp.add_child(Art.label("No competitive matches yet. Rules %s." % MpScoring.RULES_VERSION, 15, Color(0.35, 0.27, 0.2), Art.font_italic))
	else:
		comp.add_child(Art.label("Matches %d  ·  Wins %d  ·  Vanquishes %d  ·  Best %d pts  ·  Nightmare best %d" % [int(mp["matches"]), int(mp["wins"]), int(mp["vanquishes"]), int(mp["best_score"]), int(mp.get("nightmare_best_score", 0))], 16))
		comp.add_child(Art.label("Shoves given %d  ·  taken %d  ·  deaths %d" % [int(mp["shoves_given"]), int(mp["shoves_taken"]), int(mp["deaths"])], 15, Color(0.3, 0.22, 0.15)))
	global_box = parchment_box(right, Vector2(560, 0))
	global_box.add_child(Art.heading("Global Leaderboard", 26))
	global_box.add_child(Art.label(Online.last_status, 15, Color(0.35, 0.27, 0.2), Art.font_italic))
	if Online.is_configured():
		Online.top_received.connect(_on_global, CONNECT_ONE_SHOT)
		Online.fetch_top(10)
	else:
		var note := Art.label("Local records are never presented as a verified global ranking. See docs/LEADERBOARD.md to connect a server.", 14, Color(0.35, 0.27, 0.2))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(520, 0)
		global_box.add_child(note)
	var b := HBoxContainer.new()
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(b)
	back_button(b)

func _on_global(rows: Array, ok: bool, message: String) -> void:
	global_box.add_child(Art.label(message, 14, Color(0.35, 0.27, 0.2), Art.font_italic))
	if not ok:
		return
	for i in rows.size():
		var r: Dictionary = rows[i]
		global_box.add_child(Art.label("%d. %s — %d pts · %s" % [i + 1, r.get("name", "?"), int(r.get("score", 0)), r.get("house", "")], 16))
