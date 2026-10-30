# SPECTRAL RUN — Consolidation report (v0.10.0)

A quality pass over everything built so far: audit, fix, light polish, Windows
installer. No new evidence types or entities.

## What the repository actually contains

- **Entities (11):** Shade, Poltergeist, Blightness, Crawler, Lost One, Drowned
  Sailor, Plague Doctor (ghosts); Vampire, Werewolf, Shapeshifter (flesh and blood);
  the Harbinger. *Weeper and Mimic do not exist* (only the `mimic_voice` evidence).
- **Locations (5):** Ashgrove, Blackwood, Hollow Lane, Evangeline, Marrow Street,
  each with a basement. *There is no Tavern or Harbor.*
- **Difficulties (5):** Beginner, Normal, Nightmare, Hellbound, Abyssal.
- One scene (`scenes/boot.tscn`); every script is in use.

## Problems found and fixed

**Abyssal portal lifecycle** (the largest cluster)
- The entity "in the Abyss" was only hidden in its house room. It could still be
  struck, stunned, bound by a rite, or reached by the voodoo doll, and it kept
  slamming doors. A forced hunt (doll, recklessness, the Lost One's keepsake) could
  start while it was away: a frozen hunt that resumed on top of the returning hunters.
  → Occupants and the entity are now physically moved into the realm, visibly drifting
  at its far end and unable to act. Forced hunts wait. Strikes, rites, holy water, the
  doll and item placement all refuse across the portal.
- A victory, death, wipe or disconnect during the event left the realm open, and in
  the replay too. → Every ending closes the Abyss first.
- Occupants burned while away reappeared standing. Returning occupants lost their
  speech bubbles. → Fixed.
- Replays drew the traps at 1× while the replay ran at 4×. → The trap timeline follows
  replay time.

**Hunts, scoring, multiplayer**
- A vanquish during a hunt (every counterattack, for example) banished the entity
  before ending the hunt. No `hunt_end` was recorded, the HUD stayed in hunt mode, and
  survivors lost their clean-hunt credit. → End the hunt, then banish.
- Wounds taken outside hunts (hellfire, embers, miasma, traps) cancelled the next
  hunt's clean-hunt credit. Hunters away in the Abyss were credited for hunts in the
  house. → Both fixed.
- Multiplayer clients kept the house ambience and the hunt loop playing into the
  results screen and lobby. → Leaving any investigation stops its loops.
- The Harbinger's arrival didn't clear a shapeshifter reflection on clients. → Fixed.

**Audio**
- Restarting a run (or a hunt resuming within a loop's fade-out) was silenced by the
  old fade's late `stop()`. → One cancellable fade per loop.

**Lighting**
- Four independent tweens animated the same darkness colour. An older, longer one
  (the hunt fade) could finish last and leave a stale tint over the mood, Blood Moon,
  basement or hostile layers. → One fade at a time toward the composed colour.
- Snuffed flames kept a zero-energy, shadow-casting light enabled. → Disabled once
  dark.

**Investigation and UI**
- The SUSPECTED panel lit a ghost's rite items from the first second, because they
  are always in the kit. The Beginner guide said "ready to vanquish" just as early.
  → They light up when actually prepared (laid, poured, still carrying holy water),
  and ghost requirements now come from the rite's own `rite_needs`.
- "Holy water in hand" was wrong: carrying it is enough. Equipment descriptions named
  only one rite each. Modern slips ("the box that beeps", cars, a dry cleaner) were
  scattered through the text. The Thermometer had two names. → All corrected.
- "Drowned Sail…" was clipped in the suspect strip. → Short names (Sailor, Doctor,
  Shifter).
- At large Menu UI scale, the encyclopedia list, Settings, Stats and Rankings ran
  off-screen. → Scrolling and fitted widths. The in-run pause, Controls and
  match-paused panels now follow the Gameplay UI scale.
- The Lantern was missing from the encyclopedia. → Added. The multiplayer results
  replay was framed under the panel. → Re-centred.

**Robustness**
- A future location without a stove, hearth or furnace would make the werewolf
  unbeatable. → A ready silver stake is placed instead. The house test now requires a
  melt station and a furnace.
- A scene-tree timer could fire after a run was freed (the "lambda capture was freed"
  error). → Bound to the run.
- The multiplayer test's shove check had failed since doors stopped opening on
  contact: it shoved a client into the door it had walked up to. → The test pushes
  toward open floor. The shove itself was fine.

## Consolidated
- **Difficulty rules:** one table, `Defs.DIFFICULTY_INFO[..]["tune"]` plus
  `Defs.tune()` / `Defs.hostile()`, replaces about 15 scattered special cases. Values
  are unchanged. Hellbound and Abyssal keep Nightmare's base rules plus their own
  events.
- **Requirements:** one `Player.has_prepared()` is used by both the HUD and the
  Beginner guide, on the host and on clients.
- Removed five functions nothing called.

## Small polish
- **Grandfather clock:** the clock nearest the entity ticks, tolls once and stops as
  a hunt is about to break loose (new cue `clock_toll`). This is the anticipation
  sound.
- **Phantom footsteps:** a few paces behind a hunter once dread builds (not on
  Beginner).
- **Furniture:** when the entity's door/flame meddling finds nothing to act on, nearby
  furniture rattles instead.

## Verification
- Project loads with no script errors. The exported `.pck` boots cleanly.
- Unit tests 46/46. New regressions cover the Abyss edge cases and this pass.
- Bot playtest 50/50: every entity in every house, including multi-floor routes.
- Multiplayer: full (4 hunters), drop, pause, setup and abyss scenarios all OK.
- Performance (headless): about 0.8–1.5 ms of script time per frame across entities
  and difficulties, including hunts, hellfire and portals.

## Windows build
`tools/installer/build_installer.sh` exports and packs
`export/installer/SpectralRun-Setup-<version>.exe` (not committed).

- **Install:** per-user, into `%LOCALAPPDATA%\Programs\SpectralRun`.
- **Updates:** a newer installer updates the same folder through its registry key, and
  waits for the game to be closed.
- **Saves:** `%APPDATA%\Godot\app_userdata\SPECTRAL RUN` is never touched.

## Known issues / later
- The installer was built and the pack booted on Linux. The installer itself has not
  been run on a real Windows machine.
- The .exe keeps Godot's default icon and version resources. Setting them needs
  `rcedit` and `application/modify_resources`.
- No haunted portraits: the houses have none. Adding them means new furniture art.
- Toasts and big announcements don't follow the Gameplay UI scale (panels do).
- On the results screens, Menu UI scale also zooms the replay world.
- In replays, hellfire warnings and flames play at real speed while the replay runs
  at 4×, so they linger slightly.
- Occupants in the Abyss are inert (never hurt by traps). The entity there is inert by
  design.
- The Harbinger, once bound by its sigils, is never pulled into the Abyss.
