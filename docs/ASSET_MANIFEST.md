# SPECTRAL RUN — Art Asset Manifest

All artwork is looked up by **relative path** through the `Art` autoload
(`scripts/autoload/art.gd`). For every path the game first checks
`res://assets/creator/<path>` and falls back to
`res://assets/provisional/<path>`. To replace a provisional piece, drop a PNG
with the same relative path and the same pixel size (or same aspect ratio)
into `assets/creator/`. No gameplay code changes are required.

## World scale

* One gameplay grid cell = **32 world pixels**.
* World art is authored at **2× density: 64 px per cell**. The game draws it at
  0.5 scale, so it stays crisp when the camera is zoomed in.
* Projection: **strictly top-down (orthographic, directly overhead)**. No
  perspective, no visible front faces of furniture, no isometric angles.
  Shading suggests a single soft light from the upper-left.
* Style: Gothic Noir illustration — heavy black ink outlines (3–5 px at 2×),
  hand-hatched shading, grain / paper texture, desaturated charcoal, dusty
  blue and weathered brown palette, sparing warm amber and pale spectral cyan.

## Floors — `floors/*.png` (512×512, seamlessly tileable, 8×8 cells)

| file | use |
|---|---|
| `wood_dark.png` | dark oak planks (halls, studies) |
| `wood_light.png` | worn pine planks (bedrooms, cottage) |
| `parquet.png` | herringbone parquet (living/dining) |
| `carpet_red.png` | oxblood patterned damask carpet |
| `carpet_blue.png` | faded blue patterned carpet |
| `carpet_green.png` | moss-green patterned carpet |
| `tile_checker.png` | black/ivory checker tiles (kitchen) |
| `tile_white.png` | cracked white hex tiles (bathroom) |
| `stone.png` | flagstones (cellar, chapel, porch) |
| `dirt.png` | packed earth with straw (shed, barn) |
| `grass.png` | dark overgrown lawn (yards) |
| `gravel.png` | gravel path |

## Walls — `walls/`

| file | size | use |
|---|---|---|
| `wall_top.png` | 128×128 tileable | top surface of wall cells (dark plaster/brick cap) |

## Furniture — `furniture/*.png`

Image size = footprint × 64 px. Rotation 0 = the "front" (where you sit / open
it) faces **down** (+Y). The game rotates in 90° steps.

| file | footprint (cells w×h) | blocks movement |
|---|---|---|
| `bed_double.png` | 3×4 | yes |
| `bed_single.png` | 2×4 | yes |
| `wardrobe.png` | 3×1 | yes |
| `dresser.png` | 2×1 | yes |
| `nightstand.png` | 1×1 | yes |
| `desk.png` | 3×2 | yes |
| `chair.png` | 1×1 | yes |
| `armchair.png` | 2×2 | yes |
| `sofa.png` | 4×2 | yes |
| `coffee_table.png` | 2×1 | yes |
| `dining_table.png` | 5×3 (chairs drawn around it) | yes |
| `bookshelf.png` | 3×1 | yes |
| `fireplace.png` | 3×1 (lit hearth) | yes |
| `stove.png` | 2×1 (cast-iron range) | yes |
| `counter.png` | 2×1 | yes |
| `sink_kitchen.png` | 2×1 | yes |
| `icebox.png` | 1×1 | yes |
| `bathtub.png` | 2×3 (clawfoot) | yes |
| `toilet.png` | 1×1 | yes |
| `washbasin.png` | 1×1 | yes |
| `piano.png` | 3×2 | yes |
| `grandfather_clock.png` | 1×1 | yes |
| `potted_plant.png` | 1×1 | yes |
| `rug_round.png` | 4×4 | no (decoration) |
| `rug_rect.png` | 5×3 | no (decoration) |
| `crates.png` | 2×2 | yes |
| `barrel.png` | 1×1 | yes |
| `workbench.png` | 3×1 | yes |
| `woodpile.png` | 2×1 | yes |
| `candelabra.png` | 1×1 | yes (light source) |
| `floor_lamp.png` | 1×1 | yes (light source) |
| `wall_mirror.png` | 2×1 (thin, mounted on wall edge) | yes |
| `cabinet.png` | 2×1 | yes |
| `trunk.png` | 2×1 | yes |
| `side_table.png` | 1×1 | yes |
| `pew.png` | 4×1 | yes |
| `altar.png` | 3×2 | yes |
| `tree.png` | 3×3 (canopy from above) | yes |
| `hedge.png` | 2×1 | yes |
| `gravestone.png` | 1×1 | yes |
| `coffin.png` | 2×4 (closed, used only as decor in crypt rooms) | yes |
| `hay.png` | 2×2 | yes |
| `wash_tub.png` | 2×2 | yes |

