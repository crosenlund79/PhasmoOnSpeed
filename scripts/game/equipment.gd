class_name EquipmentController
extends Node
## Fast equipment handling: number keys / wheel select, left click uses, E
## interacts (hold for melting / lighting), V performs rites. Produces the short
## readout line shown above the hotbar.

signal changed()

var run: Run
var player: Player
var slots: Array = []         # equipment ids currently in the hotbar
var selected := 0
var readout := ""
var readout_color := Color(0.93, 0.88, 0.76)
var hold_action := ""         # "interact" / "rite" while a hold is in progress
var hold_t := 0.0
var hold_needed := 0.0
var prompt := ""
var _cooldown := 0.0
var _beep_t := 0.0
var _thermo_cold_t := 0.0
var _spirit_t := -1.0
var _mirror_t := 0.0
var _investigated := {}       # "room|tool" pairs already counted as investigation
var _tool_room_t := 0.0
var _last_tool_room := ""

func setup(p_run: Run, p_player: Player) -> void:
	run = p_run
	player = p_player
	rebuild_slots()

func rebuild_slots() -> void:
	var cur := current()
	slots = Defs.BASE_LOADOUT.duplicate()
	for r in Defs.RESOURCE_ORDER:
		if player.has_resource(r):
			slots.append(r)
	selected = maxi(0, slots.find(cur)) if cur != "" else 0
	changed.emit()

func current() -> String:
	if selected < 0 or selected >= slots.size():
		return ""
	return slots[selected]

func select(i: int) -> void:
	if i < 0 or i >= slots.size() or i == selected:
		return
	_end_spirit_box()
	selected = i
	Sfx.play("ui_click", -10.0)
	run.record_event("equip", {"item": current()})
	changed.emit()

func charge_text(id: String) -> String:
	match id:
		"salt", "holy_water":
			return str(player.charges[id])
		"crucifix":
			return "" if player.charges["crucifix"] > 0 else "—"
		"ghost_book":
			return "—" if player.book_placed else ""
		"silverware":
			return "%d/%d" % [int(player.resources.get("silverware", 0)), Defs.SILVERWARE_NEEDED]
	return ""

# --- Per-frame -----------------------------------------------------------------------

