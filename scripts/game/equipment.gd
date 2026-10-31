class_name EquipmentController
extends Node
## One per hunter (on the host / in solo). Fast equipment handling driven by the
## hunter's PlayerInput: number keys / wheel select, left click uses, E interacts
## (hold for melting / lighting), V performs rites, Space shoves. Produces:
##   reading — the short value shown at the top ("NEEDLE 4 · STRIKING")
##   hint    — the longer instruction line shown above the hotbar

signal changed()

const IDLE := Color(0.93, 0.88, 0.76, 0.55)
const NORMAL := Color(0.96, 0.92, 0.82)
const HOT := Color(1.0, 0.5, 0.32)
const COLD := Color(0.62, 0.86, 1.0)

var run: Run
var player: Player
var slots: Array = []         # equipment ids currently in the hotbar
var selected := 0
var reading := ""
var reading_color := IDLE
var reading_active := false   # false = idle state (subtle / hidden)
var hint := ""
var hold_action := ""         # "interact" / "rite" while a hold is in progress
var hold_t := 0.0
var hold_needed := 0.0
var prompt := ""
var _cooldown := 0.0
var _beep_t := 0.0
var _thermo_cold_t := 0.0
var _spirit_t := -1.0
var _spirit_result := ""
var _spirit_result_t := 0.0
var _mirror_t := 0.0
var _investigated := {}       # "room|tool" pairs already counted as investigation
var _tool_room_t := 0.0
var _last_tool_room := ""
var _emf_smooth := 1.0
var interact_pos := Vector2.INF   # what [E] would act on (highlighted)
var interact_icon := ""
var near_items: Array = []        # pickups close by (faintly highlighted)
var needle := 0.0                 # Witch's Needle agitation 0–5 (0 = not held)

func setup(p_run: Run, p_player: Player) -> void:
	run = p_run
	player = p_player
	player.equipment = self
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
	run.sound_to(player, "ui_click", -10.0)
	run.record_event("equip", {"actor": player.actor_id, "item": current()})
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
	var inp := player.input
	if not player.input_enabled or player.dead:
		hold_action = ""
		prompt = ""
		interact_pos = Vector2.INF
		return
	for i in 9:
		if inp.just_pressed("slot_%d" % (i + 1)):
			select(i)
	if inp.just_pressed("cycle_next"):
		select((selected + 1) % slots.size())
	if inp.just_pressed("cycle_prev"):
		select((selected - 1 + slots.size()) % slots.size())
	if inp.just_pressed("cycle"):
		# Q jumps through found resources first, then back to the base kit.
		var nxt := (selected + 1) % slots.size()
		if slots.size() > Defs.BASE_LOADOUT.size() and selected < Defs.BASE_LOADOUT.size():
			nxt = Defs.BASE_LOADOUT.size()
		select(nxt)
	if inp.just_pressed("flashlight"):
		player.flashlight_on = not player.flashlight_on
		run.sound_to(player, "flashlight_click", -4.0)
		run.record_event("flashlight", {"actor": player.actor_id, "on": player.flashlight_on})
	if inp.just_pressed("suspect"):
		run.cycle_suspect(player, 1)
	if inp.just_pressed("suspect_prev"):
		run.cycle_suspect(player, -1)
	if inp.just_pressed("shove"):
		run.shove(player)
	if inp.just_pressed("use"):
		use_current()
	if current() == "hand_mirror" and inp.pressed("use"):
		_mirror_t += delta
		if _mirror_t >= 0.5:
			_mirror_t = -10.0
			_mirror_check()
	else:
		_mirror_t = 0.0
	_update_holds(delta)

func _update_holds(delta: float) -> void:
	var inp := player.input
	var interact: Dictionary = run.find_interactable(player, player.global_position)
	interact_pos = interact.get("pos", player.global_position) if not interact.is_empty() else Vector2.INF
	interact_icon = interact.get("icon", "")
	prompt = ""
	if not interact.is_empty():
		prompt = "E / SPACE — " + interact["label"]
	var rite: String = run.rite_prompt(player)
	if rite != "" and prompt == "":
		prompt = rite
	var action := ""
	var needed := 0.0
	if inp.pressed("interact") and not interact.is_empty():
		action = "interact"
		needed = interact.get("hold", 0.0)
	elif inp.pressed("rite"):
		action = "rite"
		needed = run.rite_hold_time()
	elif inp.pressed("restart") and run.can_restart():
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
		if action == "rite" and not run.can_begin_rite(player):
			hold_action = "blocked"
		elif action == "rite":
			run.on_rite_begun(player)
		elif action == "interact" and needed <= 0.0:
			run.do_interact(player, interact)
			hold_action = "done"
	if hold_action in ["interact", "rite", "restart"]:
		hold_t += delta
		if hold_t >= hold_needed:
			var a := hold_action
			hold_action = "done"
			match a:
				"interact": run.do_interact(player, interact)
				"rite": run.perform_rite(player)
				"restart": run.restart()

