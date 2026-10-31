extends Control
## The Forest Tavern: a rundown timber-and-stone tavern deep in a dark wood, seen
## from overhead in the same ink-and-wash, candle-and-shadow style as the houses.
## Walk about (WASD), speak with the regulars (E / Space), trade with the Witch.
## Esc (or the door) returns to the main menu. Never part of an investigation.

const INNER := Rect2(-430, -310, 860, 560)       # tavern floor
const WALL := 28.0
const DOOR_HALF := 48.0
const PATH := Rect2(-70, 250, 140, 520)          # the forest track south of the door
const TALK_RANGE := 92.0
## The upper floor is laid out in the same hub scene, far from the forest; the
## staircase is taken deliberately (E / Space), as in the investigations.
const UP := Vector2(0, -3200)
const STAIR := Vector2(-388, -15)               # same spot on both floors (floor-local)
const LEDGER := Vector2(330, 172)               # the ledger desk upstairs (floor-local)

## "floor": 1 = upstairs (positions are floor-local). "rumours": how many from the pool.
const NPCS := [
	{"id": "witch", "name": "Old Morwen", "role": "the Witch", "token": "tokens/occupant_c.png", "pos": Vector2(-300, -170), "face": 0.6, "tint": Color(0.75, 0.9, 0.75),
		"lines": ["Needles, child. Glass, silver, blood. Each one hears the dead a little better.",
			"Bring Gold Ducats and a name worth fearing, and we shall trade."]},
	{"id": "antiquarian", "name": "Ashby Crane", "role": "the Antiquarian", "token": "tokens/occupant_b.png", "pos": Vector2(-300, 150), "face": -0.4, "tint": Color(0.85, 0.82, 0.75),
		"lines": ["Reliquaries, bone saints, a hand of glory in vinegar... none of it is for sale.",
			"But I do buy results. Hard houses, good coin. Read the terms."]},
	{"id": "keeper", "name": "Gideon Tallow", "role": "the Tavern Keeper", "token": "tokens/occupant_a.png", "pos": Vector2(375, -80), "face": PI, "tint": Color(0.95, 0.85, 0.72),
		"lines": ["Sit, sit. The fire's free; the ale isn't."], "rumours": 2},
	{"id": "hunter", "name": "The Hooded Stranger", "role": "a hunter of bounties", "token": "tokens/investigator.png", "pos": Vector2(168, 212), "face": 0.0, "tint": Color(0.45, 0.42, 0.5),
		"lines": ["Contracts. Names. Bounties on things that should have stayed buried.",
			"Not yet. You haven't the scars for my kind of work."], "rumours": 1},
	{"id": "madam", "name": "Madame Severine", "role": "mistress of the upper rooms", "token": "tokens/occupant_e.png", "pos": Vector2(215, 150), "face": 0.0, "tint": Color(1.0, 0.8, 0.82), "floor": 1,
		"lines": ["Mind my carpets, hunter. They cost more than your coat and keep better secrets.",
			"Gentlemen climb those stairs with their names and go down without them. Discretion, love.",
			"The ledger stays on my desk. I've never locked it. Nobody has ever dared."], "rumours": 1},
	{"id": "lodger", "name": "Rosalind Ashe", "role": "a weary lodger", "token": "tokens/occupant_d.png", "pos": Vector2(-30, 150), "face": PI, "tint": Color(0.92, 0.82, 0.86), "floor": 1,
		"lines": ["Another long night. The walls up here are thin, and the dead are dreadful gossips.",
			"Madame keeps the lamps red. Kinder to tired faces, she says."], "rumours": 1},
]
## Short folklore heard over the ale: merchants, curious wares, opportunities, danger.
const RUMOURS := [
	"They say the Rectory bell rings at three, and nobody has pulled its rope in forty years.",
	"A hunter came through last week soaked to the bone. Said the sea followed him home.",
	"Pay for your ale. The last one who didn't still walks my cellar.",
	"Mind the Manor's west wing. Doors there open for folk who never knocked.",
	"Somebody's been leaving salt on my doorstep. Can't say I mind.",
	"Old Morwen keeps her finest needles under the floorboards. Silver for those with a name.",
	"Crane pays gold for houses no sane hunter would enter. Ask him for his terms.",
	"A pedlar of relics was seen on the Saltmarsh road. Only trades when the moon runs red.",
	"There's a needle forged where the Veil is thin. Points before the dead have moved, they say.",
	"Gideon has jobs he won't offer strangers. Pays in names, not coin.",
	"Madame upstairs keeps a ledger. Half the valley's sins are in it, in their own hand.",
	"The Black Lantern's cellar door was bricked up. Something has been unbricking it.",
	"Hollow Lane's chimney smokes, and nobody's lit a fire there since the harvest went bad.",
	"When the moon bleeds, the hungry ones grow bold. Hunt by daylight if you've any sense.",
	"Abyssal houses don't give back what they take. Ask the widow Prewett. Ask her husband.",
	"A drowned man's lantern still burns at the Harbour. It shows what hides, if you dare look.",
	"Marrow Street pays its debts in bone. Don't go collecting there unless you mean it.",
	"Crane's Blackwood signet? Sixty years on the same cold hand. Nobody's prised it off yet.",
]

