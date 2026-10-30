class_name Critters
extends Node2D
## Nightmare Mode vermin: spiders, rats and cockroaches skittering about the
## house. Purely cosmetic — no damage, evidence, points or threat. One manager
## moves every critter with a cheap dart-and-pause random walk; any hunter who
## steps on one squashes it (a crunch, a little blood, a still corpse).
##
## Each machine runs its own critters (they never affect the match), so this
## works the same in solo, on the host and on clients.

const MAX_CRITTERS := 36
## Critters per room by condition; basements get extra.
const PER_ROOM := {"kept": 0.4, "worn": 1.0, "neglected": 2.0, "abandoned": 3.0}
const KINDS := {
	"spider": {"speed": 95.0, "radius": 13.0, "rest": [0.4, 2.2], "dart": [0.15, 0.6]},
	"roach": {"speed": 120.0, "radius": 13.0, "rest": [0.2, 1.2], "dart": [0.3, 1.0]},
	"rat": {"speed": 150.0, "radius": 17.0, "rest": [0.8, 3.0], "dart": [0.4, 1.2]},
}

var run
var map: HouseMap
var rng := RandomNumberGenerator.new()
var list: Array = []       # {node, kind, room, dir, t, moving, alive}
var _blood_layer: Node2D

## A single critter, drawn in code (no textures needed except the rat).
class Bug extends Node2D:
	var kind := "roach"
	var dead := false
	var phase := 0.0

	func _draw() -> void:
		var leg := 1.0 if dead else sin(phase * 30.0)
		match kind:
			"spider":
				var body := Color(0.16, 0.14, 0.13) if not dead else Color(0.3, 0.06, 0.04)
				for side in [-1.0, 1.0]:
					for i in 4:
						var a := (-0.9 + i * 0.6) + leg * 0.15 * (1 if i % 2 == 0 else -1)
						var base := Vector2(0, 0)
						var knee := Vector2(cos(a) * 5.0, side * 5.5 + sin(a) * 2.0)
						var foot := Vector2(cos(a) * 9.0, side * (6.0 if dead else 9.0) + sin(a) * 3.0)
						draw_line(base, knee, body, 1.2, true)
						draw_line(knee, foot, body, 1.0, true)
				draw_circle(Vector2(-2.5, 0), 3.6, body)
				draw_circle(Vector2(2.2, 0), 2.2, body)
			"roach":
				var shell := Color(0.5, 0.27, 0.12) if not dead else Color(0.35, 0.1, 0.05)
				for side in [-1.0, 1.0]:
					for i in 3:
						var x := -2.0 + i * 3.0
						draw_line(Vector2(x, 0), Vector2(x + leg * 1.5 - 1.0, side * 5.5), Color(0.15, 0.08, 0.04), 0.9, true)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
				draw_circle(Vector2.ZERO, 5.0, shell)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_line(Vector2(4.5, -1), Vector2(9, -4), Color(0.2, 0.1, 0.05), 0.7, true)
				draw_line(Vector2(4.5, 1), Vector2(9, 4), Color(0.2, 0.1, 0.05), 0.7, true)

func setup(p_run, p_seed: int) -> void:
	run = p_run
	map = run.map
	rng.seed = p_seed
	z_index = -1     # beneath actors, above decals
	_blood_layer = Node2D.new()
	_blood_layer.z_index = -1
	add_child(_blood_layer)
	for r in map.rooms:
		if r["outdoor"]:
			continue
		var n: float = PER_ROOM.get(r.get("condition", "worn"), 1.0)
		if int(r.get("level", 0)) < 0:
			n += 1.5
		var count := int(n) + (1 if rng.randf() < n - floorf(n) else 0)
		for i in count:
			if list.size() >= MAX_CRITTERS:
				return
			var kinds := ["spider", "roach", "roach", "rat"] if int(r.get("level", 0)) < 0 or r.get("condition", "") in ["neglected", "abandoned"] else ["spider", "roach"]
			_spawn(kinds[rng.randi_range(0, kinds.size() - 1)], r["id"])

