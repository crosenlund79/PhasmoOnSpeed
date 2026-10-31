class_name HouseMap
extends RefCounted
## Logical house: grid rasterised from room rectangles (same rules as
## tools/houses/build_houses.py), stable room identities, furniture footprints,
## walkability, pathfinding and line of sight.

const VOID := -1
const WALL := -2
const DOOR := -3
const C := Defs.CELL

var id := ""
var name := ""
var data := {}
var w := 0
var h := 0
var cells := PackedInt32Array()   # room index, or VOID/WALL/DOOR
var blocked := {}                 # Vector2i -> true for solid furniture cells
var rooms: Array = []             # [{id, name, floor, kind, lit, outdoor, cells: Array[Vector2i], index}]
var room_by_id := {}
var furniture: Array = []         # [{type, cell: Vector2i, size: Vector2i, rot, rect: Rect2, def}]
var doors: Array = []             # Vector2i
var closed_doors := {}            # door cell -> true (kept in sync by HouseView.set_door)
var astar := AStarGrid2D.new()
var spawn_cell := Vector2i.ZERO
var stairs: Array = []            # [{name, a, a_land, b, b_land}] cells; a is on the upper floor
var _stair_cells := {}            # stair cell -> landing cell on the other floor
var _own_landing := {}            # stair cell -> its landing on the same floor
var _floor_rects := {}            # floor index -> Rect2i (cells, including walls)

static func from_data(d: Dictionary) -> HouseMap:
	var m := HouseMap.new()
	m._build(d)
	return m

func _build(d: Dictionary) -> void:
	data = d
	id = d["id"]
	name = d["name"]
	w = int(d["size"][0])
	h = int(d["size"][1])
	cells.resize(w * h)
	cells.fill(VOID)
	for i in d["rooms"].size():
		var r: Dictionary = d["rooms"][i].duplicate()
		r["index"] = i
		r["cells"] = []
		rooms.append(r)
		room_by_id[r["id"]] = r
		for rect in r["rects"]:
			for y in range(int(rect[1]), int(rect[1]) + int(rect[3])):
				for x in range(int(rect[0]), int(rect[0]) + int(rect[2])):
					cells[y * w + x] = i
					r["cells"].append(Vector2i(x, y))
	var walls: Array = []
	for y in h:
		for x in w:
			if cells[y * w + x] != VOID:
				continue
			var near := false
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var v := at(Vector2i(x + dx, y + dy))
					if v >= 0:
						near = true
			if near:
				walls.append(Vector2i(x, y))
	for c in walls:
		cells[c.y * w + c.x] = WALL
	for dd in d["doors"]:
		var dc := Vector2i(int(dd[0]), int(dd[1]))
		cells[dc.y * w + dc.x] = DOOR
		doors.append(dc)
	for f in d["furniture"]:
		var def: Dictionary = Defs.FURNITURE[f[0]]
		var rot := int(f[3])
		var size: Vector2i = def["size"]
		if rot % 2 == 1:
			size = Vector2i(size.y, size.x)
		var cell := Vector2i(int(f[1]), int(f[2]))
		var item := {"type": f[0], "cell": cell, "size": size, "rot": rot, "def": def,
			"rect": Rect2(Vector2(cell) * C, Vector2(size) * C), "index": furniture.size()}
		item["room_id"] = room_at_cell(cell + size / 2)
		furniture.append(item)
		if def.get("solid", false):
			for y in range(cell.y, cell.y + size.y):
				for x in range(cell.x, cell.x + size.x):
					blocked[Vector2i(x, y)] = true
	spawn_cell = Vector2i(int(d["spawn"][0]), int(d["spawn"][1]))
	for r in rooms:
		var f := int(r.get("level", 0))   # 0 = main floor, -1 = basement ("floor" is the floor texture)
		r["level"] = f
		for c in r["cells"]:
			var cur: Rect2i = _floor_rects.get(f, Rect2i(c, Vector2i.ONE))
			_floor_rects[f] = cur.expand(c).expand(c + Vector2i.ONE)
	for f in _floor_rects:
		_floor_rects[f] = (_floor_rects[f] as Rect2i).grow(1)
	for st in d.get("stairs", []):
		var e := {"name": st.get("name", "Stairs"), "a": _v(st["a"]), "a_land": _v(st["a_land"]), "b": _v(st["b"]), "b_land": _v(st["b_land"])}
		stairs.append(e)
		_stair_cells[e["a"]] = e["b_land"]
		_stair_cells[e["b"]] = e["a_land"]
		_own_landing[e["a"]] = e["a_land"]
		_own_landing[e["b"]] = e["b_land"]
	# Staircases are two cells wide where the room allows: the sideways
	# neighbour of each stair cell becomes part of the same flight.
	for e in stairs:
		for side in ["a", "b"]:
			var c: Vector2i = e[side]
			var dvec: Vector2i = c - e[side + "_land"]
			var perp := Vector2i(dvec.y, dvec.x)
			for cand: Vector2i in [c + perp, c - perp]:
				if is_floor(cand) and at(cand) != DOOR and not _stair_cells.has(cand) and not blocked.has(cand) \
						and walkable(cand - dvec) and at(cand - dvec) != DOOR and room_at_cell(cand) == room_at_cell(c):
					_stair_cells[cand] = _stair_cells[c]
					_own_landing[cand] = cand - dvec
					e[side + "_wide"] = cand
					break
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(C, C)
	astar.offset = Vector2(C, C) * 0.5
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in h:
		for x in w:
			astar.set_point_solid(Vector2i(x, y), not walkable(Vector2i(x, y)))