var world: Node2D
var camera: Camera2D
var player: TokenSprite
var lantern: PointLight2D
var shop: WitchShop
var board: MissionBoard
var plate: RankPlate
var npcs: Array = []           # NPCS with world positions
var floor_level := 0           # 0 = the tavern floor, 1 = upstairs
var _title: Label
var _fade: ColorRect
var _fading := false
var cheats: DevCheats
var _blockers: Array = []      # Rect2s the hunter cannot walk through
var _flames: Array = []
var _npc_nodes := {}
var _name_tags := {}
var _prompt: PanelContainer
var _prompt_label: Label
var _dialog: PanelContainer
var _dialog_name: Label
var _dialog_text: Label
var _talking := {}
var _line := 0
var _rumour := 0
var _t := 0.0
var _target := ""              # "npc:<id>" / "door" / ""

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Sfx.stop_loop("hunt")
	Sfx.start_loop("music", "music_menu", -10.0, 1.5)
	# A contract left under way (the game closed mid-run) is settled as failed.
	if not SaveData.progress().get("mission_active", {}).is_empty():
		Progression.settle_mission(SaveData.progress(), {}, -1)
		SaveData.save()
	_rumour = randi() % RUMOURS.size()
	for n in NPCS:
		var d: Dictionary = n.duplicate()
		d["floor"] = int(n.get("floor", 0))
		d["pos"] = n["pos"] + (UP if d["floor"] == 1 else Vector2.ZERO)
		npcs.append(d)
	_build_world()
	_build_ui()

# --- The world ------------------------------------------------------------------------

func _sprite(path: String, pos: Vector2, size: float, rot: float = 0.0, shadow: bool = true) -> Sprite2D:
	var t := Art.tex(path)
	var k := size / maxf(1.0, t.get_size().x)
	if shadow:
		var sh := Sprite2D.new()
		sh.texture = t
		sh.position = pos + Vector2(5, 7)
		sh.rotation = rot
		sh.scale = Vector2(k, k) * 1.02
		sh.modulate = Color(0, 0, 0, 0.5)
		world.add_child(sh)
	var s := Sprite2D.new()
	s.texture = t
	s.position = pos
	s.rotation = rot
	s.scale = Vector2(k, k)
	world.add_child(s)
	return s

## A solid piece of furniture: drawn and blocking.
func _solid(path: String, pos: Vector2, size: float, rot: float = 0.0) -> Sprite2D:
	var s := _sprite(path, pos, size, rot)
	var ext := s.texture.get_size() * s.scale.x * 0.5
	if absf(sin(rot)) > 0.7:
		ext = Vector2(ext.y, ext.x)
	_blockers.append(Rect2(pos - ext * 0.85, ext * 1.7))
	return s

func _ground(path: String, r: Rect2, tint: Color, uv_scale: float = 1.0) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.texture = Art.tex(path)
	poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	poly.polygon = pts
	var uv := PackedVector2Array()
	for p in pts:
		uv.append(p * uv_scale)
	poly.uv = uv
	poly.color = tint
	world.add_child(poly)
	return poly

func _light(pos: Vector2, color: Color, energy: float, scale: float, tex: String = "lights/candle.png", flicker: bool = true) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = Art.tex(tex)
	l.position = pos
	l.color = color
	l.energy = energy
	l.texture_scale = scale
	world.add_child(l)
	if flicker:
		l.set_meta("base", energy)
		_flames.append(l)
	return l

func _build_world() -> void:
	world = Node2D.new()
	add_child(world)
	var cm := CanvasModulate.new()
	cm.color = Color(0.1, 0.105, 0.16)
	world.add_child(cm)
	# Forest floor, the track and the tavern's boards.
	_ground("floors/grass.png", Rect2(-1500, -1200, 3000, 2600), Color(0.55, 0.62, 0.5))
	_ground("floors/dirt.png", Rect2(-560, -440, 1120, 830), Color(0.7, 0.66, 0.6, 0.85))
	var track := Polygon2D.new()
	track.texture = Art.tex("floors/dirt.png")
	track.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	track.polygon = PackedVector2Array([Vector2(-75, 270), Vector2(75, 270), Vector2(95, 520), Vector2(40, 820), Vector2(150, 1300),
		Vector2(-30, 1300), Vector2(-90, 820), Vector2(-40, 520)])
	track.uv = track.polygon
	world.add_child(track)
	_ground("floors/wood_dark.png", INNER, Color(0.9, 0.85, 0.8), 2.0)
	if Art.has("decor/grime.png"):
		_ground("decor/grime.png", INNER, Color(1, 1, 1, 0.55))
	_ground("floors/stone.png", Rect2(-150, -310, 300, 90), Color(0.8, 0.78, 0.76), 2.0)
	var walls := TavernWalls.new()
	walls.inner = INNER
	walls.thick = WALL
	walls.door_half = DOOR_HALF
	world.add_child(walls)
	var o := INNER.grow(WALL)
	_blockers.append(Rect2(o.position, Vector2(o.size.x, WALL)))                      # north
	_blockers.append(Rect2(o.position, Vector2(WALL, o.size.y)))                      # west
	_blockers.append(Rect2(Vector2(INNER.end.x, o.position.y), Vector2(WALL, o.size.y)))  # east
	_blockers.append(Rect2(Vector2(o.position.x, INNER.end.y), Vector2(o.size.x * 0.5 - DOOR_HALF, WALL)))
	_blockers.append(Rect2(Vector2(DOOR_HALF, INNER.end.y), Vector2(o.size.x * 0.5 - DOOR_HALF, WALL)))
	_furnish()
	_forest()
	_build_upstairs()
	for n in npcs:
		var pool := _sprite("lights/soft.png", n["pos"], 120, 0.0, false)
		pool.modulate = Color(0, 0, 0, 0.55)
		var tok := TokenSprite.new(n["token"], 50.0)
		tok.position = n["pos"]
		tok.face_now(n["face"])
		tok.modulate = n["tint"]
		world.add_child(tok)
		_npc_nodes[n["id"]] = tok
		_blockers.append(Rect2(n["pos"] - Vector2(20, 20), Vector2(40, 40)))
	player = TokenSprite.new("tokens/investigator.png", 40.0)
	player.position = Vector2(0, 190)
	player.face_now(-PI * 0.5)
	world.add_child(player)
	lantern = PointLight2D.new()
	lantern.texture = Art.tex("lights/soft.png")
	lantern.color = Color(1.0, 0.85, 0.6)
	lantern.energy = 0.55
	lantern.texture_scale = 1.3
	player.add_child(lantern)
	camera = Camera2D.new()
	camera.zoom = Vector2(0.92, 0.92)
	camera.position = Vector2(0, -20)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	world.add_child(camera)
	camera.make_current()

