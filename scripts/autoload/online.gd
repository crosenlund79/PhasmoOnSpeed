extends Node
## Optional global leaderboard client. The game is fully playable offline; this
## only activates when a server URL is configured in user://online.cfg:
##
##   [leaderboard]
##   url="https://your-host.example/api"
##
## The client holds NO privileged credentials. The server (see
## server/leaderboard_server.py and docs/LEADERBOARD.md) recomputes every score
## from the submitted run facts using the versioned rules and rejects mismatches.

signal top_received(rows: Array, ok: bool, message: String)
signal submit_finished(ok: bool, message: String)

const CONFIG_PATH := "user://online.cfg"

var base_url := ""
var install_id := ""
var last_status := "Global leaderboard not configured — offline rankings only."

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		base_url = str(cfg.get_value("leaderboard", "url", "")).rstrip("/")
		install_id = str(cfg.get_value("leaderboard", "install_id", ""))
	if install_id == "":
		install_id = "%016x" % (randi() << 31 ^ randi())
		cfg.set_value("leaderboard", "url", base_url)
		cfg.set_value("leaderboard", "install_id", install_id)
		cfg.save(CONFIG_PATH)
	if is_configured():
		last_status = "Global leaderboard: " + base_url

func is_configured() -> bool:
	return base_url.begins_with("http")

func submit(summary: Dictionary, display_name: String) -> void:
	if not is_configured() or not summary.get("vanquished", false):
		return
	var body := {
		"name": display_name.substr(0, 24), "install_id": install_id,
		"rules_version": summary["rules_version"], "game_version": ProjectSettings.get_setting("application/config/version"),
		"house": summary["house"], "creature": summary["creature"], "time": summary["time"],
		"true_evidence": summary["true_evidence"], "incorrect_attempts": summary["incorrect_attempts"],
		"incomplete_attempts": summary["incomplete_attempts"], "wounds": summary["wounds"],
		"clean_hunts_survived": summary["clean_hunts_survived"], "blind": summary["blind"],
		"vanquished": true, "claimed_score": summary["score"], "seed": summary["seed"],
		"event_digest": summary.get("event_digest", ""),
	}
	var req := HTTPRequest.new()
	req.timeout = 8.0
	add_child(req)
	req.request_completed.connect(func(result, code, _h, bytes):
		req.queue_free()
		var ok: bool = result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
		var msg := "Submitted to the global leaderboard." if ok else "Global submission failed (%d)." % code
		if ok:
			var parsed = JSON.parse_string(bytes.get_string_from_utf8())
			if typeof(parsed) == TYPE_DICTIONARY and parsed.has("rank"):
				msg = "Global rank #%d (verified by server)." % int(parsed["rank"])
		last_status = msg
		submit_finished.emit(ok, msg))
	var err := req.request(base_url + "/v1/scores", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		req.queue_free()
		submit_finished.emit(false, "Could not reach the global leaderboard.")

func fetch_top(limit: int = 20) -> void:
	if not is_configured():
		top_received.emit([], false, last_status)
		return
	var req := HTTPRequest.new()
	req.timeout = 8.0
	add_child(req)
	req.request_completed.connect(func(result, code, _h, bytes):
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			top_received.emit([], false, "Global leaderboard unreachable.")
			return
		var parsed = JSON.parse_string(bytes.get_string_from_utf8())
		if typeof(parsed) == TYPE_DICTIONARY and parsed.has("scores"):
			top_received.emit(parsed["scores"], true, "Global leaderboard (server-verified scores).")
		else:
			top_received.emit([], false, "Global leaderboard returned unexpected data."))
	if req.request(base_url + "/v1/scores?limit=%d" % limit) != OK:
		req.queue_free()
		top_received.emit([], false, "Global leaderboard unreachable.")
