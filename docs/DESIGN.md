# SPECTRAL RUN — Implemented design reference

This documents how the approved design was implemented, including the minor
decisions made during development. **Contains spoilers.**

## Entities

| Entity | Kind | Evidence | Behaviour | Vanquish |
|---|---|---|---|---|
| The Shade | ghost | EMF 5, Freezing, Orbs | shy, stays in its room, silent hunts, slow (195) | **Rite of Stillness**: pour salt in the room you stand in, Tab → Shade, hold V in its room |
| The Poltergeist | ghost | Spirit Box, UV, Writing | throws things, roams, hunts often (225) | **Rite of Binding**: lay the Ghost Writing Book in the room, Tab → Poltergeist, hold V in its room |
| The Blightness | ghost | Needle 5, Whisper Box, Writing | a warping blot that lurches instead of gliding; every lurch pings (learn the sound) | **Rite of Severance**: place a crucifix in its room, Tab → Blightness, hold V there |
| The Crawler | ghost | Freezing, Handprints, Orbs | a dark ripple along the floor; on contact it rises and drags you to it — a wound, never an instant kill | **Rite of Drowning**: carry holy water (one flask is spent), Tab → Crawler, hold V in its room |
| The Lost One | ghost | Needle 5, Handprints, Orbs | its ordinary hunts cannot hurt. One of the three keepsakes (music box, locket, little shoe) — always the one in its room — twitches and hums a lullaby. Touch it and it hunts at 360 (faster than a sprint) and drags its catch to the basement furnace: a wound, or death if already wounded | **Rite of Rest**: salt and the Ghost Writing Book in its room, Tab → Lost One, hold V there |
| The Drowned Sailor | ghost | Freezing, Whisper Box, Ghost Writing | sways slowly, leaving wet footprints and salt-water puddles (atmosphere, not evidence; they dry up), drips, creaking timbers, a distant shanty; lights stutter as it passes. Hunts in surges (heavy steps, then a lunge) and may rise from one of its puddles — only ever one at least 300 px from every hunter | **Rite of the Tides**: salt in its room and holy water in hand (one flask is spent), Tab → Drowned Sailor, hold V there |
| The Plague Doctor | ghost | Needle 5, Freezing, Ghost Writing | slow, deliberate, pausing; raspy breathing and clinking bottles, rarely seen. Hunts at 185 (the slowest), dropping a miasma cloud every 3.2 s that swells over 1.6 s and fades after 9 s; 1.2 s inside one is a wound (4 s grace before another) | **Rite of Cleansing**: crucifix and Ghost Writing Book in its room, Tab → Plague Doctor, hold V there |
| The Weeper | ghost | Freezing, Whisper Box, Orbs | sobbing heard rooms away; slow (45 / hunts at 150) and stops to cry, even mid-hunt; darts away when approached and lunges at 330 within ~230 px | **Rite of Solace**: salt and a crucifix in its room, Tab → Weeper, hold V there |
| The Mimic | ghost | Needle 5, Whisper Box, Handprints | wears a real occupant's face and name (that resident walks the house twice), glitches in movement, garbled speech; its own pale face only while hunting (210) | **Rite of Unmasking**: Ghost Writing Book in its room, carry holy water (one flask is spent), Tab → Mimic, hold V there |
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

## The house fights back (revision 5)

* **Doors** (`HouseView.set_door`): most start closed (the same on every peer and in
  replays). A closed door blocks hunters, light and line of sight; walking into one
  pushes it open, [E] opens or closes it. Occupants and flesh-and-blood creatures
  open doors they pass; ghosts drift through. The entity swings doors (slamming them
  shut near hunters, never on someone standing in the doorway).
* **Flames** are living (`HouseView.Flame`): layered tongues that sway, with a glow
  that breathes. The entity snuffs flames and room lamps — always when a hunt
  begins — and a hunter relights them by holding [E].
* **Highlights**: a pulsing gold ring marks what [E] would act on, faint rings mark
  pickups close by. **Staircases** are two cells wide wherever the room allows.
* **Evidence shimmer**: when a phenomenon appears (needle frenzy, handprint, clue,
  writing, voice) the air of that room warps briefly — at most every 15 s per room,
  for any entity, so it says *something* is happening, never *what* it is.

## Period kit

The Witch's Needle (EMF reader, same thresholds: Level 5 = evidence), Wraithlight
Lantern (UV), Whisper Box (Spirit Box), Scrying Mirror (orb camera), Mercury
Thermometer and an oil lantern instead of a flashlight. Internal ids are unchanged.
The needle is drawn live in the information box: still at Level 1, twitching,
tapping, striking and finally rattling against the glass, with soft glass taps.

## Voodoo doll

Found like any other resource. Stabbing it (one use): a flesh-and-blood creature is
enraged (faster, hunts sooner and more often for 45 s, +25 dread); a ghost makes a
random occupant scream and burn, leaving embers that wound a hunter who walks into
them (4 s grace between burns; two wounds kill as always) for 25 s, then ashes.
With no occupant left, the ghost turns on the stabber instead. Uses are recorded in
the replay and statistics.

## Game setup (Normal / Custom), difficulties and Blood Moon

