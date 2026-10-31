"""Main-menu plaque icons (48x48 ink line art, drawn in the 64x64 design space).

ui_tome (Encyclopedia), ui_crown (Rankings), ui_gear (Settings),
ui_keyboard (Controls), ui_tavern (The Forest Tavern), ui_about (About).
Registered in items_icons.ICONS; built with the "icons" group.
"""
from __future__ import annotations

import math

import objects as O
from core import INK, catmull, ellipse_pts, gradient, noise_tex, rng

GOLD = ("#ecd290", "#6a4e1e")


def tome(cv, st):
    """an antique tome, slightly turned, brass corners, clasp and a ribbon"""
    pts = [(14, 12), (46, 9), (52, 50), (19, 55)]
    pages = cv.mask().poly([(17, 14), (48, 11), (53, 49), (21, 53), (21, 56), (55, 52), (50, 13)])
    O.P(cv, pages, gradient(cv.W, cv.H, "#efe4c6", "#b5a27c", 0), st, ow=1.4, depth=1.2, hatch=0.15)
    for k in range(3):
        cv.stroke([(22 + k * 0.4, 54.5 - k * 1.1), (53.5 - k * 0.2, 50.5 - k * 1.1)], st.thin * 0.45, "#8a7a5a", 0.7)
    cov = cv.mask().poly(pts)
    O.P(cv, cov, noise_tex(cv.W, cv.H, rng("tome"), "#6a4626", 0.25), st, depth=2.5)
    spine = cv.mask().poly([(14, 12), (20, 11.6), (25, 54.4), (19, 55)])
    O.P(cv, spine, "#3e2814", st, ow=1.1, depth=1, hatch=0.2)
    for t in (0.18, 0.82):
        y0 = 12 + (55 - 12) * t
        cv.stroke([(14.5 + 4.5 * t, y0), (20.5 + 4.5 * t, y0 - 0.5)], st.thin * 1.6, O.BRASS)
    gold = gradient(cv.W, cv.H, *GOLD, 30)
    for (x, y, dx1, dy1, dx2, dy2) in ((46, 9, -8, 0.7, 0.9, 7), (52, 50, -8, 1.0, -0.9, -7)):
        O.P(cv, cv.mask().poly([(x, y), (x + dx1, y + dy1), (x + dx2, y + dy2)]), gold, st, ow=1.0, depth=0.5, hatch=0)
    # gilt tooling: a double frame, a lozenge and an all-seeing eye
    for (i, ins) in enumerate((4.0, 6.5)):
        fr = [(24 + ins * 0.3, 13.5 + ins), (44.5 - ins * 0.9, 12 + ins), (48.5 - ins, 48 - ins), (27.5 + ins * 0.2, 51 - ins)]
        cv.stroke(fr + [fr[0]], st.thin * (1.0 if i == 0 else 0.6), "#d6b46a", 0.95)
    cx, cy = 36.5, 32
    loz = [(cx, cy - 9), (cx + 6.5, cy), (cx, cy + 9), (cx - 6.5, cy), (cx, cy - 9)]
    cv.stroke(loz, st.thin * 1.0, "#d6b46a", 0.95)
    eye = catmull([(cx - 4.5, cy), (cx, cy - 2.6), (cx + 4.5, cy)], 6) + catmull([(cx + 4.5, cy), (cx, cy + 2.6), (cx - 4.5, cy)], 6)
    cv.stroke(eye, st.thin * 0.9, "#e8c878", 0.95)
    cv.paint(cv.mask().circle(cx, cy, 1.2), (232, 200, 120))
    # clasp and a red ribbon hanging out of the pages
    O.P(cv, cv.mask().rect(48, 27, 55, 34, 1.5), gold, st, ow=1.2, depth=0.8, hatch=0)
    rib = cv.mask().poly([(40, 53), (44, 52.6), (45, 61), (42.5, 58.5), (40.5, 61.5)])
    O.P(cv, rib, "#9a1a1e", st, ow=1.1, depth=0.6, hatch=0)