func _furnish() -> void:
	# The hearth: the room's heart and its brightest light.
	_solid("furniture/fireplace.png", Vector2(0, -292), 230)
	_sprite("furniture/woodpile.png", Vector2(170, -285), 110, 0.0)
	_sprite("items/embers.png", Vector2(0, -262), 70, 0.0, false)
	var fire := _light(Vector2(0, -250), Color(1.0, 0.5, 0.2), 1.3, 4.6)
	fire.set_meta("strong", true)
	_sprite("furniture/rug_round.png", Vector2(0, -150), 230, 0.3, false)
	_solid("furniture/armchair.png", Vector2(-95, -175), 70, 0.5)
	# The bar along the east wall; bottles on the racks behind the keeper.
	for y in [-210.0, -146.0, -82.0, -18.0, 46.0]:
		_solid("furniture/counter.png", Vector2(300, y), 66, PI * 0.5)
	_solid("furniture/wine_rack.png", Vector2(414, -190), 150, PI * 0.5)
	_solid("furniture/storage_shelf.png", Vector2(414, 30), 150, PI * 0.5)
	for b in [Vector2(296, -190), Vector2(304, -100), Vector2(298, 10)]:
		_sprite("items/hand_mirror.png" if b.y > 0 else "furniture/candelabra.png", b, 26, 0.0, false)
	_light(Vector2(340, -100), Color(1.0, 0.66, 0.34), 0.7, 2.4)
	_light(Vector2(340, 10), Color(1.0, 0.66, 0.34), 0.5, 1.8)
	_solid("furniture/barrel.png", Vector2(395, 200), 60)
	_solid("furniture/barrel.png", Vector2(345, 225), 54)
	# Weathered tables with guttering candles.
	for t in [[Vector2(-40, 60), 0.05], [Vector2(150, -10), -0.08]]:
		_solid("furniture/dining_table.png", t[0], 170, t[1])
		for c in [Vector2(-60, -64), Vector2(60, -64), Vector2(-60, 64), Vector2(60, 64)]:
			_sprite("furniture/chair.png", t[0] + c.rotated(t[1]), 44, (PI * 0.5 if c.y > 0 else -PI * 0.5) + t[1] + randf_range(-0.2, 0.2))
		_sprite("furniture/candelabra.png", t[0], 30, 0.0, false)
		_light(t[0] + Vector2(0, 70), Color(1.0, 0.62, 0.3), 0.6, 2.4)
	_solid("furniture/coffee_table.png", Vector2(230, 215), 90, 0.2)
	_sprite("furniture/candelabra.png", Vector2(230, 215), 24, 0.0, false)
	_light(Vector2(230, 215), Color(1.0, 0.6, 0.3), 0.55, 1.4)
	_sprite("furniture/broken_chair.png", Vector2(-170, -20), 44, 1.9)
	# The Witch's corner: books, a bubbling tub, sigil candles and a green glow.
	_solid("furniture/bookshelf.png", Vector2(-414, -170), 160, PI * 0.5)
	_solid("furniture/wash_tub.png", Vector2(-330, -260), 84)
	_light(Vector2(-330, -260), Color(0.45, 1.0, 0.5), 0.9, 1.6)
	for c in [Vector2(-250, -270), Vector2(-330, 40), Vector2(-230, -110)]:
		_sprite("items/sigil_candle_lit.png", c, 22, 0.0, false)
		_light(c, Color(1.0, 0.66, 0.3), 0.55, 1.0)
	_sprite("items/voodoo_doll.png", Vector2(-360, -110), 26, 0.4, false)
	# The Antiquarian's clutter of odd artifacts.
	_solid("furniture/old_trunk.png", Vector2(-380, 205), 100, 0.1)
	_solid("furniture/side_table.png", Vector2(-220, 210), 56)
	_sprite("items/music_box.png", Vector2(-226, 204), 24, 0.3, false)
	_sprite("items/locket.png", Vector2(-205, 222), 18, 0.0, false)
	_sprite("items/hand_mirror.png", Vector2(-380, 200), 26, 1.2, false)
	_solid("furniture/grandfather_clock.png", Vector2(-405, 80), 56, PI * 0.5)
	_light(Vector2(-220, 210), Color(0.9, 0.75, 0.55), 0.6, 1.5)
	# The staircase to the upper rooms, against the west wall.
	_stairs("furniture/stairs_up.png", STAIR)
	_light(STAIR + Vector2(40, 0), Color(1.0, 0.45, 0.38), 0.45, 1.4)
	# Cobwebs and dust in the corners.
	for c in [Vector2(-405, -285), Vector2(405, -285), Vector2(-405, 225)]:
		_sprite("decor/cobweb.png", c, 80, c.angle() + PI * 0.75, false)

## A flight of stairs against the west wall: solid, taken with E / Space beside it.
func _stairs(path: String, at: Vector2) -> void:
	_sprite(path, at, 84, -PI * 0.5, false)
	_blockers.append(Rect2(at - Vector2(42, 40), Vector2(80, 80)))

# --- Upstairs -------------------------------------------------------------------------
## Upper-floor layout (floor-local; walls are 12 thick). A corridor of small private
## rooms behind curtained doorways, a dressing room, a lounge, and the parlour.
const UP_DOORS := [-330.0, -147.0, 17.0, 182.0, 347.0]      # doorways off the corridor
const UP_ROOMS := [-147.0, 17.0, 182.0, 347.0]              # private room centres (x)

