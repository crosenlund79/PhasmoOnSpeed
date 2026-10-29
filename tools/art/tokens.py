"""Board-game-miniature style tokens (128x128), facing +X."""
from __future__ import annotations

import math

import numpy as np

from core import (Canvas, INK, blur, catmull, col, dilate, ellipse_pts, fabric_tex, fbm, gradient, mix,
                  noise_tex, radial, rng, save, smoothstep, edge_band)

S = 128
CX, CY = 62.0, 62.0
RB = 58.0  # base radius

SKIN = "#cfa88a"
SKIN_PALE = "#c9c6c0"


def new(name):
    cv = Canvas(S, S, 4, name=name)
    return cv


def fab(cv, color, amount=0.14, weave=1.2):
    return fabric_tex(cv.W, cv.H, rng(f"{cv.name}:{color}"), color, amount, weave, cv.ss)


def base(cv, ring="#8a744a", field="#211e20", rim="#3b3739"):
    m = cv.mask().circle(CX, CY, RB)
    g = gradient(cv.W, cv.H, mix(rim, "#ffffff", 0.18), mix(rim, "#000000", 0.45), 45)
    cv.part(m, g, ow=2.6, shade=0.35, light=0.3, hatch=0.35, depth=4)
    inner = cv.mask().circle(CX, CY, RB - 6)
    t = noise_tex(cv.W, cv.H, rng(cv.name + "base"), field, 0.18, 10, 10, 4)
    cv.paint(dilate(inner.arr, 1.6 * cv.ss), INK)
    cv.paint(inner, t)
    # inner bevel shadow (upper-left lip casts onto field)
    eb = edge_band(inner.arr, -3 * cv.ss, -3 * cv.ss, 2.5 * cv.ss)
    cv.mul(eb, 0.5, (0, 0, 0))
    cv.hatch(inner.arr, 45, 2.2, 0.5, 0.18)
    # decorative ring
    ring_m = np.clip(cv.mask().circle(CX, CY, RB - 2.6).arr - cv.mask().circle(CX, CY, RB - 3.8).arr, 0, 1)
    cv.paint(ring_m, ring, 0.9)
    # facing notch on the right rim
    nt = cv.mask().poly([(CX + RB + 1.0, CY), (CX + RB - 6.5, CY - 5.5), (CX + RB - 6.5, CY + 5.5)])
    cv.paint(dilate(nt.arr, 1.2 * cv.ss), INK)
    cv.paint(nt, "#ece3cc")
    return inner.arr


def ground_shadow(cv, x, y, rx, ry, op=0.55):
    m = cv.mask().ellipse(x + 2, y + 3, rx, ry)
    cv.mul(blur(m.arr, 3 * cv.ss), op, (0, 0, 0))


def P(cv, m, fill, ow=2.2, shade=0.45, light=0.3, hatch=0.5, depth=3.0, soft=0.0, **kw):
    return cv.part(m, fill, ow=ow, shade=shade, light=light, hatch=hatch, depth=depth, soft=soft,
                   hatch_spacing=2.2, **kw)


def limb(cv, pts, w, fill, ow=1.8):
    m = cv.mask().curve(pts, w, n=10)
    return P(cv, m, fill, ow=ow, depth=1.5, hatch=0.3)


def hand(cv, x, y, r=3.4, skin=SKIN):
    P(cv, cv.mask().circle(x, y, r), skin, ow=1.6, depth=1.2, hatch=0.2)


def finish(cv, rel):
    cv.grain(0.06)
    cv.drop_shadow(2.0, 3.0, 2.0, 0.55)
    save(cv.image(), rel)


# --------------------------------------------------------------------------
# humans
# --------------------------------------------------------------------------
def investigator():
    cv = new("investigator")
    base(cv)
    cv.xf = (1.3, 62.0, 63.0)
    ground_shadow(cv, 60, 62, 30, 38)
    coat = "#6e5438"
    # coat tails flaring behind (-X)
    tail = cv.mask().poly(catmull([(62, 38), (44, 38), (30, 48), (26, 64), (30, 80), (44, 90), (62, 90)], 8)
                          + [(70, 64)], wobble=0.6)
    P(cv, tail, fab(cv, mix(coat, "#000000", 0.15)), depth=4, hatch=0.7)
    cv.stroke(catmull([(27, 64), (38, 63.5), (50, 64)], 6), 1.0, INK, 0.8)
    for yy in (46, 82):
        cv.stroke(catmull([(32, 64 + (yy - 64) * 0.8), (44, yy), (56, yy)], 6), 0.6, INK, 0.5)
    # shoulders
    sh = cv.mask().ellipse(60, 64, 19, 31, wobble=0.5)
    P(cv, sh, fab(cv, coat), depth=4, soft=0.3)
    # left arm (top, -Y) bent forward
    limb(cv, [(64, 38), (76, 36), (84, 44)], 8.5, fab(cv, coat))
    hand(cv, 86, 46)
    # right arm (bottom, +Y) holding flashlight forward
    limb(cv, [(62, 90), (76, 90), (88, 82)], 8.5, fab(cv, coat))
    # flashlight beam stub (warm)
    beam = cv.mask().poly([(100, 79), (110, 73), (110, 89), (100, 83)])
    g = np.clip(1 - radial(cv.W, cv.H, *cv.T(100, 81), cv.TR(14)), 0, 1) ** 0.7
    cv.glow(blur(beam.arr, 1.5 * cv.ss) * g, (255, 200, 120), 1.0)
    fl = cv.mask().rect(86, 77.5, 101, 84.5, 1.5)
    P(cv, fl, "#4a4a4e", ow=1.6, depth=1.2, hatch=0)
    P(cv, cv.mask().rect(98, 76.5, 102, 85.5, 1), "#a8874a", ow=1.2, depth=0.8, hatch=0)
    cv.paint(cv.mask().rect(101.5, 78, 102.5, 84), (255, 240, 200))
    hand(cv, 88, 82)
    # collar
    col_ = cv.mask().ellipse(66, 64, 14, 18)
    P(cv, col_, fab(cv, "#3f3124"), depth=2)
    # hat: wide brim, crown with dent and band
    brim = cv.mask().ellipse(68, 64, 21, 19, wobble=0.4)
    P(cv, brim, fab(cv, "#2b2724", 0.1), ow=2.6, depth=3, soft=0.2)
    cv.stroke(ellipse_pts(68, 64, 18, 16, 60) + [ellipse_pts(68, 64, 18, 16, 60)[0]], 0.6, "#504840", 0.8)
    band = cv.mask().ellipse(67, 64, 12.5, 11.5)
    P(cv, band, "#141212", ow=1.4, depth=1, hatch=0)
    crown = cv.mask().ellipse(67, 64, 11, 10)
    P(cv, crown, fab(cv, "#3a342e", 0.1), ow=1.0, depth=2.5, soft=0.3)
    cv.stroke(catmull([(60, 64), (67, 63), (74, 64)], 6), 1.2, INK, 0.8)
    return finish(cv, "tokens/investigator.png")


