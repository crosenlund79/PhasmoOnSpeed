extends Node
## Multiplayer integration test with REAL separate processes over ENet.
## Run tests/net_test.sh, which starts one host and N clients:
##   godot --headless --path . res://tests/net_test.tscn -- host <clients> <port> [scenario]
##   godot --headless --path . res://tests/net_test.tscn -- client <index> <port> [scenario]
## Scenarios: "full" (join, sync, shove, death/spectate, client vanquish, results,
## replay) and "drop" (a client disconnects mid-match, then the host shuts down).

var role := ""
var index := 0
var clients := 1
var port := 24690
var scenario := "full"
var failures: Array = []

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	role = a[0]
	if role == "host":
		clients = int(a[1])
	else:
		index = int(a[1])
	port = int(a[2])
	scenario = a[3] if a.size() > 3 else "full"
	SaveData.save_path = "user://net_test_%s_%d.json" % [role, index]
	SaveData.reset_all()
	get_tree().create_timer(90.0).timeout.connect(func():
		_say("TIMEOUT")
		get_tree().quit(2))
	await get_tree().process_frame
	if role == "host":
		await _host()
	else:
		await _client()

func _say(t: String) -> void:
	print("[%s%s] %s" % [role, "" if role == "host" else str(index), t])

func check(c: bool, msg: String) -> void:
	if not c:
		failures.append(msg)
		_say("CHECK FAILED: " + msg)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while not cond.call() and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
	return cond.call()

func _done() -> void:
	_say("RESULT " + ("OK" if failures.is_empty() else "FAIL %s" % str(failures)))
	get_tree().quit(0 if failures.is_empty() else 1)

# --- Host ----------------------------------------------------------------------------------

func _host() -> void:
	check(Net.host(port, "Host") == OK, "host could open the port")
	var all_in := await _until(func(): return Net.lobby.size() == clients + 1, 20.0)
	check(all_in, "all %d clients joined (lobby %d)" % [clients, Net.lobby.size()])
	Net.set_ready(true)
	await _until(func(): return Net.can_start(), 10.0)
	check(Net.can_start(), "everyone ready")
	Net.start_match("werewolf", 777)
	await _wait(0.5)
	var run: Run = Net.host_run
	check(run != null and run.hunters.size() == clients + 1, "host run has every hunter")
	var spawn := HouseMap.cell_center(run.map.spawn_cell)
	await _wait(3.0)
	for h in run.hunters:
		if h.remote:
			check(h.global_position.distance_to(spawn) > 60.0, "%s moved on the host (%s)" % [h.display_name, h.global_position])
	if scenario == "drop":
		await _until(func(): return run.hunters.any(func(h): return h.get_meta("disconnected", false)), 15.0)
		check(run.hunters.any(func(h): return h.get_meta("disconnected", false)), "host noticed the dropped client")
		check(run.state == "playing", "match continues after a disconnect")
		await _wait(1.0)
		_say("shutting down host")
		Net.leave()
		await _wait(1.0)
		_done()
		return
	# Private journals: the host's own discovery never reaches rivals.
	run.discover(run.player, "fur", run.player.room_id)
	check(run.player.journal.has("fur"), "host recorded its own evidence")
	# Shove: stand beside client 1 and push it.
	# Hunters are ordered by (random) peer id: find them by name.
	var by_name := func(n: String) -> Player: return run.hunters.filter(func(h): return h.display_name == n)[0]
	var c1: Player = by_name.call("Client1")
	var c1_before := c1.global_position
	run.player.global_position = c1.global_position + Vector2(-30, 0)
	run.player.aim_angle = 0.0
	run.shove(run.player)
	check(run.player.shove_cd > 4.0, "shove landed and started the cooldown")
	await _wait(0.8)
	check(c1.global_position.distance_to(c1_before) > 40.0, "shoved client was knocked back (%.0f px)" % c1.global_position.distance_to(c1_before))
	run.shove(run.player)
	check(c1.shoves_taken == 1, "cooldown prevents an immediate second shove")
	# Death + spectating for the last client.
	if clients >= 2:
		var victim: Player = by_name.call("Client%d" % clients)
		run.creature.begin_hunt(run.creature.position, false)
		run.on_creature_contact(run.creature, victim)
		victim.invuln = 0.0
		run.creature.begin_hunt(run.creature.position, false)
		run.on_creature_contact(run.creature, victim)
		check(victim.dead, "two hits killed a remote hunter")
		check(run.state == "playing", "one death does not end the match")
		await _wait(1.0)
	# Client 1 vanquishes: give it a silver stake and park the werewolf in front of it.
	c1.add_resource("silver_stake")
	c1.equipment.rebuild_slots()
	run.creature.set_process(false)
	await _wait(0.6)
	run.creature.position = c1.global_position + Vector2(35, 0)
	_say("waiting for client 1 to strike")
	await _until(func(): return run.vanquisher != null, 15.0)
	check(run.vanquisher == c1, "client 1 performed the vanquishing through its own input")
	if run.vanquisher != c1:
		_say("DBG c1 current=%s pos=%s creature=%s events=%s" % [c1.equipment.current(), c1.global_position, run.creature.position,
			str(run.recorder.data["events"].filter(func(e): return e[2].get("actor", "") == c1.actor_id).map(func(e): return [e[1], e[2]]).slice(-8))])
	await _until(func(): return get_tree().current_scene != null and get_tree().current_scene.get_script() == preload("res://scripts/ui/match_results.gd"), 10.0)
	var res: Dictionary = Game.last_result.get("match", {})
	check(res.get("outcome", "") == "vanquished", "match outcome vanquished")
	check(res.get("rows", []).size() == clients + 1, "a result row per hunter")
	var host_row: Dictionary = res["rows"].filter(func(r): return r["peer_id"] == 1)[0] if res.has("rows") else {}
	check(host_row.get("true_evidence", 0) == 1, "host scored its private evidence")
	check(SaveData.data["mp"]["matches"] == 1 and SaveData.data["history"].is_empty(), "match recorded in competitive stats only")
	await _wait(2.0)
	_done()

