class_name Player
extends CharacterBody2D
## The investigator. Movement, aim, lights, wounds and inventory. Equipment
## behaviour lives in EquipmentController. One Player per participant; the actor
## id keeps replay and (future) cooperative play unambiguous.

const WALK_SPEED := 235.0
const SPRINT_SPEED := 335.0
const STAMINA_DRAIN := 1.0 / 3.6
const STAMINA_REGEN := 1.0 / 2.4
const RADIUS := 10.0
const INVULN_AFTER_HIT := 3.0

var actor_id := "player_1"
var run: Run
var token: TokenSprite
var aim_angle := 0.0
var stamina := 1.0
var _regen_delay := 0.0
var wounds := 0
var invuln := 0.0
var blessed := 0.0
var dead := false
var input_enabled := true
var flashlight_on := true
var room_id := ""
var moving := false
var sprinting := false
var _step_t := 0.0

# Inventory: base equipment charges and found resources.
var charges := {"salt": 3, "crucifix": 1, "holy_water": 3}
var resources := {}   # id -> count
var book_placed := false
var crucifix_burns := 2

var light_pivot: Node2D
var flashlight: PointLight2D
var uv_light: PointLight2D
var ambient: PointLight2D

func _init() -> void:
	collision_layer = 4
	collision_mask = 3
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	cs.shape = circle
	add_child(cs)
	token = TokenSprite.new("tokens/investigator.png", 40.0)
	add_child(token)
	light_pivot = Node2D.new()
	add_child(light_pivot)
	flashlight = _cone_light(Color(1.0, 0.92, 0.75), 1.25, 0.62)
	uv_light = _cone_light(Color(0.55, 0.3, 1.0), 1.0, 0.42)
	uv_light.visible = false
	uv_light.range_item_cull_mask = 1 | 2   # layer 2 = UV handprints (light-only material)
	ambient = PointLight2D.new()
	ambient.texture = Art.tex("lights/soft.png")
	ambient.texture_scale = 0.42
	ambient.energy = 0.55
	ambient.color = Color(0.85, 0.8, 0.75)
	add_child(ambient)

func _cone_light(color: Color, energy: float, scale: float) -> PointLight2D:
	var l := PointLight2D.new()
	var tex := Art.tex("lights/cone.png")
	l.texture = tex
	l.texture_scale = scale
	l.energy = energy
	l.color = color
	l.shadow_enabled = true
	l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	l.shadow_color = Color(0, 0, 0, 0.85)
	l.position = Vector2(tex.get_size().x * 0.5 * scale, 0)
	light_pivot.add_child(l)
	return l

func has_resource(id: String) -> bool:
	return int(resources.get(id, 0)) > 0

func add_resource(id: String, n: int = 1) -> void:
	resources[id] = int(resources.get(id, 0)) + n

func take_resource(id: String, n: int = 1) -> void:
	resources[id] = maxi(0, int(resources.get(id, 0)) - n)
	if resources[id] == 0:
		resources.erase(id)

func facing_vector() -> Vector2:
	return Vector2.RIGHT.rotated(aim_angle)

func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
		return
	invuln = maxf(0.0, invuln - delta)
	blessed = maxf(0.0, blessed - delta)
	var dir := Vector2.ZERO
	if input_enabled:
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var mouse := get_global_mouse_position()
		if mouse.distance_to(global_position) > 4.0:
			aim_angle = (mouse - global_position).angle()
	moving = dir.length() > 0.1
	sprinting = moving and Input.is_action_pressed("sprint") and stamina > 0.02 and input_enabled
	if sprinting:
		stamina = maxf(0.0, stamina - STAMINA_DRAIN * delta)
		_regen_delay = 0.6
	else:
		_regen_delay -= delta
		if _regen_delay <= 0.0:
			stamina = minf(1.0, stamina + STAMINA_REGEN * delta)
	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	if invuln > 0.0 and wounds > 0:
		speed *= 1.12   # adrenaline after being wounded
	velocity = dir.normalized() * speed
	move_and_slide()
	token.face(aim_angle, delta, 18.0)
	light_pivot.rotation = aim_angle
	flashlight.visible = flashlight_on
	if moving:
		_step_t -= delta * (1.5 if sprinting else 1.0)
		if _step_t <= 0.0:
			_step_t = 0.32
			Sfx.play("footstep", -8.0, randf_range(0.85, 1.1), 0.1)
	token.modulate.a = 0.45 + 0.55 * absf(sin(invuln * 12.0)) if invuln > 0.0 else 1.0