func _build_upstairs() -> void:
	var r := Rect2(INNER.position + UP, INNER.size)
	var back := _ground("floors/stone.png", r.grow(900), Color(0.02, 0.015, 0.015))
	back.texture = null
	_ground("floors/wood_dark.png", r, Color(0.78, 0.66, 0.6), 2.0)
	_ground("floors/carpet_red.png", Rect2(UP + Vector2(-250, -114), Vector2(680, 68)), Color(0.7, 0.45, 0.45), 1.5)
	_ground("floors/carpet_red.png", Rect2(UP + Vector2(46, -34), Vector2(384, 284)), Color(0.75, 0.5, 0.5), 1.5)
	_ground("floors/parquet.png", Rect2(UP + Vector2(-430, -310), Vector2(200, 184)), Color(0.75, 0.62, 0.55), 2.0)
	if Art.has("decor/grime.png"):
		_ground("decor/grime.png", r, Color(1, 1, 1, 0.35))
	var walls := TavernWalls.new()
	walls.inner = INNER
	walls.thick = WALL
	walls.door = false
	walls.position = UP
	world.add_child(walls)
	var o := r.grow(WALL)
	_blockers.append(Rect2(o.position, Vector2(o.size.x, WALL)))
	_blockers.append(Rect2(o.position, Vector2(WALL, o.size.y)))
	_blockers.append(Rect2(Vector2(r.end.x, o.position.y), Vector2(WALL, o.size.y)))
	_blockers.append(Rect2(Vector2(o.position.x, r.end.y), Vector2(o.size.x, WALL)))
	# Partitions: the corridor's north wall with its doorways, the room dividers,
	# and the parlour's walls with a curtained archway.
	var parts: Array = []
	var x := INNER.position.x
	for d in UP_DOORS:
		parts.append(Rect2(x, -126, d - 32.0 - x, 12))
		x = d + 32.0
	parts.append(Rect2(x, -126, INNER.end.x - x, 12))
	for px in [-230.0, -65.0, 100.0, 265.0]:
		parts.append(Rect2(px - 6, INNER.position.y, 12, 184))
	parts.append(Rect2(34, -46, 116, 12))
	parts.append(Rect2(230, -46, 200, 12))
	parts.append(Rect2(34, -46, 12, INNER.end.y + 46))
	var pw := Partitions.new()
	pw.rects = parts
	pw.position = UP
	world.add_child(pw)
	for p: Rect2 in parts:
		_blockers.append(Rect2(p.position + UP, p.size))
	_furnish_upstairs()

func _furnish_upstairs() -> void:
	var u := UP
	var red := Color(1.0, 0.4, 0.3)
	var deco := UpperDecor.new()
	deco.position = u
	# The landing: the stairs down, a fern, a lamp with a red silk shade.
	_stairs("furniture/stairs_down.png", u + STAIR)
	_light(u + STAIR + Vector2(60, 0), Color(1.0, 0.66, 0.42), 0.55, 1.6)
	_sprite("furniture/potted_plant.png", u + Vector2(-400, 215), 54, 0.0)
	_solid("furniture/floor_lamp.png", u + Vector2(-280, 225), 36)
	_light(u + Vector2(-280, 225), red, 0.8, 2.2)
	_sprite("furniture/rug_rect.png", u + Vector2(-330, 120), 130, PI * 0.5, false).modulate = Color(0.85, 0.55, 0.55)
	# Corridor sconces.
	for cx in [-200.0, 100.0, 330.0]:
		_light(u + Vector2(cx, -80), Color(1.0, 0.5, 0.36), 0.5, 1.5)
	# The private rooms: a canopy bed each, a nightstand, a red-shaded lamp.
	for i in UP_ROOMS.size():
		var cx: float = UP_ROOMS[i]
		var bed := Vector2(cx - 18, -238)
		_solid("furniture/bed_double.png", u + bed, 92)
		deco.canopies.append(Rect2(bed - Vector2(50, 66), Vector2(100, 132)))
		_solid("furniture/nightstand.png", u + Vector2(cx + 55, -282), 34)
		_sprite("furniture/candelabra.png", u + Vector2(cx + 55, -282), 18, 0.0, false)
		_light(u + Vector2(cx + 50, -260), red, 0.75, 1.9)
		deco.curtains.append(Vector2(cx, -120))
		if i == 1:
			_solid("furniture/washbasin.png", u + Vector2(cx + 58, -165), 40)
		elif i == 2:
			_solid("furniture/wardrobe.png", u + Vector2(cx + 62, -175), 54, PI * 0.5)
		elif i == 3:
			_sprite("furniture/chair.png", u + Vector2(cx + 50, -170), 38, 2.4)
	deco.gloves.append([Vector2(-120, -160), 0.4])
	deco.fans.append([Vector2(208, -150), 2.2])
	deco.gloves.append([Vector2(390, -140), -1.2])
	# The dressing room: mirrors over powder tables, a wardrobe, a stool.
	deco.curtains.append(Vector2(-330, -120))
	for mx in [-385.0, -285.0]:
		_solid("furniture/dresser.png", u + Vector2(mx, -275), 72)
		_sprite("furniture/wall_mirror.png", u + Vector2(mx, -302), 60, 0.0, false)
		deco.bottles.append(Vector2(mx - 20, -278))
		deco.bottles.append(Vector2(mx - 10, -272))
		deco.puffs.append(Vector2(mx + 18, -276))
		_light(u + Vector2(mx, -255), Color(1.0, 0.62, 0.42), 0.7, 1.4)
	_sprite("items/hand_mirror.png", u + Vector2(-300, -190), 22, 0.8, false)
	_sprite("furniture/chair.png", u + Vector2(-380, -215), 36, PI * 0.5)
	_solid("furniture/wardrobe.png", u + Vector2(-411, -175), 56, PI * 0.5)
	deco.fans.append([Vector2(-262, -165), 0.7])
	# The lounge: a piano, a settee, a low table with wine and a dropped fan.
	_solid("furniture/piano.png", u + Vector2(-150, 220), 120)
	_solid("furniture/sofa.png", u + Vector2(-140, 60), 110, PI)
	_solid("furniture/coffee_table.png", u + Vector2(-140, 128), 72)
	_sprite("furniture/candelabra.png", u + Vector2(-140, 128), 20, 0.0, false)
	_light(u + Vector2(-140, 128), Color(1.0, 0.55, 0.32), 0.6, 1.8)
	_solid("furniture/floor_lamp.png", u + Vector2(10, 225), 34)
	_light(u + Vector2(10, 225), red, 0.8, 2.1)
	deco.fans.append([Vector2(-60, 100), -0.5])
	deco.bottles.append(Vector2(-150, 122))
	# The parlour: the madam's ledger desk, a chaise, perfume, gloves left behind.
	deco.curtains.append(Vector2(190, -40))
	_sprite("furniture/rug_round.png", u + Vector2(220, 100), 200, 0.2, false).modulate = Color(0.95, 0.55, 0.55)
	_solid("furniture/desk_large.png", u + LEDGER, 120)
	_sprite("furniture/armchair.png", u + LEDGER + Vector2(0, 52), 56, PI)
	_sprite("furniture/candelabra.png", u + LEDGER + Vector2(-40, -6), 20, 0.0, false)
	_light(u + LEDGER + Vector2(0, -30), Color(1.0, 0.6, 0.35), 0.8, 2.0)
	deco.ledger = LEDGER
	_solid("furniture/sofa.png", u + Vector2(110, 200), 100, PI)
	deco.gloves.append([Vector2(100, 150), 2.6])
	deco.fans.append([Vector2(140, 172), 0.9])
	_solid("furniture/side_table.png", u + Vector2(400, 10), 48)
	for b in [Vector2(392, 2), Vector2(406, 6), Vector2(398, 18), Vector2(410, 20)]:
		deco.bottles.append(b)
	_solid("furniture/floor_lamp.png", u + Vector2(70, -10), 34)
	_light(u + Vector2(70, -10), red, 0.85, 2.3)
	_light(u + Vector2(400, 10), Color(1.0, 0.45, 0.4), 0.5, 1.3)
	world.add_child(deco)

