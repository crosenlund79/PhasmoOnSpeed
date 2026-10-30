class_name BeginnerGuide
extends Node
## Beginner Mode: contextual advice for the local hunter, each tip shown once
## when it becomes relevant — equipment, evidence, narrowing down suspects,
## preparing and performing the vanquishing, surviving hunts. It only watches
## (journal, suspect, equipment, HUD state) and never plays for you, so it works
## the same in a solo Run and on a multiplayer ClientRun.

var run
var _said := {}
var _t := 0.0
var _last_tool := ""
var _last_suspect := ""
var _evidence_seen := 0
var _was_hunting := false
var _wounds := 0
var _queue: Array = []        # [title, text, icon] waiting for the note to clear
var _gap := 0.0

func setup(p_run) -> void:
	run = p_run

func _once(key: String, title: String, text: String, icon: String = "icons/ui_quill.png", urgent: bool = false) -> void:
	if _said.has(key):
		return
	_said[key] = true
	if urgent:
		_queue.push_front([title, text, icon])
		_gap = 0.0
	else:
		_queue.append([title, text, icon])
	while _queue.size() > 3:
		_queue.remove_at(1)   # stale tips go; the most urgent and newest stay

func _process(delta: float) -> void:
	if run == null or run.player == null or run.hud == null or run.state != "playing":
		return
	_t += delta
	var p = run.player
	var eq = p.equipment
	var hud = run.hud
	# Shown one at a time, leaving each long enough to read.
	_gap -= delta
	if _gap <= 0.0 and not _queue.is_empty():
		var n: Array = _queue.pop_front()
		hud.show_guide(n[0], n[1], n[2])
		_gap = clampf(4.0 + str(n[1]).length() * 0.05, 6.0, 12.0)
	if p.dead:
		return
	if _t > 1.5:
		_once("start", "Your first investigation", "Something haunts this house. Find its evidence, work out what it is, then vanquish it. Your EQUIPMENT is top-left: press 1–9 or scroll to switch, and click to use it. F opens and shutters your lantern.", "icons/ui_house.png")
	# Each tool explained the first time it is held.
	var tool: String = eq.current()
	if tool != _last_tool and _t > 3.0:
		_last_tool = tool
		var e: Dictionary = Defs.EQUIPMENT.get(tool, {})
		if not e.is_empty():
			_once("tool_" + tool, e["name"], e.get("desc", ""), e["icon"])
	if eq.prompt != "" and _t > 3.0:
		_once("interact", "Interacting", "Doors, stairs and anything you can pick up show a small prompt beside them — press E or Space. Hold V to perform a rite when you are ready.", "icons/ui_quill.png")
	if _t > 40.0 and p.journal.active_entries().is_empty():
		_once("hunting_tips", "Where to look", "Ghosts send the Witch's Needle into a frenzy, freeze rooms, answer the Whisper Box, leave handprints under the Wraithlight Lantern, ghost writing and orbs. Flesh-and-blood creatures leave marks instead: bite marks, blood, fur, claws, footprints… Sweep the house with your lantern lit.", "icons/eq_emf.png")
	if run.is_harbinger():
		_once("harbinger", "The Harbinger", "Recklessness has called something worse. Earlier evidence no longer counts. Light the three sigil candles (E), then hold V beside it for the Final Rite. Don't let it catch you.", "tokens/harbinger.png", true)
		return
	# Evidence → which entities still fit.
	var found: Array = p.journal.active_entries().map(func(x): return x["id"])
	if found.size() != _evidence_seen:
		_evidence_seen = found.size()
		if found.size() == 1:
			_once("first_evidence", "Evidence recorded!", "It now glows in the EVIDENCE panel (top-right). Every entity leaves exactly three kinds of evidence — each one you find rules some out.", Defs.EVIDENCE[found[0]]["icon"], true)
		if found.size() >= 1:
			var j: Journal = p.journal
			var fits: Array = Defs.ORDINARY_CREATURES.filter(func(id): return found.all(func(ev): return ev in Defs.CREATURES[id]["evidence"]) and not Defs.CREATURES[id]["evidence"].any(func(ev): return j.state(ev) == "ruled_out"))
			var names: Array = fits.map(func(id): return Defs.creature_name(id))
			var text := ""
			if fits.is_empty():
				text = "Your evidence matches no single entity — something may be misleading you. Keep looking."
			elif fits.size() == 1:
				text = "Only %s matches what you have found. Press Tab until it is your SUSPECTED entity (bottom of the screen)." % names[0]
			else:
				text = "Still possible: %s. Press Tab to choose a suspect at any time — you can change your mind." % ", ".join(names)
			_once("fits_%d" % found.size(), "%d evidence found" % found.size(), text, Defs.EVIDENCE[found[-1]]["icon"])
	# Suspect chosen → how to vanquish it, and what is still missing.
	var sus: String = p.suspect
	if sus != _last_suspect:
		_last_suspect = sus
		if sus != "":
			var steps: Array = Defs.CREATURES[sus]["vanquish"]
			_once("how_" + sus, "Vanquishing %s" % Defs.creature_name(sus), " ".join(steps), Defs.CREATURES[sus]["token"], true)
	if sus != "":
		var need: Array = hud.REQUIREMENTS.get(sus, {}).get("items", [])
		var missing: Array = need.filter(func(it): return not it in eq.slots)
		if not missing.is_empty() and _t > 20.0:
			var it: String = missing[0]
			_once("need_%s_%s" % [sus, it], "You still need: %s" % Defs.EQUIPMENT[it]["name"], Defs.EQUIPMENT[it].get("desc", ""), Defs.EQUIPMENT[it]["icon"])
		elif missing.is_empty() and not need.is_empty():
			_once("ready_" + sus, "Ready to vanquish", "You carry everything %s needs. Follow the steps: %s" % [Defs.creature_name(sus), Defs.CREATURES[sus]["vanquish"][-1]], "icons/ui_trophy.png", true)
	# Danger.
	var hunting: bool = hud._hunting
	if hunting and not _was_hunting:
		_once("first_hunt", "It is hunting!", "Get out of its sight — put walls, doors and distance between you. Holy Water (9) stuns a ghost; crucifixes placed beforehand stop ghost hunts from starting. Hunts are shorter and slower in Beginner Mode.", "icons/ui_skull.png", true)
	_was_hunting = hunting
	if p.wounds > _wounds:
		_wounds = p.wounds
		_once("wounded", "You are wounded", "A second hit and you perish. Keep away from it during hunts until your vanquishing is ready.", "icons/ui_heart_wounded.png", true)
