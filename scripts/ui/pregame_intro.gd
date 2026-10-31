class_name PregameIntro
extends CanvasLayer
## The tabletop moment before every investigation: the location cards are laid
## out, gathered and shuffled, one is turned over — the house already chosen —
## and the difficulty die rolls to the difficulty already chosen. It only ever
## SHOWS a resolved setup; it never picks or changes anything. The entity is
## never shown.
##
## Game puts it on top of the freshly built run, which stays frozen underneath
## until `finished`. Solo: click / Space / E / Esc jumps to the end. In a match
## every peer holds for the same fixed time (skipping only fast-forwards the
## animation), so the hunt begins for everyone together.

signal finished

## Timeline (seconds).
const T_FLIP := 0.75        # the face-up spread is turned face down
const T_GATHER := 0.95      # …gathered into a deck
const T_SHUFFLE := 1.2      # …riffled twice
const T_DRAW := 1.8         # the top card slides out
const T_REVEAL := 2.05      # …and is turned over
const T_DIE := 2.15         # the die is thrown
const T_LAND := 3.0         # …and comes to rest
const T_HOLD := 3.45        # fade out begins
const DURATION := 3.8       # fixed total (a match always waits this long)

const CARD := Vector2(132, 190)
## Pip colours per difficulty (Defs.DIFFICULTIES order).
const DIE_INK := {"beginner": Color(0.25, 0.42, 0.3), "normal": Color(0.1, 0.08, 0.07),
	"nightmare": Color(0.62, 0.06, 0.06), "hellbound": Color(0.85, 0.36, 0.06), "abyssal": Color(0.45, 0.14, 0.62)}

var house := ""
var difficulty := ""
var blood_moon := false
var multiplayer_match := false
var cards: Array = []        # house ids, in Game.house_ids order
var t := 0.0
var skipped := false
var _done := false
var _plans := {}             # house id -> Array of [Rect2, Color] (ground-floor plan)
var _root: Control
var _table: Control
var _hint: Label

## What the presentation will land on — exactly the resolved values given.
static func landing(house_ids: Array, p_house: String, p_difficulty: String) -> Dictionary:
	return {"card": house_ids.find(p_house), "house": p_house,
		"die_face": Defs.DIFFICULTIES.find(p_difficulty) + 1, "difficulty": p_difficulty}

func setup(p_house: String, p_difficulty: String, p_blood_moon: bool, p_multiplayer: bool) -> void:
	house = p_house
	difficulty = p_difficulty
	blood_moon = p_blood_moon
	multiplayer_match = p_multiplayer
	cards = Game.house_ids.duplicate()
	if not cards.has(house):
		cards.append(house)

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	for id in cards:
		_plans[id] = _plan_of(id)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			skip())
	add_child(_root)
	var floor_rect := TextureRect.new()
	floor_rect.texture = Art.tex("floors/wood_dark.png")
	floor_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	floor_rect.stretch_mode = TextureRect.STRETCH_TILE
	floor_rect.modulate = Color(0.36, 0.33, 0.36)
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(floor_rect)
	var warm := TextureRect.new()
	warm.texture = Art.tex("lights/soft.png")
	warm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	warm.set_anchors_preset(Control.PRESET_FULL_RECT)
	warm.offset_left = 120
	warm.offset_right = -120
	warm.offset_top = -60
	warm.offset_bottom = 60
	warm.modulate = Color(1.0, 0.7, 0.4, 0.3)
	warm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(warm)
	_table = Control.new()
	_table.set_anchors_preset(Control.PRESET_FULL_RECT)
	_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table.draw.connect(_draw_table)
	_root.add_child(_table)
	var vig := TextureRect.new()
	vig.texture = Art.tex("ui/vignette.png")
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(vig)
	_hint = Art.label("The hunt begins for everyone together…" if multiplayer_match else "Click, Space or Esc to skip", 15, Color(0.75, 0.7, 0.6), Art.font_italic)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -44
	_hint.offset_left = -300
	_hint.offset_right = 300
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 4)
	_root.add_child(_hint)
	Sfx.play("ui_hover", -6.0, 0.8, 0.0)