## Tokens — `tokens/*.png` (128×128, transparent)

Illustrated top-down "game pieces": a figure seen from above on a dark
circular inked base with a subtle rim. **Facing direction is +X (right)** —
the game rotates the token. A small notch/gleam on the right rim makes facing
readable at speed.

`investigator.png`, `occupant_a.png`, `occupant_b.png`, `occupant_c.png`,
`occupant_bitten.png` (occupant_a with visible neck wound + pallor),
`shade.png`, `poltergeist.png`, `vampire.png`, `werewolf.png`,
`shapeshifter.png` (true form), `cat.png` (smaller figure, same base size),
`harbinger.png`.

## Items & world decals — `items/*.png` (64×64, transparent)

`garlic.png`, `wooden_stake.png`, `silverware.png`, `silver_stake.png`,
`hand_mirror.png`, `iron_nails.png`, `ghost_book.png`,
`ghost_book_written.png`, `salt_pile.png`, `crucifix_placed.png`,
`sigil_candle_unlit.png`, `sigil_candle_lit.png`, `blood_drops.png`,
`coffin_soil.png`, `claw_marks.png`, `fur_tuft.png`, `paw_print.png`,
`shed_skin.png`, `uv_handprint.png` (glowing violet), `orb.png` (soft pale orb).

## Icons — `icons/*.png` (48×48, transparent)

Ink-on-parchment style icons (dark ink line art, optional muted color wash).

Evidence: `ev_emf5`, `ev_freezing`, `ev_spirit_box`, `ev_uv`, `ev_writing`,
`ev_orbs`, `ev_bite_marks`, `ev_blood_drops`, `ev_coffin_soil`,
`ev_claw_marks`, `ev_fur`, `ev_footprints`, `ev_wrong_reflection`,
`ev_shed_skin`, `ev_mimic_voice`.

Equipment: `eq_flashlight`, `eq_emf`, `eq_thermometer`, `eq_uv`,
`eq_spirit_box`, `eq_ghost_book`, `eq_orb_camera`, `eq_salt`, `eq_crucifix`,
`eq_holy_water`, `eq_garlic`, `eq_wooden_stake`, `eq_silverware`,
`eq_silver_stake`, `eq_hand_mirror`, `eq_iron_nails`.

UI: `ui_heart`, `ui_heart_wounded`, `ui_skull`, `ui_clock`, `ui_quill`,
`ui_house`, `ui_trophy`.

## UI — `ui/`

| file | size | notes |
|---|---|---|
| `parchment.png` | 512×512 | tileable aged parchment |
| `panel_frame.png` | 96×96 | 9-slice (24 px margins): parchment centre, charcoal inked border, thin gold inner rule |
| `panel_dark.png` | 96×96 | 9-slice: charcoal panel with gold rule |
| `button.png` / `button_hover.png` / `button_pressed.png` | 96×48 | 9-slice (16 px margins) |
| `title_logo.png` | 1200×300 | "SPECTRAL RUN" distressed serif logo, transparent |
| `menu_background.png` | 1920×1080 | moonlit gothic manor, ink illustration |
| `banner_vanquished.png` | 1000×220 | "VANQUISHED!" dramatic title, transparent |
| `banner_perished.png` | 1000×220 | "PERISHED!" dramatic title (blood red), transparent |
| `vignette.png` | 1024×1024 | black radial vignette, transparent centre |
| `slot.png` / `slot_selected.png` | 64×64 | hotbar slot frames |

## Lights — `lights/`

| file | size | notes |
|---|---|---|
| `soft.png` | 512×512 | white radial falloff for PointLight2D |
| `cone.png` | 1024×512 | flashlight cone; origin at the **left-centre** pixel, pointing +X |
| `cone_centered.png` | 2048×512 | the same cone with its origin at the **image centre** (used in game: the light sits at the holder so shadows are cast from the holder) |
| `candle.png` | 256×256 | warm, slightly irregular radial |

## Revision 2 additions

### Basement & neglect furniture — `furniture/*.png` (64 px per cell, rotation 0 front faces down)

