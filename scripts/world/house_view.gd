class_name HouseView
extends Node2D
## Visual construction of a house from a HouseMap: textured floors, inked walls,
## doors, furniture sprites, lights and (optionally) collision and occluders.
## Used by live runs and by the replay viewer (without collision).

const C := Defs.CELL
const ART_SCALE := 0.5   # world art is authored at 64 px per 32 px cell
const DARKNESS := Color(0.20, 0.21, 0.29)
const DARKNESS_HUNT := Color(0.13, 0.10, 0.14)
const DARKNESS_HARBINGER := Color(0.12, 0.13, 0.19)

var map: HouseMap
var modulate_node: CanvasModulate
var floor_layer: Node2D
var under_layer: Node2D
var furniture_layer: Node2D
var decal_layer: Node2D        # evidence decals, placed items
var actor_layer: Node2D
var overlay_layer: Node2D
var lights: Array = []         # [{light: PointLight2D, base: float, flicker: float, kind}]
var mirrors: Array = []        # [{furniture, sprite, overlay: Sprite2D}]
var _flicker_time := 0.0
var _flicker_strength := 0.0
var _t := 0.0
var _darkness := DARKNESS

func build(m: HouseMap, with_collision: bool, with_occluders: bool = true) -> void:
	map = m
	modulate_node = CanvasModulate.new()
	modulate_node.color = DARKNESS
	add_child(modulate_node)
	floor_layer = _layer("Floors", -10)
	under_layer = _layer("Rugs", -8)
	var walls := WallDrawer.new()
	walls.map = m
	walls.z_index = -6
	add_child(walls)
	decal_layer = _layer("Decals", -5)
	furniture_layer = _layer("Furniture", -4)
	actor_layer = _layer("Actors", 0)
	overlay_layer = _layer("Overlay", 5)
	_build_floors()
	_build_furniture()
	_build_lights()
	if with_collision:
		_build_collision()
	if with_occluders:
		_build_occluders()

func _layer(n: String, z: int) -> Node2D:
	var l := Node2D.new()
	l.name = n
	l.z_index = z
	add_child(l)
	return l

func _build_floors() -> void:
	# One textured polygon per room rect, plus door cells using the adjacent room's floor.
	for r in map.rooms:
		var tex := Art.tex("floors/%s.png" % r["floor"])
		for rect in r["rects"]:
			_floor_poly(tex, Rect2(Vector2(rect[0], rect[1]) * C, Vector2(rect[2], rect[3]) * C))
	for d in map.doors:
		var rid := map.room_at_cell(d)
		var tex := Art.tex("floors/%s.png" % map.room(rid).get("floor", "wood_dark"))
		_floor_poly(tex, Rect2(Vector2(d) * C, Vector2(C, C)))

func _floor_poly(tex: Texture2D, rect: Rect2) -> void:
	var p := Polygon2D.new()
	p.texture = tex
	p.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var pts := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	p.polygon = pts
	var uv := PackedVector2Array()
	for q in pts:
		uv.append(q / ART_SCALE)
	p.uv = uv
	floor_layer.add_child(p)

func _build_furniture() -> void:
	for f in map.furniture:
		var tex := Art.tex("furniture/%s.png" % f["type"])
		var rect: Rect2 = f["rect"]
		var s := Sprite2D.new()
		s.texture = tex
		s.position = rect.get_center()
		s.rotation = f["rot"] * PI * 0.5
		var base: Vector2i = f["def"]["size"]
		var tsize := tex.get_size()
		s.scale = Vector2(base.x * C / tsize.x, base.y * C / tsize.y)
		var layer := under_layer if f["def"].get("under", false) else furniture_layer
		if not f["def"].get("under", false):
			var sh := Sprite2D.new()
			sh.texture = tex
			sh.position = s.position + Vector2(4, 5)
			sh.rotation = s.rotation
			sh.scale = s.scale * 1.02
			sh.modulate = Color(0, 0, 0, 0.45)
			layer.add_child(sh)
		layer.add_child(s)
		f["sprite"] = s
		if f["def"].get("mirror", false):
			var ov := Sprite2D.new()
			ov.position = s.position
			ov.scale = Vector2(0.28, 0.28)
			ov.modulate = Color(1, 1, 1, 0)
			ov.z_index = 1
			furniture_layer.add_child(ov)
			mirrors.append({"furniture": f, "sprite": s, "overlay": ov})

func _light(pos: Vector2, color: Color, energy: float, scale: float, tex_path: String, flicker: float, kind: String, shadows: bool) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = Art.tex(tex_path)
	l.position = pos
	l.color = color
	l.energy = energy
	l.texture_scale = scale
	l.shadow_enabled = shadows
	l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	l.shadow_filter_smooth = 2.0
	l.shadow_color = Color(0, 0, 0, 0.75)
	add_child(l)
	lights.append({"light": l, "base": energy, "flicker": flicker, "kind": kind, "phase": randf() * 10.0})
	return l

