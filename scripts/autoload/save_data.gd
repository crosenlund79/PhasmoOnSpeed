extends Node
## Local persistence: settings, personal bests, per-house/per-creature analytics
## and recent run history. Statistics are only ever READ by the stats screens —
## they never influence difficulty or creature selection.

const SAVE_VERSION := 1
const HISTORY_LIMIT := 60

var save_path := "user://spectral_run_save.json"
var replay_path := "user://last_replay.json"
var data := {}

func _ready() -> void:
	load_data()
	Sfx.apply_volumes(settings().get("master", 0.8), settings().get("music", 0.6))

func _defaults() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"settings": {"master": 0.8, "music": 0.6, "ui_scale": 1.0, "fullscreen": false,
			"player_name": "Investigator", "dev_mode": true,
			"equip_hud": true, "equip_hud_opacity": 0.9, "equip_hud_size": 18,
			"ev_notify": true, "ev_notify_opacity": 0.95, "ev_notify_size": 1.0,
			"npc_names": true, "last_address": "127.0.0.1", "last_port": 24680},
		"records": {"best_score": 0, "best_score_time": 0.0, "best_score_house": "", "houses": {}},
		"stats": {},
		"history": [],
		"runs_started": 0,
		# Competitive multiplayer is kept completely separate from solo records.
		"mp": {"matches": 0, "wins": 0, "best_score": 0, "vanquishes": 0, "deaths": 0, "shoves_given": 0,
			"shoves_taken": 0, "history": []},
	}

func load_data() -> void:
	data = _defaults()
	if not FileAccess.file_exists(save_path):
		return
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file unreadable; starting fresh.")
		return
	for k in parsed:
		data[k] = parsed[k]
	# Older saves gain any new keys without losing existing records.
	for k in _defaults()["settings"]:
		if not data["settings"].has(k):
			data["settings"][k] = _defaults()["settings"][k]
	if not data.has("mp"):
		data["mp"] = _defaults()["mp"]

func save() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, " "))

func reset_all() -> void:
	data = _defaults()
	save()

func settings() -> Dictionary:
	return data["settings"]

func set_setting(key: String, value) -> void:
	data["settings"][key] = value
	save()

func house_record(house_id: String) -> Dictionary:
	var houses: Dictionary = data["records"]["houses"]
	if not houses.has(house_id):
		houses[house_id] = {"best_time": 0.0, "best_score": 0, "wins": 0, "runs": 0}
	return houses[house_id]

func note_run_started() -> void:
	data["runs_started"] = int(data.get("runs_started", 0)) + 1

## Records a finished run exactly once. Returns {new_best_time, new_best_score, prev_best_time, prev_best_score}.
func record_run(summary: Dictionary) -> Dictionary:
	var house_id: String = summary["house"]
	var rec := house_record(house_id)
	var out := {"new_best_time": false, "new_best_score": false,
		"prev_best_time": rec["best_time"], "prev_best_score": rec["best_score"],
		"prev_overall_best": data["records"]["best_score"]}
	rec["runs"] = int(rec["runs"]) + 1
	if summary["vanquished"]:
		rec["wins"] = int(rec["wins"]) + 1
		if rec["best_time"] <= 0.0 or summary["time"] < rec["best_time"]:
			rec["best_time"] = summary["time"]
			out["new_best_time"] = true
		if summary["score"] > int(rec["best_score"]):
			rec["best_score"] = summary["score"]
			out["new_best_score"] = true
		if summary["score"] > int(data["records"]["best_score"]):
			data["records"]["best_score"] = summary["score"]
			data["records"]["best_score_time"] = summary["time"]
			data["records"]["best_score_house"] = summary.get("house_name", house_id)
	_update_stats(summary)
	var hist: Array = data["history"]
	hist.append(_history_row(summary))
	while hist.size() > HISTORY_LIMIT:
		hist.pop_front()
	save()
	return out

