class_name Occupant
extends Node2D
## Nervous house occupant. Wanders between rooms, mutters, and flees the house
## on the first major hunt or a severe reckless reaction.

const LINES := [
	"Did you hear that?", "It's colder in here, isn't it?", "I'm not staying in this room.",
	"Something moved the chair again.", "Please hurry.", "It knows my name.", "Don't look at the mirror.",
	"Was that you breathing?", "I keep finding the door open.", "The clock stopped at three again.",
	"I'll just... stand over here.", "Are you sure you're qualified?",
]
const BITTEN_LINES := ["My neck... itches.", "I feel so terribly tired.", "Why is it so bright in here?"]
const FLEE_LINES := ["I'm leaving!", "Not today!", "You're on your own!", "Forget the deposit!"]

var actor_id := "npc_1"
var run: Run
var map: HouseMap
var rng: RandomNumberGenerator
var token: TokenSprite
var token_path := ""
var state := "wander"   # wander, idle, flee, gone
var path := PackedVector2Array()
var path_i := 0
var wait_t := 0.0
var talk_t := 0.0
var bitten := false
var bubble: Label
var _bubble_t := 0.0
var room_id := ""
var _jitter := 0.0

func setup(p_run: Run, id: String, token_file: String, start: Vector2) -> void:
	run = p_run
	map = run.map
	rng = run.rng
	actor_id = id
	token_path = token_file
	position = start
	token = TokenSprite.new(token_file, 36.0)
	add_child(token)
	bubble = Label.new()
	bubble.add_theme_font_override("font", Art.font_italic)
	bubble.add_theme_font_size_override("font_size", 13)
	bubble.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	bubble.add_theme_color_override("font_outline_color", Color.BLACK)
	bubble.add_theme_constant_override("outline_size", 5)
	bubble.size = Vector2(200, 20)
	bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble.modulate.a = 0.0
	# Lives on an unlit text layer so the house darkness never hides it.
	run.world_text.add_child(bubble)
	wait_t = rng.randf_range(0.5, 3.0)
	talk_t = rng.randf_range(8.0, 20.0)

func say(text: String) -> void:
	bubble.text = text
	_bubble_t = 3.0

func bite() -> void:
	if bitten:
		return
	bitten = true
	token_path = "tokens/occupant_bitten.png"
	token.set_token(token_path)
	Sfx.play_at("npc_gasp", position, run.world, -4.0)

func flee() -> void:
	if state == "flee" or state == "gone":
		return
	state = "flee"
	say(FLEE_LINES[rng.randi_range(0, FLEE_LINES.size() - 1)])
	Sfx.play_at("npc_flee", position, run.world, -2.0)
	path = map.path(position, HouseMap.cell_center(map.spawn_cell))
	path_i = 0

func _process(delta: float) -> void:
	if state == "gone":
		return
	room_id = map.room_at(position, room_id)
	_bubble_t -= delta
	bubble.position = position + Vector2(-100, -42)
	bubble.modulate.a = clampf(_bubble_t, 0.0, 1.0) * modulate.a
	match state:
		"wander":
			if not _step(delta, 70.0):
				state = "idle"
				wait_t = rng.randf_range(2.0, 6.0)
		"idle":
			wait_t -= delta
			_jitter += delta
			token.face(token.facing + sin(_jitter * 3.0) * 0.6, delta, 3.0)
			if wait_t <= 0.0:
				_new_destination()
		"flee":
			if not _step(delta, 250.0):
				state = "gone"
				var tw := create_tween()
				tw.tween_property(self, "modulate:a", 0.0, 0.8)
				tw.parallel().tween_property(bubble, "modulate:a", 0.0, 0.8)
				run.on_occupant_gone(self)
	if state == "wander" or state == "idle":
		talk_t -= delta
		if talk_t <= 0.0:
			talk_t = rng.randf_range(12.0, 26.0)
			var lines := BITTEN_LINES if bitten and rng.randf() < 0.6 else LINES
			say(lines[rng.randi_range(0, lines.size() - 1)])

func _new_destination() -> void:
	var rooms := map.indoor_rooms()
	var r: Dictionary = rooms[rng.randi_range(0, rooms.size() - 1)]
	path = map.path(position, HouseMap.cell_center(map.random_free_cell(r["id"], rng)))
	path_i = 0
	state = "wander"

func _step(delta: float, speed: float) -> bool:
	if path_i >= path.size():
		return false
	var to := path[path_i] - position
	if to.length() <= speed * delta:
		position = path[path_i]
		path_i += 1
	else:
		position += to.normalized() * speed * delta
		token.face(to.angle(), delta, 8.0)
	return path_i < path.size()