func _spawn(kind: String, room_id: String) -> void:
	var cell := map.random_free_cell(room_id, rng)
	var node: Node2D
	if kind == "rat":
		var s := Sprite2D.new()
		s.texture = Art.tex("decor/rat.png")
		s.scale = Vector2(0.5, 0.5)
		node = s
	else:
		var b := Bug.new()
		b.kind = kind
		b.scale = Vector2(1.5, 1.5)
		node = b
	node.position = HouseMap.cell_center(cell) + Vector2(rng.randf_range(-18, 18), rng.randf_range(-18, 18))
	node.rotation = rng.randf() * TAU
	add_child(node)
	list.append({"node": node, "kind": kind, "room": room_id, "dir": node.rotation, "t": rng.randf_range(0.0, 2.0), "moving": false, "alive": true})

func _process(delta: float) -> void:
	var feet: Array = []
	for h in run.hunters:
		if not h.dead and h.visible:
			feet.append(h.global_position)
	for c in list:
		if not c["alive"]:
			continue
		var node: Node2D = c["node"]
		var def: Dictionary = KINDS[c["kind"]]
		# Squashed underfoot?
		var squashed := false
		var near := Vector2.INF
		for f: Vector2 in feet:
			var d := f.distance_to(node.position)
			if d < def["radius"]:
				squashed = true
				break
			if d < 90.0 and d < node.position.distance_to(near):
				near = f
		if squashed:
			_squash(c)
			continue
		c["t"] -= delta
		if near != Vector2.INF and not c["moving"]:
			# Scatter away from approaching feet.
			c["dir"] = (node.position - near).angle() + rng.randf_range(-0.6, 0.6)
			c["moving"] = true
			c["t"] = rng.randf_range(def["dart"][0], def["dart"][1])
		elif c["t"] <= 0.0:
			c["moving"] = not c["moving"]
			var span: Array = def["dart"] if c["moving"] else def["rest"]
			c["t"] = rng.randf_range(span[0], span[1])
			if c["moving"]:
				c["dir"] += rng.randf_range(-1.4, 1.4)
		if c["moving"]:
			var step: Vector2 = Vector2.from_angle(c["dir"]) * float(def["speed"]) * delta
			var next: Vector2 = node.position + step
			if map.walkable(HouseMap.to_cell(next)) and map.room_at(next) == c["room"]:
				node.position = next
			else:
				c["dir"] += PI * rng.randf_range(0.6, 1.4)
			node.rotation = lerp_angle(node.rotation, c["dir"], minf(1.0, delta * 14.0))
			if node is Bug:
				node.phase += delta
				node.queue_redraw()

func _squash(c: Dictionary) -> void:
	c["alive"] = false
	var node: Node2D = c["node"]
	if node is Bug:
		node.dead = true
		node.scale *= Vector2(1.25, 0.8)
		node.queue_redraw()
	else:
		node.modulate = Color(0.55, 0.32, 0.3)
		node.scale = Vector2(0.56, 0.4)
	# A small splatter beneath the corpse.
	var splat := Sprite2D.new()
	splat.texture = Art.tex("decor/stain_%d.png" % rng.randi_range(1, 3))
	var size := 40.0 if c["kind"] == "rat" else 26.0
	var k := size / maxf(1.0, splat.texture.get_size().x)
	splat.scale = Vector2(k, k)
	splat.rotation = rng.randf() * TAU
	splat.position = node.position
	var mat := ShaderMaterial.new()
	mat.shader = run.view._mask_shader
	mat.set_shader_parameter("tint", Color(0.55, 0.03, 0.02, 0.95))
	splat.material = mat
	_blood_layer.add_child(splat)
	Sfx.play_at("critter_squish", node.position, self, -8.0 if c["kind"] != "rat" else -3.0, rng.randf_range(0.9, 1.15), 700.0)

func alive_count() -> int:
	return list.filter(func(c): return c["alive"]).size()
