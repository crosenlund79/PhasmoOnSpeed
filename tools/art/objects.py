"""Small object drawers shared by items (64x64 floor decals) and icons (48x48).

Every drawer works in a 64x64 design space; icons apply ``cv.xf`` to shrink.
``st`` is a Style giving outline weights and shading strength.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from core import (INK, blur, catmull, col, dilate, ellipse_pts, gradient, mix, noise_tex, radial, rng,
                  rrect_pts, smoothstep)

BRASS = "#a8874a"
SILVER = "#b9bcc0"
IRON = "#4a4a50"
BONE = "#e2d8c0"
BLOOD = "#7a1018"
WOOD = "#7a5634"


@dataclass
class Style:
    ow: float = 2.0       # main ink outline (final px)
    thin: float = 1.0     # detail stroke width (design px)
    shade: float = 0.45
    hatch: float = 0.45
    light: float = 0.3
    depth: float = 2.5
    icon: bool = False


def P(cv, m, fill, st, ow=None, shade=None, hatch=None, depth=None, light=None, soft=0.0):
    return cv.part(m, fill, ow=st.ow if ow is None else ow, shade=st.shade if shade is None else shade,
                   light=st.light if light is None else light, hatch=st.hatch if hatch is None else hatch,
                   depth=(st.depth if depth is None else depth), soft=soft, hatch_spacing=2.4)


def gloss(cv, x, y, rx, ry, op=0.7, rot=0):
    cv.paint(cv.mask().ellipse(x, y, rx, ry, rot=rot), (255, 250, 235), op)


def glow_at(cv, x, y, r, color, amount):
    g = np.clip(1 - radial(cv.W, cv.H, *cv.T(x, y), cv.TR(r)), 0, 1) ** 1.6
    cv.glow(g, color, amount)


def poly_rot(pts, cx, cy, ang):
    c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]


# --------------------------------------------------------------------------
# vampire kit
# --------------------------------------------------------------------------
def garlic(cv, st, cx=32, cy=33, s=1.0):
    # bulb from above-ish: cloves as overlapping lobes with a pointed tip
    lobes = [(-9, 2, 10, 13, -18), (9, 2, 10, 13, 18), (0, 4, 10, 14, 0), (-4, -2, 8, 12, -8), (4, -2, 8, 12, 8)]
    for (dx, dy, rx, ry, rot) in lobes:
        m = cv.mask().ellipse(cx + dx * s, cy + dy * s, rx * s, ry * s, rot=rot)
        P(cv, m, gradient(cv.W, cv.H, "#f1ead8", "#b9ad96", 50), st, depth=2)
        cv.stroke(catmull([(cx + dx * s, cy + (dy - ry + 3) * s), (cx + dx * 1.2 * s, cy + dy * s),
                           (cx + dx * s, cy + (dy + ry - 3) * s)], 6), st.thin * 0.7, "#8a7a86", 0.6)
    tip = cv.mask().poly([(cx - 4 * s, cy - 10 * s), (cx, cy - 22 * s), (cx + 4 * s, cy - 10 * s)])
    P(cv, tip, "#d8ccb0", st, depth=1)
    # purple streaks
    for dx in (-7, 0, 7):
        cv.stroke([(cx + dx * s, cy + 6 * s), (cx + dx * 1.1 * s, cy + 13 * s)], st.thin * 1.2, "#7a4a6a", 0.5)
    # roots
    for k in range(7):
        a = math.pi * (0.25 + k / 6 * 0.5)
        cv.stroke([(cx, cy + 16 * s), (cx + math.cos(a) * 7 * s, cy + (16 + math.sin(a) * 5) * s)],
                  st.thin * 0.8, "#8a7a5a", 0.9)


def stake(cv, st, metal=False, ang=-35):
    cx, cy = 32, 32
    body = [(cx - 24, cy - 3.2), (cx + 10, cy - 3.0), (cx + 24, cy), (cx + 10, cy + 3.0), (cx - 24, cy + 3.2)]
    body = poly_rot(body, cx, cy, ang)
    m = cv.mask().poly(body)
    if metal:
        fill = gradient(cv.W, cv.H, "#eef0f2", "#6e737a", ang + 90)
    else:
        fill = noise_tex(cv.W, cv.H, rng("stake"), "#8a6440", 0.2, 30, 4, 3)
    P(cv, m, fill, st, depth=1.5)
    # whittled facets / grip binding
    for t in (-0.2, 0.0, 0.2):
        p0 = poly_rot([(cx + 10 + t * 10, cy - 3), (cx + 22 + t * 4, cy)], cx, cy, ang)
        cv.stroke(p0, st.thin * 0.6, INK, 0.5)
    if metal:
        for k in range(4):
            x = cx - 20 + k * 3.5
            cv.stroke(poly_rot([(x, cy - 3.4), (x + 1.5, cy + 3.4)], cx, cy, ang), st.thin * 1.2, "#5a3a26", 0.95)
        gl = poly_rot([(cx - 18, cy - 1.4), (cx + 14, cy - 1.2)], cx, cy, ang)
        cv.stroke(gl, st.thin * 0.8, "#ffffff", 0.7)
    else:
        cv.stroke(poly_rot([(cx - 20, cy - 0.8), (cx + 6, cy - 0.6)], cx, cy, ang), st.thin * 0.5, "#4a3020", 0.6)
        cv.stroke(poly_rot([(cx - 22, cy + 1.2), (cx + 2, cy + 1.0)], cx, cy, ang), st.thin * 0.5, "#4a3020", 0.6)


def silverware(cv, st):
    cx, cy = 32, 32
    sil = gradient(cv.W, cv.H, "#f2f3f4", "#7c8188", 30)
    # fork
    f = poly_rot([(cx - 2, cy + 24), (cx + 2, cy + 24), (cx + 1.6, cy - 4), (cx + 6, cy - 8), (cx + 6, cy - 24),
                  (cx + 4.4, cy - 24), (cx + 4.2, cy - 12), (cx + 2.4, cy - 12), (cx + 2.4, cy - 24),
                  (cx + 0.8, cy - 24), (cx + 0.8, cy - 12), (cx - 0.8, cy - 12), (cx - 0.8, cy - 24),
                  (cx - 2.4, cy - 24), (cx - 2.4, cy - 12), (cx - 4.2, cy - 12), (cx - 4.4, cy - 24),
                  (cx - 6, cy - 24), (cx - 6, cy - 8), (cx - 1.6, cy - 4)], cx, cy, -28)
    P(cv, cv.mask().poly(f), sil, st, depth=1.2)
    # knife
    k = poly_rot([(cx - 2.2, cy + 24), (cx + 2.2, cy + 24), (cx + 2.4, cy - 2), (cx + 3.6, cy - 6),
                  (cx + 3.0, cy - 22), (cx, cy - 26), (cx - 2.4, cy - 20), (cx - 2.4, cy - 2)], cx, cy, 28)
    P(cv, cv.mask().poly(k), sil, st, depth=1.2)
    cv.stroke(poly_rot([(cx + 0.5, cy - 4), (cx + 0.5, cy - 22)], cx, cy, 28), st.thin * 0.6, "#ffffff", 0.7)
    for ang in (-28, 28):
        cv.stroke(poly_rot([(cx, cy + 6), (cx, cy + 22)], cx, cy, ang), st.thin * 0.6, "#5a5e66", 0.7)


def hand_mirror(cv, st, wrong=False):
    cx, cy = 30, 26
    h = cv.mask().poly(poly_rot([(cx - 3, cy + 12), (cx + 3, cy + 12), (cx + 2.6, cy + 34), (cx - 2.6, cy + 34)],
                                cx, cy, -30))
    P(cv, h, noise_tex(cv.W, cv.H, rng("mh"), "#5a2a1e", 0.2), st, depth=1.2)
    fr = cv.mask().ellipse(cx, cy, 16, 18, rot=-30)
    P(cv, fr, gradient(cv.W, cv.H, "#d8bb78", "#6a5024", 45), st, depth=2)
    gl = cv.mask().ellipse(cx, cy, 12, 14, rot=-30)
    cv.paint(dilate(gl.arr, 0.8 * cv.ss), INK, 0.9)
    cv.paint(gl, gradient(cv.W, cv.H, "#dfeaec", "#5d7178", 30))
    if wrong:
        # a dark silhouette with glowing eyes that isn't yours
        sil = cv.mask().ellipse(cx + 1, cy + 3, 7.5, 9.5, rot=-30)
        sil.ellipse(cx + 4, cy + 12, 10, 6, rot=-30)
        cv.paint(np.clip(sil.arr * gl.arr, 0, 1), (30, 32, 40), 0.9)
        for (ex, ey) in ((cx - 2.0, cy + 0.5), (cx + 3.4, cy + 3.2)):
            cv.paint(cv.mask().circle(ex, ey, 1.4), (255, 80, 60))
        cv.stroke(poly_rot([(cx - 8, cy - 2), (cx + 8, cy - 9)], cx, cy, 0), st.thin * 0.9, (180, 40, 40), 0.6)
    else:
        cv.stroke([(cx - 7, cy - 3), (cx - 1, cy - 11)], st.thin * 1.3, "#ffffff", 0.7)
        cv.stroke([(cx - 6, cy + 3), (cx + 3, cy - 9)], st.thin * 0.8, "#ffffff", 0.5)


def iron_nails(cv, st):
    r = rng("nails")
    for (x, y, a) in ((22, 24, 20), (36, 20, 75), (40, 40, -15), (24, 42, 130), (30, 31, 50)):
        p = poly_rot([(x - 12, y - 1.3), (x + 9, y - 1.0), (x + 13, y), (x + 9, y + 1.0), (x - 12, y + 1.3)], x, y, a)
        P(cv, cv.mask().poly(p), gradient(cv.W, cv.H, "#7a7a80", "#2e2e34", a + 90), st, depth=1, hatch=0.2)
        hd = poly_rot([(x - 12, y)], x, y, a)[0]
        P(cv, cv.mask().circle(hd[0], hd[1], 3.4), "#55555c", st, depth=1, hatch=0)
        cv.paint(cv.mask().circle(hd[0] - 0.8, hd[1] - 0.8, 1.1), "#a0a0a8", 0.7)
        # rust
        cv.paint(cv.mask().circle(*poly_rot([(x + r.random() * 8 - 4, y)], x, y, a)[0], 1.4), "#7a4a2a", 0.6)


def book(cv, st, open_=False, written=False, sigil=True):
    cx, cy = 32, 32
    if not open_:
        m = cv.mask().rect(cx - 17, cy - 21, cx + 17, cy + 21, 2.5)
        P(cv, m, noise_tex(cv.W, cv.H, rng("bk"), "#4a2a2a", 0.2), st, depth=2.5)
        sp = cv.mask().rect(cx - 17, cy - 21, cx - 11, cy + 21, 2)
        P(cv, sp, "#3a1e1e", st, ow=1.2, depth=1, hatch=0.2)
        for yy in (cy - 15, cy + 15):
            cv.stroke([(cx - 16, yy), (cx - 12, yy)], st.thin * 1.2, BRASS)
        for (x, y, sx, sy) in ((cx + 17, cy - 21, -1, 1), (cx + 17, cy + 21, -1, -1)):
            P(cv, cv.mask().poly([(x, y), (x + 7 * sx, y), (x, y + 7 * sy)]), BRASS, st, ow=1.0, depth=0.5, hatch=0)
        if sigil:
            ccx = cx + 3
            pts = [(ccx + math.cos(math.radians(-90 + k * 144)) * 9, cy + math.sin(math.radians(-90 + k * 144)) * 9)
                   for k in range(6)]
            cv.stroke(pts, st.thin * 1.1, "#c2a060", 0.95)
            cv.stroke(ellipse_pts(ccx, cy, 11, 11, 40) + [ellipse_pts(ccx, cy, 11, 11, 40)[0]], st.thin * 1.0,
                      "#c2a060", 0.95)
    else:
        # open book: two pages with a spine in the middle
        cov = cv.mask().rect(cx - 27, cy - 18, cx + 27, cy + 19, 2.5)
        P(cv, cov, "#3e2424", st, depth=2)
        for sgn in (-1, 1):
            pg = cv.mask().poly(catmull([(cx, cy - 15), (cx + sgn * 12, cy - 17.5), (cx + sgn * 25, cy - 16)], 6)
                                + [(cx + sgn * 25, cy + 16)]
                                + catmull([(cx + sgn * 25, cy + 16), (cx + sgn * 12, cy + 14.5), (cx, cy + 17)], 6))
            P(cv, pg, gradient(cv.W, cv.H, "#e4d8b8", "#b8a682", 0 if sgn > 0 else 180), st, ow=1.4, depth=2,
              hatch=0.25)
        cv.stroke([(cx, cy - 15), (cx, cy + 17)], st.thin * 1.2, INK, 0.9)
        r = rng("scrawl" if written else "lines")
        for sgn in (-1, 1):
            for k in range(7):
                yy = cy - 11 + k * 3.8
                x0, x1 = cx + sgn * 4, cx + sgn * (21 - r.random() * 5)
                if written:
                    pts = []
                    for j in range(14):
                        t = j / 13
                        pts.append((x0 + (x1 - x0) * t, yy + math.sin(j * 1.9 + k) * 1.1 + r.normal(0, 0.3)))
                    cv.stroke(pts, st.thin * 0.8, "#2a1a1a", 0.9)
                else:
                    cv.stroke([(x0, yy), (x1, yy)], st.thin * 0.4, "#8a7a5a", 0.5)
        if written:
            # an angry scrawled sigil on the right page
            pts = [(cx + 12 + math.cos(a) * 6, cy + math.sin(a * 2) * 5) for a in np.linspace(0, 6.3, 18)]
            cv.stroke(pts, st.thin * 1.1, (120, 10, 20), 0.9)


def salt_pile(cv, st):
    cx, cy = 32, 34
    r = rng("salt")
    m = cv.mask().ellipse(cx, cy, 22, 17, wobble=1.2)
    P(cv, m, gradient(cv.W, cv.H, "#ffffff", "#b8b6b0", 45), st, depth=4, soft=0.4)
    for _ in range(90):
        a = r.random() * 2 * math.pi
        d = r.random() ** 0.6
        x, y = cx + math.cos(a) * 25 * d, cy + math.sin(a) * 20 * d
        cv.paint(cv.mask().circle(x, y, 0.5 + r.random() * 0.6), "#ffffff" if d < 0.8 else "#d8d6d0", 0.9)
    for _ in range(30):
        a = r.random() * 2 * math.pi
        d = 1.0 + r.random() * 0.25
        x, y = cx + math.cos(a) * 22 * d, cy + math.sin(a) * 17 * d
        cv.paint(cv.mask().circle(x, y, 0.6), "#e8e6e0", 0.95)


def crucifix(cv, st, placed=True):
    cx, cy = 32, 32
    m = cv.mask().rect(cx - 3.8, cy - 25, cx + 3.8, cy + 25, 1)
    m.rect(cx - 15, cy - 15, cx + 15, cy - 7.5, 1)
    fill = gradient(cv.W, cv.H, "#7a5634", "#3a2414", 45) if placed else gradient(cv.W, cv.H, "#d6b86e", "#6a5024", 45)
    P(cv, m, fill, st, depth=2.2)
    # brass corpus/plate
    plate = cv.mask().rect(cx - 2, cy - 14.5, cx + 2, cy + 8, 1)
    P(cv, plate, gradient(cv.W, cv.H, "#e2c88a", "#7a5a2a", 45), st, ow=1.0, depth=0.8, hatch=0)
    for (x, y) in ((cx, cy - 22), (cx - 12.5, cy - 11.3), (cx + 12.5, cy - 11.3), (cx, cy + 22)):
        cv.paint(cv.mask().circle(x, y, 1.3), BRASS)


def candle(cv, st, lit=False, sigil=True):
    cx, cy = 32, 32
    if sigil:
        r = cv.mask().circle(cx, cy, 27)
        ring = np.clip(r.arr - cv.mask().circle(cx, cy, 25.4).arr, 0, 1)
        cv.paint(ring, "#d8d2c2", 0.85)
        pts = [(cx + math.cos(math.radians(-90 + k * 144)) * 25, cy + math.sin(math.radians(-90 + k * 144)) * 25)
               for k in range(6)]
        cv.stroke(pts, 0.9, "#d8d2c2", 0.8)
        for k in range(5):
            a = math.radians(-90 + 36 + k * 72)
            x, y = cx + math.cos(a) * 21, cy + math.sin(a) * 21
            cv.stroke([(x - 1.5, y - 1.5), (x + 1.5, y + 1.5)], 0.7, "#d8d2c2", 0.8)
            cv.stroke([(x - 1.5, y + 1.5), (x + 1.5, y - 1.5)], 0.7, "#d8d2c2", 0.8)
    # holder dish
    P(cv, cv.mask().circle(cx, cy, 12.5), gradient(cv.W, cv.H, "#c9a860", "#5e4620", 45), st, depth=2)
    w = cv.mask().circle(cx, cy, 7.5)
    P(cv, w, gradient(cv.W, cv.H, "#2a1a1c", "#120a0c", 45) if not lit else gradient(cv.W, cv.H, "#f0e6c8", "#a89c80", 45),
      st, ow=1.6, depth=1.5)
    if not lit:
        # black sigil wax with carved rune
        cv.stroke([(cx - 3, cy - 3), (cx + 3, cy + 3)], 0.8, "#8a2a2a", 0.9)
        cv.stroke([(cx + 3, cy - 3), (cx - 3, cy + 3)], 0.8, "#8a2a2a", 0.9)
        cv.paint(cv.mask().circle(cx, cy, 1.0), "#d8d0c0")
    else:
        cv.paint(cv.mask().ellipse(cx + 3, cy + 2, 3, 2), "#f6efd8", 0.9)   # wax pool
        cv.paint(cv.mask().circle(cx, cy, 1.0), INK)


def candle_flame(cv, cx=32, cy=32, amount=1.0):
    glow_at(cv, cx, cy, 32, (255, 160, 60), 0.75 * amount)
    fl = cv.mask().poly(catmull([(cx - 3.6, cy + 2), (cx - 2.6, cy - 3), (cx, cy - 9), (cx + 2.6, cy - 3),
                                 (cx + 3.6, cy + 2), (cx, cy + 4.5), (cx - 3.6, cy + 2)], 6))
    cv.paint(dilate(fl.arr, 1.0 * cv.ss), (255, 140, 40))
    cv.paint(fl, (255, 240, 190))


def blood_drops(cv, st, n=7, seed="blood"):
    r = rng(seed)
    for k in range(n):
        x, y = 14 + r.random() * 36, 14 + r.random() * 36
        rr = 2 + r.random() ** 2 * 6
        m = cv.mask().ellipse(x, y, rr, rr * (0.85 + 0.3 * r.random()), wobble=rr * 0.12)
        for _ in range(int(rr)):
            a = r.random() * 2 * math.pi
            d = rr * (1.1 + r.random() * 0.8)
            m.circle(x + math.cos(a) * d, y + math.sin(a) * d, 0.4 + r.random() * rr * 0.18)
        cv.part(m, gradient(cv.W, cv.H, "#9a1820", "#4a060c", 45), ow=0.9, shade=0.3, light=0.0, hatch=0, depth=1,
                ink_color=(40, 4, 8))
        gloss(cv, x - rr * 0.35, y - rr * 0.35, rr * 0.25, rr * 0.18, 0.5)


def soil(cv, st, coffin=True):
    cx, cy = 32, 34
    r = rng("soil")
    m = cv.mask()
    for _ in range(7):
        m.ellipse(cx + r.normal(0, 6), cy + r.normal(0, 4), 11 + r.random() * 5, 8 + r.random() * 4, wobble=1.2)
    P(cv, m, noise_tex(cv.W, cv.H, r, "#3e2e22", 0.35, 14, 14, 4), st, depth=4, soft=0.3)
    for _ in range(70):
        x, y = cx + r.normal(0, 10), cy + r.normal(0, 8)
        cv.paint(cv.mask().circle(x, y, 0.5 + r.random() * 1.2), "#6a5442" if r.random() < 0.5 else "#1c140e", 0.9)
    # grave worms and a splinter of coffin wood
    cv.stroke(catmull([(cx - 8, cy + 4), (cx - 4, cy + 1), (cx, cy + 5), (cx + 4, cy + 2)], 6), 1.6, INK)
    cv.stroke(catmull([(cx - 8, cy + 4), (cx - 4, cy + 1), (cx, cy + 5), (cx + 4, cy + 2)], 6), 0.9, "#a86a6a")
    if coffin:
        sp = cv.mask().poly(poly_rot([(cx + 2, cy - 8), (cx + 18, cy - 9), (cx + 19, cy - 6), (cx + 3, cy - 5)],
                                     cx + 10, cy - 7, -20))
        P(cv, sp, noise_tex(cv.W, cv.H, r, "#2a1e18", 0.2), st, ow=1.4, depth=1)
        cv.paint(cv.mask().circle(cx + 15, cy - 9.5, 1.2), BRASS)


def claw_marks(cv, st, floor=True):
    for k in range(3):
        off = (k - 1) * 9
        pts = [(14 + off, 10), (26 + off, 26), (40 + off, 44), (50 + off, 56)]
        cp = catmull(pts, 8)
        left, right = [], []
        for i, (x, y) in enumerate(cp):
            t = i / (len(cp) - 1)
            w = 3.4 * math.sin(math.pi * t) ** 0.6 + 0.2
            dx, dy = (cp[min(i + 1, len(cp) - 1)][0] - cp[max(i - 1, 0)][0],
                      cp[min(i + 1, len(cp) - 1)][1] - cp[max(i - 1, 0)][1])
            n = math.hypot(dx, dy) + 1e-6
            left.append((x - dy / n * w, y + dx / n * w))
            right.append((x + dy / n * w, y - dx / n * w))
        m = cv.mask().poly(left + right[::-1])
        if floor:
            # gouge: dark groove with pale splintered edge
            cv.paint(dilate(m.arr, 1.6 * cv.ss), (200, 170, 130), 0.85)
            cv.paint(dilate(m.arr, 0.6 * cv.ss), INK)
            cv.paint(m, (25, 14, 10))
            for i in range(2, len(cp) - 2, 3):
                x, y = left[i]
                cv.stroke([(x, y), (x - 2.5, y + 1)], 0.6, (210, 180, 140), 0.9)
        else:
            P(cv, m, (120, 20, 28), st, depth=1, hatch=0.2)


def fur_tuft(cv, st):
    r = rng("fur")
    bx, by = 14, 38
    locks = []
    for k in range(11):
        ang = -0.35 + (k - 5) * 0.11 + r.normal(0, 0.05)
        ln = 34 + r.random() * 10 - abs(k - 5) * 2.2
        locks.append((ang, ln, 0.35 + r.normal(0, 0.12)))
    locks.sort(key=lambda t: -abs(t[0] + 0.35))
    for i, (ang, ln, bend) in enumerate(locks):
        pts = []
        for t in np.linspace(0, 1, 8):
            a = ang + bend * t
            pts.append((bx + math.cos(a) * ln * t + r.normal(0, 0.3), by + math.sin(a) * ln * t))
        left, right = [], []
        for j, (x, y) in enumerate(pts):
            t = j / (len(pts) - 1)
            w = 4.6 * math.sin(math.pi * min(1.0, 0.25 + t * 0.85)) ** 0.8 + 0.3
            nx, ny = -math.sin(ang + bend * t), math.cos(ang + bend * t)
            left.append((x + nx * w, y + ny * w))
            right.append((x - nx * w, y - ny * w))
        m = cv.mask().poly(catmull(left, 3) + catmull(right[::-1], 3))
        c0 = "#4a3e34" if i % 2 else "#5e5042"
        P(cv, m, gradient(cv.W, cv.H, "#b8a892", c0, 90), st, ow=st.ow * 0.8, depth=1.2, hatch=0.3)
        for k in range(3):
            off = (k - 1) * 1.6
            cv.stroke(catmull([(x + off * 0.3, y) for (x, y) in pts[1:-1]], 4), st.thin * 0.45, "#2a221c", 0.6)
    # a few stray hairs
    for _ in range(10):
        a = -0.2 + r.normal(0, 0.5)
        x0, y0 = bx + 10 + r.random() * 20, by + r.normal(0, 5)
        cv.stroke(catmull([(x0, y0), (x0 + math.cos(a) * 8, y0 + math.sin(a) * 8 + 2),
                           (x0 + math.cos(a) * 14, y0 + math.sin(a) * 14 + 5)], 4), st.thin * 0.5, "#6a5a4a", 0.9)


def paw_print(cv, st, color=(74, 56, 40)):
    cx, cy = 32, 36
    pad = cv.mask().poly(catmull([(cx - 11, cy + 6), (cx - 9, cy - 3), (cx, cy - 6), (cx + 9, cy - 3), (cx + 11, cy + 6),
                                  (cx + 5, cy + 12), (cx, cy + 9), (cx - 5, cy + 12), (cx - 11, cy + 6)], 6))
    toes = cv.mask()
    for (dx, dy, rot) in ((-12, -10, -25), (-4.5, -17, -8), (4.5, -17, 8), (12, -10, 25)):
        toes.ellipse(cx + dx, cy + dy, 4.2, 5.6, rot=rot)
    claws = cv.mask()
    for (dx, dy, ang) in ((-15, -17, -35), (-6, -25, -10), (6, -25, 10), (15, -17, 35)):
        claws.poly(poly_rot([(cx + dx - 1.3, cy + dy + 2), (cx + dx, cy + dy - 3), (cx + dx + 1.3, cy + dy + 2)],
                            cx + dx, cy + dy, ang))
    allm = np.maximum(np.maximum(pad.arr, toes.arr), claws.arr)
    n = noise_tex(cv.W, cv.H, rng("paw"), color, 0.3, 20, 20, 3)
    cv.paint(blur(allm, 1.2 * cv.ss) * (1 - allm), (150, 125, 95), 0.5)
    cv.paint(dilate(allm, 0.5 * cv.ss), (30, 22, 16), 0.9)
    cv.paint(allm, n, 0.95)
    cv.mul(blur(allm, 2 * cv.ss) * allm, 0.4, (40, 30, 20))


def shed_skin(cv, st):
    r = rng("skin")
    pts = [(9, 46), (18, 36), (30, 34), (40, 40), (50, 38), (57, 26)]
    cp = catmull(pts, 10)
    left, right = [], []
    for i, (x, y) in enumerate(cp):
        t = i / (len(cp) - 1)
        w = 3.0 + 6.0 * math.sin(math.pi * min(1.0, 0.15 + t)) ** 0.7
        dx, dy = (cp[min(i + 1, len(cp) - 1)][0] - cp[max(i - 1, 0)][0],
                  cp[min(i + 1, len(cp) - 1)][1] - cp[max(i - 1, 0)][1])
        n = math.hypot(dx, dy) + 1e-6
        left.append((x - dy / n * w, y + dx / n * w))
        right.append((x + dy / n * w, y - dx / n * w))
    m = cv.mask().poly(left + right[::-1], wobble=1.1, step=2.0)
    arr = m.arr
    cv.paint(dilate(arr, st.ow * 0.8 * cv.ss, wobble=cv.wob()), (40, 36, 26), 0.9)
    cv.paint(arr, gradient(cv.W, cv.H, "#ece4c4", "#a89c74", 60), 0.88)
    from core import edge_band
    cv.mul(edge_band(arr, 3 * cv.ss, 3 * cv.ss, 2 * cv.ss), 0.35, (60, 50, 30))
    # diamond scale lattice clipped to the skin
    x = np.arange(cv.W)[None, :] / cv.ss
    y = np.arange(cv.H)[:, None] / cv.ss
    p = 4.2
    lat = (np.abs(((x + y) % p) - p / 2) < 0.35) | (np.abs(((x - y) % p) - p / 2) < 0.35)
    cv.tint(lat * arr, "#6a5e40", 0.55)
    # crumpled folds across the skin
    for i in range(3, len(cp) - 3, 5):
        cv.stroke([left[i], cp[i], right[min(i + 2, len(cp) - 1)]], st.thin * 0.7, "#5a5034", 0.7)
    # open head end
    hx, hy = cp[-1]
    cv.paint(cv.mask().ellipse(hx - 1, hy + 1.5, 3.2, 2.2, rot=-50), (70, 60, 40), 0.8)
    gloss(cv, 24, 36, 4, 1.2, 0.35, rot=-10)


def handprint(cv, st, glow=True):
    cx, cy = 32, 38
    m = cv.mask().ellipse(cx, cy, 10, 11)
    for (dx, dy, ln, ang) in ((-9, -8, 13, -28), (-3.5, -12, 16, -9), (2.5, -12, 17, 5), (8, -9, 14, 20),
                              (12, 4, 11, 62)):
        a = math.radians(ang - 90)
        x0, y0 = cx + dx, cy + dy
        x1, y1 = x0 + math.cos(a) * ln, y0 + math.sin(a) * ln
        m.line([(x0, y0), (x1, y1)], 5.6)
    arr = m.arr
    if glow:
        cv.paint(blur(arr, 3 * cv.ss), (150, 70, 230), 0.8)
        cv.paint(arr, (205, 160, 255), 0.85)
        # skin-ridge texture
        x = np.arange(cv.W)[None, :]
        y = np.arange(cv.H)[:, None]
        rid = (np.sin(np.hypot(x - cv.T(cx, cy)[0], y - cv.T(cx, cy)[1]) / (1.2 * cv.ss)) > 0.4).astype(np.float32)
        cv.paint(arr * rid, (240, 220, 255), 0.6)
    else:
        P(cv, arr, "#8a6ab0", st)


def orb(cv, st, cx=32, cy=32, rad=16):
    g = np.clip(1 - radial(cv.W, cv.H, *cv.T(cx, cy), cv.TR(rad * 1.9)), 0, 1) ** 2
    cv.glow(g, (200, 235, 240), 0.55)
    core = np.clip(1 - radial(cv.W, cv.H, *cv.T(cx, cy), cv.TR(rad)), 0, 1)
    cv.glow(smoothstep(0.0, 0.6, core) * 0.9, (235, 250, 252), 0.9)
    ring = smoothstep(0.0, 0.08, core) * (1 - smoothstep(0.08, 0.2, core))
    cv.glow(ring, (180, 230, 245), 0.5)


# --------------------------------------------------------------------------
# icon-only devices
# --------------------------------------------------------------------------
def emf(cv, st, level=5):
    cx, cy = 32, 34
    body = cv.mask().rect(cx - 14, cy - 18, cx + 14, cy + 24, 5)
    P(cv, body, gradient(cv.W, cv.H, "#6a5a46", "#2e261e", 45), st, depth=2)
    face = cv.mask().rect(cx - 10, cy - 14, cx + 10, cy + 4, 2)
    P(cv, face, "#1c1a18", st, ow=1.2, depth=1, hatch=0)
    cols = ["#5a9a4a", "#9aba4a", "#d8c04a", "#e08a3a", "#e03a2a"]
    for k in range(5):
        x = cx - 8 + k * 4
        h = 4 + k * 2.4
        m = cv.mask().rect(x - 1.4, cy + 1 - h, x + 1.4, cy + 1, 0.4)
        lit = k < level
        cv.paint(m, cols[k] if lit else "#3a3632")
        if lit and level == 5:
            glow_at(cv, x, cy + 1 - h / 2, 5, col(cols[k]), 0.25)
    cv.paint(cv.mask().circle(cx, cy + 14, 3.2), "#8a7a5a")
    cv.stroke(ellipse_pts(cx, cy + 14, 3.2, 3.2, 20) + [ellipse_pts(cx, cy + 14, 3.2, 3.2, 20)[0]], 0.8, INK)
    # antenna
    cv.stroke([(cx + 9, cy - 18), (cx + 14, cy - 28)], st.thin * 1.8, INK)
    cv.paint(cv.mask().circle(cx + 14, cy - 28, 1.8), "#c84a3a" if level == 5 else "#6a5a4a")


def thermometer(cv, st, cold=False):
    cx, cy = 32, 32
    tube = cv.mask().rect(cx - 5, cy - 26, cx + 5, cy + 14, 5)
    P(cv, tube, gradient(cv.W, cv.H, "#f0ece0", "#a8a294", 0), st, depth=1.5)
    bulb = cv.mask().circle(cx, cy + 18, 8.5)
    P(cv, bulb, gradient(cv.W, cv.H, "#f0ece0", "#a8a294", 0), st, depth=1.5)
    c = "#4a8ab8" if cold else "#b8302a"
    cv.paint(cv.mask().circle(cx, cy + 18, 5.5), c)
    top = cy + 4 if cold else cy - 14
    cv.paint(cv.mask().rect(cx - 1.8, top, cx + 1.8, cy + 16, 1.5), c)
    for k in range(7):
        y = cy - 20 + k * 4.5
        cv.stroke([(cx + 5, y), (cx + 9 - (k % 2) * 2, y)], st.thin * 0.9, INK)
    gloss(cv, cx - 2.4, cy - 10, 0.9, 10, 0.6)


def snowflake(cv, st):
    cx, cy = 32, 32
    m = cv.mask()
    for k in range(6):
        a = math.radians(k * 60 - 90)
        ex, ey = cx + math.cos(a) * 25, cy + math.sin(a) * 25
        m.line([(cx, cy), (ex, ey)], 3.4)
        for t, ln in ((0.5, 8), (0.78, 5.5)):
            px, py = cx + math.cos(a) * 25 * t, cy + math.sin(a) * 25 * t
            for sgn in (-1, 1):
                b = a + sgn * math.radians(50)
                m.line([(px, py), (px + math.cos(b) * ln, py + math.sin(b) * ln)], 2.6)
    m.circle(cx, cy, 5)
    P(cv, m, gradient(cv.W, cv.H, "#e8f4f8", "#6a9ab4", 45), st, depth=1.2, hatch=0.2)


def radio(cv, st, waves=True):
    cx, cy = 32, 36
    body = cv.mask().rect(cx - 20, cy - 13, cx + 20, cy + 16, 4)
    P(cv, body, noise_tex(cv.W, cv.H, rng("radio"), "#6a4a30", 0.2, 20, 4), st, depth=2)
    gr = cv.mask().rect(cx - 16, cy - 9, cx + 2, cy + 12, 2)
    P(cv, gr, "#2a2420", st, ow=1.2, depth=1, hatch=0)
    for k in range(6):
        y = cy - 6 + k * 3.4
        cv.stroke([(cx - 14, y), (cx, y)], st.thin * 0.9, "#8a7a5a", 0.9)
    dial = cv.mask().circle(cx + 10, cy - 2, 5.5)
    P(cv, dial, "#d8c890", st, ow=1.2, depth=1, hatch=0)
    cv.stroke([(cx + 10, cy - 2), (cx + 12.5, cy - 6)], st.thin, (150, 30, 30))
    P(cv, cv.mask().circle(cx + 10, cy + 9.5, 3), "#3a2a1c", st, ow=1.0, depth=0.8, hatch=0)
    cv.stroke([(cx + 14, cy - 13), (cx + 22, cy - 30)], st.thin * 1.8, INK)
    if waves:
        for k, rr in enumerate((6, 11, 16)):
            cv.stroke(ellipse_pts(cx + 22, cy - 30, rr * 0.9, rr * 0.9, 20, 0, -60, 30), st.thin * 1.6, (60, 110, 120),
                      0.95 - k * 0.2)


def camera(cv, st):
    cx, cy = 27, 34
    body = cv.mask().rect(cx - 22, cy - 12, cx + 18, cy + 16, 3)
    P(cv, body, noise_tex(cv.W, cv.H, rng("cam"), "#3a3230", 0.2), st, depth=2)
    bel = cv.mask().poly([(cx + 4, cy - 10), (cx + 24, cy - 14), (cx + 24, cy + 18), (cx + 4, cy + 14)])
    P(cv, bel, "#2a2220", st, depth=1.5)
    for k in range(4):
        x = cx + 7 + k * 4.5
        cv.stroke([(x, cy - 10 - k), (x, cy + 14 + k)], st.thin * 0.8, "#5a4a40", 0.9)
    lens = cv.mask().circle(cx + 24, cy + 2, 8)
    P(cv, lens, BRASS, st, depth=1.2)
    cv.paint(cv.mask().circle(cx + 24, cy + 2, 5), (30, 60, 70))
    gloss(cv, cx + 22, cy, 1.6, 1.2, 0.8)
    P(cv, cv.mask().rect(cx - 18, cy - 18, cx - 6, cy - 12, 1.5), "#5a4a40", st, ow=1.2, depth=1, hatch=0)
    glow_at(cv, cx + 24, cy + 2, 8, (160, 230, 240), 0.25)


def flashlight(cv, st, uv=False):
    cx, cy = 28, 34
    beam = cv.mask().poly([(cx + 14, cy - 5), (62, cy - 18), (62, cy + 18), (cx + 14, cy + 5)])
    c = (190, 120, 255) if uv else (255, 210, 120)
    g = np.clip(1 - radial(cv.W, cv.H, *cv.T(cx + 14, cy), cv.TR(36)), 0, 1)
    cv.paint(blur(beam.arr, 1.5 * cv.ss) * g, c, 0.7)
    body = cv.mask().rect(cx - 22, cy - 4.5, cx + 6, cy + 4.5, 2)
    P(cv, body, gradient(cv.W, cv.H, "#6a6a70", "#26262a", 90), st, depth=1.5)
    head = cv.mask().poly([(cx + 4, cy - 5), (cx + 14, cy - 8), (cx + 14, cy + 8), (cx + 4, cy + 5)])
    P(cv, head, gradient(cv.W, cv.H, "#d6b86e", "#6a5024", 90), st, depth=1.2)
    cv.paint(cv.mask().rect(cx + 13, cy - 7, cx + 15, cy + 7), (250, 240, 255) if uv else (255, 245, 210))
    for k in range(4):
        x = cx - 18 + k * 3.5
        cv.stroke([(x, cy - 4), (x, cy + 4)], st.thin * 0.7, INK, 0.7)
    P(cv, cv.mask().rect(cx - 4, cy - 7, cx + 1, cy - 4.5, 1), "#8a2a2a" if not uv else "#5a2a8a", st, ow=1.0,
      depth=0.6, hatch=0)


def holy_water(cv, st):
    cx, cy = 32, 36
    fl = cv.mask().poly(catmull([(cx - 6, cy - 16), (cx - 6, cy - 8), (cx - 16, cy + 2), (cx - 14, cy + 18),
                                 (cx, cy + 22), (cx + 14, cy + 18), (cx + 16, cy + 2), (cx + 6, cy - 8),
                                 (cx + 6, cy - 16)], 6))
    P(cv, fl, gradient(cv.W, cv.H, "#cfe2e8", "#5a7a88", 30), st, depth=2)
    cv.paint(cv.mask().poly(catmull([(cx - 14, cy + 6), (cx, cy + 3), (cx + 14, cy + 6)], 6)
                            + [(cx + 13, cy + 17), (cx, cy + 21), (cx - 13, cy + 17)]), (120, 170, 200), 0.6)
    ck = cv.mask().rect(cx - 5, cy - 24, cx + 5, cy - 15, 1.5)
    P(cv, ck, "#8a6a44", st, ow=1.4, depth=1, hatch=0.2)
    cv.stroke([(cx, cy + 0), (cx, cy + 14)], st.thin * 1.8, "#e8d8a0")
    cv.stroke([(cx - 5, cy + 5), (cx + 5, cy + 5)], st.thin * 1.8, "#e8d8a0")
    gloss(cv, cx - 9, cy + 2, 1.4, 5, 0.7, rot=20)


def salt_box(cv, st):
    cx, cy = 24, 32
    can = cv.mask().rect(cx - 13, cy - 18, cx + 13, cy + 20, 3)
    P(cv, can, gradient(cv.W, cv.H, "#3a5a7a", "#1e2e40", 0), st, depth=2)
    lab = cv.mask().rect(cx - 13, cy - 6, cx + 13, cy + 10)
    P(cv, lab, "#d8ccb0", st, ow=1.0, depth=1, hatch=0)
    cv.stroke([(cx - 8, cy + 2), (cx + 8, cy + 2)], st.thin * 2.2, "#3a2a22")
    P(cv, cv.mask().ellipse(cx, cy - 18, 13, 3.5), "#c8c0b0", st, ow=1.4, depth=0.8, hatch=0)
    # pouring stream & pile
    cv.stroke(catmull([(cx + 12, cy - 18), (cx + 20, cy - 8), (cx + 24, cy + 12)], 6), st.thin * 1.6, "#f4f2ec", 0.95)
    P(cv, cv.mask().ellipse(cx + 24, cy + 20, 9, 4), "#f0eee8", st, ow=1.4, depth=1, hatch=0)


def heart(cv, st, wounded=False):
    cx, cy = 32, 34
    pts = []
    for i in range(80):
        t = 2 * math.pi * i / 80
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
        pts.append((cx + x * 1.4, cy + y * 1.35 - 2))
    m = cv.mask().poly(pts)
    P(cv, m, gradient(cv.W, cv.H, "#c23a3a", "#5a0c12", 45), st, depth=3)
    gloss(cv, cx - 10, cy - 10, 3.5, 2.2, 0.55, rot=-30)
    if wounded:
        crack = [(cx + 2, cy - 15), (cx - 3, cy - 6), (cx + 3, cy + 1), (cx - 2, cy + 8), (cx + 1, cy + 14)]
        cv.stroke(crack, st.thin * 3.2, INK)
        cv.stroke(crack, st.thin * 1.2, (240, 210, 190), 0.6)
        for (x, y, ln) in ((cx - 2, cy + 8, 9), (cx + 6, cy + 4, 6)):
            d = cv.mask().ellipse(x, y + ln, 2.4, 3.2)
            d.line([(x, y), (x, y + ln)], 2.2)
            cv.part(d, BLOOD, ow=1.2, shade=0.2, light=0, hatch=0, depth=0.5)


def skull(cv, st):
    cx, cy = 32, 30
    m = cv.mask().poly(catmull([(cx - 17, cy + 4), (cx - 18, cy - 8), (cx - 8, cy - 20), (cx + 8, cy - 20),
                                (cx + 18, cy - 8), (cx + 17, cy + 4), (cx + 10, cy + 10), (cx + 9, cy + 18),
                                (cx - 9, cy + 18), (cx - 10, cy + 10), (cx - 17, cy + 4)], 6))
    P(cv, m, gradient(cv.W, cv.H, "#f2ead6", "#a49a84", 45), st, depth=3)
    for sx in (-1, 1):
        e = cv.mask().ellipse(cx + sx * 7.5, cy - 1, 5.5, 6.2, rot=sx * 12)
        cv.paint(e, INK)
    cv.paint(cv.mask().poly([(cx, cy + 5), (cx - 3, cy + 10), (cx + 3, cy + 10)]), INK)
    for k in range(5):
        x = cx - 6 + k * 3
        cv.stroke([(x, cy + 13), (x, cy + 18)], st.thin * 0.9, INK)
    cv.stroke([(cx - 8, cy + 13), (cx + 8, cy + 13)], st.thin * 0.9, INK)
    cv.stroke(catmull([(cx - 10, cy - 14), (cx - 4, cy - 12), (cx - 1, cy - 16)], 5), st.thin * 0.6, INK, 0.6)


def pocket_watch(cv, st):
    cx, cy = 32, 35
    cv.stroke(ellipse_pts(cx, cy - 25, 4, 3.4, 20) + [ellipse_pts(cx, cy - 25, 4, 3.4, 20)[0]], st.thin * 1.8, INK)
    P(cv, cv.mask().rect(cx - 3, cy - 23, cx + 3, cy - 19, 1), BRASS, st, ow=1.2, depth=0.6, hatch=0)
    P(cv, cv.mask().circle(cx, cy, 20), gradient(cv.W, cv.H, "#d8bb78", "#6a5024", 45), st, depth=2)
    P(cv, cv.mask().circle(cx, cy, 15.5), "#ece2c8", st, ow=1.2, depth=1.5, hatch=0.2)
    for k in range(12):
        a = k * math.pi / 6
        r0 = 12 if k % 3 else 10.5
        cv.stroke([(cx + math.cos(a) * r0, cy + math.sin(a) * r0), (cx + math.cos(a) * 14, cy + math.sin(a) * 14)],
                  st.thin * (1.4 if k % 3 == 0 else 0.8), INK)
    cv.stroke([(cx, cy), (cx + 7, cy - 5)], st.thin * 1.6, INK)
    cv.stroke([(cx, cy), (cx - 2, cy - 11)], st.thin * 1.2, INK)
    cv.paint(cv.mask().circle(cx, cy, 1.6), INK)


def quill(cv, st):
    pts = [(14, 54), (24, 40), (36, 24), (50, 8)]
    cp = catmull(pts, 10)
    left, right = [], []
    for i, (x, y) in enumerate(cp):
        t = i / (len(cp) - 1)
        w = 9 * math.sin(math.pi * min(1, t * 1.05)) ** 0.7 if t > 0.25 else 0.8
        dx, dy = (cp[min(i + 1, len(cp) - 1)][0] - cp[max(i - 1, 0)][0],
                  cp[min(i + 1, len(cp) - 1)][1] - cp[max(i - 1, 0)][1])
        n = math.hypot(dx, dy) + 1e-6
        left.append((x - dy / n * w * 0.7, y + dx / n * w * 0.7))
        right.append((x + dy / n * w * 1.0, y - dx / n * w * 1.0))
    m = cv.mask().poly(left + right[::-1])
    P(cv, m, gradient(cv.W, cv.H, "#ece6d6", "#8a8478", 45), st, depth=1.5)
    cv.stroke(cp, st.thin * 1.0, INK, 0.8)
    for i in range(8, len(cp) - 2, 2):
        x, y = cp[i]
        cv.stroke([(x, y), (right[i][0] + 1, right[i][1] + 1.5)], st.thin * 0.5, "#5a564c", 0.7)
    cv.stroke([(14, 54), (10, 60)], st.thin * 2, INK)


def house(cv, st):
    # gothic manor silhouette with lit window
    m = cv.mask()
    m.poly([(8, 56), (8, 32), (20, 20), (32, 32), (32, 56)])
    m.poly([(28, 56), (28, 26), (40, 10), (52, 26), (52, 56)])
    m.rect(44, 14, 48, 26)
    m.rect(6, 54, 58, 58)
    P(cv, m, noise_tex(cv.W, cv.H, rng("house"), "#3a3640", 0.2), st, depth=2)
    for (x, y) in ((16, 38), (36, 34), (44, 34), (36, 46)):
        cv.paint(cv.mask().rect(x, y, x + 4, y + 6, 1), (230, 170, 70) if (x, y) != (36, 46) else (40, 36, 44))
    cv.paint(cv.mask().poly(catmull([(18, 56), (18, 48), (22, 45), (26, 48)], 4) + [(26, 56)]), INK)
    cv.stroke([(40, 10), (40, 4)], st.thin * 1.6, INK)
    cv.stroke([(37, 6), (43, 6)], st.thin * 1.4, INK)


def trophy(cv, st):
    cx = 32
    gold = gradient(cv.W, cv.H, "#ecd290", "#6a4e1e", 30)
    cup = cv.mask().poly(catmull([(cx - 16, 10), (cx - 15, 22), (cx - 8, 32), (cx, 34), (cx + 8, 32), (cx + 15, 22),
                                  (cx + 16, 10)], 6))
    for sx in (-1, 1):
        cv.stroke(catmull([(cx + sx * 15, 14), (cx + sx * 23, 15), (cx + sx * 21, 25), (cx + sx * 11, 28)], 6),
                  st.thin * 4.4, INK)
        cv.stroke(catmull([(cx + sx * 15, 14), (cx + sx * 23, 15), (cx + sx * 21, 25), (cx + sx * 11, 28)], 6),
                  st.thin * 2.2, "#c8a860")
    P(cv, cup, gold, st, depth=2)
    stem = cv.mask().rect(cx - 3, 33, cx + 3, 46, 1)
    stem.rect(cx - 13, 46, cx + 13, 54, 2)
    P(cv, stem, gold, st, depth=1.5)
    cv.paint(cv.mask().ellipse(cx, 11, 15, 2.6), "#4a3414")
    gloss(cv, cx - 8, 18, 1.5, 5, 0.7)
    star = [(cx + math.cos(math.radians(-90 + k * 144)) * 5, 22 + math.sin(math.radians(-90 + k * 144)) * 5)
            for k in range(6)]
    cv.stroke(star, st.thin * 1.0, "#5a3a12")


def bite(cv, st):
    cx, cy = 32, 32
    sk = cv.mask().circle(cx, cy, 22)
    P(cv, sk, gradient(cv.W, cv.H, "#e2cbb8", "#9a7c6c", 45), st, depth=3)
    cv.paint(blur(cv.mask().ellipse(cx, cy, 12, 7).arr, 2 * cv.ss), (150, 50, 70), 0.6)
    for x in (cx - 6, cx + 6):
        cv.paint(dilate(cv.mask().circle(x, cy - 2, 2.8).arr, 0.6 * cv.ss), INK)
        cv.paint(cv.mask().circle(x, cy - 2, 2.8), (90, 0, 10))
        d = cv.mask().ellipse(x, cy + 10, 1.9, 2.6)
        d.line([(x, cy), (x, cy + 10)], 1.6)
        cv.paint(d, (150, 14, 24))


def mouth_voice(cv, st):
    cx, cy = 26, 32
    lips = cv.mask().poly(catmull([(cx - 16, cy), (cx - 8, cy - 9), (cx, cy - 6), (cx + 8, cy - 9), (cx + 16, cy),
                                   (cx + 8, cy + 10), (cx - 8, cy + 10), (cx - 16, cy)], 6))
    P(cv, lips, gradient(cv.W, cv.H, "#a8404a", "#4a1018", 45), st, depth=2)
    cv.paint(cv.mask().poly(catmull([(cx - 13, cy), (cx, cy - 2), (cx + 13, cy)], 6)
                            + catmull([(cx + 13, cy), (cx, cy + 3), (cx - 13, cy)], 6)), INK)
    for k in range(4):
        x = cx - 6 + k * 4
        cv.paint(cv.mask().rect(x, cy - 1.5, x + 3, cy + 0.6, 0.5), "#e8e0cc")
    for k, rr in enumerate((8, 14, 20)):
        cv.stroke(ellipse_pts(cx + 18, cy, rr, rr * 1.1, 20, 0, -45, 45), st.thin * 1.8, (60, 110, 120), 0.95 - k * 0.2)


def footprints(cv, st):
    k = 1.35

    def foot(x, y, ang, color=(40, 30, 26)):
        m = cv.mask().ellipse(x, y, 5.5 * k, 9.5 * k, rot=ang)
        m.ellipse(*poly_rot([(x, y + 9 * k)], x, y, ang)[0], 4.2 * k, 4.6 * k, rot=ang)
        for (dx, dy, rr) in ((-4.6, -11.5, 1.9), (-1.6, -13, 1.6), (1.2, -13, 1.4), (3.6, -12, 1.2), (5.4, -10.4, 1.0)):
            m.circle(*poly_rot([(x + dx * k, y + dy * k)], x, y, ang)[0], rr * k)
        cv.paint(dilate(m.arr, 1.0 * cv.ss), (20, 14, 12), 0.5)
        cv.paint(m, color, 1.0)
    foot(20, 40, -14)
    foot(43, 24, 8)


def orbs3(cv, st):
    orb(cv, st, 22, 38, 10)
    orb(cv, st, 42, 22, 7)
    orb(cv, st, 44, 46, 5)
    for (x, y, rr) in ((22, 38, 10), (42, 22, 7), (44, 46, 5)):
        cv.stroke(ellipse_pts(x, y, rr, rr, 30) + [ellipse_pts(x, y, rr, rr, 30)[0]], st.thin * 1.1, (70, 110, 120), 0.8)
