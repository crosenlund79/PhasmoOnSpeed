class_name Scoring
extends RefCounted
## Deterministic, versioned points algorithm. See docs/SCORING.md.
## The server reference implementation (server/leaderboard_server.py) mirrors
## this exactly; bump RULES_VERSION whenever any constant changes.

const RULES_VERSION := "1.0.0"

const VICTORY_BASE := 4000
const SPEED_MAX := 3000
const SPEED_FULL_UNTIL := 60.0      # seconds: full speed bonus at or below
const SPEED_ZERO_AT := 420.0        # seconds: no speed bonus at or above
const EVIDENCE_EACH := 300
const EVIDENCE_CAP := 3             # only the vanquished entity's own evidence counts
const CLEAN_ID_BONUS := 1000        # first vanquishing attempt was correct
const UNHARMED_BONUS := 800
const HUNT_SURVIVED_EACH := 150
const HUNT_SURVIVED_CAP := 3        # reckless-provoked and Harbinger hunts never count
const AUDACITY_BONUS := 250         # correct, completely blind victory
const WRONG_ATTEMPT_PENALTY := 700  # every incorrect vanquishing attempt
const INCOMPLETE_ATTEMPT_PENALTY := 250  # right identity, preparation missing
const DIFFICULTY := {
	"shade": 1.0, "poltergeist": 1.05, "vampire": 1.15, "werewolf": 1.2, "shapeshifter": 1.3, "harbinger": 1.25,
}

## summary keys used: vanquished(bool), time(float s), creature(String: the entity
## finally vanquished), true_evidence(int), incorrect_attempts(int),
## incomplete_attempts(int), wounds(int), clean_hunts_survived(int), blind(bool).
static func compute(summary: Dictionary) -> Dictionary:
	var lines: Array = []
	if not summary.get("vanquished", false):
		return {"total": 0, "lines": [["Perished — no score", 0]], "version": RULES_VERSION, "multiplier": 1.0}
	var t := float(summary.get("time", 0.0))
	var speed_frac := clampf((SPEED_ZERO_AT - t) / (SPEED_ZERO_AT - SPEED_FULL_UNTIL), 0.0, 1.0)
	var speed := int(round(SPEED_MAX * speed_frac))
	var evidence := EVIDENCE_EACH * mini(int(summary.get("true_evidence", 0)), EVIDENCE_CAP)
	var incorrect := int(summary.get("incorrect_attempts", 0))
	var incomplete := int(summary.get("incomplete_attempts", 0))
	var ident := CLEAN_ID_BONUS if incorrect == 0 and incomplete == 0 else 0
	var unharmed := UNHARMED_BONUS if int(summary.get("wounds", 0)) == 0 else 0
	var hunts := HUNT_SURVIVED_EACH * mini(int(summary.get("clean_hunts_survived", 0)), HUNT_SURVIVED_CAP)
	var audacity := AUDACITY_BONUS if summary.get("blind", false) and incorrect == 0 else 0
	lines.append(["Vanquished", VICTORY_BASE])
	lines.append(["Swiftness", speed])
	lines.append(["Evidence", evidence])
	lines.append(["Clean identification", ident])
	lines.append(["Unharmed", unharmed])
	lines.append(["Hunts survived", hunts])
	if audacity > 0:
		lines.append(["Audacity", audacity])
	var subtotal := VICTORY_BASE + speed + evidence + ident + unharmed + hunts + audacity
	var mult: float = DIFFICULTY.get(summary.get("creature", ""), 1.0)
	var scaled := int(round(subtotal * mult))
	var bonus_from_mult := scaled - subtotal
	if bonus_from_mult != 0:
		lines.append(["Creature difficulty ×%.2f" % mult, bonus_from_mult])
	var penalty := WRONG_ATTEMPT_PENALTY * incorrect + INCOMPLETE_ATTEMPT_PENALTY * incomplete
	if penalty > 0:
		lines.append(["Reckless attempts", -penalty])
	var total := maxi(0, scaled - penalty)
	return {"total": total, "lines": lines, "version": RULES_VERSION, "multiplier": mult}
