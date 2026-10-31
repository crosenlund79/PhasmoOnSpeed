class_name Rankings
extends RefCounted
## Offline rankings against FICTIONAL legendary ghost hunters. Their scores use the
## same Scoring scale as the player (rules 1.0.0). Each legend has a stable id;
## with Safe Names OFF (settings, private experimentation only) the table shows a
## recognisable fictional hunter instead — same id, score and place.

const LEGENDS := [
	{"id": "spookwell", "alt": "Abraham Van Helsing", "alt_note": "Wrote the book on vampires. Then staked the author's enemies.", "name": "Professor Spookwell", "score": 11420, "time": 71.4, "house": "Blackwood Manor", "note": "Wrote the book. Then the book wrote back."},
	{"id": "hexley", "alt": "Hermione Granger", "alt_note": "Read every book in the house before the ghost did.", "name": "Mina Hexley", "score": 11060, "time": 79.2, "house": "St. Evangeline Rectory", "note": "Has never once run. Things run from her."},
	{"id": "hellstorm", "alt": "Harry Potter", "alt_note": "Has survived worse. Repeatedly.", "name": "Vince Hellstorm", "score": 10690, "time": 66.8, "house": "Hollow Lane Farmhouse", "note": "Fastest stake in the county. Possibly too fast."},
	{"id": "shade", "alt": "Buffy Summers", "alt_note": "Into every generation, a hunter is born.", "name": "Eleanor Shade", "score": 10310, "time": 98.5, "house": "Marrow Street Townhouse", "note": "No relation. She insists."},
	{"id": "grimley", "alt": "John Constantine", "alt_note": "Smokes in the haunted rooms. The ghosts complain.", "name": "Brother Grimley", "score": 9870, "time": 121.0, "house": "St. Evangeline Rectory", "note": "Blesses everything. Twice."},
	{"id": "crowe", "alt": "Percy Jackson", "alt_note": "Mostly fights monsters. Ghosts are a hobby.", "name": "Catrin Crowe", "score": 9540, "time": 104.3, "house": "Ashgrove Cottage", "note": "Talks to the crows. They talk back."},
	{"id": "vile", "alt": "Dean Winchester", "alt_note": "Salt, iron and classic rock.", "name": "Dr. Ambrose Vile", "score": 9120, "time": 133.7, "house": "Blackwood Manor", "note": "Medical doctor. Of what, nobody asks."},
	{"id": "thistle", "alt": "Sam Winchester", "alt_note": "Does the research. Dean takes the credit.", "name": "Old Meg Thistle", "score": 8730, "time": 142.9, "house": "Hollow Lane Farmhouse", "note": "Carries garlic. For every occasion."},
	{"id": "penumbra", "alt": "Geralt of Rivia", "alt_note": "Charges for every haunting. Hmm.", "name": "Silas Penumbra", "score": 8240, "time": 157.1, "house": "Marrow Street Townhouse", "note": "Prefers the dark. The dark is ambivalent."},
	{"id": "fogg", "alt": "Ichabod Crane", "alt_note": "Prefers houses without horses.", "name": "Lady Wilhelmina Fogg", "score": 7810, "time": 176.4, "house": "Ashgrove Cottage", "note": "Investigates in full evening dress."},
	{"id": "quill", "alt": "Jonathan Harker", "alt_note": "Took notes. Survived the castle. Mostly.", "name": "Barnaby Quill", "score": 7150, "time": 203.0, "house": "Saltmarsh Harbour", "note": "Journalist. Survived, mostly."},
	{"id": "lantern", "alt": "Carl Kolchak", "alt_note": "Reporter. Nobody believes his articles.", "name": "Theo Lantern", "score": 6380, "time": 238.6, "house": "The Black Lantern Inn", "note": "Still afraid of the dark. Goes anyway."},
]

## A legend as currently displayed (name and note follow the Safe Names setting).
static func shown(l: Dictionary) -> Dictionary:
	var r: Dictionary = l.duplicate()
	if not SaveData.settings().get("safe_names", true):
		r["name"] = l["alt"]
		r["note"] = l["alt_note"]
	return r

## Returns rows sorted by score: {name, score, time, house, note, fictional, is_player}.
static func table(player_name: String, player_best: int, player_time: float = 0.0, player_house: String = "") -> Array:
	var rows: Array = []
	for l in LEGENDS:
		var r: Dictionary = shown(l)
		r["fictional"] = true
		r["is_player"] = false
		rows.append(r)
	if player_best > 0:
		rows.append({"name": player_name, "score": player_best, "time": player_time, "house": player_house,
			"note": "That's you.", "fictional": false, "is_player": true})
	rows.sort_custom(func(a, b): return a["score"] > b["score"])
	return rows

## 1-based rank a score would take among the legends (ties go to the player).
static func rank_for(score: int) -> int:
	var rank := 1
	for l in LEGENDS:
		if l["score"] > score:
			rank += 1
	return rank

## The legend directly above a score, or {} when the player is first.
static func next_rival(score: int) -> Dictionary:
	var best := {}
	for l in LEGENDS:
		if l["score"] > score and (best.is_empty() or l["score"] < best["score"]):
			best = l
	return shown(best) if not best.is_empty() else best