func _process(delta: float) -> void:
	if _done:
		return
	var before := t
	t += delta
	_cues(before, t)
	if skipped and not multiplayer_match:
		t = maxf(t, T_HOLD)

	_root.modulate.a = clampf(1.0 - (t - T_HOLD) / (DURATION - T_HOLD), 0.0, 1.0)
	_table.queue_redraw()
	if t >= DURATION:
		_done = true
		finished.emit()
		queue_free()

## Fast-forward to the result. In a match only the view jumps; the wait stays.
func skip() -> void:
	if skipped:
		return
	skipped = true
	if multiplayer_match:
		_hint.text = "Waiting for the other hunters…"

func _input(event: InputEvent) -> void:
	if _done:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_E, KEY_ENTER]:
			skip()
		get_viewport().set_input_as_handled()   # nothing reaches the frozen run underneath

## The time the picture shows (skipping in a match shows the end early).
func _view_t() -> float:
	return maxf(t, T_LAND + 0.2) if skipped else t

func _cues(a: float, b: float) -> void:
	if skipped:
		return
	for i in cards.size():
		var s := _deal_start(i)
		if a < s and b >= s:
			Sfx.play("ui_hover", -10.0, 0.9 + 0.04 * i, 0.0)
	for c in [[T_FLIP, "ui_hover", -8.0, 0.7], [T_SHUFFLE + 0.05, "ui_click", -10.0, 0.6], [T_SHUFFLE + 0.35, "ui_click", -10.0, 0.65],
			[T_REVEAL, "ui_click", -4.0, 0.8], [T_DIE + (T_LAND - T_DIE) / 3.0, "ui_click", -6.0, 0.55],
			[T_DIE + (T_LAND - T_DIE) * 2.0 / 3.0, "ui_click", -8.0, 0.6], [T_LAND, "ui_click", -4.0, 0.5]]:
		if a < c[0] and b >= c[0]:
			Sfx.play(c[1], c[2], c[3], 0.0)
	if blood_moon and a < T_LAND + 0.1 and b >= T_LAND + 0.1:
		Sfx.play("clock_toll", -12.0, 0.8, 0.0)

# --- Layout ------------------------------------------------------------------------------

func _deal_start(i: int) -> float:
	return 0.05 + i * 0.05

func _size() -> Vector2:
	return _table.size if _table and _table.size.x > 0 else Vector2(1600, 900)

func _scale() -> float:
	var s := _size()
	return clampf(minf((s.x - 120.0) / (cards.size() * (CARD.x + 26.0)), s.y / 900.0), 0.55, 1.15)

func _spread_pos(i: int) -> Vector2:
	var s := _size()
	var k := _scale()
	var off := i - (cards.size() - 1) * 0.5
	return Vector2(s.x * 0.5 + off * (CARD.x + 26.0) * k, s.y * 0.47 + absf(off) * absf(off) * 3.0 * k)

func _deck_pos() -> Vector2:
	var s := _size()
	return Vector2(s.x * 0.5 - 250.0 * _scale(), s.y * 0.5)

func _die_pos() -> Vector2:
	var s := _size()
	return Vector2(s.x * 0.5 + 250.0 * _scale(), s.y * 0.52)

static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