func _forest() -> void:
	# Lanterns by the door, a woodpile, and a grave someone forgot.
	_solid("furniture/floor_lamp.png", Vector2(-95, 305), 40)
	_light(Vector2(-95, 305), Color(1.0, 0.72, 0.4), 1.0, 2.6)
	_solid("furniture/barrel.png", Vector2(110, 310), 50)
	_solid("furniture/crates.png", Vector2(520, -220), 90, 0.3)
	_sprite("furniture/gravestone.png", Vector2(-520, 360), 44, 0.2)
	_sprite("furniture/gravestone.png", Vector2(-470, 410), 40, -0.3)
	# Cold moonlight through the canopy.
	_light(Vector2(-650, -500), Color(0.5, 0.6, 0.95), 0.55, 6.0, "lights/soft.png", false)
	_light(Vector2(700, 520), Color(0.45, 0.55, 0.9), 0.35, 5.0, "lights/soft.png", false)
	# A dense, deterministic ring of dark trees around the clearing.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1888
	var clear := INNER.grow(110.0)
	var placed := 0
	var tries := 0
	while placed < 170 and tries < 4000:
		tries += 1
		var p := Vector2(rng.randf_range(-1450, 1450), rng.randf_range(-1150, 1350))
		if clear.has_point(p) or (absf(p.x - _track_x(p.y)) < 120.0 and p.y > 200.0):
			continue
		var s := rng.randf_range(150, 290)
		var tr := _sprite("furniture/tree.png", p, s, rng.randf() * TAU)
		var k := rng.randf_range(0.45, 0.75)
		tr.modulate = Color(k, k * 1.05, k * 1.02)
		placed += 1

func _track_x(y: float) -> float:
	if y < 520.0:
		return 0.0
	return -25.0 + (y - 520.0) * 0.08

# --- Interface ------------------------------------------------------------------------

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	var vig := TextureRect.new()
	vig.texture = Art.tex("ui/vignette.png")
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vig)
	_title = Art.heading("The Forest Tavern", 38, Color(0.93, 0.85, 0.65))
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_title.add_theme_constant_override("outline_size", 8)
	_title.position = Vector2(28, 18)
	root.add_child(_title)
	var help := Art.label("WASD to walk  ·  E / Space to speak or take the stairs  ·  Esc to leave", 16, Color(0.85, 0.8, 0.7), Art.font_italic)
	help.add_theme_color_override("font_outline_color", Color.BLACK)
	help.add_theme_constant_override("outline_size", 5)
	help.position = Vector2(30, 66)
	root.add_child(help)
	plate = RankPlate.new()
	plate.anchor_left = 1.0
	plate.anchor_right = 1.0
	plate.offset_left = -360
	plate.offset_right = -20
	plate.offset_top = 18
	root.add_child(plate)
	# Interaction prompt chip (as in the houses).
	_prompt = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.05, 0.82)
	sb.border_color = Color(Art.GOLD.r, Art.GOLD.g, Art.GOLD.b, 0.85)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(7)
	sb.set_content_margin_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	_prompt.add_theme_stylebox_override("panel", sb)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.visible = false
	root.add_child(_prompt)
	for n in npcs:
		var tag := Art.label(n["name"], 14, Color(0.86, 0.8, 0.68, 0.75), Art.font_italic)
		tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		tag.add_theme_constant_override("outline_size", 5)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tag)
		_name_tags[n["id"]] = tag
	_prompt_label = Art.label("", 15, Color(0.93, 0.88, 0.76), Art.font_heading)
	_prompt.add_child(_prompt_label)
	# Dialogue at the foot of the screen.
	_dialog = PanelContainer.new()
	_dialog.anchor_left = 0.5
	_dialog.anchor_right = 0.5
	_dialog.anchor_top = 1.0
	_dialog.anchor_bottom = 1.0
	_dialog.offset_left = -420
	_dialog.offset_right = 420
	_dialog.offset_top = -160
	_dialog.offset_bottom = -24
	_dialog.visible = false
	root.add_child(_dialog)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 4)
	_dialog.add_child(dv)
	_dialog_name = Art.heading("", 24, Art.BLOOD)
	dv.add_child(_dialog_name)
	_dialog_text = Art.label("", 19, Art.INK, Art.font_italic)
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dv.add_child(_dialog_text)
	var more := Art.label("E / Space — continue   ", 13, Color(0.4, 0.3, 0.2), Art.font_heading)
	more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dv.add_child(more)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	shop = WitchShop.new()
	shop.visible = false
	cc.add_child(shop)
	shop.changed.connect(func(): plate.refresh())
	board = MissionBoard.new()
	board.visible = false
	cc.add_child(board)
	cheats = DevCheats.new()
	cheats.offset_top = 150
	root.add_child(cheats)
	cheats.changed.connect(func():
		plate.refresh()
		shop.refresh()
		if board.visible:
			board.refresh())
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	_fit_shop()

