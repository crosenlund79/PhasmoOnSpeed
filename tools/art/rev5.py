"""Revision 5 art: period investigation kit (Witch's Needle, lanterns, Whisper Box,
scrying mirror), the voodoo doll, keepsakes, ashes and embers, and tokens for the
Blightness, the Crawler and the Lost One. Same procedural ink-and-wash style as
objects.py / tokens.py; every drawer works in the 64x64 design space (items and
icons) or the 128x128 token space."""
from __future__ import annotations

import math

import numpy as np

import objects as O
from core import INK, OUT, blur, catmull, col, dilate, ellipse_pts, gradient, noise_tex, radial, rng, save
OUT_TOK = OUT / "tokens"
from objects import BRASS, P, glow_at, gloss, poly_rot


# --------------------------------------------------------------------------
# Witch's Needle
# --------------------------------------------------------------------------
def witch_needle(cv, st, frenzy=False):
    """A slender glass tube on a diagonal, a dark needle inside, a corked end sealed with a sigil."""
    ang = -38
    cx, cy = 30, 34
    tube_pts = poly_rot([(cx - 24, cy - 5.5), (cx + 16, cy - 5.5), (cx + 16, cy + 5.5), (cx - 24, cy + 5.5)], cx, cy, ang)
    tube = cv.mask().poly(tube_pts)
    end = poly_rot([(cx - 24, cy)], cx, cy, ang)[0]
    tube.circle(end[0], end[1], 5.5)
    cv.paint(dilate(tube.arr, 0.7 * cv.ss), INK, 0.8)
    cv.paint(tube, gradient(cv.W, cv.H, "#f6fafa", "#c4d4d8", ang + 90), 0.55)
    # the needle: pivot near the cork, tip swung against the glass when frenzied
    swing = 4.0 if frenzy else 0.6
    a = poly_rot([(cx + 12, cy)], cx, cy, ang)[0]
    b = poly_rot([(cx - 21, cy + swing)], cx, cy, ang)[0]
    cv.stroke([a, b], st.thin * 2.2, (24, 22, 26))
    cv.stroke([a, b], st.thin * 0.8, (130, 130, 140), 0.8)
    cv.paint(cv.mask().circle(a[0], a[1], 2.0), "#3a3430")
    if frenzy:
        # strike sparks and rattle lines where the tip hits the glass
        for k in range(4):
            sx, sy = b[0] + (k - 1.5) * 2.4, b[1] + 4 + (k % 2) * 2
            cv.stroke([(sx, sy), (sx + 2.5, sy + 4.5)], st.thin, (255, 230, 170), 0.9)
        for k, off in enumerate((-9, -14)):
            p0 = poly_rot([(cx - 18, cy + off)], cx, cy, ang)[0]
            p1 = poly_rot([(cx - 6, cy + off)], cx, cy, ang)[0]
            cv.stroke([p0, p1], st.thin * 0.9, INK, 0.7 - k * 0.25)
        glow_at(cv, b[0], b[1], 10, (255, 200, 120), 0.3)
    # glass highlight
    h0 = poly_rot([(cx - 20, cy - 3.2)], cx, cy, ang)[0]
    h1 = poly_rot([(cx + 12, cy - 3.2)], cx, cy, ang)[0]
    cv.stroke([h0, h1], st.thin * 0.9, "#ffffff", 0.6)
    # cork stopper and its wax sigil seal
    ck = cv.mask().poly(poly_rot([(cx + 15, cy - 6.5), (cx + 27, cy - 5.5), (cx + 27, cy + 5.5), (cx + 15, cy + 6.5)], cx, cy, ang))
    P(cv, ck, noise_tex(cv.W, cv.H, rng("cork"), "#9a7046", 0.25, 18, 18), st, depth=1.2, hatch=0.3)
    sc = poly_rot([(cx + 21, cy)], cx, cy, ang)[0]
    P(cv, cv.mask().circle(sc[0] + 1.5, sc[1] + 4.5, 5.2), gradient(cv.W, cv.H, "#b8261c", "#5a0a08", 45), st, ow=1.4, depth=1, hatch=0)
    star = [(sc[0] + 1.5 + math.cos(math.radians(-90 + k * 144)) * 3.6, sc[1] + 4.5 + math.sin(math.radians(-90 + k * 144)) * 3.6) for k in range(6)]
    cv.stroke(star, 0.7, "#e8c878", 0.9)


