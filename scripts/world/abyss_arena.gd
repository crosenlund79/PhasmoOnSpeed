class_name AbyssArena
extends Node2D
## Abyssal Hell: a small trap-filled realm far outside the house, where an
## Abyssal portal sends whoever stood in its room for a minute. The trap
## timeline is a pure function of (seed, seconds since the portal opened), so
## the host (which applies damage), clients and replays all draw the same traps.
##
## Traps, each with a readable warning before it hurts:
##   spikes — a scattered set of floor tiles glow, then spikes punch up
##   jets   — a whole row or column glows, then a sheet of hellfire roars along it
##   hands  — three grasping shadow hands sweep slow, visible loops

const ORIGIN := Vector2(-2400, -2400)     # outside every house (houses start at 0,0)
const COLS := 20
const ROWS := 12
const C := 32.0
const DURATION := 60.0
const SPIKE_PERIOD := 2.0
const SPIKE_WARN := 0.9
const SPIKE_ACTIVE := 0.6
const JET_PERIOD := 3.2
const JET_WARN := 1.0
const JET_ACTIVE := 0.8
const HAND_RADIUS := 18.0

var seed_value := 1
var t := 0.0
var running := false
var clock: Callable   # optional: replays drive the timeline from replay time instead

static func rect() -> Rect2:
	return Rect2(ORIGIN, Vector2(COLS, ROWS) * C)

static func contains(pos: Vector2) -> bool:
	return rect().grow(40.0).has_point(pos)

## Where the k-th occupant or the entity drifts, slowly, by the far (right) wall —
## clear of the hunters' spawn, visible to them, harmless.
static func far_point(k: int, at: float) -> Vector2:
	var y := (2.0 + (k % 4) * 2.6) * C + sin(at * 0.7 + k * 1.9) * C * 0.6
	return ORIGIN + Vector2((COLS - 5.0) * C + sin(at * 0.5 + k) * C * 0.6, y)

## Spawn points for k arrivals, spread along the left wall.
static func spawn_point(k: int) -> Vector2:
	return ORIGIN + Vector2(1.5 * C, (2.5 + (k % 4) * 2.4) * C)

func build(with_collision: bool) -> void:
	z_index = -2
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED   # readable in any darkness
	material = m
	for k in 3:
		var l := PointLight2D.new()
		l.texture = Art.tex("lights/soft.png")
		l.color = Color(0.7, 0.3, 1.0)
		l.energy = 0.9
		l.texture_scale = 1.6
		l.position = ORIGIN + Vector2((4 + k * 6) * C, ROWS * C * 0.5)
		add_child(l)
	if with_collision:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var r := rect()
		for wall in [Rect2(r.position - Vector2(C, C), Vector2(r.size.x + 2 * C, C)), Rect2(Vector2(r.position.x - C, r.end.y), Vector2(r.size.x + 2 * C, C)),
				Rect2(r.position - Vector2(C, 0), Vector2(C, r.size.y)), Rect2(Vector2(r.end.x, r.position.y), Vector2(C, r.size.y))]:
			var cs := CollisionShape2D.new()
			var sh := RectangleShape2D.new()
			sh.size = wall.size
			cs.shape = sh
			cs.position = wall.get_center()
			body.add_child(cs)
		add_child(body)
	visible = false

func open(p_seed: int) -> void:
	seed_value = p_seed
	t = 0.0
	running = true
	visible = true

func close() -> void:
	running = false
	visible = false

func _process(delta: float) -> void:
	if running:
		t = float(clock.call()) if clock.is_valid() else t + delta
		queue_redraw()

# --- The trap timeline -------------------------------------------------------------------

func _h(a: int, b: int, c: int) -> float:
	return float(hash([seed_value, a, b, c]) % 10007) / 10007.0

## Spike tiles of the current wave, with "warn" or "active" (or "" when idle).
func spike_state(at: float) -> Array:
	var wave := int(floor(at / SPIKE_PERIOD))
	var ph := fmod(at, SPIKE_PERIOD)
	var phase := "warn" if ph < SPIKE_WARN else ("active" if ph < SPIKE_WARN + SPIKE_ACTIVE else "")
	var cells: Array = []
	if phase != "" and at > 1.5:   # a moment to find your feet first
		for y in ROWS:
			for x in range(2, COLS):
				if _h(wave, x, y) < 0.3:
					cells.append(Vector2i(x, y))
	return [phase, cells]

## The fire lane of the current jet: [phase, is_row, index].
func jet_state(at: float) -> Array:
	var n := int(floor(at / JET_PERIOD))
	var ph := fmod(at, JET_PERIOD)
	var phase := "warn" if ph < JET_WARN else ("active" if ph < JET_WARN + JET_ACTIVE else "")
	if at < 3.0:
		phase = ""
	var is_row := _h(n, 7, 7) < 0.5
	var idx := int(_h(n, 9, 9) * (ROWS if is_row else COLS))
	return [phase, is_row, idx]