def occupant(name, hair, hair2, dress, accent, style, pale=False, bitten=False):
    cv = new(name)
    skin = SKIN_PALE if pale else SKIN
    if pale:
        dress = mix(dress, "#9aa0a4", 0.45)
        hair = mix(hair, "#6a6a6a", 0.3)
        accent = mix(accent, "#9aa0a4", 0.4)
    base(cv, ring="#7a6a50")
    cv.xf = (1.4, 62.0, 63.0)
    ground_shadow(cv, 60, 62, 24, 32)
    # skirt / lower body visible behind (-X)
    if style in ("a", "c"):
        sk = cv.mask().poly(catmull([(60, 41), (48, 41), (40, 51), (38, 64), (40, 77), (48, 87), (60, 87)], 8)
                            + [(66, 64)], wobble=0.6)
        P(cv, sk, fab(cv, mix(dress, "#000000", 0.25)), depth=3, hatch=0.7)
        for yy in (50, 58, 70, 78):
            cv.stroke([(41, 64 + (yy - 64) * 1.05), (54, 64 + (yy - 64) * 0.8)], 0.7, INK, 0.6)
    # shoulders (hunched: narrow, raised)
    sh = cv.mask().ellipse(60, 64, 15, 24 if style != "b" else 27, wobble=0.5)
    P(cv, sh, fab(cv, dress), depth=3.5, soft=0.35)
    if style == "b":
        # waistcoat over white shirt
        wc = cv.mask().ellipse(62, 64, 12, 18)
        P(cv, wc, fab(cv, accent), depth=2, ow=1.4)
        for yy in (58, 64, 70):
            cv.paint(cv.mask().circle(73, yy, 1.0), "#c8b27a")
    if style == "c":
        # shawl across shoulders with fringe
        sw = cv.mask().ellipse(58, 64, 13, 26, wobble=0.6)
        P(cv, sw, fab(cv, accent), depth=2.5)
        for k in range(14):
            a = math.pi * (0.55 + k / 13 * 0.9)
            x, y = 58 + math.cos(a) * 13, 64 + math.sin(a) * 26
            cv.stroke([(x, y), (x - 3, y)], 0.7, mix(accent, "#000000", 0.4), 0.9)
    if style == "a":
        # lace collar
        lc = cv.mask().ellipse(66, 64, 10, 14)
        P(cv, lc, "#d8d2c2", ow=1.2, depth=1.5, hatch=0.2)
    # arms hugging forward: hands clasped near chest (nervous)
    arm_c = "#a49c8e" if style == "b" else dress
    limb(cv, [(60, 42), (72, 44), (80, 58)], 7.5, fab(cv, arm_c))
    limb(cv, [(60, 86), (72, 84), (80, 70)], 7.5, fab(cv, arm_c))
    hand(cv, 81, 60, 3.2, skin)
    hand(cv, 81, 68, 3.2, skin)
    # head
    hx, hy = 67, 64
    if style == "c":
        # braid trailing behind
        for k in range(6):
            P(cv, cv.mask().ellipse(54 - k * 5, 64 + math.sin(k) * 1.5, 3.6, 3.0), fab(cv, hair), ow=1.2, depth=1, hatch=0.2)
        cv.paint(cv.mask().circle(24, 65, 2.2), accent)
    head = cv.mask().ellipse(hx, hy, 11, 10.5)
    P(cv, head, skin, ow=2.2, depth=2)
    # hair from above
    hr = cv.mask().ellipse(hx - 1.5, hy, 10.5, 10.5, wobble=0.4)
    P(cv, hr, fab(cv, hair, 0.2), ow=1.2, depth=2.5, soft=0.2)
    if style == "b":
        # bald crown
        P(cv, cv.mask().ellipse(hx - 0.5, hy, 6.5, 6), skin, ow=0.8, depth=1.5, hatch=0.1)
        cv.paint(cv.mask().ellipse(hx - 2.5, hy - 2.5, 2, 1.4), "#f2dcc6", 0.6)
    else:
        # parting & strands
        for k in range(7):
            yy = hy - 8 + k * 2.6
            cv.stroke(catmull([(hx + 7, hy + (yy - hy) * 0.3), (hx, yy), (hx - 8, yy * 0.9 + hy * 0.1)], 6), 0.5,
                      hair2, 0.8)
        cv.stroke([(hx + 8, hy - 0.5), (hx - 4, hy - 0.5)], 0.7, mix(skin, "#000", 0.2), 0.8)
    if style == "a":
        bun = cv.mask().circle(hx - 9, hy, 5.2)
        P(cv, bun, fab(cv, hair, 0.2), ow=1.4, depth=1.5)
        cv.stroke(ellipse_pts(hx - 9, hy, 3, 3, 16, 0, 0, 300), 0.6, hair2, 0.9)
    # face cue: nose tip & brows at the front edge
    cv.paint(cv.mask().ellipse(hx + 10.8, hy, 1.8, 1.6), mix(skin, "#000000", 0.1))
    cv.stroke([(hx + 9.5, hy - 4.5), (hx + 9.5, hy - 1.5)], 0.8, INK, 0.7)
    cv.stroke([(hx + 9.5, hy + 1.5), (hx + 9.5, hy + 4.5)], 0.8, INK, 0.7)
    if bitten:
        # puncture wounds on the neck/shoulder (left side, toward -Y)
        bx, by = 66, 50
        cv.paint(blur(cv.mask().ellipse(bx, by, 6, 4.5).arr, 1.5 * cv.ss), (150, 40, 50), 0.6)
        for (px, py) in ((bx - 2.4, by), (bx + 2.4, by + 0.4)):
            cv.paint(cv.mask().circle(px, py, 1.6), (60, 0, 8))
            cv.paint(cv.mask().circle(px - 0.4, py - 0.4, 0.7), (210, 30, 40))
            cv.stroke(catmull([(px, py + 1), (px - 1.5, py + 3.5), (px - 2.5, py + 6.5)], 5), 0.8, (150, 10, 20), 0.95)
        # pallor veins
        for k in range(3):
            a = -1.8 + k * 0.5
            cv.stroke(catmull([(bx, by), (bx + math.cos(a) * 4, by + math.sin(a) * 4),
                               (bx + math.cos(a + 0.4) * 8, by + math.sin(a + 0.4) * 7)], 5), 0.4, (110, 80, 120), 0.6)
    return finish(cv, f"tokens/{name}.png")


