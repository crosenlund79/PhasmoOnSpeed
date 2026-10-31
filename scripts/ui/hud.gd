extends CanvasLayer
## Gameplay HUD for the hunter on this machine, organised around the screen edges
## so the centre stays free for movement and encounters:
##   top-left    EQUIPMENT  — circular slots, selected one highlighted
##   top-right   EVIDENCE   — every evidence type, greyed until discovered
##   top-centre  readings / contextual feedback, then time, health, dread
##   bottom      SUSPECTED  — chosen entity, its evidence and requirements
## plus the "HUNTING!" warning, evidence cards, toasts (bottom-left), dramatic
## messages, spectating, the pause / controls panels and the shared
## multiplayer pause banner.
##
## `run` is a Run (solo / host) or a ClientRun (multiplayer client); both expose
## the same small read interface (elapsed, threat, map, player, hunters, …).

const INK := Color(0.09, 0.07, 0.06)
const INK_SOFT := Color(0.27, 0.2, 0.14)
const BONE := Color(0.93, 0.88, 0.76)
const PANEL_BG := Color(0.06, 0.05, 0.05, 0.74)
const DISC_BG := Color(0.1, 0.08, 0.07, 0.9)
const RING_OFF := Color(0.42, 0.36, 0.28, 0.55)
const EQ_SHORT := {"emf": "Needle", "thermometer": "Thermo", "uv": "Wraithlight", "spirit_box": "Whisper Box",
	"ghost_book": "Book", "orb_camera": "Scrying", "salt": "Salt", "crucifix": "Crucifix",
	"holy_water": "Holy Water", "garlic": "Garlic", "wooden_stake": "Stake", "silverware": "Silverware",
	"silver_stake": "Silver Stake", "hand_mirror": "Mirror", "iron_nails": "Iron Nails", "voodoo_doll": "Doll"}
## How each entity is vanquished: the method line under the SUSPECTED panel, and
## for creatures of flesh the items it takes. A ghost's items are its rite_needs
## (see requirement_items), so the panel can never disagree with the rite itself.
const REQUIREMENTS := {
	"shade": {"method": "Salt its room · Rite of Stillness there (hold V)"},
	"poltergeist": {"method": "Book in its room · Rite of Binding there (hold V)"},
	"blightness": {"method": "Crucifix in its room · Rite of Severance there (hold V)"},
	"crawler": {"method": "Carry holy water · Rite of Drowning in its room (hold V)"},
	"lost_one": {"method": "Book and salt in its room · Rite of Rest (hold V) · never touch its keepsake"},
	"drowned_sailor": {"method": "Salt its room, carry holy water · Rite of the Tides there (hold V)"},
	"plague_doctor": {"method": "Crucifix and book in its room · Rite of Cleansing there (hold V)"},
	"weeper": {"method": "Salt and a crucifix in its room · Rite of Solace there (hold V)"},
	"mimic": {"method": "Book in its room, carry holy water · Rite of Unmasking there (hold V)"},
	"vampire": {"items": ["garlic", "wooden_stake"], "method": "Carry garlic · strike with the wooden stake"},
	"werewolf": {"items": ["silverware", "silver_stake"], "method": "Melt silverware · strike with the silver stake"},
	"shapeshifter": {"items": ["hand_mirror", "iron_nails"], "method": "Unmask it in the mirror · strike with iron nails"},
}

static func requirement_items(id: String) -> Array:
	if Defs.is_ghost(id):
		return Defs.CREATURES[id].get("rite_needs", [])
	return REQUIREMENTS.get(id, {}).get("items", [])

## A circular icon slot. Styled by state; drawn, so it scales cleanly.
class Disc extends Control:
	var icon: TextureRect
	var fill := DISC_BG
	var ring := RING_OFF
	var ring_w := 2.0
	var glow := 0.0

	func _init(path: String, d: float) -> void:
		custom_minimum_size = Vector2(d, d)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon = Art.icon_rect(path, d * 0.64)
		icon.position = Vector2(d * 0.18, d * 0.18)
		icon.size = Vector2(d * 0.64, d * 0.64)
		add_child(icon)

	var ruled := false   # the player believes this evidence is absent

	func set_ruled(r: bool) -> void:
		ruled = r
		if r:
			ring = Color(0.55, 0.1, 0.08, 0.95)
			ring_w = 2.0
			glow = 0.0
			fill = Color(0.12, 0.05, 0.05, 0.9)
			icon.modulate = Color(0.35, 0.3, 0.3, 0.4)
		queue_redraw()

	func set_state(on: bool, strong: bool = false) -> void:
		ruled = false
		ring = Art.GOLD if on else RING_OFF
		ring_w = 3.0 if strong else (2.0 if on else 1.5)
		glow = 0.4 if strong else (0.16 if on else 0.0)
		fill = Color(0.2, 0.14, 0.07, 0.95) if strong else DISC_BG
		icon.modulate = Color.WHITE if on else Color(0.42, 0.4, 0.38, 0.55)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		if glow > 0.0:
			draw_circle(c, r + 3.0, Color(Art.GOLD.r, Art.GOLD.g, Art.GOLD.b, glow))
		draw_circle(c, r - 1.0, fill)
		draw_arc(c, r - ring_w * 0.5 - 0.5, 0.0, TAU, 48, ring, ring_w, true)
		if ruled:
			# Ruled out by the player: a bold red ink cross over the dimmed icon.
			var d := r * 0.55
			for pair in [[Vector2(-d, -d), Vector2(d, d)], [Vector2(d, -d), Vector2(-d, d)]]:
				draw_line(c + pair[0], c + pair[1], Color(0, 0, 0, 0.7), 4.5, true)
				draw_line(c + pair[0], c + pair[1], Color(0.8, 0.12, 0.08), 2.5, true)

