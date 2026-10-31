class_name Creature
extends Node2D
## The entity inhabiting the house. One class, behaviour tuned by Defs.CREATURES
## plus a few type-specific branches (vampire ambush, werewolf pursuit,
## shapeshifter forms, Harbinger binding). Gameplay decisions about threat and
## vanquishing live in Run; this node moves, hunts and shows itself.

signal hunt_started(creature)
signal hunt_ended(creature, hit_player: bool)

const CONTACT_RADIUS := 24.0
const WARN_TIME := 2.5

var actor_id := "creature_1"
var type_id := ""
var def := {}
var run: Run
var map: HouseMap
var rng: RandomNumberGenerator
var lair_room := ""
var room_id := ""
var state := "roam"      # roam, warn, hunt, stunned, bound, banished
var token: TokenSprite
var glow: PointLight2D
var alpha := 0.0
var target_alpha := 0.0
var path := PackedVector2Array()
var path_i := 0
var wait_t := 0.0
var state_t := 0.0
var hunt_count := 0
var hunt_reckless := false
var hunt_hit := false
var cooldown_t := 0.0
var repath_t := 0.0
var last_seen := Vector2.INF
var chase_speed := 0.0
var manifest_t := 0.0
var form := ""            # shapeshifter appearance (never changes its identity)
var form_t := 0.0
var exposed_t := 0.0
var weakened_t := 0.0
var stunned_t := 0.0
var transformations := 0
var slowed_t := 0.0
var target: Player = null
var tag: SpeechTag          # shapeshifter human disguise: same name tag as an occupant
var _talk_t := 8.0
var angered_t := 0.0        # voodoo doll: enraged flesh-and-blood creature
var wrath := false          # Lost One: its keepsake was touched
# Home room: the entity lives in lair_room, makes short excursions into one or
# two neighbouring rooms, comes back and settles before wandering again. Hunts
# and pursuit ignore all of this and go anywhere in the house.
var _excursion: Array = []  # rooms still to visit on the current excursion
var _settle_t := 0.0        # time left resting at home before the next excursion
# The Weeper stops to cry (even mid-hunt); the Mimic glitches now and then.
var _cry_t := 6.0
var _crying_t := 0.0
var _sob_t := 3.0
var _glitch_t := 10.0
var _glitch_left := 0.0
var wrath_target: Player = null
# Blightness: rush in a straight line, stop, shake/recover ~0.5 s, pick a new line.
const BLIGHT_RUSH_SPEED := {"roam": 430.0, "hunt": 640.0}
const BLIGHT_RUSH_REACH := {"roam": 140.0, "hunt": 200.0}
var _rush_dir := Vector2.ZERO
var _rush_left := 0.0
var _rush_target_i := -1
var _recover_t := 0.0
var _rushes := 0
var _distort: ShaderMaterial
var wolf := false           # werewolf: human until dread brings the full moon
var reverted := false       # werewolf / shapeshifter after banishment: their human form
var _show_t := 0.0          # forced visibility (transformations, defeat)

const GLISTEN_SHADER := """
shader_type canvas_item;
uniform float t = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.3, 0.59, 0.11)) * 1.1 + 0.08;
	float band = pow(max(0.0, sin((UV.x + UV.y * 0.7) * 11.0 - t * 4.0)), 16.0);
	float spark = pow(max(0.0, sin(UV.x * 63.0 + t * 2.0) * sin(UV.y * 57.0 - t * 1.7)), 40.0);
	COLOR = vec4(vec3(g) + band * 0.75 + spark * 0.8, c.a) * COLOR;
}
"""

## Colourless, wet-looking, glistening: the shapeshifter's own face.
static func glisten_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = GLISTEN_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

