class_name Lighting
extends RefCounted
## Shared light construction.

## Flashlight-style cone. The light node sits AT the holder because Godot casts
## 2D shadows from the node position. (Previously the node was placed half a
## texture ahead to line up a left-origin cone, so shadows were cast from a point
## that could sit inside or behind a wall — cutting wedges out of the beam.)
## The texture's centre pixel is the cone's apex, so no offset is needed.
static func make_cone(color: Color, energy: float, scale: float) -> PointLight2D:
	var l := PointLight2D.new()
	var tex := Art.tex("lights/cone_centered.png")
	l.texture = tex
	l.texture_scale = scale
	l.energy = energy
	l.color = color
	l.shadow_enabled = true
	l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	l.shadow_filter_smooth = 1.5
	l.shadow_color = Color(0, 0, 0, 0.85)
	return l