func _fit_shop() -> void:
	var w := get_viewport().get_visible_rect().size.x if get_viewport() else 1600.0
	shop.custom_minimum_size.x = minf(760.0, w - 60.0)
	board.custom_minimum_size.x = minf(800.0, w - 60.0)

# --- Play -----------------------------------------------------------------------------

func _busy() -> bool:
	return shop.visible or _dialog.visible or board.visible or _fading

func _origin() -> Vector2:
	return UP if floor_level == 1 else Vector2.ZERO

func _process(delta: float) -> void:
	_t += delta
	for i in _flames.size():
		var l: PointLight2D = _flames[i]
		var amp := 0.14 if l.has_meta("strong") else 0.08
		l.energy = float(l.get_meta("base")) * (1.0 + sin(_t * 7.0 + i * 1.7) * amp + sin(_t * 19.0 + i) * amp * 0.5)
	if not _busy():
		_walk(delta)
	# Regulars glance at the hunter when close.
	for n in npcs:
		var tok: TokenSprite = _npc_nodes[n["id"]]
		var d := player.position.distance_to(n["pos"])
		tok.face((player.position - n["pos"]).angle() if d < 200.0 else n["face"], delta, 3.0)
	camera.position = player.position.lerp(_origin() + Vector2(0, -20), 0.55)
	var xf := get_viewport().get_canvas_transform()
	for n in npcs:
		var tag: Label = _name_tags[n["id"]]
		tag.visible = n["floor"] == floor_level
		tag.position = xf * (n["pos"] + Vector2(0, 30)) - Vector2(tag.size.x * 0.5, 0)
	_update_prompt()