def occupant_a():
    return occupant("occupant_a", "#7a3a22", "#b0633a", "#4b5d74", "#d8d2c2", "a")


def occupant_b():
    return occupant("occupant_b", "#8a8580", "#c0bab2", "#5a5248", "#6a3a26", "b")


def occupant_c():
    return occupant("occupant_c", "#c9a35c", "#e6cb8a", "#6e4a5a", "#4f5d3a", "c")


def occupant_bitten():
    return occupant("occupant_bitten", "#7a3a22", "#b0633a", "#4b5d74", "#d8d2c2", "a", pale=True, bitten=True)


# Additional occupants (more distinct looks; the shapeshifter's human disguise
# borrows an unused one, so it never duplicates a real occupant).
OCCUPANT_LOOKS = {
    "occupant_d": ("#2e2a28", "#5a514a", "#7a6a3e", "#8c2f2a", "b"),
    "occupant_e": ("#5b3f2b", "#8a6446", "#3f5a4a", "#c9b98e", "a"),
    "occupant_f": ("#a9a49b", "#d6d0c4", "#5a3c5e", "#7d6b3b", "c"),
}
BASE_LOOKS = {
    "occupant_a": ("#7a3a22", "#b0633a", "#4b5d74", "#d8d2c2", "a"),
    "occupant_b": ("#8a8580", "#c0bab2", "#5a5248", "#6a3a26", "b"),
    "occupant_c": ("#c9a35c", "#e6cb8a", "#6e4a5a", "#4f5d3a", "c"),
}


def occupant_d():
    return occupant("occupant_d", *OCCUPANT_LOOKS["occupant_d"])


def occupant_e():
    return occupant("occupant_e", *OCCUPANT_LOOKS["occupant_e"])


def occupant_f():
    return occupant("occupant_f", *OCCUPANT_LOOKS["occupant_f"])


def occupant_bitten_variants():
    # A bitten occupant keeps their own clothes and hair: only pallor and wounds change.
    for name, look in list(BASE_LOOKS.items()) + list(OCCUPANT_LOOKS.items()):
        occupant(name + "_bitten", *look, pale=True, bitten=True)