## Gold rings around what can be picked up or used nearby: a bright pulsing ring
## on what [E] would act on, faint rings on other pickups close by.
class Highlighter extends Node2D:
	var target := Vector2.INF
	var near: Array = []
	var _t := 0.0
	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
	func _draw() -> void:
		var gold := Art.GOLD
		for v: Vector2 in near:
			if v.distance_to(target) > 4.0:
				draw_arc(v, 15.0, 0.0, TAU, 32, Color(0, 0, 0, 0.35), 3.0, true)
				draw_arc(v, 15.0, 0.0, TAU, 32, Color(gold.r, gold.g, gold.b, 0.55 + 0.15 * sin(_t * 3.0)), 1.8, true)
		if target != Vector2.INF:
			var r := 19.0 + 2.5 * sin(_t * 6.0)
			draw_arc(target, r + 3.0, 0.0, TAU, 40, Color(0, 0, 0, 0.5), 3.5, true)
			draw_arc(target, r, 0.0, TAU, 40, Color(1.0, 0.85, 0.45, 0.9), 2.0, true)
			for i in 4:
				var a := _t * 1.6 + i * PI * 0.5
				draw_circle(target + Vector2.from_angle(a) * r, 1.8, Color(1.0, 0.95, 0.7, 0.9))

## The Witch's Needle in its corked, sigil-sealed glass tube. Almost motionless
## when nothing is near; twitches, taps and finally rattles against the glass as
## the presence (level 1–5) grows.
class NeedleGauge extends Control:
	var level := 0.0
	var variant: Dictionary = Progression.needle_params()   # your own equipped needle's look
	var _y := 0.0          # needle tip deflection (px), a damped spring
	var _v := 0.0
	var _flash := 0.0
	var _shake := Vector2.ZERO
	var _strikes: Array = []   # recent strike marks [y_sign, age]
	const RATE := [0.0, 0.15, 1.6, 3.2, 6.5, 18.0]      # kicks per second by level
	const KICK := [0.0, 25.0, 70.0, 165.0, 210.0, 260.0]  # kick strength (px/s)
	func _lerp_tab(tab: Array, lv: float) -> float:
		var i := clampi(int(floor(lv)), 0, 4)
		return lerpf(tab[i], tab[i + 1], clampf(lv - i, 0.0, 1.0))
	func _process(delta: float) -> void:
		var lv := clampf(level, 0.0, 5.0)
		var inner := size.y * 0.32 - 2.0
		# Random kicks from the presence, faster and harder as it grows.
		if randf() < _lerp_tab(RATE, lv) * delta:
			_v += _lerp_tab(KICK, lv) * (1.0 if randf() < 0.5 else -1.0)
		_v += (-140.0 * _y - float(variant["damp"]) * _v) * delta
		_y += _v * delta
		if absf(_y) >= inner:
			_y = signf(_y) * inner
			if absf(_v) > 30.0:
				_flash = clampf(absf(_v) / 200.0, 0.4, 1.0)
				_strikes.append([signf(_y), 0.0])
				_shake = Vector2(randf_range(-1, 1), signf(_y)) * clampf(absf(_v) / 120.0, 0.0, 2.5)
			_v = -_v * 0.45
		_flash = maxf(0.0, _flash - delta * 5.0)
		_shake = _shake.move_toward(Vector2.ZERO, delta * 12.0)
		for st in _strikes:
			st[1] += delta
		_strikes = _strikes.filter(func(st): return st[1] < 0.35)
		queue_redraw()
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var o := _shake + (Vector2(randf_range(-1.5, 1.5), randf_range(-1.0, 1.0)) if level >= 4.9 else Vector2.ZERO)
		var cy := h * 0.5
		var tube := Rect2(Vector2(h * 0.3, h * 0.18) + o, Vector2(w - h * 1.6, h * 0.64))
		var pivot := Vector2(tube.end.x - 6.0, cy) + o
		var tip := Vector2(tube.position.x + 8.0, cy + _y) + o
		var glass: Color = variant["glass"]
		var glow: Color = variant["glow"]
		if glow.a > 0.0:
			draw_rect(tube.grow(3.0), glow)
		draw_rect(tube, Color(glass.r, glass.g, glass.b, 0.32))   # pale old glass behind the needle
		for st in _strikes:
			# Where the needle hit: a white chip of light and a hairline crack-glint.
			var a: float = 1.0 - st[1] / 0.35
			var yy: float = tube.position.y + 2.0 if st[0] < 0.0 else tube.end.y - 2.0
			draw_line(Vector2(tube.position.x + 4.0, yy), Vector2(tube.position.x + 22.0, yy), Color(1.0, 0.95, 0.8, a * 0.9), 2.0)
		draw_line(pivot, tip, Color(0.05, 0.04, 0.05), 3.4, true)
		draw_line(pivot, tip, Color(0.55, 0.55, 0.6, 0.9), 1.0, true)
		draw_circle(pivot, 2.4, Color(0.25, 0.22, 0.2))
		if _flash > 0.0:
			draw_circle(tip, 2.0 + 5.0 * _flash, Color(1.0, 0.95, 0.8, _flash * 0.9))
		# Glass: outline, rounded end and a highlight.
		draw_rect(tube, Color(glass.r, glass.g, glass.b, 0.75), false, 1.5)
		draw_arc(Vector2(tube.position.x, cy) + o, tube.size.y * 0.5, PI * 0.5, PI * 1.5, 16, Color(glass.r, glass.g, glass.b, 0.75), 1.5, true)
		draw_line(tube.position + Vector2(4, 3), Vector2(tube.end.x - 4, tube.position.y + 3), Color(1, 1, 1, 0.35), 1.0)
		# Cork stopper with its sealing sigil.
		var cork := Rect2(Vector2(tube.end.x, h * 0.12) + o, Vector2(h * 0.9, h * 0.76))
		draw_rect(cork, Color(0.55, 0.38, 0.22))
		draw_rect(cork, Color(0.1, 0.07, 0.05), false, 1.2)
		var sc := cork.get_center()
		var sr := cork.size.y * 0.32
		draw_circle(sc, sr, Color(0.55, 0.06, 0.05))
		var pts := PackedVector2Array()
		for i in 6:
			pts.append(sc + Vector2.from_angle(-PI * 0.5 + i * TAU * 2.0 / 5.0) * sr * 0.75)
		draw_polyline(pts, variant["sigil"], 1.0, true)

