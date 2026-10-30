class_name WorldFx
extends RefCounted
## Applies recorded / networked world events to a HouseView: decals, UV prints,
## orbs, mirror reflections, furniture rattles, flicker and darkness. Shared by
## the multiplayer client view and the replay player so both show the world the
## same way the host saw it. Never touches gameplay state.

var view: HouseView
var text_layer: CanvasLayer
var decals := {}
var orbs: Array = []
var _uv_material: CanvasItemMaterial
var _t := 0.0

func _init(p_view: HouseView, p_text_layer: CanvasLayer) -> void:
	view = p_view
	text_layer = p_text_layer
	_uv_material = CanvasItemMaterial.new()
	_uv_material.light_mode = CanvasItemMaterial.LIGHT_MODE_LIGHT_ONLY

## Screen-space warp used by the Blightness and by disturbed rooms.
const DISTORT_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float t = 0.0;
uniform float strength = 0.012;
uniform vec4 tint : source_color = vec4(0.8, 0.95, 0.6, 1.0);
uniform float own = 0.45;
uniform float round_mask = 1.0;
void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c);
	float edge = mix(1.0, smoothstep(0.5, 0.18, r), round_mask);
	float ripple = sin(r * 38.0 - t * 9.0) * strength * edge;
	vec2 suv = SCREEN_UV + normalize(c + 0.0001) * ripple + vec2(sin(UV.y * 24.0 + t * 3.0), cos(UV.x * 21.0 + t * 2.6)) * strength * 0.35;
	vec4 scr = texture(screen_tex, suv);
	vec4 o = texture(TEXTURE, UV);
	COLOR = vec4(mix(scr.rgb * tint.rgb, o.rgb, o.a * own), edge * COLOR.a);
}
"""
static var _distort: Shader

static func distort_material(strength: float, tint: Color, own: float, round_mask: bool = true) -> ShaderMaterial:
	if _distort == null:
		_distort = Shader.new()
		_distort.code = DISTORT_SHADER
	var m := ShaderMaterial.new()
	m.shader = _distort
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("own", own)
	m.set_shader_parameter("round_mask", 1.0 if round_mask else 0.0)
	return m

## An expanding, fading ring (Blightness pings, rage, furnace flare) that frees itself.
class FxRing extends Node2D:
	var color := Color(0.75, 0.9, 0.45)
	var radius := 60.0
	var dur := 0.9
	var _t := 0.0
	func _process(delta: float) -> void:
		_t += delta
		if _t >= dur:
			queue_free()
		queue_redraw()
	func _draw() -> void:
		var k := clampf(_t / dur, 0.0, 1.0)
		draw_arc(Vector2.ZERO, 6.0 + radius * k, 0.0, TAU, 48, Color(color.r, color.g, color.b, (1.0 - k) * 0.8), 2.5 * (1.0 - k) + 0.5, true)

static func ring(parent: Node, pos: Vector2, color: Color, radius: float = 60.0, dur: float = 0.9) -> void:
	var r := FxRing.new()
	r.position = pos
	r.color = color
	r.radius = radius
	r.dur = dur
	r.z_index = 6
	parent.add_child(r)

## Returns true when the event was a world-visual event handled here.
func apply(type: String, d: Dictionary) -> bool:
	match type:
		"decal":
			var s := Sprite2D.new()
			s.texture = Art.tex(d["sprite"])
			s.position = Vector2(d["x"], d["y"])
			s.rotation = float(d.get("rot", 0.0))
			var k := float(d.get("size", 28.0)) / maxf(1.0, s.texture.get_size().x)
			s.scale = Vector2(k, k)
			if d.get("uv", false):
				s.material = _uv_material
				s.light_mask = 2
			view.decal_layer.add_child(s)
			decals[d["id"]] = s
		"decal_remove":
			if decals.has(d["id"]) and is_instance_valid(decals[d["id"]]):
				decals[d["id"]].queue_free()
			decals.erase(d["id"])
		"decal_swap":
			if decals.has(d["id"]) and is_instance_valid(decals[d["id"]]):
				decals[d["id"]].texture = Art.tex(d["sprite"])
		"flicker":
			view.flicker(float(d["dur"]), float(d["strength"]))
		"darkness":
			view.set_darkness(Color.html(d["color"]), float(d["t"]))
		"mirror":
			view.show_mirror_overlay(int(d["index"]), Art.tex(Defs.FORM_TOKENS["true"]), 0.85 if d.get("on", true) else 0.0)
		"shake":
			view.shake_furniture(int(d["index"]))
		"orb":
			var o := Sprite2D.new()
			o.texture = Art.tex("items/orb.png")
			o.scale = Vector2(0.35, 0.35)
			o.visible = false
			o.set_meta("base", Vector2(d["x"], d["y"]))
			o.set_meta("phase", float(d["phase"]))
			text_layer.add_child(o)
			orbs.append(o)
		"creature_fx":
			match str(d.get("kind", "")):
				"ping": ring(view.overlay_layer, Vector2(d["x"], d["y"]), Color(0.75, 0.9, 0.45), 70.0, 0.9)
				"rage": ring(view.overlay_layer, Vector2(d["x"], d["y"]), Color(1.0, 0.25, 0.15), 110.0, 1.2)
				"twitch":
					if decals.has(d["id"]) and is_instance_valid(decals[d["id"]]):
						twitch(decals[d["id"]])
		"shimmer":
			view.shimmer_room(str(d["room"]))
		"npc_burn":
			view.burst_flames(Vector2(d["x"], d["y"]), 1.6)
		"furnace":
			view.burst_flames(Vector2(d["x"], d["y"]), 2.2, 2.0)
			ring(view.overlay_layer, Vector2(d["x"], d["y"]), Color(1.0, 0.5, 0.15), 140.0, 1.4)
		"door":
			view.set_door(int(d["i"]), bool(d["open"]))
		"light":
			view.set_light(int(d["i"]), bool(d["on"]))
		"orb_clear":
			for o in orbs:
				o.queue_free()
			orbs.clear()
		_:
			return false
	return true

## A keepsake rattling on its own.
static func twitch(s: Node2D) -> void:
	if s.has_meta("twitching"):
		return
	s.set_meta("twitching", true)
	var base := s.rotation
	var tw := s.create_tween()
	for i in 6:
		tw.tween_property(s, "rotation", base + (0.22 if i % 2 == 0 else -0.22), 0.06)
	tw.tween_property(s, "rotation", base, 0.06)
	tw.tween_callback(func(): s.remove_meta("twitching"))

func set_orbs_visible(v: bool) -> void:
	for o in orbs:
		o.visible = v

func tick(delta: float) -> void:
	_t += delta
	for o in orbs:
		var ph: float = o.get_meta("phase")
		o.position = o.get_meta("base") + Vector2(sin(_t * 0.7 + ph) * 18.0, cos(_t * 0.5 + ph * 2.0) * 14.0)
		o.modulate.a = 0.55 + 0.35 * sin(_t * 2.0 + ph)

func clear() -> void:
	for k in decals:
		if is_instance_valid(decals[k]):
			decals[k].queue_free()
	decals.clear()
	for o in orbs:
		o.queue_free()
	orbs.clear()