# --------------------------------------------------------------------------
# lanterns
# --------------------------------------------------------------------------
def lantern(cv, st, violet=False):
    cx, cy = 32, 35
    glass = (190, 130, 255) if violet else (255, 200, 110)
    glow_at(cv, cx, cy + 2, 30, glass, 0.45)
    # top cap and ring handle
    cv.stroke(ellipse_pts(cx, cy - 23, 6, 5, 24, 0, 180, 360), st.thin * 1.8, INK)
    cap = cv.mask().poly([(cx - 12, cy - 13), (cx - 6, cy - 19), (cx + 6, cy - 19), (cx + 12, cy - 13)])
    P(cv, cap, gradient(cv.W, cv.H, "#3a3836", "#121010", 45), st, depth=1.5)
    # glass chamber
    ch = cv.mask().rect(cx - 10, cy - 13, cx + 10, cy + 13, 1.5)
    cv.paint(dilate(ch.arr, 0.8 * cv.ss), INK)
    gc = "#c8a8ff" if violet else "#ffe6a8"
    gd = "#5a2a9a" if violet else "#c8782a"
    cv.paint(ch, gradient(cv.W, cv.H, gc, gd, 90))
    # flame inside
    fx, fy = cx, cy + 2
    fl = cv.mask().poly(catmull([(fx - 3.4, fy + 3), (fx - 2.4, fy - 2), (fx, fy - 9), (fx + 2.4, fy - 2), (fx + 3.4, fy + 3), (fx, fy + 5), (fx - 3.4, fy + 3)], 6))
    cv.paint(dilate(fl.arr, 1.0 * cv.ss), (235, 140, 255) if violet else (255, 140, 40))
    cv.paint(fl, (250, 235, 255) if violet else (255, 245, 200))
    # iron frame bars and base
    for x in (cx - 10, cx, cx + 10):
        cv.stroke([(x, cy - 13), (x, cy + 13)], st.thin * 1.4, "#2a2624")
    base = cv.mask().rect(cx - 13, cy + 12, cx + 13, cy + 18, 2)
    P(cv, base, gradient(cv.W, cv.H, "#4a4440", "#141210", 45), st, depth=1.5)
    gloss(cv, cx - 6, cy - 4, 1.2, 5, 0.6)


# --------------------------------------------------------------------------
# Whisper Box
# --------------------------------------------------------------------------
def whisper_box(cv, st, open_=False):
    cx, cy = 32, 38
    wood = noise_tex(cv.W, cv.H, rng("wbox"), "#6a4228", 0.22, 22, 5)
    body = cv.mask().rect(cx - 19, cy - 8, cx + 19, cy + 14, 2)
    P(cv, body, wood, st, depth=2)
    for y in (cy - 2, cy + 6):
        cv.stroke([(cx - 18, y), (cx + 18, y)], st.thin * 0.6, (40, 24, 14), 0.5)
    if open_:
        lid = cv.mask().poly([(cx - 19, cy - 8), (cx + 19, cy - 8), (cx + 15, cy - 24), (cx - 15, cy - 24)])
        P(cv, lid, wood, st, depth=1.5)
        inside = cv.mask().rect(cx - 16, cy - 10, cx + 16, cy - 6, 1)
        cv.paint(inside, (30, 18, 12))
        for k, rr in enumerate((7, 12, 17)):
            pts = [(cx - rr + 4, cy - 26 - k * 3), (cx, cy - 30 - k * 4), (cx + rr - 4, cy - 26 - k * 3)]
            cv.stroke(catmull(pts, 10), st.thin * 1.2, (200, 220, 230), 0.85 - k * 0.2)
    else:
        lid = cv.mask().rect(cx - 20, cy - 15, cx + 20, cy - 7, 2)
        P(cv, lid, wood, st, depth=1.8)
    # brass hinges and lock plate with keyhole
    for x in (cx - 13, cx + 13):
        P(cv, cv.mask().rect(x - 3, cy - 10, x + 3, cy - 5, 0.6), BRASS, st, ow=1.0, depth=0.8, hatch=0)
    lk = cv.mask().rect(cx - 4.5, cy - 4, cx + 4.5, cy + 5, 1)
    P(cv, lk, gradient(cv.W, cv.H, "#e0c47a", "#6a5024", 45), st, ow=1.2, depth=1, hatch=0)
    cv.paint(cv.mask().circle(cx, cy - 0.5, 1.4), INK)
    cv.paint(cv.mask().rect(cx - 0.6, cy - 0.5, cx + 0.6, cy + 3), INK)