* **Normal Game:** house, entity and Blood Moon (15 %) are rolled; the player picks
  the difficulty, or Random (Normal / Nightmare / Hellbound / Abyssal — never Beginner).
* **Custom Game:** house, entity, difficulty and Blood Moon (On / Off / Random), each
  fixed or random. Same form (`SetupForm`) for solo and the multiplayer host.
* Everything random is resolved once (`Game.resolve_setup`) — on the host in
  multiplayer; a random entity is rolled by the run itself and never sent to clients.
  A rolled difficulty and a Blood Moon are announced at the start; the entity never is.
* **Hellbound / Abyssal** play by Nightmare's rules for now (`Defs.DIFFICULTY_INFO[...]
  ["rules"]`), with their own names and personal records.
* **Blood Moon** is atmosphere only: red, slowly breathing moonlight, a faint red
  cast over the house and a red moon beside the hearts. It coexists with the
  werewolf's full moon (which stays red) and the vampire's mist. Stored in replays.

## Hellbound and Abyssal

Both keep Nightmare's base (text-only suspect panel, critters, blood, terrified
occupants) and add their own identity. Recorded evidence stays truthful.

* **Hellbound — the house is hostile.** Dread rises 1.6× faster, the grace period is
  shorter, hunts return in ~half the time, the entity slams doors / snuffs flames /
  rattles furniture every 4–9 s, occupants panic harder (fear 2.6), and starting a
  rite is answered with fire and a surge of dread. **Hellfire** every 8–14 s near a
  hunter: a red glowing circle for 1.6 s, then flames for 3.5 s that wound anyone in
  them (4 s grace, two-wound rule).
* **Abyssal — reality tears.** A violet cast and drifting purple ripples. Every
  80–120 s (first after ~50 s) a **portal** picks a room (usually one a hunter is in):
  a pulsing violet veil and a spinning tear for 2.5 s, then everyone in that room —
  hunters, occupants and the entity — is pulled to **Abyssal Hell** (`AbyssArena`)
  for 60 s. It has spike tiles (0.9 s warning), sweeping hellfire lanes (1 s warning)
  and three grasping shadow hands; each hit is a wound. Survivors return to the room
  they were taken from; the entity and occupants return too. Hunters elsewhere play on.
  The trap timeline is a function of the portal's seed and time, so host, clients
  and replays draw the same traps; only the host deals damage.
* Replays record hellfire, portals, pulls, returns and wounds by source; results
  count hellfire burns and abyss trips / escapes (scoring unchanged).

## Playtesting refinements

* **Blightness** moves in rushes: it picks the furthest point of its path it can
  reach in a straight, clear line (≤ 140 px roaming, 200 px hunting), launches at
  430 / 640 px/s, slams to a stop and shudders for ~0.5 s, then picks the next line.
  Every hunting rush pings. Walls and furniture stop a rush dead; it never steers.
* **Safe Names** (Settings, default ON): original names. OFF swaps occupants and the
  offline legends for recognisable fictional characters (private use only). Names
  are display-only over stable ids (`name_id`, legend `id`); personalities, scores
  and saves are unaffected. Each multiplayer player sees names per their own setting.
* **Temperatures**: outdoors 12–14.5 °C, ordinary rooms 12.5–15 °C; the entity's
  room 4–8 °C, below zero only for freezing ghosts.
* **Always Show Ghost Marker** (setup, default Off; solo always, matches in Custom
  Game): a marker above the entity, red while it hunts. Visual only.
* **Ruled-out evidence**: right-click an evidence icon to mark it ruled out (red
  cross) and again to restore it. A local, unscored deduction; finding it later
  makes it Found. Entities contradicted by a ruled-out type are crossed in the
  SUSPECTED list but stay selectable.

## Beginner Mode

A guided first investigation (`scripts/game/beginner_guide.gd`): one-off tips
appear in a parchment note on the left as things become relevant — each tool
the first time it is held, the first evidence, which entities still fit what
has been found, how to vanquish the chosen suspect and which items are still
missing, the first hunt and the first wound. Danger is gentler: dread builds at
60 %, no hunts for the first 80 s, hunts are 15 % slower, 30 % shorter and come
50 % less often, with longer invulnerability after a hit. Controls and rules
are otherwise unchanged; records are kept separately and are not submitted
online.

## Replay moments

The looping results replay shows short popups (icon + one line, at most two at
once) for evidence found, wounds, deaths, hunts, crucifix saves, wrong or
incomplete attempts, fleeing occupants, shapeshifter changes, the Harbinger and
the vanquishing — read only from the recorded events, never from live logic.

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

## Home rooms (0.11.0)

Every entity lives in a home room (its lair). Ordinary wandering is short
excursions into one or two neighbouring rooms, then back home to settle for
15–30 s (longer for stronger homebodies). Hunts and pursuit ignore this and reach
any floor or the outdoors. A home room can change at most twice per run (first
check at 100–160 s with a 50 % chance, a second 90–140 s later at 30 %; never for
the Lost One). The cold and the orbs move with it; "The haunting has shifted…" is
shown, the room is not. Passive dread runs at 80 % of the old rate (0.176/s).