# --------------------------------------------------------------------------
# entities
# --------------------------------------------------------------------------
def shade():
    cv = new("shade")
    base(cv, ring="#5fa8b4", field="#151a1f")
    cv.xf = (1.15, 62.0, 63.0)
    r = cv.rnd
    # cold glow on the base
    g = np.clip(1 - radial(cv.W, cv.H, *cv.T(66, 62), cv.TR(46)), 0, 1) ** 1.5
    cv.glow(g, (110, 200, 220), 0.35)
    # trailing tendrils behind (-X)
    for k in range(7):
        y0 = 46 + k * 6
        pts = [(60, y0), (44, y0 + r.normal(0, 4)), (30, y0 + r.normal(0, 7)), (16 + r.random() * 6, y0 + r.normal(0, 9))]
        m = cv.mask().curve(pts, 3.6 - abs(k - 3) * 0.35, n=12)
        cv.paint(blur(m.arr, 1.2 * cv.ss), (200, 235, 240), 0.55)
        cv.stroke(catmull(pts, 12), 0.6, (40, 70, 80), 0.5)
    # veil body: teardrop, head toward +X
    pts = catmull([(84, 64), (78, 44), (60, 36), (38, 44), (28, 56), (34, 64), (26, 72), (36, 84), (60, 92),
                   (78, 84), (84, 64)], 10)
    veil = cv.mask().poly(pts, wobble=1.0)
    gv = gradient(cv.W, cv.H, "#f2fbfc", "#6fa3ae", 180)
    cv.paint(dilate(veil.arr, 1.4 * cv.ss), (30, 60, 72), 0.8)
    cv.paint(veil, gv, 0.72)
    # folds
    for k in range(6):
        yy = 46 + k * 7
        cv.stroke(catmull([(78, 64 + (yy - 64) * 0.4), (60, yy), (40, yy + (yy - 64) * 0.2)], 8), 0.6, (60, 110, 125),
                  0.6)
    cv.hatch(edge_band(veil.arr, 4 * cv.ss, 4 * cv.ss, 3 * cv.ss), 45, 2.0, 0.5, 0.5, color=(40, 80, 95))
    # reaching wisp arms
    for (y_, s_) in ((46, -1), (82, 1)):
        a = cv.mask().curve([(70, y_), (84, y_ - s_ * 2), (98, y_ - s_ * 8)], 3.4, n=10)
        cv.paint(dilate(a.arr, 1.0 * cv.ss), (30, 60, 72), 0.7)
        cv.paint(a, (225, 245, 248), 0.8)
        for f in range(3):
            cv.stroke([(98, y_ - s_ * 8), (104, y_ - s_ * (6 + f * 2.5))], 0.8, (225, 245, 248), 0.8)
    # hooded head
    hd = cv.mask().ellipse(74, 64, 12, 11)
    cv.paint(dilate(hd.arr, 1.4 * cv.ss), (30, 60, 72), 0.9)
    cv.paint(hd, gradient(cv.W, cv.H, "#ffffff", "#9cc9d1", 45), 0.9)
    # hollow eyes at the front of the face + mouth
    for yy in (59.5, 68.5):
        cv.paint(cv.mask().ellipse(82.5, yy, 2.6, 2.0), (10, 20, 26))
        cv.paint(cv.mask().circle(83, yy, 0.8), (150, 240, 255))
    cv.paint(cv.mask().ellipse(85, 64, 1.2, 2.4), (10, 20, 26), 0.8)
    cv.grain(0.05)
    cv.drop_shadow(2.0, 3.0, 2.0, 0.55)
    gl = blur(veil.arr, 5 * cv.ss)
    cv.glow(gl * 0.6, (140, 230, 245), 0.45)
    save(cv.image(), "tokens/shade.png")


def poltergeist():
    cv = new("poltergeist")
    base(cv, ring="#7d8f5a", field="#1a1c17")
    cv.xf = (1.12, 62.0, 63.0)
    r = cv.rnd
    # motion swirls
    for k in range(4):
        a0 = k * 90 + r.random() * 40
        rad = 40 + r.random() * 8
        cv.stroke(ellipse_pts(62, 62, rad, rad, 30, 0, a0, a0 + 70), 0.9, (150, 170, 120), 0.55)
    # jagged chaotic body
    pts = []
    n = 26
    for i in range(n):
        a = 2 * math.pi * i / n
        rad = (17 if i % 2 else 30) + r.normal(0, 4)
        if abs(math.cos(a) - 1) < 0.2:
            rad += 4
        pts.append((60 + math.cos(a) * rad, 64 + math.sin(a) * rad * 0.95))
    body = cv.mask().poly(pts, wobble=0.6)
    g = noise_tex(cv.W, cv.H, r, "#7b8569", 0.3, 12, 12, 3)
    P(cv, body, g, ow=2.6, depth=4, soft=0.4, hatch=0.7)
    # inner cracks
    for _ in range(9):
        a = r.random() * 2 * math.pi
        cv.stroke([(62, 64), (62 + math.cos(a) * 12, 64 + math.sin(a) * 12),
                   (62 + math.cos(a + 0.3) * 20, 64 + math.sin(a + 0.3) * 20)], 0.8, INK, 0.75)
    core_ = cv.mask().ellipse(66, 64, 11, 10, wobble=0.8)
    P(cv, core_, "#9aa483", ow=1.8, depth=2)
    # wild glaring eyes and gaping mouth at the front
    for yy in (59, 69):
        cv.paint(cv.mask().ellipse(74, yy, 3.2, 2.4), INK)
        cv.paint(cv.mask().ellipse(74.5, yy, 2.0, 1.4), (220, 240, 120))
        cv.paint(cv.mask().circle(75, yy, 0.6), INK)
    mouth = cv.mask().poly([(76, 60), (80, 64), (76, 68), (78, 64)])
    cv.paint(dilate(mouth.arr, 0.8 * cv.ss), INK)
    # floating debris: plate shard, book, fork, chair leg, stones
    def shard(x, y, s, rot, color):
        q = [(x + s * math.cos(math.radians(rot + a)), y + s * math.sin(math.radians(rot + a))) for a in (0, 110, 200, 290)]
        P(cv, cv.mask().poly(q), color, ow=1.4, depth=1, hatch=0.2)
    shard(96, 40, 6, 20, "#d8d4ca")
    shard(30, 28, 5, 70, "#d8d4ca")
    shard(100, 86, 4.5, 140, "#6a5a40")
    shard(26, 96, 6, 200, "#5a3a26")
    bk = cv.mask().poly([(84, 18), (96, 22), (93, 31), (81, 27)])
    P(cv, bk, "#5a2526", ow=1.4, depth=1.2)
    cv.stroke([(84.5, 19.5), (82, 26)], 0.6, "#d8c9a0")
    cv.stroke([(28, 52), (20, 40)], 1.6, INK)
    cv.stroke([(28, 52), (20, 40)], 0.8, "#b0b0b4")
    for k in (-1, 0, 1):
        cv.stroke([(20, 40), (17 + k * 1.5, 36)], 0.5, "#b0b0b4")
    for (x, y) in ((44, 104), (88, 104), (106, 60), (40, 20)):
        P(cv, cv.mask().circle(x, y, 2.2), "#8a8680", ow=1.0, depth=0.6, hatch=0)
    cv.grain(0.06)
    cv.drop_shadow(2.0, 3.0, 2.0, 0.55)
    cv.glow(blur(core_.arr, 6 * cv.ss) * 0.5, (180, 220, 120), 0.4)
    save(cv.image(), "tokens/poltergeist.png")