# --------------------------------------------------------------------------
# scrying mirror
# --------------------------------------------------------------------------
def scrying_mirror(cv, st, orbs=True):
    cx, cy = 32, 30
    h = cv.mask().rect(cx - 3, cy + 18, cx + 3, cy + 31, 1.5)
    P(cv, h, noise_tex(cv.W, cv.H, rng("smh"), "#3a2418", 0.2), st, depth=1.2)
    fr = cv.mask().ellipse(cx, cy, 18, 21)
    P(cv, fr, gradient(cv.W, cv.H, "#e2c27a", "#5a4018", 45), st, depth=2)
    for k in range(10):
        a = math.radians(k * 36)
        cv.paint(cv.mask().circle(cx + math.cos(a) * 16.5, cy + math.sin(a) * 19.5, 1.3), "#f4dc9a", 0.8)
    gl = cv.mask().ellipse(cx, cy, 13, 16)
    cv.paint(dilate(gl.arr, 0.8 * cv.ss), INK)
    cv.paint(gl, gradient(cv.W, cv.H, "#2a3036", "#06080a", 30))
    if orbs:
        for (x, y, r) in ((cx - 4, cy - 6, 2.6), (cx + 5, cy + 3, 1.8), (cx - 2, cy + 8, 1.3)):
            glow_at(cv, x, y, 5, (170, 230, 245), 0.6)
            cv.paint(cv.mask().circle(x, y, r * 0.6), (220, 250, 255), 0.9)
    cv.stroke([(cx - 8, cy - 9), (cx - 3, cy - 14)], st.thin, "#ffffff", 0.45)


# --------------------------------------------------------------------------
# voodoo doll, keepsakes, ashes
# --------------------------------------------------------------------------
def voodoo_doll(cv, st):
    cx, cy = 32, 32
    burlap = noise_tex(cv.W, cv.H, rng("burlap"), "#9a8058", 0.3, 30, 30)
    body = cv.mask()
    body.circle(cx, cy - 13, 9)
    body.rect(cx - 7, cy - 6, cx + 7, cy + 10, 3)
    body.line([(cx - 6, cy - 3), (cx - 17, cy + 2)], 6)
    body.line([(cx + 6, cy - 3), (cx + 17, cy + 2)], 6)
    body.line([(cx - 4, cy + 8), (cx - 8, cy + 22)], 6.5)
    body.line([(cx + 4, cy + 8), (cx + 8, cy + 22)], 6.5)
    P(cv, body, burlap, st, depth=1.8, hatch=0.4)
    cv.stroke([(cx - 7, cy - 1), (cx + 7, cy - 1)], st.thin * 1.4, "#5a1a14")   # twine
    for (ex, ey) in ((cx - 3.5, cy - 14), (cx + 3.5, cy - 14)):
        cv.stroke([(ex - 1.8, ey - 1.8), (ex + 1.8, ey + 1.8)], st.thin * 1.1, INK)
        cv.stroke([(ex - 1.8, ey + 1.8), (ex + 1.8, ey - 1.8)], st.thin * 1.1, INK)
    cv.stroke([(cx - 3, cy - 9), (cx - 1, cy - 8), (cx + 1, cy - 9), (cx + 3, cy - 8)], st.thin * 0.8, INK)
    for k in range(4):
        cv.stroke([(cx - 3 + k * 2, cy - 9.5), (cx - 3 + k * 2, cy - 7.5)], st.thin * 0.5, INK)
    # pins with coloured heads
    for (x0, y0, x1, y1, c) in ((cx + 2, cy + 2, cx + 14, cy - 10, "#c8282a"), (cx - 4, cy - 15, cx - 15, cy - 25, "#2a2a2a"),
                                (cx + 1, cy + 6, cx + 16, cy + 12, "#e0c040")):
        cv.stroke([(x0, y0), (x1, y1)], st.thin * 0.9, "#b0b0b8")
        P(cv, cv.mask().circle(x1, y1, 2.4), c, st, ow=1.0, depth=0.6, hatch=0)
    cv.paint(cv.mask().circle(cx + 1, cy + 1, 2.2), "#7a1018", 0.8)   # a dark heart patch


