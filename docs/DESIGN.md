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

## Identification

Every entity — including the vampire, werewolf and shapeshifter — can be chosen
as the suspect at any time with Tab / Shift+Tab, with zero, one, two or three
clues. The encyclopedia (main menu) openly describes all of them. Only the
evidence *journal* keeps its rule: hidden evidence types are never listed until
you actually find one.

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
* Shown as the EVIDENCE panel (top-right): every evidence type is listed from
  the start, greyed until discovered, then gold. The rest of the HUD sits on the
  edges too — EQUIPMENT top-left, readings / time / health top-centre, the
  SUSPECTED panel bottom-centre — keeping the centre of the screen clear.

## Nightmare Mode

Chosen on the house screen (solo) or by the host in the lobby. Scoring rules
are unchanged, but personal bests are kept separately and Nightmare runs are
not sent to the global leaderboard.

* The SUSPECTED panel shows only the entity's name and description — no
  evidence or requirement icons.
* Occupants are terrified (`fear` 2.0): they talk and react more, panic-run
  between rooms, have fits of distress and use frightened lines.
* Strange noises (knocks, dragging, creaks, distant screams) every 7–16 s,
  which the occupants react to. Old blood in every room.
* Spiders, cockroaches and rats (`scripts/game/critters.gd`), more of them in
  neglected rooms and basements, at most 36. Step on one and it dies with a
  crunch and a little blood. They have no gameplay effect and are simulated
  locally on each machine.

## Basements

Every house has a basement (root cellar, wine vaults, farm cellar, ossuary ring,
coal vault) with internal loops and two connections to the main floor
(staircases or hatches). Stepping onto a stair tile takes you to the landing on
the other floor. Floors are laid out apart in the same world, so they never
share walls, light or line of sight; paths for the entity and occupants include
the staircase jump. Basement rooms are rooms like any other (names, evidence,
resources, lairs). The view is darker and the ambience deeper while you are below.

## Neglect

Each room has a condition — kept, worn, neglected or abandoned — that tints the
floor and layers grime, damp and cracks plus stains, cobwebs, peeling paper and
litter. These are placed deterministically per house, away from doorways and
stairs, on a layer beneath items and evidence, so they never hide anything that
matters.

## Occupants

Occupants have names (shown under them; can be hidden in Settings) and one of
five personalities — nervous, skeptical, curious, dramatic, calm — which nudges
their walking pace, idling, chatter frequency and how they react to bangs and
rattles (the curious go to look). The shapeshifter's human form uses the same
name tag and an unused occupant look and talks like a person with a personality
of its own; only its behaviour and the evidence give it away.

## Competitive multiplayer

See `docs/MULTIPLAYER.md` and the competitive section of `docs/SCORING.md`.

## Analytics

`SaveData` keeps per-house/per-entity runs, wins, losses, average/best times,
best score, evidence found, discovery rooms and average first-find times,
correct/incorrect identifications, blind wins, wounds, transformations and
Harbinger encounters, plus the last 60 runs. The DEV STATISTICS screen shows
them. Statistics are never read by gameplay: creature choice is uniform from
the run seed.
