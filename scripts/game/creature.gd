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
var wrath_target: Player = null
var _hop_acc := 0.0         # Blightness lurches
var _hops := 0
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
	if p_type == "shapeshifter":
		tag = SpeechTag.new(run.world_text, run.disguise["name"])
		_set_form(["human", "cat", "ghost"][rng.randi_range(0, 2)], false)
	modulate.a = 0.0
	wait_t = rng.randf_range(1.0, 3.0)

func _glow_color() -> Color:
	match type_id:
		"vampire": return Color(0.9, 0.2, 0.2)
		"werewolf": return Color(1.0, 0.7, 0.3)
		"harbinger": return Color(0.7, 0.85, 1.0)
		"shapeshifter": return Color(0.75, 0.45, 1.0)
		"blightness": return Color(0.6, 0.85, 0.3)
		"crawler": return Color(0.35, 0.25, 0.45)
		"lost_one": return Color(0.85, 0.85, 1.0)
	return Art.SPECTRAL

func current_token() -> String:
	if type_id == "werewolf" and (not wolf or reverted):
		return "tokens/werewolf_human.png"
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
	var k := 0.85 if run.difficulty == "beginner" else 1.0   # Beginner: slower hunts
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
	cooldown_t = def["hunt_cooldown"] * (1.5 if run.difficulty == "beginner" else 1.0) * (0.5 if angered_t > 0.0 else 1.0)
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
	if exposed_t <= 0.0 and type_id == "shapeshifter" and token.token_path != current_token():
		token.set_token(current_token())
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
		elif exposed_t > 0.0:
			want = 1.0
		elif _glimpsed():
			want = 0.5
		manifest_t -= delta
		if is_ghost_like() and manifest_t < 0.0:
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
	glow.energy = 0.0 if silhouette else alpha * (1.2 if state == "hunt" or state == "bound" else 0.6)

func disguised() -> bool:
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
		var fear := 2.0 if run.difficulty == "nightmare" else 1.0
		_talk_t = Occupants.talk_delay(run.disguise["personality"], rng, fear)
		var line := Occupants.pick_line(run.disguise["personality"], "lines", rng, fear)
		tag.say(line)
		run.on_say(run._creature_actor_id(), line)

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
		# It does not glide: it lurches, and every lurch pings.
		_hop_acc += delta
		var interval := 0.3 if is_hunting() else 0.55
		if _hop_acc < interval:
			return true
		delta = _hop_acc
		_hop_acc = 0.0
		_hops += 1
		if is_hunting() or _hops % 2 == 0:
			run.sound_at("blight_ping", position, -6.0 if is_hunting() else -14.0, rng.randf_range(0.95, 1.05), 900.0)
			run.creature_fx("ping", position)
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

func _set_path_to(p: Vector2) -> void:
	path = map.path(position, p)
	path_i = 0

func _roam(delta: float) -> void:
	if wait_t > 0.0:
		wait_t -= delta
		if wait_t <= 0.0:
			_set_path_to(_pick_roam_target())
		return
	var spd: float = def["roam_speed"]
	if type_id == "shapeshifter" and form == "cat":
		spd = 80.0
	if not _move_along(delta, spd):
		wait_t = rng.randf_range(1.5, 5.0) if type_id != "harbinger" else rng.randf_range(0.5, 1.5)

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
	var rid := lair_room
	if rng.randf() > float(def["lair_bias"]):
		var rooms := map.indoor_rooms()
		rid = rooms[rng.randi_range(0, rooms.size() - 1)]["id"]
	return HouseMap.cell_center(map.random_free_cell(rid, rng))

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
	if state_t >= float(def["hunt_duration"]) * (0.7 if run.difficulty == "beginner" else 1.0) or run.living_hunters().is_empty():
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
			chase_speed = minf(chase_speed + 28.0 * delta, 288.0 * (0.85 if run.difficulty == "beginner" else 1.0))
		else:
			chase_speed = move_toward(chase_speed, base, 60.0 * delta)
	else:
		chase_speed = move_toward(chase_speed, base * 0.85, 40.0 * delta)
	var spd := chase_speed
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