def vampire():
    cv = new("vampire")
    base(cv, ring="#8a2a2a", field="#1b1416")
    cv.xf = (1.08, 62.0, 63.0)
    ground_shadow(cv, 58, 62, 34, 46)
    # cape spread wide behind with scalloped (bat-wing) back edge
    back = []
    for i in range(7):
        t = i / 6
        y = 12 + t * 100
        x = 22 + (6 if i % 2 else 0) + 10 * abs(t - 0.5)
        back.append((x, y))
    pts = [(70, 30), (56, 14)] + back + [(56, 112), (70, 98), (78, 64)]
    cape = cv.mask().poly(catmull(pts[:2], 4) + pts[2:], wobble=0.5)
    P(cv, cape, fab(cv, "#1a1418", 0.12), ow=2.8, depth=5, hatch=0.7, light=0.15)
    # red lining visible along the front edges
    lin = cv.mask().poly([(70, 30), (60, 22), (54, 40), (58, 64), (54, 88), (60, 106), (70, 98), (64, 64)])
    P(cv, lin, fab(cv, "#6a1420"), ow=1.6, depth=2.5, hatch=0.5)
    # cape ribs
    for (x, y) in back[1:-1]:
        cv.stroke(catmull([(x + 2, y), ((x + 56) / 2, (y + 64) / 2 + 2), (58, 64)], 6), 0.8, "#3a3036", 0.9)
    # shoulders
    sh = cv.mask().ellipse(62, 64, 13, 22)
    P(cv, sh, fab(cv, "#201a1e"), depth=3, soft=0.3)
    # high collar: two tall points framing the head
    for s_ in (-1, 1):
        cl = cv.mask().poly([(60, 64 + s_ * 6), (56, 64 + s_ * 22), (72, 64 + s_ * 20), (80, 64 + s_ * 13),
                             (70, 64 + s_ * 8)])
        P(cv, cl, fab(cv, "#7a1824"), ow=2.0, depth=2, hatch=0.4)
        cv.stroke([(60, 64 + s_ * 8), (70, 64 + s_ * 17)], 0.6, INK, 0.7)
    # clawed hands forward
    for s_ in (-1, 1):
        limb(cv, [(66, 64 + s_ * 16), (78, 64 + s_ * 18), (88, 64 + s_ * 14)], 5.5, fab(cv, "#201a1e"))
        hand(cv, 90, 64 + s_ * 14, 3.0, SKIN_PALE)
        for k in range(3):
            yy = 64 + s_ * 14 + (k - 1) * 2
            cv.stroke([(92, yy), (98, yy + s_ * 0.5)], 0.7, INK)
    # pale bald head with pointed ears
    for s_ in (-1, 1):
        ear = cv.mask().poly([(70, 64 + s_ * 8), (64, 64 + s_ * 15), (75, 64 + s_ * 9.5)])
        P(cv, ear, "#d9d6cf", ow=1.4, depth=1, hatch=0.2)
    hd = cv.mask().ellipse(73, 64, 11, 9.5)
    P(cv, hd, gradient(cv.W, cv.H, "#f0eee8", "#a8a6a8", 45), ow=2.2, depth=2.5)
    # brow ridge, eyes red at front
    cv.stroke(catmull([(80, 57), (82.5, 61), (83, 64), (82.5, 67), (80, 71)], 6), 0.8, INK, 0.7)
    for yy in (60.5, 67.5):
        cv.paint(cv.mask().ellipse(82.4, yy, 1.4, 1.8), (200, 20, 30))
    cv.stroke([(70, 59), (66, 62), (66, 66), (70, 69)], 0.5, (120, 110, 130), 0.5)
    cv.grain(0.06)
    cv.drop_shadow(2.0, 3.0, 2.0, 0.55)
    for yy in (60.5, 67.5):
        cv.glow(np.clip(1 - radial(cv.W, cv.H, *cv.T(83, yy), cv.TR(4)), 0, 1), (255, 40, 40), 0.6)
    save(cv.image(), "tokens/vampire.png")


def furry(cv, pts, amp, rnd, step=2.5):
    """Spiky fur outline: alternate radii along a smooth polygon."""
    out = []
    p = np.array(catmull(pts, 7))
    c = p.mean(axis=0)
    for i, q in enumerate(p):
        d = q - c
        n = np.linalg.norm(d) + 1e-6
        k = amp * ((0.5 + 0.9 * rnd.random()) if rnd.random() < 0.42 else -0.25)
        out.append(tuple(q + d / n * k))
    return out