def music_box(cv, st):
    cx, cy = 32, 36
    body = cv.mask().rect(cx - 17, cy - 9, cx + 17, cy + 13, 2)
    P(cv, body, noise_tex(cv.W, cv.H, rng("mbox"), "#5a2e2a", 0.2, 18, 5), st, depth=2)
    lid = cv.mask().poly([(cx - 17, cy - 9), (cx + 17, cy - 9), (cx + 13, cy - 22), (cx - 13, cy - 22)])
    P(cv, lid, noise_tex(cv.W, cv.H, rng("mboxl"), "#6a3a32", 0.2, 18, 5), st, depth=1.5)
    cv.paint(cv.mask().rect(cx - 13, cy - 11, cx + 13, cy - 7, 1), "#2a1410")
    # a tiny dancer
    cv.stroke([(cx, cy - 11), (cx, cy - 18)], st.thin, "#e8d8c0")
    cv.paint(cv.mask().ellipse(cx, cy - 15, 3.4, 1.6), "#e8c8d0", 0.9)
    cv.paint(cv.mask().circle(cx, cy - 20, 1.6), "#f0e0d0")
    for x in (cx - 10, cx + 10):
        cv.stroke(ellipse_pts(x, cy + 2, 3, 3, 16), st.thin, BRASS)
    P(cv, cv.mask().rect(cx + 17, cy + 1, cx + 22, cy + 4, 1), BRASS, st, ow=1.0, depth=0.6, hatch=0)   # key


def locket(cv, st):
    cx, cy = 32, 38
    chain = [(cx - 14 + k * 2.4, cy - 26 + abs(k - 5.8) ** 1.6 * 0.9) for k in range(12)]
    for (x, y) in chain:
        cv.stroke(ellipse_pts(x, y, 1.3, 1.0, 10), st.thin * 0.7, BRASS, 0.9)
    lk = cv.mask().ellipse(cx, cy, 13, 15)
    P(cv, lk, gradient(cv.W, cv.H, "#f0d48a", "#6a4a18", 45), st, depth=2)
    cv.stroke(ellipse_pts(cx, cy, 9, 11, 28), st.thin * 0.9, "#8a6a2a", 0.9)
    # engraved initial
    cv.stroke(catmull([(cx - 4, cy + 5), (cx - 4, cy - 5), (cx + 3, cy - 2), (cx - 4, cy + 1), (cx + 4, cy + 5)], 6), st.thin * 1.1, "#5a3a10")
    gloss(cv, cx - 5, cy - 6, 2, 3, 0.6)


def child_shoe(cv, st):
    cx, cy = 32, 34
    sole = cv.mask().poly(catmull([(cx - 18, cy + 8), (cx - 20, cy), (cx - 14, cy - 6), (cx + 4, cy - 6), (cx + 16, cy - 2),
                                   (cx + 20, cy + 6), (cx + 14, cy + 12), (cx - 12, cy + 12), (cx - 18, cy + 8)], 6))
    P(cv, sole, gradient(cv.W, cv.H, "#5a3a2a", "#20140c", 45), st, depth=2)
    up = cv.mask().poly(catmull([(cx - 16, cy + 4), (cx - 14, cy - 12), (cx - 2, cy - 14), (cx + 6, cy - 6), (cx + 14, cy),
                                 (cx + 12, cy + 6), (cx - 16, cy + 4)], 6))
    P(cv, up, gradient(cv.W, cv.H, "#8a5a44", "#3a2018", 45), st, depth=1.6)
    cv.stroke([(cx - 6, cy - 10), (cx + 4, cy - 4)], st.thin * 1.4, "#e8dcc4")   # strap
    P(cv, cv.mask().circle(cx + 4, cy - 4, 1.8), BRASS, st, ow=0.8, depth=0.5, hatch=0)


def ash_pile(cv, st, embers=True):
    r = rng("ash")
    cx, cy = 32, 32
    m = cv.mask().ellipse(cx, cy, 24, 18, wobble=2.5)
    cv.paint(blur(m.arr, 2.0 * cv.ss), (40, 36, 34), 0.85)
    for _ in range(40):
        x, y = cx + r.normal(0, 10), cy + r.normal(0, 7)
        cv.paint(cv.mask().circle(x, y, r.uniform(0.6, 2.2)), (150 + r.integers(0, 50),) * 3, 0.7)
    if embers:
        for _ in range(14):
            x, y = cx + r.normal(0, 9), cy + r.normal(0, 6)
            glow_at(cv, x, y, 4, (255, 110, 30), 0.5)
            cv.paint(cv.mask().circle(x, y, r.uniform(0.8, 1.8)), (255, 170 + r.integers(0, 60), 60))


# --------------------------------------------------------------------------
# tokens
# --------------------------------------------------------------------------
def _token_base(name, ring, field):
    import tokens as T
    cv = T.new(name)
    T.base(cv, ring=ring, field=field)
    cv.xf = (1.12, 62.0, 63.0)
    return cv, T


