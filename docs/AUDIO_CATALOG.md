# SPECTRAL RUN — Audio Catalog

Every sound the game can play, where a replacement goes, and what is still
missing. The code-side list lives in `scripts/core/audio_catalog.gd`
(`AudioCatalog.CUES`); a test keeps it and this document in step.

**Summary (current build)**

| | |
|---|---|
| Sound cues in the catalog | **56** |
| …triggered by the game | **51** |
| …generated but currently never triggered | **5** (`camera_shutter`, `cat_meow`, `emf_beep`, `emf_spike`, `thermometer_tick`) |
| Cues using generated placeholder audio | **56 of 56** — all made by `tools/audio/generate_audio.py` |
| Cues with creator (original) audio | **0** so far |
| Suggested missing sounds | **24** (see the end) |

## Replacing a sound (creator workflow)

1. Find the sound below and note its **Creator file**.
2. Save your audio there, with exactly that name, under
   `res://assets/creator/audio/` (on disk: `assets/creator/audio/` in the project).
   The listed format (`.wav` for short effects, `.ogg` for ambience and loops) is
   looked for first; the other format with the same name is accepted too.
3. Relaunch the game. That's all — no scripts, scenes or resources to edit.
   (Opening the project in the Godot editor, or `tools/dev.sh import`, imports the
   file properly; un-imported plain PCM `.wav` and `.ogg` files are also read
   directly, so a relaunch is enough while developing.)
4. To ship it, export as usual: imported creator files go into the export
   (preset **Windows Desktop** in `export_presets.cfg`).

**Restore the placeholder:** delete your file (and its `.import` file, if the editor
made one) and relaunch. The generated sound in `assets/audio/` is never removed.

**Variants (optional):** add `<name>_01.wav` … `<name>_08.wav` next to (or instead
of) `<name>.wav`; one is picked at random each time the sound plays. Loops always
use their first file. One file is always enough.

**What a replacement does not change:** when and why a sound plays, looping,
volume and per-sound gain, the bus, positional placement and distance falloff,
pitch randomisation, cooldowns and what other players hear. Trim silence from the
start of one-shots — playback starts immediately. Loops should be seamless.

**Formats:** 44.1 kHz WAV (16-bit PCM) for effects, OGG Vorbis for ambience/music.
Lookup order per cue: `<name>.<listed format>`, `<name>.<other format>`, then
`<name>_01…_08` in the same order. If nothing is found the placeholder plays; if the
placeholder were missing too the game simply stays silent for that cue.

**Behaviour key:** *one-shot* = plays once, everyone in range or only you as noted ·
*positional* = placed in the world, fades with distance (`AudioStreamPlayer2D`) ·
*2D/UI* = not positional · *loop* = continuous until stopped · *private* = only the
hunter it concerns hears it (in multiplayer too).

Status in every row below: **Existing placeholder** (generated) unless marked.

---

## Player — `res://assets/creator/audio/player/`

| ID | Name | Creator file | Trigger | Behavior | Priority | Notes |
|---|---|---|---|---|---|---|
| `footstep` | Footstep on boards | `player/footstep.wav` | Every ~0.32 s while you move (faster sprinting); taking stairs; one of the Nightmare noises | one-shot, 2D, pitch-randomised, private | Essential | Ideal for **variants** (`footstep_01…`). Rivals' footsteps are not played. |
| `player_hurt` | You are wounded | `player/hurt.wav` | First wound from the entity, embers or the furnace | one-shot, private | Essential | |
| `player_death` | You perish | `player/death.wav` | Second wound | one-shot, private | Essential | |
| `pickup` | Pick up / retrieve | `player/pickup.wav` | Picking up a resource; retrieving your book or crucifix | one-shot, private | Desirable | |
| `place_item` | Lay an item down | `player/place_item.wav` | Placing the book, salt or crucifix | one-shot, positional | Desirable | |

## Equipment — `res://assets/creator/audio/equipment/`