func _build_lights() -> void:
	for r in map.rooms:
		var center := map.room_center(r["id"])
		var extent := 0.0
		for c in r["cells"]:
			extent = maxf(extent, center.distance_to(HouseMap.cell_center(c)))
		if r["outdoor"]:
			# Pale moonlight washes over gardens and streets.
			_light(center, Color(0.55, 0.65, 0.9), 0.55, clampf(extent / 180.0, 1.0, 4.0), "lights/soft.png", 0.0, "moon", false)
		elif r["lit"]:
			_light(center, Color(1.0, 0.78, 0.5), 0.75, clampf(extent / 200.0, 0.8, 2.6), "lights/soft.png", 0.03, "room", true)
		else:
			_light(center, Color(0.45, 0.5, 0.7), 0.18, clampf(extent / 220.0, 0.6, 2.2), "lights/soft.png", 0.0, "dim", false)
	for f in map.furniture:
		var lt: String = f["def"].get("light", "")
		var pos: Vector2 = f["rect"].get_center()
		match lt:
			"candle":
				_light(pos, Color(1.0, 0.66, 0.32), 0.9, 0.55, "lights/candle.png", 0.18, "candle", true)
			"lamp":
				_light(pos, Color(1.0, 0.8, 0.55), 0.85, 0.75, "lights/candle.png", 0.05, "lamp", true)
			"hearth":
				_light(pos + Vector2(0, 10).rotated(f["rot"] * PI * 0.5), Color(1.0, 0.5, 0.2), 1.1, 0.9, "lights/candle.png", 0.25, "hearth", true)

func _build_collision() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for rect in _merged_rects(func(c): return map.is_wall(c) or map.at(c) == HouseMap.VOID):
		_add_rect_shape(body, rect)
	var fbody := StaticBody2D.new()
	fbody.collision_layer = 2
	fbody.collision_mask = 0
	add_child(fbody)
	for f in map.furniture:
		if f["def"].get("solid", false):
			_add_rect_shape(fbody, (f["rect"] as Rect2).grow(-3.0))

func _add_rect_shape(body: StaticBody2D, rect: Rect2) -> void:
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = rect.size
	cs.shape = sh
	cs.position = rect.get_center()
	body.add_child(cs)

## Greedy merge of matching cells into horizontal runs then vertical stacks.
func _merged_rects(pred: Callable) -> Array:
	var out: Array = []
	var runs := {}
	for y in range(-1, map.h + 1):
		var x := -1
		while x <= map.w:
			if pred.call(Vector2i(x, y)):
				var x0 := x
				while x <= map.w and pred.call(Vector2i(x, y)):
					x += 1
				var key := Vector2i(x0, x)
				if runs.has(key) and int(runs[key]["y"]) + int(runs[key]["h"]) == y:
					runs[key]["h"] = int(runs[key]["h"]) + 1
				else:
					if runs.has(key):
						out.append(runs[key])
					runs[key] = {"x0": x0, "x1": x, "y": y, "h": 1}
			x += 1
	for k in runs:
		out.append(runs[k])
	var rects: Array = []
	for r in out:
		rects.append(Rect2(Vector2(r["x0"], r["y"]) * C, Vector2(r["x1"] - r["x0"], r["h"]) * C))
	return rects

func _build_occluders() -> void:
	for rect in _merged_rects(func(c): return map.is_wall(c)):
		var occ := LightOccluder2D.new()
		var poly := OccluderPolygon2D.new()
		var r: Rect2 = rect.grow(-2.0)
		poly.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		occ.occluder = poly
		add_child(occ)

# --- Runtime effects --------------------------------------------------------------

func flicker(duration: float, strength: float = 1.0) -> void:
	_flicker_time = maxf(_flicker_time, duration)
	_flicker_strength = maxf(_flicker_strength, strength)

func set_darkness(c: Color, time: float = 1.0) -> void:
	_darkness = c
	create_tween().tween_property(modulate_node, "color", c, time)

func _process(delta: float) -> void:
	_t += delta
	if _flicker_time > 0.0:
		_flicker_time -= delta
		if _flicker_time <= 0.0:
			_flicker_strength = 0.0
	for l in lights:
		var light: PointLight2D = l["light"]
		var e: float = l["base"]
		if l["flicker"] > 0.0:
			e *= 1.0 + sin(_t * 9.0 + l["phase"]) * l["flicker"] * 0.5 + sin(_t * 23.0 + l["phase"] * 3.0) * l["flicker"] * 0.3
		if _flicker_strength > 0.0 and l["kind"] != "moon":
			var n := sin(_t * 37.0 + l["phase"] * 7.0) + sin(_t * 61.0 + l["phase"])
			if n > 0.6 * (1.0 - _flicker_strength * 0.5):
				e *= 0.08
		light.energy = e

func show_mirror_overlay(index: int, tex: Texture2D, visible_alpha: float) -> void:
	if index < 0 or index >= mirrors.size():
		return
	var ov: Sprite2D = mirrors[index]["overlay"]
	ov.texture = tex
	create_tween().tween_property(ov, "modulate:a", visible_alpha, 0.4)