## A card's pose at time `vt`: [position, rotation, scale, flip (0 face … 1 back)].
func _card_pose(i: int, vt: float) -> Array:
	var k := _scale()
	var n := cards.size()
	var spread := _spread_pos(i)
	var spread_rot := (i - (n - 1) * 0.5) * 0.035
	var deck := _deck_pos() + Vector2(-i * 0.8, -i * 1.2) * k
	var deck_rot := sin(i * 2.3) * 0.03
	if vt < T_FLIP:
		var p := _ease((vt - _deal_start(i)) / 0.32)
		var from := Vector2(_size().x * 0.5, _size().y + CARD.y * k)
		return [from.lerp(spread, p), lerpf(0.6, spread_rot, p), k, 0.0]
	if vt < T_GATHER:
		var f := clampf((vt - T_FLIP) / (T_GATHER - T_FLIP - 0.02), 0.0, 1.0)
		return [spread, spread_rot, k, f]
	if vt < T_SHUFFLE:
		var p := _ease((vt - T_GATHER) / (T_SHUFFLE - T_GATHER))
		return [spread.lerp(deck, p), lerpf(spread_rot, deck_rot, p), k, 1.0]
	if vt < T_DRAW or i != n - 1:
		var pos := deck
		var rot := deck_rot
		if vt < T_DRAW:
			var q := fmod((vt - T_SHUFFLE) / ((T_DRAW - T_SHUFFLE) * 0.5), 1.0)
			var side := -1.0 if i % 2 == 0 else 1.0
			pos += Vector2(side * sin(q * PI) * 70.0 * k, -sin(q * PI) * 10.0 * k)
			rot += side * sin(q * PI) * 0.12
		return [pos, rot, k, 1.0]
	# The top card: drawn out, enlarged and turned over.
	var reveal := _deck_pos() + Vector2(0, -6) * k
	var p := _ease((vt - T_DRAW) / (T_REVEAL - T_DRAW))
	var f := 1.0 - clampf((vt - T_REVEAL) / 0.28, 0.0, 1.0)
	return [deck.lerp(reveal, p) + Vector2(0, -sin(p * PI) * 40.0 * k), lerpf(deck_rot, 0.0, p), k * lerpf(1.0, 1.3, p), f]

## Which house a card shows: the spread is every location in order; once
## gathered, the card that is turned over is always the resolved house.
func _card_house(i: int, vt: float) -> String:
	if vt >= T_DRAW and i == cards.size() - 1:
		return house
	return cards[i]

func revealed_house() -> String:
	return _card_house(cards.size() - 1, DURATION)

func die_difficulty(vt: float) -> String:
	if vt >= T_LAND:
		return difficulty
	return Defs.DIFFICULTIES[int(vt * 13.0) % Defs.DIFFICULTIES.size()]

# --- Drawing -----------------------------------------------------------------------------

func _draw_table() -> void:
	var vt := _view_t()
	var n := cards.size()
	var heading := "The cards are dealt…"
	if vt >= T_GATHER:
		heading = "…shuffled…"
	if vt >= T_REVEAL:
		heading = "The case is drawn"
	_text(heading, Vector2(_size().x * 0.5, _size().y * 0.12), 40, Color(0.93, 0.85, 0.65), Art.font_heading)
	if vt >= T_REVEAL:
		# Candle-warm light pools under the turned card (and the die once it rests).
		var a := clampf((vt - T_REVEAL) / 0.4, 0.0, 1.0)
		_glow(_deck_pos(), 520.0 * _scale(), Color(1.0, 0.75, 0.4, 0.45 * a))
		if vt >= T_LAND:
			var g: Color = DIE_INK.get(difficulty, Art.INK)
			g = g.lightened(0.4) if difficulty != "normal" else Color(1.0, 0.8, 0.5)
			g.a = 0.4 * clampf((vt - T_LAND) / 0.3, 0.0, 1.0)
			_glow(_die_pos(), 420.0 * _scale(), g)
	for i in n:
		if vt < _deal_start(i):
			continue
		var pose := _card_pose(i, vt)
		_draw_card(_card_house(i, vt), pose[0], pose[1], pose[2], pose[3])
	if vt >= T_REVEAL + 0.2:
		var a := clampf((vt - T_REVEAL - 0.2) / 0.3, 0.0, 1.0)
		var nm: String = Game.house(house).get("name", house)
		_text(nm, _deck_pos() + Vector2(0, CARD.y * 0.5 * 1.3 * _scale() + 36), 28, Color(0.95, 0.88, 0.7, a), Art.font_heading)
	if vt >= T_DIE:
		_draw_die(vt)
	_table.draw_set_transform_matrix(Transform2D.IDENTITY)