def werewolf():
    cv = new("werewolf")
    base(cv, ring="#7a5a3a", field="#1d1a17")
    cv.xf = (1.02, 62.0, 63.0)
    r = cv.rnd
    ground_shadow(cv, 58, 62, 38, 46)
    fur = "#4f443a"
    # hulking back/shoulders
    body = cv.mask().poly(furry(cv, [(70, 22), (44, 18), (24, 36), (18, 64), (24, 92), (44, 110), (70, 106),
                                     (80, 84), (82, 64), (80, 44), (70, 22)], 3.0, r))
    t = noise_tex(cv.W, cv.H, r, fur, 0.25, 16, 16, 3)
    P(cv, body, t, ow=2.6, depth=6, soft=0.35, hatch=0.7)
    # darker spine ridge
    sp = cv.mask().poly(furry(cv, [(70, 64), (50, 56), (26, 62), (26, 66), (50, 72), (70, 64)], 2.0, r))
    cv.paint(blur(sp.arr, 1.5 * cv.ss), "#2d2620", 0.8)
    # fur strokes following the body
    for _ in range(160):
        x, y = 22 + r.random() * 58, 20 + r.random() * 88
        if cv.a[int(y * 4), int(x * 4)] < 0.5 or math.hypot((x - 50) / 32, (y - 64) / 46) > 1:
            continue
        a = math.atan2(y - 64, x - 78) + r.normal(0, 0.2)
        ln = 3 + r.random() * 4
        cv.stroke([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], 0.6,
                  "#1c1814" if r.random() < 0.6 else "#8a7c6c", 0.75)
    # huge arms with claws reaching forward
    for s_ in (-1, 1):
        arm = cv.mask().poly(furry(cv, [(66, 64 + s_ * 30), (82, 64 + s_ * 40), (98, 64 + s_ * 34),
                                        (98, 64 + s_ * 26), (82, 64 + s_ * 28), (66, 64 + s_ * 22)], 1.8, r))
        P(cv, arm, th if False else noise_tex(cv.W, cv.H, rng("wwarm"), "#665646", 0.25, 16, 16, 3), ow=2.2, depth=3,
          hatch=0.6)
        pw = cv.mask().ellipse(100, 64 + s_ * 30, 5.5, 6.5)
        P(cv, pw, "#4a3f36", ow=1.8, depth=1.5)
        for k in range(4):
            yy = 64 + s_ * 30 + (k - 1.5) * 3.2
            cl = cv.mask().poly([(104, yy - 1), (112, yy + s_ * 0.8), (104, yy + 1)])
            P(cv, cl, "#e6decb", ow=1.0, depth=0.6, hatch=0)
    # head with long snout toward +X
    th = noise_tex(cv.W, cv.H, rng("wwhead"), "#7a6652", 0.25, 16, 16, 3)
    hd = cv.mask().poly(furry(cv, [(86, 64), (80, 51), (66, 49), (60, 64), (66, 79), (80, 77), (86, 64)], 1.8, r))
    P(cv, hd, th, ow=2.4, depth=3, hatch=0.5, light=0.35)
    for k in range(14):
        yy = 52 + k * 1.8
        cv.stroke([(64, yy), (78, 64 + (yy - 64) * 0.6)], 0.5, "#2a221c", 0.6)
    sn = cv.mask().ellipse(92, 64, 11.5, 6.5)
    P(cv, sn, noise_tex(cv.W, cv.H, r, "#8c7a66", 0.2), ow=2.2, depth=2, light=0.4)
    cv.paint(cv.mask().ellipse(101, 64, 2.8, 3.4), INK)
    cv.paint(cv.mask().circle(100.4, 62.8, 0.8), (140, 140, 150), 0.8)
    cv.stroke([(84, 64), (100, 64)], 0.6, INK, 0.6)
    # ears swept back
    for s_ in (-1, 1):
        ear = cv.mask().poly([(74, 64 + s_ * 8), (60, 64 + s_ * 16), (70, 64 + s_ * 13), (78, 64 + s_ * 12)])
        P(cv, ear, "#4a3f36", ow=1.6, depth=1, hatch=0.4)
        cv.paint(cv.mask().ellipse(82, 64 + s_ * 6, 1.8, 1.3), (240, 170, 40))
    cv.grain(0.06)
    cv.drop_shadow(2.0, 3.0, 2.0, 0.55)
    for s_ in (-1, 1):
        cv.glow(np.clip(1 - radial(cv.W, cv.H, *cv.T(82, 64 + s_ * 6), cv.TR(4)), 0, 1),
                (255, 170, 40), 0.55)
    save(cv.image(), "tokens/werewolf.png")


def shapeshifter():
    cv = new("shapeshifter")
    base(cv, ring="#7a4a80", field="#1a151c")
    cv.xf = (1.12, 62.0, 63.0)
    r = cv.rnd
    ground_shadow(cv, 60, 62, 34, 36)
    flesh = "#6e4a72"
    # tentacles
    for k in range(9):
        a = k * 2 * math.pi / 9 + r.normal(0, 0.2)
        if math.cos(a) > 0.8:
            continue
        ln = 30 + r.random() * 14
        pts = [(60 + math.cos(a) * 10, 64 + math.sin(a) * 10)]
        aa = a
        for j in range(4):
            aa += r.normal(0, 0.45)
            pts.append((pts[-1][0] + math.cos(aa) * ln / 4, pts[-1][1] + math.sin(aa) * ln / 4))
        cp = catmull(pts, 10)
        left, right = [], []
        for i, (x, y) in enumerate(cp):
            tt = i / (len(cp) - 1)
            w = 6.5 * (1 - tt) + 0.8
            if i < len(cp) - 1:
                dx, dy = cp[i + 1][0] - x, cp[i + 1][1] - y
            n = math.hypot(dx, dy) + 1e-6
            left.append((x - dy / n * w, y + dx / n * w))
            right.append((x + dy / n * w, y - dx / n * w))
        tm = cv.mask().poly(left + right[::-1])
        P(cv, tm, noise_tex(cv.W, cv.H, rng(f"ss{k}"), mix(flesh, "#000000", 0.15), 0.2), ow=1.8, depth=2, hatch=0.5)
        for i in range(2, len(cp) - 3, 4):
            cv.paint(cv.mask().circle(cp[i][0], cp[i][1], 1.1), "#c8a0b0", 0.8)
    # lumpy core mass
    core_ = cv.mask()
    for _ in range(9):
        a = r.random() * 2 * math.pi
        d = r.random() * 12
        core_.ellipse(62 + math.cos(a) * d, 64 + math.sin(a) * d, 12 + r.random() * 6, 11 + r.random() * 6, wobble=1)
    P(cv, core_, noise_tex(cv.W, cv.H, r, flesh, 0.3, 10, 10, 3), ow=2.6, depth=4, soft=0.45, hatch=0.6)
    # veins
    for _ in range(10):
        a = r.random() * 2 * math.pi
        cv.stroke(catmull([(62, 64), (62 + math.cos(a) * 8, 64 + math.sin(a + 0.3) * 8),
                           (62 + math.cos(a + 0.4) * 18, 64 + math.sin(a + 0.4) * 16)], 6), 0.6, "#3a1e3e", 0.7)
    # many eyes
    eyes = [(78, 58, 3.6), (78, 70, 3.6), (70, 48, 2.6), (70, 80, 2.8), (58, 56, 2.2), (60, 72, 2.4),
            (50, 64, 2.0), (84, 64, 2.2), (66, 64, 2.0), (54, 46, 1.8), (52, 82, 1.8)]
    for (x, y, rr) in eyes:
        cv.paint(dilate(cv.mask().ellipse(x, y, rr, rr * 0.8).arr, 1.0 * cv.ss), INK)
        cv.paint(cv.mask().ellipse(x, y, rr, rr * 0.8), "#e6dcc0")
        cv.paint(cv.mask().ellipse(x + rr * 0.2, y, rr * 0.55, rr * 0.55), (220, 190, 40))
        cv.paint(cv.mask().ellipse(x + rr * 0.25, y, rr * 0.16, rr * 0.45), INK)
    # toothy maw at the front
    mw = cv.mask().ellipse(88, 64, 3.2, 7)
    cv.paint(dilate(mw.arr, 0.8 * cv.ss), INK)
    cv.paint(mw, (60, 10, 20))
    for k in range(5):
        yy = 59 + k * 2.5
        cv.paint(cv.mask().poly([(86, yy - 0.8), (89, yy), (86, yy + 0.8)]), "#e6dcc0")
    cv.grain(0.06)
    cv.drop_shadow(2.0, 3.0, 2.0, 0.55)
    save(cv.image(), "tokens/shapeshifter.png")


