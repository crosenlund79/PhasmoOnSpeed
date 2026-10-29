extends Node
## Competitive multiplayer transport (Godot high-level multiplayer over ENet).
##
## Authority model: the HOST runs the only simulation (Run): entity choice and
## AI, evidence, shared world changes, damage, shoves, vanquishing and scoring.
## CLIENTS send their own hunter's movement and button state; they render the
## world from host snapshots and events (ClientRun) and never decide outcomes.
## Every RPC lives on this autoload, so node paths match on all peers.

signal lobby_changed()
signal status_changed(text: String)
signal connection_lost(reason: String)

const DEFAULT_PORT := 24680
const MAX_PLAYERS := 4
const PROTOCOL := "spectral-run-mp-1"
const REPLAY_CHUNK := 48000
## World events every hunter may see/hear. Everything else (evidence, attempts,
## suspects, the entity's true type) stays on the host and in the replay.
const PUBLIC_EVENTS := ["decal", "decal_remove", "decal_swap", "flicker", "darkness", "sfx", "screen_shake", "shake",
	"mirror", "say", "npc", "npc_flee", "npc_gone", "hunt_start", "hunt_end", "harbinger", "bound", "sigil",
	"sigil_spawn", "death", "attack", "vanquish", "shove", "left", "floor", "orb", "orb_clear", "creature_meta"]

var peer: ENetMultiplayerPeer
var lobby := {}               # peer_id -> {name, ready}
var house := "ashgrove"
var in_match := false
var host_run: Node = null
var client_run: Node = null
var status := ""
var _replay_parts := {}
var _pending_results := {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _fail("Could not connect to the host."))
	multiplayer.server_disconnected.connect(func(): _lost("The host closed the game."))

func is_online() -> bool:
	return peer != null and multiplayer.multiplayer_peer == peer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func is_host() -> bool:
	return is_online() and multiplayer.is_server()

func my_peer_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1

func _set_status(t: String) -> void:
	status = t
	status_changed.emit(t)

# --- Session -------------------------------------------------------------------------

func host(port: int, display_name: String) -> Error:
	leave()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		peer = null
		_set_status("Could not open port %d (%s). Is it already in use?" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	lobby = {1: {"name": _clean(display_name), "ready": false}}
	_set_status("Hosting on port %d. Waiting for rivals…" % port)
	lobby_changed.emit()
	return OK

func join(address: String, port: int, display_name: String) -> Error:
	leave()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), port)
	if err != OK:
		peer = null
		_set_status("Could not start connecting (%s)." % error_string(err))
		return err
	multiplayer.multiplayer_peer = peer
	set_meta("join_name", _clean(display_name))
	_set_status("Connecting to %s:%d…" % [address, port])
	return OK

func leave() -> void:
	if peer:
		peer.close()
	peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	lobby = {}
	in_match = false
	host_run = null
	client_run = null
	_replay_parts.clear()

func _clean(n: String) -> String:
	n = n.strip_edges().substr(0, 20)
	return n if n != "" else "Investigator"

func _fail(reason: String) -> void:
	_set_status(reason)
	leave()
	connection_lost.emit(reason)

func _lost(reason: String) -> void:
	var was_in_match := in_match
	leave()
	_set_status(reason)
	connection_lost.emit(reason)
	if was_in_match:
		Game.goto_lobby(reason)

func _on_connected() -> void:
	_set_status("Connected. Introducing yourself…")
	c_hello.rpc_id(1, get_meta("join_name", "Investigator"), PROTOCOL)

func _on_peer_connected(_id: int) -> void:
	pass   # the client introduces itself with c_hello

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var who: String = lobby.get(id, {}).get("name", "A rival")
	lobby.erase(id)
	if in_match and host_run:
		host_run.on_peer_left(id)
	_set_status("%s left." % who)
	_broadcast_lobby()

# --- Lobby -----------------------------------------------------------------------------

