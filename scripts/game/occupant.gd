class_name Occupant
extends Node2D
## Nervous house occupant with a name and a lightweight personality. Wanders
## between rooms, reacts to disturbances, mutters, and flees the house on the
## first major hunt or a severe reckless reaction.

var actor_id := "npc_1"
var run: Run
var map: HouseMap
var rng: RandomNumberGenerator
var token: TokenSprite
var token_path := ""
var person := {}          # {name, token, personality}
var traits := {}
var state := "wander"     # wander, idle, approach, flee, gone
var path := PackedVector2Array()
var path_i := 0
var wait_t := 0.0
var talk_t := 0.0
var react_cd := 0.0
var bitten := false
var tag: SpeechTag
var room_id := ""
var _jitter := 0.0

func setup(p_run: Run, id: String, p_person: Dictionary, start: Vector2) -> void:
	run = p_run
	map = run.map
	rng = run.rng
	actor_id = id
	person = p_person
	traits = Occupants.PERSONALITIES[person["personality"]]
	token_path = person["token"]
	position = start
	token = TokenSprite.new(token_path, 36.0)
	add_child(token)
	# Lives on an unlit text layer so the house darkness never hides it.
	tag = SpeechTag.new(run.world_text, person["name"])
	wait_t = rng.randf_range(0.5, 3.0)
	talk_t = rng.randf_range(6.0, 14.0)

func say(text: String) -> void:
	tag.say(text)
	run.on_say(actor_id, text)

func _line(kind: String) -> String:
	var lines: Array = traits[kind]
	return lines[rng.randi_range(0, lines.size() - 1)]

func bite() -> void:
	if bitten:
		return
	bitten = true
	token_path = Occupants.bitten_token(person["token"])
	token.set_token(token_path)
	run.sound_at("npc_gasp", position, -4.0)

func flee() -> void:
	if state == "flee" or state == "gone":
		return
	state = "flee"
	say(_line("flee"))
	run.sound_at("npc_flee", position, -2.0)
	path = map.path(position, HouseMap.cell_center(map.spawn_cell))
	path_i = 0

## A disturbance nearby (a bang, a scream, a rattle). Personality decides the response.
func react(at: Vector2) -> void:
	if state == "flee" or state == "gone" or react_cd > 0.0 or position.distance_to(at) > 320.0:
		return
	react_cd = 9.0
	if rng.randf() < 0.75:
		say(_line("react"))
	if traits["approach"] and rng.randf() < 0.6:
		path = map.path(position, at)
		path_i = 0
		state = "wander"
	elif traits["jitter"] > 0.5:
		_jitter = 0.0
		wait_t = maxf(wait_t, 1.5)

func _process(delta: float) -> void:
	if state == "gone":
		return
	room_id = map.room_at(position, room_id)
	react_cd = maxf(0.0, react_cd - delta)
	tag.update(position, modulate.a, delta)
	match state:
		"wander":
			if not _step(delta, traits["speed"]):
				state = "idle"
				wait_t = rng.randf_range(traits["idle"][0], traits["idle"][1])
		"idle":
			wait_t -= delta
			_jitter += delta
			token.face(token.facing + sin(_jitter * 3.0) * 0.6 * float(traits["jitter"]), delta, 3.0)
			if wait_t <= 0.0:
				_new_destination()
		"flee":
			if not _step(delta, 250.0):
				state = "gone"
				var tw := create_tween()
				tw.tween_property(self, "modulate:a", 0.0, 0.8)
				tw.tween_callback(func(): tag.set_visible(false))
				run.on_occupant_gone(self)
	if state == "wander" or state == "idle":
		talk_t -= delta
		if talk_t <= 0.0:
			talk_t = rng.randf_range(traits["talk"][0], traits["talk"][1])
			say(Occupants.BITTEN_LINES[rng.randi_range(0, 2)] if bitten and rng.randf() < 0.6 else _line("lines"))

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
	if to.length() > 90.0:
		position = path[path_i]   # staircase link between floors
		path_i += 1
	elif to.length() <= speed * delta:
		position = path[path_i]
		path_i += 1
	else:
		position += to.normalized() * speed * delta
		token.face(to.angle(), delta, 8.0)
	return path_i < path.size()
