class_name ReplayRecorder
extends RefCounted
## Records actual run state for faithful playback: actor tracks sampled at HZ
## plus discrete world events. Playback (scripts/replay/replay_player.gd) only
## reads this data; it never runs gameplay logic.

const HZ := 15.0
const FORMAT_VERSION := 1

var data := {}
var _acc := 0.0
var _last_token := {}

func _init(house_id: String, run_seed: int) -> void:
	data = {"version": FORMAT_VERSION, "house": house_id, "seed": run_seed, "hz": HZ,
		"actors": {}, "tracks": {}, "events": [], "duration": 0.0}

func register_actor(actor_id: String, kind: String, token: String, diameter: float) -> void:
	data["actors"][actor_id] = {"kind": kind, "token": token, "size": diameter}
	data["tracks"][actor_id] = []
	_last_token[actor_id] = token

## actors: {actor_id: [pos: Vector2, rot: float, alpha: float, token: String]}
func tick(t: float, delta: float, actors: Dictionary) -> void:
	_acc += delta
	if _acc < 1.0 / HZ:
		return
	_acc = fmod(_acc, 1.0 / HZ)
	sample(t, actors)

func sample(t: float, actors: Dictionary) -> void:
	data["duration"] = t
	for aid in actors:
		if not data["tracks"].has(aid):
			continue
		var a: Array = actors[aid]
		var tr: Array = data["tracks"][aid]
		var pos: Vector2 = a[0]
		tr.append_array([snappedf(t, 0.01), snappedf(pos.x, 0.1), snappedf(pos.y, 0.1), snappedf(a[1], 0.01), snappedf(a[2], 0.01)])
		if a.size() > 3 and a[3] != _last_token.get(aid, ""):
			_last_token[aid] = a[3]
			event(t, "token", {"actor": aid, "token": a[3]})

func event(t: float, type: String, payload: Dictionary = {}) -> void:
	data["events"].append([snappedf(t, 0.01), type, payload])

func finish(t: float, outcome: String) -> Dictionary:
	event(t, "end", {"outcome": outcome})
	data["duration"] = t
	return data

func digest() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(JSON.stringify(data["events"]).to_utf8_buffer())
	return ctx.finish().hex_encode()
