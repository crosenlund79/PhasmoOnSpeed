extends Screen
## DEV STATISTICS: persisted performance history per house and creature.
## Development tool — it names hidden creatures. Read-only: statistics never
## feed back into difficulty or creature selection.

func _ready() -> void:
	add_backdrop("ui/menu_background.png", 0.75)
	var v := centered_column(1480, 20)
	var t := Art.heading("DEV STATISTICS", 40, Color(0.75, 0.85, 0.95))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var warn := Art.label("Development view — contains spoilers. Runs started: %d" % int(SaveData.data.get("runs_started", 0)), 15, Color(0.8, 0.75, 0.65), Art.font_italic)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(warn)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1480, 680)
	v.add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	var stats: Dictionary = SaveData.data["stats"]
	if stats.is_empty():
		body.add_child(Art.label("No runs recorded yet.", 18))
	var cols := ["Creature", "Runs", "Won", "Lost", "Avg win", "Best", "Best pts", "Evidence", "Right ID", "Wrong ID", "Blind", "Wounds", "Shifts", "Harbinger"]
	for house_id in stats:
		body.add_child(Art.heading(Game.house(house_id).get("name", house_id), 24))
		var grid := GridContainer.new()
		grid.columns = cols.size()
		grid.add_theme_constant_override("h_separation", 16)
		body.add_child(grid)
		for c in cols:
			grid.add_child(Art.label(c, 14, Color(0.35, 0.27, 0.2), Art.font_heading))
		var rooms_lines: Array = []
		for cid in stats[house_id]:
			var s: Dictionary = stats[house_id][cid]
			var avg: float = s["total_win_time"] / s["wins"] if s["wins"] > 0 else 0.0
			var vals := [Defs.creature_name(cid), s["runs"], s["wins"], s["losses"],
				Journal.format_time(avg) if avg > 0 else "—", Journal.format_time(s["best_time"]) if s["best_time"] > 0 else "—",
				s.get("best_score", 0), s["evidence_found"], s["correct_ids"], s["incorrect_ids"], s["blind_wins"],
				s["wounds"], s["transformations"], s["harbinger"]]
			for val in vals:
				grid.add_child(Art.label(str(val), 15))
			var top: Array = s["evidence_rooms"].keys()
			top.sort_custom(func(a, b): return s["evidence_rooms"][a] > s["evidence_rooms"][b])
			var avg_times: Array = []
			for ev in s.get("evidence_times", {}):
				var pair: Array = s["evidence_times"][ev]
				avg_times.append("%s %s" % [Defs.EVIDENCE[ev]["short"], Journal.format_time(pair[1] / maxf(1.0, pair[0]))])
			if not top.is_empty():
				rooms_lines.append("%s — discoveries: %s%s" % [Defs.creature_name(cid),
					", ".join(top.slice(0, 5).map(func(k): return "%s ×%d" % [k, s["evidence_rooms"][k]])),
					("  |  avg first-find: " + ", ".join(avg_times)) if not avg_times.is_empty() else ""])
		for line in rooms_lines:
			var l := Art.label(line, 14, Color(0.3, 0.22, 0.15), Art.font_italic)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(1400, 0)
			body.add_child(l)
	body.add_child(Art.heading("Recent runs", 24))
	var hist: Array = SaveData.data["history"]
	for i in range(hist.size() - 1, maxi(-1, hist.size() - 16), -1):
		var h: Dictionary = hist[i]
		body.add_child(Art.label("%s · %s%s · %s · %s · %d pts · ev %d · wrong %d · wounds %d" % [
			h["date"], Defs.creature_name(h["creature"]), " → Harbinger" if h["harbinger"] else "",
			Game.house(h["house"]).get("name", h["house"]), ("WON " if h["won"] else "LOST ") + Journal.format_time_precise(h["time"]),
			h["score"], h["evidence"], h["wrong"], h["wounds"]], 14))
	var b := HBoxContainer.new()
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_theme_constant_override("separation", 12)
	v.add_child(b)
	back_button(b)
	b.add_child(Art.button("Reset all data", func():
		SaveData.reset_all()
		Game.goto_stats(), 220))