@rpc("any_peer", "reliable")
func c_hello(display_name: String, protocol: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		s_rejected.rpc_id(id, "Version mismatch: the host runs a different build.")
		return
	if in_match:
		s_rejected.rpc_id(id, "A match is already in progress.")
		return
	if lobby.size() >= MAX_PLAYERS:
		s_rejected.rpc_id(id, "The lobby is full (4 hunters).")
		return
	var name := _clean(display_name)
	var taken := lobby.values().map(func(p): return p["name"])
	var base := name
	var n := 2
	while name in taken:
		name = "%s %d" % [base, n]
		n += 1
	lobby[id] = {"name": name, "ready": false}
	_set_status("%s joined." % name)
	_broadcast_lobby()

@rpc("authority", "reliable")
func s_rejected(reason: String) -> void:
	_fail(reason)

@rpc("authority", "reliable")
func s_lobby(data: Dictionary, house_id: String) -> void:
	lobby = {}
	for k in data:
		lobby[int(k)] = data[k]
	house = house_id
	if status.begins_with("Connect"):
		_set_status("In the lobby. Ready up when you are.")
	lobby_changed.emit()

func _broadcast_lobby() -> void:
	if multiplayer.is_server():
		s_lobby.rpc(lobby, house)
		lobby_changed.emit()

func set_ready(r: bool) -> void:
	if multiplayer.is_server():
		_apply_ready(1, r)
	else:
		c_ready.rpc_id(1, r)

@rpc("any_peer", "reliable")
func c_ready(r: bool) -> void:
	if multiplayer.is_server():
		_apply_ready(multiplayer.get_remote_sender_id(), r)

func _apply_ready(id: int, r: bool) -> void:
	if lobby.has(id):
		lobby[id]["ready"] = r
		_broadcast_lobby()

func set_house(house_id: String) -> void:
	if multiplayer.is_server():
		house = house_id
		_broadcast_lobby()

func can_start() -> bool:
	if not is_host() or lobby.size() < 2:
		return false
	for id in lobby:
		if not lobby[id]["ready"]:
			return false
	return true

func roster() -> Array:
	var ids := lobby.keys()
	ids.sort()
	return ids.map(func(id): return {"peer_id": id, "name": lobby[id]["name"]})

## Host: start the match for everyone. creature_override is for tests only.
func start_match(creature_override: String = "", run_seed: int = -1) -> void:
	if not is_host():
		return
	in_match = true
	var seed_value := run_seed if run_seed >= 0 else int(Time.get_unix_time_from_system() * 1000.0) % 2147483647
	var r := roster()
	s_start.rpc(house, seed_value, r)
	host_run = Game.start_match_host(house, seed_value, creature_override, r)

@rpc("authority", "reliable")
func s_start(house_id: String, seed_value: int, r: Array) -> void:
	in_match = true
	client_run = Game.start_match_client(house_id, seed_value, r, my_peer_id())

# --- Match: client → host ----------------------------------------------------------------

func client_send_input(pos: Vector2, aim: float, flags: int, mask: int, counters: PackedByteArray) -> void:
	if is_online() and not multiplayer.is_server():
		c_input.rpc_id(1, pos, aim, flags, mask, counters)

@rpc("any_peer", "unreliable_ordered")
func c_input(pos: Vector2, aim: float, flags: int, mask: int, counters: PackedByteArray) -> void:
	if multiplayer.is_server() and host_run and in_match:
		host_run.apply_remote_input(multiplayer.get_remote_sender_id(), pos, aim, flags, mask, counters)

# --- Match: host → clients ----------------------------------------------------------------

func host_world_event(type: String, payload: Dictionary) -> void:
	if is_host() and in_match and type in PUBLIC_EVENTS:
		s_event.rpc(type, payload)

func host_private(peer_id: int, kind: String, data: Dictionary) -> void:
	if is_host() and in_match and peer_id != 1 and lobby.has(peer_id):
		s_private.rpc_id(peer_id, kind, data)

func host_snapshot(t: float, threat: float, actors: Dictionary, sigils_lit: int, harbinger: bool, hunting: bool) -> void:
	if not is_host() or not in_match:
		return
	var packed: Array = []
	for id in actors:
		var a: Array = actors[id]
		var pos: Vector2 = a[0]
		packed.append([id, snappedf(pos.x, 0.1), snappedf(pos.y, 0.1), snappedf(a[1], 0.01), snappedf(a[2], 0.01), a[3], a[4]])
	s_snapshot.rpc(t, threat, packed, sigils_lit, harbinger, hunting)

func host_hud_state(peer_id: int, data: Dictionary) -> void:
	if is_host() and in_match and lobby.has(peer_id):
		s_hud.rpc_id(peer_id, data)

@rpc("authority", "unreliable_ordered")
func s_snapshot(t: float, threat: float, actors: Array, sigils_lit: int, harbinger: bool, hunting: bool) -> void:
	if client_run:
		client_run.apply_snapshot(t, threat, actors, sigils_lit, harbinger, hunting)

@rpc("authority", "reliable")
func s_event(type: String, payload: Dictionary) -> void:
	if client_run:
		client_run.apply_event(type, payload)

@rpc("authority", "reliable")
func s_private(kind: String, data: Dictionary) -> void:
	if client_run:
		client_run.apply_private(kind, data)

@rpc("authority", "unreliable_ordered")
func s_hud(data: Dictionary) -> void:
	if client_run:
		client_run.apply_hud(data)

# --- Results -------------------------------------------------------------------------------

## Host: send final results and the (compressed, chunked) replay to every client.
func host_send_results(results: Dictionary, replay: Dictionary) -> void:
	if not is_host():
		return
	var raw := JSON.stringify(replay).to_utf8_buffer()
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var total := int(ceil(float(packed.size()) / REPLAY_CHUNK))
	s_results.rpc(results, raw.size(), total)
	for i in total:
		s_replay_chunk.rpc(i, packed.slice(i * REPLAY_CHUNK, mini((i + 1) * REPLAY_CHUNK, packed.size())))
	in_match = false
	host_run = null
	for id in lobby:
		lobby[id]["ready"] = false

@rpc("authority", "reliable")
func s_results(results: Dictionary, raw_size: int, total: int) -> void:
	_pending_results = {"results": results, "raw": raw_size, "total": total}
	_replay_parts.clear()
	in_match = false
	if total == 0:
		_deliver_results(PackedByteArray())

@rpc("authority", "reliable")
func s_replay_chunk(i: int, bytes: PackedByteArray) -> void:
	_replay_parts[i] = bytes
	if _pending_results.is_empty() or _replay_parts.size() < int(_pending_results["total"]):
		return
	var packed := PackedByteArray()
	for k in int(_pending_results["total"]):
		packed.append_array(_replay_parts[k])
	_deliver_results(packed)

func _deliver_results(packed: PackedByteArray) -> void:
	var replay := {}
	if packed.size() > 0:
		var raw := packed.decompress(int(_pending_results["raw"]), FileAccess.COMPRESSION_ZSTD)
		var parsed = JSON.parse_string(raw.get_string_from_utf8())
		if typeof(parsed) == TYPE_DICTIONARY:
			replay = parsed
	var results: Dictionary = _pending_results["results"]
	_pending_results = {}
	_replay_parts.clear()
	client_run = null
	for id in lobby:
		lobby[id]["ready"] = false
	Game.show_match_results(results, replay)