def blightness():
    """A blot of rot and distortion: concentric warped rings around a sick-green core."""
    cv, T = _token_base("blightness", "#6a7a3a", "#14160f")
    r = cv.rnd
    g = np.clip(1 - radial(cv.W, cv.H, *cv.T(62, 62), cv.TR(44)), 0, 1) ** 1.4
    cv.glow(g, (150, 190, 70), 0.35)
    for k, rr in enumerate((34, 26, 18)):
        pts = [(62 + math.cos(a) * rr * (1 + 0.12 * math.sin(a * 5 + k)), 62 + math.sin(a) * rr * (1 + 0.12 * math.cos(a * 4 - k)))
               for a in np.linspace(0, 2 * math.pi, 48)]
        cv.stroke(pts, 1.4 - k * 0.2, (180, 210, 110), 0.55 + k * 0.1)
    core = cv.mask().poly(catmull([(62 + math.cos(a) * (14 + r.normal(0, 2.5)), 62 + math.sin(a) * (14 + r.normal(0, 2.5)))
                                   for a in np.linspace(0, 2 * math.pi, 12, endpoint=False)], 6), wobble=1.2)
    cv.paint(dilate(core.arr, 1.4 * cv.ss), (20, 26, 10))
    cv.paint(core, gradient(cv.W, cv.H, "#3c4a1e", "#0c1006", 45))
    for k in range(9):
        a = r.uniform(0, 2 * math.pi)
        p0 = (62 + math.cos(a) * 10, 62 + math.sin(a) * 10)
        p1 = (62 + math.cos(a) * (28 + r.uniform(0, 10)), 62 + math.sin(a) * (28 + r.uniform(0, 10)))
        cv.stroke(catmull([p0, ((p0[0] + p1[0]) / 2 + r.normal(0, 4), (p0[1] + p1[1]) / 2 + r.normal(0, 4)), p1], 8), 1.0, (60, 80, 30), 0.8)
    for yy in (57, 67):
        cv.paint(cv.mask().ellipse(72, yy, 2.4, 1.6), (210, 240, 120))
    T.finish(cv, "tokens/blightness.png")


def crawler():
    """Long and low: a starved thing dragging itself forward on spidery arms."""
    cv, T = _token_base("crawler", "#5a4a5e", "#141216")
    skin = "#7a7470"
    T.ground_shadow(cv, 60, 64, 34, 16, 0.6)
    body = cv.mask().poly(catmull([(30, 60), (44, 52), (66, 52), (80, 58), (84, 64), (80, 70), (66, 76), (44, 76), (30, 68), (30, 60)], 8))
    T.P(cv, body, gradient(cv.W, cv.H, "#8a8480", "#2a2628", 0), depth=2)
    for k in range(5):
        x = 42 + k * 7
        cv.stroke([(x, 54 + k % 2), (x + 2, 74 - k % 2)], 0.8, (40, 36, 38), 0.6)   # ribs
    for (sy, s) in ((50, -1), (78, 1)):
        arm = [(70, 64 + s * 6), (86, sy + s * 4), (98, sy + s * 2), (108, sy + s * 8)]
        T.limb(cv, arm, 4.2, skin)
        for f in range(4):
            cv.stroke([(108, sy + s * 8), (114 + f * 0.8, sy + s * (4 + f * 3))], 1.0, INK, 0.9)
    for (sy, s) in ((54, -1), (74, 1)):
        T.limb(cv, [(36, 64 + s * 6), (24, sy + s * 6), (14, sy + s * 2)], 3.6, skin)
    hd = cv.mask().ellipse(90, 64, 10, 9)
    T.P(cv, hd, gradient(cv.W, cv.H, "#a8a29c", "#4a4644", 45), depth=2)
    cv.paint(cv.mask().poly([(84, 60), (100, 62), (100, 66), (84, 68)]), (30, 6, 8))   # gaping mouth
    for yy in (58, 70):
        cv.paint(cv.mask().circle(93, yy, 1.4), (230, 220, 200))
    T.finish(cv, "tokens/crawler.png")