func setup(p_run: Run, p_type: String, p_lair: String, start: Vector2) -> void:
	run = p_run
	map = run.map
	rng = run.rng
	type_id = p_type
	def = Defs.CREATURES[p_type]
	lair_room = p_lair
	position = start
	room_id = map.room_at(start)
	var size := 58.0 if p_type == "harbinger" else 44.0
	token = TokenSprite.new(def["token"] if p_type != "werewolf" else "tokens/werewolf_human.png", size)
	add_child(token)
	glow = PointLight2D.new()
	glow.texture = Art.tex("lights/soft.png")
	glow.texture_scale = 0.5 if p_type != "harbinger" else 0.9
	glow.color = _glow_color()
	glow.energy = 0.0
	add_child(glow)
	if p_type == "blightness":
		# Never a clean shape: a warping blot of the world behind it.
		_distort = WorldFx.distort_material(0.016, Color(0.78, 0.92, 0.55), 0.5)
		token.sprite.material = _distort
	elif p_type == "crawler":
		# A dark ripple in the floorboards rather than a figure.
		_distort = WorldFx.distort_material(0.022, Color(0.45, 0.4, 0.5), 0.55)
		token.sprite.material = _distort
	if p_type == "mimic":
		# A real occupant's face and name: that person now walks the house twice.
		tag = SpeechTag.new(run.world_text, run.disguise["name"])
		token.set_token(current_token())
	if p_type == "shapeshifter":
		tag = SpeechTag.new(run.world_text, run.disguise["name"])
		_set_form(["human", "cat", "ghost"][rng.randi_range(0, 2)], false)
	modulate.a = 0.0
	wait_t = rng.randf_range(1.0, 3.0)
	_settle_t = rng.randf_range(8.0, 18.0)   # it starts at home

func _glow_color() -> Color:
	match type_id:
		"vampire": return Color(0.9, 0.2, 0.2)
		"werewolf": return Color(1.0, 0.7, 0.3)
		"harbinger": return Color(0.7, 0.85, 1.0)
		"shapeshifter": return Color(0.75, 0.45, 1.0)
		"blightness": return Color(0.6, 0.85, 0.3)
		"crawler": return Color(0.35, 0.25, 0.45)
		"lost_one": return Color(0.85, 0.85, 1.0)
		"weeper": return Color(0.7, 0.78, 0.95)
		"mimic": return Color(0.85, 0.8, 0.95)
		"drowned_sailor": return Color(0.45, 0.7, 0.8)
		"plague_doctor": return Color(0.6, 0.75, 0.35)
	return Art.SPECTRAL

func current_token() -> String:
	if type_id == "werewolf" and (not wolf or reverted):
		return "tokens/werewolf_human.png"
	if type_id == "mimic":
		return def["token"] if is_hunting() or state == "banished" else run.disguise["token"]
	if type_id == "shapeshifter" and reverted:
		return "tokens/shapeshifter_human.png"
	if type_id == "shapeshifter":
		if exposed_t <= 0.0 and form == "human":
			return run.disguise["token"]
		return Defs.FORM_TOKENS["true" if exposed_t > 0.0 else form]
	return def["token"]

func is_hunting() -> bool:
	return state == "hunt" or state == "warn"

func is_ghost_like() -> bool:
	return def["kind"] == "ghost" or def["kind"] == "harbinger"

func is_visible_now() -> bool:
	return alpha > 0.25

func speed_for_hunt() -> float:
	var k := Defs.tune(run.difficulty, "hunt_speed")   # Beginner: slower hunts
	if wrath:
		return 360.0 * k   # the Lost One's fury: faster than anyone can run
	if angered_t > 0.0:
		k *= 1.2
	if type_id == "shapeshifter":
		return Defs.FORM_SPEED["true" if exposed_t > 0.0 else form] * k
	return def["hunt_speed"] * k

# --- State changes requested by Run --------------------------------------------

## Starts the warning phase of a hunt. `start_pos` may relocate the creature fairly.
func begin_hunt(start_pos: Vector2, reckless: bool) -> void:
	position = start_pos
	room_id = map.room_at(position)
	state = "warn"
	state_t = 0.0
	hunt_reckless = reckless
	hunt_hit = false
	hunt_count += 1
	path = PackedVector2Array()
	last_seen = Vector2.INF
	chase_speed = speed_for_hunt() * 0.9
	target_alpha = 0.55
	if type_id == "shapeshifter" and exposed_t <= 0.0:
		_set_form(["ghost", "vampire", "werewolf", "human"][rng.randi_range(0, 3)], true)
	hunt_started.emit(self)

