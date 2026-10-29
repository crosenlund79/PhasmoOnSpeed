class_name Defs
extends RefCounted
## Static game data: evidence, creatures, equipment. Pure data, no behaviour.

const CELL := 32.0

# --- Evidence -----------------------------------------------------------------
# hidden == true: never listed in the journal until discovered in the current run.
const EVIDENCE := {
	"emf5": {"name": "EMF Level 5", "short": "EMF 5", "icon": "icons/ev_emf5.png", "hidden": false},
	"freezing": {"name": "Freezing Temperatures", "short": "Freezing", "icon": "icons/ev_freezing.png", "hidden": false},
	"spirit_box": {"name": "Spirit Box Response", "short": "Spirit Box", "icon": "icons/ev_spirit_box.png", "hidden": false},
	"uv": {"name": "Ultraviolet Handprints", "short": "UV", "icon": "icons/ev_uv.png", "hidden": false},
	"writing": {"name": "Ghost Writing", "short": "Writing", "icon": "icons/ev_writing.png", "hidden": false},
	"orbs": {"name": "Ghost Orbs", "short": "Orbs", "icon": "icons/ev_orbs.png", "hidden": false},
	"bite_marks": {"name": "Bite Marks", "short": "Bite Marks", "icon": "icons/ev_bite_marks.png", "hidden": true},
	"blood_drops": {"name": "Blood Droplets", "short": "Blood", "icon": "icons/ev_blood_drops.png", "hidden": true},
	"coffin_soil": {"name": "Grave Soil", "short": "Grave Soil", "icon": "icons/ev_coffin_soil.png", "hidden": true},
	"claw_marks": {"name": "Claw Marks", "short": "Claws", "icon": "icons/ev_claw_marks.png", "hidden": true},
	"fur": {"name": "Shed Fur", "short": "Fur", "icon": "icons/ev_fur.png", "hidden": true},
	"footprints": {"name": "Unusual Footprints", "short": "Footprints", "icon": "icons/ev_footprints.png", "hidden": true},
	"wrong_reflection": {"name": "Wrong Reflection", "short": "Reflection", "icon": "icons/ev_wrong_reflection.png", "hidden": true},
	"shed_skin": {"name": "Shed Skin", "short": "Skin", "icon": "icons/ev_shed_skin.png", "hidden": true},
	"mimic_voice": {"name": "Mimicked Voice", "short": "Voice", "icon": "icons/ev_mimic_voice.png", "hidden": true},
}
const CONVENTIONAL_EVIDENCE := ["emf5", "freezing", "spirit_box", "uv", "writing", "orbs"]

