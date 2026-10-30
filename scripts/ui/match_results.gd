extends Control
## Competitive results: ranking, individual scores and breakdowns, evidence
## contribution, vanquishing credit, survival, penalties and commentary, over a
## looping 4× replay of the actual match.

var result := {}
var mres := {}
var replay_player: ReplayPlayer

func setup(p_result: Dictionary) -> void:
	result = p_result
	mres = result["match"]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var won: bool = mres["outcome"] == "vanquished"
	if not result["replay"].is_empty():
		replay_player = ReplayPlayer.new()
		replay_player.setup(result["replay"])
		replay_player.follow = result.get("me", "player_1") if result.get("me", "") != "" else "player_1"
		# Centre the replayed hunter in the area left of the panel (which starts at 50%).
		replay_player.camera_offset = Vector2(get_viewport_rect().size.x * (0.5 - 0.5 * 0.5) / replay_player.zoom, 0.0)
		var holder := Node2D.new()
		add_child(holder)
		holder.add_child(replay_player)
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(root)
	var dark := ColorRect.new()
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark.color = Color(0, 0, 0, 0.3) if won else Color(0.12, 0.0, 0.0, 0.45)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dark)
	Sfx.play("results_win" if won else "results_lose", 0.0)
	var banner := TextureRect.new()
	banner.texture = Art.tex("ui/banner_vanquished.png" if won else "ui/banner_perished.png")
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	banner.anchor_right = 0.5
	banner.offset_top = 14
	banner.offset_bottom = 170
	root.add_child(banner)
	var rows: Array = mres["rows"]
	var winner: Dictionary = rows[0]
	var head := Art.label(_headline(winner), 26, Color(0.95, 0.88, 0.7), Art.font_italic)
	head.anchor_right = 0.5
	head.offset_top = 168
	head.offset_bottom = 204
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_color_override("font_outline_color", Color.BLACK)
	head.add_theme_constant_override("outline_size", 8)
	root.add_child(head)
	var quip := Art.label("“" + _commentary() + "”", 20, Color(0.86, 0.8, 0.66), Art.font_italic)
	quip.anchor_right = 0.5
	quip.anchor_top = 1.0
	quip.anchor_bottom = 1.0
	quip.offset_left = 30
	quip.offset_top = -110
	quip.offset_bottom = -30
	quip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quip.add_theme_color_override("font_outline_color", Color.BLACK)
	quip.add_theme_constant_override("outline_size", 7)
	root.add_child(quip)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
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
	v.add_child(Art.heading("Final standings", 30))
	v.add_child(Art.label("%s · %s · %s" % [mres["house_name"], Journal.format_time_precise(mres["time"]), _entity_line()], 15, Color(0.3, 0.22, 0.15), Art.font_italic))
	for r in rows:
		_row(v, r, r["actor"] == result.get("me", ""))
	v.add_child(Art.label("Competitive rules %s · solo rankings are kept separately." % mres["rules_version"], 12, Color(0.4, 0.32, 0.24)))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	v.add_child(buttons)
	if Net.is_online():
		buttons.add_child(Art.button("Back to Lobby", func(): Game.goto_lobby(), 240))
	buttons.add_child(Art.button("Main Menu", func():
		Net.leave()
		Game.goto_menu(), 240))

func _row(v: VBoxContainer, r: Dictionary, mine: bool) -> void:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.55, 0.42, 0.22, 0.22 if mine else 0.1)
	sb.border_color = Player.COLORS[int(r["index"]) % 4]
	sb.border_width_left = 5
	sb.set_content_margin_all(6)
	box.add_theme_stylebox_override("panel", sb)
	v.add_child(box)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 2)
	box.add_child(inner)
	var top := HBoxContainer.new()
	inner.add_child(top)
	top.add_child(Art.label("#%d" % int(r["rank"]), 24, Art.INK, Art.font_heading))
	var name_l := Art.label("  %s%s" % [r["name"], "  (you)" if mine else ""], 22, Art.INK, Art.font_heading)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	top.add_child(Art.label("%d" % int(r["score"]), 26, Art.INK, Art.font_heading))
	var facts: Array = []
	facts.append("%d evidence (%d first)" % [int(r["true_evidence"]), int(r["first_finds"])])
	if r["vanquisher"]:
		facts.append("★ vanquished it")
	facts.append("alive" if r["alive"] and int(r["wounds"]) == 0 else ("wounded" if r["alive"] else "† perished"))
	if int(r["incorrect_attempts"]) > 0:
		facts.append("%d wrong attempt%s" % [int(r["incorrect_attempts"]), "" if int(r["incorrect_attempts"]) == 1 else "s"])
	if int(r["shoves_given"]) > 0:
		facts.append("%d shove%s" % [int(r["shoves_given"]), "" if int(r["shoves_given"]) == 1 else "s"])
	inner.add_child(Art.label("  ·  ".join(facts), 15, Color(0.3, 0.22, 0.15)))
	if mine:
		var grid := GridContainer.new()
		grid.columns = 2
		inner.add_child(grid)
		for line in r["score_lines"]:
			var n := Art.label(str(line[0]), 15, Art.INK)
			n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(n)
			var val := int(line[1])
			grid.add_child(Art.label(("+%d" % val) if val > 0 else str(val), 15, Art.BLOOD if val < 0 else Art.INK, Art.font_heading))

func _entity_line() -> String:
	var c: String = mres["creature"]
	if mres["harbinger"]:
		return "The Harbinger (it replaced %s)" % Defs.creature_name(mres["original_creature"])
	return Defs.creature_name(c)

func _headline(winner: Dictionary) -> String:
	match mres["outcome"]:
		"vanquished":
			return "%s wins with %d points." % [winner["name"], int(winner["score"])]
		_:
			return "The house wins. %s scored best among the fallen." % winner["name"]

func _commentary() -> String:
	var rows: Array = mres["rows"]
	var r := RandomNumberGenerator.new()
	r.seed = int(mres["seed"])
	var most_shoves: Dictionary = rows[0]
	for row in rows:
		if int(row["shoves_given"]) > int(most_shoves["shoves_given"]):
			most_shoves = row
	var vanq := rows.filter(func(x): return x["vanquisher"])
	if int(most_shoves["shoves_given"]) >= 3:
		return "%s shoved rivals %d times. Survival of the fittest. Friendship of the shortest." % [most_shoves["name"], int(most_shoves["shoves_given"])]
	if not vanq.is_empty() and int(vanq[0]["rank"]) > 1:
		return "%s banished it — and still lost to %s's paperwork." % [vanq[0]["name"], rows[0]["name"]]
	if mres["outcome"] != "vanquished":
		return ["Nobody left. Technically a draw. Spiritually, a massacre.", "The occupants send their regards. From the carriage."][r.randi_range(0, 1)]
	if mres["harbinger"]:
		return "Someone summoned the Harbinger. Everyone knows who. Nobody is saying."
	return ["An admirable display of teamwork. For someone else.", "Competitive ghost hunting: like regular ghost hunting, but with elbows."][r.randi_range(0, 1)]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		Net.leave()
		Game.goto_menu()