func _glow(at: Vector2, size: float, col: Color) -> void:
	_table.draw_set_transform_matrix(Transform2D.IDENTITY)
	_table.draw_texture_rect(Art.tex("lights/soft.png"), Rect2(at - Vector2(size, size) * 0.5, Vector2(size, size)), false, col)

func _text(s: String, pos: Vector2, size: int, col: Color, font: Font) -> void:
	_table.draw_set_transform_matrix(Transform2D.IDENTITY)
	var w := 900.0
	var p := pos + Vector2(-w * 0.5, size * 0.35)
	_table.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_CENTER, w, size, 8, Color(0, 0, 0, col.a))
	_table.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_CENTER, w, size, col)

func _draw_card(id: String, pos: Vector2, rot: float, k: float, flip: float) -> void:
	var sx := absf(cos(flip * PI))
	var face := flip < 0.5
	var r := Rect2(-CARD * 0.5, CARD)
	_table.draw_set_transform(pos + Vector2(6, 9) * k, rot, Vector2(maxf(sx, 0.02) * k, k))
	_table.draw_rect(r.grow(2), Color(0, 0, 0, 0.45))
	_table.draw_set_transform(pos, rot, Vector2(maxf(sx, 0.02) * k, k))
	if not face:
		_table.draw_style_box(Art.stylebox("ui/panel_dark.png", 24, Color(0.12, 0.1, 0.1), Art.GOLD), r)
		var c := Vector2.ZERO
		_table.draw_arc(c, 34, 0, TAU, 40, Art.GOLD, 2.0, true)
		_table.draw_arc(c, 42, 0, TAU, 40, Color(Art.GOLD, 0.5), 1.0, true)
		var star := PackedVector2Array()
		for j in 6:
			var a := -PI * 0.5 + j * TAU * 2.0 / 5.0
			star.append(c + Vector2(cos(a), sin(a)) * 30.0)
		_table.draw_polyline(star, Art.GOLD, 1.6, true)
		_table.draw_rect(r.grow(-12), Color(Art.GOLD, 0.35), false, 1.0)
		return
	_table.draw_style_box(Art.parchment_panel(), r)
	var nm: String = Game.house(id).get("name", id)
	_table.draw_multiline_string(Art.font_heading, Vector2(r.position.x + 10, r.position.y + 30), nm, HORIZONTAL_ALIGNMENT_CENTER, CARD.x - 20, 15, 2, Art.INK)
	var plan_r := Rect2(r.position.x + 14, r.position.y + 66, CARD.x - 28, CARD.y - 96)
	_table.draw_rect(plan_r, Color(0.2, 0.17, 0.14, 0.18))
	_draw_plan(id, plan_r.grow(-4))
	_table.draw_rect(plan_r, Color(0.16, 0.11, 0.07, 0.8), false, 1.2)
	_table.draw_texture_rect(Art.tex("icons/ui_house.png"), Rect2(-11, r.end.y - 30, 22, 22), false, Color(1, 1, 1, 0.85))

## A tiny ground-floor plan from the house data, inked onto the card.
func _plan_of(id: String) -> Array:
	var rooms: Array = Game.house(id).get("rooms", [])
	var out: Array = []
	var bb := Rect2()
	var first := true
	for room in rooms:
		if int(room.get("level", 0)) != 0:
			continue
		var c := _floor_colour(str(room.get("floor", "")), bool(room.get("outdoor", false)))
		for rr in room.get("rects", []):
			var rect := Rect2(rr[0], rr[1], rr[2], rr[3])
			out.append([rect, c])
			bb = rect if first else bb.merge(rect)
			first = false
	return [bb, out]

func _floor_colour(f: String, outdoor: bool) -> Color:
	if outdoor:
		return Color(0.42, 0.5, 0.36, 0.55) if f in ["grass", "dirt", "gravel"] else Color(0.5, 0.5, 0.48, 0.5)
	if f.begins_with("carpet"):
		return Color(0.55, 0.22, 0.2, 0.75)
	if f.begins_with("tile") or f == "stone":
		return Color(0.6, 0.6, 0.58, 0.75)
	return Color(0.52, 0.36, 0.22, 0.75)