func _walk(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir == Vector2.ZERO:
		return
	var speed := 300.0 if Input.is_action_pressed("sprint") else 210.0
	var step := dir * speed * delta
	for axis in [Vector2(step.x, 0), Vector2(0, step.y)]:
		var np: Vector2 = player.position + axis
		if _walkable(np):
			player.position = np
	player.face(dir.angle(), delta, 14.0)

func _walkable(p: Vector2) -> bool:
	var inside := INNER.grow(-16.0).has_point(p) or Rect2(-DOOR_HALF + 16, INNER.end.y - 20, DOOR_HALF * 2 - 32, WALL + 60).has_point(p) or PATH.has_point(p)
	if floor_level == 1:
		inside = INNER.grow(-16.0).has_point(p - UP)
	if not inside:
		return false
	var body := Rect2(p - Vector2(14, 14), Vector2(28, 28))
	for r in _blockers:
		if r.intersects(body):
			return false
	return true

func _nearest_target() -> String:
	var o := _origin()
	if floor_level == 0 and player.position.distance_to(Vector2(0, INNER.end.y + 10)) < 70.0:
		return "door"
	if player.position.distance_to(o + STAIR) < 85.0:
		return "stairs"
	if floor_level == 1 and player.position.distance_to(o + LEDGER) < 90.0:
		return "ledger"
	var best := ""
	var best_d := TALK_RANGE
	for n in npcs:
		var d := player.position.distance_to(n["pos"])
		if n["floor"] == floor_level and d < best_d:
			best_d = d
			best = "npc:" + n["id"]
	return best

func _npc(id: String) -> Dictionary:
	for n in npcs:
		if n["id"] == id:
			return n
	return {}

func _update_prompt() -> void:
	_target = "" if _busy() else _nearest_target()
	_prompt.visible = _target != ""
	if _target == "":
		return
	var at := Vector2(0, INNER.end.y + 10)
	var text := "E / SPACE — Leave the tavern"
	if _target == "stairs":
		at = _origin() + STAIR
		text = "E / SPACE — Climb the stairs" if floor_level == 0 else "E / SPACE — Go back down"
	elif _target == "ledger":
		at = _origin() + LEDGER
		text = "E / SPACE — Leaf through the ledger"
	elif _target.begins_with("npc:"):
		var n := _npc(_target.substr(4))
		at = n["pos"]
		text = "E / SPACE — Speak with %s, %s" % [n["name"], n["role"]]
	if _prompt_label.text != text:
		_prompt_label.text = text
		_prompt.reset_size()
	var screen: Vector2 = get_viewport().get_canvas_transform() * at
	var vs := get_viewport().get_visible_rect().size
	_prompt.position = Vector2(clampf(screen.x - _prompt.size.x * 0.5, 10.0, vs.x - _prompt.size.x - 10.0), clampf(screen.y - _prompt.size.y - 42.0, 100.0, vs.y - 60.0))

func talk(id: String) -> void:
	var n := _npc(id)
	if n.is_empty():
		return
	_line = 0
	var lines: Array = n["lines"].duplicate()
	if id in ["madam", "lodger"]:
		lines = [lines[_rumour % lines.size()]]   # one of their own lines, in turn
	for i in int(n.get("rumours", 0)):
		lines.append(RUMOURS[_rumour % RUMOURS.size()])
		_rumour += 1
	if id == "keeper":
		if SaveData.progress().get("blackmail_keeper", false):
			lines.append("...You've been upstairs, reading. Fine. I've work for you. And you never saw that page.")
		else:
			lines.append("My other jobs? Not for strangers. Not unless you've something on me. Nobody has.")
	_talking = n.duplicate()
	_talking["lines"] = lines
	_dialog.visible = true
	_dialog_name.text = "%s, %s" % [n["name"], n["role"]]
	_show_line()

## The madam's ledger: read once to learn the keeper's secret (blackmail_keeper).
func read_ledger() -> void:
	var p := SaveData.progress()
	var lines := ["Initials, dates and sums in a neat, merciless hand. You already know the page that matters."]
	if not p.get("blackmail_keeper", false):
		p["blackmail_keeper"] = true
		SaveData.save()
		lines = ["Initials, dates and sums in a neat, merciless hand. Half the valley is in here.",
			"One entry, every Thursday for three years: “G. Tallow. The blue room. Settled in church silver.”",
			"The poor-box of St. Evangeline went missing three years ago. Gideon Tallow will want to talk."]
	_talking = {"id": "ledger", "lines": lines, "narrate": true}
	_line = 0
	_dialog.visible = true
	_dialog_name.text = "The Madam's Ledger"
	_show_line()

func _show_line() -> void:
	var t: String = _talking["lines"][_line]
	_dialog_text.text = t if _talking.get("narrate", false) else "“%s”" % t

func _advance() -> void:
	_line += 1
	if _line < _talking["lines"].size():
		_show_line()
		return
	_dialog.visible = false
	if _talking["id"] == "witch":
		open_shop()
	elif _talking["id"] == "antiquarian":
		open_missions("antiquarian")
	elif _talking["id"] == "keeper":
		open_missions("keeper")   # locked until you hold his secret; the board says so

func open_shop() -> void:
	_fit_shop()
	shop.refresh()
	shop.visible = true

func open_missions(giver: String) -> void:
	_fit_shop()
	board.open(giver)

## Up or down the stairs: a short fade, then you stand on the other floor's landing.
func take_stairs() -> void:
	if _fading:
		return
	_fading = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.18)
	tw.tween_callback(func():
		floor_level = 1 - floor_level
		player.position = _origin() + STAIR + Vector2(78, 0)
		player.face_now(0.0)
		camera.position = player.position.lerp(_origin() + Vector2(0, -20), 0.55)
		camera.reset_smoothing()
		_title.text = "The Forest Tavern" if floor_level == 0 else "The Upper Rooms"
		Sfx.play("footstep", -2.0, 0.7))
	tw.tween_property(_fade, "color:a", 0.0, 0.25)
	tw.tween_callback(func(): _fading = false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if shop.visible:
				shop.visible = false
			elif board.visible:
				board.visible = false
			elif _dialog.visible:
				_dialog.visible = false
			else:
				Game.goto_menu()
			get_viewport().set_input_as_handled()
		elif event.is_action("interact"):
			if _dialog.visible:
				_advance()
			elif shop.visible or board.visible or _fading:
				return
			elif _target == "door":
				Game.goto_menu()
			elif _target == "stairs":
				take_stairs()
			elif _target == "ledger":
				read_ledger()
			elif _target.begins_with("npc:"):
				talk(_target.substr(4))
			get_viewport().set_input_as_handled()

## Timber-framed stone walls with a doorway in the south wall.
class TavernWalls extends Node2D:
	var inner: Rect2
	var thick := 28.0
	var door_half := 48.0
	var door := true               # false: an unbroken south wall (the upper floor)
	func _draw() -> void:
		var cap := Art.tex("walls/wall_top.png")
		var o := inner.grow(thick)
		var dh := door_half if door else 0.0
		var segs := [Rect2(o.position, Vector2(o.size.x, thick)), Rect2(o.position, Vector2(thick, o.size.y)),
			Rect2(Vector2(inner.end.x, o.position.y), Vector2(thick, o.size.y)),
			Rect2(Vector2(o.position.x, inner.end.y), Vector2(o.size.x * 0.5 - dh, thick)),
			Rect2(Vector2(dh, inner.end.y), Vector2(o.size.x * 0.5 - dh, thick))]
		for r: Rect2 in segs:
			var x := r.position.x
			while x < r.end.x:
				var y := r.position.y
				var w := minf(thick, r.end.x - x)
				while y < r.end.y:
					var h := minf(thick, r.end.y - y)
					var src := Rect2(Vector2(posmod(int(x / thick), 4), posmod(int(y / thick), 4)) * 32.0, Vector2(32, 32) * Vector2(w, h) / thick)
					draw_texture_rect_region(cap, Rect2(x, y, w, h), src, Color(0.8, 0.76, 0.72))
					y += thick
				x += thick
			draw_rect(r, Art.INK, false, 2.0)
		# Timber beams at intervals along the walls.
		var beam := Color(0.24, 0.15, 0.08)
		var bx := o.position.x + 120.0
		while bx < o.end.x - 60.0:
			if absf(bx) > door_half + 20.0:
				draw_rect(Rect2(bx - 7, o.position.y - 2, 14, thick + 4), beam)
				draw_rect(Rect2(bx - 7, inner.end.y - 2, 14, thick + 4), beam)
			bx += 170.0
		var by := o.position.y + 120.0
		while by < o.end.y - 60.0:
			draw_rect(Rect2(o.position.x - 2, by - 7, thick + 4, 14), beam)
			draw_rect(Rect2(inner.end.x - 2, by - 7, thick + 4, 14), beam)
			by += 170.0
		# Threshold and an open, sagging door.
		if door:
			draw_rect(Rect2(-door_half, inner.end.y, door_half * 2, thick), Color(0.3, 0.22, 0.14))
			draw_line(Vector2(-door_half, inner.end.y + thick), Vector2(-door_half + 14, inner.end.y + thick + 74), Color(0.32, 0.2, 0.1), 9.0)
			draw_line(Vector2(-door_half, inner.end.y + thick), Vector2(-door_half + 14, inner.end.y + thick + 74), Art.INK, 2.0)
		# Soft inner shadow where the walls meet the floor.
		for i in 6:
			var a := 0.16 - i * 0.025
			draw_rect(inner.grow(-i * 3.0), Color(0, 0, 0, a), false, 3.0)

## Thin lath-and-plaster partitions with timber edges (the upper floor).
class Partitions extends Node2D:
	var rects: Array = []
	func _draw() -> void:
		for r: Rect2 in rects:
			draw_rect(r, Color(0.42, 0.33, 0.27))
			draw_rect(r.grow(-2.0), Color(0.55, 0.45, 0.38))
			draw_rect(r, Color(0.2, 0.12, 0.07), false, 2.0)

## Soft furnishings drawn by hand: curtained doorways, bed canopies, perfume
## bottles, powder puffs, dropped gloves and fans, and the open ledger.
class UpperDecor extends Node2D:
	const VELVET := Color(0.46, 0.06, 0.09)
	var curtains: Array = []       # doorway centres (gap 64, horizontal walls)
	var canopies: Array = []       # Rect2 over each bed
	var bottles: Array = []
	var puffs: Array = []
	var gloves: Array = []         # [pos, angle]
	var fans: Array = []           # [pos, angle]
	var ledger := Vector2.INF

	func _draw() -> void:
		for c: Vector2 in curtains:
			# Heavy drapes gathered to either side of the doorway, a rod above.
			draw_line(c + Vector2(-36, 0), c + Vector2(36, 0), Color(0.55, 0.42, 0.18), 3.0)
			for s in [-1.0, 1.0]:
				var pts := PackedVector2Array([c + Vector2(32 * s, -7), c + Vector2(17 * s, -5), c + Vector2(21 * s, 7), c + Vector2(32 * s, 8)])
				draw_colored_polygon(pts, VELVET)
				draw_polyline(pts, Color(0.2, 0.02, 0.03), 1.5)
				draw_circle(c + Vector2(22 * s, 1), 2.0, Color(0.8, 0.62, 0.25))
			# A sheer veil left half-drawn across the gap.
			draw_rect(Rect2(c + Vector2(-17, -4), Vector2(18, 8)), Color(0.75, 0.25, 0.3, 0.35))
		for r: Rect2 in canopies:
			# Four posts and a gauzy canopy with swagged edges.
			draw_rect(r, Color(0.6, 0.12, 0.16, 0.28))
			for i in 4:
				var y := r.position.y + r.size.y * (i + 0.5) / 4.0
				draw_line(Vector2(r.position.x + 4, y), Vector2(r.end.x - 4, y), Color(0.85, 0.4, 0.42, 0.18), 2.0)
			draw_rect(r, Color(0.35, 0.05, 0.08, 0.9), false, 3.0)
			for p in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
				draw_circle(p, 5.0, Color(0.25, 0.14, 0.07))
				draw_circle(p, 2.5, Color(0.75, 0.55, 0.2))
		for i in bottles.size():
			var b: Vector2 = bottles[i]
			var glass: Color = [Color(0.9, 0.35, 0.55, 0.85), Color(0.5, 0.75, 0.9, 0.85), Color(0.95, 0.75, 0.35, 0.85)][i % 3]
			draw_circle(b, 4.5, glass)
			draw_circle(b + Vector2(-1.5, -1.5), 1.5, Color(1, 1, 1, 0.7))
			draw_rect(Rect2(b + Vector2(-1.5, -8), Vector2(3, 4)), Color(0.8, 0.65, 0.3))
		for p: Vector2 in puffs:
			draw_circle(p, 6.0, Color(0.98, 0.9, 0.88))
			draw_circle(p + Vector2(10, 4), 3.0, Color(0.92, 0.85, 0.8, 0.6))
		for g in gloves:
			draw_set_transform(g[0], g[1], Vector2.ONE)
			draw_rect(Rect2(-14, -3, 22, 6), Color(0.92, 0.88, 0.82))
			for f in 4:
				draw_line(Vector2(8, -3 + f * 2), Vector2(13, -4 + f * 2.6), Color(0.92, 0.88, 0.82), 1.5)
			draw_rect(Rect2(-14, -3, 22, 6), Color(0.3, 0.25, 0.2, 0.6), false, 1.0)
		for f in fans:
			draw_set_transform(f[0], f[1], Vector2.ONE)
			var pts := PackedVector2Array([Vector2.ZERO])
			for k in 9:
				pts.append(Vector2.from_angle(-PI * 0.85 + k * PI * 0.7 / 8.0) * 18.0)
			draw_colored_polygon(pts, Color(0.12, 0.08, 0.1))
			for k in 9:
				draw_line(Vector2.ZERO, pts[k + 1], Color(0.8, 0.6, 0.3, 0.8), 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if ledger != Vector2.INF:
			# The open ledger on the desk, and its red ribbon.
			var l := ledger + Vector2(10, -4)
			draw_rect(Rect2(l + Vector2(-20, -13), Vector2(40, 26)), Color(0.93, 0.88, 0.76))
			draw_line(l + Vector2(0, -13), l + Vector2(0, 13), Color(0.4, 0.3, 0.2), 1.5)
			for k in 5:
				draw_line(l + Vector2(-17, -8 + k * 4), l + Vector2(-3, -8 + k * 4), Color(0.3, 0.25, 0.2, 0.7), 1.0)
				draw_line(l + Vector2(3, -8 + k * 4), l + Vector2(17, -8 + k * 4), Color(0.3, 0.25, 0.2, 0.7), 1.0)
			draw_line(l + Vector2(2, 13), l + Vector2(6, 24), Color(0.7, 0.08, 0.1), 2.0)
