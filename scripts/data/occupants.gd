class_name Occupants
extends RefCounted
## Occupant names, looks and lightweight personalities. Lines are plain English
## passed through tr() when shown, so a translation catalogue can be added later.

const NAMES := [
	"Agatha Pell", "Edmund Wrae", "Lavinia Thorne", "Cuthbert Ames", "Prudence Hollis", "Ambrose Kettle",
	"Winifred Marsh", "Horace Bleak", "Ottilie Crane", "Jasper Lowe", "Mabel Quarry", "Silas Fenwick",
	"Dorothea Vane", "Percival Moss", "Euphemia Grey", "Barnaby Stroud", "Hester Lark", "Ignatius Pole",
	"Clementine Ash", "Rupert Hale",
]
## Safe Names OFF (private experimentation): recognisable characters from gothic
## and supernatural fiction, by the same index as NAMES — the stable identity.
const FICTION_NAMES := [
	"Mina Harker", "Jonathan Harker", "Lucy Westenra", "Arthur Holmwood", "Carmilla Karnstein", "R. M. Renfield",
	"Dorian Gray", "Victor Frankenstein", "Elizabeth Lavenza", "Henry Jekyll", "Edward Hyde", "Ichabod Crane",
	"Katrina Van Tassel", "Roderick Usher", "Madeline Usher", "Quincey Morris", "Jacob Marley", "Ebenezer Scrooge",
	"Laura Hollis", "Basil Hallward",
]

## The name shown for a NAMES entry, following the Safe Names setting.
static func display_name(name_id: int) -> String:
	if name_id < 0 or name_id >= NAMES.size():
		return "Stranger"
	return NAMES[name_id] if SaveData.settings().get("safe_names", true) else FICTION_NAMES[name_id]

const TOKENS := ["tokens/occupant_a.png", "tokens/occupant_b.png", "tokens/occupant_c.png",
	"tokens/occupant_d.png", "tokens/occupant_e.png", "tokens/occupant_f.png"]

## Behaviour knobs per personality; every value is a gentle nudge, not a simulation.
const PERSONALITIES := {
	"nervous": {
		"label": "Nervous", "speed": 78.0, "idle": [1.5, 3.5], "talk": [10.0, 18.0], "jitter": 1.0, "approach": false,
		"lines": ["Did you hear that? Please tell me you heard that.", "I'm not staying in this room.", "Was that you breathing?",
			"It's colder in here, isn't it? It is, isn't it?", "I'll just... stand over here.", "Please hurry."],
		"react": ["What was that?!", "Oh no. Oh no no no.", "I knew it. I knew it!"],
		"flee": ["I'm leaving!", "Not today!", "Forget the deposit!"],
	},
	"skeptical": {
		"label": "Skeptical", "speed": 62.0, "idle": [3.0, 7.0], "talk": [16.0, 28.0], "jitter": 0.15, "approach": false,
		"lines": ["Honestly, these old pipes make the strangest noises.", "It's just the wind.", "Are you sure you're qualified?",
			"My cousin said it's subsidence.", "Ghosts. In this economy."],
		"react": ["Draughty house, that's all.", "That'll be the rats.", "Probably the boiler."],
		"flee": ["Fine — I'm leaving, but not because of ghosts!", "I'll wait in the car. For unrelated reasons."],
	},
	"curious": {
		"label": "Curious", "speed": 70.0, "idle": [2.0, 5.0], "talk": [13.0, 22.0], "jitter": 0.3, "approach": true,
		"lines": ["Remarkable. That chair moved without anyone touching it.", "May I see the little box that beeps?",
			"I've been keeping notes, you know.", "The clock stopped at three again. Fascinating."],
		"react": ["Did you see that? Do it again!", "Ooh. Where did that come from?", "I must take a closer look."],
		"flee": ["On reflection, I'll observe from the garden!", "Fascinating — goodbye!"],
	},
	"dramatic": {
		"label": "Dramatic", "speed": 74.0, "idle": [2.0, 4.0], "talk": [11.0, 19.0], "jitter": 0.6, "approach": false,
		"lines": ["We're all going to die in this dreadful place!", "It knows my name. It whispers it at night.",
			"Don't look at the mirror. Never look at the mirror.", "I can feel it watching us."],
		"react": ["It's here! It's HERE!", "I'm too young to be haunted!", "Somebody do something!"],
		"flee": ["Save yourselves!", "I always said this house was cursed!"],
	},
	"calm": {
		"label": "Calm", "speed": 64.0, "idle": [3.0, 6.0], "talk": [15.0, 26.0], "jitter": 0.1, "approach": false,
		"lines": ["Everyone stay together. There's probably an explanation.", "Deep breaths. We're fine.",
			"I've put the kettle on, if anyone wants tea.", "Let the professionals work."],
		"react": ["Steady now.", "Nobody panic.", "That was... unusual. Stay calm."],
		"flee": ["Right. Everyone out, calmly.", "Time to leave — single file, please."],
	},
}
## Nightmare Mode: what everyone says once the house has truly got to them.
## Mixed in with each personality's own lines, so voices stay recognisable.
const FRIGHT_LINES := {
	"lines": ["Something touched my hand. Something COLD.", "Please. Please let's just go.", "I can't breathe in here.",
		"It's in the walls. It's in the WALLS.", "Don't leave me alone in here!", "I keep hearing my name.",
		"There's blood on the floor. Whose blood is that?", "Something's crawling on me — get it off!"],
	"react": ["No — no, no, NO!", "Oh God, what was that?!", "It's coming closer!", "Make it stop!", "Did it move? It moved!"],
}

