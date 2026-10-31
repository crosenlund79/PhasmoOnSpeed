"""Items (64x64 floor decals) and icons (48x48 ink line art)."""
from __future__ import annotations

import math

import numpy as np

import objects as O
import menu_icons as MI
import rev5 as R5
from core import Canvas, INK, blur, col, dilate, gradient, save, catmull

ITEM_ST = O.Style(ow=2.0, thin=1.0, shade=0.45, hatch=0.45, light=0.3, depth=2.5)
ICON_ST = O.Style(ow=2.1, thin=1.35, shade=0.3, hatch=0.35, light=0.25, depth=2.0, icon=True)


# --------------------------------------------------------------------------
# items
# --------------------------------------------------------------------------
def item(name, draw, shadow=True, post=None, grain=0.06):
    cv = Canvas(64, 64, 4, name="item:" + name)
    draw(cv, ITEM_ST)
    cv.grain(grain)
    if shadow:
        cv.drop_shadow(1.5, 2.0, 1.4, 0.5)
    if post:
        post(cv)
    save(cv.image(), f"items/{name}.png")


ITEMS = {
    "garlic": (lambda cv, st: O.garlic(cv, st), True, None),
    "wooden_stake": (lambda cv, st: O.stake(cv, st), True, None),
    "silverware": (lambda cv, st: O.silverware(cv, st), True, None),
    "silver_stake": (lambda cv, st: O.stake(cv, st, metal=True), True, None),
    "hand_mirror": (lambda cv, st: O.hand_mirror(cv, st), True, None),
    "iron_nails": (lambda cv, st: O.iron_nails(cv, st), True, None),
    "ghost_book": (lambda cv, st: O.book(cv, st), True, None),
    "ghost_book_written": (lambda cv, st: O.book(cv, st, open_=True, written=True), True, None),
    "salt_pile": (lambda cv, st: O.salt_pile(cv, st), True, None),
    "crucifix_placed": (lambda cv, st: O.crucifix(cv, st, placed=True), True, None),
    "sigil_candle_unlit": (lambda cv, st: O.candle(cv, st, lit=False), True, None),
    "sigil_candle_lit": (lambda cv, st: O.candle(cv, st, lit=True), True, lambda cv: O.candle_flame(cv)),
    "blood_drops": (lambda cv, st: O.blood_drops(cv, st), False, None),
    "coffin_soil": (lambda cv, st: O.soil(cv, st), True, None),
    "claw_marks": (lambda cv, st: O.claw_marks(cv, st, floor=True), False, None),
    "fur_tuft": (lambda cv, st: O.fur_tuft(cv, st), True, None),
    "paw_print": (lambda cv, st: O.paw_print(cv, st), False, None),
    "shed_skin": (lambda cv, st: O.shed_skin(cv, st), True, None),
    "uv_handprint": (lambda cv, st: O.handprint(cv, st, glow=True), False, None),
    "orb": (lambda cv, st: O.orb(cv, st, 32, 32, 17), False, None),
    # revision 5
    "voodoo_doll": (lambda cv, st: R5.voodoo_doll(cv, st), True, None),
    "music_box": (lambda cv, st: R5.music_box(cv, st), True, None),
    "locket": (lambda cv, st: R5.locket(cv, st), True, None),
    "child_shoe": (lambda cv, st: R5.child_shoe(cv, st), True, None),
    "ashes": (lambda cv, st: R5.ash_pile(cv, st, embers=False), False, None),
    "embers": (lambda cv, st: R5.ash_pile(cv, st, embers=True), False, None),
    # the Drowned Sailor's trail
    "puddle": (lambda cv, st: R5.puddle(cv, st), False, None),
    "wet_footprint": (lambda cv, st: R5.wet_footprint(cv, st), False, None),
}


# --------------------------------------------------------------------------
# icons
# --------------------------------------------------------------------------
def halo(cv, r=1.1, color=(232, 222, 198), op=0.92):
    h = dilate(np.clip(cv.a * 1.4, 0, 1), r * cv.ss) * op
    c = col(color)
    na = cv.a + h * (1 - cv.a)
    rgb = (cv.rgb * cv.a[..., None] + c * (h * (1 - cv.a))[..., None]) / np.maximum(na, 1e-4)[..., None]
    cv.rgb, cv.a = rgb, na


def icon(name, draw):
    cv = Canvas(48, 48, 4, name="icon:" + name)
    cv.xf = (0.75, 0.0, 0.0)
    draw(cv, ICON_ST)
    cv.xf = None
    cv.grain(0.04)
    halo(cv)
    save(cv.image(), f"icons/{name}.png")


def drops3(cv, st):
    """three classic teardrops: point at the top, round bottom"""
    for (x, y, sc) in ((22, 34, 1.0), (42, 22, 0.72), (44, 46, 0.6)):
        arc = [(x + 9 * sc * math.cos(a), y + 2 * sc + 9 * sc * math.sin(a)) for a in np.linspace(-0.3, math.pi + 0.3, 24)]
        m = cv.mask().poly(catmull([(x, y - 16 * sc)] + arc + [(x, y - 16 * sc)], 3))
        O.P(cv, m, gradient(cv.W, cv.H, "#b02a30", "#4a060c", 45), st, depth=1.5)
        O.gloss(cv, x - 3.5 * sc, y + 1 * sc, 1.5 * sc, 3.2 * sc, 0.6, rot=15)