## The red moon beside your hearts while a Blood Moon hangs over the house.
class BloodMoonGlyph extends Control:
	var _t := 0.0
	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.42
		draw_circle(c, r * (1.35 + 0.1 * sin(_t * 0.8)), Color(0.8, 0.1, 0.05, 0.18))
		draw_circle(c, r, Color(0.62, 0.08, 0.05))
		draw_circle(c + Vector2(-r * 0.3, -r * 0.2), r * 0.22, Color(0.45, 0.05, 0.03))
		draw_circle(c + Vector2(r * 0.35, r * 0.3), r * 0.15, Color(0.45, 0.05, 0.03))
		draw_arc(c, r, 0.0, TAU, 24, Color(0.1, 0.02, 0.02), 1.2, true)

var run
var k := 1.0                    # HUD scale setting
var equip_panel: PanelContainer
var equip_grid: GridContainer
var evidence_panel: PanelContainer
var evidence_grid: GridContainer
var info_main: Label
var needle_gauge: NeedleGauge
var prompt_chip: PanelContainer
var prompt_icon: TextureRect
var prompt_text: Label
var info_sub: Label
var hold_bar: ProgressBar
var timer_label: Label
var hearts: Array = []
var dread_fill: ColorRect
var stamina_fill: ColorRect
var status_line: Label
var hunt_label: Label
var suspect_box: VBoxContainer
var toast_box: VBoxContainer
var big_title: Label
var big_sub: Label
var big_box: VBoxContainer
var hunt_overlay: TextureRect
var wound_overlay: ColorRect
var pause_panel: Control
var help_panel: Control
var shared_pause_panel: Control
var shared_pause_title: Label
var shared_pause_sub: Label
var spectate_label: Label
var guide_panel: PanelContainer
var guide_title: Label
var guide_text: Label
var guide_icon: TextureRect
var _guide_t := 0.0
var suspect_picker: HBoxContainer
var notify_root: Node2D
var highlighter: Highlighter
var _notifications: Array = []
var _ev_discs := {}            # evidence id -> Disc
var _hunting := false
var _t := 0.0
var _shake := 0.0
var _toast_recent := {}
var _equipment = null
var _picker_t := 0.0
var spectating := false
var spectate_index := 0

func setup(p_run) -> void:
	run = p_run
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	k = clampf(float(_settings().get("hud_scale", 1.0)), Game.GAME_SCALE_MIN, Game.GAME_SCALE_MAX)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_overlays(root)
	_build_equipment(root)
	_build_evidence(root)
	_build_centre(root)
	_build_suspect(root)
	_build_toasts(root)
	_build_prompt_chip(root)
	_build_guide(root)
	_build_big_message(root)
	_build_suspect_picker(root)
	_build_spectate(root)
	_build_pause(root)
	_build_shared_pause(root)
	_build_help(root)
	notify_root = Node2D.new()
	notify_root.z_index = 40
	run.world_text.add_child(notify_root)
	highlighter = Highlighter.new()
	highlighter.z_index = 20
	run.world_text.add_child(highlighter)
	_equipment = run.player.equipment
	_equipment.changed.connect(_on_equipment_changed)
	_rebuild_equipment()
	refresh()

func _settings() -> Dictionary:
	return SaveData.settings()

func _px(v: float) -> int:
	return int(round(v * k))

func nightmare() -> bool:
	return Defs.rules(str(run.get("difficulty"))) == "nightmare"

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

func _outlined(text: String, size: int, color: Color, font: Font = null, outline: int = 4) -> Label:
	var l := Art.label(text, size, color, font)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", outline)
	return l