# --- Creatures ----------------------------------------------------------------
# kind: "ghost" (standard equipment works), "physical" (it does not), "harbinger".
# "public": shown in ordinary menus/journal suspect list.
const CREATURES := {
	"shade": {
		"name": "The Shade", "kind": "ghost", "public": true, "token": "tokens/shade.png",
		"evidence": ["emf5", "freezing", "orbs"],
		"hunt_threshold": 60.0, "hunt_cooldown": 30.0, "hunt_duration": 16.0,
		"hunt_speed": 195.0, "roam_speed": 70.0, "interaction_interval": 13.0, "lair_bias": 0.8,
		"difficulty": 1.0,
		"rite": "salt",
		"blurb": "A shy, sorrowful presence. Clings to its room and hunts rarely, but silently.",
		"rite_text": "Rite of Stillness: pour salt in its room, then perform the rite there.",
	},
	"poltergeist": {
		"name": "The Poltergeist", "kind": "ghost", "public": true, "token": "tokens/poltergeist.png",
		"evidence": ["spirit_box", "uv", "writing"],
		"hunt_threshold": 50.0, "hunt_cooldown": 25.0, "hunt_duration": 15.0,
		"hunt_speed": 225.0, "roam_speed": 95.0, "interaction_interval": 6.5, "lair_bias": 0.55,
		"difficulty": 1.05,
		"rite": "book",
		"blurb": "A spiteful, noisy spirit. Throws things, roams widely, and hunts often.",
		"rite_text": "Rite of Binding: lay the Ghost Writing Book in its room, then perform the rite there.",
	},
	"vampire": {
		"name": "Vampire", "kind": "physical", "public": false, "token": "tokens/vampire.png",
		"evidence": ["bite_marks", "blood_drops", "coffin_soil"],
		"hunt_threshold": 52.0, "hunt_cooldown": 28.0, "hunt_duration": 14.0,
		"hunt_speed": 215.0, "roam_speed": 110.0, "interaction_interval": 9.0, "lair_bias": 0.35,
		"difficulty": 1.15,
		"blurb": "It stalks from the dark and strikes from behind.",
		"rite_text": "Carry garlic to weaken it, then drive a wooden stake into it.",
	},
	"werewolf": {
		"name": "Werewolf", "kind": "physical", "public": false, "token": "tokens/werewolf.png",
		"evidence": ["claw_marks", "fur", "footprints"],
		"hunt_threshold": 45.0, "hunt_cooldown": 22.0, "hunt_duration": 15.0,
		"hunt_speed": 240.0, "roam_speed": 120.0, "interaction_interval": 7.0, "lair_bias": 0.45,
		"difficulty": 1.2,
		"blurb": "Relentless. Once it sees you, it runs you down.",
		"rite_text": "Gather silverware, melt it into a silver stake at a hearth or stove, then strike.",
	},
	"shapeshifter": {
		"name": "Shapeshifter", "kind": "physical", "public": false, "token": "tokens/shapeshifter.png",
		"evidence": ["wrong_reflection", "shed_skin", "mimic_voice"],
		"hunt_threshold": 50.0, "hunt_cooldown": 25.0, "hunt_duration": 15.0,
		"hunt_speed": 215.0, "roam_speed": 100.0, "interaction_interval": 8.0, "lair_bias": 0.4,
		"difficulty": 1.3,
		"blurb": "It wears borrowed faces. None of them are its own.",
		"rite_text": "Expose its true form with a hand mirror, then pin it with cold iron nails.",
	},
	"harbinger": {
		"name": "The Harbinger", "kind": "harbinger", "public": false, "token": "tokens/harbinger.png",
		"evidence": [],
		"hunt_threshold": 0.0, "hunt_cooldown": 14.0, "hunt_duration": 12.0,
		"hunt_speed": 228.0, "roam_speed": 90.0, "interaction_interval": 5.0, "lair_bias": 0.3,
		"difficulty": 1.25,
		"blurb": "Summoned by recklessness. It does not haunt. It hunts.",
		"rite_text": "Light the three sigil candles, then perform the Final Rite beside the bound Harbinger.",
	},
}
const ORDINARY_CREATURES := ["shade", "poltergeist", "vampire", "werewolf", "shapeshifter"]
const PUBLIC_SUSPECTS := ["shade", "poltergeist"]
const SHAPESHIFTER_FORMS := ["human", "ghost", "vampire", "werewolf", "cat"]
const FORM_TOKENS := {
	"human": "tokens/occupant_c.png", "ghost": "tokens/shade.png", "vampire": "tokens/vampire.png",
	"werewolf": "tokens/werewolf.png", "cat": "tokens/cat.png", "true": "tokens/shapeshifter.png",
}
const FORM_SPEED := {"human": 205.0, "ghost": 200.0, "vampire": 215.0, "werewolf": 245.0, "cat": 150.0, "true": 210.0}

# --- Equipment ----------------------------------------------------------------
# Slot equipment (numbers 1-9). Flashlight is a separate always-available toggle.
const EQUIPMENT := {
	"emf": {"name": "EMF Reader", "icon": "icons/eq_emf.png", "detector": true},
	"thermometer": {"name": "Thermometer", "icon": "icons/eq_thermometer.png", "detector": true},
	"uv": {"name": "UV Flashlight", "icon": "icons/eq_uv.png", "detector": true},
	"spirit_box": {"name": "Spirit Box", "icon": "icons/eq_spirit_box.png", "detector": true},
	"ghost_book": {"name": "Ghost Writing Book", "icon": "icons/eq_ghost_book.png", "placeable": true},
	"orb_camera": {"name": "Orb Camera", "icon": "icons/eq_orb_camera.png", "detector": true},
	"salt": {"name": "Salt", "icon": "icons/eq_salt.png", "placeable": true, "charges": 3},
	"crucifix": {"name": "Crucifix", "icon": "icons/eq_crucifix.png", "placeable": true, "charges": 2},
	"holy_water": {"name": "Holy Water", "icon": "icons/eq_holy_water.png", "charges": 3},
	# Resources found in the house (appear in the hotbar only once collected).
	"garlic": {"name": "Garlic", "icon": "icons/eq_garlic.png", "resource": true},
	"wooden_stake": {"name": "Wooden Stake", "icon": "icons/eq_wooden_stake.png", "resource": true},
	"silverware": {"name": "Silverware", "icon": "icons/eq_silverware.png", "resource": true},
	"silver_stake": {"name": "Silver Stake", "icon": "icons/eq_silver_stake.png", "resource": true},
	"hand_mirror": {"name": "Hand Mirror", "icon": "icons/eq_hand_mirror.png", "resource": true},
	"iron_nails": {"name": "Iron Nails", "icon": "icons/eq_iron_nails.png", "resource": true},
}
const BASE_LOADOUT := ["emf", "thermometer", "uv", "spirit_box", "ghost_book", "orb_camera", "salt", "crucifix", "holy_water"]
const RESOURCE_ORDER := ["garlic", "wooden_stake", "silverware", "silver_stake", "hand_mirror", "iron_nails"]
const SILVERWARE_NEEDED := 3