func hold_progress() -> float:
	if hold_action in ["interact", "rite", "restart"] and hold_needed > 0.0:
		return clampf(hold_t / hold_needed, 0.0, 1.0)
	return 0.0

func _set_reading(text: String, col: Color, active: bool = true) -> void:
	reading = text
	reading_color = col
	reading_active = active

## Updates detector readings and investigation credit. Called by Run each frame.
func update_tools(delta: float) -> void:
	var cur := current()
	var ph: Phenomena = run.phenomena
	player.uv_light.visible = cur == "uv" and not player.dead
	if player.is_local:
		ph.set_orbs_visible(cur == "orb_camera")
	_set_reading("", IDLE, false)
	hint = ""
	needle = 0.0
	near_items = run.nearby_pickups(player.global_position) if not player.dead else []
	_track_investigation(cur, delta)
	_spirit_result_t -= delta
	match cur:
		"emf":
			var r := ph.emf_at(player.global_position)
			var lv: int = r[0]
			var target := ph.emf_value(player.global_position)
			# The local hunter's equipped needle variant (Progression) only reaches a
			# little further and settles faster on the DISPLAYED reading; evidence below
			# still comes from emf_at() alone.
			var nv := Progression.needle_params(player.is_local)
			if float(nv["sense"]) > 1.0:
				target = maxf(target, Progression.needle_sense(ph.hotspots, player.global_position, nv["sense"]))
			_emf_smooth = lerpf(_emf_smooth, target, clampf(delta * float(nv["smooth"]), 0.0, 1.0))
			# Witch's Needle: same thresholds as the old EMF reading (Level 5 = evidence).
			var shown := 5.0 if lv == 5 else minf(_emf_smooth, 4.9)
			needle = shown
			var words := ["STILL", "STILL", "TWITCHING", "TAPPING", "STRIKING", "RATTLING!"]
			var num := ("%.1f" % shown) if nv["precise"] and lv != 5 else str(int(shown))
			_set_reading("NEEDLE %s · %s" % [num, words[int(shown)]], HOT if shown >= 4.0 else (NORMAL if shown >= 2.0 else IDLE), shown >= 2.0)
			hint = "Witch's Needle — it stirs near a presence"
			# Glass taps, faster and harder with the agitation; a soft rattle at Level 5.
			_beep_t -= delta
			if shown >= 1.8 and _beep_t <= 0.0:
				_beep_t = 0.07 if lv == 5 else clampf(1.1 / pow(shown - 0.8, 1.6), 0.12, 0.9)
				run.sound_to(player, "needle_tap", -16.0 + shown * 2.0 - (4.0 if lv == 5 else 0.0), randf_range(0.85, 1.25))
			if lv == 5:
				run.discover(player, "emf5", r[1])
		"thermometer":
			var temp := ph.temperature(player.room_id)
			_set_reading("%.1f °C" % temp, COLD if temp <= 3.0 else NORMAL, true)
			hint = "Thermometer — %s" % run.map.room_name(player.room_id)
			if temp <= 0.0:
				_thermo_cold_t += delta
				if _thermo_cold_t > 1.2:
					run.discover(player, "freezing", player.room_id)
			else:
				_thermo_cold_t = 0.0
		"uv":
			_set_reading("WRAITHLIGHT", Color(0.78, 0.6, 1.0, 0.7), false)
			hint = "Wraithlight Lantern — sweep walls and doorways"
		"spirit_box":
			if _spirit_t >= 0.0:
				_set_reading("WHISPER BOX: LISTENING…", NORMAL, true)
			elif _spirit_result_t > 0.0:
				_set_reading(_spirit_result, HOT if _spirit_result.ends_with("WHISPERS") else NORMAL, true)
			else:
				_set_reading("WHISPER BOX", IDLE, false)
			hint = "Whisper Box — click to open the lid and ask"
		"ghost_book":
			hint = "Ghost Writing Book — click to lay it down" if not player.book_placed else "Book placed — [E] near it to retrieve"
			_set_reading("BOOK PLACED" if player.book_placed else "", IDLE, false)
		"orb_camera":
			_set_reading("◉ SCRYING", Color(0.7, 0.85, 0.95, 0.8), false)
			hint = "Scrying Mirror — orbs show in the black glass"
		"salt":
			hint = "Salt (%d) — click to pour a line" % player.charges["salt"]
		"crucifix":
			hint = "Crucifix — click to place (%d burns)" % player.crucifix_burns if player.charges["crucifix"] > 0 else "Crucifix placed — [E] to retrieve"
		"holy_water":
			hint = "Holy Water (%d) — click to splash" % player.charges["holy_water"]
		"garlic":
			hint = "Garlic — its stench repels some things"
		"wooden_stake", "silver_stake", "iron_nails":
			hint = "%s — click to strike at close range" % Defs.EQUIPMENT[cur]["name"]
		"silverware":
			hint = "Silverware %d/%d — melt at a stove or hearth" % [int(player.resources.get("silverware", 0)), Defs.SILVERWARE_NEEDED]
		"hand_mirror":
			hint = "Hand Mirror — hold click to look into it"
		"voodoo_doll":
			hint = "Voodoo Doll — click to stab it (something will answer)"
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
		run.add_investigation(player, 1, "tool:" + cur)

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
				if player.is_local:
					Sfx.start_loop("spirit", "spirit_box_static", -8.0, 0.15)
				run.record_event("spirit_box", {"actor": player.actor_id})
				run.add_investigation(player, 1, "spirit_box")
		"ghost_book":
			if not player.book_placed and run.place_item(player, "ghost_book", front):
				player.book_placed = true
		"salt":
			if player.charges["salt"] > 0 and run.place_item(player, "salt", front):
				player.charges["salt"] -= 1
				run.sound_at("salt_pour", player.global_position, -4.0)
		"crucifix":
			if player.charges["crucifix"] > 0 and run.place_item(player, "crucifix", front):
				player.charges["crucifix"] = 0
		"holy_water":
			if player.charges["holy_water"] > 0:
				player.charges["holy_water"] -= 1
				_cooldown = 0.8
				run.splash_holy_water(player)
		"wooden_stake", "silver_stake", "iron_nails":
			_cooldown = 0.9
			run.strike(player, cur)
		"garlic":
			_cooldown = 1.0
			run.tell(player, "You brandish the garlic. The smell alone is a weapon.", "icons/eq_garlic.png")
		"silverware":
			run.tell(player, "Melt %d pieces at a stove or hearth to cast a silver stake." % Defs.SILVERWARE_NEEDED, "icons/eq_silverware.png")
			_cooldown = 1.0
		"orb_camera":
			run.sound_to(player, "mirror_reveal", -14.0, 1.3)
			_cooldown = 0.6
		"voodoo_doll":
			_cooldown = 1.0
			run.use_voodoo(player)
		"emf", "thermometer", "uv":
			pass
	changed.emit()

