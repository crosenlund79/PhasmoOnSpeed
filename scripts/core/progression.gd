class_name Progression
extends RefCounted
## Light progression: item tiers, Gold Ducats and Renown (never shown as anything
## but "Renown"), hunter ranks, and the Witch's wares. Pure rules over a save
## dictionary (SaveData.data["progress"]); never touches scores or leaderboards.

const TIERS := {
	"common": {"name": "Common", "color": Color(0.78, 0.75, 0.68), "order": 0},
	"uncommon": {"name": "Uncommon", "color": Color(0.42, 0.7, 0.36), "order": 1},
	"rare": {"name": "Rare", "color": Color(0.38, 0.58, 0.95), "order": 2},
	"epic": {"name": "Epic", "color": Color(0.7, 0.4, 0.9), "order": 3},
	"legendary": {"name": "Legendary", "color": Color(1.0, 0.64, 0.18), "order": 4},
}

## Witch's Needle variants. Only presentation and the *display* sense range
## change: the evidence rule (Needle 5 inside a hotspot) is never touched.
##   sense   — multiplier of the distance at which the needle starts to stir
##   smooth  — how fast the reading settles (higher = steadier, quicker)
##   precise — reading shows one decimal ("NEEDLE 3.4")
##   glass / sigil / glow — gauge colours
const NEEDLES := {
	"common": {"name": "Witch's Needle", "tier": "common", "level": 1, "price": 0,
		"sense": 1.0, "smooth": 8.0, "precise": false, "damp": 7.0,
		"glass": Color(0.86, 0.84, 0.74), "sigil": Color(0.78, 0.63, 0.30), "glow": Color(0, 0, 0, 0),
		"desc": "The needle every hunter starts with. It knows enough."},
	"silver": {"name": "Tarnished Silver Needle", "tier": "uncommon", "level": 3, "price": 150,
		"sense": 1.12, "smooth": 10.0, "precise": false, "damp": 8.0,
		"glass": Color(0.8, 0.86, 0.9), "sigil": Color(0.85, 0.88, 0.92), "glow": Color(0.8, 0.9, 1.0, 0.12),
		"desc": "Silver listens a little further. It stirs a step sooner."},
	"raven": {"name": "Raven-Quill Needle", "tier": "rare", "level": 6, "price": 400,
		"sense": 1.22, "smooth": 12.0, "precise": true, "damp": 9.0,
		"glass": Color(0.62, 0.74, 0.95), "sigil": Color(0.45, 0.62, 1.0), "glow": Color(0.4, 0.6, 1.0, 0.18),
		"desc": "A raven's quill in blued glass. Its reading is read to a tenth."},
	"bloodglass": {"name": "Bloodglass Needle", "tier": "epic", "level": 10, "price": 900,
		"sense": 1.32, "smooth": 14.0, "precise": true, "damp": 10.0,
		"glass": Color(0.95, 0.5, 0.5), "sigil": Color(1.0, 0.78, 0.35), "glow": Color(1.0, 0.25, 0.2, 0.22),
		"desc": "Sealed with a hunter's blood. Steady as a heartbeat, keen as a wound."},
	"veilpiercer": {"name": "The Veilpiercer", "tier": "legendary", "level": 15, "price": 2000,
		"sense": 1.45, "smooth": 16.0, "precise": true, "damp": 11.0,
		"glass": Color(0.75, 0.95, 1.0), "sigil": Color(1.0, 0.72, 0.25), "glow": Color(0.6, 0.95, 1.0, 0.3),
		"desc": "Forged where the Veil is thinnest. It points before the dead have moved."},
}
const NEEDLE_ORDER := ["common", "silver", "raven", "bloodglass", "veilpiercer"]

## Hunter titles by minimum level.
const TITLES := [[1, "Uninitiated"], [3, "Gravewalker"], [6, "Spirit Seeker"], [10, "Occult Hunter"],
	[15, "Warden of the Veil"], [22, "Dreadbane"], [30, "Harbinger's Bane"]]
const MAX_LEVEL := 50
const REWARD_KEYS_KEPT := 120
const DIFF_MULT := {"beginner": 0.6, "normal": 1.0, "nightmare": 1.35, "hellbound": 1.6, "abyssal": 1.9}

static func defaults() -> Dictionary:
	return {"ducats": 0, "renown": 0, "owned": ["common"], "needle": "common", "rewarded": []}

static func tier_name(tier: String) -> String:
	return TIERS.get(tier, TIERS["common"])["name"]

static func tier_color(tier: String) -> Color:
	return TIERS.get(tier, TIERS["common"])["color"]

## Every equipment item is Common unless Defs assigns it a "tier".
static func item_tier(item_id: String) -> String:
	return str(Defs.EQUIPMENT.get(item_id, {}).get("tier", "common"))

# --- Renown levels -----------------------------------------------------------------

## Renown needed to advance FROM `level` to the next: 200, 566, 1039, 1600, ...
static func level_cost(level: int) -> int:
	return int(round(200.0 * pow(float(level), 1.5)))

static func level_for(renown: int) -> int:
	return int(level_info(renown)["level"])

