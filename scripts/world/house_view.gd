class_name HouseView
extends Node2D
## Visual construction of a house from a HouseMap: textured floors, inked walls,
## doors, furniture sprites, lights and (optionally) collision and occluders.
## Used by live runs and by the replay viewer (without collision).

const C := Defs.CELL
const ART_SCALE := 0.5   # world art is authored at 64 px per 32 px cell
const DARKNESS := Color(0.23, 0.24, 0.32)
const DARKNESS_HUNT := Color(0.13, 0.10, 0.14)
const DARKNESS_HARBINGER := Color(0.12, 0.13, 0.19)
const DARKNESS_BASEMENT := Color(0.17, 0.17, 0.22)
## Neglect per room condition: overlay opacities, decal counts, floor tint.
const CONDITION := {
	"kept": {"grime": 0.0, "damp": 0.0, "cracks": 0.0, "dust": 0.0, "mould": 0.0, "sat": 1.0, "stains": 0, "webs": 0, "peel": 0, "litter": 0, "tint": Color(1, 1, 1)},
	"worn": {"grime": 0.5, "damp": 0.0, "cracks": 0.25, "dust": 0.25, "mould": 0.0, "sat": 0.88, "stains": 2, "webs": 1, "peel": 2, "litter": 1, "tint": Color(0.97, 0.95, 0.92)},
	"neglected": {"grime": 0.8, "damp": 0.4, "cracks": 0.5, "dust": 0.45, "mould": 0.2, "sat": 0.7, "stains": 5, "webs": 3, "peel": 5, "litter": 3, "tint": Color(0.93, 0.92, 0.88)},
	"abandoned": {"grime": 1.0, "damp": 0.75, "cracks": 0.7, "dust": 0.6, "mould": 0.45, "sat": 0.5, "stains": 8, "webs": 4, "peel": 8, "litter": 6, "tint": Color(0.9, 0.93, 0.88)},
}
## Faded, desaturated floors for neglected rooms.
const FADE_SHADER := """
shader_type canvas_item;
uniform float sat = 1.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float g = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	c.rgb = mix(vec3(g), c.rgb, sat);
	COLOR = c;
}
"""
## Uses an overlay's alpha as a mask for a LIGHT colour (dust, pale tide marks):
## neglect reads as a change in value, not just more darkness.
const MASK_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.8, 0.78, 0.72, 0.5);
void fragment() {
	COLOR = vec4(tint.rgb, texture(TEXTURE, UV).a * tint.a);
}
"""

var map: HouseMap
var modulate_node: CanvasModulate
var floor_layer: Node2D
var neglect_layer: Node2D      # grime, damp, cobwebs — always beneath items and evidence
var under_layer: Node2D
var furniture_layer: Node2D
var decal_layer: Node2D        # evidence decals, placed items
var actor_layer: Node2D
var overlay_layer: Node2D
var lights: Array = []         # [{light: PointLight2D, base: float, flicker: float, kind}]
var mirrors: Array = []        # [{furniture, sprite, overlay: Sprite2D}]
var doors: Array = []          # [{cell, open, leaf: DoorLeaf, shape, occluder}]
var _with_collision := false
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
	neglect_layer = _layer("Neglect", -9)
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
	_build_neglect()
	_build_stairs()
	_build_furniture()
	_build_lights()
	_with_collision = with_collision
	_build_doors(with_occluders)
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
	_fade_shader = _shader(FADE_SHADER)
	_mask_shader = _shader(MASK_SHADER)
	for r in map.rooms:
		var tex := Art.tex("floors/%s.png" % r["floor"])
		var cond: Dictionary = CONDITION.get(r.get("condition", "kept"), CONDITION["kept"])
		var mat: ShaderMaterial = null
		if float(cond["sat"]) < 1.0:
			mat = ShaderMaterial.new()
			mat.shader = _fade_shader
			mat.set_shader_parameter("sat", cond["sat"])
		for rect in r["rects"]:
			_floor_poly(tex, Rect2(Vector2(rect[0], rect[1]) * C, Vector2(rect[2], rect[3]) * C), cond["tint"], null, 1.0, mat)
	for d in map.doors:
		var rid := map.room_at_cell(d)
		var tex := Art.tex("floors/%s.png" % map.room(rid).get("floor", "wood_dark"))
		_floor_poly(tex, Rect2(Vector2(d) * C, Vector2(C, C)))

var _fade_shader: Shader
var _mask_shader: Shader

func _shader(code: String) -> Shader:
	var sh := Shader.new()
	sh.code = code
	return sh

func _floor_poly(tex: Texture2D, rect: Rect2, tint: Color = Color.WHITE, layer: Node2D = null, alpha: float = 1.0, mat: Material = null, uv_scale: float = 1.0) -> void:
	var p := Polygon2D.new()
	p.texture = tex
	p.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var pts := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	p.polygon = pts
	var uv := PackedVector2Array()
	for q in pts:
		uv.append(q / ART_SCALE * uv_scale)
	p.uv = uv
	p.color = Color(tint.r, tint.g, tint.b, alpha)
	if mat:
		p.material = mat
	(layer if layer else floor_layer).add_child(p)

## Weathering: tiled grime/damp/crack overlays plus a few stains, cobwebs,
## peeling wallpaper and litter. Deterministic per house and room (never uses
## the gameplay RNG) and placed away from doorways and stairs.
func _build_neglect() -> void:
	for r in map.rooms:
		var cond: Dictionary = CONDITION.get(r.get("condition", ""), {})
		if cond.is_empty() or r["outdoor"]:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(map.id + ":" + r["id"])
		# Dark passes (soot, damp, cracks) and light passes (dust, pale mould and
		# tide marks) from the same masks, offset so they never line up.
		var passes := [["grime", cond["grime"], null, 1.0], ["damp", cond["damp"], null, 1.0], ["cracks", cond["cracks"], null, 1.0],
			["grime", cond["dust"], Color(0.78, 0.75, 0.68, 1.0), 0.73], ["damp", cond["mould"], Color(0.62, 0.7, 0.55, 1.0), 0.61]]
		for pass_def in passes:
			var a: float = pass_def[1]
			if a <= 0.0 or not Art.has("decor/%s.png" % pass_def[0]):
				continue
			var tex := Art.tex("decor/%s.png" % pass_def[0])
			var mat: ShaderMaterial = null
			if pass_def[2] != null:
				mat = ShaderMaterial.new()
				mat.shader = _mask_shader
				var c: Color = pass_def[2]
				mat.set_shader_parameter("tint", Color(c.r, c.g, c.b, a))
			for rect in r["rects"]:
				_floor_poly(tex, Rect2(Vector2(rect[0], rect[1]) * C, Vector2(rect[2], rect[3]) * C), Color.WHITE, neglect_layer, a, mat, pass_def[3])
		var blocked := {}
		for d in map.doors:
			for o in [Vector2i.ZERO, Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)]:
				blocked[d + o] = true
		for st in map.stairs:
			for k in ["a", "a_land", "b", "b_land"]:
				blocked[st[k]] = true
		var cells: Array = r["cells"].filter(func(c): return not blocked.has(c))
		var edge: Array = map.wall_adjacent_cells(r["id"]).filter(func(c): return not blocked.has(c))
		if cells.is_empty():
			continue
		for i in int(cond["stains"]):
			var spos := HouseMap.cell_center(cells[rng.randi_range(0, cells.size() - 1)])
			var ssize := rng.randf_range(56.0, 110.0)
			var srot := rng.randf() * TAU
			var stain := "decor/stain_%d.png" % rng.randi_range(1, 3)
			_neglect_decal(stain, spos, srot, ssize * 1.12, 0.55, false, Color(0.8, 0.77, 0.66))   # pale tide ring
			_neglect_decal(stain, spos, srot, ssize, rng.randf_range(0.75, 1.0))
		for i in int(cond["litter"]):
			var kinds := ["decor/rubble.png", "decor/papers_scattered.png", "decor/dust_sheet_scrap.png"]
			_neglect_decal(kinds[rng.randi_range(0, kinds.size() - 1)], HouseMap.cell_center(cells[rng.randi_range(0, cells.size() - 1)]), rng.randf() * TAU, rng.randf_range(22.0, 32.0), 0.95)
		# Cobwebs in room corners (art anchored top-left; rotate about the corner point).
		var rect: Array = r["rects"][0]
		var x0: float = rect[0] * C
		var y0: float = rect[1] * C
		var x1: float = (rect[0] + rect[2]) * C
		var y1: float = (rect[1] + rect[3]) * C
		var corners := [[Vector2(x0, y0), 0.0, Vector2i(rect[0], rect[1])], [Vector2(x1, y0), PI * 0.5, Vector2i(rect[0] + rect[2] - 1, rect[1])],
			[Vector2(x1, y1), PI, Vector2i(rect[0] + rect[2] - 1, rect[1] + rect[3] - 1)], [Vector2(x0, y1), PI * 1.5, Vector2i(rect[0], rect[1] + rect[3] - 1)]]
		var start := rng.randi_range(0, 3)
		for i in mini(int(cond["webs"]), 4):
			var cn: Array = corners[(start + i) % 4]
			if blocked.has(cn[2]):
				continue
			_neglect_decal("decor/cobweb.png", cn[0], cn[1], 48.0, 0.95, true)
		# Peeling wallpaper along walls (papered rooms only).
		if not (r["floor"] in ["stone", "dirt", "tile_white", "tile_checker"]):
			for i in int(cond["peel"]):
				if edge.is_empty():
					break
				var c: Vector2i = edge[rng.randi_range(0, edge.size() - 1)]
				var rot := 0.0
				if map.is_wall(c + Vector2i(0, -1)):
					rot = 0.0
				elif map.is_wall(c + Vector2i(1, 0)):
					rot = PI * 0.5
				elif map.is_wall(c + Vector2i(0, 1)):
					rot = PI
				else:
					rot = PI * 1.5
				var pos := HouseMap.cell_center(c) + Vector2(0, -C * 0.36).rotated(rot)
				_neglect_decal("decor/peel.png", pos, rot, 46.0, 1.0)

## Nightmare Mode: old blood — pools, drag smears and spatter — in every
## indoor room, heaviest in neglected rooms and basements. Deterministic per
## house so host, clients and replays agree. Never uses evidence sprites, so
## it can't be mistaken for a vampire's blood droplets.
func build_nightmare() -> void:
	for r in map.rooms:
		if r["outdoor"]:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(map.id + ":nightmare:" + r["id"])
		var cells: Array = r["cells"].filter(func(c): return not map.is_stair(c))
		if cells.is_empty():
			continue
		var heavy: bool = r.get("condition", "") in ["neglected", "abandoned"] or int(r.get("level", 0)) < 0
		var count := rng.randi_range(2, 4) + (3 if heavy else 0)
		for i in count:
			var pos := HouseMap.cell_center(cells[rng.randi_range(0, cells.size() - 1)])
			var stain := "decor/stain_%d.png" % rng.randi_range(1, 3)
			match rng.randi_range(0, 2):
				0:   # a dried pool
					_blood(stain, pos, rng.randf() * TAU, rng.randf_range(40.0, 80.0), rng.randf_range(0.7, 0.95))
				1:   # a drag smear: a run of overlapping blots
					var dir := Vector2.from_angle(rng.randf() * TAU)
					var blots := rng.randi_range(4, 8)
					for j in blots:
						_blood(stain, pos + dir * j * 14.0, dir.angle(), 30.0 - j * 2.0, 0.8 - j * 0.06)
				2:   # spatter
					for j in rng.randi_range(4, 8):
						_blood(stain, pos + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30)), rng.randf() * TAU, rng.randf_range(8.0, 18.0), 0.9)

func _blood(path: String, pos: Vector2, rot: float, size: float, alpha: float) -> void:
	# The stain art is near-black; its alpha masks a flat old-blood red instead.
	var s := _neglect_decal(path, pos, rot, size * 1.2, minf(1.0, alpha + 0.1), false, Color(0.42, 0.03, 0.02))
	if s:
		s.reparent(decal_layer)   # above the faded floor; laid before any evidence decals

func _neglect_decal(path: String, pos: Vector2, rot: float, size: float, alpha: float, corner: bool = false, light: Color = Color(0, 0, 0, 0)) -> Sprite2D:
	if not Art.has(path):
		return null
	var s := Sprite2D.new()
	if light.a > 0.0:
		var mat := ShaderMaterial.new()
		mat.shader = _mask_shader
		mat.set_shader_parameter("tint", Color(light.r, light.g, light.b, alpha))
		s.material = mat
	s.texture = Art.tex(path)
	s.position = pos
	s.rotation = rot
	if corner:
		s.centered = false   # the texture's top-left corner sits on the room corner
	var k := size / maxf(1.0, s.texture.get_size().x)
	s.scale = Vector2(k, k)
	s.modulate.a = alpha
	neglect_layer.add_child(s)
	return s

## Staircases and hatches between floors (walkable cells, drawn under actors).
func _build_stairs() -> void:
	for st in map.stairs:
		var top := "furniture/hatch.png" if st.get("style", "stairs") == "hatch" else "furniture/stairs_down.png"
		for pair in [[st["a"], st["a_land"], top, st.get("a_wide")], [st["b"], st["b_land"], "furniture/stairs_up.png", st.get("b_wide")]]:
			var cell: Vector2i = pair[0]
			var land: Vector2i = pair[1]
			var s := Sprite2D.new()
			s.texture = Art.tex(pair[2])
			s.position = HouseMap.cell_center(cell)
			# Steps lead away from the landing; a wide flight spans two cells.
			s.rotation = Vector2(cell - land).angle() - PI * 0.5
			var ts := s.texture.get_size()
			var width := C
			if pair[3] != null:
				var wide: Vector2i = pair[3]
				s.position = (HouseMap.cell_center(cell) + HouseMap.cell_center(wide)) * 0.5
				width = C * 2.0
			# Exactly the stair cells: flush with the walls, never into a neighbouring room.
			s.scale = Vector2(width / maxf(1.0, ts.x), C / maxf(1.0, ts.y))
			under_layer.add_child(s)

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

## Doors: most start closed (deterministic per house, so every peer and every
## replay agrees). A closed door blocks hunters, light and sight; ghosts pass.
func _build_doors(with_occluders: bool) -> void:
	for i in map.doors.size():
		var c: Vector2i = map.doors[i]
		var across := map.is_wall(c + Vector2i(-1, 0)) or map.is_wall(c + Vector2i(1, 0))   # leaf spans x
		var leaf := DoorLeaf.new()
		leaf.across = across
		leaf.position = Vector2(c) * C + (Vector2(2, C * 0.5) if across else Vector2(C * 0.5, 2))
		leaf.z_index = -3
		add_child(leaf)
		var d := {"cell": c, "open": false, "leaf": leaf, "shape": null, "occluder": null}
		if _with_collision:
			var body := StaticBody2D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			var cs := CollisionShape2D.new()
			var sh := RectangleShape2D.new()
			sh.size = Vector2(C, 8) if across else Vector2(8, C)
			cs.shape = sh
			cs.position = HouseMap.cell_center(c)
			body.add_child(cs)
			add_child(body)
			d["shape"] = cs
		if with_occluders:
			var occ := LightOccluder2D.new()
			var poly := OccluderPolygon2D.new()
			var r := Rect2(HouseMap.cell_center(c) - (Vector2(C, 4) if across else Vector2(4, C)) * 0.5, Vector2(C, 4) if across else Vector2(4, C))
			poly.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
			occ.occluder = poly
			add_child(occ)
			d["occluder"] = occ
		doors.append(d)
		set_door(i, hash(map.id + ":door:%d" % i) % 10 < 3, false)

func set_door(i: int, open: bool, animate: bool = true) -> void:
	if i < 0 or i >= doors.size():
		return
	var d: Dictionary = doors[i]
	d["open"] = open
	if open:
		map.closed_doors.erase(d["cell"])
	else:
		map.closed_doors[d["cell"]] = true
	if d["shape"]:
		d["shape"].set_deferred("disabled", open)
	if d["occluder"]:
		d["occluder"].visible = not open
	var leaf: DoorLeaf = d["leaf"]
	var target := -PI * 0.5 if open else 0.0
	if animate:
		create_tween().tween_property(leaf, "rotation", target, 0.25).set_trans(Tween.TRANS_QUAD)
	else:
		leaf.rotation = target

func door_index_at(pos: Vector2, radius: float) -> int:
	var best := -1
	var bd := radius
	for i in doors.size():
		var dd := pos.distance_to(HouseMap.cell_center(doors[i]["cell"]))
		if dd < bd:
			bd = dd
			best = i
	return best

## A wooden door leaf hinged at one frame post; rotation 0 = closed across the gap.
class DoorLeaf extends Node2D:
	var across := true
	func _draw() -> void:
		var C2 := Defs.CELL - 4.0
		var r := Rect2(Vector2(0, -3), Vector2(C2, 6)) if across else Rect2(Vector2(-3, 0), Vector2(6, C2))
		draw_rect(r.grow(1.5), Art.INK)
		draw_rect(r, Color(0.36, 0.24, 0.14))
		var mid := r.position + r.size * (Vector2(0.78, 0.5) if across else Vector2(0.5, 0.78))
		draw_circle(mid, 1.6, Color(0.75, 0.6, 0.3))   # brass knob

## A living flame: layered tongues that sway and gutter, never a static glow.
class Flame extends Node2D:
	var size := 7.0
	var _t := randf() * 10.0
	var lit := true
	func _ready() -> void:
		var m := CanvasItemMaterial.new()
		m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		material = m
	func _process(delta: float) -> void:
		_t += delta
		if lit:
			queue_redraw()
	func _draw() -> void:
		if not lit:
			return
		var sway := sin(_t * 5.3) * 0.25 + sin(_t * 11.7) * 0.12
		var h := size * (1.6 + 0.25 * sin(_t * 8.1) + 0.12 * sin(_t * 19.0))
		for layer in [[1.0, Color(0.95, 0.35, 0.08, 0.75)], [0.68, Color(1.0, 0.72, 0.2, 0.9)], [0.36, Color(1.0, 0.95, 0.75, 1.0)]]:
			var k: float = layer[0]
			var w := size * 0.55 * k
			var tip := Vector2(sway * size * k, -h * k)
			var pts := PackedVector2Array()
			for a in 9:
				var ang := PI * a / 8.0
				pts.append(Vector2(cos(ang) * w, sin(ang) * w * 0.8))
			pts.append(Vector2(-w * 0.8, -h * k * 0.35) + tip * 0.3)
			pts.append(tip)
			pts.append(Vector2(w * 0.8, -h * k * 0.35) + tip * 0.3)
			draw_colored_polygon(pts, layer[1])

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
	var entry := {"light": l, "base": energy, "flicker": flicker, "kind": kind, "phase": randf() * 10.0, "on": true, "flame": null, "scale": scale, "pos": pos}
	if kind in ["candle", "lamp", "hearth"]:
		var fl := Flame.new()
		fl.position = pos
		fl.size = {"candle": 4.0, "lamp": 5.0, "hearth": 8.0}[kind]
		fl.z_index = 2
		furniture_layer.add_child(fl)
		entry["flame"] = fl
	lights.append(entry)
	return l

## Lights that supernatural activity can snuff out (and hunters relight).
func can_extinguish(i: int) -> bool:
	return i >= 0 and i < lights.size() and lights[i]["kind"] in ["room", "candle", "lamp", "hearth"]

func set_light(i: int, on: bool) -> void:
	if not can_extinguish(i):
		return
	var l: Dictionary = lights[i]
	l["on"] = on
	if l["flame"]:
		l["flame"].lit = on
		l["flame"].queue_redraw()

func _build_lights() -> void:
	for r in map.rooms:
		# Never place a light inside a wall (L-shaped rooms): shadows break.
		var center := HouseMap.cell_center(map.nearest_floor(HouseMap.to_cell(map.room_center(r["id"])), r["id"]))
		var extent := 0.0
		for c in r["cells"]:
			extent = maxf(extent, center.distance_to(HouseMap.cell_center(c)))
		if r["outdoor"]:
			# Pale moonlight washes over gardens and streets.
			_light(center, Color(0.55, 0.65, 0.9), 0.55, clampf(extent / 200.0, 0.9, 3.2), "lights/soft.png", 0.0, "moon", true)
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
			"furnace":
				_light(pos + Vector2(0, 14).rotated(f["rot"] * PI * 0.5), Color(1.0, 0.42, 0.16), 0.8, 0.7, "lights/candle.png", 0.3, "hearth", true)

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
		# Exact cell bounds: shrinking each piece left hairline gaps between
		# neighbouring occluders that light leaked through.
		var r: Rect2 = rect
		poly.polygon = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		occ.occluder = poly
		add_child(occ)

# --- Runtime effects --------------------------------------------------------------

func flicker(duration: float, strength: float = 1.0) -> void:
	_flicker_time = maxf(_flicker_time, duration)
	_flicker_strength = maxf(_flicker_strength, strength)

func set_darkness(c: Color, time: float = 1.0) -> void:
	_darkness = c
	create_tween().tween_property(modulate_node, "color", _effective_darkness(), time)

## The viewer's floor: basements are always a shade darker (and colder).
var basement_view := false

func set_basement_view(on: bool) -> void:
	if on == basement_view:
		return
	basement_view = on
	create_tween().tween_property(modulate_node, "color", _effective_darkness(), 0.6)

func _effective_darkness() -> Color:
	var c := _darkness * Color(0.74, 0.76, 0.84) if basement_view else _darkness
	match mood:
		"moon": c *= Color(0.95, 1.05, 1.35)    # full moon: a cold, brighter blue
		"mist": c *= Color(1.3, 0.62, 0.64)     # blood mist: everything reddens
	return c

## Dread escalation: "moon" (werewolf) or "mist" (vampire). Permanent once set.
var mood := ""
var _mist: Array = []

func set_mood(m: String) -> void:
	if mood == m:
		return
	mood = m
	create_tween().tween_property(modulate_node, "color", _effective_darkness(), 2.5)
	if m == "moon":
		for l in lights:
			if l["kind"] == "moon":
				l["base"] = float(l["base"]) * 2.4
				l["light"].color = Color(0.78, 0.86, 1.0)
	elif m == "mist":
		# Two drifting layers of thick red fog over the whole house; thin enough to see through.
		var ws := Vector2(map.w, map.h) * C
		for k in 2:
			var s := Sprite2D.new()
			s.texture = Art.tex("decor/damp.png")
			s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			s.region_enabled = true
			s.region_rect = Rect2(Vector2.ZERO, ws * (0.7 + k * 0.25))
			s.scale = Vector2.ONE / (0.7 + k * 0.25)
			s.centered = false
			var mat := ShaderMaterial.new()
			mat.shader = _mask_shader
			mat.set_shader_parameter("tint", Color(0.42, 0.03, 0.04, 0.42 - k * 0.1))
			s.material = mat
			s.modulate.a = 0.0
			s.z_index = 2 + k
			overlay_layer.add_child(s)
			create_tween().tween_property(s, "modulate:a", 1.0, 4.0)
			_mist.append(s)

func _process(delta: float) -> void:
	_t += delta
	for k in _mist.size():
		var s: Sprite2D = _mist[k]
		var r := s.region_rect
		r.position = Vector2(_t * (9.0 if k == 0 else -6.0), sin(_t * 0.07 + k) * 40.0 + _t * 3.0)
		s.region_rect = r
	if _flicker_time > 0.0:
		_flicker_time -= delta
		if _flicker_time <= 0.0:
			_flicker_strength = 0.0
	for l in lights:
		var light: PointLight2D = l["light"]
		var e: float = l["base"]
		if not l["on"]:
			light.energy = move_toward(light.energy, 0.0, delta * 3.0)
			continue
		if l["flicker"] > 0.0:
			e *= 1.0 + sin(_t * 9.0 + l["phase"]) * l["flicker"] * 0.5 + sin(_t * 23.0 + l["phase"] * 3.0) * l["flicker"] * 0.3
			if l["flame"]:
				# Fire breathes: the glow swells and shifts a little with the flame.
				light.texture_scale = l["scale"] * (1.0 + sin(_t * 6.3 + l["phase"]) * 0.04)
				light.position = l["pos"] + Vector2(sin(_t * 5.3 + l["phase"]), cos(_t * 4.1 + l["phase"])) * 1.5
		if _flicker_strength > 0.0 and l["kind"] != "moon":
			var n := sin(_t * 37.0 + l["phase"] * 7.0) + sin(_t * 61.0 + l["phase"])
			if n > 0.6 * (1.0 - _flicker_strength * 0.5):
				e *= 0.08
		light.energy = e

## Evidence beginning to appear: the air of the room warps faintly for a moment.
func shimmer_room(room_id: String) -> void:
	var r := map.room(room_id)
	if r.is_empty():
		return
	for rect in r["rects"]:
		var s := Sprite2D.new()
		s.texture = Art.tex("lights/soft.png")
		s.centered = false
		var rr := Rect2(Vector2(rect[0], rect[1]) * C, Vector2(rect[2], rect[3]) * C)
		s.position = rr.position
		s.scale = rr.size / s.texture.get_size()
		s.material = WorldFx.distort_material(0.004, Color(0.92, 0.96, 1.0), 0.06, false)
		s.modulate.a = 0.0
		s.z_index = 4
		overlay_layer.add_child(s)
		var tw := create_tween()
		tw.tween_property(s, "modulate:a", 1.0, 0.5)
		tw.tween_method(func(v): s.material.set_shader_parameter("t", v), 0.0, 6.0, 1.4)
		tw.tween_property(s, "modulate:a", 0.0, 0.6)
		tw.tween_callback(s.queue_free)

## A short-lived column of fire (a burning occupant, the furnace's roar).
func burst_flames(pos: Vector2, dur: float, size: float = 1.0) -> void:
	var holder := Node2D.new()
	holder.position = pos
	holder.z_index = 3
	overlay_layer.add_child(holder)
	for i in 5:
		var f := Flame.new()
		f.size = (9.0 + randf() * 5.0) * size
		f.position = Vector2(randf_range(-10, 10), randf_range(-6, 8)) * size
		holder.add_child(f)
	var l := PointLight2D.new()
	l.texture = Art.tex("lights/candle.png")
	l.color = Color(1.0, 0.5, 0.15)
	l.energy = 1.6
	l.texture_scale = 1.1 * size
	holder.add_child(l)
	var tw := create_tween()
	tw.tween_interval(dur)
	tw.tween_property(holder, "modulate:a", 0.0, 0.5)
	tw.parallel().tween_property(l, "energy", 0.0, 0.5)
	tw.tween_callback(holder.queue_free)

## Brief rattle of a furniture sprite (poltergeist activity; replay and clients too).
func shake_furniture(index: int) -> void:
	if index < 0 or index >= map.furniture.size() or not map.furniture[index].has("sprite"):
		return
	var s: Sprite2D = map.furniture[index]["sprite"]
	if s.has_meta("shaking"):
		return
	s.set_meta("shaking", true)
	var base_rot := s.rotation
	var tw := create_tween()
	for i in 4:
		tw.tween_property(s, "rotation", base_rot + randf_range(-0.08, 0.08), 0.05)
	tw.tween_property(s, "rotation", base_rot, 0.05)
	tw.tween_callback(func(): s.remove_meta("shaking"))

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
					var tint := Color.WHITE
					if outdoor_only:
						tint = Color(0.55, 0.62, 0.5)
					elif map.floor_of_cell(c) < 0:
						tint = Color(0.42, 0.4, 0.44)   # basement walls read clearly darker than stone floors
					draw_texture_rect_region(cap, Rect2(p, cs), src, tint)
					_maybe_window(c, p)
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

	## Leaded windows on straight exterior walls (indoor on one side, outdoors on the other).
	func _maybe_window(c: Vector2i, p: Vector2) -> void:
		if posmod(c.x * 3 + c.y * 5, 7) != 0:
			return
		for o in [Vector2i(0, 1), Vector2i(1, 0)]:
			var a := map.at(c - o)
			var b := map.at(c + o)
			if a < 0 or b < 0 or map.rooms[a]["outdoor"] == map.rooms[b]["outdoor"]:
				continue
			var side := Vector2i(o.y, o.x)
			if not (map.is_wall(c + side) and map.is_wall(c - side)):
				continue
			var r := Rect2(p + Vector2(4, 11), Vector2(C - 8, 10)) if o.y == 1 else Rect2(p + Vector2(11, 4), Vector2(10, C - 8))
			draw_rect(r.grow(2.0), Color(0.33, 0.24, 0.15))
			draw_rect(r, Color(0.42, 0.5, 0.62))
			draw_rect(Rect2(r.position, r.size * Vector2(0.5, 0.5)), Color(0.62, 0.7, 0.8, 0.6))
			var mid := r.get_center()
			if o.y == 1:
				draw_line(Vector2(mid.x, r.position.y), Vector2(mid.x, r.end.y), Art.INK, 1.5)
			else:
				draw_line(Vector2(r.position.x, mid.y), Vector2(r.end.x, mid.y), Art.INK, 1.5)
			draw_rect(r.grow(2.0), Art.INK, false, 1.5)
			return

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
		else:
			draw_rect(Rect2(p + Vector2(C * 0.5 - 4, 0), Vector2(8, C)), Color(0.24, 0.16, 0.1, 0.9))
			draw_rect(Rect2(p + Vector2(-2, -3), Vector2(C + 4, 6)), wood)
			draw_rect(Rect2(p + Vector2(-2, C - 3), Vector2(C + 4, 6)), wood)
			draw_rect(Rect2(p + Vector2(-2, -3), Vector2(C + 4, 6)), ink, false, 1.5)
			draw_rect(Rect2(p + Vector2(-2, C - 3), Vector2(C + 4, 6)), ink, false, 1.5)
