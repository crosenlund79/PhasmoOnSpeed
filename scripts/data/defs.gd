class_name Defs
extends RefCounted
## Static game data: evidence, creatures, equipment. Pure data, no behaviour.

const CELL := 32.0

# --- Evidence -----------------------------------------------------------------
# hidden == true: never listed in the journal until discovered in the current run.
const EVIDENCE := {
	"emf5": {"name": "Witch's Needle Frenzy", "short": "Needle 5", "icon": "icons/ev_emf5.png", "hidden": false},
	"freezing": {"name": "Freezing Temperatures", "short": "Freezing", "icon": "icons/ev_freezing.png", "hidden": false},
	"spirit_box": {"name": "Whisper Box Response", "short": "Whisper", "icon": "icons/ev_spirit_box.png", "hidden": false},
	"uv": {"name": "Wraithlight Handprints", "short": "Handprints", "icon": "icons/ev_uv.png", "hidden": false},
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
# Every entity is selectable as a suspect and fully described in the encyclopedia.
# The encyclopedia and in-game hints read these entries; "vanquish" steps are
# the authoritative player-facing description of the code in scripts/game/run.gd.
const CREATURES := {
	"shade": {
		"name": "The Shade", "kind": "ghost", "token": "tokens/shade.png",
		"evidence": ["emf5", "freezing", "orbs"],
		"hunt_threshold": 60.0, "hunt_cooldown": 30.0, "hunt_duration": 16.0,
		"hunt_speed": 195.0, "roam_speed": 70.0, "interaction_interval": 13.0, "lair_bias": 0.8,
		"difficulty": 1.0, "rite": "salt", "rite_needs": ["salt"], "rite_name": "Rite of Stillness",
		"blurb": "A shy, sorrowful presence. Clings to its room and hunts rarely.",
		"behaviour": "Spends most of its time in its own room, stirring the air and the Witch's Needle there. Its room turns bitterly cold.",
		"hunting": "Hunts the least often of any entity and moves slowest of all. It blinks in and out of sight while it hunts.",
		"strengths": ["Its evidence gathers in one room — but so does its attention."],
		"weaknesses": ["Placed crucifixes stop its hunts from starting.", "Holy water stuns it and ends a hunt.", "Salt slows it while it hunts."],
		"vanquish": ["Find the room it haunts.", "Pour salt in that room.", "Choose The Shade as your suspect (Tab).", "Hold V inside its room to perform the Rite of Stillness."],
	},
	"poltergeist": {
		"name": "The Poltergeist", "kind": "ghost", "token": "tokens/poltergeist.png",
		"evidence": ["spirit_box", "uv", "writing"],
		"hunt_threshold": 50.0, "hunt_cooldown": 25.0, "hunt_duration": 15.0,
		"hunt_speed": 225.0, "roam_speed": 95.0, "interaction_interval": 6.5, "lair_bias": 0.55,
		"difficulty": 1.05, "rite": "book", "rite_needs": ["ghost_book"], "rite_name": "Rite of Binding",
		"blurb": "A spiteful, noisy spirit. Throws things, roams widely, and hunts often.",
		"behaviour": "Rattles furniture, bangs and creaks doors, leaves handprints on walls and answers the Whisper Box. It wanders far from its room.",
		"hunting": "Hunts often and quickly, though still slower than a walking investigator.",
		"strengths": ["Roams the whole house, so it can be anywhere.", "Frequent hunts."],
		"weaknesses": ["Placed crucifixes stop its hunts from starting.", "Holy water stuns it and ends a hunt.", "Salt slows it while it hunts."],
		"vanquish": ["Find the room it haunts.", "Lay the Ghost Writing Book in that room.", "Choose The Poltergeist as your suspect (Tab).", "Hold V inside its room to perform the Rite of Binding."],
	},
	"blightness": {
		"name": "The Blightness", "kind": "ghost", "token": "tokens/blightness.png",
		"evidence": ["emf5", "spirit_box", "writing"],
		"hunt_threshold": 55.0, "hunt_cooldown": 27.0, "hunt_duration": 14.0,
		"hunt_speed": 215.0, "roam_speed": 85.0, "interaction_interval": 9.0, "lair_bias": 0.65,
		"difficulty": 1.1, "rite": "crucifix", "rite_needs": ["crucifix"], "rite_name": "Rite of Severance",
		"blurb": "A rot in the air. It moves in lurches, and the house pings as it passes.",
		"behaviour": "Never a clear shape: when it shows itself it is a warping blot that jumps from place to place, each lurch sending out a hollow ping. It meddles with doors and snuffs out flames.",
		"hunting": "Hunts in sudden lurches rather than a steady glide — listen for the pings coming closer, each one a jump.",
		"strengths": ["Hard to read: it is never where it was a moment ago."],
		"weaknesses": ["Every movement pings — you can hear it coming.", "Placed crucifixes stop its hunts from starting.", "Holy water stuns it and ends a hunt."],
		"vanquish": ["Find the room it haunts.", "Place a crucifix in that room.", "Choose The Blightness as your suspect (Tab).", "Hold V inside its room to perform the Rite of Severance."],
	},
	"crawler": {
		"name": "The Crawler", "kind": "ghost", "token": "tokens/crawler.png",
		"evidence": ["freezing", "uv", "orbs"],
		"hunt_threshold": 52.0, "hunt_cooldown": 26.0, "hunt_duration": 15.0,
		"hunt_speed": 205.0, "roam_speed": 75.0, "interaction_interval": 10.0, "lair_bias": 0.7,
		"difficulty": 1.1, "rite": "holy_water", "rite_needs": ["holy_water"], "rite_name": "Rite of Drowning",
		"blurb": "A shadow that moves along the floor where no shadow should be.",
		"behaviour": "Slides across floors as a dark ripple, low and flat, rarely more than a smear in the corner of your eye. Basements suit it.",
		"hunting": "Hunts as a shadow on the floorboards. If it reaches you it rises out of the floor and drags you under — a wound, not a death, unless you are already hurt.",
		"strengths": ["Almost invisible while it hunts: look at the floor, not the air.", "Its grab staggers you and pulls you to it."],
		"weaknesses": ["Placed crucifixes stop its hunts from starting.", "Holy water stuns it and ends a hunt.", "Salt slows it while it hunts."],
		"vanquish": ["Find the room it haunts.", "Carry at least one flask of holy water.", "Choose The Crawler as your suspect (Tab).", "Hold V inside its room to perform the Rite of Drowning (it uses one flask)."],
	},
	"lost_one": {
		"name": "The Lost One", "kind": "ghost", "token": "tokens/lost_one.png",
		"evidence": ["emf5", "uv", "orbs"],
		"hunt_threshold": 62.0, "hunt_cooldown": 32.0, "hunt_duration": 12.0,
		"hunt_speed": 190.0, "roam_speed": 70.0, "interaction_interval": 11.0, "lair_bias": 0.75,
		"difficulty": 1.15, "rite": "rest", "rite_needs": ["ghost_book", "salt"], "rite_name": "Rite of Rest",
		"blurb": "A child who never left. It will not hurt you — unless you take what is theirs.",
		"behaviour": "Clings to one keepsake in the house — a music box, a locket or a little shoe. That object twitches on its own and plays a few notes of a lullaby when you come near.",
		"hunting": "Its ordinary hunts cannot wound you; it only frightens. But touch its keepsake and it manifests, hunting faster than anyone can run, and drags whoever it catches down to the basement furnace.",
		"strengths": ["Touching its keepsake brings a hunt you cannot outrun.", "Its furnace drag wounds — or kills the already wounded."],
		"weaknesses": ["Harmless while you leave its keepsake alone.", "Placed crucifixes stop its hunts from starting.", "Holy water stuns it and ends a hunt."],
		"vanquish": ["Find the room it haunts — and leave the twitching keepsake alone.", "Pour salt and lay the Ghost Writing Book in that room.", "Choose The Lost One as your suspect (Tab).", "Hold V inside its room to perform the Rite of Rest."],
	},
	"drowned_sailor": {
		"name": "The Drowned Sailor", "kind": "ghost", "token": "tokens/drowned_sailor.png",
		"evidence": ["freezing", "spirit_box", "writing"],
		"hunt_threshold": 56.0, "hunt_cooldown": 29.0, "hunt_duration": 14.0,
		"hunt_speed": 200.0, "roam_speed": 55.0, "interaction_interval": 10.0, "lair_bias": 0.6,
		"difficulty": 1.1, "rite": "tides", "rite_needs": ["salt", "holy_water"], "rite_name": "Rite of the Tides",
		"blurb": "An old sailor, still dripping from the sea that took him.",
		"behaviour": "Wanders slowly in a tattered pea coat, swaying like a deck in a swell. It leaves salt-water puddles and wet bare footprints behind it, timbers creak and water drips where it passes, and nearby lights stutter as it goes by. Sometimes you hear a far-off sea shanty whispered.",
		"hunting": "Hunts in waterlogged surges — heavy and slow, then a sudden lunge. It may rise out of one of its own puddles, so a wet floor is a warning. Never right beside you: it always emerges at a distance.",
		"strengths": ["Can appear from any puddle it has left in the house.", "Its surges close distance quickly."],
		"weaknesses": ["Puddles and wet footprints betray where it walks.", "Placed crucifixes stop its hunts from starting.", "Holy water stuns it and ends a hunt.", "Salt slows it while it hunts."],
		"vanquish": ["Find the room it haunts.", "Pour salt in that room and carry at least one flask of holy water.", "Choose The Drowned Sailor as your suspect (Tab).", "Hold V inside its room to perform the Rite of the Tides (it uses one flask)."],
	},
	"plague_doctor": {
		"name": "The Plague Doctor", "kind": "ghost", "token": "tokens/plague_doctor.png",
		"evidence": ["emf5", "freezing", "writing"],
		"hunt_threshold": 58.0, "hunt_cooldown": 30.0, "hunt_duration": 15.0,
		"hunt_speed": 185.0, "roam_speed": 50.0, "interaction_interval": 11.0, "lair_bias": 0.7,
		"difficulty": 1.15, "rite": "cleansing", "rite_needs": ["crucifix", "ghost_book"], "rite_name": "Rite of Cleansing",
		"blurb": "Beaked, robed and patient. It is still making its rounds.",
		"behaviour": "Walks with slow, deliberate steps, pausing as if to examine the room. You hear it before you see it: rasping breath through the beak and the clink of glass medicine bottles. It rarely shows itself.",
		"hunting": "Hunts slowly, but leaves a sickly green miasma in its wake. The clouds swell for a moment, linger, then thin away — stay in one too long and it wounds you.",
		"strengths": ["Its miasma closes corridors and rooms for a while.", "Silent while it wanders: only breath and glass give it away."],
		"weaknesses": ["The slowest hunter of all — distance saves you.", "Placed crucifixes stop its hunts from starting.", "Holy water stuns it and ends a hunt.", "Salt slows it while it hunts."],
		"vanquish": ["Find the room it haunts.", "Place a crucifix and lay the Ghost Writing Book in that room.", "Choose The Plague Doctor as your suspect (Tab).", "Hold V inside its room to perform the Rite of Cleansing."],
	},
	"weeper": {
		"name": "The Weeper", "kind": "ghost", "token": "tokens/weeper.png",
		"evidence": ["freezing", "spirit_box", "orbs"],
		"hunt_threshold": 57.0, "hunt_cooldown": 30.0, "hunt_duration": 14.0,
		"hunt_speed": 150.0, "roam_speed": 45.0, "interaction_interval": 11.0, "lair_bias": 0.75,
		"difficulty": 1.15, "rite": "solace", "rite_needs": ["salt", "crucifix"], "rite_name": "Rite of Solace",
		"blurb": "A hunched, veiled figure, sobbing into its hands.",
		"behaviour": "Its crying carries through the walls — you will hear it rooms away. It shuffles slowly, stopping often to weep, but come too close and it darts away faster than you can follow.",
		"hunting": "Hunts slowly and stops to sob even mid-hunt — until it is near you. Within a few strides it lunges faster than a sprint. Keep your distance; never let it get close.",
		"strengths": ["Terrifyingly fast at close range.", "Its sobbing hides where it really is."],
		"weaknesses": ["Slow at a distance, and it stops to cry.", "Placed crucifixes stop its hunts from starting.", "Holy water stuns it and ends a hunt.", "Salt slows it while it hunts."],
		"vanquish": ["Find the room it haunts.", "Pour salt and place a crucifix in that room.", "Choose The Weeper as your suspect (Tab).", "Hold V inside its room to perform the Rite of Solace."],
	},
	"mimic": {
		"name": "The Mimic", "kind": "ghost", "token": "tokens/mimic.png",
		"evidence": ["emf5", "spirit_box", "uv"],
		"hunt_threshold": 54.0, "hunt_cooldown": 28.0, "hunt_duration": 14.0,
		"hunt_speed": 210.0, "roam_speed": 75.0, "interaction_interval": 10.0, "lair_bias": 0.6,
		"difficulty": 1.2, "rite": "unmasking", "rite_needs": ["ghost_book", "holy_water"], "rite_name": "Rite of Unmasking",
		"blurb": "One of the residents is here twice. Only one of them is alive.",
		"behaviour": "Wears the face, the clothes and the name of a real occupant and goes about the house like them — so two of that person walk the halls. Now and then it moves wrongly, jerking or gliding, and its speech comes out garbled.",
		"hunting": "Drops the borrowed face when it hunts: a pale, hollow-eyed thing. It returns to the disguise afterwards.",
		"strengths": ["Hides in plain sight among the occupants.", "Ghost equipment is the only honest witness."],
		"weaknesses": ["Two people with the same name is a giveaway.", "Its speech glitches; its movement is unnatural.", "Placed crucifixes stop its hunts from starting.", "Holy water stuns it and ends a hunt."],
		"vanquish": ["Find the room it haunts.", "Lay the Ghost Writing Book there and carry holy water.", "Choose The Mimic as your suspect (Tab).", "Hold V inside its room to perform the Rite of Unmasking (it uses one flask)."],
	},
	"vampire": {
		"name": "Vampire", "kind": "physical", "token": "tokens/vampire.png",
		"evidence": ["bite_marks", "blood_drops", "coffin_soil"],
		"hunt_threshold": 52.0, "hunt_cooldown": 28.0, "hunt_duration": 14.0,
		"hunt_speed": 215.0, "roam_speed": 110.0, "interaction_interval": 9.0, "lair_bias": 0.35,
		"difficulty": 1.15,
		"blurb": "It stalks from the dark and strikes from behind.",
		"behaviour": "Drifts after the investigators, leaving blood droplets on the floor. Its resting room is strewn with grave soil, and sooner or later an occupant is bitten. When dread runs high a thick red mist fills the house.",
		"hunting": "Ambushes: its hunts begin behind you and out of your light.",
		"strengths": ["Ghost equipment is useless against it.", "Crucifixes and holy water have no power over it."],
		"weaknesses": ["Garlic carried in your kit repels and slows it at close range.", "With the wooden stake in hand you can counterattack the moment it reaches you.", "Shows as a dark silhouette when caught in your lantern's beam."],
		"vanquish": ["Find garlic (kitchens, pantries, dining rooms) and keep it in your kit.", "Find a wooden stake (sheds, cellars, studies).", "Strike it with the stake at close range."],
	},
	"werewolf": {
		"name": "Werewolf", "kind": "physical", "token": "tokens/werewolf.png",
		"evidence": ["claw_marks", "fur", "footprints"],
		"hunt_threshold": 45.0, "hunt_cooldown": 22.0, "hunt_duration": 15.0,
		"hunt_speed": 240.0, "roam_speed": 120.0, "interaction_interval": 7.0, "lair_bias": 0.45,
		"difficulty": 1.2,
		"blurb": "Relentless. Once it sees you, it runs you down.",
		"behaviour": "Walks the house as a rough, unshaven man until dread runs high: then the full moon breaks through and it tears into a wolf for good. Leaves heavy paw prints, sheds fur and gouges the walls of its den.",
		"hunting": "Hunts most often of all. As a wolf it accelerates while it can see you until it outruns a walking investigator. Only sprinting and breaking line of sight save you.",
		"strengths": ["Ghost equipment is useless against it.", "Crucifixes and holy water have no power over it.", "Gets faster the longer it sees you."],
		"weaknesses": ["Silver: with the silver stake in hand you can counterattack the moment it reaches you.", "Shows as a dark silhouette when caught in your lantern's beam."],
		"vanquish": ["Collect three pieces of silverware.", "Hold E or Space at a stove or hearth to melt them into a silver stake.", "Strike it with the silver stake at close range."],
	},
	"shapeshifter": {
		"name": "Shapeshifter", "kind": "physical", "token": "tokens/shapeshifter.png",
		"evidence": ["wrong_reflection", "shed_skin", "mimic_voice"],
		"hunt_threshold": 50.0, "hunt_cooldown": 25.0, "hunt_duration": 15.0,
		"hunt_speed": 215.0, "roam_speed": 100.0, "interaction_interval": 8.0, "lair_bias": 0.4,
		"difficulty": 1.3,
		"blurb": "It wears borrowed faces. None of them are its own.",
		"behaviour": "Changes its appearance — a person, a ghost, a vampire, a werewolf, or rarely a black cat. As a person it passes for one of the occupants. It mimics voices, sheds skin and its true form shows in mirrors it passes.",
		"hunting": "Takes a new shape for each hunt; its speed depends on the shape it wears. Its identity never changes.",
		"strengths": ["Its appearance is never its identity: weapons for the shape it wears do nothing.", "Ghost equipment is useless against it."],
		"weaknesses": ["Mirrors show its true form.", "Cold iron, once it is exposed."],
		"vanquish": ["Find a hand mirror (bathrooms, bedrooms).", "Find iron nails (sheds, cellars, studies, kitchens).", "Face it and hold click with the mirror to expose its true form (works even when it is unseen).", "While it is exposed, strike it with the iron nails."],
	},
	"harbinger": {
		"name": "The Harbinger", "kind": "harbinger", "token": "tokens/harbinger.png",
		"evidence": [],
		"hunt_threshold": 0.0, "hunt_cooldown": 14.0, "hunt_duration": 12.0,
		"hunt_speed": 228.0, "roam_speed": 90.0, "interaction_interval": 5.0, "lair_bias": 0.3,
		"difficulty": 1.25,
		"blurb": "Summoned by recklessness. It does not haunt. It hunts.",
		"behaviour": "Replaces the original entity after two reckless vanquishing attempts or three wrong ones. Everything found before it arrived is meaningless.",
		"hunting": "Begins hunting within seconds of arriving and hunts again every few seconds.",
		"strengths": ["Crucifixes cannot stop it.", "Leaves no evidence."],
		"weaknesses": ["Holy water stuns it briefly.", "Three sigil candles bind it in its room."],
		"vanquish": ["Find the three pale sigil candles and hold E or Space to light each one.", "When all three burn it is bound in its room and stops hunting.", "Stand beside it and hold V to perform the Final Rite."],
	},
}
const ORDINARY_CREATURES := ["shade", "poltergeist", "blightness", "crawler", "lost_one", "drowned_sailor", "plague_doctor", "weeper", "mimic", "vampire", "werewolf", "shapeshifter"]
const ENCYCLOPEDIA_ORDER := ["shade", "poltergeist", "blightness", "crawler", "lost_one", "drowned_sailor", "plague_doctor", "weeper", "mimic", "vampire", "werewolf", "shapeshifter", "harbinger"]
const SHAPESHIFTER_FORMS := ["human", "ghost", "vampire", "werewolf", "cat"]
const FORM_TOKENS := {
	"human": "tokens/occupant_d.png", "ghost": "tokens/shade.png", "vampire": "tokens/vampire.png",
	"werewolf": "tokens/werewolf.png", "cat": "tokens/cat.png", "true": "tokens/shapeshifter.png",
}
const FORM_SPEED := {"human": 205.0, "ghost": 200.0, "vampire": 215.0, "werewolf": 245.0, "cat": 150.0, "true": 210.0}

# --- Equipment ----------------------------------------------------------------
# Slot equipment (numbers 1-9). The lantern is a separate always-available toggle (F).
# Internal ids keep their original names; what the player sees is period kit.
const EQUIPMENT := {
	"emf": {"name": "Witch's Needle", "icon": "icons/eq_emf.png", "detector": true, "desc": "A dark needle sealed in a corked glass tube. It lies still in quiet rooms, twitches near a ghost's touch and taps the glass harder the stronger the presence. Some ghosts send it into a rattling frenzy (Needle 5)."},
	"thermometer": {"name": "Thermometer", "icon": "icons/eq_thermometer.png", "detector": true, "desc": "Shows the temperature of the room you stand in. Any entity's room runs cold; only some fall below freezing."},
	"uv": {"name": "Wraithlight Lantern", "icon": "icons/eq_uv.png", "detector": true, "desc": "A lantern of violet glass. Its light reveals handprints invisible in ordinary light. Sweep walls near disturbances."},
	"spirit_box": {"name": "Whisper Box", "icon": "icons/eq_spirit_box.png", "detector": true, "desc": "A wooden box with brass hinges and a lock. Open it to ask a question: near the right ghost, a voice may whisper back."},
	"ghost_book": {"name": "Ghost Writing Book", "icon": "icons/eq_ghost_book.png", "placeable": true, "desc": "Lay it down in the haunted room. Some ghosts write in it. Needed for the Rites of Binding, Rest and Cleansing."},
	"orb_camera": {"name": "Scrying Mirror", "icon": "icons/eq_orb_camera.png", "detector": true, "desc": "A black-glass mirror. Gaze through it to see ghost orbs drifting in a haunted room — invisible to the naked eye."},
	"salt": {"name": "Salt", "icon": "icons/eq_salt.png", "placeable": true, "charges": 3, "desc": "Pour a line (3 uses). Hunting ghosts that cross it are slowed. Needed for the Rites of Stillness, Rest and the Tides."},
	"crucifix": {"name": "Crucifix", "icon": "icons/eq_crucifix.png", "placeable": true, "charges": 2, "desc": "Place it near a ghost: it burns to stop a ghost hunt from starting (2 burns). Powerless against flesh and blood. Needed for the Rites of Severance and Cleansing."},
	"holy_water": {"name": "Holy Water", "icon": "icons/eq_holy_water.png", "charges": 3, "desc": "Splash a ghost to stun it and end its hunt; you are briefly blessed against a ghost's touch (3 flasks; the last never runs dry — it refills a few seconds after each splash). Useless against creatures of flesh and blood. The Rites of Drowning and the Tides each spend a flask."},
	# Resources found in the house (appear in the hotbar only once collected).
	"garlic": {"name": "Garlic", "icon": "icons/eq_garlic.png", "resource": true, "desc": "Found in kitchens and pantries. Carried, it repels and weakens a vampire at close range."},
	"wooden_stake": {"name": "Wooden Stake", "icon": "icons/eq_wooden_stake.png", "resource": true, "desc": "Found in sheds, cellars and studies. Strike at close range (garlic required)."},
	"silverware": {"name": "Silverware", "icon": "icons/eq_silverware.png", "resource": true, "desc": "Three pieces hide around dining rooms and kitchens. Melt them at a stove or hearth."},
	"silver_stake": {"name": "Silver Stake", "icon": "icons/eq_silver_stake.png", "resource": true, "desc": "Cast from melted silverware. Strike at close range."},
	"hand_mirror": {"name": "Hand Mirror", "icon": "icons/eq_hand_mirror.png", "resource": true, "desc": "Found in bathrooms and bedrooms. Hold click while facing something to see what it truly is."},
	"voodoo_doll": {"name": "Voodoo Doll", "icon": "icons/eq_voodoo_doll.png", "resource": true, "desc": "A pin-stuck burlap doll. Stab it (click) and something answers: flesh-and-blood creatures are enraged, and a ghost takes it out on whoever is nearest to hand. Use at your peril."},
	"iron_nails": {"name": "Iron Nails", "icon": "icons/eq_iron_nails.png", "resource": true, "desc": "Cold iron. Found in sheds, cellars, studies and kitchens. Strike at close range."},
}
const BASE_LOADOUT := ["emf", "thermometer", "uv", "spirit_box", "ghost_book", "orb_camera", "salt", "crucifix", "holy_water"]
const RESOURCE_ORDER := ["garlic", "wooden_stake", "silverware", "silver_stake", "hand_mirror", "iron_nails", "voodoo_doll"]
const SILVERWARE_NEEDED := 3

# Where resources are placed (room kinds, in preference order) and world sprite.
const RESOURCE_SPAWNS := {
	"garlic": {"kinds": ["kitchen", "pantry", "dining"], "count": 1, "sprite": "items/garlic.png"},
	"wooden_stake": {"kinds": ["shed", "cellar", "study", "living"], "count": 1, "sprite": "items/wooden_stake.png"},
	"silverware": {"kinds": ["dining", "kitchen", "pantry", "living", "study"], "count": 3, "sprite": "items/silverware.png"},
	"hand_mirror": {"kinds": ["bathroom", "bedroom"], "count": 1, "sprite": "items/hand_mirror.png"},
	"iron_nails": {"kinds": ["shed", "cellar", "study", "kitchen"], "count": 1, "sprite": "items/iron_nails.png"},
	"voodoo_doll": {"kinds": ["bedroom", "study", "cellar", "storage"], "count": 1, "sprite": "items/voodoo_doll.png"},
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
	# Revision 2: basements and neglect.
	"boiler": {"size": Vector2i(3, 2), "solid": true, "light": "furnace", "melt": true},
	"wine_rack": {"size": Vector2i(3, 1), "solid": true},
	"coal_pile": {"size": Vector2i(2, 2), "solid": true},
	"storage_shelf": {"size": Vector2i(3, 1), "solid": true},
	"covered_armchair": {"size": Vector2i(2, 2), "solid": true},
	"covered_sofa": {"size": Vector2i(4, 2), "solid": true},
	"broken_chair": {"size": Vector2i(1, 1), "solid": true},
	"old_trunk": {"size": Vector2i(2, 1), "solid": true},
	"water_tank": {"size": Vector2i(2, 2), "solid": true},
	"pipes": {"size": Vector2i(4, 1), "solid": false, "under": true},
	"boards": {"size": Vector2i(2, 1), "solid": false, "under": true},
	"debris": {"size": Vector2i(2, 2), "solid": false, "under": true},
	"desk_large": {"size": Vector2i(6, 4), "solid": true},
	# Revision 6: the inn and the harbour. Water is impassable, drawn under the actors
	# and never blocks sight; the boat hull is drawn over the water around its deck.
	"bar_counter": {"size": Vector2i(4, 1), "solid": true},
	"keg_rack": {"size": Vector2i(3, 1), "solid": true},
	"bollard": {"size": Vector2i(1, 1), "solid": true},
	"rope_coil": {"size": Vector2i(1, 1), "solid": true},
	"fishing_net": {"size": Vector2i(2, 2), "solid": false, "under": true},
	"water": {"size": Vector2i(2, 2), "solid": true, "under": true},
	"boat_hull": {"size": Vector2i(6, 14), "solid": false, "under": true},
}

static func evidence_name(id: String) -> String:
	return EVIDENCE.get(id, {}).get("name", id)

# --- Difficulty & match setup --------------------------------------------------
## Selectable difficulties, in menu order. Each names the base rule set it plays by;
## Hellbound and Abyssal build on Nightmare's and add their own events (Run:
## hellfire and hostility; portals and Abyssal Hell).
const DIFFICULTIES := ["beginner", "normal", "nightmare", "hellbound", "abyssal"]
const DIFFICULTY_INFO := {
	"beginner": {"name": "Beginner", "rules": "beginner", "desc": "A guided first investigation: tips as you go, and gentler hunts.",
		"tune": {"dread": 0.6, "grace": 2.0, "hunt_cooldown": 1.5, "hunt_speed": 0.85, "hunt_length": 0.7, "wound_grace": 1.6}},
	"normal": {"name": "Normal", "rules": "normal", "desc": "The suspect panel shows each entity's evidence and what it takes to vanquish it.",
		"tune": {}},
	"nightmare": {"name": "Nightmare", "rules": "nightmare", "desc": "Only a name and description on the suspect panel. Terrified occupants, vermin, blood and noises in the walls.",
		"tune": {"panic": 2.0}},
	"hellbound": {"name": "Hellbound", "rules": "nightmare", "hostile": "hellbound", "desc": "Nightmare, and the house itself turns hostile: dread surges, doors slam, flames die, hunts come back fast — and the floor erupts in hellfire.",
		"tune": {"panic": 2.6, "dread": 1.6, "grace": 0.6, "hunt_cooldown": 0.55, "haunt_every": 0.35}},
	"abyssal": {"name": "Abyssal", "rules": "nightmare", "hostile": "abyssal", "desc": "Nightmare, and reality tears: purple portals swallow whole rooms and drag everyone inside to a minute of traps in Abyssal Hell.",
		"tune": {"panic": 2.0}},
}
## "Random" difficulty never picks Beginner.
const RANDOM_DIFFICULTIES := ["normal", "nightmare", "hellbound", "abyssal"]
const BLOOD_MOON_CHANCE := 0.15

## The rule set a difficulty plays by ("beginner", "normal" or "nightmare").
static func rules(difficulty: String) -> String:
	return DIFFICULTY_INFO.get(difficulty, DIFFICULTY_INFO["normal"])["rules"]

## A difficulty's multiplier for one aspect of play (1.0 unless it changes it).
##   dread          how fast dread (threat) builds
##   grace          length of the calm opening before the first hunt can roll
##   hunt_cooldown  time before the entity may hunt again
##   hunt_speed     entity speed while hunting
##   hunt_length    how long a hunt lasts
##   wound_grace    invulnerability after a wound
##   panic          how strongly occupants (and a disguised shapeshifter) fear
##   haunt_every    time between the entity slamming doors / snuffing flames
static func tune(difficulty: String, key: String) -> float:
	return float(DIFFICULTY_INFO.get(difficulty, DIFFICULTY_INFO["normal"])["tune"].get(key, 1.0))

## "hellbound" or "abyssal" for the openly hostile difficulties, else "".
static func hostile(difficulty: String) -> String:
	return str(DIFFICULTY_INFO.get(difficulty, {}).get("hostile", ""))

static func difficulty_name(difficulty: String) -> String:
	return DIFFICULTY_INFO.get(difficulty, {}).get("name", difficulty.capitalize())

static func creature_name(id: String) -> String:
	return CREATURES.get(id, {}).get("name", id)

## A compact name for tight spots (the suspect strip): "Sailor", not "The Drowned Sailor".
const SHORT_NAMES := {"drowned_sailor": "Sailor", "plague_doctor": "Doctor", "shapeshifter": "Shifter"}

static func short_name(id: String) -> String:
	return SHORT_NAMES.get(id, creature_name(id).trim_prefix("The "))

## Whether entity `id` fits a journal: every evidence type found belongs to it and
## none it leaves has been ruled out. Uses only the player's own notes — never
## the hidden identity of the entity.
static func fits(id: String, journal) -> bool:
	var ev: Array = CREATURES.get(id, {}).get("evidence", [])
	for e in journal.active_entries():
		if not e["id"] in ev:
			return false
	for r in journal.ruled_out:
		if r in ev:
			return false
	return true

## The suspects a journal still allows, in roster order.
static func candidates(journal) -> Array:
	return ORDINARY_CREATURES.filter(func(id): return fits(id, journal))

## Floor texture -> footstep surface. Tiles ring like stone; carpets muffle wood.
## Any floor not listed (or a surface without recordings) uses the generic step.
const FLOOR_SURFACE := {
	"wood_dark": "wood", "wood_light": "wood", "parquet": "wood",
	"carpet_red": "carpet", "carpet_blue": "carpet", "carpet_green": "carpet",
	"stone": "stone", "tile_white": "stone", "tile_checker": "stone",
	"dirt": "dirt", "grass": "grass", "gravel": "gravel",
}

## The footstep cue for a floor texture ("footstep" when the surface is unknown).
static func footstep_cue(floor_texture: String) -> String:
	var s: String = FLOOR_SURFACE.get(floor_texture, "")
	return "footstep_" + s if s != "" else "footstep"

static func is_ghost(id: String) -> bool:
	return CREATURES.get(id, {}).get("kind", "") == "ghost"

## One-line vanquishing summary derived from the authoritative steps.
static func vanquish_summary(id: String) -> String:
	return " ".join(CREATURES.get(id, {}).get("vanquish", []))
