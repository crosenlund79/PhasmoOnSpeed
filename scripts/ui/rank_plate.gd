class_name RankPlate
extends PanelContainer
## A small engraved brass plate: hunter title, Renown level, progress to the next
## level and the Gold Ducat purse. Used on the main menu and in the Forest Tavern.

const BRASS := Color(0.62, 0.48, 0.24)
const BRASS_DARK := Color(0.27, 0.18, 0.08)
const ENGRAVE := Color(0.16, 0.1, 0.04)

var _title: Label
var _level: Label
var _bar: RenownBar
var _purse: Label

static func brass_style(bg: Color = BRASS) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = BRASS_DARK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(5)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(2, 3)
	sb.set_content_margin_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	return sb

func _init() -> void:
	add_theme_stylebox_override("panel", brass_style())
	custom_minimum_size = Vector2(330, 0)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	_title = Art.label("", 23, ENGRAVE, Art.font_heading)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	_level = Art.label("", 17, ENGRAVE, Art.font_heading)
	top.add_child(_level)
	_bar = RenownBar.new()
	_bar.custom_minimum_size = Vector2(0, 12)
	v.add_child(_bar)
	_purse = Art.label("", 15, ENGRAVE, Art.font_italic)
	v.add_child(_purse)
	refresh()

func refresh() -> void:
	var p: Dictionary = SaveData.progress()
	var info := Progression.level_info(int(p["renown"]))
	_title.text = info["title"]
	_level.text = "Level %d" % info["level"]
	_bar.frac = info["frac"]
	_bar.queue_redraw()
	var next := "%d / %d Renown" % [info["into"], info["need"]] if info["need"] > 0 else "%d Renown" % int(p["renown"])
	_purse.text = "%s   ·   %d Gold Ducats" % [next, int(p["ducats"])]

## Results-screen lines for a reward returned by Progression.grant().
static func add_reward_lines(v: VBoxContainer, reward: Dictionary) -> void:
	if reward.is_empty() or not reward.get("granted", false):
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	row.add_child(Art.label("Spoils", 18, Art.INK, Art.font_heading))
	row.add_child(Art.label("+%d Gold Ducats" % int(reward["ducats"]), 18, Color(0.5, 0.36, 0.08), Art.font_heading))
	row.add_child(Art.label("+%d Renown" % int(reward["renown"]), 18, Color(0.35, 0.18, 0.4), Art.font_heading))
	if int(reward["level"]) > int(reward["level_before"]):
		var t := "Renown rises: Level %d" % int(reward["level"])
		if reward["title"] != reward["title_before"]:
			t += " — you are now a %s!" % reward["title"]
		v.add_child(Art.label(t, 17, Art.BLOOD, Art.font_heading))
	else:
		var info := Progression.level_info(int(SaveData.progress()["renown"]))
		v.add_child(Art.label("%s · Level %d · %d / %d Renown to the next" % [info["title"], info["level"], info["into"], info["need"]], 14, Color(0.3, 0.22, 0.15), Art.font_italic))

## What fleeing or dying cost (results screens).
static func add_penalty_lines(v: VBoxContainer, pen: Dictionary) -> void:
	if pen.is_empty() or not pen.get("applied", false):
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	row.add_child(Art.label("Fled" if pen["kind"] == "flee" else "The price of death", 18, Art.INK, Art.font_heading))
	row.add_child(Art.label("%d Renown" % int(pen["renown"]), 18, Art.BLOOD, Art.font_heading))
	if str(pen.get("lost_item", "")) != "":
		v.add_child(Art.label("Lost: %s — it shattered as you fell." % pen["lost_item"], 16, Art.BLOOD, Art.font_italic))
	if int(pen["level"]) < int(pen["level_before"]):
		v.add_child(Art.label("Renown falls: Level %d (%s)" % [int(pen["level"]), pen["title"]], 15, Art.BLOOD, Art.font_italic))

## Results-screen line for a contract settled by Progression.settle_mission().
static func add_mission_lines(v: VBoxContainer, m: Dictionary) -> void:
	if m.is_empty():
		return
	var t := ""
	if m["success"]:
		t = "Contract fulfilled: %s" % m["name"]
		if int(m["ducats"]) > 0:
			t += "  ·  +%d Gold Ducats" % int(m["ducats"])
		if int(m["renown"]) > 0:
			t += "  ·  +%d Renown" % int(m["renown"])
		if not m["granted"]:
			t += "  (already paid)"
	else:
		t = "Contract failed: %s" % m["name"]
		if int(m["renown"]) < 0:
			t += "  ·  %d Renown" % int(m["renown"])
		if m.get("once", false):
			t += "  ·  It will not be offered again."
	var l := Art.label(t, 17, Color(0.42, 0.3, 0.06) if m["success"] else Art.BLOOD, Art.font_heading)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)

## An engraved channel filled with molten gold.
class RenownBar extends Control:
	var frac := 0.0
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.12, 0.08, 0.04, 0.85))
		var f := Rect2(Vector2(2, 2), Vector2((size.x - 4.0) * clampf(frac, 0.0, 1.0), size.y - 4.0))
		draw_rect(f, Color(0.98, 0.78, 0.36))
		draw_rect(Rect2(f.position, Vector2(f.size.x, f.size.y * 0.4)), Color(1, 0.95, 0.75, 0.5))
		for i in range(1, 10):
			var x := size.x * i / 10.0
			draw_line(Vector2(x, 1), Vector2(x, size.y - 1), Color(0.1, 0.06, 0.02, 0.35), 1.0)
		draw_rect(r, Color(0.1, 0.06, 0.02), false, 1.5)