def lost_one():
    """A small, pale child in an old nightgown, hollow eyes, clutching nothing."""
    cv, T = _token_base("lost_one", "#8a7a9a", "#16141c")
    g = np.clip(1 - radial(cv.W, cv.H, *cv.T(62, 62), cv.TR(40)), 0, 1) ** 1.6
    cv.glow(g, (200, 200, 230), 0.3)
    gown = cv.mask().poly(catmull([(70, 64), (64, 46), (48, 40), (36, 48), (32, 64), (36, 80), (48, 88), (64, 82), (70, 64)], 8), wobble=0.8)
    T.P(cv, gown, gradient(cv.W, cv.H, "#f0ecf2", "#8a8698", 180), depth=2.5, hatch=0.35)
    for (y_, s_) in ((48, -1), (80, 1)):
        T.limb(cv, [(58, y_), (70, y_ + s_ * -2), (78, y_ + s_ * -5)], 3.0, "#d8d4da")
    # long dark hair spilling back over the gown, a narrow pale face at the front
    hair = cv.mask().poly(catmull([(76, 64), (72, 52), (60, 50), (44, 54), (38, 64), (44, 74), (60, 78), (72, 76), (76, 64)], 8), wobble=1.0)
    T.P(cv, hair, gradient(cv.W, cv.H, "#2a2226", "#0a0708", 45), depth=2, hatch=0.6)
    for k in range(6):
        y0 = 54 + k * 4
        cv.stroke(catmull([(70, 64 + (y0 - 64) * 0.5), (56, y0), (42, y0 + (y0 - 64) * 0.2)], 8), 0.7, (70, 60, 66), 0.6)
    face = cv.mask().ellipse(77, 64, 5.5, 8)
    T.P(cv, face, gradient(cv.W, cv.H, "#f6f2f6", "#bab6c6", 45), ow=1.6, depth=1.2, hatch=0.15)
    for yy in (60.5, 67.5):
        cv.paint(cv.mask().ellipse(80, yy, 1.6, 2.0), (10, 8, 14))
        cv.stroke([(79.5, yy + 1.5), (78.5, yy + 6)], 0.7, (60, 50, 80), 0.6)   # tear streaks
    T.finish(cv, "tokens/lost_one.png")


def drowned_sailor():
    """An old sailor in a sodden, tattered pea coat and tricorn, seaweed in his
    collar, a halo of sea water dripping from him."""
    cv, T = _token_base("drowned_sailor", "#3a5a66", "#0e1416")
    r = cv.rnd
    g = np.clip(1 - radial(cv.W, cv.H, *cv.T(62, 62), cv.TR(44)), 0, 1) ** 1.5
    cv.glow(g, (90, 150, 170), 0.3)
    T.ground_shadow(cv, 60, 63, 26, 32)
    # the wet halo: a dark spreading pool under him
    pool = cv.mask().ellipse(58, 64, 30, 36, wobble=2.0)
    cv.paint(blur(pool.arr, 2.0 * cv.ss), (30, 52, 62), 0.55)
    # broad shoulders in a heavy coat, ragged at the hem
    coat = cv.mask().poly(catmull([(70, 64), (68, 40), (54, 34), (42, 40), (36, 52), (34, 64), (36, 76), (42, 88), (54, 94), (68, 88), (70, 64)], 8), wobble=1.2)
    T.P(cv, coat, gradient(cv.W, cv.H, "#3c4a52", "#10171c", 160), depth=3, hatch=0.6)
    for k in range(7):
        y0 = 40 + k * 8
        cv.stroke([(37, y0), (31 - r.uniform(0, 4), y0 + r.uniform(-2, 2))], 1.0, (20, 28, 32), 0.85)   # tatters
    for yy in (52, 60, 68, 76):
        cv.paint(cv.mask().circle(69, yy, 1.4), "#9a8a5a")   # tarnished brass buttons
    # sodden, bloated hands hanging forward
    T.limb(cv, [(60, 38), (72, 36), (84, 42)], 6.5, "#2e3a42")
    T.limb(cv, [(60, 90), (72, 92), (84, 86)], 6.5, "#2e3a42")
    for (x, y) in ((86, 43), (86, 85)):
        T.P(cv, cv.mask().circle(x, y, 3.6), "#9aaaa6", ow=1.6, depth=1.2, hatch=0.2)
    # seaweed draped over the collar
    for k in range(5):
        a = -0.9 + k * 0.45
        p0 = (64 + math.cos(a) * 9, 64 + math.sin(a) * 12)
        cv.stroke(catmull([p0, (p0[0] - 10, p0[1] + r.normal(0, 3)), (p0[0] - 20, p0[1] + r.normal(0, 5))], 8), 2.2, (70, 130, 60), 0.9)
    # a pale, drowned face under a battered tricorn
    hd = cv.mask().ellipse(70, 64, 10, 10)
    T.P(cv, hd, gradient(cv.W, cv.H, "#c4d2cc", "#6a7a78", 45), depth=1.6)
    for yy in (60, 68):
        cv.paint(cv.mask().ellipse(77.5, yy, 1.6, 2.0), (12, 20, 24))   # hollow eyes
    cv.stroke([(79, 62), (79, 66)], 0.8, (60, 80, 80), 0.8)
    hat = cv.mask().poly([(71, 64), (50, 48), (50, 80)], wobble=0.8)
    T.P(cv, hat, gradient(cv.W, cv.H, "#2a2a28", "#0a0a0a", 45), depth=2, hatch=0.5)
    cv.stroke([(69, 64), (52, 50)], 0.8, (110, 96, 64), 0.8)
    cv.stroke([(69, 64), (52, 78)], 0.8, (110, 96, 64), 0.8)
    # drops of sea water around him
    for k in range(10):
        a = r.uniform(0, 2 * math.pi)
        d = r.uniform(34, 46)
        x, y = 62 + math.cos(a) * d, 62 + math.sin(a) * d
        cv.paint(cv.mask().ellipse(x, y, 1.4, 2.0), (150, 200, 215), 0.8)
        cv.paint(cv.mask().circle(x - 0.4, y - 0.6, 0.5), (230, 245, 250), 0.9)
    T.finish(cv, "tokens/drowned_sailor.png")