| ID | Name | Creator file | Trigger | Behavior | Priority | Notes |
|---|---|---|---|---|---|---|
| `flashlight_click` | Lantern shutter | `equipment/lantern_shutter.wav` | F opens / shutters the lantern | one-shot, private | Desirable | Id kept from the old flashlight. |
| `needle_tap` | Witch's Needle on glass | `equipment/witch_needle_tap.wav` | Repeatedly while the Needle reads ≥ 2 — faster and louder with the reading; rapid at Level 5 | one-shot, private, pitch-randomised | Essential | Keep it tiny and soft — it repeats up to ~14×/s. Variants work well. |
| `spirit_box_static` | Whisper Box hiss | `equipment/whisper_box_hiss.ogg` | While the Whisper Box is open and listening (~1.6 s) | **loop**, 2D, private | Essential | Id kept from the old Spirit Box. Must loop seamlessly. |
| `spirit_box_voice` | Whisper Box answers | `equipment/whisper_box_voice.wav` | The box gets a response (evidence) | one-shot, positional | Essential | |
| `mirror_reveal` | Mirror shimmer | `equipment/mirror_shimmer.wav` | Gazing into the Scrying Mirror (soft); hand mirror look; shapeshifter exposed (loud) | one-shot, private / positional | Desirable | Shared by both mirrors. |
| `salt_pour` | Salt poured | `equipment/salt_pour.wav` | Pouring a salt line | one-shot, positional | Desirable | |
| `holy_water_splash` | Holy water splash | `equipment/holy_water_splash.wav` | Splashing holy water | one-shot, positional | Desirable | |
| `crucifix_burn` | Crucifix flares | `equipment/crucifix_burn.wav` | A crucifix stops a hunt; a blessing repels a ghost; the Harbinger is stunned | one-shot, positional | Desirable | |
| `stake_strike` | Stake / nails strike | `equipment/stake_strike.wav` | Striking with a stake or nails; counterattack (loud, low); stabbing the voodoo doll (high); shoving a rival (high) | one-shot, positional | Essential | One sound, four uses via pitch. |
| `melt_silver` | Silver melting | `equipment/melt_silver.wav` | Casting the silver stake at a stove/hearth | one-shot, positional | Optional | |
| `camera_shutter` | Camera shutter | `equipment/camera_shutter.wav` | **Not triggered** (the orb camera became the Scrying Mirror) | — | Optional | Unused placeholder. |
| `emf_beep` | EMF beep | `equipment/emf_beep.wav` | **Not triggered** (replaced by `needle_tap`) | — | Optional | Unused placeholder. |
| `emf_spike` | EMF spike | `equipment/emf_spike.wav` | **Not triggered** | — | Optional | Unused placeholder. |
| `thermometer_tick` | Thermometer tick | `equipment/thermometer_tick.wav` | **Not triggered** | — | Optional | Unused placeholder. |

## Evidence & journal — `res://assets/creator/audio/evidence/`

| ID | Name | Creator file | Trigger | Behavior | Priority | Notes |
|---|---|---|---|---|---|---|
| `pencil_scribble` | Journal pencil | `evidence/journal_write.wav` | A new journal entry; a Beginner Mode tip appears (soft) | one-shot, 2D, private | Essential | The "evidence recorded" signature sound. |
| `whisper_mimic` | Mimicked voice | `evidence/mimic_voice.wav` | The shapeshifter imitates an occupant (evidence) | one-shot, positional | Essential | |

## Entities — `res://assets/creator/audio/entities/`

| ID | Name | Creator file | Trigger | Behavior | Priority | Notes |
|---|---|---|---|---|---|---|
| `hunt_start` | A hunt begins | `entities/hunt_start.wav` | Every hunt (with the flicker) | one-shot, 2D, everyone | Essential | |
| `hunt_loop` | Hunt drone | `entities/hunt_loop.ogg` | For the whole hunt | **loop**, 2D | Essential | Seamless loop. |
| `ghost_wail` | Ghost wail | `entities/ghost_wail.wav` | Shade / Poltergeist / Lost One (wrath) hunt; an incomplete rite | one-shot, positional | Essential | |
| `poltergeist_bang` | Poltergeist bang | `entities/poltergeist_bang.wav` | Poltergeist interactions | one-shot, positional | Desirable | |
| `vampire_hiss` | Vampire hiss | `entities/vampire_hiss.wav` | Vampire hunt; repelled by garlic; enraged by the doll | one-shot, positional | Essential | |
| `werewolf_howl` | Werewolf howl | `entities/werewolf_howl.wav` | Werewolf hunt; the full moon transformation | one-shot, positional | Essential | |
| `werewolf_growl` | Werewolf growl | `entities/werewolf_growl.wav` | End of the transformation; enraged by the doll | one-shot, positional | Desirable | |
| `shapeshift` | Shapeshift | `entities/shapeshift.wav` | Shapeshifter changes form during a hunt; iron fails on borrowed skin | one-shot, positional | Desirable | |
| `cat_meow` | Cat | `entities/cat_meow.wav` | **Not triggered** | — | Optional | Could voice the shapeshifter's cat form. |
| `harbinger_arrival` | The Harbinger | `entities/harbinger_arrival.wav` | The Harbinger is summoned; all three sigils lit (low) | one-shot, 2D, everyone | Essential | |
| `blight_ping` | Blightness ping | `entities/blightness_ping.wav` | Every Blightness lurch while hunting (and every second lurch while roaming); its hunt start | one-shot, positional | Essential | The tell players learn — keep it distinctive. |
| `crawl_drag` | Crawler drag | `entities/crawler_drag.wav` | Crawler hunt start; its grab; the Lost One's furnace drag | one-shot, positional | Essential | |
| `music_box` | Lost One's lullaby | `entities/lost_one_music_box.wav` | Its keepsake twitches near a hunter; Lost One hunt start | one-shot, positional | Essential | |
| `reckless_reaction` | The house is angered | `entities/reckless_reaction.wav` | Wrong / reckless attempts; doll on a non-standard creature | one-shot, 2D | Desirable | |
| `vanquish_success` | Vanquished | `entities/vanquish.wav` | The entity is vanquished | one-shot, 2D | Essential | |