def crown(cv, st):
    """a gold crown with five points, pearls and a red stone"""
    gold = gradient(cv.W, cv.H, *GOLD, 30)
    top = [(8, 22), (18, 34), (24, 14), (32, 30), (40, 14), (46, 34), (56, 22)]
    body = cv.mask().poly(top + [(51, 46), (13, 46)])
    O.P(cv, body, gold, st, depth=2.2)
    band = cv.mask().poly([(12, 44), (52, 44), (51, 53), (13, 53)])
    O.P(cv, band, gradient(cv.W, cv.H, "#d8b868", "#5a4016", 90), st, depth=1.6)
    for (x, y) in ((8, 21), (24, 13), (40, 13), (56, 21), (32, 28)):
        O.P(cv, cv.mask().circle(x, y - 1, 3.2), gradient(cv.W, cv.H, "#fbf6ea", "#a8a094", 45), st, ow=1.1,
            depth=0.6, hatch=0)
        O.gloss(cv, x - 1, y - 2.2, 0.9, 0.8, 0.8)
    O.P(cv, cv.mask().ellipse(32, 48.5, 4.2, 3.2), gradient(cv.W, cv.H, "#e0404a", "#5a0a10", 45), st, ow=1.1,
        depth=0.6, hatch=0)
    for x in (20, 44):
        O.P(cv, cv.mask().ellipse(x, 48.5, 2.6, 2.2), gradient(cv.W, cv.H, "#4a7ad0", "#0a1a4a", 45), st, ow=1.0,
            depth=0.4, hatch=0)
    O.gloss(cv, 16, 36, 1.2, 4, 0.6)


def gear(cv, st):
    """a brass cog with a dark hub"""
    cx, cy, r_out, r_in, teeth = 32, 32, 25, 19, 10
    pts = []
    for k in range(teeth):
        a0 = 2 * math.pi * k / teeth
        for (da, r) in ((-0.17, r_in), (-0.11, r_out), (0.11, r_out), (0.17, r_in)):
            pts.append((cx + math.cos(a0 + da) * r, cy + math.sin(a0 + da) * r))
        a1 = a0 + math.pi / teeth
        pts.append((cx + math.cos(a1) * r_in, cy + math.sin(a1) * r_in))
    m = cv.mask().poly(pts)
    m.circle(cx, cy, 8.5, fill=0)
    O.P(cv, m, gradient(cv.W, cv.H, "#d8bb78", "#5a4220", 45), st, depth=2.5)
    for k in range(5):
        a = 2 * math.pi * k / 5 + 0.3
        cv.stroke([(cx + math.cos(a) * 9.5, cy + math.sin(a) * 9.5), (cx + math.cos(a) * 15.5, cy + math.sin(a) * 15.5)],
                  st.thin * 0.9, "#4a3414", 0.8)
    ring = ellipse_pts(cx, cy, 16.5, 16.5, 48)
    cv.stroke(ring + [ring[0]], st.thin * 0.9, "#4a3414", 0.85)
    hole = ellipse_pts(cx, cy, 8.5, 8.5, 32)
    cv.stroke(hole + [hole[0]], st.ow * 1.2, INK)
    O.gloss(cv, cx - 10, cy - 11, 3, 1.4, 0.55, rot=-40)


def keyboard(cv, st):
    """a typewriter-style keyboard: round keys on a dark wooden case"""
    case = cv.mask().poly([(6, 22), (58, 22), (61, 50), (3, 50)])
    O.P(cv, case, noise_tex(cv.W, cv.H, rng("kbd"), "#4a3424", 0.18), st, depth=2.5)
    O.P(cv, cv.mask().rect(4, 46, 60, 52, 1.5), "#2e2018", st, ow=1.2, depth=1, hatch=0.2)
    rows = ((25.5, 7, 9.0, 8), (32.5, 6.5, 7.6, 8), (39.5, 6.1, 9.2, 6))
    for (y, rr, x0, n) in rows:
        for i in range(n):
            x = x0 + i * 6.6 + (y - 25) * 0.08
            key = cv.mask().circle(x, y + 2.4, 2.75)
            O.P(cv, key, gradient(cv.W, cv.H, "#f0e8d4", "#9a907c", 45), st, ow=1.0, depth=0.6, hatch=0)
            ring = ellipse_pts(x, y + 2.4, 2.75, 2.75, 16)
            cv.stroke(ring + [ring[0]], st.thin * 0.7, O.BRASS, 0.9)
    bar = cv.mask().rect(18, 45, 46, 48.5, 1.6)
    O.P(cv, bar, gradient(cv.W, cv.H, "#f0e8d4", "#9a907c", 90), st, ow=1.0, depth=0.5, hatch=0)