static func _v(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))

# --- Floors ----------------------------------------------------------------------------

## 0 = main floor, -1 = basement. Walls/void resolve by the floor rectangle they lie in.
func floor_of_cell(c: Vector2i) -> int:
	var v := at(c)
	if v >= 0:
		return int(rooms[v]["level"])
	for f in _floor_rects:
		if (_floor_rects[f] as Rect2i).has_point(c):
			return f
	return 0

func floor_at(p: Vector2) -> int:
	return floor_of_cell(to_cell(p))

func floors() -> Array:
	var out := _floor_rects.keys()
	out.sort()
	out.reverse()
	return out

func floor_bounds(f: int) -> Rect2:
	var r: Rect2i = _floor_rects.get(f, Rect2i(0, 0, w, h))
	return Rect2(Vector2(r.position) * C, Vector2(r.size) * C)

func is_stair(c: Vector2i) -> bool:
	return _stair_cells.has(c)

## World position of the landing on the other floor when `pos` stands on a stair
## cell and the mover is heading onto the steps (away from that stair's own
## landing). Crossing a staircase sideways never takes you to another floor.
## move_dir == Vector2.ZERO skips the direction test (host-side validation).
func stair_destination(pos: Vector2, locked: Vector2i = Vector2i(-99, -99), move_dir: Vector2 = Vector2.ZERO) -> Vector2:
	var c := to_cell(pos)
	if c == locked or not _stair_cells.has(c):
		return Vector2.INF
	if move_dir != Vector2.ZERO:
		var down := Vector2(c - _own_landing[c]).normalized()
		if move_dir.normalized().dot(down) < 0.35:
			return Vector2.INF
	return cell_center(_stair_cells[c])

## The stair cell within radius of pos (closest), or (-99, -99).
func nearest_stair(pos: Vector2, radius: float) -> Vector2i:
	var best := Vector2i(-99, -99)
	var bd := radius
	for c in _stair_cells:
		var d := pos.distance_to(cell_center(c))
		if d < bd:
			bd = d
			best = c
	return best

## World position of the landing on the other floor for a stair cell.
func stair_target(c: Vector2i) -> Vector2:
	return cell_center(_stair_cells[c])