func _end_spirit_box() -> void:
	if _spirit_t >= 0.0:
		_spirit_t = -1.0
		if player.is_local:
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
	_spirit_result_t = 2.5
	if answered:
		run.sound_at("spirit_box_voice", player.global_position, 0.0)
		var lines := ["\"…behind…\"", "\"…leave…\"", "\"…here…\"", "\"…mine…\"", "\"…cold…\""]
		_spirit_result = "WHISPER BOX: IT WHISPERS"
		run.tell(player, "Whisper Box: " + lines[run.rng.randi_range(0, lines.size() - 1)], "icons/eq_spirit_box.png")
		run.discover(player, "spirit_box", player.room_id)
	else:
		_spirit_result = "WHISPER BOX: SILENCE"

func _mirror_check() -> void:
	var c: Creature = run.creature
	run.sound_to(player, "mirror_reveal", -6.0)
	if c == null or c.state == "banished":
		return
	var to := c.position - player.global_position
	var in_view := to.length() < 270.0 and absf(angle_difference(player.aim_angle, to.angle())) < 0.55 and run.map.los(player.global_position, c.position)
	# The mirror shows a shapeshifter's truth even when it is unseen; anything
	# else is only reflected when it is actually visible.
	if not in_view or (c.type_id != "shapeshifter" and not c.is_visible_now()):
		run.tell(player, "Only your own frightened face looks back.", "icons/eq_hand_mirror.png", true)
		return
	if c.type_id == "shapeshifter":
		c.expose(12.0)
		run.sound_at("mirror_reveal", player.global_position, 2.0)
		run.announce_to(player, "ITS TRUE FORM IS REVEALED", "The mirror will not lie for it. Strike while it is exposed.", Color(0.8, 0.6, 1.0), 2.4)
		run.record_event("expose", {"actor": player.actor_id})
		run.add_investigation(player, 2, "mirror")
	else:
		run.tell(player, "The reflection matches what stands before you.", "icons/eq_hand_mirror.png")
		run.add_investigation(player, 1, "mirror")