func end_hunt() -> void:
	if not is_hunting():
		return
	state = "roam"
	state_t = 0.0
	target_alpha = 0.0
	cooldown_t = def["hunt_cooldown"] * Defs.tune(run.difficulty, "hunt_cooldown") * (0.5 if angered_t > 0.0 else 1.0)
	if wrath:
		wrath = false
		wrath_target = null
	path = PackedVector2Array()
	wait_t = rng.randf_range(2.0, 4.0)
	hunt_ended.emit(self, hunt_hit)

func stun(duration: float) -> void:
	var was_hunting := is_hunting()
	if type_id == "harbinger":
		stunned_t = duration
		return
	if was_hunting:
		hunt_hit = false
		end_hunt()
	state = "stunned"
	stunned_t = duration
	target_alpha = 0.0

func expose(duration: float) -> void:
	if exposed_t <= 0.0:
		transformations += 1
		run.on_transform(self, "true")
	exposed_t = duration
	target_alpha = 1.0
	token.set_token(current_token())

func bind_at(pos: Vector2) -> void:
	if is_hunting():
		end_hunt()
	state = "bound"
	position = pos
	target_alpha = 1.0

func banish() -> void:
	state = "banished"
	target_alpha = 0.0
	alpha = maxf(alpha, 1.0)
	modulate.a = 1.0
	match type_id:
		"vampire":
			# Crumbles to dust: greys, cracks, and blows away.
			run.creature_fx("dust", position)
			var tw := create_tween()
			tw.tween_property(token.sprite, "modulate", Color(0.55, 0.52, 0.5), 0.35)
			tw.tween_property(token, "scale", Vector2(1.15, 0.9), 0.25)
			tw.parallel().tween_property(self, "modulate:a", 0.0, 1.2).set_delay(0.2)
			return
		"werewolf", "shapeshifter":
			# The beast / the borrowed faces fall away: a human body is left behind.
			reverted = true
			if type_id == "shapeshifter":
				token.sprite.material = glisten_material()
			token.set_token(current_token())
			token.sprite.modulate = Color(3.0, 3.0, 3.0)
			run.creature_fx("revert", position)
			var tw := create_tween()
			tw.tween_property(token.sprite, "modulate", Color.WHITE, 0.6)
			tw.tween_interval(1.4)
			tw.tween_property(self, "modulate:a", 0.0, 0.8)
			return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(token, "scale", Vector2(2.2, 2.2), 1.6)
	tw.tween_property(self, "modulate:a", 0.0, 1.6)
	tw.tween_property(glow, "energy", 3.0, 0.4)

## The full moon: the human form tears into the wolf, visibly and for good.
func transform_to_wolf() -> void:
	if wolf or type_id != "werewolf":
		return
	_show_t = 3.2
	run.sound_at("werewolf_howl", position, 4.0)
	run.creature_fx("transform", position)
	var tw := create_tween()
	for i in 8:
		tw.tween_property(token, "rotation", 0.12 if i % 2 == 0 else -0.12, 0.08)
		tw.parallel().tween_property(token, "scale", Vector2.ONE * (1.0 + i * 0.04), 0.08)
	tw.tween_callback(func():
		wolf = true
		token.set_token(current_token())
		token.sprite.modulate = Color(2.5, 2.2, 2.0)
		run.sound_at("werewolf_growl", position, 2.0))
	tw.tween_property(token.sprite, "modulate", Color.WHITE, 0.5)
	tw.parallel().tween_property(token, "scale", Vector2(1.3, 1.3), 0.25)
	tw.tween_property(token, "scale", Vector2.ONE, 0.4)
	tw.parallel().tween_property(token, "rotation", 0.0, 0.2)