func at(c: Vector2i) -> int:
	if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
		return VOID
	return cells[c.y * w + c.x]

func is_floor(c: Vector2i) -> bool:
	var v := at(c)
	return v >= 0 or v == DOOR

func walkable(c: Vector2i) -> bool:
	return is_floor(c) and not blocked.has(c)

func is_wall(c: Vector2i) -> bool:
	return at(c) == WALL

static func to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / C), floori(p.y / C))

static func cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * C

func world_size() -> Vector2:
	return Vector2(w, h) * C

## Room id for a cell. Door cells resolve to `prefer` when it is adjacent,
## otherwise to the first adjacent room (up, left, down, right).
func room_at_cell(c: Vector2i, prefer: String = "") -> String:
	var v := at(c)
	if v >= 0:
		return rooms[v]["id"]
	if v == DOOR:
		var first := ""
		for o in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)]:
			var n := at(c + o)
			if n >= 0:
				var rid: String = rooms[n]["id"]
				if rid == prefer:
					return rid
				if first == "":
					first = rid
		return first
	return ""

func room_at(p: Vector2, prefer: String = "") -> String:
	return room_at_cell(to_cell(p), prefer)

func room_name(room_id: String) -> String:
	return room_by_id.get(room_id, {}).get("name", "Unknown")

func room(room_id: String) -> Dictionary:
	return room_by_id.get(room_id, {})

func indoor_rooms() -> Array:
	return rooms.filter(func(r): return not r["outdoor"])

func rooms_of_kind(kind: String) -> Array:
	return rooms.filter(func(r): return r["kind"] == kind)

func room_center(room_id: String) -> Vector2:
	var r := room(room_id)
	var sum := Vector2.ZERO
	for c in r["cells"]:
		sum += cell_center(c)
	return sum / maxf(1.0, r["cells"].size())

## Free (walkable) cells of a room, optionally excluding door-adjacent cells.
func free_cells(room_id: String, avoid_doors: bool = true) -> Array:
	var out: Array = []
	for c in room(room_id).get("cells", []):
		if not walkable(c) or _stair_cells.has(c):
			continue
		if avoid_doors:
			var near_door := false
			for o in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)]:
				if at(c + o) == DOOR:
					near_door = true
			if near_door:
				continue
		out.append(c)
	return out

func random_free_cell(room_id: String, rng: RandomNumberGenerator, avoid: Dictionary = {}) -> Vector2i:
	var opts := free_cells(room_id).filter(func(c): return not avoid.has(c))
	if opts.is_empty():
		opts = free_cells(room_id, false)
	if opts.is_empty():
		return spawn_cell
	return opts[rng.randi_range(0, opts.size() - 1)]

## Walkable cells of a room that touch a wall (for claw marks, handprints).
func wall_adjacent_cells(room_id: String) -> Array:
	var out: Array = []
	for c in room(room_id).get("cells", []):
		if not walkable(c):
			continue
		for o in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)]:
			if is_wall(c + o):
				out.append(c)
				break
	return out

func furniture_with(flag: String) -> Array:
	return furniture.filter(func(f): return f["def"].get(flag, false))

## Nearest floor cell belonging to `room_id` (furniture allowed).
func nearest_floor(c: Vector2i, room_id: String) -> Vector2i:
	var best := c
	var bd := INF
	for cell in room(room_id).get("cells", []):
		var d := Vector2(cell - c).length_squared()
		if d < bd:
			bd = d
			best = cell
	return best

func nearest_walkable(c: Vector2i) -> Vector2i:
	if walkable(c):
		return c
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if walkable(n):
					return n
	return spawn_cell