def tavern(cv, st):
    """a small woodland hut with a lit window, among dark fir trees"""
    def fir(x, base, h, w, seed):
        t = cv.mask()
        for k in range(3):
            y0 = base - h + k * h * 0.28
            ww = w * (0.55 + k * 0.25)
            t.poly([(x, y0), (x + ww, y0 + h * 0.42), (x - ww, y0 + h * 0.42)])
        O.P(cv, t, noise_tex(cv.W, cv.H, rng(seed), "#2c4030", 0.25), st, depth=1.5, hatch=0.4)
        cv.stroke([(x, base - 2), (x, base + 2)], st.thin * 2.4, "#3a2818")
    fir(10, 50, 40, 9, "fir1")
    fir(54, 48, 36, 8.5, "fir2")
    # the hut: log walls under a steep roof, a chimney with smoke
    O.P(cv, cv.mask().rect(39, 14, 44, 26, 0.8), "#5a4a44", st, ow=1.2, depth=0.8, hatch=0.2)
    walls = cv.mask().rect(17, 33, 47, 55, 1)
    O.P(cv, walls, noise_tex(cv.W, cv.H, rng("hutwall"), "#7a5634", 0.2), st, depth=2)
    for y in (38, 43, 48):
        cv.stroke([(18, y), (46, y)], st.thin * 0.7, "#3a2414", 0.8)
    roof = cv.mask().poly([(11, 35), (32, 14), (53, 35), (49, 37), (32, 20), (15, 37)])
    roof.poly([(15, 37), (32, 20), (49, 37)])
    O.P(cv, roof, noise_tex(cv.W, cv.H, rng("hutroof"), "#4a3828", 0.25), st, depth=2, hatch=0.5)
    win = cv.mask().rect(21, 39.5, 28, 46, 0.8)
    cv.paint(win, (238, 182, 84))
    O.glow_at(cv, 24.5, 43, 9, (255, 190, 90), 0.45)
    cv.stroke([(24.5, 39.5), (24.5, 46)], st.thin * 0.8, INK)
    cv.stroke([(21, 42.7), (28, 42.7)], st.thin * 0.8, INK)
    door = cv.mask().poly(catmull([(34, 55), (34, 44), (38.5, 41), (43, 44)], 4) + [(43, 55)])
    O.P(cv, door, "#3a2416", st, ow=1.2, depth=0.6, hatch=0.2)
    cv.paint(cv.mask().circle(41, 49, 0.9), (210, 170, 90))
    for (x, y, r) in ((43, 11, 2.2), (46, 8, 2.6), (50.5, 6, 2.1)):
        cv.paint(cv.mask().circle(x, y, r), (200, 196, 190), 0.55)
    cv.stroke([(4, 56), (60, 56)], st.thin * 1.2, "#3a3020", 0.7)


def about(cv, st):
    """a wax-sealed letter (the About page)"""
    m = cv.mask().poly([(8, 16), (56, 13), (58, 49), (6, 52)])
    O.P(cv, m, gradient(cv.W, cv.H, "#efe4c6", "#b5a27c", 30), st, depth=2)
    cv.stroke([(8, 16), (32, 34), (56, 13)], st.thin * 1.2, "#6a5a3a", 0.9)
    for (a, b) in (((6, 52), (26, 32)), ((58, 49), (38, 31))):
        cv.stroke([a, b], st.thin * 0.7, "#8a7a5a", 0.7)
    seal = cv.mask().circle(32, 34, 7.5, wobble=0.8)
    O.P(cv, seal, gradient(cv.W, cv.H, "#c0303a", "#4a060c", 45), st, ow=1.4, depth=1)
    cv.stroke(ellipse_pts(32, 34, 4.5, 4.5, 20) + [ellipse_pts(32, 34, 4.5, 4.5, 20)[0]], st.thin * 0.8,
              (240, 170, 160), 0.6)
    O.gloss(cv, 29.5, 31.5, 1.6, 1.0, 0.6)


ICONS = {
    "ui_tome": tome,
    "ui_crown": crown,
    "ui_gear": gear,
    "ui_keyboard": keyboard,
    "ui_tavern": tavern,
    "ui_about": about,
}