def plague_doctor():
    """Seen from above: a wide-brimmed black hat, dark waxed robes, and the long
    pale beak of the mask jutting forward; round glass eyes catch the light."""
    cv, T = _token_base("plague_doctor", "#5a6a3a", "#121410")
    r = cv.rnd
    g = np.clip(1 - radial(cv.W, cv.H, *cv.T(62, 62), cv.TR(44)), 0, 1) ** 1.6
    cv.glow(g, (140, 170, 80), 0.25)
    T.ground_shadow(cv, 60, 63, 26, 32)
    # a faint sickly haze trailing behind
    for k in range(5):
        cv.paint(blur(cv.mask().circle(34 - k * 2, 50 + k * 7, 8 + k).arr, 3.0 * cv.ss), (110, 130, 50), 0.12)
    robe = cv.mask().poly(catmull([(68, 64), (66, 38), (52, 32), (38, 38), (32, 52), (30, 64), (32, 76), (38, 90), (52, 96), (66, 90), (68, 64)], 8), wobble=0.6)
    T.P(cv, robe, gradient(cv.W, cv.H, "#2c2a26", "#08080a", 160), depth=3.5, hatch=0.6)
    for k in range(5):
        cv.stroke(catmull([(64, 44 + k * 10), (48, 42 + k * 11), (34, 40 + k * 12)], 8), 0.7, (60, 56, 50), 0.6)   # folds of waxed cloth
    # gloved hands and the cane held forward
    T.limb(cv, [(58, 38), (70, 40), (80, 46)], 6.0, "#1c1a18")
    T.limb(cv, [(58, 90), (70, 88), (80, 82)], 6.0, "#1c1a18")
    cv.stroke([(82, 82), (100, 92)], 2.2, (60, 44, 30), 1.0)
    cv.paint(cv.mask().circle(82, 82, 2.4), (30, 26, 22))
    # medicine bottles at the belt
    for (x, y, c) in ((50, 34, (120, 160, 90)), (44, 36, (150, 110, 70))):
        T.P(cv, cv.mask().ellipse(x, y, 2.4, 3.2), c, ow=1.0, depth=0.8, hatch=0)
    # the wide hat brim, crown, and the long beak jutting forward
    brim = cv.mask().circle(62, 64, 17)
    T.P(cv, brim, gradient(cv.W, cv.H, "#2e2c2a", "#0a0a0a", 45), depth=2, hatch=0.4)
    crown = cv.mask().circle(61, 64, 9.5)
    T.P(cv, crown, gradient(cv.W, cv.H, "#3a3632", "#121010", 45), ow=1.4, depth=1.6, hatch=0.3)
    cv.stroke(ellipse_pts(61, 64, 10.5, 10.5, 40), 1.2, (90, 30, 26), 0.8)   # hatband
    beak = cv.mask().poly(catmull([(74, 58), (92, 61), (104, 64), (92, 67), (74, 70)], 6))
    T.P(cv, beak, gradient(cv.W, cv.H, "#d8cab0", "#7a6a50", 90), ow=1.8, depth=1.6, hatch=0.3)
    for xx in (84, 92):
        cv.stroke([(xx, 61.5), (xx, 66.5)], 0.7, (90, 74, 50), 0.8)   # stitched leather seams
    for yy in (57, 71):
        T.P(cv, cv.mask().circle(76, yy, 3.0), gradient(cv.W, cv.H, "#d8e4c0", "#4a5a3a", 45), ow=1.4, depth=0.8, hatch=0)
        cv.paint(cv.mask().circle(75.2, yy - 0.8, 0.9), (250, 255, 230), 0.9)
    T.finish(cv, "tokens/plague_doctor.png")