## Draws wall caps, ink outlines, inner shadows and door thresholds.
class WallDrawer extends Node2D:
	var map: HouseMap

	func _draw() -> void:
		var cap := Art.tex("walls/wall_top.png")
		var ink := Art.INK
		var cs := Vector2(C, C)
		for y in map.h:
			for x in map.w:
				var c := Vector2i(x, y)
				var v := map.at(c)
				var p := Vector2(c) * C
				if v == HouseMap.WALL:
					var outdoor_only := _outdoor_only(c)
					var src := Rect2(Vector2(posmod(x, 4), posmod(y, 4)) * 32.0, Vector2(32, 32))
					draw_texture_rect_region(cap, Rect2(p, cs), src, Color(0.55, 0.62, 0.5) if outdoor_only else Color.WHITE)
				elif v == HouseMap.DOOR:
					_draw_door(c, p)
		# Ink outlines and soft shadows where walls meet floor.
		for y in map.h:
			for x in map.w:
				var c := Vector2i(x, y)
				if not map.is_floor(c):
					continue
				var p := Vector2(c) * C
				for o in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)]:
					var n: Vector2i = c + o
					if map.at(n) == HouseMap.WALL or map.at(n) == HouseMap.VOID:
						var a: Vector2
						var b: Vector2
						var sh: Rect2
						match o:
							Vector2i(0, -1):
								a = p; b = p + Vector2(C, 0); sh = Rect2(p, Vector2(C, 9))
							Vector2i(0, 1):
								a = p + Vector2(0, C); b = p + cs; sh = Rect2(p + Vector2(0, C - 5), Vector2(C, 5))
							Vector2i(-1, 0):
								a = p; b = p + Vector2(0, C); sh = Rect2(p, Vector2(8, C))
							_:
								a = p + Vector2(C, 0); b = p + cs; sh = Rect2(p + Vector2(C - 5, 0), Vector2(5, C))
						draw_rect(sh, Color(0, 0, 0, 0.35))
						draw_line(a, b, ink, 4.0)
		# Thin ink seam where two different rooms touch without a wall (open plan / outdoor).
		for y in map.h:
			for x in map.w:
				var c := Vector2i(x, y)
				var v := map.at(c)
				if v < 0:
					continue
				for o in [Vector2i(1, 0), Vector2i(0, 1)]:
					var n := map.at(c + o)
					if n >= 0 and n != v and not (map.rooms[v]["outdoor"] and map.rooms[n]["outdoor"]):
						var p := Vector2(c + o) * C
						var e := Vector2(0, C) if o.x == 1 else Vector2(C, 0)
						draw_line(p, p + e, Color(0, 0, 0, 0.5), 2.0)

	func _outdoor_only(c: Vector2i) -> bool:
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var v := map.at(c + Vector2i(dx, dy))
				if v >= 0 and not map.rooms[v]["outdoor"]:
					return false
		return true

	func _draw_door(c: Vector2i, p: Vector2) -> void:
		var horizontal_wall := map.is_wall(c + Vector2i(-1, 0)) or map.is_wall(c + Vector2i(1, 0))
		var wood := Color(0.30, 0.20, 0.12)
		var ink := Art.INK
		if horizontal_wall:
			# Passage runs vertically: frame posts left/right, threshold across.
			draw_rect(Rect2(p + Vector2(0, C * 0.5 - 4), Vector2(C, 8)), Color(0.24, 0.16, 0.1, 0.9))
			draw_rect(Rect2(p + Vector2(-3, -2), Vector2(6, C + 4)), wood)
			draw_rect(Rect2(p + Vector2(C - 3, -2), Vector2(6, C + 4)), wood)
			draw_rect(Rect2(p + Vector2(-3, -2), Vector2(6, C + 4)), ink, false, 1.5)
			draw_rect(Rect2(p + Vector2(C - 3, -2), Vector2(6, C + 4)), ink, false, 1.5)
			# Open door leaf swung against the wall.
			draw_line(p + Vector2(C - 1, 2), p + Vector2(C + 1, C - 2).rotated(0.0) + Vector2(-C * 0.9, -C * 0.55), ink, 5.0)
			draw_line(p + Vector2(C - 1, 2), p + Vector2(C + 1, C - 2) + Vector2(-C * 0.9, -C * 0.55), Color(0.42, 0.29, 0.17), 3.0)
		else:
			draw_rect(Rect2(p + Vector2(C * 0.5 - 4, 0), Vector2(8, C)), Color(0.24, 0.16, 0.1, 0.9))
			draw_rect(Rect2(p + Vector2(-2, -3), Vector2(C + 4, 6)), wood)
			draw_rect(Rect2(p + Vector2(-2, C - 3), Vector2(C + 4, 6)), wood)
			draw_rect(Rect2(p + Vector2(-2, -3), Vector2(C + 4, 6)), ink, false, 1.5)
			draw_rect(Rect2(p + Vector2(-2, C - 3), Vector2(C + 4, 6)), ink, false, 1.5)
			draw_line(p + Vector2(2, 1), p + Vector2(C * 0.45, C * 0.85), ink, 5.0)
			draw_line(p + Vector2(2, 1), p + Vector2(C * 0.45, C * 0.85), Color(0.42, 0.29, 0.17), 3.0)