func _set_form(f: String, announce: bool) -> void:
	if f == form:
		return
	var had := form != ""
	form = f
	token.set_token(current_token())
	if had:
		transformations += 1
		if announce:
			run.sound_at("shapeshift", position, -2.0)
		run.on_transform(self, f)

# --- Simulation -------------------------------------------------------------------

func _process(delta: float) -> void:
	if state == "banished":
		if token.sprite.material and type_id == "shapeshifter":
			state_t += delta
			token.sprite.material.set_shader_parameter("t", state_t)
		return
	_show_t = maxf(0.0, _show_t - delta)
	state_t += delta
	cooldown_t = maxf(0.0, cooldown_t - delta)
	exposed_t = maxf(0.0, exposed_t - delta)
	weakened_t = maxf(0.0, weakened_t - delta)
	slowed_t = maxf(0.0, slowed_t - delta)
	angered_t = maxf(0.0, angered_t - delta)
	if _distort:
		_distort.set_shader_parameter("t", state_t + float(hunt_count) * 3.0)
	if (type_id == "mimic" or (exposed_t <= 0.0 and type_id == "shapeshifter")) and token.token_path != current_token():
		token.set_token(current_token())   # (the Mimic drops its borrowed face while it hunts)
	_weeper_tick(delta)
	_glitch_left = maxf(0.0, _glitch_left - delta)
	room_id = map.room_at(position, room_id)
	match state:
		"roam": _roam(delta)
		"warn": _warn(delta)
		"hunt": _hunt(delta)
		"stunned":
			stunned_t -= delta
			if stunned_t <= 0.0:
				state = "roam"
				cooldown_t = maxf(cooldown_t, 6.0)
		"bound":
			token.face(token.facing + delta * 0.8, delta)
	if type_id == "harbinger" and stunned_t > 0.0 and state != "stunned":
		stunned_t -= delta
	if type_id == "shapeshifter" and state == "roam" and exposed_t <= 0.0:
		form_t -= delta
		if form_t <= 0.0:
			form_t = rng.randf_range(14.0, 26.0)
			var r := rng.randf()
			_set_form("cat" if r < 0.25 else ("human" if r < 0.5 else ["ghost", "vampire", "werewolf"][rng.randi_range(0, 2)]), false)
	_update_visibility(delta)
	_update_disguise(delta)
	run.phenomena.creature_tick(self, delta)

func _update_visibility(delta: float) -> void:
	var want := target_alpha
	if state == "roam":
		want = 0.0
		if type_id == "shapeshifter" and exposed_t <= 0.0 and (form == "cat" or form == "human"):
			want = 1.0
		elif type_id == "mimic":
			want = 1.0   # in plain sight, as one of the residents
		elif exposed_t > 0.0:
			want = 1.0
		elif _glimpsed():
			want = 0.5
		manifest_t -= delta
		if is_ghost_like() and type_id != "mimic" and manifest_t < 0.0:
			if manifest_t < -1.4:
				manifest_t = rng.randf_range(18.0, 34.0)
			else:
				want = 0.55
	elif state == "hunt":
		want = 1.0
		if is_ghost_like():
			# Ghosts blink in and out while hunting: readable but unsettling.
			want = 0.9 if fmod(state_t, 0.9) < 0.62 else 0.25
	if wrath or _show_t > 0.0:
		want = 1.0   # the Lost One's fury; a transformation in full view
	# A roaming flesh-and-blood creature caught in the beam shows only as a shadow.
	var silhouette := state == "roam" and want == 0.5 and _glimpsed()
	token.sprite.modulate = Color(0.12, 0.11, 0.13) if silhouette else Color.WHITE
	if type_id == "crawler":
		# A flat dark ripple along the floorboards, never a figure — until it rises.
		var rising := has_meta("rising")
		token.sprite.modulate = Color.WHITE if rising else Color(0.25, 0.2, 0.3)
		var wob := 1.0 + sin(state_t * 7.0) * 0.08
		token.scale = Vector2(1.25 * wob, 1.25) if rising else Vector2(1.35 * wob, 0.5)
		if state == "hunt" and not rising:
			want = 0.6
	if angered_t > 0.0 and state == "roam" and fmod(angered_t, 6.0) > 4.8:
		want = maxf(want, 0.8)   # an enraged creature shows itself now and then
	alpha = move_toward(alpha, want, delta * 2.5)
	modulate.a = alpha
	glow.energy = 0.0 if silhouette or disguised() else alpha * (1.2 if state == "hunt" or state == "bound" else 0.6)