func _history_row(s: Dictionary) -> Dictionary:
	return {"house": s["house"], "creature": s["original_creature"], "final": s["creature"], "won": s["vanquished"],
		"time": snappedf(s["time"], 0.01), "score": s["score"], "evidence": s["evidence_ids"].size(),
		"wrong": s["incorrect_attempts"], "wounds": s["wounds"], "harbinger": s["harbinger"],
		"rules": s["rules_version"], "date": Time.get_datetime_string_from_system()}

func _update_stats(s: Dictionary) -> void:
	var stats: Dictionary = data["stats"]
	var h: String = s["house"]
	if not stats.has(h):
		stats[h] = {}
	var c: String = s["original_creature"]
	if not stats[h].has(c):
		stats[h][c] = {"runs": 0, "wins": 0, "losses": 0, "total_win_time": 0.0, "best_time": 0.0,
			"evidence_found": 0, "evidence_rooms": {}, "correct_ids": 0, "incorrect_ids": 0,
			"blind_wins": 0, "wounds": 0, "transformations": 0, "harbinger": 0, "best_score": 0,
			"evidence_times": {}}
	var st: Dictionary = stats[h][c]
	st["runs"] += 1
	if s["vanquished"]:
		st["wins"] += 1
		st["total_win_time"] += s["time"]
		if st["best_time"] <= 0.0 or s["time"] < st["best_time"]:
			st["best_time"] = s["time"]
		st["best_score"] = maxi(int(st["best_score"]), int(s["score"]))
		st["correct_ids"] += 1
		if s["blind"]:
			st["blind_wins"] += 1
	else:
		st["losses"] += 1
	st["incorrect_ids"] += int(s["incorrect_attempts"])
	st["wounds"] += int(s["wounds"])
	st["transformations"] += int(s["transformations"])
	if s["harbinger"]:
		st["harbinger"] += 1
	for e in s["evidence"]:
		st["evidence_found"] += 1
		var key: String = "%s @ %s" % [Defs.evidence_name(e["id"]), e["room_name"]]
		st["evidence_rooms"][key] = int(st["evidence_rooms"].get(key, 0)) + 1
		var times: Dictionary = st["evidence_times"]
		if not times.has(e["id"]):
			times[e["id"]] = [0, 0.0]
		times[e["id"]][0] += 1
		times[e["id"]][1] += float(e["time"])

## Records one finished competitive match for the local hunter (never touches solo records).
func record_match(results: Dictionary, my_actor: String) -> Dictionary:
	var mp: Dictionary = data["mp"]
	var me := {}
	for r in results.get("rows", []):
		if r["actor"] == my_actor:
			me = r
	var out := {"new_best": false, "prev_best": int(mp["best_score"])}
	if me.is_empty():
		return out
	mp["matches"] = int(mp["matches"]) + 1
	if int(me["rank"]) == 1:
		mp["wins"] = int(mp["wins"]) + 1
	if me["vanquisher"]:
		mp["vanquishes"] = int(mp["vanquishes"]) + 1
	if not me["alive"]:
		mp["deaths"] = int(mp["deaths"]) + 1
	mp["shoves_given"] = int(mp["shoves_given"]) + int(me["shoves_given"])
	mp["shoves_taken"] = int(mp["shoves_taken"]) + int(me["shoves_taken"])
	if int(me["score"]) > int(mp["best_score"]):
		mp["best_score"] = int(me["score"])
		out["new_best"] = true
	var hist: Array = mp["history"]
	hist.append({"house": results["house"], "creature": results["creature"], "outcome": results["outcome"],
		"time": results["time"], "score": me["score"], "rank": me["rank"], "players": results["rows"].size(),
		"rules": results["rules_version"], "date": Time.get_datetime_string_from_system()})
	while hist.size() > HISTORY_LIMIT:
		hist.pop_front()
	save()
	return out

func save_replay(replay: Dictionary) -> void:
	var f := FileAccess.open(replay_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(replay))