# --- Client --------------------------------------------------------------------------------

func _client() -> void:
	await _wait(0.5 + index * 0.3)
	check(Net.join("127.0.0.1", port, "Client%d" % index) == OK, "client could start connecting")
	var joined := await _until(func(): return Net.lobby.has(Net.my_peer_id()), 15.0)
	check(joined, "joined the lobby")
	Net.set_ready(true)
	var started := await _until(func(): return Net.client_run != null, 25.0)
	check(started, "received the match start")
	if not started:
		_done()
		return
	var cr: ClientRun = Net.client_run
	await _wait(0.5)
	# Walk away from the spawn (different directions per client).
	var dirs := ["move_right", "move_left", "move_right"]
	var act: String = dirs[(index - 1) % dirs.size()]
	await get_tree().process_frame
	Input.action_press(act)
	await _wait(1.2)
	Input.action_release(act)
	check(cr.player.global_position.distance_to(HouseMap.cell_center(cr.map.spawn_cell)) > 60.0, "local hunter moved")
	await _wait(1.0)
	check(cr._actors.size() >= 3, "puppets for rivals / entity / occupants exist (%d)" % cr._actors.size())
	if scenario == "drop":
		if index == 2:
			_say("dropping out")
			Net.leave()
			await _wait(0.5)
			_done()
			return
		var lost := [false]
		Net.connection_lost.connect(func(_r): lost[0] = true)
		await _until(func(): return lost[0], 30.0)
		check(lost[0], "client noticed the host shutting down")
		await _wait(0.5)
		check(get_tree().current_scene.get_script() == preload("res://scripts/ui/lobby.gd"), "client returned to the lobby screen")
		_done()
		return
	check(not cr.player.journal.has("fur"), "rival's evidence did not leak into this journal")
	if index == 1:
		var got_stake := await _until(func(): return "silver_stake" in cr.player.equipment.slots, 20.0)
		check(got_stake, "hotbar mirrored the granted silver stake")
		cr.player.aim_override = 0.0
		var slot: int = cr.player.equipment.slots.find("silver_stake")
		if slot >= 0 and slot < 9:
			Input.action_press("slot_%d" % (slot + 1))
			await get_tree().process_frame
			await get_tree().process_frame
			Input.action_release("slot_%d" % (slot + 1))
		else:
			Input.action_press("cycle")
			await get_tree().process_frame
			await get_tree().process_frame
			Input.action_release("cycle")
		await _wait(1.2)
		for i in 4:
			# Press on a frame boundary: timer callbacks run after input polling.
			await get_tree().process_frame
			Input.action_press("use")
			await get_tree().process_frame
			await get_tree().process_frame
			Input.action_release("use")
			await _wait(1.0)
	var got := await _until(func(): return not Game.last_result.get("match", {}).is_empty(), 30.0)
	check(got, "received the match results")
	if got:
		var res: Dictionary = Game.last_result["match"]
		check(res["rows"].size() >= 2, "results list every hunter")
		check(Game.last_result["me"] != "", "found my own row")
		check(not Game.last_result["replay"].is_empty(), "received the replay")
		var tracks: Dictionary = Game.last_result["replay"].get("tracks", {})
		check(tracks.keys().filter(func(k): return k.begins_with("player_")).size() == res["rows"].size(), "replay has every hunter's track")
		var shove_events: Array = Game.last_result["replay"].get("events", []).filter(func(e): return e[1] == "shove")
		check(shove_events.size() >= 1, "replay recorded the shove")
	_done()