# Where resources are placed (room kinds, in preference order) and world sprite.
const RESOURCE_SPAWNS := {
	"garlic": {"kinds": ["kitchen", "pantry", "dining"], "count": 1, "sprite": "items/garlic.png"},
	"wooden_stake": {"kinds": ["shed", "cellar", "study", "living"], "count": 1, "sprite": "items/wooden_stake.png"},
	"silverware": {"kinds": ["dining", "kitchen", "pantry", "living", "study"], "count": 3, "sprite": "items/silverware.png"},
	"hand_mirror": {"kinds": ["bathroom", "bedroom"], "count": 1, "sprite": "items/hand_mirror.png"},
	"iron_nails": {"kinds": ["shed", "cellar", "study", "kitchen"], "count": 1, "sprite": "items/iron_nails.png"},
}

# --- Furniture ----------------------------------------------------------------
# size in cells at rotation 0; solid: blocks movement; light: emits light; melt: silver melting station.
const FURNITURE := {
	"bed_double": {"size": Vector2i(3, 4), "solid": true},
	"bed_single": {"size": Vector2i(2, 4), "solid": true},
	"wardrobe": {"size": Vector2i(3, 1), "solid": true},
	"dresser": {"size": Vector2i(2, 1), "solid": true},
	"nightstand": {"size": Vector2i(1, 1), "solid": true},
	"desk": {"size": Vector2i(3, 2), "solid": true},
	"chair": {"size": Vector2i(1, 1), "solid": true},
	"armchair": {"size": Vector2i(2, 2), "solid": true},
	"sofa": {"size": Vector2i(4, 2), "solid": true},
	"coffee_table": {"size": Vector2i(2, 1), "solid": true},
	"dining_table": {"size": Vector2i(5, 3), "solid": true},
	"bookshelf": {"size": Vector2i(3, 1), "solid": true},
	"fireplace": {"size": Vector2i(3, 1), "solid": true, "light": "hearth", "melt": true},
	"stove": {"size": Vector2i(2, 1), "solid": true, "melt": true},
	"counter": {"size": Vector2i(2, 1), "solid": true},
	"sink_kitchen": {"size": Vector2i(2, 1), "solid": true},
	"icebox": {"size": Vector2i(1, 1), "solid": true},
	"bathtub": {"size": Vector2i(2, 3), "solid": true},
	"toilet": {"size": Vector2i(1, 1), "solid": true},
	"washbasin": {"size": Vector2i(1, 1), "solid": true},
	"piano": {"size": Vector2i(3, 2), "solid": true},
	"grandfather_clock": {"size": Vector2i(1, 1), "solid": true},
	"potted_plant": {"size": Vector2i(1, 1), "solid": true},
	"rug_round": {"size": Vector2i(4, 4), "solid": false, "under": true},
	"rug_rect": {"size": Vector2i(5, 3), "solid": false, "under": true},
	"crates": {"size": Vector2i(2, 2), "solid": true},
	"barrel": {"size": Vector2i(1, 1), "solid": true},
	"workbench": {"size": Vector2i(3, 1), "solid": true},
	"woodpile": {"size": Vector2i(2, 1), "solid": true},
	"candelabra": {"size": Vector2i(1, 1), "solid": true, "light": "candle"},
	"floor_lamp": {"size": Vector2i(1, 1), "solid": true, "light": "lamp"},
	"wall_mirror": {"size": Vector2i(2, 1), "solid": true, "mirror": true},
	"cabinet": {"size": Vector2i(2, 1), "solid": true},
	"trunk": {"size": Vector2i(2, 1), "solid": true},
	"side_table": {"size": Vector2i(1, 1), "solid": true},
	"pew": {"size": Vector2i(4, 1), "solid": true},
	"altar": {"size": Vector2i(3, 2), "solid": true, "light": "candle"},
	"tree": {"size": Vector2i(3, 3), "solid": true},
	"hedge": {"size": Vector2i(2, 1), "solid": true},
	"gravestone": {"size": Vector2i(1, 1), "solid": true},
	"coffin": {"size": Vector2i(2, 4), "solid": true},
	"hay": {"size": Vector2i(2, 2), "solid": true},
	"wash_tub": {"size": Vector2i(2, 2), "solid": true},
}

static func evidence_name(id: String) -> String:
	return EVIDENCE.get(id, {}).get("name", id)

static func creature_name(id: String) -> String:
	return CREATURES.get(id, {}).get("name", id)

static func is_ghost(id: String) -> bool:
	return CREATURES.get(id, {}).get("kind", "") == "ghost"