func _draw_plan(id: String, into: Rect2) -> void:
	var plan: Array = _plans.get(id, [Rect2(), []])
	var bb: Rect2 = plan[0]
	if bb.size.x <= 0 or bb.size.y <= 0:
		return
	var s := minf(into.size.x / bb.size.x, into.size.y / bb.size.y)
	var off := into.position + (into.size - bb.size * s) * 0.5
	for e in plan[1]:
		var rr: Rect2 = e[0]
		var q := Rect2(off + (rr.position - bb.position) * s, rr.size * s)
		_table.draw_rect(q, e[1])
		_table.draw_rect(q, Color(0.12, 0.08, 0.05, 0.7), false, 0.8)

func _draw_die(vt: float) -> void:
	var k := _scale()
	var end := _die_pos()
	var p := clampf((vt - T_DIE) / (T_LAND - T_DIE), 0.0, 1.0)
	var start := Vector2(_size().x + 120.0, end.y - 120.0 * k)
	var pos := start.lerp(end, _ease(p * 1.1))
	pos.y -= absf(sin(p * PI * 3.0)) * 110.0 * k * (1.0 - p)
	var rot := (1.0 - p) * (1.0 - p) * 13.0

	var d := die_difficulty(vt)
	var sz := 106.0
	_table.draw_set_transform(end + Vector2(8, 12) * k, 0.0, Vector2(k, k * 0.5))
	_table.draw_circle(Vector2.ZERO, sz * 0.62 * (0.6 + 0.4 * p), Color(0, 0, 0, 0.35 * p))
	_table.draw_set_transform(pos, rot, Vector2(k, k))
	var h := sz * 0.5
	var top := PackedVector2Array([Vector2(-h, -h), Vector2(-h + 16, -h - 16), Vector2(h + 16, -h - 16), Vector2(h, -h)])
	var side := PackedVector2Array([Vector2(h, -h), Vector2(h + 16, -h - 16), Vector2(h + 16, h - 16), Vector2(h, h)])
	_table.draw_colored_polygon(top, Color(0.93, 0.89, 0.8))
	_table.draw_colored_polygon(side, Color(0.62, 0.56, 0.46))
	var face := Rect2(-h, -h, sz, sz)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.86, 0.8, 0.68)
	sb.set_corner_radius_all(10)
	sb.border_color = Art.INK
	sb.set_border_width_all(3)
	_table.draw_style_box(sb, face)
	for poly in [top, side]:
		var closed: PackedVector2Array = poly.duplicate()
		closed.append(poly[0])
		_table.draw_polyline(closed, Art.INK, 2.5, true)
	var ink: Color = DIE_INK.get(d, Art.INK)
	var pips: int = Defs.DIFFICULTIES.find(d) + 1
	for pp in _pips(pips):
		_table.draw_circle(pp * h * 0.55, 8.5, ink)
		_table.draw_circle(pp * h * 0.55 + Vector2(-2.5, -2.5), 2.6, Color(1, 1, 1, 0.25))
	_table.draw_set_transform_matrix(Transform2D.IDENTITY)
	if vt >= T_LAND:
		var a := clampf((vt - T_LAND) / 0.25, 0.0, 1.0)
		var col: Color = DIE_INK.get(d, Art.INK).lightened(0.55) if d != "normal" else Color(0.95, 0.88, 0.7)
		col.a = a
		_text(Defs.difficulty_name(d), end + Vector2(0, sz * 0.5 * k + 50), 30, col, Art.font_heading)
		if blood_moon:
			_text("A Blood Moon rises", end + Vector2(0, sz * 0.5 * k + 88), 20, Color(0.9, 0.2, 0.15, a), Art.font_italic)

static func _pips(n: int) -> Array:
	match n:
		1: return [Vector2.ZERO]
		2: return [Vector2(-1, -1), Vector2(1, 1)]
		3: return [Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)]
		4: return [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
		_: return [Vector2(-1, -1), Vector2(1, -1), Vector2.ZERO, Vector2(-1, 1), Vector2(1, 1)]