def wet_footprint(cv, st):
    """One bare, sea-wet footprint (toes toward -Y), dark and glistening."""
    cx, cy = 32, 34
    m = cv.mask().ellipse(cx, cy, 7.5, 13)
    m.ellipse(cx, cy + 12, 5.6, 6)
    for (dx, dy, rr) in ((-6.2, -15.5, 2.6), (-2.2, -17.6, 2.2), (1.6, -17.6, 1.9), (4.8, -16.2, 1.6), (7.2, -14, 1.4)):
        m.circle(cx + dx, cy + dy, rr)
    cv.paint(blur(m.arr, 2.0 * cv.ss), (40, 70, 80), 0.45)
    cv.paint(m, gradient(cv.W, cv.H, "#3c5a64", "#1a2a30", 45), 0.8)
    cv.paint(cv.mask().ellipse(cx - 2.5, cy - 4, 1.4, 5), (200, 230, 240), 0.55)   # wet sheen
    for k in range(4):
        x, y = cx + (k - 1.5) * 6, cy + 18 + (k % 2) * 3
        cv.paint(cv.mask().ellipse(x, y, 1.1, 1.5), (120, 170, 185), 0.6)   # drips


def puddle(cv, st):
    """A pool of dark sea water on the boards, with a cold reflected sheen and ripples."""
    r = rng("puddle")
    m = cv.mask().ellipse(32, 32, 24, 16, wobble=2.5)
    m.ellipse(42, 40, 12, 8, wobble=1.5)
    cv.paint(blur(dilate(m.arr, 1.5 * cv.ss), 1.5 * cv.ss), (24, 34, 38), 0.55)
    cv.paint(m, gradient(cv.W, cv.H, "#3a5862", "#0e1a20", 30), 0.82)
    cv.paint(cv.mask().ellipse(24, 26, 9, 3, rot=-15), (170, 210, 225), 0.35)   # reflected light
    for k, rr in enumerate((6, 11)):
        cv.stroke(ellipse_pts(38, 36, rr, rr * 0.65, 40), 0.8, (150, 200, 215), 0.5 - k * 0.2)
    for _ in range(3):
        x, y = 32 + r.normal(0, 8), 32 + r.normal(0, 5)
        cv.paint(cv.mask().circle(x, y, 0.8), (210, 235, 245), 0.7)


TOKENS5 = [blightness, crawler, lost_one, drowned_sailor, plague_doctor]


def build_tokens(only=None):
    for f in TOKENS5 + [werewolf_human, shapeshifter_human]:
        if only and f.__name__ not in only:
            continue
        f()


# --------------------------------------------------------------------------
# revision 6: human forms
# --------------------------------------------------------------------------
def werewolf_human():
    """The werewolf before the moon: a rough, unshaven man in a torn brown coat."""
    import tokens as T
    T.occupant("werewolf_human", "#3a2a1c", "#6a4a2a", "#4a3626", "#7a2a1a", "b")


def shapeshifter_human():
    """Its true human form: colourless, wet-looking, unnaturally glistening."""
    import tokens as T
    from PIL import Image, ImageChops, ImageDraw, ImageFilter
    T.occupant("shapeshifter_human", "#8a8a8a", "#b0b0b0", "#8a8a8a", "#c0c0c0", "c", pale=True)
    p = OUT_TOK / "shapeshifter_human.png"
    im = Image.open(p).convert("RGBA")
    a = im.getchannel("A")
    g = im.convert("L").point(lambda v: min(255, int(v * 1.15 + 10)))
    rgb = Image.merge("RGB", (g, g, g.point(lambda v: min(255, v + 8))))
    sheen = Image.new("L", im.size, 0)
    d = ImageDraw.Draw(sheen)
    for k, (x0, w) in enumerate(((30, 10), (58, 6), (80, 4))):
        d.polygon([(x0, 18), (x0 + w, 18), (x0 + w - 26, 110), (x0 - 26, 110)], fill=150 - k * 30)
    sheen = sheen.filter(ImageFilter.GaussianBlur(3))
    sheen = ImageChops.multiply(sheen, a)
    rgb = Image.composite(Image.new("RGB", im.size, (255, 255, 255)), rgb, sheen)
    out = rgb.convert("RGBA")
    out.putalpha(a)
    out.save(p)


def build_rev6():
    werewolf_human()
    shapeshifter_human()
