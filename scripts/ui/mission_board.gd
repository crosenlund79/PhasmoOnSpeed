class_name MissionBoard
extends PanelContainer
## Special contracts offered in the Forest Tavern (see Progression.MISSIONS): the
## Antiquarian's merchant contracts or the Tavern Keeper's one-attempt jobs. Shows
## each contract's requirements, rewards and state; "Take the contract" starts it
## through the ordinary setup flow. Solo only.

signal changed()

const HEADS := {
	"antiquarian": ["Ashby Crane's Contracts", "“Harder houses, better coin. I pay for results, not for courage.”"],
	"keeper": ["Gideon Tallow's Jobs", "“One try each. Fail me and the whole valley hears of it. So do I.”"],
}
const STATE_COLORS := {"locked": Color(0.4, 0.33, 0.27), "available": Color(0.3, 0.45, 0.15),
	"completed": Color(0.55, 0.4, 0.08), "failed": Color(0.55, 0.1, 0.08)}

var giver := "antiquarian"
var _title: Label
var _quote: Label
var _list: VBoxContainer
var _balance: Label

func _init() -> void:
	custom_minimum_size = Vector2(800, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_title = Art.heading("", 30)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_balance = Art.label("", 17, Color(0.3, 0.2, 0.08), Art.font_heading)
	_balance.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_balance)
	_quote = Art.label("", 16, Color(0.35, 0.25, 0.18), Art.font_italic)
	v.add_child(_quote)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	v.add_child(_list)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(foot)
	foot.add_child(Art.label("Contracts are solo hunts, apart from ordinary investigations.   Esc to leave  ", 14, Color(0.4, 0.3, 0.2), Art.font_italic))
	foot.add_child(Art.button("Leave", func(): visible = false, 180))

func open(p_giver: String) -> void:
	giver = p_giver
	refresh()
	visible = true

func refresh() -> void:
	var p: Dictionary = SaveData.progress()
	var info := Progression.level_info(int(p["renown"]))
	_title.text = HEADS[giver][0]
	_quote.text = HEADS[giver][1]
	if giver == "keeper" and not p.get("blackmail_keeper", false):
		_quote.text = "“Those? Not for you. Not unless you've something on me.”"
	_balance.text = "%d Gold Ducats  ·  %s, Level %d" % [int(p["ducats"]), info["title"], info["level"]]
	for c in _list.get_children():
		c.queue_free()
	for id in Progression.missions_for(giver):
		_list.add_child(_row(id, p))

func _row(id: String, p: Dictionary) -> Control:
	var m: Dictionary = Progression.MISSIONS[id]
	var state := Progression.mission_state(p, id)
	var block := Progression.mission_block(p, id)
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.3, 0.2, 0.1, 0.18 if state == "available" else 0.08)
	sb.border_color = STATE_COLORS[state]
	sb.border_width_left = 6
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(8)
	sb.content_margin_left = 14
	box.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	box.add_child(h)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	info.add_child(top)
	top.add_child(Art.label(m["name"], 21, Art.INK, Art.font_heading))
	var chip := Art.label(state.to_upper(), 14, STATE_COLORS[state], Art.font_heading)
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(chip)
	var d := Art.label(m["desc"], 14, Color(0.3, 0.22, 0.15), Art.font_italic)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(380, 0)
	info.add_child(d)
	var ent := "an unknown entity" if m["entity"] == "random" else Defs.creature_name(m["entity"])
	var where := "%s  ·  %s  ·  %s%s" % [Game.house(m["house"]).get("name", m["house"]), Defs.DIFFICULTY_INFO[m["difficulty"]]["name"],
		ent, "  ·  Blood Moon" if m["blood_moon"] else ""]
	info.add_child(Art.label(where, 14, Color(0.25, 0.18, 0.12), Art.font_heading))
	var req := "Requires Renown Level %d" % int(m["level"])
	if m["giver"] == "keeper":
		req = "Requires leverage over the keeper" if block == "blackmail" else "Gideon owes you a hearing"
		req += "  ·  ONE attempt"
	info.add_child(Art.label(req, 14, Art.BLOOD if block in ["level", "blackmail"] else Color(0.3, 0.22, 0.15), Art.font_heading))
	var pay := "Reward: +%d Gold Ducats on first success" % int(m["ducats"]) if int(m["ducats"]) > 0 else "Reward: +%d Renown" % int(m["renown"])
	if int(m["penalty"]) > 0:
		pay += "  ·  Failure: -%d Renown" % int(m["penalty"])
	info.add_child(Art.label(pay, 14, Color(0.42, 0.3, 0.06), Art.font_heading))
	var b := Art.button("Take the contract", func(): _take(id), 200)
	b.disabled = block != "" or Net.is_online()
	b.tooltip_text = {"level": "Your Renown is not yet enough.", "blackmail": "Gideon won't offer this to you. Not yet.",
		"completed": "Already done.", "failed": "One attempt only."}.get(block, "Solo only." if Net.is_online() else "")
	if state in ["completed", "failed", "locked"]:
		b.text = state.capitalize()
	b.custom_minimum_size = Vector2(200, 44)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	return box

## Starts the contract through the ordinary setup flow (Game.start_setup), so the
## pre-game presentation and the run behave exactly as for a Custom Game.
func _take(id: String) -> void:
	if Net.is_online():
		return
	var p: Dictionary = SaveData.progress()
	if not Progression.take_mission(p, id, int(SaveData.data.get("runs_started", 0)) + 1):
		return
	SaveData.save()
	Sfx.play("needle_tap", -6.0)
	# A contract never becomes the remembered setup ("Hunt Again" stays ordinary).
	var prev = SaveData.settings().get("setup", null)
	Game.start_setup(Progression.mission_setup(id))
	if prev == null:
		SaveData.settings().erase("setup")
	else:
		SaveData.settings()["setup"] = prev
	SaveData.save()