## Environment & supernatural events — `res://assets/creator/audio/environment/`

| ID | Name | Creator file | Trigger | Behavior | Priority | Notes |
|---|---|---|---|---|---|---|
| `door_creak` | Door creak | `environment/door_creak.wav` | Opening/closing a door; ghost interactions; Nightmare noises | one-shot, positional | Essential | Variants recommended. |
| `door_slam` | Door slam | `environment/door_slam.wav` | The entity slams a door shut | one-shot, positional | Essential | |
| `candle_light` | Flame catches | `environment/flame_light.wav` | Relighting a flame; lighting a sigil candle | one-shot, positional | Desirable | |
| `flame_snuff` | Flame snuffed | `environment/flame_snuff.wav` | The entity puts a flame out | one-shot, positional | Desirable | |
| `ignite` | Supernatural fire | `environment/supernatural_ignite.wav` | Voodoo doll burns an occupant; walking into embers (high) | one-shot, positional | Essential | |
| `furnace_roar` | Furnace roar | `environment/furnace_roar.wav` | The Lost One's furnace sequence | one-shot, positional | Essential | |
| `nm_knock` | Knocking in the walls | `environment/nightmare_knock.wav` | Nightmare Mode ambient noise (every 7–16 s) | one-shot, positional | Desirable | |
| `nm_drag` | Something dragged | `environment/nightmare_drag.wav` | Nightmare noise; the vampire's blood mist rising | one-shot, positional | Desirable | |
| `critter_squish` | Critter squashed | `environment/critter_squish.wav` | Stepping on a spider, roach or rat (Nightmare) | one-shot, positional, local | Optional | |

## Ambience & music — `res://assets/creator/audio/ambient/`

| ID | Name | Creator file | Trigger | Behavior | Priority | Notes |
|---|---|---|---|---|---|---|
| `ambience_house` | House ambience | `ambient/house_ambience.ogg` | The whole run (pitched down in basements) | **loop**, 2D | Essential | Long, seamless; the most-heard sound in the game. |
| `music_menu` | Menu music | `ambient/menu_music.ogg` | Main menu | **loop**, music volume | Essential | |

## Occupants — `res://assets/creator/audio/npc/`

| ID | Name | Creator file | Trigger | Behavior | Priority | Notes |
|---|---|---|---|---|---|---|
| `npc_gasp` | Occupant gasp | `npc/gasp.wav` | Bitten by the vampire; Nightmare fits of distress | one-shot, positional | Desirable | Variants recommended (several voices). |
| `npc_flee` | Occupant flees | `npc/flee.wav` | An occupant runs from the house | one-shot, positional | Desirable | |
| `scream_1` | Scream 1 | `npc/scream_1.wav` | Results screen of a death (random); occupant burning | one-shot | Desirable | |
| `scream_2` | Scream 2 | `npc/scream_2.wav` | Same, plus a distant Nightmare scream | one-shot | Desirable | |
| `scream_3` | Scream 3 | `npc/scream_3.wav` | Same, plus the Lost One's scream when its keepsake is touched | one-shot | Desirable | |

## Interface & results — `res://assets/creator/audio/ui/`