## World-space path between two points (cell centres), empty if unreachable.
## Paths that change floor include an instant jump from a staircase cell to the
## landing on the other floor (consecutive points far apart = take the stairs).
func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var a := nearest_walkable(to_cell(from))
	var b := nearest_walkable(to_cell(to))
	var fa := floor_of_cell(a)
	var fb := floor_of_cell(b)
	if fa != fb and not stairs.is_empty():
		return _floor_path(a, b, fa, fb)
	return _grid_path(a, b)

## Shortest route between floors: take a staircase on this floor that brings the
## mover closer to the target floor, then continue from its landing (basement to
## upper floor goes through the main floor: two staircases).
func _floor_path(a: Vector2i, b: Vector2i, fa: int, fb: int) -> PackedVector2Array:
	if fa == fb:
		return _grid_path(a, b)
	var best := PackedVector2Array()
	var best_len := INF
	for st in stairs:
		for side in ["a", "b"]:
			var enter: Vector2i = st[side]
			if floor_of_cell(enter) != fa:
				continue
			var land: Vector2i = st["b_land"] if side == "a" else st["a_land"]
			var fl := floor_of_cell(land)
			if absi(fl - fb) >= absi(fa - fb):
				continue
			var p1 := _grid_path(a, enter)
			if p1.is_empty() and a != enter:
				continue
			var p2 := _floor_path(land, b, fl, fb)
			if p2.is_empty() and land != b:
				continue
			var length := float(p1.size() + p2.size())
			if length < best_len:
				best_len = length
				best = p1 if not p1.is_empty() else PackedVector2Array([cell_center(enter)])
				best.append_array(p2 if not p2.is_empty() else PackedVector2Array([cell_center(land)]))
	return best

func _grid_path(a: Vector2i, b: Vector2i) -> PackedVector2Array:
	if a == b:
		return PackedVector2Array([cell_center(b)])
	return astar.get_point_path(a, b)

## Line of sight: walls and closed doors block (furniture is low).
func los(a: Vector2, b: Vector2) -> bool:
	var dist := a.distance_to(b)
	var steps := int(ceil(dist / 8.0))
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / steps)
		var c := to_cell(p)
		var v := at(c)
		if v == WALL or v == VOID or (v == DOOR and closed_doors.has(c)):
			return false
	return true

func reachable_from_spawn() -> Dictionary:
	var seen := {spawn_cell: true}
	var stack: Array = [spawn_cell]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		var nexts: Array = [c + Vector2i(0, -1), c + Vector2i(-1, 0), c + Vector2i(0, 1), c + Vector2i(1, 0)]
		if _stair_cells.has(c):
			nexts.append(_stair_cells[c])
		for n in nexts:
			if walkable(n) and not seen.has(n):
				seen[n] = true
				stack.append(n)
	return seen

## Rooms directly connected to room_id (through a doorway or an open edge), same floor.
func neighbour_rooms(room_id: String) -> Array:
	var r := room(room_id)
	if r.is_empty():
		return []
	var me: int = r["index"]
	var out := {}
	var cs := {}
	for c in r["cells"]:
		cs[c] = true
	const DIRS := [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)]
	for d in doors:
		var sides := {}
		for o in DIRS:
			var v := at(d + o)
			if v >= 0:
				sides[v] = true
		if sides.has(me):
			for v in sides:
				if v != me:
					out[rooms[v]["id"]] = true
	for c in r["cells"]:
		for o in DIRS:
			var v := at(c + o)
			if v >= 0 and v != me and not cs.has(c + o):
				out[rooms[v]["id"]] = true
	return out.keys()

## Number of distinct doorways/open edges out of a room (escape routes).
func exits(room_id: String) -> int:
	var r := room(room_id)
	var cs := {}
	for c in r["cells"]:
		cs[c] = true
	var n := 0
	for d in doors:
		for o in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)]:
			if cs.has(d + o):
				n += 1
				break
	for c in r["cells"]:
		for o in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)]:
			var v := at(c + o)
			if v >= 0 and v != r["index"]:
				return n + 1
	return n