func hand_positions(at: float) -> Array:
	var out: Array = []
	var r := rect()
	for k in 3:
		var a := 0.45 + 0.13 * k
		var b := 0.61 + 0.09 * k
		var px := r.position.x + r.size.x * (0.55 + 0.4 * sin(at * a + k * 2.1))
		var py := r.position.y + r.size.y * (0.5 + 0.4 * sin(at * b + k * 1.3))
		out.append(Vector2(px, py))
	return out

## What would hurt something standing at pos right now ("" if nothing).
func hazard_at(pos: Vector2) -> String:
	if not running:
		return ""
	var cell := Vector2i(floor((pos - ORIGIN) / C))
	var sp := spike_state(t)
	if sp[0] == "active" and cell in sp[1]:
		return "spikes"
	var j := jet_state(t)
	if j[0] == "active" and ((j[1] and cell.y == j[2]) or (not j[1] and cell.x == j[2])):
		return "hellfire jet"
	for hp: Vector2 in hand_positions(t):
		if hp.distance_to(pos) < HAND_RADIUS + 10.0:
			return "grasping hands"
	return ""

# --- Drawing -------------------------------------------------------------------------------

func _draw() -> void:
	if not running:
		return
	var r := rect()
	draw_rect(r.grow(700.0), Color(0.03, 0.0, 0.04))   # the void around it
	draw_rect(r, Color(0.13, 0.04, 0.16))
	for y in ROWS:
		for x in COLS:
			var v := _h(x, y, 1)
			draw_rect(Rect2(ORIGIN + Vector2(x, y) * C, Vector2(C, C)).grow(-1.0), Color(0.16 + v * 0.06, 0.05, 0.2 + v * 0.07))
	# Cracks of light in the floor, slowly pulsing.
	for k in 14:
		var a := ORIGIN + Vector2(_h(k, 2, 3) * r.size.x, _h(k, 3, 4) * r.size.y)
		var b := a + Vector2(_h(k, 5, 6) - 0.5, _h(k, 6, 7) - 0.5) * 120.0
		draw_line(a, b, Color(0.8, 0.3, 1.0, 0.35 + 0.25 * sin(t * 2.0 + k)), 2.0)
	draw_rect(r, Color(0.65, 0.25, 0.9), false, 4.0)
	var sp := spike_state(t)
	for c: Vector2i in sp[1]:
		var cr := Rect2(ORIGIN + Vector2(c) * C, Vector2(C, C)).grow(-3.0)
		if sp[0] == "warn":
			draw_rect(cr, Color(0.9, 0.2, 0.3, 0.25 + 0.25 * sin(t * 20.0)))
			draw_rect(cr, Color(1.0, 0.35, 0.4, 0.9), false, 2.0)
		else:
			for i in 3:
				var base := cr.position + Vector2(5 + i * 9, 24)
				draw_colored_polygon(PackedVector2Array([base + Vector2(-4, 0), base + Vector2(4, 0), base + Vector2(0, -18)]), Color(0.88, 0.85, 0.92))
			draw_rect(cr, Color(0.7, 0.05, 0.1, 0.5))
	var j := jet_state(t)
	if j[0] != "":
		var lane := Rect2(Vector2(r.position.x, ORIGIN.y + j[2] * C), Vector2(r.size.x, C)) if j[1] else Rect2(Vector2(ORIGIN.x + j[2] * C, r.position.y), Vector2(C, r.size.y))
		if j[0] == "warn":
			draw_rect(lane, Color(1.0, 0.45, 0.1, 0.18 + 0.15 * sin(t * 24.0)))
			draw_rect(lane, Color(1.0, 0.55, 0.2, 0.85), false, 2.0)
		else:
			draw_rect(lane, Color(1.0, 0.45, 0.08, 0.8))
			draw_rect(lane.grow(-6.0), Color(1.0, 0.9, 0.5, 0.85))
	for hp: Vector2 in hand_positions(t):
		draw_circle(hp, HAND_RADIUS + 8.0, Color(0.6, 0.2, 0.9, 0.25))
		draw_circle(hp, HAND_RADIUS, Color(0.04, 0.0, 0.05, 0.95))
		for f in 5:
			var ang := -PI * 0.5 + (f - 2) * 0.38 + sin(t * 6.0 + f) * 0.15
			draw_line(hp, hp + Vector2.from_angle(ang) * (HAND_RADIUS + 12.0), Color(0.04, 0.0, 0.05), 4.0, true)
	var left := maxf(0.0, DURATION - t)
	draw_string(ThemeDB.fallback_font, ORIGIN + Vector2(r.size.x * 0.5 - 60, -14), "THE ABYSS  %d" % int(ceil(left)), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.85, 0.6, 1.0))
