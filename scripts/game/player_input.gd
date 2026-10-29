class_name PlayerInput
extends RefCounted
## Per-hunter action state. Equipment logic reads this instead of the global
## Input singleton, so the host can drive remote hunters from network packets
## exactly like the local one.

const ACTIONS := ["use", "interact", "rite", "suspect", "suspect_prev", "cycle", "cycle_next", "cycle_prev",
	"flashlight", "restart", "shove", "slot_1", "slot_2", "slot_3", "slot_4", "slot_5", "slot_6", "slot_7", "slot_8", "slot_9"]

var held := {}
var just := {}
var move := Vector2.ZERO
var sprint := false
var aim := 0.0
## Remote input: cumulative press counters (mod 256) so a lost packet never
## swallows a tap.
var _counters := PackedByteArray()
var _seen := PackedByteArray()

func _init() -> void:
	_counters.resize(ACTIONS.size())
	_seen.resize(ACTIONS.size())

func pressed(a: String) -> bool:
	return held.get(a, false)

func just_pressed(a: String) -> bool:
	return just.get(a, false)

## Local hunter: sample the keyboard/mouse.
func poll_local(enabled: bool) -> void:
	just.clear()
	for a in ACTIONS:
		var on := enabled and Input.is_action_pressed(a)
		if enabled and Input.is_action_just_pressed(a):
			just[a] = true
			_counters[ACTIONS.find(a)] = (_counters[ACTIONS.find(a)] + 1) % 256
		held[a] = on
	# Shift+Tab cycles suspects backwards.
	if just.has("suspect") and Input.is_key_pressed(KEY_SHIFT):
		just.erase("suspect")
		var si := ACTIONS.find("suspect")
		_counters[si] = (_counters[si] + 255) % 256
		just["suspect_prev"] = true
		var i := ACTIONS.find("suspect_prev")
		_counters[i] = (_counters[i] + 1) % 256
	move = Input.get_vector("move_left", "move_right", "move_up", "move_down") if enabled else Vector2.ZERO
	sprint = enabled and Input.is_action_pressed("sprint")

func held_mask() -> int:
	var m := 0
	for i in ACTIONS.size():
		if held.get(ACTIONS[i], false):
			m |= 1 << i
	return m

func counters() -> PackedByteArray:
	return _counters

## Remote hunter: apply a packet from the owning client.
func apply_remote(mask: int, counters_in: PackedByteArray) -> void:
	for i in ACTIONS.size():
		held[ACTIONS[i]] = (mask >> i) & 1 == 1
		if i < counters_in.size() and counters_in[i] != _seen[i]:
			just[ACTIONS[i]] = true
			_seen[i] = counters_in[i]

## Called by the host after a frame's actions have been consumed.
func consume() -> void:
	just.clear()