| ID | Name | Creator file | Trigger | Behavior | Priority | Notes |
|---|---|---|---|---|---|---|
| `ui_click` | Click | `ui/click.wav` | Every button; switching equipment; choosing a suspect | one-shot, 2D | Desirable | |
| `ui_hover` | Hover / toast | `ui/hover.wav` | Button hover; HUD notifications | one-shot, 2D | Optional | |
| `results_win` | Victory sting | `ui/results_win.wav` | Results screen, vanquished | one-shot | Essential | |
| `results_lose` | Defeat sting | `ui/results_lose.wav` | Results screen, perished | one-shot | Essential | |

---

## Missing sounds worth adding (suggestions — not implemented)

None of these play today; each would need a small code hook as well as a file.
Suggested ids and paths follow the same scheme so they slot in later.

| Suggested ID | Name | Suggested file | Would play when | Priority |
|---|---|---|---|---|
| `stairs_use` | Creaking stairs | `player/stairs.wav` | Taking stairs (now only a pitched footstep) | Essential |
| `door_locked` | Door rattles / blocked | `environment/door_rattle.wav` | Bumping into a closed door | Desirable |
| `rival_footstep` | Rivals' footsteps | `player/footstep_rival.wav` | Other hunters moving nearby (multiplayer) | Desirable |
| `shove` | Shove impact | `player/shove.wav` | Shoving / being shoved (currently a pitched stake strike) | Desirable |
| `counterattack` | Counterattack | `equipment/counterattack.wav` | Driving the stake home on a lunging creature | Essential |
| `item_switch` | Equipment rummage | `equipment/item_switch.wav` | Changing equipment (currently the UI click) | Optional |
| `wraithlight_hum` | Wraithlight hum | `equipment/wraithlight_hum.ogg` | Loop while the violet lantern is held | Optional |
| `thermometer_cold` | Freezing reading | `equipment/thermometer_cold.wav` | The thermometer drops below zero | Desirable |
| `evidence_found` | Evidence sting | `evidence/evidence_found.wav` | A subtle musical sting with the journal pencil | Optional |
| `shimmer` | Disturbed room | `evidence/room_shimmer.wav` | The room-shimmer effect | Desirable |
| `ghost_manifest` | Manifestation | `entities/ghost_manifest.wav` | A ghost briefly becomes visible while roaming | Essential |
| `entity_attack` | Entity strikes | `entities/attack.wav` | A creature wounds a hunter (only the hurt sound plays now) | Essential |
| `vampire_dust` | Crumbling to dust | `entities/vampire_dust.wav` | The vampire's defeat | Desirable |
| `werewolf_transform` | Bones cracking | `entities/werewolf_transform.wav` | The moonlit transformation (now howl + growl) | Desirable |
| `shapeshifter_revert` | Wet unmasking | `entities/shapeshifter_revert.wav` | The shapeshifter's true form revealed on defeat | Optional |
| `sigil_bind` | Binding chime | `entities/sigil_bind.wav` | All sigils lit / the Harbinger bound | Optional |
| `full_moon` | Moonrise | `ambient/full_moon.wav` | The werewolf's full moon | Desirable |
| `blood_mist` | Blood mist bed | `ambient/blood_mist.ogg` | Loop under the vampire's red mist | Desirable |
| `basement_ambience` | Basement bed | `ambient/basement.ogg` | Loop on the basement floor (now the house loop, pitched down) | Desirable |
| `weather` | Rain and wind | `ambient/weather.ogg` | Loop outdoors / against windows | Optional |
| `fire_crackle` | Living flame crackle | `environment/fire_crackle.ogg` | Positional loop at hearths and candles | Desirable |
| `npc_speech` | Occupant mutter | `npc/mutter.wav` | Occupant speech bubbles (currently silent) | Optional |
| `npc_burn_death` | Burning death | `npc/burn_death.wav` | Occupant dies in flames (now scream + ignite) | Optional |
| `replay_moment` | Replay notification | `ui/replay_moment.wav` | Replay popups | Optional |

## Highest-priority replacements

1. `ambience_house` → `ambient/house_ambience.ogg` (heard all game)
2. `footstep` → `player/footstep.wav` (+ variants)
3. `needle_tap` → `equipment/witch_needle_tap.wav`
4. `pencil_scribble` → `evidence/journal_write.wav`
5. `hunt_start` + `hunt_loop` → `entities/…`
6. `door_creak` / `door_slam` → `environment/…`
7. `spirit_box_static` + `spirit_box_voice` → `equipment/whisper_box_…`
8. The creature signatures: `vampire_hiss`, `werewolf_howl`, `blight_ping`, `crawl_drag`, `music_box`
9. `results_win` / `results_lose`, `vanquish_success`
10. `menu_music`
