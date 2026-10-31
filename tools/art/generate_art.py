#!/usr/bin/env python3
"""Regenerate every provisional art asset for SPECTRAL RUN.

    python3 tools/art/generate_art.py                 # everything
    python3 tools/art/generate_art.py floors tokens   # only some groups
        groups: floors furniture tokens items icons ui | rev. 2: basement decor menu | rev. 6: locations
    python3 tools/art/generate_art.py --check         # verify sizes vs docs/ASSET_MANIFEST.md
    python3 tools/art/generate_art.py --preview DIR   # also write contact sheets to DIR

All art is procedural (numpy + Pillow), original, and deterministic: every
asset derives its random stream from a CRC32 of its own name.
Output: assets/provisional/<relative path from the manifest>.
"""
from __future__ import annotations

import re
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from core import OUT, ROOT  # noqa: E402

C = 64
FURNITURE = {
    "bed_double": (3, 4), "bed_single": (2, 4), "wardrobe": (3, 1), "dresser": (2, 1), "nightstand": (1, 1),
    "desk": (3, 2), "chair": (1, 1), "armchair": (2, 2), "sofa": (4, 2), "coffee_table": (2, 1),
    "dining_table": (5, 3), "bookshelf": (3, 1), "fireplace": (3, 1), "stove": (2, 1), "counter": (2, 1),
    "sink_kitchen": (2, 1), "icebox": (1, 1), "bathtub": (2, 3), "toilet": (1, 1), "washbasin": (1, 1),
    "piano": (3, 2), "grandfather_clock": (1, 1), "potted_plant": (1, 1), "rug_round": (4, 4), "rug_rect": (5, 3),
    "crates": (2, 2), "barrel": (1, 1), "workbench": (3, 1), "woodpile": (2, 1), "candelabra": (1, 1),
    "floor_lamp": (1, 1), "wall_mirror": (2, 1), "cabinet": (2, 1), "trunk": (2, 1), "side_table": (1, 1),
    "pew": (4, 1), "altar": (3, 2), "tree": (3, 3), "hedge": (2, 1), "gravestone": (1, 1), "coffin": (2, 4),
    "hay": (2, 2), "wash_tub": (2, 2),
}
# revision 2: basement / neglect furniture and stairs (built by neglect.py, group "basement")
FURNITURE2 = {
    "boiler": (3, 2), "wine_rack": (3, 1), "coal_pile": (2, 2), "storage_shelf": (3, 1), "covered_armchair": (2, 2),
    "covered_sofa": (4, 2), "broken_chair": (1, 1), "old_trunk": (2, 1), "water_tank": (2, 2), "pipes": (4, 1),
    "boards": (2, 1), "debris": (2, 2), "desk_large": (6, 4), "stairs_down": (1, 1), "stairs_up": (1, 1),
    "hatch": (1, 1),
}
# revision 6: the inn and the harbour (built by locations.py, group "locations")
FURNITURE3 = {
    "bar_counter": (4, 1), "keg_rack": (3, 1), "rope_coil": (1, 1), "bollard": (1, 1), "fishing_net": (2, 2),
    "water": (2, 2), "boat_hull": (6, 14),
}
DECOR = {"grime": (512, 512), "damp": (512, 512), "cracks": (512, 512), "cobweb": (64, 64), "stain_1": (128, 128),
         "stain_2": (128, 128), "stain_3": (128, 128), "peel": (128, 32), "dust_sheet_scrap": (64, 64),
         "rubble": (64, 64), "papers_scattered": (64, 64), "rat": (64, 64)}
MENU = {"case_photo_1": (128, 160), "case_photo_2": (128, 160), "case_photo_3": (128, 160), "case_file": (192, 256),
        "journal_open": (320, 224), "map_pinned": (256, 192), "pocket_watch": (96, 96), "magnifier": (96, 96),
        "inkwell": (96, 96), "plaque": (320, 64), "plaque_hover": (320, 64), "plaque_pressed": (320, 64),
        "plaque_dev": (320, 64)}
FLOORS = ["wood_dark", "wood_light", "parquet", "carpet_red", "carpet_blue", "carpet_green", "tile_checker",
          "tile_white", "stone", "dirt", "grass", "gravel"]
TOKENS = ["investigator", "occupant_a", "occupant_b", "occupant_c", "occupant_bitten", "occupant_d", "occupant_e",
          "occupant_f", "occupant_a_bitten", "occupant_b_bitten", "occupant_c_bitten", "occupant_d_bitten",
          "occupant_e_bitten", "occupant_f_bitten", "shade", "poltergeist",
          "vampire", "werewolf", "shapeshifter", "cat", "harbinger", "blightness", "crawler", "lost_one", "drowned_sailor", "plague_doctor", "werewolf_human",
          "shapeshifter_human"]
ITEMS = ["garlic", "wooden_stake", "silverware", "silver_stake", "hand_mirror", "iron_nails", "ghost_book",
         "ghost_book_written", "salt_pile", "crucifix_placed", "sigil_candle_unlit", "sigil_candle_lit",
         "blood_drops", "coffin_soil", "claw_marks", "fur_tuft", "paw_print", "shed_skin", "uv_handprint", "orb",
         "voodoo_doll", "music_box", "locket", "child_shoe", "ashes", "embers", "puddle", "wet_footprint"]
