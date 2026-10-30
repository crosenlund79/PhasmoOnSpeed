class_name EquipmentMirror
extends RefCounted
## Client-side stand-in for EquipmentController: holds the host's latest view of
## this hunter's equipment so the HUD can draw it. It decides nothing.

signal changed()

var slots: Array = Defs.BASE_LOADOUT.duplicate()
var selected := 0
var reading := ""
var reading_color := Color(0.93, 0.88, 0.76, 0.55)
var reading_active := false
var hint := ""
var prompt := ""
var _hold := 0.0
var interact_pos := Vector2.INF
var interact_icon := ""
var near_items: Array = []
var needle := 0.0
var _charges: Array = []

func apply(d: Dictionary) -> void:
	reading = d["reading"]
	reading_color = Color.html(d["rc"])
	reading_active = d["ra"]
	hint = d["hint"]
	prompt = d["prompt"]
	_hold = float(d["hold"])
	var ip: Array = d.get("ip", [])
	interact_pos = Vector2(ip[0], ip[1]) if ip.size() == 2 else Vector2.INF
	near_items = d.get("near", []).map(func(a): return Vector2(a[0], a[1]))
	needle = float(d.get("nd", 0.0))
	interact_icon = str(d.get("pi", ""))
	var new_slots: Array = d["slots"]
	var new_charges: Array = d["charges"]
	if new_slots != slots or int(d["sel"]) != selected or new_charges != _charges:
		slots = new_slots
		selected = int(d["sel"])
		_charges = new_charges
		changed.emit()

func current() -> String:
	return slots[selected] if selected >= 0 and selected < slots.size() else ""

func hold_progress() -> float:
	return _hold

func charge_text(id: String) -> String:
	var i := slots.find(id)
	return str(_charges[i]) if i >= 0 and i < _charges.size() else ""