def cat():
    cv = new("cat")
    base(cv, ring="#6a6050", field="#4a4541")
    cv.xf = (1.55, 62.0, 63.0)
    ground_shadow(cv, 60, 62, 20, 14)
    black = "#1d1b1f"
    t = noise_tex(cv.W, cv.H, cv.rnd, black, 0.25, 20, 20, 3)
    # tail curling behind
    tail = cv.mask().curve([(46, 64), (36, 66), (30, 76), (34, 86), (42, 86)], 4.2, n=10)
    P(cv, tail, t, ow=1.8, depth=1.5, hatch=0.3, light=0.5)
    body = cv.mask().ellipse(58, 64, 15, 10.5, wobble=0.4)
    P(cv, body, t, ow=2.2, depth=2.5, light=0.5, hatch=0.3)
    cv.stroke(catmull([(46, 64), (58, 63.5), (70, 64)], 6), 0.6, (90, 96, 120), 0.6)
    # paws peeking
    for (x, y) in ((70, 54.5), (70, 73.5), (48, 55), (48, 73)):
        P(cv, cv.mask().ellipse(x, y, 2.8, 2.0), t, ow=1.2, depth=0.8, hatch=0, light=0.4)
    # head + ears pointing forward-out
    hd = cv.mask().circle(76, 64, 8.2)
    P(cv, hd, t, ow=2.0, depth=2, light=0.55, hatch=0.2)
    for s_ in (-1, 1):
        ear = cv.mask().poly([(74, 64 + s_ * 4), (84, 64 + s_ * 9.5), (79, 64 + s_ * 2.5)])
        P(cv, ear, t, ow=1.4, depth=0.8, hatch=0, light=0.4)
        cv.paint(cv.mask().poly([(76, 64 + s_ * 4.5), (82, 64 + s_ * 8), (79, 64 + s_ * 3.5)]), (90, 50, 60), 0.7)
    # glowing yellow eyes at the front
    for s_ in (-1, 1):
        cv.paint(cv.mask().ellipse(82.4, 64 + s_ * 2.8, 1.5, 1.8), (240, 205, 60))
        cv.paint(cv.mask().ellipse(82.8, 64 + s_ * 2.8, 0.4, 1.2), INK)
    cv.paint(cv.mask().ellipse(84.4, 64, 0.9, 1.1), (150, 90, 100))
    for s_ in (-1, 1):
        for k in (-1, 1):
            cv.stroke([(84, 64 + s_ * 1.2), (90, 64 + s_ * (2.5 + k))], 0.3, (200, 200, 200), 0.6)
    cv.grain(0.05)
    cv.drop_shadow(2.0, 3.0, 2.0, 0.55)
    for s_ in (-1, 1):
        cv.glow(np.clip(1 - radial(cv.W, cv.H, *cv.T(82.5, 64 + s_ * 2.8), cv.TR(3.6)), 0, 1),
                (255, 220, 80), 0.6)
    save(cv.image(), "tokens/cat.png")