def ev_claw(cv, st):
    for k in range(3):
        off = (k - 1) * 11
        pts = [(12 + off, 10), (26 + off, 22), (40 + off, 38), (50 + off, 56)]
        cp = catmull(pts, 8)
        left, right = [], []
        for i, (x, y) in enumerate(cp):
            t = i / (len(cp) - 1)
            w = 3.0 * math.sin(math.pi * t) ** 0.9 + 0.2
            dx = cp[min(i + 1, len(cp) - 1)][0] - cp[max(i - 1, 0)][0]
            dy = cp[min(i + 1, len(cp) - 1)][1] - cp[max(i - 1, 0)][1]
            n = math.hypot(dx, dy) + 1e-6
            left.append((x - dy / n * w, y + dx / n * w))
            right.append((x + dy / n * w, y - dx / n * w))
        m = cv.mask().poly(left + right[::-1])
        O.P(cv, m, gradient(cv.W, cv.H, "#b0303a", "#4a0a12", 45), st, depth=1)


ICONS = {
    "ev_emf5": lambda cv, st: R5.witch_needle(cv, st, frenzy=True),
    "ev_freezing": lambda cv, st: O.snowflake(cv, st),
    "ev_spirit_box": lambda cv, st: R5.whisper_box(cv, st, open_=True),
    "ev_uv": lambda cv, st: O.handprint(cv, st, True),
    "ev_writing": lambda cv, st: O.book(cv, st, open_=True, written=True),
    "ev_orbs": lambda cv, st: O.orbs3(cv, st),
    "ev_bite_marks": lambda cv, st: O.bite(cv, st),
    "ev_blood_drops": drops3,
    "ev_coffin_soil": lambda cv, st: O.soil(cv, st, True),
    "ev_claw_marks": ev_claw,
    "ev_fur": lambda cv, st: O.fur_tuft(cv, st),
    "ev_footprints": lambda cv, st: O.footprints(cv, st),
    "ev_wrong_reflection": lambda cv, st: O.hand_mirror(cv, st, wrong=True),
    "ev_shed_skin": lambda cv, st: O.shed_skin(cv, st),
    "ev_mimic_voice": lambda cv, st: O.mouth_voice(cv, st),
    "eq_flashlight": lambda cv, st: R5.lantern(cv, st),
    "eq_emf": lambda cv, st: R5.witch_needle(cv, st),
    "eq_thermometer": lambda cv, st: O.thermometer(cv, st),
    "eq_uv": lambda cv, st: R5.lantern(cv, st, violet=True),
    "eq_spirit_box": lambda cv, st: R5.whisper_box(cv, st),
    "eq_ghost_book": lambda cv, st: O.book(cv, st),
    "eq_orb_camera": lambda cv, st: R5.scrying_mirror(cv, st),
    "eq_salt": lambda cv, st: O.salt_box(cv, st),
    "eq_crucifix": lambda cv, st: O.crucifix(cv, st, placed=False),
    "eq_holy_water": lambda cv, st: O.holy_water(cv, st),
    "eq_garlic": lambda cv, st: O.garlic(cv, st),
    "eq_wooden_stake": lambda cv, st: O.stake(cv, st),
    "eq_silverware": lambda cv, st: O.silverware(cv, st),
    "eq_silver_stake": lambda cv, st: O.stake(cv, st, metal=True),
    "eq_hand_mirror": lambda cv, st: O.hand_mirror(cv, st),
    "eq_iron_nails": lambda cv, st: O.iron_nails(cv, st),
    "eq_voodoo_doll": lambda cv, st: R5.voodoo_doll(cv, st),
    "ui_heart": lambda cv, st: O.heart(cv, st),
    "ui_heart_wounded": lambda cv, st: O.heart(cv, st, wounded=True),
    "ui_skull": lambda cv, st: O.skull(cv, st),
    "ui_clock": lambda cv, st: O.pocket_watch(cv, st),
    "ui_quill": lambda cv, st: O.quill(cv, st),
    "ui_house": lambda cv, st: O.house(cv, st),
    "ui_trophy": lambda cv, st: O.trophy(cv, st),
}


ICONS.update(MI.ICONS)   # main-menu plaque icons


def build_items(only=None):
    for n, (fn, sh, post) in ITEMS.items():
        if only and n not in only:
            continue
        item(n, fn, sh, post)


def build_icons(only=None):
    for n, fn in ICONS.items():
        if only and n not in only:
            continue
        icon(n, fn)


def build_all(only=None):
    build_items(only)
    build_icons(only)


if __name__ == "__main__":
    import sys
    build_all(sys.argv[1:] or None)
