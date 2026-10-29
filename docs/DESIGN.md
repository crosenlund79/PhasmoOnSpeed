# SPECTRAL RUN — Implemented design reference

This documents how the approved design was implemented, including the minor
decisions made during development. **Contains spoilers.**

## Entities

| Entity | Kind | Evidence | Behaviour | Vanquish |
|---|---|---|---|---|
| The Shade | ghost | EMF 5, Freezing, Orbs | shy, stays in its room, silent hunts, slow (195) | **Rite of Stillness**: pour salt in the room you stand in, Tab → Shade, hold V in its room |
| The Poltergeist | ghost | Spirit Box, UV, Writing | throws things, roams, hunts often (225) | **Rite of Binding**: lay the Ghost Writing Book in the room, Tab → Poltergeist, hold V in its room |
| Vampire | physical (hidden) | Bite Marks, Blood Droplets, Grave Soil | stalks the investigator, ambushes from behind and out of the light | carry **garlic** (weakens and repels it when close) and strike with a **wooden stake** |
| Werewolf | physical (hidden) | Claw Marks, Shed Fur, Unusual Footprints | relentless pursuit, accelerates while it sees you (240→288) | collect **3 silverware**, hold E at a stove or hearth to cast a **silver stake**, strike |
| Shapeshifter | physical (hidden) | Wrong Reflection, Shed Skin, Mimicked Voice | changes appearance (human, ghost, vampire, werewolf, rarely a cat); identity never changes | **expose** it with the **hand mirror** (hold click while facing it — works even when it is unseen), then strike with **iron nails** while exposed |
| The Harbinger | special | none | replaces the entity after recklessness; hunts within seconds and every ~14 s | light **three sigil candles** (hold E) → it is bound in its room → hold V beside it (Final Rite) |

* Conventional equipment does nothing useful against physical entities: no EMF,
  no orbs, no spirit-box answers; crucifixes don't stop their hunts; holy water
  doesn't make them flinch. A cold room (4–8 °C) still marks any entity's lair,
  but only a ghost with Freezing drops below zero.
* Physical entities show up as a dark **silhouette** when caught in the
  flashlight beam while roaming, and fully during hunts.
* Mirrors: every house has at least two wall mirrors. The shapeshifter's true
  form appears in a mirror it passes (Wrong Reflection).

## Attempting to vanquish

Selecting a suspect (Tab) is never an attempt. An attempt happens only when a
rite is completed (V) or a stake/nails strike lands within reach of the entity.
Strikes at empty air are not attempts.

| Outcome | Effect |
|---|---|
| Correct | Victory. If no evidence was found and no meaningful investigation happened: *"The house falls silent… then something laughs."* (Audacity, recorded) |
| Right identity, preparation incomplete (rite outside its room, unexposed shapeshifter) | dread +10, −250 points |
| Wrong, after meaningful investigation | dread +20, flicker, "Something in the house is angered." |
| Wrong, without meaningful investigation | **severe reaction**: occupants flee, *"THE HOUSE NOTICED — the madness deepens"*, dread +40, a hunt is forced 5 s later |
| 2 reckless attempts, or 3 wrong attempts in total | **The Harbinger** replaces the entity |

Meaningful investigation = at least 4 points: 1 per (room, detector) pair used
for 2 s, 1 per placed item / spirit-box question / melt, 3 per evidence found.
Flashlight toggling and equipment swapping never count.

### Harbinger replacement

Unmistakable: tolling arrival sound, house darkens, heavy flicker and screen
shake, full-width message. All journal entries are voided ("Prior presence —
N records disregarded"), every phenomenon of the old entity is removed, and the
old entity's evidence types are no longer accepted.

## Threat (dread) and hunts

* Dread rises 0.22/s plus: evidence +4, spirit-box question in its room +2,
  placing items in its room +1, failed attempts as above; each hunt −25,
  crucifix burn −15.
* No ordinary hunts in the first 40 s. When dread ≥ the entity's threshold a
  hunt is rolled every 2 s. Hunts have a 2.5 s warning, start ≥ 300 px from the
  investigator, and last 12–16 s. A hunt ends immediately after it wounds you.
* Crucifix: placed item with 2 burns; prevents a ghost hunt starting within
  150 px. Holy water: 3 splashes; stuns a ghost and ends its hunt, plus a 3 s
  blessing that repels a ghost's touch. Salt slows a hunting ghost that crosses it.
* Occupants flee on the first hunt, a severe reaction, or the Harbinger.

## Journal

* Records only genuine discoveries produced by the current entity's
  phenomena, through observation (in range, line of sight, lit) or equipment.
* First discovery per type keeps its time and the room where it **occurred**
  (the hotspot's / clue's room; the thermometer's room; the voice's source).
  Every occurrence is also stored for analytics.
* Pencil-scribble sound + one small toast per new entry; duplicates are silent.
* Fixed width (288 px at 1600×900), discovered list scrolls and auto-scrolls to
  the newest; the unconfirmed list is a single wrapped line.

## Multiplayer boundaries (not implemented)

* Every actor has a stable id (`player_1`, `creature_1`, `npc_N`) used by the
  replay; per-player state (wounds, inventory, stamina) lives on `Player`.
* `Run` owns authoritative state (time, dread, attempts, journal) and resolves
  every gameplay decision through methods (`discover`, `attempt_vanquish`,
  `on_creature_contact`, `place_item`, `strike`) that a future network layer
  can call on the host.
* Creature targeting uses `run.player`; supporting several players means
  choosing the nearest visible player there and in `Phenomena._observe`.

## Analytics

`SaveData` keeps per-house/per-entity runs, wins, losses, average/best times,
best score, evidence found, discovery rooms and average first-find times,
correct/incorrect identifications, blind wins, wounds, transformations and
Harbinger encounters, plus the last 60 runs. The DEV STATISTICS screen shows
them. Statistics are never read by gameplay: creature choice is uniform from
the run seed.