def harbinger():
    cv = new("harbinger")
    base(cv, ring="#9a1c1c", field="#0d0b0d", rim="#2a2426")
    r = cv.rnd
    g = np.clip(1 - radial(cv.W, cv.H, 62 * cv.ss, 62 * cv.ss, 56 * cv.ss), 0, 1)
    cv.mul(g, 0.5, (0, 0, 0))
    # tattered robes: long irregular strips trailing back, filling the base
    pts = []
    n = 34
    for i in range(n):
        a = 2 * math.pi * i / n + r.normal(0, 0.04)
        front = math.cos(a)
        if front > 0.5:
            rad = 30 + r.normal(0, 1.5)
        else:
            spike = r.random() ** 0.7 * 16 if i % 2 else -r.random() * 4
            rad = 40 + spike * (1 - front) * 0.8
        pts.append((60 + math.cos(a) * rad, 64 + math.sin(a) * rad))
    robe = cv.mask().poly(pts, wobble=0.5)
    rt = noise_tex(cv.W, cv.H, r, "#17141b", 0.3, 14, 14, 3)
    P(cv, robe, rt, ow=2.8, depth=6, hatch=0.8, light=0.12, soft=0.4)
    for k in range(9):
        a = math.pi * (0.5 + k / 8 * 1.0) + r.normal(0, 0.05)
        cv.stroke(catmull([(56 + math.cos(a) * 22, 64 + math.sin(a) * 22),
                           (58 + math.cos(a + r.normal(0, 0.1)) * 34, 64 + math.sin(a) * 33),
                           (60 + math.cos(a) * 46, 64 + math.sin(a) * 44)], 6), 0.7, (60, 54, 68), 0.7)
    # skeletal arms with long claws reaching forward
    for s_ in (-1, 1):
        limb(cv, [(64, 64 + s_ * 22), (80, 64 + s_ * 30), (94, 64 + s_ * 29)], 7, rt)
        bx, by = 96, 64 + s_ * 29
        for k in range(4):
            yy = by + (k - 1.5) * 3.4
            pts_ = [(bx - 2, by), (bx + 6, yy), (bx + 13, yy + s_ * 1.6), (bx + 16, yy + s_ * 3.4)]
            cv.stroke(pts_, 2.2, INK)
            cv.stroke(pts_, 1.1, "#ddd6c4")
    # pale corona (halo of cold light around the head)
    halo = cv.mask().circle(76, 64, 27)
    cv.paint(blur(halo.arr, 4 * cv.ss), (200, 230, 238), 0.55)
    for k in range(12):
        a = k * 2 * math.pi / 12 + 0.13
        ray = cv.mask().poly([(76 + math.cos(a - 0.07) * 20, 64 + math.sin(a - 0.07) * 20),
                              (76 + math.cos(a) * 33, 64 + math.sin(a) * 33),
                              (76 + math.cos(a + 0.07) * 20, 64 + math.sin(a + 0.07) * 20)])
        cv.paint(blur(ray.arr, 0.5 * cv.ss), (235, 248, 250), 0.85)
    ring_ = np.clip(cv.mask().circle(76, 64, 24.5).arr - cv.mask().circle(76, 64, 22.6).arr, 0, 1)
    cv.paint(ring_, (245, 252, 252), 0.95)
    # hood
    hood = cv.mask().ellipse(73, 64, 19, 20.5, wobble=0.6)
    P(cv, hood, rt, ow=2.4, depth=3, hatch=0.6)
    # iron-and-gold crown: tall spikes (crown + skull drawn 1.2x)
    cv.xf = (1.2, 78.0, 64.0)
    gold = gradient(cv.W, cv.H, "#d6b468", "#4e3a1a", 45)
    crown = cv.mask()
    for k in range(10):
        a = k * 2 * math.pi / 10 + math.pi / 10
        ln = 22 if k % 2 == 0 else 19
        crown.poly([(77 + math.cos(a - 0.2) * 13, 64 + math.sin(a - 0.2) * 12.5),
                    (77 + math.cos(a) * ln, 64 + math.sin(a) * ln),
                    (77 + math.cos(a + 0.2) * 13, 64 + math.sin(a + 0.2) * 12.5)])
    crown.ellipse(77, 64, 15.5, 15)
    P(cv, crown, gold, ow=1.8, depth=1.5, hatch=0.4)
    for k in range(10):
        a = k * 2 * math.pi / 10 + math.pi / 10
        cv.paint(cv.mask().circle(77 + math.cos(a) * 14.2, 64 + math.sin(a) * 13.8, 1.1), (150, 20, 20))
    # skull
    sk = cv.mask().ellipse(78, 64, 13.5, 12.5)
    P(cv, sk, gradient(cv.W, cv.H, "#f2ecdc", "#9a9284", 45), ow=2.2, depth=3, hatch=0.5)
    cv.stroke(catmull([(68, 59), (74, 61.5), (79, 58)], 6), 0.7, INK, 0.7)
    cv.stroke(catmull([(70, 69), (75, 67), (78, 70)], 6), 0.5, INK, 0.5)
    for yy in (58.5, 69.5):
        cv.paint(cv.mask().ellipse(86.5, yy, 3.4, 3.6), (8, 6, 8))
        cv.paint(cv.mask().circle(87.2, yy, 1.0), (255, 70, 50))
    cv.paint(cv.mask().poly([(89.5, 62.4), (91.6, 64), (89.5, 65.6)]), (8, 6, 8))
    for k in range(7):
        yy = 58.6 + k * 1.8
        cv.paint(cv.mask().rect(90.6, yy, 92.4, yy + 1.4, 0.3), "#e6e0d0")
        cv.stroke([(90.6, yy), (92.4, yy)], 0.3, INK, 0.9)
    cv.grain(0.06)
    cv.drop_shadow(2.0, 3.0, 2.0, 0.6)
    gl = np.clip(1 - radial(cv.W, cv.H, 76 * cv.ss, 64 * cv.ss, 40 * cv.ss), 0, 1) ** 2
    cv.glow(gl * (1 - sk.arr) * (1 - crown.arr), (190, 230, 240), 0.35)
    for yy in (58.5, 69.5):
        cv.glow(np.clip(1 - radial(cv.W, cv.H, *cv.T(87.2, yy), cv.TR(4.5)), 0, 1), (255, 60, 40), 0.8)
    cv.xf = None
    save(cv.image(), "tokens/harbinger.png")


ALL = [investigator, occupant_a, occupant_b, occupant_c, occupant_bitten, occupant_d, occupant_e, occupant_f,
       occupant_bitten_variants, shade, poltergeist, vampire, werewolf, shapeshifter, cat, harbinger]


def build_all(only=None):
    for f in ALL:
        if only and f.__name__ not in only:
            continue
        f()


if __name__ == "__main__":
    import sys
    build_all(sys.argv[1:] or None)