## The shared ink-and-gold panel used by every HUD box.
func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = Color(Art.GOLD.r, Art.GOLD.g, Art.GOLD.b, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(_px(7))
	sb.content_margin_left = _px(8)
	sb.content_margin_right = _px(8)
	sb.content_margin_top = _px(5)
	sb.content_margin_bottom = _px(6)
	return sb

func _panel(root: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	return p

## EQUIPMENT and EVIDENCE share this exact heading.
func _corner_heading(text: String) -> Label:
	var l := _outlined(text, _px(15), Art.GOLD, Art.font_heading, 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", _px(4))
	g.add_theme_constant_override("v_separation", _px(3))
	return g

## One grid cell: disc + small label beneath.
func _cell(icon: String, label: String, show_label: bool, d: float = 42.0) -> Array:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", _px(1))
	v.custom_minimum_size = Vector2(_px(74), 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var disc := Disc.new(icon, _px(d))
	v.add_child(disc)
	var l := _outlined(label, _px(11), BONE, Art.font_heading, 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size = Vector2(_px(74), 0)
	l.visible = show_label
	v.add_child(l)
	return [v, disc, l]

func _build_equipment(root: Control) -> void:
	equip_panel = _panel(root)
	equip_panel.position = Vector2(_px(10), _px(10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", _px(3))
	equip_panel.add_child(v)
	v.add_child(_corner_heading("EQUIPMENT"))
	equip_grid = _grid()
	v.add_child(equip_grid)
	equip_panel.modulate.a = clampf(float(_settings().get("equip_hud_opacity", 0.9)), 0.2, 1.0)

func _on_equipment_changed() -> void:
	_rebuild_equipment()
	refresh()

func _rebuild_equipment() -> void:
	for c in equip_grid.get_children():
		c.queue_free()
	var eq = _equipment
	var show: bool = _settings().get("equip_labels", true)
	for i in eq.slots.size():
		var id: String = eq.slots[i]
		var cell := _cell(Defs.EQUIPMENT[id]["icon"], EQ_SHORT.get(id, Defs.EQUIPMENT[id]["name"]), show)
		var disc: Disc = cell[1]
		disc.set_state(true, i == eq.selected)
		if i != eq.selected:
			disc.icon.modulate = Color(0.85, 0.82, 0.78, 0.9)
			disc.ring = Color(0.55, 0.47, 0.34, 0.7)
		else:
			cell[2].add_theme_color_override("font_color", Art.GOLD)
		var key := _outlined(str(i + 1) if i < 9 else "", _px(11), Color(0.95, 0.85, 0.6), Art.font_heading, 3)
		key.position = Vector2(-_px(2), -_px(3))
		disc.add_child(key)
		var ch: String = eq.charge_text(id)
		if ch != "":
			var cl := _outlined(ch, _px(11), BONE, null, 3)
			cl.position = Vector2(_px(28), _px(27))
			disc.add_child(cl)
		equip_grid.add_child(cell[0])

func _build_evidence(root: Control) -> void:
	evidence_panel = _panel(root)
	evidence_panel.anchor_left = 1.0
	evidence_panel.anchor_right = 1.0
	evidence_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	evidence_panel.offset_left = -_px(10)
	evidence_panel.offset_right = -_px(10)
	evidence_panel.offset_top = _px(10)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", _px(3))
	evidence_panel.add_child(v)
	v.add_child(_corner_heading("EVIDENCE"))
	evidence_grid = _grid()
	v.add_child(evidence_grid)
	var show: bool = _settings().get("ev_labels", true)
	# Every evidence type is listed from the start — the six conventional ones first.
	var order: Array = Defs.CONVENTIONAL_EVIDENCE.duplicate()
	for id in Defs.EVIDENCE:
		if not id in order:
			order.append(id)
	for id in order:
		var cell := _cell(Defs.EVIDENCE[id]["icon"], Defs.EVIDENCE[id]["short"], show)
		evidence_grid.add_child(cell[0])
		_ev_discs[id] = cell[1]
		# Right-click: "I've looked hard — it isn't here" (the player's deduction, reversible).
		var disc: Disc = cell[1]
		var eid: String = id
		disc.mouse_filter = Control.MOUSE_FILTER_STOP
		disc.tooltip_text = "%s — right-click to rule out / restore" % Defs.EVIDENCE[id]["name"]
		disc.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
				toggle_ruled_out(eid))

func _build_centre(root: Control) -> void:
	var col := VBoxContainer.new()
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.offset_left = -_px(220)
	col.offset_right = _px(220)
	col.offset_top = _px(10)
	col.add_theme_constant_override("separation", _px(4))
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	# Upper box: what the current tool / surroundings are telling you.
	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", _panel_style())
	info.custom_minimum_size = Vector2(0, _px(62))
	col.add_child(info)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 0)
	iv.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_child(iv)
	needle_gauge = NeedleGauge.new()
	needle_gauge.custom_minimum_size = Vector2(_px(320), _px(38))
	needle_gauge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	needle_gauge.visible = false
	iv.add_child(needle_gauge)
	# Same typography as the EQUIPMENT / EVIDENCE panels: heading face, outlined.
	info_main = _outlined("", _px(15), Art.GOLD, Art.font_heading, 3)
	info_main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_main.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	iv.add_child(info_main)
	info_sub = _outlined("", _px(11), BONE, Art.font_heading, 3)
	info_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	iv.add_child(info_sub)
	hold_bar = ProgressBar.new()
	hold_bar.custom_minimum_size = Vector2(0, _px(4))
	hold_bar.show_percentage = false
	hold_bar.max_value = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Art.GOLD
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	hold_bar.add_theme_stylebox_override("fill", fill)
	hold_bar.add_theme_stylebox_override("background", bg)
	hold_bar.modulate.a = 0.0
	iv.add_child(hold_bar)
	# Lower box: run status.
	var status := PanelContainer.new()
	status.add_theme_stylebox_override("panel", _panel_style())
	status.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	status.custom_minimum_size = Vector2(_px(330), 0)
	col.add_child(status)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", _px(2))
	status.add_child(sv)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", _px(6))
	sv.add_child(top)
	top.add_child(Art.icon_rect("icons/ui_clock.png", _px(22)))
	timer_label = _outlined("00:00.00", _px(22), BONE, Art.font_numeric, 3)
	timer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(timer_label)
	for i in 2:
		var h := Art.icon_rect("icons/ui_heart.png", _px(22))
		top.add_child(h)
		hearts.append(h)
	if run.get("blood_moon"):
		var moon := BloodMoonGlyph.new()
		moon.custom_minimum_size = Vector2(_px(22), _px(22))
		moon.tooltip_text = "Blood Moon"
		top.add_child(moon)
	dread_fill = _bar(sv, Color(0.62, 0.1, 0.07))
	stamina_fill = _bar(sv, Color(0.62, 0.72, 0.78))
	status_line = _outlined("", _px(12), Color(0.85, 0.8, 0.7), Art.font_italic, 3)
	status_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sv.add_child(status_line)
	# The hunt warning sits just beneath, away from the investigator.
	hunt_label = Art.label("HUNTING!", _px(64), Color(0.75, 0.04, 0.03), Art.font_heading)
	hunt_label.add_theme_color_override("font_outline_color", Color(0.05, 0.0, 0.0, 0.6))
	hunt_label.add_theme_constant_override("outline_size", _px(8))
	hunt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hunt_label.modulate.a = 0.0
	col.add_child(hunt_label)

func _bar(parent: Control, color: Color) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color(0.0, 0.0, 0.0, 0.55)
	bar.custom_minimum_size = Vector2(0, _px(4))
	parent.add_child(bar)
	var f := ColorRect.new()
	f.color = color
	f.size = Vector2(0, _px(4))
	bar.add_child(f)
	return f

func _build_suspect(root: Control) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(p)
	p.offset_top = -_px(8)
	p.offset_bottom = -_px(8)
	suspect_box = VBoxContainer.new()
	suspect_box.add_theme_constant_override("separation", _px(2))
	p.add_child(suspect_box)

func _rebuild_suspect() -> void:
	for c in suspect_box.get_children():
		c.queue_free()
	var p = run.player
	var sus: String = p.suspect
	if run.is_harbinger():
		sus = "harbinger"
	var title := _corner_heading("SUSPECTED")
	suspect_box.add_child(title)
	if not nightmare() and sus != "harbinger":
		suspect_box.add_child(_suspect_choices(sus))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _px(8))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	suspect_box.add_child(row)
	if sus == "":
		if Defs.candidates(p.journal).is_empty():
			# The player's own notes contradict every entity: say so, and how to fix it.
			row.add_child(_outlined("No entity fits", _px(22), Color(0.9, 0.35, 0.25), Art.font_heading))
			row.add_child(_outlined("Right-click a ruled-out evidence type to restore it", _px(13), Color(0.8, 0.75, 0.66), Art.font_italic, 3))
			return
		row.add_child(_outlined("None", _px(22), BONE, Art.font_heading))
		row.add_child(_outlined("Tab / Shift+Tab to choose", _px(13), Color(0.8, 0.75, 0.66), Art.font_italic, 3))
		return
	var d: Dictionary = Defs.CREATURES[sus]
	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", -_px(2))
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(name_box)
	name_box.add_child(_outlined(d["name"], _px(22), Art.GOLD if sus != "harbinger" else Color(0.85, 0.15, 0.1), Art.font_heading))
	if nightmare():
		# Nightmare: no icons — only what the creature is said to be.
		var blurb := _outlined(d["blurb"], _px(14), BONE, Art.font_italic, 3)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.custom_minimum_size = Vector2(_px(360), 0)
		row.add_child(blurb)
		return
	if sus == "harbinger":
		var t := _outlined("Sigil candles lit %d / 3  ·  then the Final Rite beside it (hold V)" % run.sigils_lit(), _px(14), BONE, Art.font_italic, 3)
		row.add_child(t)
		return
	var show: bool = _settings().get("suspect_labels", true)
	var j: Journal = p.journal
	for ev in d["evidence"]:
		var cell := _cell(Defs.EVIDENCE[ev]["icon"], Defs.EVIDENCE[ev]["short"], show, 34.0)
		cell[1].set_state(j.has(ev))
		if j.state(ev) == "ruled_out":
			cell[1].set_ruled(true)
		row.add_child(cell[0])
	var sep := ColorRect.new()
	sep.color = Color(Art.GOLD.r, Art.GOLD.g, Art.GOLD.b, 0.4)
	sep.custom_minimum_size = Vector2(1, _px(40))
	row.add_child(sep)
	var req: Dictionary = REQUIREMENTS.get(sus, {"method": ""})
	for item in requirement_items(sus):
		var cell := _cell(Defs.EQUIPMENT[item]["icon"], EQ_SHORT.get(item, item), show, 34.0)
		cell[1].set_state(p.has_prepared(item))
		row.add_child(cell[0])
	var m := _outlined(req["method"], _px(12), Color(0.85, 0.8, 0.7), Art.font_italic, 3)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	suspect_box.add_child(m)

## Every entity you can suspect: the chosen one in gold, the others greyed (Tab cycles).
func _suspect_choices(sus: String) -> HBoxContainer:
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", _px(2))
	choices.alignment = BoxContainer.ALIGNMENT_CENTER
	var show: bool = _settings().get("suspect_labels", true)
	for id in Defs.ORDINARY_CREATURES:
		var cell := _cell(Defs.CREATURES[id]["token"], Defs.short_name(id), show, 34.0 if id == sus else 28.0)
		var on: bool = id == sus
		cell[1].set_state(on, on)
		if on:
			cell[2].add_theme_color_override("font_color", Art.GOLD)
		else:
			cell[2].modulate = Color(1, 1, 1, 0.5)
		# Contradicted by your notes (found or ruled-out evidence): crossed through;
		# Tab skips it until the notes change.
		var j: Journal = run.player.journal
		if not Defs.fits(id, j):
			cell[1].set_ruled(true)
			if on:
				cell[1].ring = Art.GOLD
			cell[0].modulate = Color(1, 1, 1, 0.75)
		choices.add_child(cell[0])
	return choices

func _build_toasts(root: Control) -> void:
	toast_box = VBoxContainer.new()
	toast_box.anchor_top = 1.0
	toast_box.anchor_bottom = 1.0
	toast_box.offset_left = _px(12)
	toast_box.offset_right = _px(12) + 420
	toast_box.offset_top = -260
	toast_box.offset_bottom = -_px(12)
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_theme_constant_override("separation", 4)
	root.add_child(toast_box)

## Beginner Mode: a parchment note of advice on the left edge, above the toasts.
func _build_guide(root: Control) -> void:
	guide_panel = PanelContainer.new()
	guide_panel.add_theme_stylebox_override("panel", Art.parchment_panel())
	guide_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guide_panel.anchor_top = 1.0
	guide_panel.anchor_bottom = 1.0
	guide_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	guide_panel.offset_left = _px(12)
	guide_panel.offset_right = _px(12) + _px(400)
	guide_panel.offset_top = -200
	guide_panel.offset_bottom = -200
	guide_panel.modulate.a = 0.0
	root.add_child(guide_panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", _px(10))
	guide_panel.add_child(h)
	guide_icon = Art.icon_rect("icons/ui_quill.png", _px(40))
	guide_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(guide_icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	guide_title = Art.label("", _px(17), Art.BLOOD, Art.font_heading)
	v.add_child(guide_title)
	guide_text = _small("", _px(15), INK)
	guide_text.custom_minimum_size = Vector2(_px(330), 0)
	v.add_child(guide_text)

func show_guide(title: String, text: String, icon: String = "icons/ui_quill.png") -> void:
	guide_title.text = title
	guide_text.text = text
	guide_icon.texture = Art.tex(icon)
	guide_panel.offset_top = -200   # collapse, then regrow upwards to fit the new text
	guide_panel.offset_bottom = -200
	_guide_t = clampf(5.0 + text.length() * 0.06, 7.0, 15.0)
	Sfx.play("pencil_scribble", -14.0, 1.1)
	var tw := guide_panel.create_tween()
	tw.tween_property(guide_panel, "modulate:a", 1.0, 0.3)

func _build_big_message(root: Control) -> void:
	big_box = VBoxContainer.new()
	big_box.anchor_left = 0.0
	big_box.anchor_right = 1.0
	big_box.anchor_top = 0.3
	big_box.anchor_bottom = 0.3
	big_box.offset_left = _px(220)
	big_box.offset_right = -_px(220)
	big_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big_box.modulate.a = 0.0
	root.add_child(big_box)
	big_title = Art.label("", _px(58), Art.GOLD, Art.font_heading)
	big_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_title.add_theme_color_override("font_outline_color", Color.BLACK)
	big_title.add_theme_constant_override("outline_size", _px(12))
	big_box.add_child(big_title)
	big_sub = Art.label("", _px(22), BONE, Art.font_italic)
	big_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	big_sub.add_theme_color_override("font_outline_color", Color.BLACK)
	big_sub.add_theme_constant_override("outline_size", 8)
	big_box.add_child(big_sub)

## Compact strip of every entity, shown briefly above the SUSPECTED panel while choosing.
func _build_suspect_picker(root: Control) -> void:
	var holder := CenterContainer.new()
	holder.anchor_left = 0.0
	holder.anchor_right = 1.0
	holder.anchor_top = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_top = -_px(250)
	holder.offset_bottom = -_px(140)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	suspect_picker = HBoxContainer.new()
	suspect_picker.add_theme_constant_override("separation", 6)
	suspect_picker.modulate.a = 0.0
	holder.add_child(suspect_picker)
	for id in [""] + Defs.ORDINARY_CREATURES:
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", Art.parchment_panel())
		cell.custom_minimum_size = Vector2(_px(88), 0)
		cell.set_meta("id", id)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		cell.add_child(v)
		if id == "":
			var q := Art.label("?", _px(32), INK, Art.font_heading)
			q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.add_child(q)
		else:
			v.add_child(Art.icon_rect(Defs.CREATURES[id]["token"], _px(38)))
		var n := Art.label("None" if id == "" else Defs.short_name(id), _px(13), INK, Art.font_heading)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n)
		suspect_picker.add_child(cell)

func show_suspect_picker() -> void:
	if not nightmare():
		return   # the SUSPECTED panel already lists every entity
	_picker_t = 1.6
	for cell in suspect_picker.get_children():
		var on: bool = cell.get_meta("id") == run.player.suspect
		cell.modulate = Color(1, 1, 1, 1) if on else Color(0.55, 0.52, 0.5, 0.85)
		cell.scale = Vector2(1.08, 1.08) if on else Vector2.ONE

func _build_spectate(root: Control) -> void:
	spectate_label = _outlined("", 24, Color(0.85, 0.85, 0.95), Art.font_heading, 8)
	spectate_label.anchor_left = 0.0
	spectate_label.anchor_right = 1.0
	spectate_label.anchor_top = 1.0
	spectate_label.anchor_bottom = 1.0
	spectate_label.offset_top = -_px(180)
	spectate_label.offset_bottom = -_px(150)
	spectate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spectate_label.visible = false
	root.add_child(spectate_label)

## Panels built at their design size follow the Gameplay UI scale about their centre.
func _scale_with_hud(c: Control) -> void:
	c.scale = Vector2(k, k)
	c.resized.connect(func(): c.pivot_offset = c.size * 0.5)

func _centered_panel(root: Control, width: float) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.visible = false
	root.add_child(cc)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.show_behind_parent = true
	cc.add_child(dim)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(width, 0)
	_scale_with_hud(p)
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	return v

func _build_pause(root: Control) -> void:
	var v := _centered_panel(root, 380)
	pause_panel = v.get_parent().get_parent()
	var t := Art.heading("Paused" if not run.multiplayer_match else "Menu", 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if run.multiplayer_match:
		var note := "Opening the menu pauses the match for everyone — for up to %d seconds." % int(Net.PAUSE_LIMIT) if Net.options.get("pause_limit", true) else "Opening the menu pauses the match for everyone until you resume."
		var nl := _small(note, 15, INK_SOFT, Art.font_italic)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(nl)
	v.add_child(Art.button("Resume", func(): toggle_pause()))
	if not run.multiplayer_match:
		v.add_child(Art.button("Restart run", func():
			run.set_paused(false)
			run.restart()))
	v.add_child(Art.button("Controls", func(): help_panel.visible = true))
	v.add_child(Art.button("Leave match" if run.multiplayer_match else "Abandon to menu", func():
		run.set_paused(false)
		Sfx.stop_all_loops()
		if run.multiplayer_match:
			Net.leave()
		Game.goto_menu()))

## Multiplayer: the banner every hunter sees while the match is paused.
func _build_shared_pause(root: Control) -> void:
	shared_pause_panel = Control.new()
	shared_pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	shared_pause_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shared_pause_panel.visible = false
	root.add_child(shared_pause_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.03, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shared_pause_panel.add_child(dim)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style())
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.2
	p.anchor_bottom = 0.2
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.offset_left = -260
	p.offset_right = 260
	_scale_with_hud(p)
	shared_pause_panel.add_child(p)
	var v := VBoxContainer.new()
	p.add_child(v)
	shared_pause_title = _outlined("MATCH PAUSED", 40, Art.GOLD, Art.font_heading, 6)
	shared_pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(shared_pause_title)
	shared_pause_sub = _outlined("", 18, BONE, Art.font_italic, 4)
	shared_pause_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shared_pause_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(shared_pause_sub)

var _shared_by := ""
var _shared_left := -1.0

## by: who opened their menu; remaining < 0 means no time limit.
func show_shared_pause(on: bool, by: String = "", remaining: float = -1.0) -> void:
	shared_pause_panel.visible = on
	_shared_by = by
	_shared_left = remaining
	_update_shared_pause(0.0)
	if not on and pause_panel.visible:
		toast("The match has resumed.", "icons/ui_clock.png", true)

func _update_shared_pause(delta: float) -> void:
	if not shared_pause_panel.visible:
		return
	if _shared_left >= 0.0:
		_shared_left = maxf(0.0, _shared_left - delta)
		shared_pause_sub.text = "%s opened the menu  ·  resumes in %d s" % [_shared_by, int(ceil(_shared_left))]
	else:
		shared_pause_sub.text = "%s opened the menu  ·  no time limit" % _shared_by

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

# --- Journal updates ---------------------------------------------------------------------

func on_discovered(entry: Dictionary) -> void:
	refresh()
	var disc: Disc = _ev_discs.get(entry["id"])
	if disc:
		disc.pivot_offset = disc.size * 0.5
		disc.modulate = Color(1.9, 1.5, 0.7)
		disc.scale = Vector2(1.35, 1.35)
		var tw := disc.create_tween().set_parallel(true)
		tw.tween_property(disc, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(disc, "modulate", Color.WHITE, 1.6)
	_notify_evidence(entry)

## The big, unmistakable "EVIDENCE RECORDED" card that pops beside the investigator.
func _notify_evidence(entry: Dictionary) -> void:
	var s := _settings()
	if not s.get("ev_notify", true):
		return
	var card := Node2D.new()
	notify_root.add_child(card)
	var scale_k: float = clampf(float(s.get("ev_notify_size", 1.0)), 0.6, 1.6) / run.CAMERA_ZOOM
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.09, 0.08, 0.78)
	sb.border_color = Art.GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 6
	panel.add_theme_stylebox_override("panel", sb)
	card.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	panel.add_child(h)
	var icon_holder := Control.new()
	icon_holder.custom_minimum_size = Vector2(48, 48)
	h.add_child(icon_holder)
	var book := Art.icon_rect("icons/ui_quill.png", 48)
	book.pivot_offset = Vector2(24, 24)
	icon_holder.add_child(book)
	var ev_icon := Art.icon_rect(entry["icon"], 26)
	ev_icon.position = Vector2(26, 26)
	icon_holder.add_child(ev_icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	h.add_child(v)
	v.add_child(Art.label("EVIDENCE RECORDED", 13, Art.GOLD, Art.font_heading))
	v.add_child(Art.label(entry["name"], 22, Color(0.97, 0.93, 0.84), Art.font_italic))
	v.add_child(Art.label("%s · %s" % [Journal.format_time(entry["time"]), entry["room_name"]], 14, Color(0.85, 0.8, 0.7), Art.font_heading))
	card.scale = Vector2(scale_k, scale_k) * 0.6
	card.modulate.a = 0.0
	card.set_meta("age", 0.0)
	card.set_meta("target_scale", scale_k)
	_notifications.append(card)
	while _notifications.size() > 3:
		var old: Node2D = _notifications.pop_front()
		old.queue_free()
	# Pop-in with a little quill flourish.
	var tw := card.create_tween().set_parallel(true)
	tw.tween_property(card, "scale", Vector2(scale_k, scale_k), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", clampf(float(s.get("ev_notify_opacity", 0.95)), 0.2, 1.0), 0.2)
	var bt := book.create_tween()
	bt.tween_property(book, "rotation", -0.35, 0.12)
	bt.tween_property(book, "rotation", 0.25, 0.12)
	bt.tween_property(book, "rotation", -0.15, 0.12)
	bt.tween_property(book, "rotation", 0.0, 0.12)

## Mark / unmark evidence as ruled out (local to this player; never scored).
func toggle_ruled_out(id: String) -> void:
	if run.player.journal.toggle_ruled_out(id):
		Sfx.play("pencil_scribble", -16.0, 1.4)
		run.on_ruled_out_changed(id)
		refresh()

func refresh() -> void:
	var j: Journal = run.player.journal
	var voided := {}
	for e in j.void_entries():
		voided[e["id"]] = true
	for id in _ev_discs:
		var disc: Disc = _ev_discs[id]
		disc.set_state(j.has(id))
		if j.state(id) == "ruled_out":
			disc.set_ruled(true)
		if not j.has(id) and voided.has(id):
			disc.ring = Color(0.5, 0.2, 0.15, 0.6)    # found before the Harbinger: no longer counts
			disc.queue_redraw()
	_rebuild_suspect()

# --- Per-frame -----------------------------------------------------------------------------

var _sigils_seen := -1

func _process(delta: float) -> void:
	_t += delta
	if run == null or run.player == null:
		return
	_update_shared_pause(delta)
	if _guide_t > 0.0:
		_guide_t -= delta
		if _guide_t <= 0.0:
			guide_panel.create_tween().tween_property(guide_panel, "modulate:a", 0.0, 0.6)
	timer_label.text = Journal.format_time_precise(run.elapsed)
	var p = run.player
	hearts[0].texture = Art.tex("icons/ui_heart_wounded.png" if p.wounds >= 2 else "icons/ui_heart.png")
	hearts[1].texture = Art.tex("icons/ui_heart_wounded.png" if p.wounds >= 1 else "icons/ui_heart.png")
	hearts[1].modulate.a = 0.45 if p.wounds >= 1 else 1.0
	var dw: float = dread_fill.get_parent().size.x
	dread_fill.size = Vector2(dw * clampf(run.threat / 100.0, 0.0, 1.0), _px(4))
	var sw: float = stamina_fill.get_parent().size.x
	stamina_fill.size = Vector2(sw * p.stamina, _px(4))
	stamina_fill.color = Color(0.62, 0.72, 0.78) if p.stamina > 0.25 else Color(0.8, 0.4, 0.3)
	var line: String = "◆ " + run.map.room_name(p.room_id)
	if AbyssArena.contains(p.global_position) and run.view.abyss and run.view.abyss.running:
		line = "◆ THE ABYSS — %d s" % int(ceil(AbyssArena.DURATION - run.view.abyss.t))
	if str(run.get("difficulty")) != "normal":
		line += "  ·  " + Defs.difficulty_name(str(run.get("difficulty")))
	if run.multiplayer_match:
		var parts: Array = []
		for h in run.hunters:
			if h != p:
				parts.append("%s %s" % [h.display_name, "†" if h.dead else ("♥" if h.wounds >= 1 else "♥♥")])
		line += "   ·   " + "  ".join(parts)
	status_line.text = line
	var eq = _equipment
	_update_info(eq, p)
	highlighter.target = eq.interact_pos if not p.dead and not spectating else Vector2.INF
	highlighter.near = eq.near_items if not p.dead and not spectating else []
	if run.is_harbinger() and run.sigils_lit() != _sigils_seen:
		_sigils_seen = run.sigils_lit()
		refresh()
	_update_notifications(delta, p)
	_picker_t -= delta
	suspect_picker.modulate.a = clampf(_picker_t * 2.0, 0.0, 1.0)
	var target_hunt := 0.0
	if _hunting:
		target_hunt = 0.3 + 0.12 * sin(_t * 6.0)
	hunt_overlay.modulate.a = move_toward(hunt_overlay.modulate.a, target_hunt, delta * 2.0)
	hunt_label.modulate.a = (0.55 + 0.2 * sin(_t * 7.0)) if _hunting else move_toward(hunt_label.modulate.a, 0.0, delta * 3.0)
	wound_overlay.color.a = move_toward(wound_overlay.color.a, 0.18 if p.wounds >= 1 and p.invuln <= 0.0 and not p.dead else 0.0, delta * 0.8)
	if _shake > 0.0:
		_shake -= delta
		run.camera.offset = Vector2(randf_range(-6, 6), randf_range(-6, 6)) * _shake
	else:
		run.camera.offset = Vector2.ZERO
	if spectating:
		_update_spectating()
	for key in _toast_recent.keys():
		_toast_recent[key] -= delta
		if _toast_recent[key] <= 0.0:
			_toast_recent.erase(key)

## Top-centre information: the live reading first, then the contextual prompt.
func _update_info(eq, p) -> void:
	needle_gauge.visible = not p.dead and eq.current() == "emf"
	needle_gauge.level = eq.needle
	if p.dead:
		info_main.text = "—"
		info_sub.text = ""
		hold_bar.modulate.a = 0.0
		return
	if eq.reading != "":
		info_main.text = eq.reading
		var col: Color = eq.reading_color
		col.a = 1.0 if eq.reading_active else 0.7
		info_main.add_theme_color_override("font_color", col)
		info_sub.text = eq.hint
	else:
		info_main.text = eq.hint.to_upper()
		info_main.add_theme_color_override("font_color", Art.GOLD)
		# Object actions get their own prompt beside the object; rites stay here.
		info_sub.text = eq.prompt if eq.prompt.begins_with("[V]") else ""
	_update_prompt_chip(eq, p)
	var hp: float = eq.hold_progress()
	hold_bar.value = hp
	hold_bar.modulate.a = 1.0 if hp > 0.0 else 0.0

## A small chip beside the highlighted object: icon + "E / SPACE — Open Door".
func _build_prompt_chip(root: Control) -> void:
	prompt_chip = PanelContainer.new()
	var sb := _panel_style()
	sb.border_color = Color(Art.GOLD.r, Art.GOLD.g, Art.GOLD.b, 0.85)
	sb.content_margin_top = _px(3)
	sb.content_margin_bottom = _px(3)
	prompt_chip.add_theme_stylebox_override("panel", sb)
	prompt_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_chip.visible = false
	root.add_child(prompt_chip)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", _px(6))
	prompt_chip.add_child(h)
	prompt_icon = Art.icon_rect("icons/ui_quill.png", _px(22))
	h.add_child(prompt_icon)
	prompt_text = _outlined("", _px(13), BONE, Art.font_heading, 3)
	h.add_child(prompt_text)

func _update_prompt_chip(eq, p) -> void:
	var show: bool = not p.dead and not spectating and eq.interact_pos != Vector2.INF and eq.prompt.begins_with("E /")
	prompt_chip.visible = show
	if not show:
		return
	if prompt_text.text != eq.prompt:
		prompt_text.text = eq.prompt
		prompt_icon.texture = Art.tex(eq.interact_icon if eq.interact_icon != "" else "icons/ui_quill.png")
		prompt_chip.reset_size()
	var vs := get_viewport().get_visible_rect().size
	var at: Vector2 = get_viewport().get_canvas_transform() * eq.interact_pos
	var sz := prompt_chip.size
	var pos := at + Vector2(-sz.x * 0.5, -sz.y - 34.0)
	pos.x = clampf(pos.x, 190.0, vs.x - 190.0 - sz.x)
	pos.y = clampf(pos.y, 200.0, vs.y - 170.0 - sz.y)
	prompt_chip.position = pos

func _update_notifications(delta: float, p) -> void:
	var y := -58.0
	for card in _notifications.duplicate():
		if not is_instance_valid(card):
			_notifications.erase(card)
			continue
		var age: float = card.get_meta("age") + delta
		card.set_meta("age", age)
		var sk: float = card.get_meta("target_scale")
		var panel: Control = card.get_child(0)
		var size: Vector2 = panel.size * sk
		card.position = card.position.lerp(p.global_position + Vector2(-size.x * 0.5, y - size.y), clampf(delta * 14.0, 0.0, 1.0)) if age > 0.05 else p.global_position + Vector2(-size.x * 0.5, y - size.y)
		y -= size.y + 4.0
		if age > 3.4:
			card.modulate.a = move_toward(card.modulate.a, 0.0, delta * 2.0)
			if card.modulate.a <= 0.01:
				_notifications.erase(card)
				card.queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if help_panel.visible:
			help_panel.visible = false
		else:
			toggle_pause()
	elif event.is_action_pressed("help"):
		help_panel.visible = not help_panel.visible
	elif spectating and (event.is_action_pressed("use") or event.is_action_pressed("cycle")):
		spectate_index += 1

func toggle_pause() -> void:
	if run.state != "playing":
		return
	pause_panel.visible = not pause_panel.visible
	run.set_paused(pause_panel.visible)

# --- Spectating ------------------------------------------------------------------------------

func begin_spectating() -> void:
	spectating = true
	spectate_label.visible = true

func _update_spectating() -> void:
	var alive: Array = run.hunters.filter(func(h): return not h.dead)
	if alive.is_empty():
		spectate_label.text = "All hunters have fallen"
		return
	var target = alive[spectate_index % alive.size()]
	if run.camera.get_parent() != target:
		run.camera.reparent(target, false)
		run.camera.position = Vector2.ZERO
		run.camera.reset_smoothing()
	run._apply_camera_limits(target.global_position)
	run.view.set_basement_view(run.map.floor_at(target.global_position) < 0)
	spectate_label.text = "Spectating %s  ·  click to switch" % target.display_name

# --- Messages ----------------------------------------------------------------------------------

func set_hunting(on: bool) -> void:
	_hunting = on

func wound() -> void:
	wound_overlay.color.a = 0.55
	shake(0.5)

func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

## Small unobtrusive notification (bottom-left). Identical messages within 4 s are dropped.
func toast(text: String, icon: String = "", quiet: bool = false) -> void:
	if _toast_recent.has(text):
		return
	_toast_recent[text] = 4.0
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Art.parchment_panel())
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	if icon != "":
		h.add_child(Art.icon_rect(icon, _px(22)))
	h.add_child(Art.label(text, _px(16), INK))
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
	tw.tween_property(big_box, "modulate:a", 1.0, 0.35)
	tw.tween_interval(dur)
	tw.tween_property(big_box, "modulate:a", 0.0, 0.8)