func disguised() -> bool:
	if type_id == "mimic":
		return not is_hunting() and state != "banished" and state != "stunned"
	return type_id == "shapeshifter" and form == "human" and exposed_t <= 0.0 and state != "banished"

## As a person it looks, is labelled and talks exactly like an occupant.
func _update_disguise(delta: float) -> void:
	if tag == null:
		return
	var shown := disguised() and alpha > 0.3
	tag.set_visible(shown)
	if not shown:
		return
	tag.update(position, alpha, delta)
	_talk_t -= delta
	if _talk_t <= 0.0 and state == "roam":
		# Talks exactly like an occupant would — terrified, too, in Nightmare.
		var fear := Defs.tune(run.difficulty, "panic")
		_talk_t = Occupants.talk_delay(run.disguise["personality"], rng, fear)
		var line := Occupants.pick_line(run.disguise["personality"], "lines", rng, fear)
		if type_id == "mimic" and rng.randf() < 0.35:
			line = _garble(line)
			run.sound_at("whisper_mimic", position, -12.0, 0.7, 700.0)
		tag.say(line)
		run.on_say(run._creature_actor_id(), line)

## The Mimic's borrowed voice slips: stretched, doubled, wrong.
func _garble(line: String) -> String:
	var out := ""
	for ch in line:
		var r := rng.randf()
		if r < 0.1 and ch != " ":
			out += ch + ch + ch
		elif r < 0.2:
			out += ch.to_upper()
		elif r < 0.23:
			out += "—"
		else:
			out += ch
	return out

func _glimpsed() -> bool:
	var physical: bool = def["kind"] == "physical" and not (type_id == "shapeshifter" and form == "ghost")
	if not physical:
		return false
	for p: Player in run.hunters:
		if p.dead or not p.flashlight_on:
			continue
		var to := position - p.global_position
		if to.length() < 230.0 and absf(angle_difference(p.aim_angle, to.angle())) < 0.42 and map.los(p.global_position, position):
			return true
	return false

func _move_along(delta: float, speed: float) -> bool:
	if path_i >= path.size():
		return false
	if type_id == "blightness":
		return _blight_move(delta)
	var target_pt := path[path_i]
	var to := target_pt - position
	if to.length() > 90.0:
		# Consecutive path points are at most one cell apart; a larger gap is a
		# staircase link between floors: take it instantly.
		position = target_pt
		path_i += 1
		return path_i < path.size()
	var step := speed * delta
	if to.length() <= step:
		position = target_pt
		path_i += 1
	else:
		position += to.normalized() * step
		token.face(to.angle(), delta, 10.0)
	return path_i < path.size()

