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
	_settle_abandoned_run()
	Sfx.apply_volumes(settings().get("master", 0.8), settings().get("music", 0.6))

func _defaults() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"settings": {"master": 0.8, "music": 0.6, "ui_scale": 1.0, "fullscreen": false,
			"player_name": "Investigator", "dev_mode": true, "dev_cheats": false,
			"equip_labels": true, "ev_labels": true, "suspect_labels": true,
			"equip_hud_opacity": 0.9, "hud_scale": 1.0, "difficulty": "normal",
			"ev_notify": true, "ev_notify_opacity": 0.95, "ev_notify_size": 1.0,
			"npc_names": true, "safe_names": true, "last_address": "127.0.0.1", "last_port": 24680},
		"records": {"best_score": 0, "best_score_time": 0.0, "best_score_house": "", "houses": {}},
		"stats": {},
		"history": [],
		"runs_started": 0,
		# Competitive multiplayer is kept completely separate from solo records.
		"mp": {"matches": 0, "wins": 0, "best_score": 0, "vanquishes": 0, "deaths": 0, "shoves_given": 0,
			"shoves_taken": 0, "history": []},
		# Gold Ducats, Renown, owned and equipped wares (see Progression).
		"progress": Progression.defaults(),
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
	# Saves from before progression start at 0 Ducats / 0 Renown with the common needle.
	if typeof(data.get("progress")) != TYPE_DICTIONARY:
		data["progress"] = Progression.defaults()
	for k in Progression.defaults():
		if not data["progress"].has(k):
			data["progress"][k] = Progression.defaults()[k]

func save() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, " "))

func reset_all() -> void:
	data = _defaults()
	save()

func settings() -> Dictionary:
	return data["settings"]

func progress() -> Dictionary:
	return data["progress"]

func set_setting(key: String, value) -> void:
	data["settings"][key] = value
	save()

## Normal and Nightmare personal bests are kept apart.
func house_record(house_id: String, difficulty: String = "normal") -> Dictionary:
	var key := "houses" if difficulty == "normal" else difficulty + "_houses"
	if not data["records"].has(key):
		data["records"][key] = {}
	var houses: Dictionary = data["records"][key]
	if not houses.has(house_id):
		houses[house_id] = {"best_time": 0.0, "best_score": 0, "wins": 0, "runs": 0}
	return houses[house_id]

func note_run_started() -> void:
	data["runs_started"] = int(data.get("runs_started", 0)) + 1

## Records a finished run exactly once. Returns {new_best_time, new_best_score, prev_best_time, prev_best_score}.
func record_run(summary: Dictionary) -> Dictionary:
	var house_id: String = summary["house"]
	var other_mode: bool = summary.get("difficulty", "normal") != "normal"
	var rec := house_record(house_id, summary.get("difficulty", "normal"))
	var out := {"new_best_time": false, "new_best_score": false,
		"prev_best_time": rec["best_time"], "prev_best_score": rec["best_score"],
		"prev_overall_best": data["records"]["best_score"]}
	rec["runs"] = int(rec["runs"]) + 1
	if summary["vanquished"] and not summary.get("dev_immortal", false):
		rec["wins"] = int(rec["wins"]) + 1
		if rec["best_time"] <= 0.0 or summary["time"] < rec["best_time"]:
			rec["best_time"] = summary["time"]
			out["new_best_time"] = true
		if summary["score"] > int(rec["best_score"]):
			rec["best_score"] = summary["score"]
			out["new_best_score"] = true
		if not other_mode and summary["score"] > int(data["records"]["best_score"]):
			data["records"]["best_score"] = summary["score"]
			data["records"]["best_score_time"] = summary["time"]
			data["records"]["best_score_house"] = summary.get("house_name", house_id)
	_update_stats(summary)
	var key := "solo:%s:%d:%.2f" % [house_id, int(summary.get("seed", 0)), float(summary["time"])]
	match str(summary.get("outcome", "")):
		"perished":
			out["penalty"] = Progression.penalize(progress(), "death", summary.get("difficulty", "normal"), key)
		"fled":
			out["penalty"] = Progression.penalize(progress(), "flee", summary.get("difficulty", "normal"), key)
		_:
			out["reward"] = Progression.grant(progress(), Progression.solo_reward(summary), key)
	out["mission"] = Progression.settle_mission(progress(), summary, int(data.get("runs_started", 0)))
	end_run_guard()
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
		"rules": s["rules_version"], "difficulty": s.get("difficulty", "normal"), "date": Time.get_datetime_string_from_system()}

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
	st["voodoo"] = int(st.get("voodoo", 0)) + int(s.get("voodoo_uses", 0))
	st["npcs_burned"] = int(st.get("npcs_burned", 0)) + int(s.get("npcs_burned", 0))
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
	var diff: String = results.get("difficulty", "normal")
	var best_key := "best_score" if diff == "normal" else diff + "_best_score"
	out["prev_best"] = int(mp.get(best_key, 0))
	if int(me["score"]) > int(mp.get(best_key, 0)):
		mp[best_key] = int(me["score"])
		out["new_best"] = true
	var key := "mp:%s:%d:%.2f:%s" % [results.get("house", ""), int(results.get("seed", 0)), float(results.get("time", 0.0)), my_actor]
	out["reward"] = Progression.grant(progress(), Progression.match_reward(results, me), key)
	if not me["alive"]:
		out["penalty"] = Progression.penalize(progress(), "death", results.get("difficulty", "normal"), key + ":death")
	end_run_guard()
	var hist: Array = mp["history"]
	hist.append({"house": results["house"], "creature": results["creature"], "outcome": results["outcome"],
		"time": results["time"], "score": me["score"], "rank": me["rank"], "players": results["rows"].size(),
		"rules": results["rules_version"], "difficulty": results.get("difficulty", "normal"), "date": Time.get_datetime_string_from_system()})
	while hist.size() > HISTORY_LIMIT:
		hist.pop_front()
	save()
	return out

# --- Run guard ---------------------------------------------------------------------------
# An investigation in progress is noted in the save. Finishing it normally (results)
# clears the note; quitting the game or dropping out mid-run leaves it, and it is
# settled as fleeing on the next launch — closing the window is no escape.

func begin_run_guard(difficulty: String) -> void:
	progress()["pending"] = {"key": "pending:%d" % Time.get_ticks_usec() + ":" + str(Time.get_unix_time_from_system()), "difficulty": difficulty}
	save()

func end_run_guard() -> void:
	progress().erase("pending")

## Deliberate fleeing (or leaving a match): the penalty now, the guard cleared.
func flee_now(difficulty: String) -> Dictionary:
	var g: Dictionary = progress().get("pending", {})
	var out := Progression.penalize(progress(), "flee", difficulty, str(g.get("key", "flee:%d" % Time.get_ticks_usec())))
	end_run_guard()
	save()
	return out

## On launch: an investigation abandoned by quitting counts as fleeing.
var startup_notice := ""

func _settle_abandoned_run() -> void:
	var g = progress().get("pending")
	if typeof(g) != TYPE_DICTIONARY:
		return
	var r := Progression.penalize(progress(), "flee", str(g.get("difficulty", "normal")), str(g.get("key", "")))
	end_run_guard()
	save()
	if r["applied"]:
		startup_notice = "You abandoned your last investigation: %d Renown." % int(r["renown"])

func save_replay(replay: Dictionary) -> void:
	var f := FileAccess.open(replay_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(replay))