## A line for a personality; in Nightmare (fear > 1) often a frightened one.
static func pick_line(personality: String, kind: String, rng: RandomNumberGenerator, fear: float = 1.0) -> String:
	var lines: Array = PERSONALITIES[personality][kind]
	if fear > 1.0 and FRIGHT_LINES.has(kind) and rng.randf() < 0.55:
		lines = FRIGHT_LINES[kind]
	return lines[rng.randi_range(0, lines.size() - 1)]

## Seconds until the next idle remark; frightened people talk more.
static func talk_delay(personality: String, rng: RandomNumberGenerator, fear: float = 1.0) -> float:
	var t: Array = PERSONALITIES[personality]["talk"]
	return rng.randf_range(t[0], t[1]) / fear

const BITTEN_LINES := ["My neck... itches.", "I feel so terribly tired.", "Why is it so bright in here?"]

## A distinct cast for a house: no repeated names or looks, varied personalities.
static func cast_for(_map: HouseMap, rng: RandomNumberGenerator, count: int) -> Array:
	var names := NAMES.duplicate()
	var tokens := TOKENS.duplicate()
	var kinds := PERSONALITIES.keys()
	_shuffle(names, rng)
	_shuffle(tokens, rng)
	_shuffle(kinds, rng)
	var out: Array = []
	for i in count:
		var nid := NAMES.find(names[i])
		out.append({"name": display_name(nid), "name_id": nid, "token": tokens[i % tokens.size()], "personality": kinds[i % kinds.size()]})
	return out

static func disguise_for(rng: RandomNumberGenerator, taken: Array) -> Dictionary:
	var used_ids := taken.map(func(p): return int(p.get("name_id", NAMES.find(p["name"]))))
	var used_tokens := taken.map(func(p): return p["token"])
	# A disguise is a plausible extra occupant: an unused name and an unused look.
	var ids: Array = range(NAMES.size()).filter(func(i): return not (i in used_ids))
	var tokens := TOKENS.filter(func(t): return not (t in used_tokens))
	var kinds := PERSONALITIES.keys()
	var nid: int = ids[rng.randi_range(0, ids.size() - 1)]
	return {"name": display_name(nid), "name_id": nid,
		"token": tokens[rng.randi_range(0, tokens.size() - 1)] if not tokens.is_empty() else TOKENS[0],
		"personality": kinds[rng.randi_range(0, kinds.size() - 1)]}

static func bitten_token(token: String) -> String:
	return token.replace(".png", "_bitten.png")

static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