## {level, into, need, frac, title} for a Renown total.
static func level_info(renown: int) -> Dictionary:
	var lv := 1
	var left := maxi(0, renown)
	while lv < MAX_LEVEL and left >= level_cost(lv):
		left -= level_cost(lv)
		lv += 1
	var need := level_cost(lv) if lv < MAX_LEVEL else 0
	return {"level": lv, "into": left, "need": need, "frac": 1.0 if need == 0 else float(left) / need, "title": title_for(lv)}

static func title_for(level: int) -> String:
	var t: String = TITLES[0][1]
	for row in TITLES:
		if level >= int(row[0]):
			t = row[1]
	return t

# --- Rewards -----------------------------------------------------------------------

static func solo_reward(summary: Dictionary) -> Dictionary:
	var m: float = DIFF_MULT.get(str(summary.get("difficulty", "normal")), 1.0)
	var score := maxi(0, int(summary.get("score", 0)))
	if summary.get("vanquished", false):
		return {"ducats": int(round((20.0 + score / 100.0) * m)), "renown": int(round((60.0 + score / 40.0) * m))}
	var ev: int = summary.get("evidence_ids", []).size()
	return {"ducats": int(round(5.0 * m)), "renown": int(round((15.0 + 5.0 * ev) * m))}

static func match_reward(results: Dictionary, me: Dictionary) -> Dictionary:
	var m: float = DIFF_MULT.get(str(results.get("difficulty", "normal")), 1.0)
	var score := maxi(0, int(me.get("score", 0)))
	var won: bool = results.get("outcome", "") == "vanquished"
	var first: bool = int(me.get("rank", 9)) == 1
	var d := (15.0 + score / 100.0) if won else 5.0 + score / 400.0
	var r := (50.0 + score / 40.0) if won else 15.0 + score / 120.0
	if first and won:
		d += 15.0
		r += 40.0
	return {"ducats": int(round(d * m)), "renown": int(round(r * m))}

## Grants a reward exactly once per key. Returns what changed (granted=false on a repeat).
static func grant(p: Dictionary, reward: Dictionary, key: String) -> Dictionary:
	var before := level_info(int(p["renown"]))
	var out := {"granted": false, "ducats": 0, "renown": 0, "level_before": before["level"], "level": before["level"],
		"title": before["title"], "title_before": before["title"]}
	var keys: Array = p["rewarded"]
	if key in keys:
		return out
	keys.append(key)
	while keys.size() > REWARD_KEYS_KEPT:
		keys.pop_front()
	p["ducats"] = int(p["ducats"]) + int(reward["ducats"])
	p["renown"] = int(p["renown"]) + int(reward["renown"])
	var after := level_info(int(p["renown"]))
	out.merge({"granted": true, "ducats": int(reward["ducats"]), "renown": int(reward["renown"]),
		"level": after["level"], "title": after["title"]}, true)
	return out

# --- The Witch's wares ---------------------------------------------------------------

## "" when the needle can be bought, otherwise why not.
static func buy_block(p: Dictionary, id: String) -> String:
	var n: Dictionary = NEEDLES.get(id, {})
	if n.is_empty():
		return "unknown"
	if id in p["owned"]:
		return "owned"
	if level_for(int(p["renown"])) < int(n["level"]):
		return "level"
	if int(p["ducats"]) < int(n["price"]):
		return "ducats"
	return ""

static func buy(p: Dictionary, id: String) -> bool:
	if buy_block(p, id) != "":
		return false
	p["ducats"] = int(p["ducats"]) - int(NEEDLES[id]["price"])
	p["owned"].append(id)
	return true

static func equip(p: Dictionary, id: String) -> bool:
	if not id in p["owned"]:
		return false
	p["needle"] = id
	return true

## The local player's equipped needle parameters (common for anyone else).
static func needle_params(local: bool = true) -> Dictionary:
	if not local or SaveData.data.is_empty():
		return NEEDLES["common"]
	var id := str(SaveData.progress().get("needle", "common"))
	return NEEDLES.get(id, NEEDLES["common"])

## Display-only sense value for a stronger needle: the same falloff as
## Phenomena.emf_value with a longer reach. Never feeds evidence.
static func needle_sense(hotspots: Array, pos: Vector2, sense: float) -> float:
	var v := 1.0
	for hs in hotspots:
		var d: float = pos.distance_to(hs["pos"])
		v = maxf(v, float(hs["level"]) * clampf(1.2 - d / (120.0 * sense), 0.0, 1.0))
	return clampf(v, 1.0, 5.0)

# --- Developer cheats (menus / tavern only) -----------------------------------------

static func cheats_allowed() -> bool:
	return (OS.is_debug_build() or SaveData.settings().get("dev_mode", false)) and not Net.is_online()

static func cheat_add(p: Dictionary, key: String, amount: int) -> bool:
	if not cheats_allowed() or not key in ["ducats", "renown"]:
		return false
	p[key] = maxi(0, int(p[key]) + amount)
	return true

static func reset_progress(p: Dictionary) -> void:
	var keep: Array = p.get("rewarded", [])
	p.merge(defaults(), true)
	p["rewarded"] = keep   # past runs stay rewarded: a reset never re-pays them
