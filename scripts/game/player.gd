class_name Player
extends CharacterBody2D
## A hunter (investigator). Movement, aim, lights, wounds, inventory and the
## per-hunter investigation record (journal, suspect, attempts). Equipment
## behaviour lives in EquipmentController.
##
## Modes:
##  * local  — driven by this machine's keyboard/mouse (solo, the host, a client's own hunter)
##  * remote — on the host, a client's hunter: position/aim arrive from the network
##  * puppet — on a client, another hunter: purely visual, fed by snapshots

const WALK_SPEED := 235.0
const SPRINT_SPEED := 335.0
const STAMINA_DRAIN := 1.0 / 3.6
const STAMINA_REGEN := 1.0 / 2.4
const RADIUS := 10.0
const INVULN_AFTER_HIT := 3.0

const COLORS := [Color(0.95, 0.82, 0.5), Color(0.55, 0.8, 1.0), Color(0.85, 0.55, 0.95), Color(0.6, 0.95, 0.6)]
const SHOVE_COOLDOWN := 5.0
const SHOVE_RANGE := 48.0
const SHOVE_IMMUNITY := 1.6

var actor_id := "player_1"
var peer_id := 1
var index := 0
var display_name := "Investigator"
var is_local := true
var remote := false
var puppet := false
var run   # Run on the host / solo, ClientRun on clients
var input := PlayerInput.new()
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

# Personal investigation record (each hunter has a private journal).
var journal := Journal.new()
var suspect := ""
var investigation := 0
var wrong_attempts := 0
var reckless_attempts := 0
var incomplete_attempts := 0
var attempts: Array = []
var clean_hunts := 0
var first_finds := 0
var equipment   # EquipmentController (host / solo) or EquipmentMirror (client)

# Competitive play.
var shove_cd := 0.0
var shove_immune := 0.0
var knock_vel := Vector2.ZERO
var stunned := 0.0
var shoves_given := 0
var shoves_taken := 0
var name_label: Label

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

func color() -> Color:
	return COLORS[index % COLORS.size()]

func alive() -> bool:
	return not dead

## Puppets (client view of rivals) never collide or read input.
func make_puppet() -> void:
	puppet = true
	is_local = false
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)

## Name tag under rival hunters (multiplayer only), on the unlit text layer.
func attach_name_label(layer: CanvasLayer) -> void:
	name_label = Label.new()
	name_label.text = display_name
	name_label.add_theme_font_override("font", Art.font_heading)
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", color())
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 5)
	name_label.size = Vector2(160, 18)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(name_label)

func _process(_delta: float) -> void:
	if name_label:
		name_label.position = global_position + Vector2(-80, -40)
		name_label.modulate.a = 0.35 if dead else 1.0
		name_label.text = display_name + ("  †" if dead else "")

## Applies a shove impulse (local hunters only; remote ones get it via the network).
func knockback(impulse: Vector2) -> void:
	knock_vel = impulse
	stunned = 0.35

func _cone_light(color: Color, energy: float, scale: float) -> PointLight2D:
	var l := Lighting.make_cone(color, energy, scale)
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
	invuln = maxf(0.0, invuln - delta)
	blessed = maxf(0.0, blessed - delta)
	shove_cd = maxf(0.0, shove_cd - delta)
	shove_immune = maxf(0.0, shove_immune - delta)
	stunned = maxf(0.0, stunned - delta)
	light_pivot.rotation = aim_angle
	flashlight.visible = flashlight_on and not dead
	if dead or remote:
		velocity = Vector2.ZERO
		token.face(aim_angle, delta, 18.0)
		return
	var dir := Vector2.ZERO
	if input_enabled and stunned <= 0.0:
		dir = input.move
	if input_enabled and is_local:
		var mouse := get_global_mouse_position()
		if mouse.distance_to(global_position) > 4.0:
			aim_angle = (mouse - global_position).angle()
	moving = dir.length() > 0.1
	sprinting = moving and input.sprint and stamina > 0.02 and input_enabled
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
	velocity = dir.normalized() * speed + knock_vel
	knock_vel = knock_vel.move_toward(Vector2.ZERO, 1500.0 * delta)
	move_and_slide()
	token.face(aim_angle, delta, 18.0)
	if moving:
		_step_t -= delta * (1.5 if sprinting else 1.0)
		if _step_t <= 0.0:
			_step_t = 0.32
			Sfx.play("footstep", -8.0, randf_range(0.85, 1.1), 0.1)
	token.modulate.a = 0.45 + 0.55 * absf(sin(invuln * 12.0)) if invuln > 0.0 else 1.0