func process_input(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if not player.input_enabled or player.dead:
		hold_action = ""
		return
	for i in 9:
		if Input.is_action_just_pressed("slot_%d" % (i + 1)):
			select(i)
	if Input.is_action_just_pressed("cycle_next"):
		select((selected + 1) % slots.size())
	if Input.is_action_just_pressed("cycle_prev"):
		select((selected - 1 + slots.size()) % slots.size())
	if Input.is_action_just_pressed("cycle"):
		# Q jumps through found resources first, then back to the base kit.
		var nxt := (selected + 1) % slots.size()
		if slots.size() > Defs.BASE_LOADOUT.size() and selected < Defs.BASE_LOADOUT.size():
			nxt = Defs.BASE_LOADOUT.size()
		select(nxt)
	if Input.is_action_just_pressed("flashlight"):
		player.flashlight_on = not player.flashlight_on
		Sfx.play("flashlight_click", -4.0)
		run.record_event("flashlight", {"on": player.flashlight_on})
	if Input.is_action_just_pressed("suspect"):
		run.cycle_suspect()
	if Input.is_action_just_pressed("use"):
		use_current()
	if current() == "hand_mirror" and Input.is_action_pressed("use"):
		_mirror_t += delta
		if _mirror_t >= 0.5:
			_mirror_t = -10.0
			_mirror_check()
	else:
		_mirror_t = 0.0
	_update_holds(delta)

func _update_holds(delta: float) -> void:
	var interact := run.find_interactable(player.global_position)
	prompt = ""
	if not interact.is_empty():
		prompt = "[E] " + interact["label"]
	var rite := run.rite_prompt()
	if rite != "" and prompt == "":
		prompt = rite
	var action := ""
	var needed := 0.0
	if Input.is_action_pressed("interact") and not interact.is_empty():
		action = "interact"
		needed = interact.get("hold", 0.0)
	elif Input.is_action_pressed("rite"):
		action = "rite"
		needed = run.rite_hold_time()
	elif Input.is_action_pressed("restart"):
		action = "restart"
		needed = 0.8
	if action == "":
		hold_action = ""
	elif hold_action == "done" or hold_action == "blocked":
		pass   # wait for the key to be released before another action
	elif action != hold_action:
		hold_action = action
		hold_t = 0.0
		hold_needed = needed
		if action == "rite" and not run.can_begin_rite():
			hold_action = "blocked"
		elif action == "interact" and needed <= 0.0:
			run.do_interact(interact)
			hold_action = "done"
	if hold_action in ["interact", "rite", "restart"]:
		hold_t += delta
		if hold_t >= hold_needed:
			var a := hold_action
			hold_action = "done"
			match a:
				"interact": run.do_interact(interact)
				"rite": run.perform_rite()
				"restart": run.restart()

func hold_progress() -> float:
	if hold_action in ["interact", "rite", "restart"] and hold_needed > 0.0:
		return clampf(hold_t / hold_needed, 0.0, 1.0)
	return 0.0

## Updates detector readouts and investigation credit. Called by Run each frame.
func update_tools(delta: float) -> void:
	var cur := current()
	var ph: Phenomena = run.phenomena
	player.uv_light.visible = cur == "uv"
	ph.set_orbs_visible(cur == "orb_camera")
	readout = ""
	readout_color = Color(0.93, 0.88, 0.76)
	_track_investigation(cur, delta)
	match cur:
		"emf":
			var r := ph.emf_at(player.global_position)
			var lv: int = r[0]
			readout = "EMF   " + "▮".repeat(lv) + "▯".repeat(5 - lv) + ("   LEVEL FIVE" if lv == 5 else "")
			if lv >= 4:
				readout_color = Color(1.0, 0.45, 0.3)
			_beep_t -= delta
			if lv >= 2 and _beep_t <= 0.0:
				_beep_t = 0.9 / lv
				Sfx.play("emf_spike" if lv == 5 else "emf_beep", -10.0 + lv, 0.8 + lv * 0.12, 0.05)
			if lv == 5:
				run.discover("emf5", r[1])
		"thermometer":
			var temp := ph.temperature(player.room_id)
			readout = "Thermometer  %.1f °C  · %s" % [temp, run.map.room_name(player.room_id)]
			if temp <= 0.0:
				readout_color = Color(0.6, 0.85, 1.0)
				_thermo_cold_t += delta
				if _thermo_cold_t > 1.2:
					run.discover("freezing", player.room_id)
			else:
				_thermo_cold_t = 0.0
		"uv":
			readout = "UV light — sweep walls and doorways"
		"spirit_box":
			readout = "Spirit Box — click to ask a question" if _spirit_t < 0.0 else "Spirit Box — listening…"
		"ghost_book":
			readout = "Ghost Writing Book — click to lay it down" if not player.book_placed else "Book placed — [E] near it to retrieve"
		"orb_camera":
			readout = "Orb Camera — viewfinder active"
		"salt":
			readout = "Salt (%d) — click to pour a line" % player.charges["salt"]
		"crucifix":
			readout = "Crucifix — click to place (%d burns)" % player.crucifix_burns if player.charges["crucifix"] > 0 else "Crucifix placed — [E] to retrieve"
		"holy_water":
			readout = "Holy Water (%d) — click to splash" % player.charges["holy_water"]
		"garlic":
			readout = "Garlic — its stench repels some things"
		"wooden_stake", "silver_stake", "iron_nails":
			readout = "%s — click to strike at close range" % Defs.EQUIPMENT[cur]["name"]
		"silverware":
			readout = "Silverware %d/%d — melt at a stove or hearth" % [int(player.resources.get("silverware", 0)), Defs.SILVERWARE_NEEDED]
		"hand_mirror":
			readout = "Hand Mirror — hold click to look into it"
	if _spirit_t >= 0.0:
		_spirit_t += delta
		if _spirit_t >= 1.6:
			_spirit_answer()

func _track_investigation(cur: String, delta: float) -> void:
	# Meaningful investigation = actually using a detector in a room for a moment.
	# Flashlight toggling and idle equipment swapping never count.
	if not Defs.EQUIPMENT.get(cur, {}).get("detector", false):
		_tool_room_t = 0.0
		return
	var key := player.room_id + "|" + cur
	if key != _last_tool_room:
		_last_tool_room = key
		_tool_room_t = 0.0
	_tool_room_t += delta
	if _tool_room_t > 2.0 and not _investigated.has(key):
		_investigated[key] = true
		run.add_investigation(1, "tool:" + cur)

# --- Using items ------------------------------------------------------------------------

func use_current() -> void:
	if _cooldown > 0.0:
		return
	var cur := current()
	var front := player.global_position + player.facing_vector() * 22.0
	match cur:
		"spirit_box":
			if _spirit_t < 0.0:
				_spirit_t = 0.0
				_cooldown = 2.0
				Sfx.start_loop("spirit", "spirit_box_static", -8.0, 0.15)
				run.record_event("spirit_box", {})
				run.add_investigation(1, "spirit_box")
		"ghost_book":
			if not player.book_placed and run.place_item("ghost_book", front):
				player.book_placed = true
		"salt":
			if player.charges["salt"] > 0 and run.place_item("salt", front):
				player.charges["salt"] -= 1
				Sfx.play("salt_pour", -4.0)
		"crucifix":
			if player.charges["crucifix"] > 0 and run.place_item("crucifix", front):
				player.charges["crucifix"] = 0
		"holy_water":
			if player.charges["holy_water"] > 0:
				player.charges["holy_water"] -= 1
				_cooldown = 0.8
				run.splash_holy_water()
		"wooden_stake", "silver_stake", "iron_nails":
			_cooldown = 0.9
			run.strike(cur)
		"garlic":
			_cooldown = 1.0
			run.toast("You brandish the garlic. The smell alone is a weapon.", "icons/eq_garlic.png")
		"silverware":
			run.toast("Melt %d pieces at a stove or hearth to cast a silver stake." % Defs.SILVERWARE_NEEDED, "icons/eq_silverware.png")
			_cooldown = 1.0
		"orb_camera":
			Sfx.play("camera_shutter", -4.0, 1.0, 0.3)
			_cooldown = 0.6
		"emf", "thermometer", "uv":
			pass
	changed.emit()

func _end_spirit_box() -> void:
	if _spirit_t >= 0.0:
		_spirit_t = -1.0
		Sfx.stop_loop("spirit", 0.2)

func _spirit_answer() -> void:
	_end_spirit_box()
	var c: Creature = run.creature
	var answered := false
	if c and "spirit_box" in run.phenomena.evidence and c.state != "banished":
		var close: bool = player.room_id == c.lair_room or player.global_position.distance_to(c.position) < 220.0
		if close and run.rng.randf() < 0.75:
			answered = true
	if player.room_id == (c.lair_room if c else ""):
		run.add_threat(2.0, "spirit_box_lair")
	if answered:
		Sfx.play("spirit_box_voice", 0.0)
		var lines := ["\"…behind…\"", "\"…leave…\"", "\"…here…\"", "\"…mine…\"", "\"…cold…\""]
		run.toast("Spirit Box: " + lines[run.rng.randi_range(0, lines.size() - 1)], "icons/eq_spirit_box.png")
		run.discover("spirit_box", player.room_id)
	else:
		run.toast("Spirit Box: …only static.", "icons/eq_spirit_box.png", true)

func _mirror_check() -> void:
	var c: Creature = run.creature
	Sfx.play("mirror_reveal", -6.0, 1.0, 0.5)
	if c == null or c.state == "banished":
		return
	var to := c.position - player.global_position
	var in_view := to.length() < 270.0 and absf(angle_difference(player.aim_angle, to.angle())) < 0.55 and run.map.los(player.global_position, c.position)
	# The mirror shows a shapeshifter's truth even when it is unseen; anything
	# else is only reflected when it is actually visible.
	if not in_view or (c.type_id != "shapeshifter" and not c.is_visible_now()):
		run.toast("Only your own frightened face looks back.", "icons/eq_hand_mirror.png", true)
		return
	if c.type_id == "shapeshifter":
		c.expose(12.0)
		Sfx.play("mirror_reveal", 2.0)
		run.big_message("ITS TRUE FORM IS REVEALED", "The mirror will not lie for it. Strike while it is exposed.", Color(0.8, 0.6, 1.0), 2.4)
		run.record_event("expose", {})
		run.add_investigation(2, "mirror")
	else:
		run.toast("The reflection matches what stands before you.", "icons/eq_hand_mirror.png")
		run.add_investigation(1, "mirror")