| file | footprint | blocks | notes |
|---|---|---|---|
| `boiler.png` | 3×2 | yes | riveted iron boiler/furnace with pipes, faint orange firebox glow |
| `wine_rack.png` | 3×1 | yes | dusty wine rack, bottle ends seen from above |
| `coal_pile.png` | 2×2 | yes | heap of coal with a shovel |
| `storage_shelf.png` | 3×1 | yes | sagging shelves of jars, tins and boxes |
| `covered_armchair.png` | 2×2 | yes | armchair under a grey dust sheet |
| `covered_sofa.png` | 4×2 | yes | sofa under a dust sheet |
| `broken_chair.png` | 1×1 | yes | toppled chair, a leg snapped |
| `old_trunk.png` | 2×1 | yes | battered, strapped, lid ajar |
| `water_tank.png` | 2×2 | yes | round cistern / water tank from above |
| `pipes.png` | 4×1 | no | exposed pipes run along a wall (decoration, drawn under actors) |
| `boards.png` | 2×1 | no | loose planks on the floor (decoration) |
| `debris.png` | 2×2 | no | fallen plaster, rubble, splinters (decoration) |
| `desk_large.png` | 6×4 | yes | the investigator's desk for the main menu: leather blotter, scattered case papers, photographs, brass lamp base, inkwell |

### Stairs — `furniture/` (walkable, drawn under actors)

| file | footprint | notes |
|---|---|---|
| `stairs_down.png` | 1×1 | steps descending away from the viewer (darker at the far edge), stone/wood edging |
| `stairs_up.png` | 1×1 | steps rising (lighter at the far edge) |
| `hatch.png` | 1×1 | open wooden cellar hatch / coal chute with a ladder visible |

### Neglect overlays — `decor/`

| file | size | notes |
|---|---|---|
| `grime.png` | 512×512 tileable, transparent | soot, dust and scuffs (light) |
| `damp.png` | 512×512 tileable, transparent | water stains, mould blooms, tide marks (heavier, greenish-brown) |
| `cracks.png` | 512×512 tileable, transparent | cracked plaster/stone hairlines |
| `cobweb.png` | 64×64 | corner cobweb, anchored in the TOP-LEFT corner (the game rotates it per corner) |
| `stain_1.png`, `stain_2.png`, `stain_3.png` | 128×128 | individual damp stains / spills |
| `peel.png` | 128×32 | peeling wallpaper strip curling off a wall edge (wall along the TOP edge) |
| `dust_sheet_scrap.png`, `rubble.png`, `papers_scattered.png`, `rat.png` | 64×64 | small floor details |

### Main menu scene — `menu/`

| file | size | notes |
|---|---|---|
| `case_photo_1.png`…`case_photo_3.png` | 128×160 | old sepia photographs of the houses / occupants (no real people), slightly curled, with tape |
| `case_file.png` | 192×256 | manila case file with "SPECTRAL" stamp and handwritten notes |
| `journal_open.png` | 320×224 | the open hunter's journal from above, inked notes and sketches |
| `map_pinned.png` | 256×192 | hand-drawn floorplan with red string and pins |
| `pocket_watch.png`, `magnifier.png`, `inkwell.png` | 96×96 | desk props from above |
| `plaque.png`, `plaque_hover.png`, `plaque_pressed.png` | 320×64 | 9-slice (24 px margins) brass-framed parchment plaque buttons with nail heads in the corners |
| `plaque_dev.png` | 320×64 | 9-slice, cold steel/blue variant for developer-only buttons |

## Revision 5 additions

Period kit icons replace the modern ones in place (same file names, so ids stay
stable): `eq_emf.png` is now the **Witch's Needle** (corked glass tube, dark needle,
sigil seal), `ev_emf5.png` the needle in frenzy, `eq_uv.png` the violet
**Wraithlight Lantern**, `eq_flashlight.png` the oil lantern, `eq_spirit_box.png` /
`ev_spirit_box.png` the **Whisper Box** (wooden, brass hinges and lock; closed / open
and whispering) and `eq_orb_camera.png` the **Scrying Mirror**.

| file | size | notes |
|---|---|---|
| `icons/eq_voodoo_doll.png` | 48×48 | pin-stuck burlap doll |
| `items/voodoo_doll.png`, `items/music_box.png`, `items/locket.png`, `items/child_shoe.png` | 64×64 | floor items: the doll and the three keepsakes |
| `items/ashes.png`, `items/embers.png` | 64×64 | what a burned occupant leaves (embers glow; they are a hazard) |
| `tokens/blightness.png`, `tokens/crawler.png`, `tokens/lost_one.png` | 128×128 | the three new ghosts (the game draws the first two through a warp shader) |
| `tokens/drowned_sailor.png`, `tokens/plague_doctor.png` | 128×128 | the Drowned Sailor (pea coat, tricorn, dripping sea water) and the Plague Doctor (hat brim, robes, beaked mask) |
| `items/puddle.png`, `items/wet_footprint.png` | 64×64 | the Drowned Sailor's trail — atmospheric, not evidence; they dry up after a while |
