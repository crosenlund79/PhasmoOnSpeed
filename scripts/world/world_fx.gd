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
		"orb_clear":
			for o in orbs:
				o.queue_free()
			orbs.clear()
		_:
			return false
	return true

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
