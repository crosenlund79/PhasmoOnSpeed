class_name MpScoring
extends RefCounted
## Competitive multiplayer points (separate from solo Scoring and its rankings).
## Computed only by the host from authoritative facts. See docs/SCORING.md.

const RULES_VERSION := "mp-1.0.0"

const EVIDENCE_EACH := 400        # entity's own evidence in YOUR journal (cap 3)
const FIRST_FIND_EACH := 250      # ...that you recorded before any rival (cap 3)
const CORRECT_SUSPECT := 800      # your chosen suspect was right when it ended
const VANQUISHER := 2000          # the hunter who performed the vanquishing
const UNHARMED := 800             # alive at the end, never wounded
const WOUNDED_ALIVE := 400        # alive at the end, wounded once
const SWIFTNESS_MAX := 1500       # surviving hunters of a won match, by match time
const SPEED_FULL_UNTIL := 60.0
const SPEED_ZERO_AT := 420.0
const HUNT_SURVIVED_EACH := 100   # cap 3; reckless-provoked and Harbinger hunts never count
const HUNT_CAP := 3
const WRONG_PENALTY := 700
const RECKLESS_EXTRA := 300       # on top of the wrong-attempt penalty
const INCOMPLETE_PENALTY := 250

static func compute(f: Dictionary) -> Dictionary:
	var lines: Array = []
	var won: bool = f.get("vanquished", false)
	var alive: bool = f.get("alive", false)
	var ev := EVIDENCE_EACH * mini(int(f.get("true_evidence", 0)), 3)
	var first := FIRST_FIND_EACH * mini(int(f.get("first_finds", 0)), 3)
	var ident := CORRECT_SUSPECT if f.get("suspect_correct", false) else 0
	var vanq := VANQUISHER if won and f.get("vanquisher", false) else 0
	var surv := 0
	if won and alive:
		surv = UNHARMED if int(f.get("wounds", 0)) == 0 else WOUNDED_ALIVE
	var swift := 0
	if won and alive:
		var t := float(f.get("time", 0.0))
		swift = int(round(SWIFTNESS_MAX * clampf((SPEED_ZERO_AT - t) / (SPEED_ZERO_AT - SPEED_FULL_UNTIL), 0.0, 1.0)))
	var hunts := HUNT_SURVIVED_EACH * mini(int(f.get("clean_hunts_survived", 0)), HUNT_CAP)
	lines.append(["Evidence", ev])
	lines.append(["First discoveries", first])
	lines.append(["Correct suspect", ident])
	if vanq > 0:
		lines.append(["Vanquished it", vanq])
	lines.append(["Survival", surv])
	lines.append(["Swiftness", swift])
	lines.append(["Hunts survived", hunts])
	var subtotal := ev + first + ident + vanq + surv + swift + hunts
	var mult: float = Scoring.DIFFICULTY.get(f.get("creature", ""), 1.0)
	var scaled := int(round(subtotal * mult))
	if scaled != subtotal:
		lines.append(["Creature difficulty ×%.2f" % mult, scaled - subtotal])
	var wrong := int(f.get("incorrect_attempts", 0))
	var reckless := int(f.get("reckless_attempts", 0))
	var incomplete := int(f.get("incomplete_attempts", 0))
	var penalty := WRONG_PENALTY * wrong + RECKLESS_EXTRA * reckless + INCOMPLETE_PENALTY * incomplete
	if penalty > 0:
		lines.append(["Reckless attempts", -penalty])
	return {"total": maxi(0, scaled - penalty), "lines": lines, "version": RULES_VERSION}

## Highest score wins. Ties: vanquisher, then survivors, then fewer wrong attempts.
static func rank(rows: Array) -> Array:
	var out := rows.duplicate()
	out.sort_custom(func(a, b):
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		if a["vanquisher"] != b["vanquisher"]:
			return a["vanquisher"]
		if a["alive"] != b["alive"]:
			return a["alive"]
		if a["incorrect_attempts"] != b["incorrect_attempts"]:
			return a["incorrect_attempts"] < b["incorrect_attempts"]
		return a["index"] < b["index"])
	for i in out.size():
		out[i]["rank"] = i + 1
	return out