## The Blightness never steers: it launches along a straight, clear line toward
## the furthest point of its path it can reach, slams to a stop, shudders for half
## a second, then picks the next line. Same pattern roaming and hunting.
func _blight_move(delta: float) -> bool:
	var mode := "hunt" if is_hunting() else "roam"
	if _rush_left > 0.0:
		var step := minf(float(BLIGHT_RUSH_SPEED[mode]) * delta, _rush_left)
		var nxt := position + _rush_dir * step
		if map.walkable(HouseMap.to_cell(nxt)):
			position = nxt
			_rush_left -= step
		else:
			_rush_left = 0.0   # hit a wall or furniture: stop dead
		token.face(_rush_dir.angle(), delta, 30.0)
		token.scale = Vector2(1.4, 0.75)   # smeared out by its own speed
		if _rush_left <= 0.0:
			if _rush_target_i >= 0:
				path_i = maxi(path_i, _rush_target_i + 1)
			_recover_t = rng.randf_range(0.42, 0.58)
		return true
	if _recover_t > 0.0:
		# Shaking itself back together.
		_recover_t -= delta
		var k := clampf(_recover_t / 0.5, 0.0, 1.0)
		token.scale = Vector2.ONE * (1.0 + 0.08 * k)
		token.position = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 3.5 * k
		token.rotation = rng.randf_range(-0.25, 0.25) * k
		if _distort:
			_distort.set_shader_parameter("strength", 0.016 + 0.03 * k)
		return path_i < path.size() or _recover_t > 0.0
	token.position = Vector2.ZERO
	token.rotation = 0.0
	token.scale = Vector2.ONE
	if path_i >= path.size():
		return false
	if position.distance_to(path[path_i]) > 90.0:
		position = path[path_i]   # staircase link between floors
		path_i += 1
		_recover_t = 0.3
		return true
	# The furthest point ahead it can reach in one straight, unobstructed rush.
	var best := -1
	var reach: float = BLIGHT_RUSH_REACH[mode]
	for k in range(path_i, mini(path_i + 10, path.size())):
		if k > path_i and path[k].distance_to(path[k - 1]) > 90.0:
			break
		if position.distance_to(path[k]) > reach or not _clear_line(position, path[k]):
			break
		best = k
	if best < 0:
		best = path_i
	var tgt := path[best]
	if position.distance_to(tgt) < 4.0:
		path_i = best + 1
		return path_i < path.size()
	_rush_dir = (tgt - position).normalized()
	_rush_left = position.distance_to(tgt)
	_rush_target_i = best
	_rushes += 1
	if _distort:
		_distort.set_shader_parameter("strength", 0.016)
	if is_hunting() or _rushes % 2 == 0:
		run.sound_at("blight_ping", position, -6.0 if is_hunting() else -14.0, rng.randf_range(0.95, 1.05), 900.0)
		run.creature_fx("ping", position)
	return true

func _clear_line(a: Vector2, b: Vector2) -> bool:
	var n := int(ceil(a.distance_to(b) / 8.0))
	for i in range(1, n + 1):
		if not map.walkable(HouseMap.to_cell(a.lerp(b, float(i) / n))):
			return false
	return true

func _set_path_to(p: Vector2) -> void:
	path = map.path(position, p)
	path_i = 0
	_rush_target_i = -1   # (a rush already under way keeps its line; it just won't skip ahead)

## Waterlogged surges (the Drowned Sailor: heavy, then a sudden lunge) and the
## Plague Doctor's measured tread. 1.0 for everything else.
func hunt_gait() -> float:
	match type_id:
		"drowned_sailor":
			return 1.35 if fmod(state_t, 2.6) > 1.8 else 0.72
		"plague_doctor":
			return 0.75 + 0.3 * absf(sin(state_t * 2.2))
		"weeper":
			if _crying_t > 0.0:
				return 0.0   # it stops to sob, even mid-hunt
			if target and is_instance_valid(target) and position.distance_to(target.global_position) < 230.0:
				return 2.2   # close in, it lunges faster than a sprint
	return 1.0

## The Weeper: soft sobbing that carries through walls, and every so often it
## stops dead to cry — roaming or hunting.
func _weeper_tick(delta: float) -> void:
	if type_id != "weeper" or state in ["stunned", "bound"]:
		return
	if _crying_t > 0.0:
		_crying_t -= delta
		token.position = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 1.6
		if _crying_t <= 0.0:
			token.position = Vector2.ZERO
		return
	_sob_t -= delta
	if _sob_t <= 0.0:
		_sob_t = rng.randf_range(5.0, 8.0)
		run.sound_at("weeper_sob", position, -14.0, rng.randf_range(0.95, 1.08), 1150.0)
	_cry_t -= delta
	if _cry_t <= 0.0:
		_cry_t = rng.randf_range(7.0, 11.0) if is_hunting() else rng.randf_range(9.0, 15.0)
		_crying_t = rng.randf_range(1.8, 2.8)
		run.sound_at("weeper_sob", position, -3.0 if is_hunting() else -7.0, rng.randf_range(0.92, 1.0), 1250.0)

