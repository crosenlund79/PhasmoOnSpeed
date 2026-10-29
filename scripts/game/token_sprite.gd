class_name TokenSprite
extends Node2D
## Illustrated top-down token (player, occupants, creatures) with a soft drop
## shadow. Art faces +X; `facing` is the world angle the figure looks toward.

var sprite: Sprite2D
var shadow: Sprite2D
var token_path := ""
var facing := 0.0
var diameter := 30.0

func _init(path: String = "", size: float = 30.0) -> void:
	diameter = size
	shadow = Sprite2D.new()
	shadow.modulate = Color(0, 0, 0, 0.5)
	shadow.position = Vector2(3, 4)
	add_child(shadow)
	sprite = Sprite2D.new()
	add_child(sprite)
	if path != "":
		set_token(path)

func set_token(path: String) -> void:
	if path == token_path:
		return
	token_path = path
	var t := Art.tex(path)
	sprite.texture = t
	shadow.texture = t
	var s := diameter / maxf(1.0, t.get_size().x)
	sprite.scale = Vector2(s, s)
	shadow.scale = Vector2(s, s) * 1.04

func set_diameter(d: float) -> void:
	diameter = d
	var p := token_path
	token_path = ""
	set_token(p)

func face(angle: float, delta: float, rate: float = 14.0) -> void:
	facing = lerp_angle(facing, angle, clampf(rate * delta, 0.0, 1.0))
	sprite.rotation = facing
	shadow.rotation = facing

func face_now(angle: float) -> void:
	facing = angle
	sprite.rotation = angle
	shadow.rotation = angle
