class_name Journal
extends RefCounted
## Automatic evidence journal model. Records the FIRST genuine discovery of each
## evidence type (time + room where it occurred). Every occurrence is also kept
## for analytics/replay. Never identifies the creature.

signal discovered(entry: Dictionary)
signal voided()

var entries: Array = []        # [{id, name, icon, time, room_id, room_name, void}]
var occurrences: Array = []    # every genuine occurrence, including repeats
var _known := {}               # evidence id -> entry (non-void entries only)
## The player's own deductions: evidence they believe is NOT present. Never
## authoritative, never scored, and overridden the moment the evidence is found.
var ruled_out := {}

func has(id: String) -> bool:
	return _known.has(id)

## Returns true if this was a new journal entry.
func record(id: String, time: float, room_id: String, room_name: String) -> bool:
	occurrences.append({"id": id, "time": time, "room_id": room_id, "room_name": room_name})
	if _known.has(id):
		return false
	ruled_out.erase(id)   # found after all: the deduction was wrong
	var def: Dictionary = Defs.EVIDENCE.get(id, {})
	var e := {"id": id, "name": def.get("name", id), "icon": def.get("icon", ""), "time": time,
		"room_id": room_id, "room_name": room_name, "void": false}
	entries.append(e)
	_known[id] = e
	discovered.emit(e)
	return true

## Active (non-void) entries in discovery order.
func active_entries() -> Array:
	return entries.filter(func(e): return not e["void"])

func void_entries() -> Array:
	return entries.filter(func(e): return e["void"])

## Conventional evidence not yet discovered.
func undiscovered_conventional() -> Array:
	var out: Array = []
	for id in Defs.CONVENTIONAL_EVIDENCE:
		if not _known.has(id):
			out.append(id)
	return out

## "unknown", "found" or "ruled_out".
func state(id: String) -> String:
	if _known.has(id):
		return "found"
	return "ruled_out" if ruled_out.has(id) else "unknown"

## Marks / unmarks undiscovered evidence as ruled out. Found evidence can't be.
func toggle_ruled_out(id: String) -> bool:
	if _known.has(id) or not Defs.EVIDENCE.has(id):
		return false
	if ruled_out.has(id):
		ruled_out.erase(id)
	else:
		ruled_out[id] = true
	return true

## Harbinger replacement: previous evidence no longer counts for the new encounter.
func void_all() -> void:
	ruled_out.clear()
	for e in entries:
		e["void"] = true
	_known.clear()
	voided.emit()

static func format_time(t: float) -> String:
	var total := int(floor(t))
	return "%02d:%02d" % [total / 60, total % 60]

static func format_time_precise(t: float) -> String:
	var total := int(floor(t))
	var cs := int(floor((t - total) * 100.0))
	return "%02d:%02d.%02d" % [total / 60, total % 60, cs]