func _hunter_near(dist: float) -> bool:
	for h: Player in run.living_hunters():
		if position.distance_to(h.global_position) < dist and map.los(position, h.global_position):
			return true
	return false

func _roam(delta: float) -> void:
	_sway(delta)
	if _crying_t > 0.0:
		return
	if type_id == "mimic":
		_glitch_t -= delta
		if _glitch_t <= 0.0:
			_glitch_t = rng.randf_range(9.0, 16.0)
			_glitch_left = 0.5   # a jerk, a glide — not how people move
			run.sound_at("whisper_mimic", position, -14.0, 0.55, 650.0)
	if room_id == lair_room:
		_settle_t = maxf(0.0, _settle_t - delta)
	if wait_t > 0.0:
		wait_t -= delta
		if wait_t <= 0.0:
			_set_path_to(_pick_roam_target())
		return
	var spd: float = def["roam_speed"]
	if type_id == "shapeshifter" and form == "cat":
		spd = 80.0
	if type_id == "weeper" and _hunter_near(150.0):
		spd *= 3.2   # approached, it darts away faster than you can follow
	if _glitch_left > 0.0:
		spd *= 3.0
		token.rotation = rng.randf_range(-0.6, 0.6)
	elif type_id == "mimic":
		token.rotation = 0.0
	if type_id == "plague_doctor":
		spd *= 0.55 + 0.45 * absf(sin(state_t * 1.8))   # slow, deliberate steps
		if rng.randf() < delta * 0.12:
			wait_t = rng.randf_range(1.5, 3.0)            # stops, as if examining the room
			return
	if not _move_along(delta, spd):
		if type_id == "harbinger":
			wait_t = rng.randf_range(0.5, 1.5)
		elif type_id == "plague_doctor":
			wait_t = rng.randf_range(3.0, 7.0)
		else:
			wait_t = rng.randf_range(1.5, 5.0)

## The sailor rolls like a deck in a swell; the doctor bows its beak as it walks.
func _sway(_delta: float) -> void:
	match type_id:
		"drowned_sailor":
			token.rotation = sin(state_t * 1.7) * 0.14
			token.position.y = absf(sin(state_t * 1.7)) * -2.0
		"plague_doctor":
			token.rotation = sin(state_t * 0.9) * 0.05

func _pick_roam_target() -> Vector2:
	var player: Node2D = run.nearest_hunter(position)
	if type_id == "vampire" and rng.randf() < 0.45 and player:
		# Stalking: drift to a room near the investigator, without approaching too closely.
		var near := map.nearest_walkable(HouseMap.to_cell(player.global_position + Vector2.from_angle(rng.randf() * TAU) * 220.0))
		return HouseMap.cell_center(near)
	if type_id == "shapeshifter" and rng.randf() < 0.3 and not map.furniture_with("mirror").is_empty():
		var mirrors := map.furniture_with("mirror")
		var m: Dictionary = mirrors[rng.randi_range(0, mirrors.size() - 1)]
		return HouseMap.cell_center(map.nearest_walkable(HouseMap.to_cell(m["rect"].get_center())))
	if type_id == "harbinger":
		var rooms := map.indoor_rooms()
		return HouseMap.cell_center(map.random_free_cell(rooms[rng.randi_range(0, rooms.size() - 1)]["id"], rng))
	return HouseMap.cell_center(map.random_free_cell(_next_home_room(), rng))