ICONS = ["ev_emf5", "ev_freezing", "ev_spirit_box", "ev_uv", "ev_writing", "ev_orbs", "ev_bite_marks",
         "ev_blood_drops", "ev_coffin_soil", "ev_claw_marks", "ev_fur", "ev_footprints", "ev_wrong_reflection",
         "ev_shed_skin", "ev_mimic_voice", "eq_flashlight", "eq_emf", "eq_thermometer", "eq_uv", "eq_spirit_box",
         "eq_ghost_book", "eq_orb_camera", "eq_salt", "eq_crucifix", "eq_holy_water", "eq_garlic",
         "eq_wooden_stake", "eq_silverware", "eq_silver_stake", "eq_hand_mirror", "eq_iron_nails", "eq_voodoo_doll", "ui_heart",
         "ui_heart_wounded", "ui_skull", "ui_clock", "ui_quill", "ui_house", "ui_trophy"]
UI = {"parchment": (512, 512), "panel_frame": (96, 96), "panel_dark": (96, 96), "button": (96, 48),
      "button_hover": (96, 48), "button_pressed": (96, 48), "title_logo": (1200, 300),
      "menu_background": (1920, 1080), "banner_vanquished": (1000, 220), "banner_perished": (1000, 220),
      "vignette": (1024, 1024), "slot": (64, 64), "slot_selected": (64, 64)}
LIGHTS = {"soft": (512, 512), "cone": (1024, 512), "cone_centered": (2048, 512), "candle": (256, 256)}
OPAQUE_OK = {"parchment", "menu_background"}


def expected():
    exp = {}
    for f in FLOORS:
        exp[f"floors/{f}.png"] = (512, 512)
    exp["walls/wall_top.png"] = (128, 128)
    for f, (w, h) in FURNITURE.items():
        exp[f"furniture/{f}.png"] = (w * C, h * C)
    for f, (w, h) in FURNITURE2.items():
        exp[f"furniture/{f}.png"] = (w * C, h * C)
    for f, (w, h) in FURNITURE3.items():
        exp[f"furniture/{f}.png"] = (w * C, h * C)
    for f, s in DECOR.items():
        exp[f"decor/{f}.png"] = s
    for f, s in MENU.items():
        exp[f"menu/{f}.png"] = s
    for f in TOKENS:
        exp[f"tokens/{f}.png"] = (128, 128)
    for f in ITEMS:
        exp[f"items/{f}.png"] = (64, 64)
    for f in ICONS:
        exp[f"icons/{f}.png"] = (48, 48)
    for f, s in UI.items():
        exp[f"ui/{f}.png"] = s
    for f, s in LIGHTS.items():
        exp[f"lights/{f}.png"] = s
    return exp


def check():
    from PIL import Image
    exp = expected()
    # cross-check that every png named in the manifest is in our list
    man = (ROOT / "docs" / "ASSET_MANIFEST.md").read_text(encoding="utf-8")
    named = set(re.findall(r"`([a-z0-9_]+)\.png`", man))
    named |= {n for n in re.findall(r"`([a-z0-9_]+)`", man) if n.startswith(("ev_", "eq_", "ui_"))}
    ours = {Path(p).stem for p in exp}
    missing_from_list = sorted(named - ours)
    bad = []
    for rel, (w, h) in sorted(exp.items()):
        p = OUT / rel
        if not p.exists():
            bad.append(f"MISSING {rel}")
            continue
        im = Image.open(p)
        if im.size != (w, h):
            bad.append(f"SIZE {rel}: {im.size} != {(w, h)}")
        stem = Path(rel).stem
        if rel.startswith(("floors/", "walls/")) or stem in OPAQUE_OK:
            continue
        if im.mode != "RGBA":
            bad.append(f"MODE {rel}: {im.mode} (expected RGBA)")
    extra = sorted(str(p.relative_to(OUT)) for p in OUT.rglob("*.png") if str(p.relative_to(OUT)) not in exp)
    print(f"checked {len(exp)} files")
    for b in bad:
        print("  ", b)
    for m in missing_from_list:
        print("   manifest name not generated:", m)
    for e in extra:
        print("   extra file:", e)
    ok = not bad and not missing_from_list
    print("OK" if ok else "PROBLEMS FOUND")
    return ok


GROUPS = ["floors", "furniture", "tokens", "items", "ui", "basement", "decor", "menu", "locations"]


def main(argv):
    if "--check" in argv:
        return 0 if check() else 1
    preview = None
    if "--preview" in argv:
        i = argv.index("--preview")
        preview = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    groups = [a for a in argv if not a.startswith("-")] or GROUPS
    t0 = time.time()
    for g in groups:
        t = time.time()
        if g == "floors":
            import floors
            floors.build_all()
        elif g == "furniture":
            import furniture
            furniture.build_all()
        elif g == "tokens":
            import tokens
            import rev5
            tokens.build_all()
            rev5.build_tokens()
        elif g in ("items", "icons"):
            import items_icons
            items_icons.build_items() if g == "items" else None
            items_icons.build_icons()
        elif g == "ui":
            import ui
            ui.build_all()
        elif g == "basement":
            import neglect
            neglect.build_furniture()
        elif g == "decor":
            import neglect
            neglect.build_decor()
        elif g == "menu":
            import menu_props
            menu_props.build_all()
        elif g == "locations":
            import locations
            locations.build_all()
        else:
            print("unknown group", g)
            continue
        print(f"[{g}] {time.time() - t:.1f}s")
    print(f"done in {time.time() - t0:.1f}s -> {OUT}")
    ok = check()
    if preview:
        import preview as pv
        out = Path(preview)
        out.mkdir(parents=True, exist_ok=True)
        for n, fn in pv.SHEETS.items():
            fn(out)
        print("previews ->", out)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