## Where an ordinary wander goes next: an excursion room, back home, or a new
## spot within the home room. Stronger homebodies (lair_bias) settle longer.
func _next_home_room() -> String:
	if not _excursion.is_empty():
		return _excursion.pop_front()
	if room_id != lair_room:
		_settle_t = rng.randf_range(14.0, 26.0) * (0.6 + float(def["lair_bias"]))
		return lair_room
	if _settle_t > 0.0:
		return lair_room
	var near: Array = map.neighbour_rooms(lair_room).filter(func(r): return not map.room(r).get("outdoor", false))
	if near.is_empty():
		near = map.neighbour_rooms(lair_room)
	if near.is_empty():
		return lair_room
	var first: String = near[rng.randi_range(0, near.size() - 1)]
	_excursion = [first]
	if rng.randf() < 0.4:
		var further: Array = map.neighbour_rooms(first).filter(func(r): return r != lair_room and not map.room(r).get("outdoor", false))
		if not further.is_empty():
			_excursion.append(further[rng.randi_range(0, further.size() - 1)])
	return _excursion.pop_front()

## A new home room (Run decides when). It walks there and settles in.
func relocate_home(new_lair: String) -> void:
	lair_room = new_lair
	_excursion = [new_lair]
	_settle_t = 0.0
	wait_t = minf(wait_t, 0.5)

func _warn(delta: float) -> void:
	alpha = move_toward(alpha, 0.55, delta)
	if state_t >= WARN_TIME:
		state = "hunt"
		state_t = 0.0

func _player_visible(player: Node2D) -> bool:
	var d := position.distance_to(player.global_position)
	var reach := 470.0
	if player.flashlight_on:
		reach = 560.0
	if player.sprinting:
		reach += 60.0
	return d < reach and map.los(position, player.global_position)

func _hunt(delta: float) -> void:
	_sway(delta)
	if state_t >= float(def["hunt_duration"]) * Defs.tune(run.difficulty, "hunt_length") or run.hunters_in_house().is_empty():
		end_hunt()
		return
	# Chase the hunter it can see (sticking with its current quarry while visible).
	if target == null or target.dead or not _player_visible(target):
		var best: Player = null
		var bd := INF
		for h: Player in run.living_hunters():
			var d := position.distance_to(h.global_position)
			if d < bd and _player_visible(h):
				bd = d
				best = h
		if best:
			target = best
	var player: Player = target if target and not target.dead else run.nearest_hunter(position)
	var sees := _player_visible(player)
	if wrath and wrath_target and not wrath_target.dead:
		player = wrath_target   # it knows exactly who took it
		target = wrath_target
		sees = true
	var base := speed_for_hunt()
	if sees:
		last_seen = player.global_position
		if type_id == "werewolf" and wolf:
			chase_speed = minf(chase_speed + 28.0 * delta, 288.0 * Defs.tune(run.difficulty, "hunt_speed"))
		else:
			chase_speed = move_toward(chase_speed, base, 60.0 * delta)
	else:
		chase_speed = move_toward(chase_speed, base * 0.85, 40.0 * delta)
	var spd := chase_speed * hunt_gait()
	if slowed_t > 0.0:
		spd *= 0.5
	if weakened_t > 0.0:
		spd *= 0.45
	if type_id == "harbinger" and stunned_t > 0.0:
		spd = 0.0
	repath_t -= delta
	if repath_t <= 0.0:
		repath_t = 0.25
		if sees:
			_set_path_to(player.global_position)
		elif last_seen != Vector2.INF:
			_set_path_to(last_seen)
			last_seen = Vector2.INF
		elif path_i >= path.size():
			var rooms := map.indoor_rooms()
			_set_path_to(HouseMap.cell_center(map.random_free_cell(rooms[rng.randi_range(0, rooms.size() - 1)]["id"], rng)))
	if sees and position.distance_to(player.global_position) < 70.0 and type_id != "blightness":
		# Close the final gap directly (paths are cell-centred).
		var to: Vector2 = player.global_position - position
		position += to.normalized() * minf(spd * delta, to.length())
		token.face(to.angle(), delta, 12.0)
	else:
		_move_along(delta, spd)
	if stunned_t <= 0.0:
		for h: Player in run.living_hunters():
			if position.distance_to(h.global_position) < CONTACT_RADIUS:
				run.on_creature_contact(self, h)
				break
