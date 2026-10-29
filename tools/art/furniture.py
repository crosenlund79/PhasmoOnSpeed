"""Top-down furniture sprites (footprint x 64 px, front faces +Y)."""
from __future__ import annotations

import math

import numpy as np
from PIL import Image

from core import (Canvas, INK, blur, col, dilate, ellipse_pts, erode, fabric_tex, fbm, gradient, mix,
                  noise_tex, radial, rng, rrect_pts, save, smoothstep, wood_tex, edge_band, catmull)

C = 64
L, T, R, B = 3, 3, 6, 7  # inset: left, top, right, bottom (room for drop shadow)

WOODS = {
    "oak": ("#6e4c31", "#2c1b10", "#8f6a48"),
    "walnut": ("#4c3222", "#1b100a", "#6b4a33"),
    "mahogany": ("#5c2a1f", "#220d08", "#7d4030"),
    "pine": ("#8c6c48", "#4a3420", "#a98a63"),
    "ebony": ("#2a2220", "#0c0908", "#3e3430"),
    "grey": ("#5e5650", "#2a2522", "#7a726a"),
}
BRASS = "#a8874a"
IRON = "#34343a"
LINEN = "#cdc4ae"
PORCELAIN = "#d9d5ca"


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
def new(name, cw, ch, ss=2):
    return Canvas(cw * C, ch * C, ss, name=name)


def box(cv):
    return L, T, cv.w - R, cv.h - B


def wtex(cv, kind="oak", vertical=False, seed="", rings=None):
    base, dark, light = WOODS[kind]
    span = cv.w if vertical else cv.h
    rings = rings or max(3, int(span / 7))
    return wood_tex(cv.W, cv.H, rng(f"{cv.name}:wood:{kind}:{vertical}:{seed}"), base, dark, light,
                    vertical=vertical, rings=rings)


def wood(cv, m, kind="oak", vertical=False, seed="", **kw):
    kw.setdefault("hatch", 0.45)
    return cv.part(m, wtex(cv, kind, vertical, seed), **kw)


def fab(cv, color, amount=0.12, weave=2.0):
    return fabric_tex(cv.W, cv.H, rng(f"{cv.name}:fab:{color}"), color, amount, weave, cv.ss)


def stone_tex(cv, color="#6a6864", seed=""):
    r = rng(f"{cv.name}:stone:{seed}")
    t = noise_tex(cv.W, cv.H, r, color, 0.18, 10, 10, 5)
    return t


def groove(cv, pts, w=1.0, op=0.85, light=0.35, closed=False):
    if closed:
        pts = list(pts) + [pts[0]]
    cv.stroke(pts, w, INK, op)
    m = cv.mask().line([(x + w * 0.9, y + w * 0.9) for x, y in pts], w * 0.8)
    cv.screen(m, light)


def groove_rect(cv, x0, y0, x1, y1, w=1.0, op=0.8, r=0):
    pts = rrect_pts(x0, y0, x1, y1, r, 4)
    groove(cv, pts, w, op, closed=True)


def knob(cv, x, y, r=2.2, color=BRASS):
    m = cv.mask().circle(x, y, r)
    cv.part(m, color, ow=1.2, shade=0.5, light=0.5, hatch=0, depth=1.0)
    cv.paint(cv.mask().circle(x - r * 0.35, y - r * 0.35, r * 0.35), (250, 235, 190), 0.8)


def cushion(cv, x0, y0, x1, y1, color, r=6, ow=2.4, soft=0.55, tufts=0, seam=True, wobble=0.5):
    m = cv.mask().rect(x0, y0, x1, y1, r, wobble=wobble)
    cv.part(m, fab(cv, color), ow=ow, shade=0.35, light=0.28, hatch=0.35, soft=soft, depth=5)
    if seam:
        g = 3.0
        pts = rrect_pts(x0 + g, y0 + g, x1 - g, y1 - g, max(1, r - 2), 4)
        cv.stroke(pts + [pts[0]], 0.6, mix(color, INK, 0.6), 0.6)
    if tufts:
        nx, ny = tufts if isinstance(tufts, tuple) else (tufts, 1)
        for i in range(nx):
            for j in range(ny):
                tx = x0 + (x1 - x0) * (i + 0.5) / nx
                ty = y0 + (y1 - y0) * (j + 0.5) / ny
                for a in range(4):
                    ang = a * math.pi / 2 + math.pi / 4
                    cv.stroke([(tx, ty), (tx + math.cos(ang) * 4, ty + math.sin(ang) * 4)], 0.6,
                              mix(color, INK, 0.7), 0.6)
                cv.paint(cv.mask().circle(tx, ty, 1.3), mix(color, INK, 0.75))
                cv.paint(cv.mask().circle(tx - 0.4, ty - 0.4, 0.5), mix(color, "#ffffff", 0.4), 0.7)
    return m


def candle(cv, x, y, r=3.0, lit=True):
    cv.part(cv.mask().circle(x, y, r), "#ddd2b4", ow=1.2, shade=0.35, light=0.3, hatch=0, depth=1.2)
    cv.paint(cv.mask().circle(x, y, r * 0.35), "#3a2a1a")
    if lit:
        cv._glows.append((x, y, r))


def book(cv, x, y, w, h, color, rot=0, pages=True):
    pts = rrect_pts(-w / 2, -h / 2, w / 2, h / 2, 1.0, 3)
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    P = lambda q: [(x + px * c - py * s, y + px * s + py * c) for px, py in q]
    m = cv.mask().poly(P(pts))
    cv.part(m, fab(cv, color, 0.1), ow=1.4, shade=0.4, light=0.25, hatch=0.3, depth=2)
    if pages:
        cv.stroke(P([(-w / 2 + 2, -h / 2 + 1.5), (-w / 2 + 2, h / 2 - 1.5)]), 0.8, "#d8c9a0", 0.9)
        g = rrect_pts(-w / 2 + 3.5, -h / 2 + 2.5, w / 2 - 2, h / 2 - 2.5, 0.5, 2)
        cv.stroke(P(g + [g[0]]), 0.5, BRASS, 0.7)


def paper(cv, x, y, w, h, rot=0, writing=True):
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    P = lambda q: [(x + px * c - py * s, y + px * s + py * c) for px, py in q]
    m = cv.mask().poly(P([(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]))
    cv.part(m, "#d6caa8", ow=1.0, shade=0.25, light=0.0, hatch=0, depth=1.5)
    if writing:
        rr = rng(f"{cv.name}:paper:{x}:{y}")
        yy = -h / 2 + 3
        while yy < h / 2 - 2:
            ln = (w - 6) * (0.5 + 0.5 * rr.random())
            cv.stroke(P([(-w / 2 + 3, yy), (-w / 2 + 3 + ln, yy)]), 0.5, "#3a3028", 0.6)
            yy += 2.6


def glow_pass(cv, extra=1.0):
    for (x, y, r) in getattr(cv, "_glows", []):
        d = radial(cv.W, cv.H, x * cv.ss, y * cv.ss, r * cv.ss * 7)
        g = np.clip(1 - d, 0, 1) ** 2.2
        cv.glow(g, (255, 170, 70), 0.45 * extra)
        # flame
        fl = cv.mask().ellipse(x, y - r * 0.15, r * 0.45, r * 0.75)
        cv.paint(dilate(fl.arr, 1.2 * cv.ss), (255, 160, 50))
        cv.paint(fl, (255, 236, 170))


def finish(cv, rel, shadow=(3.0, 4.0, 2.5, 0.55), grain=0.07):
    cv.grain(grain)
    if shadow:
        cv.drop_shadow(*shadow)
    glow_pass(cv)
    img = cv.image()
    save(img, rel)
    return img


def F(name, cw, ch):
    cv = new(name, cw, ch)
    cv._glows = []
    return cv


# --------------------------------------------------------------------------
# bedroom
# --------------------------------------------------------------------------
def _bed(name, cw, ch, pillows):
    cv = F(name, cw, ch)
    x0, y0, x1, y1 = box(cv)
    # frame
    frame = cv.mask().rect(x0, y0, x1, y1, 5, wobble=0.3)
    wood(cv, frame, "walnut", True)
    # mattress / blanket area
    mx0, my0, mx1, my1 = x0 + 6, y0 + 22, x1 - 6, y1 - 12
    cushion(cv, mx0, my0, mx1, my1, LINEN, r=6, soft=0.35, seam=False)
    # blanket (quilt) covering lower 70%
    by0 = my0 + (my1 - my0) * 0.3
    bl = cv.mask().rect(mx0 - 1.5, by0, mx1 + 1.5, my1 + 2, 6, wobble=0.6)
    q = fab(cv, "#5b2a2a" if cw > 2 else "#3f4f62", 0.1)
    cv.part(bl, q, ow=2.4, shade=0.4, light=0.2, hatch=0.4, soft=0.4, depth=6)
    # quilt diamond stitching
    m = bl.arr
    xs = np.arange(cv.W)[None, :] / cv.ss
    ys = np.arange(cv.H)[:, None] / cv.ss
    p = 14.0
    lat = (np.abs(((xs + ys) % p) - p / 2) < 0.45) | (np.abs(((xs - ys) % p) - p / 2) < 0.45)
    cv.tint(lat * erode(m, 3 * cv.ss), "#1d0f0f" if cw > 2 else "#18202a", 0.5)
    # folded-back sheet band
    fb = cv.mask().rect(mx0 - 1, by0 - 1, mx1 + 1, by0 + 7, 3, wobble=0.4)
    cv.part(fb, fab(cv, "#ddd5c0"), ow=1.8, shade=0.35, light=0.3, hatch=0.2, depth=2.5)
    # wrinkles
    rr = cv.rnd
    for i in range(7):
        sx = mx0 + 6 + rr.random() * (mx1 - mx0 - 12)
        sy = by0 + 14 + rr.random() * (my1 - by0 - 24)
        cv.stroke(catmull([(sx, sy), (sx + 5, sy + 3 + rr.random() * 3), (sx + 9, sy + 9)], 6), 0.7, INK, 0.35)
    # pillows
    pw = (mx1 - mx0 - 6 * (pillows - 1) - 4) / pillows
    for i in range(pillows):
        px0 = mx0 + 2 + i * (pw + 6)
        cushion(cv, px0, my0 + 3, px0 + pw, my0 + 24, "#e2dccb", r=7, soft=0.6, seam=False, wobble=0.8)
        cv.stroke(catmull([(px0 + pw * 0.3, my0 + 13), (px0 + pw * 0.5, my0 + 15), (px0 + pw * 0.7, my0 + 12)], 6),
                  0.7, INK, 0.35)
    # headboard (carved) & footboard
    hb = cv.mask().rect(x0, y0, x1, y0 + 14, 5, wobble=0.3)
    wood(cv, hb, "walnut", False, "hb", ow=3)
    groove_rect(cv, x0 + 4, y0 + 4, x1 - 4, y0 + 10, 0.8)
    for xx in (x0 + 6, x1 - 6):
        cv.part(cv.mask().circle(xx, y0 + 7, 5), wtex(cv, "walnut", seed="post"), ow=2, depth=2)
        knob(cv, xx, y0 + 7, 2.0)
    fbm_ = cv.mask().rect(x0, y1 - 10, x1, y1, 4, wobble=0.3)
    wood(cv, fbm_, "walnut", False, "fb", ow=3)
    groove(cv, [(x0 + 6, y1 - 5), (x1 - 6, y1 - 5)], 0.8)
    for xx in (x0 + 5, x1 - 5):
        knob(cv, xx, y1 - 5, 2.6)
    return finish(cv, f"furniture/{name}.png")


def bed_double():
    return _bed("bed_double", 3, 4, 2)


def bed_single():
    return _bed("bed_single", 2, 4, 1)


def _case_top(cv, kind, x0, y0, x1, y1, r=3, crown=True):
    m = cv.mask().rect(x0, y0, x1, y1, r, wobble=0.3)
    wood(cv, m, kind, False, "top", ow=3.2)
    if crown:
        groove_rect(cv, x0 + 3.5, y0 + 3.5, x1 - 3.5, y1 - 3.5, 0.9, r=1)
    return m


def wardrobe():
    cv = F("wardrobe", 3, 1)
    x0, y0, x1, y1 = box(cv)
    # door edge strip at the front (seen just beyond the cornice)
    front = cv.mask().rect(x0 + 3, y1 - 10, x1 - 3, y1, 2)
    wood(cv, front, "oak", False, "front", ow=2.5)
    mid = (x0 + x1) / 2
    cv.stroke([(mid, y1 - 9), (mid, y1 - 1)], 1.0, INK, 0.9)
    # cornice top
    _case_top(cv, "oak", x0, y0, x1, y1 - 7, 4)
    groove_rect(cv, x0 + 8, y0 + 8, x1 - 8, y1 - 15, 0.8, r=2)
    # carved central cartouche
    cm = cv.mask().ellipse(mid, (y0 + y1 - 7) / 2, 14, 8, wobble=0.3)
    wood(cv, cm, "oak", True, "cart", ow=1.6, depth=2)
    groove(cv, ellipse_pts(mid, (y0 + y1 - 7) / 2, 9, 4.5, 30), 0.7, closed=True)
    for xx in (mid - 4, mid + 4):
        knob(cv, xx, y1 - 2, 2.0)
    # dust & a hatbox on top
    hb = cv.mask().circle(x0 + 26, y0 + 21, 14)
    cv.part(hb, fab(cv, "#6a5a4c"), ow=2.4, depth=3, soft=0.3)
    cv.stroke(ellipse_pts(x0 + 26, y0 + 21, 11, 11, 40) + [ellipse_pts(x0 + 26, y0 + 21, 11, 11, 40)[0]], 0.7, INK, 0.6)
    cv.stroke([(x0 + 12, y0 + 21), (x0 + 40, y0 + 21)], 2.0, "#7a2a2a")
    cv.stroke([(x0 + 26, y0 + 7), (x0 + 26, y0 + 35)], 2.0, "#7a2a2a")
    for a in (0.6, 2.4):
        cv.part(cv.mask().ellipse(x0 + 26 + math.cos(a) * 4, y0 + 21 - math.sin(a) * 3, 4, 2.2, rot=-math.degrees(a)),
                "#8a3030", ow=1.0, depth=0.8, hatch=0)
    # folded linens
    ln = cv.mask().rect(x1 - 52, y0 + 9, x1 - 18, y0 + 31, 3, wobble=0.5)
    cv.part(ln, fab(cv, "#cfc6b0"), ow=1.8, shade=0.35, light=0.25, hatch=0.3, depth=2)
    for yy in (y0 + 15, y0 + 20, y0 + 25):
        cv.stroke([(x1 - 50, yy), (x1 - 20, yy)], 0.5, INK, 0.5)
    return finish(cv, "furniture/wardrobe.png")


def dresser():
    cv = F("dresser", 2, 1)
    x0, y0, x1, y1 = box(cv)
    _case_top(cv, "walnut", x0, y0, x1, y1 - 2, 3)
    for xx in (x0 + 18, x1 - 18):
        knob(cv, xx, y1 - 1, 2.2)
    # lace doily, perfume bottle, hairbrush
    d = cv.mask().ellipse(x0 + 40, y0 + 25, 18, 12, wobble=0.6)
    cv.part(d, "#d8d0bb", ow=1.0, shade=0.2, light=0, hatch=0, depth=2)
    for k in range(12):
        a = k * math.pi / 6
        cv.paint(cv.mask().circle(x0 + 40 + math.cos(a) * 13, y0 + 25 + math.sin(a) * 8.5, 1.6), "#9a927e", 0.8)
    rr = cv.rnd
    cv.part(cv.mask().circle(x0 + 40, y0 + 25, 6), "#5d6f70", ow=1.4, shade=0.5, light=0.5, hatch=0, depth=1.5)
    for k in range(9):
        a = k * 2 * math.pi / 9 + rr.normal(0, 0.2)
        px, py = x0 + 40 + math.cos(a) * 5.5, y0 + 25 + math.sin(a) * 4.5
        cv.part(cv.mask().circle(px, py, 2.4 + rr.random()), "#6e2a30" if k % 3 else "#8a6a4a", ow=0.9,
                shade=0.4, light=0.3, hatch=0, depth=0.8)
    hb = cv.mask().rect(x1 - 34, y0 + 14, x1 - 12, y0 + 22, 3)
    cv.part(hb, wtex(cv, "mahogany", seed="brush"), ow=1.4, depth=1.5)
    cv.part(cv.mask().ellipse(x1 - 38, y0 + 18, 7, 6), "#3b2a22", ow=1.4, depth=1.5)
    return finish(cv, "furniture/dresser.png")


def nightstand():
    cv = F("nightstand", 1, 1)
    x0, y0, x1, y1 = box(cv)
    _case_top(cv, "walnut", x0, y0, x1, y1 - 2, 3)
    knob(cv, (x0 + x1) / 2, y1 - 1, 2.0)
    book(cv, x0 + 20, y0 + 30, 18, 24, "#3f2a35", rot=-12)
    # candle in brass holder
    cv.part(cv.mask().circle(x1 - 16, y0 + 16, 8), BRASS, ow=1.6, shade=0.45, light=0.4, hatch=0, depth=2)
    cv.stroke([(x1 - 9, y0 + 16), (x1 - 5, y0 + 18)], 1.6, INK)
    candle(cv, x1 - 16, y0 + 16, 3.5)
    return finish(cv, "furniture/nightstand.png")


def wall_mirror():
    cv = F("wall_mirror", 2, 1)
    x0, y0, x1, _ = box(cv)
    y1 = 24
    fr = cv.mask().rect(x0 + 4, y0, x1 - 4, y1, 4, wobble=0.3)
    cv.part(fr, noise_tex(cv.W, cv.H, cv.rnd, "#9a7a40", 0.2), ow=3, shade=0.5, light=0.4, hatch=0.4, depth=3)
    # ornate crest
    crest = cv.mask().ellipse((x0 + x1) / 2, y1 - 2, 12, 6, wobble=0.6)
    cv.part(crest, "#a8874a", ow=2, shade=0.5, light=0.45, hatch=0.3, depth=2)
    for xx in (x0 + 10, x1 - 10):
        cv.part(cv.mask().circle(xx, y1 - 3, 4), "#a8874a", ow=1.6, depth=1.5)
    # silvered glass edge
    gl = cv.mask().rect(x0 + 10, y0 + 5, x1 - 10, y1 - 8, 2)
    g = gradient(cv.W, cv.H, "#c9d6db", "#5e7178", 20)
    cv.part(gl, g, ow=1.4, shade=0.3, light=0.5, hatch=0, depth=1.5)
    for k in range(3):
        xx = x0 + 22 + k * 24
        cv.stroke([(xx, y0 + 6), (xx + 6, y1 - 9)], 1.0, "#ffffff", 0.55)
    # faint reflected sheen on the floor
    m = np.zeros((cv.H, cv.W), np.float32)
    sh = cv.mask().poly([(x0 + 12, y1 + 2), (x1 - 12, y1 + 2), (x1 - 2, cv.h - 4), (x0 + 2, cv.h - 4)])
    m = blur(sh.arr, 4 * cv.ss) * 0.16
    cv.grain(0.06)
    cv.drop_shadow(2, 3, 2, 0.5)
    cv.glow(m, (170, 200, 215), 1.0)
    save(cv.image(), "furniture/wall_mirror.png")


# --------------------------------------------------------------------------
# study / living
# --------------------------------------------------------------------------
def desk():
    cv = F("desk", 3, 2)
    x0, y0, x1, y1 = box(cv)
    top = cv.mask().rect(x0, y0, x1, y1, 4, wobble=0.3)
    wood(cv, top, "mahogany", False, ow=3.4)
    groove_rect(cv, x0 + 4, y0 + 4, x1 - 4, y1 - 4, 0.9, r=2)
    # leather writing inset
    lt = cv.mask().rect(x0 + 34, y0 + 14, x1 - 34, y1 - 18, 2)
    cv.part(lt, fab(cv, "#2f4a3a", 0.2), ow=1.6, shade=0.3, light=0.15, hatch=0.25, depth=2)
    cv.stroke(rrect_pts(x0 + 37, y0 + 17, x1 - 37, y1 - 21, 1, 2) + [(x0 + 37 + 1, y0 + 17)], 0.6, BRASS, 0.7)
    paper(cv, x0 + 82, y0 + 52, 34, 44, rot=-6)
    paper(cv, x0 + 108, y0 + 50, 30, 40, rot=9)
    # inkwell & quill
    cv.part(cv.mask().circle(x1 - 50, y0 + 30, 7), "#2c3238", ow=1.8, shade=0.4, light=0.5, hatch=0, depth=2)
    cv.paint(cv.mask().circle(x1 - 50, y0 + 30, 3.5), "#0c0c10")
    q = cv.mask().curve([(x1 - 52, y0 + 28), (x1 - 40, y0 + 12), (x1 - 28, y0 + 4)], 2.6)
    cv.part(q, "#e2dccb", ow=1.0, shade=0.3, light=0, hatch=0, depth=1)
    cv.stroke([(x1 - 50, y0 + 27), (x1 - 29, y0 + 5)], 0.6, INK, 0.7)
    # books stack and candle
    book(cv, x0 + 20, y0 + 32, 22, 30, "#5a2526", rot=4)
    book(cv, x0 + 21, y0 + 30, 19, 26, "#2b3d52", rot=-8)
    cv.part(cv.mask().circle(x1 - 18, y1 - 22, 8), BRASS, ow=1.6, shade=0.45, light=0.4, hatch=0, depth=2)
    candle(cv, x1 - 18, y1 - 22, 3.6)
    for xx in (x0 + 52, x1 - 52):
        knob(cv, xx, y1 - 1, 2.0)
    return finish(cv, "furniture/desk.png")


def chair(name="chair", kind="walnut", seat="#5a2c2a", cv=None, save_it=True):
    if cv is None:
        cv = F(name, 1, 1)
    x0, y0, x1, y1 = box(cv)
    w = x1 - x0
    seatm = cv.mask().rect(x0 + 6, y0 + 14, x1 - 6, y1, 6, wobble=0.3)
    wood(cv, seatm, kind, False, "seat", ow=3)
    cushion(cv, x0 + 10, y0 + 18, x1 - 10, y1 - 4, seat, r=5, soft=0.5, tufts=1)
    back = cv.mask().poly(catmull([(x0 + 2, y0 + 12), (x0 + w / 2, y0 + 1), (x1 - 2, y0 + 12)], 10)
                          + catmull([(x1 - 4, y0 + 18), (x0 + w / 2, y0 + 9), (x0 + 4, y0 + 18)], 10), wobble=0.3)
    wood(cv, back, kind, False, "back", ow=3, depth=2.5)
    for k in range(4):
        xx = x0 + 12 + k * (w - 24) / 3
        cv.stroke([(xx, y0 + 9 + abs(k - 1.5) * 1.6), (xx, y0 + 17)], 1.0, INK, 0.6)
    if save_it:
        return finish(cv, f"furniture/{name}.png")
    return cv


def armchair():
    cv = F("armchair", 2, 2)
    x0, y0, x1, y1 = box(cv)
    col_ = "#43566a"
    # base/outer shell
    body = cv.mask().rect(x0 + 2, y0 + 4, x1 - 2, y1, 14, wobble=0.5)
    cv.part(body, fab(cv, col_), ow=3.4, shade=0.4, light=0.2, hatch=0.4, soft=0.4, depth=6)
    # back with wings
    back = cv.mask().poly(catmull([(x0, y0 + 30), (x0 + 4, y0 + 6), (x0 + 30, y0), ((x0 + x1) / 2, y0 + 2),
                                   (x1 - 30, y0), (x1 - 4, y0 + 6), (x1, y0 + 30)], 8)
                          + [(x1 - 18, y0 + 30), (x1 - 20, y0 + 20), ((x0 + x1) / 2, y0 + 18),
                             (x0 + 20, y0 + 20), (x0 + 18, y0 + 30)], wobble=0.4)
    cv.part(back, fab(cv, col_), ow=3.2, shade=0.45, light=0.3, hatch=0.4, soft=0.5, depth=5)
    # arms
    for (ax0, ax1) in ((x0 + 2, x0 + 20), (x1 - 20, x1 - 2)):
        a = cv.mask().rect(ax0, y0 + 24, ax1, y1 - 2, 8, wobble=0.5)
        cushion(cv, ax0, y0 + 24, ax1, y1 - 2, col_, r=8, soft=0.55)
        cv.stroke(catmull([(ax0 + 4, y1 - 8), ((ax0 + ax1) / 2, y1 - 5), (ax1 - 4, y1 - 8)], 6), 0.7, INK, 0.5)
    # seat cushion with tufting
    cushion(cv, x0 + 22, y0 + 22, x1 - 22, y1 - 6, "#4d6176", r=7, soft=0.55, tufts=(2, 2))
    # tufting on back
    for i in range(5):
        tx = x0 + 26 + i * (x1 - x0 - 52) / 4
        cv.paint(cv.mask().circle(tx, y0 + 10 + abs(i - 2) * 1.2, 1.3), "#1d2530")
    # antimacassar lace
    lc = cv.mask().rect((x0 + x1) / 2 - 14, y0 + 3, (x0 + x1) / 2 + 14, y0 + 13, 3, wobble=0.8)
    cv.part(lc, "#d6cfbb", ow=1.0, shade=0.2, light=0, hatch=0, depth=1.5)
    return finish(cv, "furniture/armchair.png")


def sofa():
    cv = F("sofa", 4, 2)
    x0, y0, x1, y1 = box(cv)
    c = "#5e2425"
    body = cv.mask().rect(x0 + 2, y0 + 4, x1 - 2, y1, 12, wobble=0.5)
    cv.part(body, fab(cv, c), ow=3.4, shade=0.4, light=0.2, hatch=0.4, soft=0.4, depth=6)
    # rolled back (chesterfield)
    back = cv.mask().rect(x0, y0, x1, y0 + 30, 12, wobble=0.5)
    cv.part(back, fab(cv, c), ow=3.2, shade=0.45, light=0.3, hatch=0.4, soft=0.55, depth=5)
    for i in range(14):
        for j in range(2):
            tx = x0 + 22 + i * (x1 - x0 - 44) / 13 + (j * (x1 - x0 - 44) / 26)
            ty = y0 + 9 + j * 10
            if tx > x1 - 20:
                continue
            cv.paint(cv.mask().circle(tx, ty, 1.4), "#200b0b")
            for a in range(4):
                ang = a * math.pi / 2 + math.pi / 4
                cv.stroke([(tx, ty), (tx + math.cos(ang) * 3.5, ty + math.sin(ang) * 3.5)], 0.6, "#200b0b", 0.5)
    for (ax0, ax1) in ((x0, x0 + 24), (x1 - 24, x1)):
        cushion(cv, ax0, y0 + 6, ax1, y1 - 2, c, r=10, soft=0.6)
        cv.stroke(ellipse_pts((ax0 + ax1) / 2, y1 - 16, 6, 6, 20, 0, 0, 300), 0.8, INK, 0.5)
    seat_w = (x1 - x0 - 52) / 3
    for i in range(3):
        sx = x0 + 26 + i * seat_w
        cushion(cv, sx + 1, y0 + 30, sx + seat_w - 1, y1 - 6, "#6b2c2c", r=6, soft=0.55, tufts=1)
    # throw pillow
    p = cv.mask().rect(x0 + 30, y0 + 22, x0 + 54, y0 + 44, 6, wobble=0.8)
    cv.part(p, fab(cv, "#8a7546"), ow=2.0, shade=0.4, light=0.3, hatch=0.3, soft=0.5, depth=3)
    return finish(cv, "furniture/sofa.png")


def coffee_table():
    cv = F("coffee_table", 2, 1)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().ellipse((x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2, n=120, wobble=0.3)
    wood(cv, m, "mahogany", False, ow=3.2)
    groove(cv, ellipse_pts((x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2 - 5, (y1 - y0) / 2 - 5, 90), 0.9, closed=True)
    # tea tray, cup and saucer
    tr = cv.mask().rect(x0 + 30, y0 + 13, x0 + 62, y1 - 13, 4)
    cv.part(tr, "#8f8a80", ow=1.6, shade=0.45, light=0.45, hatch=0.2, depth=2)
    for (cx, cy) in ((x0 + 40, y0 + 25), (x0 + 54, y1 - 22)):
        cv.part(cv.mask().circle(cx, cy, 5.5), PORCELAIN, ow=1.2, shade=0.3, light=0.3, hatch=0, depth=1.2)
        cv.paint(cv.mask().circle(cx, cy, 3.2), "#4a2e1c")
    book(cv, x1 - 30, (y0 + y1) / 2, 18, 22, "#2e3a2c", rot=78)
    return finish(cv, "furniture/coffee_table.png")


def dining_table():
    cv = F("dining_table", 5, 3)
    W, H = cv.w, cv.h
    # chairs around the table (drawn first so the table overlaps them)
    def place_chair(cx, cy, rot):
        sub = F(f"dining_chair_{cx}_{cy}", 1, 1)
        chair(cv=sub, save_it=False, kind="walnut", seat="#4f2827")
        sub.grain(0.05)
        sub.drop_shadow(2, 3, 2, 0.5)
        im = sub.image().rotate(rot, resample=Image.BICUBIC)
        arr = np.asarray(im.resize((im.width * cv.ss, im.height * cv.ss), Image.LANCZOS), np.float32)
        a = arr[..., 3] / 255
        X, Y = int(cx * cv.ss - arr.shape[1] / 2), int(cy * cv.ss - arr.shape[0] / 2)
        h, w = arr.shape[:2]
        tgt_rgb = cv.rgb[Y:Y + h, X:X + w]
        tgt_a = cv.a[Y:Y + h, X:X + w]
        aa = a[:tgt_rgb.shape[0], :tgt_rgb.shape[1]]
        tgt_rgb[:] = tgt_rgb * (1 - aa[..., None]) + arr[:tgt_rgb.shape[0], :tgt_rgb.shape[1], :3] * aa[..., None]
        tgt_a[:] = tgt_a + aa * (1 - tgt_a)
    for k in range(3):
        cx = 72 + k * 88
        place_chair(cx, 32, 180)
        place_chair(cx, H - 36, 0)
    place_chair(30, H / 2 - 2, -90)
    place_chair(W - 33, H / 2 - 2, 90)
    tx0, ty0, tx1, ty1 = 44, 40, W - 48, H - 46
    top = cv.mask().rect(tx0, ty0, tx1, ty1, 6, wobble=0.3)
    wood(cv, top, "walnut", False, ow=3.4)
    groove_rect(cv, tx0 + 5, ty0 + 5, tx1 - 5, ty1 - 5, 0.9, r=3)
    # lace runner
    rn = cv.mask().rect(tx0 + 20, (ty0 + ty1) / 2 - 16, tx1 - 20, (ty0 + ty1) / 2 + 16, 2, wobble=0.6)
    cv.part(rn, fab(cv, "#d4ccb6"), ow=1.4, shade=0.25, light=0.1, hatch=0.15, depth=2)
    for i in range(int((tx1 - tx0 - 44) / 8)):
        xx = tx0 + 24 + i * 8
        for yy in ((ty0 + ty1) / 2 - 13, (ty0 + ty1) / 2 + 13):
            cv.paint(cv.mask().circle(xx, yy, 1.5), "#9d947f", 0.8)
    # plates
    for k in range(3):
        cx = 72 + k * 88
        for cy in (ty0 + 15, ty1 - 15):
            cv.part(cv.mask().circle(cx, cy, 10), PORCELAIN, ow=1.6, shade=0.35, light=0.3, hatch=0, depth=2)
            cv.stroke(ellipse_pts(cx, cy, 6.5, 6.5, 30) + [ellipse_pts(cx, cy, 6.5, 6.5, 30)[0]], 0.6, "#7d8a96", 0.8)
            cv.stroke([(cx - 14, cy - 6), (cx - 14, cy + 6)], 1.2, "#9a9a9a")
            cv.stroke([(cx + 14, cy - 6), (cx + 14, cy + 6)], 1.2, "#9a9a9a")
    for cy in ((ty0 + ty1) / 2,):
        for cx in (tx0 + 15, tx1 - 15):
            cv.part(cv.mask().circle(cx, cy, 10), PORCELAIN, ow=1.6, shade=0.35, light=0.3, hatch=0, depth=2)
    # centre candelabra
    cx, cy = (tx0 + tx1) / 2, (ty0 + ty1) / 2
    cv.part(cv.mask().circle(cx, cy, 8), BRASS, ow=1.8, shade=0.45, light=0.4, hatch=0, depth=2)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        ex, ey = cx + math.cos(a) * 15, cy + math.sin(a) * 11
        cv.stroke([(cx, cy), (ex, ey)], 2.6, INK)
        cv.stroke([(cx, cy), (ex, ey)], 1.4, BRASS)
        cv.part(cv.mask().circle(ex, ey, 4.5), BRASS, ow=1.4, depth=1.2, hatch=0)
        candle(cv, ex, ey, 2.8)
    candle(cv, cx, cy, 3.0)
    return finish(cv, "furniture/dining_table.png")


def bookshelf():
    cv = F("bookshelf", 3, 1)
    x0, y0, x1, y1 = box(cv)
    frame = cv.mask().rect(x0, y0, x1, y1, 3, wobble=0.2)
    wood(cv, frame, "walnut", False, ow=3.4)
    inner = cv.mask().rect(x0 + 5, y0 + 5, x1 - 5, y1 - 4, 1)
    cv.paint(inner, "#140e0a")
    rr = cv.rnd
    cols_ = ["#5a2526", "#2b3d52", "#3d4a2c", "#6b5a3a", "#4a2e40", "#2a2a2a", "#7a6a50", "#38302a"]
    # two partitions
    parts = [x0 + 5, x0 + (x1 - x0) / 3, x0 + 2 * (x1 - x0) / 3, x1 - 5]
    for pi in range(3):
        xx = parts[pi] + (2 if pi else 0)
        end = parts[pi + 1] - 2
        while xx < end - 3:
            bw = 3 + rr.random() * 4.5
            if xx + bw > end:
                break
            depth = 14 + rr.random() * (y1 - y0 - 24)
            if rr.random() < 0.08:
                xx += bw
                continue
            c_ = cols_[int(rr.integers(0, len(cols_)))]
            bm = cv.mask().rect(xx, y1 - 5 - depth, xx + bw, y1 - 5, 0.8)
            cv.part(bm, fab(cv, c_, 0.15), ow=0.9, shade=0.4, light=0.35, hatch=0, depth=1.2)
            cv.stroke([(xx + bw / 2, y1 - 5 - depth + 2), (xx + bw / 2, y1 - 6)], 0.4, "#c7b27a", 0.5)
            xx += bw + 0.5
        if pi < 2:
            pm = cv.mask().rect(parts[pi + 1] - 2, y0 + 3, parts[pi + 1] + 2, y1 - 3)
            wood(cv, pm, "walnut", True, "part", ow=1.4, depth=1)
    # front lip
    lip = cv.mask().rect(x0 + 2, y1 - 6, x1 - 2, y1, 2)
    wood(cv, lip, "walnut", False, "lip", ow=2.2, depth=2)
    return finish(cv, "furniture/bookshelf.png")


def fireplace():
    cv = F("fireplace", 3, 1)
    x0, y0, x1, y1 = box(cv)
    st = stone_tex(cv, "#6c6862")
    # mantle / surround
    sur = cv.mask().rect(x0, y0, x1, y1 - 8, 3, wobble=0.4)
    cv.part(sur, st, ow=3.4, shade=0.5, light=0.3, hatch=0.5, depth=4)
    # mantle shelf (carved)
    mant = cv.mask().rect(x0 + 2, y0 + 2, x1 - 2, y0 + 16, 2, wobble=0.3)
    cv.part(mant, stone_tex(cv, "#7b766e", "m"), ow=2.4, shade=0.5, light=0.35, hatch=0.4, depth=3)
    groove(cv, [(x0 + 8, y0 + 9), (x1 - 8, y0 + 9)], 0.8)
    for xx in (x0 + 22, x1 - 22):
        candle(cv, xx, y0 + 9, 3.0)
    # firebox
    fx0, fx1 = x0 + 34, x1 - 34
    fb = cv.mask().rect(fx0, y0 + 18, fx1, y1 - 4, 2)
    cv.part(fb, "#0e0908", ow=2.4, shade=0, light=0, hatch=0)
    # logs & embers
    rr = cv.rnd
    glowm = cv.mask().rect(fx0 + 4, y0 + 22, fx1 - 4, y1 - 8, 3)
    cv.paint(blur(glowm.arr, 3 * cv.ss), (170, 60, 20), 0.85)
    for k in range(3):
        lx = fx0 + 10 + k * (fx1 - fx0 - 20) / 2.6
        lg = cv.mask().rect(lx, y0 + 24 + (k % 2) * 4, lx + 40, y0 + 31 + (k % 2) * 4, 3.5)
        cv.part(lg, wtex(cv, "walnut", seed=f"log{k}"), ow=1.6, shade=0.5, light=0.0, hatch=0.3, depth=2)
        cv.paint(cv.mask().rect(lx + 2, y0 + 30 + (k % 2) * 4, lx + 38, y0 + 31.5 + (k % 2) * 4), (255, 120, 40), 0.85)
    for _ in range(50):
        ex, ey = fx0 + 6 + rr.random() * (fx1 - fx0 - 12), y0 + 21 + rr.random() * (y1 - y0 - 29)
        cv.paint(cv.mask().circle(ex, ey, 0.6 + rr.random()), (255, 190, 90), 0.9)
    # flames
    for k in range(5):
        fx = fx0 + 14 + k * (fx1 - fx0 - 28) / 4
        fl = cv.mask().poly(catmull([(fx - 6, y0 + 34), (fx - 3, y0 + 26), (fx + rr.normal(0, 1.5), y0 + 20),
                                     (fx + 3, y0 + 26), (fx + 6, y0 + 34)], 6))
        cv.paint(fl, (255, 150, 50), 0.9)
        cv.paint(cv.mask().ellipse(fx, y0 + 30, 2.5, 4), (255, 235, 170), 0.9)
    # hearth apron
    ap = cv.mask().rect(x0 + 24, y1 - 10, x1 - 24, y1, 2, wobble=0.3)
    cv.part(ap, stone_tex(cv, "#4c4a48", "ap"), ow=2.4, shade=0.4, light=0.25, hatch=0.4, depth=2)
    for xx in np.linspace(x0 + 40, x1 - 40, 6):
        cv.stroke([(xx, y1 - 9), (xx, y1 - 1)], 0.6, INK, 0.6)
    cv._glows.append(((x0 + x1) / 2, y0 + 30, 9))
    cv.grain(0.07)
    cv.drop_shadow(3, 4, 2.5, 0.55)
    glow_pass(cv)
    g = np.clip(1 - radial(cv.W, cv.H, (x0 + x1) / 2 * cv.ss, y1 * cv.ss, 70 * cv.ss), 0, 1) ** 2
    cv.glow(g, (255, 140, 50), 0.25)
    save(cv.image(), "furniture/fireplace.png")


def piano():
    cv = F("piano", 3, 2)
    x0, y0, x1, y1 = box(cv)
    # baby grand: keyboard along the bottom, curved bentside to the right
    pts = [(x0 + 2, y1 - 22), (x0 + 2, y0 + 14)] + catmull(
        [(x0 + 2, y0 + 14), (x0 + 30, y0 + 1), (x0 + 90, y0 + 2), (x1 - 40, y0 + 20), (x1 - 6, y0 + 40),
         (x1 - 2, y1 - 30), (x1 - 6, y1 - 22)], 10) + [(x1 - 6, y1 - 22)]
    body = cv.mask().poly(pts, wobble=0.3)
    t = wtex(cv, "ebony")
    cv.part(body, t, ow=3.6, shade=0.5, light=0.35, hatch=0.4, depth=5)
    # lid sheen
    sheen = cv.mask().poly(catmull([(x0 + 20, y0 + 16), (x0 + 80, y0 + 10), (x1 - 50, y0 + 30)], 8)
                           + [(x1 - 54, y0 + 38), (x0 + 22, y0 + 26)])
    cv.screen(blur(sheen.arr, 3 * cv.ss), 0.25, (200, 210, 230))
    # hinge line & music desk
    groove(cv, [(x0 + 8, y1 - 34), (x1 - 12, y1 - 34)], 0.8)
    md = cv.mask().rect(x0 + 50, y1 - 42, x1 - 70, y1 - 35, 1.5)
    wood(cv, md, "ebony", seed="md", ow=1.4, depth=1)
    paper(cv, x0 + 80, y1 - 46, 22, 10, 0, True)
    # keyboard
    kb = cv.mask().rect(x0 + 4, y1 - 24, x1 - 10, y1 - 8, 1)
    cv.part(kb, "#e3dccb", ow=2.2, shade=0.2, light=0, hatch=0, depth=2)
    n = 36
    kw = (x1 - 10 - x0 - 4) / n
    for i in range(n + 1):
        xx = x0 + 4 + i * kw
        cv.stroke([(xx, y1 - 23), (xx, y1 - 8)], 0.4, INK, 0.8)
    for i in range(n):
        if i % 7 in (0, 1, 3, 4, 5):
            xx = x0 + 4 + (i + 1) * kw
            cv.paint(cv.mask().rect(xx - kw * 0.3, y1 - 24, xx + kw * 0.3, y1 - 15), INK)
    cheek = cv.mask().rect(x0 + 2, y1 - 26, x1 - 8, y1 - 22, 1)
    wood(cv, cheek, "ebony", seed="ch", ow=1.2, depth=1)
    # bench
    bn = cv.mask().rect(x0 + 50, y1 - 6, x1 - 60, y1, 2)
    wood(cv, bn, "ebony", seed="bn", ow=2.0, depth=1.5)
    return finish(cv, "furniture/piano.png")


def grandfather_clock():
    cv = F("grandfather_clock", 1, 1)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0 + 6, y0 + 2, x1 - 6, y1, 3, wobble=0.2)
    wood(cv, m, "mahogany", False, ow=3.2)
    # bonnet pediment (swan neck) from above
    ped = cv.mask().rect(x0 + 3, y0, x1 - 3, y0 + 12, 3)
    wood(cv, ped, "mahogany", False, "p", ow=2.6, depth=2)
    for xx in (x0 + 8, (x0 + x1) / 2, x1 - 8):
        knob(cv, xx, y0 + 6, 2.6)
    # dial
    cx, cy = (x0 + x1) / 2, y0 + 33
    cv.part(cv.mask().circle(cx, cy, 15), "#a8874a", ow=2.0, shade=0.5, light=0.4, hatch=0.2, depth=2)
    cv.part(cv.mask().circle(cx, cy, 12), "#e0d6bc", ow=1.0, shade=0.25, light=0.0, hatch=0, depth=1.5)
    for k in range(12):
        a = k * math.pi / 6
        cv.stroke([(cx + math.cos(a) * 9, cy + math.sin(a) * 9), (cx + math.cos(a) * 11, cy + math.sin(a) * 11)],
                  0.8 if k % 3 else 1.4, INK)
    cv.stroke([(cx, cy), (cx + 6, cy - 4)], 1.2, INK)
    cv.stroke([(cx, cy), (cx - 2, cy - 9)], 0.9, INK)
    cv.paint(cv.mask().circle(cx, cy, 1.2), INK)
    return finish(cv, "furniture/grandfather_clock.png")


def potted_plant():
    cv = F("potted_plant", 1, 1)
    cx, cy = 28, 28
    rr = cv.rnd
    cv.part(cv.mask().circle(cx, cy, 17), noise_tex(cv.W, cv.H, rr, "#8a4f34", 0.15), ow=3, shade=0.45, light=0.3,
            hatch=0.4, depth=3)
    groove(cv, ellipse_pts(cx, cy, 15, 15, 40), 0.7, closed=True)
    cv.paint(cv.mask().circle(cx, cy, 13), "#2a1d14")
    # fronds
    for k in range(11):
        a = k * 2 * math.pi / 11 + rr.normal(0, 0.15)
        ln = 21 + rr.random() * 6
        tip = (cx + math.cos(a) * ln, cy + math.sin(a) * ln)
        mid = (cx + math.cos(a + 0.2) * ln * 0.55, cy + math.sin(a + 0.2) * ln * 0.55)
        leaf = cv.mask()
        pts_l = catmull([(cx, cy), mid, tip], 10)
        left, right = [], []
        for i, (px, py) in enumerate(pts_l):
            t = i / (len(pts_l) - 1)
            w = 5.6 * math.sin(math.pi * t) ** 0.8
            nx, ny = -math.sin(a), math.cos(a)
            left.append((px + nx * w, py + ny * w))
            right.append((px - nx * w, py - ny * w))
        leaf.poly(left + right[::-1])
        cv.part(leaf, "#3d5a34" if k % 2 else "#4c6b3c", ow=1.6, shade=0.45, light=0.3, hatch=0.35, depth=2)
        cv.stroke(pts_l, 0.6, "#1c2a18", 0.8)
        for i in range(3, len(pts_l) - 2, 3):
            px, py = pts_l[i]
            nx, ny = -math.sin(a), math.cos(a)
            cv.stroke([(px, py), (px + nx * 3.5 + math.cos(a) * 2, py + ny * 3.5 + math.sin(a) * 2)], 0.5,
                      "#1c2a18", 0.6)
    return finish(cv, "furniture/potted_plant.png")


def rug(name, cw, ch, round_):
    cv = F(name, cw, ch)
    W, H = cv.w, cv.h
    cx, cy = W / 2, H / 2
    rr = cv.rnd
    if round_:
        m = cv.mask().ellipse(cx, cy, W / 2 - 6, H / 2 - 6, n=200, wobble=0.4)
    else:
        m = cv.mask().rect(16, 6, W - 16, H - 6, 3, wobble=0.4)
    field = "#5b2422" if round_ else "#2a3448"
    cv.part(m, fab(cv, field, 0.08, 1.5), ow=2.6, shade=0.15, light=0.1, hatch=0.15, depth=5)
    # small field lattice of lozenges
    xs = np.arange(cv.W)[None, :] / cv.ss
    ys = np.arange(cv.H)[:, None] / cv.ss
    p = 12.0
    lz = (np.abs(((xs - cx) % p) - p / 2) + np.abs(((ys - cy) % p) - p / 2)) < 2.2
    cv.tint(lz * m.arr, mix(field, "#c2a068", 0.25), 0.7)
    # border bands
    def band(off, color, w):
        if round_:
            outer = cv.mask().ellipse(cx, cy, W / 2 - 6 - off, H / 2 - 6 - off, n=200).arr
            inner = cv.mask().ellipse(cx, cy, W / 2 - 6 - off - w, H / 2 - 6 - off - w, n=200).arr
        else:
            outer = cv.mask().rect(16 + off, 6 + off, W - 16 - off, H - 6 - off, 2).arr
            inner = cv.mask().rect(16 + off + w, 6 + off + w, W - 16 - off - w, H - 6 - off - w, 2).arr
        b = np.clip(outer - inner, 0, 1)
        cv.tint(dilate(b, 0.8 * cv.ss), INK, 0.6)
        cv.tint(b, fab(cv, color, 0.12), 1)
        return b
    band(5, "#a8834e", 3)
    b2 = band(10, "#2a1512" if round_ else "#7a2e2a", 12)
    band(24, "#a8834e", 2.5)
    # repeating motif in the wide border
    if round_:
        R = W / 2 - 6 - 16
        for k in range(40):
            a = k * 2 * math.pi / 40
            px, py = cx + math.cos(a) * R, cy + math.sin(a) * R
            cv.tint(cv.mask().ellipse(px, py, 3.6, 2, rot=math.degrees(a) + 90), "#c2a068", 0.9)
    else:
        for x in np.arange(26, W - 22, 12):
            for y in (6 + 16, H - 6 - 16):
                cv.tint(cv.mask().poly([(x, y - 3.5), (x + 3.5, y), (x, y + 3.5), (x - 3.5, y)]), "#c2a068", 0.9)
        for y in np.arange(26, H - 22, 12):
            for x in (16 + 16, W - 16 - 16):
                cv.tint(cv.mask().poly([(x, y - 3.5), (x + 3.5, y), (x, y + 3.5), (x - 3.5, y)]), "#c2a068", 0.9)
    # central medallion
    pts = []
    S = min(W, H) * (0.28 if round_ else 0.3)
    for i in range(240):
        a = 2 * math.pi * i / 240
        rad = S * (0.75 + 0.18 * math.cos(8 * a) + 0.07 * math.cos(16 * a))
        pts.append((cx + rad * math.cos(a) * (1 if round_ else 1.35), cy + rad * math.sin(a)))
    md = cv.mask().poly(pts)
    cv.tint(dilate(md.arr, 1.3 * cv.ss), INK, 0.6)
    cv.tint(md, fab(cv, "#7c3a2c" if round_ else "#5a2a28", 0.12), 1)
    pts2 = [(cx + (x - cx) * 0.6, cy + (y - cy) * 0.6) for x, y in pts]
    md2 = cv.mask().poly(pts2)
    cv.tint(dilate(md2.arr, 1.0 * cv.ss), INK, 0.5)
    cv.tint(md2, fab(cv, "#b08a50", 0.12), 1)
    md3 = cv.mask().circle(cx, cy, S * 0.2)
    cv.tint(md3, fab(cv, "#2a1512", 0.12), 1)
    for k in range(8):
        a = k * math.pi / 4
        cv.tint(cv.mask().ellipse(cx + math.cos(a) * S * 0.33 * (1 if round_ else 1.3), cy + math.sin(a) * S * 0.33,
                                  S * 0.1, S * 0.04, rot=math.degrees(a)), "#2a1512", 0.9)
    # corner spandrels for rect
    if not round_:
        for (sx, sy) in ((40, 30), (W - 40, 30), (40, H - 30), (W - 40, H - 30)):
            q = cv.mask().ellipse(sx, sy, 16, 11)
            cv.tint(dilate(q.arr, 1.0 * cv.ss), INK, 0.5)
            cv.tint(q, fab(cv, "#5a2a28", 0.12), 1)
    # wear
    n = cv.noise(5, 5, 3, seed="wear")
    cv.screen(m.arr * smoothstep(0.75, 0.98, n), 0.18, (170, 150, 130))
    cv.mul(m.arr * smoothstep(0.35, 0.05, n), 0.25)
    cv.hatch(m.arr * smoothstep(0.4, 0.1, n), 30, 3.2, 0.6, 0.25)
    # fringe
    if round_:
        for k in range(150):
            a = k * 2 * math.pi / 150
            r0 = W / 2 - 6
            cv.stroke([(cx + math.cos(a) * r0, cy + math.sin(a) * r0),
                       (cx + math.cos(a) * (r0 + 4), cy + math.sin(a) * (r0 + 4))], 0.7, "#cfc3a0", 0.9)
    else:
        for y in np.arange(9, H - 8, 2.4):
            for (xa, xb) in ((16, 9 + rr.random() * 2), (W - 16, W - 9 - rr.random() * 2)):
                cv.stroke([(xa, y), (xb, y + rr.normal(0, 0.4))], 0.7, "#cfc3a0", 0.9)
    return finish(cv, f"furniture/{name}.png", shadow=(1.5, 2, 2, 0.35))


def rug_round():
    return rug("rug_round", 4, 4, True)


def rug_rect():
    return rug("rug_rect", 5, 3, False)


def cabinet():
    cv = F("cabinet", 2, 1)
    x0, y0, x1, y1 = box(cv)
    # painted (dusty teal) cabinet with marble top
    m = cv.mask().rect(x0, y0, x1, y1 - 2, 3, wobble=0.3)
    cv.part(m, noise_tex(cv.W, cv.H, cv.rnd, "#3e5452", 0.12), ow=3.2, shade=0.45, light=0.25, hatch=0.45, depth=3)
    mt = cv.mask().rect(x0 + 5, y0 + 5, x1 - 5, y1 - 8, 2)
    n = fbm(cv.W, cv.H, 4, 3, rng("cab:marble"), 5)
    veins = smoothstep(0.92, 1.0, 1 - np.abs(np.sin((n * 7) * math.pi)))
    marble = col("#cbc6ba")[None, None, :] * (0.92 + 0.1 * n[..., None]) * (1 - 0.35 * veins[..., None])
    cv.part(mt, marble, ow=1.6, shade=0.3, light=0.25, hatch=0.15, depth=2)
    for (xx, yy) in ((x0 + 3, y0 + 3), (x1 - 3, y0 + 3), (x0 + 3, y1 - 5), (x1 - 3, y1 - 5)):
        cv.part(cv.mask().poly([(xx - 3, yy - 3), (xx + 3, yy - 3), (xx + 3, yy + 3), (xx - 3, yy + 3)]), BRASS,
                ow=1.0, depth=1, hatch=0)
    # small curio objects: bell jar and a skull?  -> a candle and a jar
    cv.part(cv.mask().circle(x0 + 26, y0 + 25, 10), "#9fb7b8", ow=1.4, shade=0.3, light=0.55, hatch=0, depth=2)
    cv.paint(cv.mask().circle(x0 + 26, y0 + 25, 5), "#4a3a2a", 0.8)
    for k in range(5):
        a = k * 1.25
        cv.stroke([(x0 + 26, y0 + 25), (x0 + 26 + math.cos(a) * 6, y0 + 25 + math.sin(a) * 6)], 0.8, "#6a2a20", 0.9)
    cv.stroke(ellipse_pts(x0 + 26, y0 + 25, 7, 7, 20, 0, 200, 260), 1.2, "#ffffff", 0.7)
    book(cv, x1 - 30, y0 + 25, 22, 16, "#2b3d52", rot=8)
    book(cv, x1 - 31, y0 + 24, 18, 13, "#5a2526", rot=-6)
    for xx in ((x0 + x1) / 2 - 5, (x0 + x1) / 2 + 5):
        knob(cv, xx, y1 - 2, 2.0)
    return finish(cv, "furniture/cabinet.png")


def trunk():
    cv = F("trunk", 2, 1)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0 + 2, y0 + 2, x1 - 2, y1 - 2, 6, wobble=0.3)
    cv.part(m, noise_tex(cv.W, cv.H, cv.rnd, "#5a3a26", 0.18), ow=3.4, shade=0.5, light=0.3, hatch=0.5, depth=4,
            soft=0.3)
    # wooden slats
    for xx in (x0 + 30, x1 - 30):
        s = cv.mask().rect(xx - 5, y0 + 2, xx + 5, y1 - 2, 1)
        wood(cv, s, "oak", True, f"sl{xx}", ow=1.8, depth=1.5)
    # iron bands
    for yy in (y0 + 12, y1 - 12):
        b = cv.mask().rect(x0 + 2, yy - 2, x1 - 2, yy + 2, 1)
        cv.part(b, IRON, ow=1.2, shade=0.3, light=0.4, hatch=0, depth=1)
        for xx in np.linspace(x0 + 8, x1 - 8, 9):
            cv.paint(cv.mask().circle(xx, yy, 0.9), "#9a9590")
    # brass corners and lock
    for (xx, yy, sx, sy) in ((x0 + 2, y0 + 2, 1, 1), (x1 - 2, y0 + 2, -1, 1), (x0 + 2, y1 - 2, 1, -1),
                             (x1 - 2, y1 - 2, -1, -1)):
        cv.part(cv.mask().poly([(xx, yy), (xx + 10 * sx, yy), (xx, yy + 10 * sy)]), BRASS, ow=1.2, depth=1, hatch=0)
    lk = cv.mask().rect((x0 + x1) / 2 - 5, y1 - 8, (x0 + x1) / 2 + 5, y1, 1.5)
    cv.part(lk, BRASS, ow=1.4, shade=0.4, light=0.5, hatch=0, depth=1)
    cv.paint(cv.mask().circle((x0 + x1) / 2, y1 - 4, 1.0), INK)
    # leather side handles
    for xx in (x0 - 1, x1 + 1):
        cv.part(cv.mask().rect(xx - 2, (y0 + y1) / 2 - 7, xx + 2, (y0 + y1) / 2 + 7, 1.5), "#2a1c12", ow=1.0,
                depth=1, hatch=0)
    return finish(cv, "furniture/trunk.png")


def side_table():
    cv = F("side_table", 1, 1)
    cx, cy = 28, 28
    m = cv.mask().circle(cx, cy, 24, wobble=0.2)
    wood(cv, m, "mahogany", False, ow=3.2)
    groove(cv, ellipse_pts(cx, cy, 20, 20, 60), 0.8, closed=True)
    d = cv.mask().circle(cx, cy, 15, wobble=0.9)
    cv.part(d, "#d8d0bb", ow=1.0, shade=0.2, light=0, hatch=0, depth=1.5)
    for k in range(16):
        a = k * math.pi / 8
        cv.paint(cv.mask().circle(cx + math.cos(a) * 12, cy + math.sin(a) * 12, 1.4), "#9a927e", 0.8)
    # oil lamp
    cv.part(cv.mask().circle(cx, cy, 8.5), "#7f8f84", ow=1.8, shade=0.3, light=0.55, hatch=0, depth=2)
    cv.part(cv.mask().circle(cx, cy, 5), BRASS, ow=1.2, depth=1.2, hatch=0)
    cv._glows.append((cx, cy, 3.0))
    return finish(cv, "furniture/side_table.png")


def candelabra():
    cv = F("candelabra", 1, 1)
    cx, cy = 28, 28
    cv.part(cv.mask().circle(cx, cy, 11), BRASS, ow=2.4, shade=0.45, light=0.45, hatch=0.3, depth=2.5)
    groove(cv, ellipse_pts(cx, cy, 7.5, 7.5, 30), 0.7, closed=True)
    for k in range(5):
        a = k * 2 * math.pi / 5 - math.pi / 2
        ex, ey = cx + math.cos(a) * 19, cy + math.sin(a) * 19
        cv.stroke(catmull([(cx, cy), (cx + math.cos(a + 0.4) * 10, cy + math.sin(a + 0.4) * 10), (ex, ey)], 8), 3.4, INK)
        cv.stroke(catmull([(cx, cy), (cx + math.cos(a + 0.4) * 10, cy + math.sin(a + 0.4) * 10), (ex, ey)], 8), 1.8,
                  BRASS)
        cv.part(cv.mask().circle(ex, ey, 5.2), BRASS, ow=1.6, shade=0.45, light=0.45, hatch=0, depth=1.2)
        candle(cv, ex, ey, 3.2)
        # wax drips
        cv.paint(cv.mask().ellipse(ex + 2.5, ey + 2.5, 1.2, 0.8), "#e8dfc6", 0.9)
    candle(cv, cx, cy, 3.4)
    return finish(cv, "furniture/candelabra.png")


def floor_lamp():
    cv = F("floor_lamp", 1, 1)
    cx, cy = 28, 28
    # warm glow on floor (under the shade)
    m = cv.mask().ellipse(cx, cy, 22, 22, n=90, wobble=0.5)
    sh = gradient(cv.W, cv.H, "#c89c5c", "#7a5a34", 45)
    cv.part(m, sh, ow=3.0, shade=0.4, light=0.4, hatch=0.35, depth=4)
    # pleats
    for k in range(20):
        a = k * 2 * math.pi / 20
        cv.stroke([(cx + math.cos(a) * 8, cy + math.sin(a) * 8), (cx + math.cos(a) * 21, cy + math.sin(a) * 21)],
                  0.6, "#4a321c", 0.55)
    # fringe
    for k in range(60):
        a = k * 2 * math.pi / 60
        cv.stroke([(cx + math.cos(a) * 22, cy + math.sin(a) * 22), (cx + math.cos(a) * 25, cy + math.sin(a) * 25)],
                  0.7, "#5a3418", 0.9)
    # top opening showing bulb glow
    cv.part(cv.mask().circle(cx, cy, 8), "#f4d48c", ow=1.6, shade=0, light=0, hatch=0)
    cv.paint(cv.mask().circle(cx, cy, 4.5), "#fff4d0")
    cv.paint(cv.mask().circle(cx, cy, 1.8), BRASS)
    cv._glows.append((cx, cy, 2.6))
    cv.grain(0.06)
    cv.drop_shadow(3, 4, 2.5, 0.5)
    g = np.clip(1 - radial(cv.W, cv.H, cx * cv.ss, cy * cv.ss, 30 * cv.ss), 0, 1) ** 2
    cv.glow(g * (1 - m.arr * 0.6), (255, 190, 100), 0.35)
    save(cv.image(), "furniture/floor_lamp.png")


# --------------------------------------------------------------------------
# kitchen & bath
# --------------------------------------------------------------------------
def _counter_base(cv, kind="oak", top="butcher"):
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0, x1, y1 - 2, 2, wobble=0.2)
    if top == "butcher":
        # strips of wood (butcher block) running left-right
        wood(cv, m, kind, False, ow=3.2)
        for yy in np.linspace(y0 + 6, y1 - 8, 6):
            cv.stroke([(x0 + 2, yy), (x1 - 2, yy)], 0.6, INK, 0.55)
    else:
        n = fbm(cv.W, cv.H, 4, 3, rng(cv.name + "marble"), 5)
        veins = smoothstep(0.92, 1.0, 1 - np.abs(np.sin((n * 7) * math.pi)))
        marble = col("#b9b5ac")[None, None, :] * (0.92 + 0.1 * n[..., None]) * (1 - 0.35 * veins[..., None])
        cv.part(m, marble, ow=3.2, shade=0.4, light=0.25, hatch=0.3, depth=3)
    lip = cv.mask().rect(x0 + 2, y1 - 6, x1 - 2, y1, 1.5)
    wood(cv, lip, "walnut", False, "lip", ow=1.8, depth=1.2)
    return x0, y0, x1, y1


def counter():
    cv = F("counter", 2, 1)
    x0, y0, x1, y1 = _counter_base(cv)
    # cutting board, knife, onions, jar
    b = cv.mask().rect(x0 + 12, y0 + 10, x0 + 52, y0 + 38, 4)
    wood(cv, b, "pine", False, "board", ow=1.8, depth=2)
    cv.paint(cv.mask().rect(x0 + 20, y0 + 22, x0 + 44, y0 + 25), "#c9c9c9")
    cv.stroke([(x0 + 20, y0 + 23.5), (x0 + 44, y0 + 23.5)], 0.6, INK, 0.7)
    cv.part(cv.mask().rect(x0 + 44, y0 + 21.5, x0 + 52, y0 + 26, 1), "#3a2316", ow=1.0, depth=1, hatch=0)
    for (cx, cy) in ((x1 - 40, y0 + 20), (x1 - 32, y0 + 30)):
        cv.part(cv.mask().circle(cx, cy, 5.5), "#b49565", ow=1.4, shade=0.45, light=0.35, hatch=0.2, depth=1.5)
        cv.stroke([(cx - 1, cy - 3), (cx + 1, cy + 3)], 0.5, "#6a4a2a", 0.7)
    cv.part(cv.mask().circle(x1 - 16, y0 + 18, 8), "#6f7f78", ow=1.8, shade=0.35, light=0.5, hatch=0, depth=2)
    cv.part(cv.mask().circle(x1 - 16, y0 + 18, 5), "#8a6a40", ow=1.0, depth=1, hatch=0)
    return finish(cv, "furniture/counter.png")


def sink_kitchen():
    cv = F("sink_kitchen", 2, 1)
    x0, y0, x1, y1 = _counter_base(cv, top="marble")
    bx0, by0, bx1, by1 = x0 + 22, y0 + 10, x1 - 22, y1 - 10
    bowl = cv.mask().rect(bx0, by0, bx1, by1, 8)
    cv.part(bowl, PORCELAIN, ow=2.4, shade=0.0, light=0.0, hatch=0)
    inner = cv.mask().rect(bx0 + 4, by0 + 4, bx1 - 4, by1 - 4, 6)
    g = gradient(cv.W, cv.H, "#8e8a82", "#d8d4ca", 45)
    cv.part(inner, g, ow=1.2, shade=0, light=0, hatch=0)
    eb = edge_band(inner.arr, -4 * cv.ss, -4 * cv.ss, 3 * cv.ss)
    cv.mul(eb, 0.45)
    cv.hatch(eb, 45, 2.4, 0.5, 0.4)
    # water
    cv.paint(cv.mask().ellipse((bx0 + bx1) / 2 + 4, (by0 + by1) / 2 + 3, 18, 7), "#55707a", 0.55)
    cv.paint(cv.mask().circle((bx0 + bx1) / 2, (by0 + by1) / 2 + 2, 2.2), "#1c1c1c")
    # faucet
    fx = (bx0 + bx1) / 2
    cv.part(cv.mask().rect(fx - 2.5, y0 + 2, fx + 2.5, by0 + 12, 2), BRASS, ow=1.6, shade=0.4, light=0.5, hatch=0, depth=1)
    for xx in (fx - 10, fx + 10):
        cv.part(cv.mask().circle(xx, y0 + 6, 3.4), BRASS, ow=1.4, depth=1, hatch=0)
        cv.stroke([(xx - 2.5, y0 + 6), (xx + 2.5, y0 + 6)], 0.8, INK)
    # sponge / soap
    cv.part(cv.mask().rect(x1 - 18, y0 + 12, x1 - 8, y0 + 20, 2), "#cfc28f", ow=1.2, depth=1, hatch=0.2)
    return finish(cv, "furniture/sink_kitchen.png")


def stove():
    cv = F("stove", 2, 1)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0, x1, y1 - 2, 3, wobble=0.2)
    it = noise_tex(cv.W, cv.H, cv.rnd, "#2b2b2f", 0.2, 12, 6)
    cv.part(m, it, ow=3.4, shade=0.5, light=0.35, hatch=0.55, depth=3)
    groove_rect(cv, x0 + 4, y0 + 4, x1 - 4, y1 - 6, 0.9, r=1)
    # four burner plates
    for (cx, cy) in ((x0 + 20, y0 + 16), (x0 + 46, y0 + 16), (x0 + 20, y0 + 36), (x0 + 46, y0 + 36)):
        cv.part(cv.mask().circle(cx, cy, 9), "#1b1b1e", ow=1.6, shade=0.3, light=0.4, hatch=0, depth=1.5)
        for rad in (6.5, 3.5):
            cv.stroke(ellipse_pts(cx, cy, rad, rad, 30) + [ellipse_pts(cx, cy, rad, rad, 30)[0]], 0.6, "#5e5e62", 0.8)
        cv.stroke([(cx - 6, cy), (cx + 6, cy)], 0.7, "#5e5e62", 0.8)
    cv.paint(blur(cv.mask().circle(x0 + 46, y0 + 36, 6).arr, 2 * cv.ss), (200, 70, 30), 0.55)
    # kettle
    cv.part(cv.mask().circle(x0 + 20, y0 + 16, 7.5), "#6b6e70", ow=1.8, shade=0.45, light=0.55, hatch=0.2, depth=2)
    cv.part(cv.mask().circle(x0 + 20, y0 + 16, 2.4), "#2a2a2a", ow=0.8, depth=0.5, hatch=0)
    cv.stroke([(x0 + 26, y0 + 13), (x0 + 32, y0 + 10)], 1.8, INK)
    # flue pipe at back right
    cv.part(cv.mask().circle(x1 - 22, y0 + 18, 10), "#222226", ow=2.6, shade=0.5, light=0.45, hatch=0.3, depth=3)
    cv.paint(cv.mask().circle(x1 - 22, y0 + 18, 6), "#0a0a0b")
    # oven door handle (brass rail) at the front
    cv.part(cv.mask().rect(x0 + 10, y1 - 6, x1 - 10, y1 - 2, 2), BRASS, ow=1.4, shade=0.4, light=0.5, hatch=0, depth=1)
    return finish(cv, "furniture/stove.png")


def icebox():
    cv = F("icebox", 1, 1)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0 + 2, y0, x1 - 2, y1 - 2, 3)
    wood(cv, m, "oak", False, ow=3.2)
    groove_rect(cv, x0 + 6, y0 + 4, x1 - 6, y1 - 7, 0.9, r=2)
    for xx in (x0 + 12, x1 - 12):
        cv.part(cv.mask().rect(xx - 4, y0 + 1, xx + 4, y0 + 10, 1.5), BRASS, ow=1.2, depth=1, hatch=0)
    cv.part(cv.mask().rect((x0 + x1) / 2 - 6, y1 - 6, (x0 + x1) / 2 + 6, y1, 1.5), BRASS, ow=1.4, depth=1, hatch=0)
    # a block of ice/ice pick on top
    return finish(cv, "furniture/icebox.png")


def bathtub():
    cv = F("bathtub", 2, 3)
    x0, y0, x1, y1 = box(cv)
    cx = (x0 + x1) / 2
    # claw feet
    for (fx, fy) in ((x0 + 8, y0 + 18), (x1 - 8, y0 + 18), (x0 + 8, y1 - 16), (x1 - 8, y1 - 16)):
        f = cv.mask().ellipse(fx, fy, 6, 5)
        cv.part(f, BRASS, ow=1.6, shade=0.5, light=0.4, hatch=0, depth=1.2)
        for k in (-1, 0, 1):
            cv.stroke([(fx + k * 2.5, fy + 2), (fx + k * 3, fy + 5)], 0.8, INK)
    outer = cv.mask().rect(x0 + 6, y0 + 4, x1 - 6, y1 - 2, 30, wobble=0.3)
    cv.part(outer, noise_tex(cv.W, cv.H, cv.rnd, "#d6d2c6", 0.06), ow=3.4, shade=0.4, light=0.35, hatch=0.4, depth=4)
    inner = cv.mask().rect(x0 + 14, y0 + 14, x1 - 14, y1 - 10, 24)
    g = gradient(cv.W, cv.H, "#7f7c75", "#d0ccc2", 50)
    cv.part(inner, g, ow=1.4, shade=0, light=0, hatch=0)
    eb = edge_band(inner.arr, -5 * cv.ss, -5 * cv.ss, 4 * cv.ss)
    cv.mul(eb, 0.4)
    cv.hatch(eb, 45, 2.6, 0.5, 0.45)
    # murky water
    w = cv.mask().rect(x0 + 18, y0 + 40, x1 - 18, y1 - 14, 20, wobble=0.5)
    cv.paint(w, gradient(cv.W, cv.H, "#4c6366", "#2b3a3e", 70), 0.7)
    for k in range(4):
        yy = y0 + 60 + k * 26
        cv.stroke(catmull([(cx - 18, yy), (cx - 6, yy - 2), (cx + 6, yy + 1), (cx + 18, yy - 1)], 6), 0.6,
                  "#aac0c0", 0.4)
    # faucet & drain at head end (top)
    cv.part(cv.mask().rect(cx - 3, y0 + 4, cx + 3, y0 + 22, 2), BRASS, ow=1.6, shade=0.4, light=0.5, hatch=0, depth=1)
    for xx in (cx - 11, cx + 11):
        cv.part(cv.mask().circle(xx, y0 + 9, 3.6), BRASS, ow=1.4, depth=1, hatch=0)
        cv.stroke([(xx - 2.5, y0 + 9), (xx + 2.5, y0 + 9)], 0.8, INK)
    cv.part(cv.mask().circle(cx, y0 + 28, 2.4), "#3a3a3a", ow=0.8, depth=0.5, hatch=0)
    # soap dish on rim
    return finish(cv, "furniture/bathtub.png")


def toilet():
    cv = F("toilet", 1, 1)
    x0, y0, x1, y1 = box(cv)
    cx = (x0 + x1) / 2
    # wooden cistern at back
    tk = cv.mask().rect(x0 + 3, y0, x1 - 3, y0 + 15, 3)
    wood(cv, tk, "walnut", False, ow=2.8, depth=2.5)
    cv.part(cv.mask().rect(cx + 6, y0 + 4, cx + 14, y0 + 8, 1), BRASS, ow=1.0, depth=1, hatch=0)
    # bowl
    b = cv.mask().ellipse(cx, y0 + 33, 18, 20)
    cv.part(b, PORCELAIN, ow=3.0, shade=0.4, light=0.35, hatch=0.35, depth=3)
    # wooden seat ring
    seat = cv.mask().ellipse(cx, y0 + 34, 15.5, 17.5)
    wood(cv, seat, "mahogany", False, "seat", ow=1.4, depth=2)
    inner = cv.mask().ellipse(cx, y0 + 35, 9.5, 11.5)
    cv.part(inner, gradient(cv.W, cv.H, "#6f6c66", "#cfcbc0", 50), ow=1.2, shade=0, light=0, hatch=0)
    cv.paint(cv.mask().ellipse(cx + 1, y0 + 37, 4.5, 5), "#506468", 0.7)
    return finish(cv, "furniture/toilet.png")


def washbasin():
    cv = F("washbasin", 1, 1)
    x0, y0, x1, y1 = box(cv)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2 + 2
    m = cv.mask().rect(x0 + 1, y0 + 1, x1 - 1, y1 - 1, 4)
    wood(cv, m, "walnut", False, ow=3.0)
    cv.part(cv.mask().circle(cx - 2, cy + 2, 17), PORCELAIN, ow=2.4, shade=0.35, light=0.4, hatch=0.3, depth=2.5)
    inner = cv.mask().circle(cx - 2, cy + 2, 12.5)
    cv.part(inner, gradient(cv.W, cv.H, "#8a8780", "#d6d2c8", 45), ow=1.0, shade=0, light=0, hatch=0)
    cv.paint(cv.mask().circle(cx - 1, cy + 3, 9), "#6a8286", 0.45)
    cv.stroke(ellipse_pts(cx - 2, cy + 2, 14.5, 14.5, 40) + [ellipse_pts(cx - 2, cy + 2, 14.5, 14.5, 40)[0]],
              0.6, "#5d7aa0", 0.8)
    # pitcher
    cv.part(cv.mask().circle(x1 - 10, y0 + 10, 7.5), PORCELAIN, ow=1.8, shade=0.4, light=0.4, hatch=0.2, depth=1.6)
    cv.paint(cv.mask().circle(x1 - 10, y0 + 10, 4.2), "#7a8a8e")
    cv.stroke([(x1 - 17, y0 + 7), (x1 - 21, y0 + 5)], 1.6, INK)
    return finish(cv, "furniture/washbasin.png")


# --------------------------------------------------------------------------
# workshop / barn / outdoors
# --------------------------------------------------------------------------
def crate(cv, x0, y0, x1, y1, seed, stencil=True):
    m = cv.mask().rect(x0, y0, x1, y1, 2, wobble=0.3)
    wood(cv, m, "pine", False, seed, ow=3.0, depth=2.5)
    n = 4
    for k in range(1, n):
        yy = y0 + (y1 - y0) * k / n
        cv.stroke([(x0 + 1, yy), (x1 - 1, yy)], 0.9, INK, 0.85)
    # frame battens
    for (bx0, bx1) in ((x0, x0 + 7), (x1 - 7, x1)):
        b = cv.mask().rect(bx0, y0, bx1, y1, 1)
        wood(cv, b, "pine", True, seed + "b", ow=1.6, depth=1.2)
    for (bx, by) in ((x0 + 3.5, y0 + 4), (x1 - 3.5, y0 + 4), (x0 + 3.5, y1 - 4), (x1 - 3.5, y1 - 4)):
        cv.paint(cv.mask().circle(bx, by, 1.0), "#1a1a1a")
    if stencil:
        f = cv.mask().text(((x0 + x1) / 2, (y0 + y1) / 2), "XXX" if "a" in seed else "No.7",
                           __import__("core").font("IMFellEnglishSC-Regular.ttf", 22 * cv.ss // 2), anchor="mm")
        cv.tint(f, "#2a1a10", 0.55)


def crates():
    cv = F("crates", 2, 2)
    crate(cv, 4, 4, 70, 68, "a")
    crate(cv, 64, 30, 118, 84, "b")
    crate(cv, 12, 72, 60, 118, "c", stencil=False)
    # small one on top
    crate(cv, 76, 6, 116, 34, "d", stencil=False)
    # straw tufts
    rr = cv.rnd
    for _ in range(18):
        x, y = 60 + rr.normal(0, 12), 70 + rr.normal(0, 12)
        a = rr.random() * math.pi
        cv.stroke([(x, y), (x + math.cos(a) * 7, y + math.sin(a) * 7)], 0.8, "#b39a5c", 0.9)
    return finish(cv, "furniture/crates.png")


def barrel():
    cv = F("barrel", 1, 1)
    cx, cy = 28, 28
    m = cv.mask().circle(cx, cy, 24, wobble=0.3)
    cv.part(m, IRON, ow=3.2, shade=0.4, light=0.4, hatch=0.3, depth=3)
    lid = cv.mask().circle(cx, cy, 20.5)
    wood(cv, lid, "oak", True, "lid", ow=1.4, depth=3)
    for k in range(-3, 4):
        xx = cx + k * 5.5
        h = math.sqrt(max(0, 20 ** 2 - (xx - cx) ** 2))
        cv.stroke([(xx, cy - h), (xx, cy + h)], 0.8, INK, 0.85)
    # staves ring (ends visible between hoop & lid)
    for k in range(24):
        a = k * 2 * math.pi / 24
        cv.stroke([(cx + math.cos(a) * 20.5, cy + math.sin(a) * 20.5), (cx + math.cos(a) * 23.5, cy + math.sin(a) * 23.5)],
                  0.6, "#888", 0.6)
    cv.part(cv.mask().circle(cx + 8, cy - 6, 2.5), "#2a1a10", ow=1.0, depth=0.8, hatch=0)
    return finish(cv, "furniture/barrel.png")


def workbench():
    cv = F("workbench", 3, 1)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0, x1, y1, 2, wobble=0.3)
    wood(cv, m, "pine", False, ow=3.4)
    for yy in (y0 + 18, y0 + 36):
        cv.stroke([(x0 + 2, yy), (x1 - 2, yy)], 0.9, INK, 0.8)
    # stains, gouges
    n = cv.noise(6, 3, 3, seed="st")
    cv.mul(m.arr * smoothstep(0.7, 0.95, n), 0.4, (40, 25, 15))
    # vise
    v = cv.mask().rect(x0 + 4, y1 - 14, x0 + 30, y1 + 2, 2)
    cv.part(v, IRON, ow=2.0, shade=0.4, light=0.4, hatch=0.3, depth=2)
    cv.stroke([(x0 + 17, y1 - 4), (x0 + 17, y1 + 4)], 2.0, "#8a8a8a")
    # hammer
    cv.part(cv.mask().rect(x0 + 50, y0 + 12, x0 + 80, y0 + 16, 1.5), wtex(cv, "oak", seed="hm"), ow=1.4, depth=1, hatch=0)
    cv.part(cv.mask().rect(x0 + 76, y0 + 6, x0 + 84, y0 + 22, 1.5), IRON, ow=1.4, shade=0.4, light=0.5, hatch=0,
            depth=1)
    # saw
    saw = cv.mask().poly([(x0 + 100, y0 + 28), (x0 + 150, y0 + 22), (x0 + 150, y0 + 32), (x0 + 100, y0 + 38)])
    cv.part(saw, "#9a9a9e", ow=1.4, shade=0.3, light=0.5, hatch=0, depth=1)
    for k in range(18):
        xx = x0 + 100 + k * 2.8
        yy = y0 + 38 - k * 0.33
        cv.stroke([(xx, yy), (xx + 1.4, yy + 1.6)], 0.5, INK)
    cv.part(cv.mask().rect(x0 + 86, y0 + 26, x0 + 102, y0 + 40, 3), wtex(cv, "walnut", seed="sh"), ow=1.4, depth=1)
    cv.paint(cv.mask().ellipse(x0 + 94, y0 + 33, 4, 2.5), "#120c08")
    # chisels and nails
    for k in range(3):
        xx = x1 - 36 + k * 8
        cv.part(cv.mask().rect(xx, y0 + 8, xx + 3.5, y0 + 22, 1), wtex(cv, "walnut", seed=f"c{k}"), ow=1.0, depth=1, hatch=0)
        cv.part(cv.mask().rect(xx + 0.5, y0 + 22, xx + 3, y0 + 32, 0.5), "#a0a0a4", ow=0.8, depth=0.6, hatch=0)
    rr = cv.rnd
    for _ in range(14):
        x, y = x0 + 120 + rr.random() * 30, y0 + 8 + rr.random() * 10
        a = rr.random() * math.pi
        cv.stroke([(x, y), (x + math.cos(a) * 5, y + math.sin(a) * 5)], 0.9, "#4a4a50")
    # shavings
    for _ in range(14):
        x, y = x0 + 40 + rr.random() * 60, y0 + 40 + rr.random() * 10
        cv.stroke(ellipse_pts(x, y, 3, 2, 12, rr.random() * 180, 0, 260), 0.7, "#c8a870", 0.9)
    return finish(cv, "furniture/workbench.png")


def woodpile():
    cv = F("woodpile", 2, 1)
    rr = cv.rnd
    rows = [(8, 4), (22, 4), (36, 4), (15, 3), (29, 3)]
    for i, (yy, n) in enumerate(rows):
        for k in range(n):
            x0 = 4 + k * 3 + rr.normal(0, 2)
            x1 = 114 - (n - 1 - k) * 3 + rr.normal(0, 2)
            ry = 7 + rr.random() * 2
            m = cv.mask().rect(x0, yy - ry / 2 + k * 0.2, x1, yy + ry / 2, ry / 2, wobble=0.6)
            bark = noise_tex(cv.W, cv.H, rng(f"wp{i}{k}"), "#4b3a2c", 0.3, 40, 6, 3)
            cv.part(m, bark, ow=1.8, shade=0.5, light=0.25, hatch=0.4, depth=2)
            if rr.random() < 0.5:
                # split face showing pale wood
                sf = cv.mask().rect(x0 + 4, yy - ry * 0.15, x1 - 4, yy + ry * 0.3, 1.5)
                cv.part(sf, wtex(cv, "pine", seed=f"sf{i}{k}"), ow=0.8, shade=0.2, light=0, hatch=0, depth=1)
            # cut end rings
            for ex in (x0 + 2, x1 - 2):
                e = cv.mask().ellipse(ex, yy, 2.5, ry / 2 - 0.3)
                cv.part(e, "#b8945e", ow=1.0, shade=0.2, light=0, hatch=0, depth=0.6)
            break_ = None
        _ = break_
    # bark crumbs
    for _ in range(30):
        x, y = rr.random() * 118, 44 + rr.random() * 8
        cv.paint(cv.mask().circle(x, y, 0.8 + rr.random()), "#3a2a1c")
    return finish(cv, "furniture/woodpile.png")


def hay():
    cv = F("hay", 2, 2)
    x0, y0, x1, y1 = box(cv)
    rr = cv.rnd
    # loose straw
    for _ in range(140):
        x, y = rr.uniform(x0, x1), rr.uniform(y0, y1)
        a = rr.random() * math.pi
        ln = 4 + rr.random() * 8
        cv.stroke([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], 0.8, "#a68a4e", 0.9)
    m = cv.mask().rect(x0 + 8, y0 + 8, x1 - 8, y1 - 8, 8, wobble=1.4)
    base = noise_tex(cv.W, cv.H, rr, "#8f7442", 0.3, 6, 40, 4)
    cv.part(m, base, ow=3.0, shade=0.6, light=0.3, hatch=0.7, depth=8, soft=0.5)
    # flake bands (a bale is made of compressed slabs)
    for yy in np.linspace(y0 + 20, y1 - 20, 6):
        cv.stroke(catmull([(x0 + 10, yy), (x0 + 40, yy + 2), (x1 - 40, yy - 2), (x1 - 10, yy)], 8), 1.0, INK, 0.55)
    # straw strands texture
    for _ in range(700):
        x, y = rr.uniform(x0 + 10, x1 - 10), rr.uniform(y0 + 10, y1 - 10)
        a = rr.normal(math.pi / 2, 0.35)
        ln = 3 + rr.random() * 7
        c = mix("#6e5a32", "#d6bc78", rr.random())
        cv.stroke([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], 0.6, c, 0.9)
    # twine
    for xx in (x0 + 34, x1 - 34):
        cv.stroke([(xx, y0 + 8), (xx + 1, y1 - 8)], 2.2, INK, 0.8)
        cv.stroke([(xx, y0 + 8), (xx + 1, y1 - 8)], 1.2, "#7a6040", 1)
    # pitchfork leaning on it
    cv.stroke([(x0 + 14, y1 - 6), (x1 - 30, y0 + 30)], 3.0, INK)
    cv.stroke([(x0 + 14, y1 - 6), (x1 - 30, y0 + 30)], 1.6, "#8a6a40")
    for k in (-1, 0, 1):
        cv.stroke([(x1 - 30, y0 + 30), (x1 - 22 + k * 3, y0 + 16 + k * 3)], 1.0, "#8a8a8e")
    return finish(cv, "furniture/hay.png")


def wash_tub():
    cv = F("wash_tub", 2, 2)
    cx, cy = 58, 58
    m = cv.mask().circle(cx, cy, 50, wobble=0.4)
    wood(cv, m, "oak", True, ow=3.4, depth=4)
    for k in range(32):
        a = k * 2 * math.pi / 32
        cv.stroke([(cx + math.cos(a) * 42, cy + math.sin(a) * 42), (cx + math.cos(a) * 50, cy + math.sin(a) * 50)],
                  0.7, INK, 0.7)
    for rad in (49, 44):
        cv.stroke(ellipse_pts(cx, cy, rad, rad, 120) + [ellipse_pts(cx, cy, rad, rad, 120)[0]], 2.0, IRON, 1)
    inner = cv.mask().circle(cx, cy, 41)
    cv.part(inner, gradient(cv.W, cv.H, "#2f3e40", "#58706f", 60), ow=1.6, shade=0, light=0, hatch=0)
    eb = edge_band(inner.arr, -6 * cv.ss, -6 * cv.ss, 5 * cv.ss)
    cv.mul(eb, 0.5)
    rr = cv.rnd
    # suds
    for _ in range(40):
        a = rr.random() * 2 * math.pi
        rad = rr.random() ** 0.5 * 34
        x, y = cx + math.cos(a) * rad, cy + math.sin(a) * rad
        s = 1.5 + rr.random() * 3.5
        cv.part(cv.mask().circle(x, y, s), "#c9d0cc", ow=0.6, shade=0.2, light=0.4, hatch=0, depth=0.6)
    # washboard across
    wb = cv.mask().rect(cx - 6, cy - 36, cx + 22, cy + 30, 3)
    wood(cv, wb, "pine", False, "wb", ow=2.0, depth=2)
    for yy in np.arange(cy - 26, cy + 20, 3.2):
        cv.stroke([(cx - 2, yy), (cx + 18, yy)], 0.8, "#8f8f94", 0.9)
    # side handles
    for sx in (-1, 1):
        cv.part(cv.mask().rect(cx + sx * 52 - 4, cy - 8, cx + sx * 52 + 4, cy + 8, 2), wtex(cv, "oak", seed="h"),
                ow=1.6, depth=1.2)
    return finish(cv, "furniture/wash_tub.png")


def tree():
    cv = F("tree", 3, 3)
    rr = cv.rnd
    cx, cy = 90, 90

    def blob(x, y, r, color, light=0.3, hatch=0.55):
        m = cv.mask().ellipse(x, y, r, r * (0.85 + 0.3 * rr.random()), wobble=r * 0.12, n=90, rot=rr.random() * 180)
        cv.part(m, noise_tex(cv.W, cv.H, rng(f"tree{x:.0f}{y:.0f}"), color, 0.25, 30, 30, 3), ow=2.4, shade=0.55,
                light=light, hatch=hatch, depth=5)
        for k in range(int(r * 0.8)):
            a = rr.random() * 2 * math.pi
            d = r * (0.3 + 0.6 * rr.random())
            px, py = x + math.cos(a) * d, y + math.sin(a) * d
            cv.stroke(ellipse_pts(px, py, 2.8, 2.0, 10, rr.random() * 360, 200, 340), 0.6, INK, 0.45)
        return m
    # outer mass: irregular ring of clumps
    base = cv.mask()
    for k in range(13):
        a = k * 2 * math.pi / 13 + rr.normal(0, 0.15)
        d = 58 + rr.normal(0, 6)
        base.ellipse(cx + math.cos(a) * d, cy + math.sin(a) * d, 26 + rr.random() * 6, 24 + rr.random() * 6, wobble=2)
    base.circle(cx, cy, 66)
    cv.part(base, noise_tex(cv.W, cv.H, rng("treebase"), "#1c281b", 0.25, 30, 30, 3), ow=3.2, shade=0.6, light=0.1,
            hatch=0.6, depth=8)
    pts = [(cx + rr.normal(0, 40), cy + rr.normal(0, 40)) for _ in range(14)]
    pts = [p for p in pts if math.hypot(p[0] - cx, p[1] - cy) < 62]
    pts.sort(key=lambda p: (p[0] + p[1]), reverse=True)
    for (x, y) in pts:
        blob(x, y, 18 + rr.random() * 10, "#2a3c2a", 0.22)
    for k in range(7):
        x, y = cx - 14 + rr.normal(0, 22), cy - 14 + rr.normal(0, 22)
        blob(x, y, 12 + rr.random() * 7, "#3a5236", 0.32, 0.4)
    for _ in range(70):
        a = rr.random() * 2 * math.pi
        rad = rr.random() * 55
        x, y = cx - 16 + math.cos(a) * rad, cy - 16 + math.sin(a) * rad
        cv.tint(cv.mask().ellipse(x, y, 2.4, 1.5, rot=rr.random() * 180), "#6f8458",
                0.6 * float(cv.a[int(y * 2), int(x * 2)] > 0.5))
    return finish(cv, "furniture/tree.png", shadow=(6, 8, 5, 0.6))


def hedge():
    cv = F("hedge", 2, 1)
    x0, y0, x1, y1 = box(cv)
    rr = cv.rnd
    m = cv.mask().rect(x0 + 1, y0 + 1, x1 - 1, y1 - 1, 10, wobble=2.2)
    cv.part(m, noise_tex(cv.W, cv.H, rr, "#283a26", 0.3, 20, 10, 3), ow=3.0, shade=0.55, light=0.3, hatch=0.55,
            depth=5)
    for _ in range(90):
        x, y = rr.uniform(x0 + 5, x1 - 5), rr.uniform(y0 + 5, y1 - 6)
        a = rr.random() * 360
        cv.part(cv.mask().ellipse(x, y, 3.2, 2, rot=a), "#3f5a3a" if rr.random() < 0.6 else "#52703f", ow=0.9,
                shade=0.3, light=0.3, hatch=0, depth=0.8)
    return finish(cv, "furniture/hedge.png", shadow=(4, 5, 3, 0.55))


def gravestone():
    cv = F("gravestone", 1, 1)
    x0, y0, x1, y1 = box(cv)
    # weathered slab with a rounded head, lying flat-ish
    pts = [(x0 + 8, y1 - 2), (x0 + 8, y0 + 18)] + catmull([(x0 + 8, y0 + 18), ((x0 + x1) / 2, y0 + 1),
                                                           (x1 - 8, y0 + 18)], 12) + [(x1 - 8, y1 - 2)]
    m = cv.mask().poly(pts, wobble=0.6)
    cv.part(m, stone_tex(cv, "#6d6c68"), ow=3.2, shade=0.5, light=0.35, hatch=0.5, depth=4)
    cx = (x0 + x1) / 2
    groove(cv, [(cx, y0 + 12), (cx, y0 + 36)], 1.4)
    groove(cv, [(cx - 8, y0 + 20), (cx + 8, y0 + 20)], 1.4)
    for yy in (y0 + 42, y0 + 47):
        groove(cv, [(cx - 9, yy), (cx + 9, yy)], 0.7)
    # moss & cracks
    n = cv.noise(5, 5, 3, seed="moss")
    cv.tint(m.arr * smoothstep(0.62, 0.85, n), "#4a5a34", 0.65)
    cv.stroke([(x1 - 10, y0 + 24), (x1 - 15, y0 + 30), (x1 - 13, y0 + 38)], 0.7, INK, 0.8)
    return finish(cv, "furniture/gravestone.png")


def coffin():
    cv = F("coffin", 2, 4)
    x0, y0, x1, y1 = box(cv)
    cx = (x0 + x1) / 2
    W_ = x1 - x0
    pts = [(cx - W_ * 0.3, y0 + 2), (cx + W_ * 0.3, y0 + 2), (x1 - 4, y0 + 62), (cx + W_ * 0.28, y1 - 2),
           (cx - W_ * 0.28, y1 - 2), (x0 + 4, y0 + 62)]
    m = cv.mask().poly(pts, wobble=0.3)
    wood(cv, m, "ebony", True, ow=3.6, depth=5)
    inner = [(cx + (x - cx) * 0.8, y0 + (y - y0) * 0.93 + 8) for x, y in pts]
    groove(cv, inner, 1.0, closed=True)
    # brass handles along sides
    for yy in (y0 + 80, y0 + 130, y0 + 180):
        for sx in (-1, 1):
            xe = cx + sx * (W_ * 0.5 - 4 - abs(yy - (y0 + 62)) * 0.035)
            cv.part(cv.mask().rect(xe - 2.5, yy - 8, xe + 2.5, yy + 8, 2), BRASS, ow=1.4, shade=0.4, light=0.5, hatch=0,
                    depth=1)
    # cross on lid
    c = cv.mask().rect(cx - 3, y0 + 40, cx + 3, y0 + 120, 1)
    c.rect(cx - 16, y0 + 58, cx + 16, y0 + 64, 1)
    cv.part(c, "#8a7344", ow=1.6, shade=0.4, light=0.5, hatch=0.2, depth=1.5)
    # dust
    n = cv.noise(4, 6, 3, seed="dust")
    cv.screen(m.arr * smoothstep(0.6, 0.95, n), 0.18, (190, 180, 160))
    return finish(cv, "furniture/coffin.png")


def pew():
    cv = F("pew", 4, 1)
    x0, y0, x1, y1 = box(cv)
    # back rail
    back = cv.mask().rect(x0 + 6, y0, x1 - 6, y0 + 14, 3)
    wood(cv, back, "oak", False, "back", ow=3.0, depth=2.5)
    seat = cv.mask().rect(x0 + 6, y0 + 12, x1 - 6, y1, 3)
    wood(cv, seat, "oak", False, "seat", ow=3.0)
    for yy in (y0 + 24, y0 + 36):
        cv.stroke([(x0 + 8, yy), (x1 - 8, yy)], 0.8, INK, 0.75)
    groove(cv, [(x0 + 10, y0 + 7), (x1 - 10, y0 + 7)], 0.8)
    # carved ends
    for (ex0, ex1) in ((x0, x0 + 10), (x1 - 10, x1)):
        e = cv.mask().rect(ex0, y0 - 1, ex1, y1 + 1, 4)
        wood(cv, e, "oak", True, f"end{ex0}", ow=2.6, depth=2)
        cv.part(cv.mask().circle((ex0 + ex1) / 2, y0 + 5, 4.2), wtex(cv, "oak", seed="fin"), ow=1.6, depth=1.5)
    book(cv, x0 + 70, y0 + 30, 16, 12, "#3a1e1e", rot=6)
    book(cv, x1 - 80, y0 + 32, 16, 12, "#1e2a3a", rot=-10)
    return finish(cv, "furniture/pew.png")


def altar():
    cv = F("altar", 3, 2)
    x0, y0, x1, y1 = box(cv)
    m = cv.mask().rect(x0, y0, x1, y1, 3, wobble=0.4)
    cv.part(m, stone_tex(cv, "#77736b"), ow=3.6, shade=0.5, light=0.3, hatch=0.5, depth=4)
    groove_rect(cv, x0 + 5, y0 + 5, x1 - 5, y1 - 5, 1.0)
    # altar cloth: white with crimson runner and gold trim, hanging over the front edge
    cl = cv.mask().rect(x0 + 18, y0 + 8, x1 - 18, y1 + 1, 2, wobble=0.5)
    cv.part(cl, fab(cv, "#d8d0bc"), ow=2.0, shade=0.3, light=0.2, hatch=0.25, depth=3)
    rn = cv.mask().rect((x0 + x1) / 2 - 16, y0 + 8, (x0 + x1) / 2 + 16, y1 + 1, 1)
    cv.part(rn, fab(cv, "#6a1e22"), ow=1.4, shade=0.35, light=0.15, hatch=0.25, depth=2)
    for xx in ((x0 + x1) / 2 - 13, (x0 + x1) / 2 + 13):
        cv.stroke([(xx, y0 + 9), (xx, y1)], 1.0, "#b0904e")
    for k in range(10):
        xx = (x0 + x1) / 2 - 12 + k * 2.7
        cv.stroke([(xx, y1 - 1), (xx, y1 + 2)], 0.8, "#b0904e")
    # crucifix laid / standing cross base, book, chalice, candles
    cx, cy = (x0 + x1) / 2, y0 + 30
    cr = cv.mask().rect(cx - 3, cy - 18, cx + 3, cy + 14, 1)
    cr.rect(cx - 12, cy - 9, cx + 12, cy - 3, 1)
    cv.part(cr, BRASS, ow=1.8, shade=0.45, light=0.55, hatch=0.2, depth=1.5)
    book(cv, cx, cy + 32, 26, 18, "#2a1a1a", rot=0)
    cv.part(cv.mask().circle(cx - 46, cy + 10, 7), BRASS, ow=1.8, shade=0.4, light=0.55, hatch=0, depth=1.5)
    cv.paint(cv.mask().circle(cx - 46, cy + 10, 4), "#4a1016")
    for xx in (x0 + 14, x1 - 14):
        for yy in (y0 + 16, y1 - 18):
            cv.part(cv.mask().circle(xx, yy, 6.5), BRASS, ow=1.6, shade=0.45, light=0.45, hatch=0, depth=1.2)
            candle(cv, xx, yy, 3.4)
    return finish(cv, "furniture/altar.png")


ALL = [bed_double, bed_single, wardrobe, dresser, nightstand, desk, chair, armchair, sofa, coffee_table,
       dining_table, bookshelf, fireplace, stove, counter, sink_kitchen, icebox, bathtub, toilet, washbasin,
       piano, grandfather_clock, potted_plant, rug_round, rug_rect, crates, barrel, workbench, woodpile,
       candelabra, floor_lamp, wall_mirror, cabinet, trunk, side_table, pew, altar, tree, hedge, gravestone,
       coffin, hay, wash_tub]


def build_all(only=None):
    for f in ALL:
        if only and f.__name__ not in only:
            continue
        f()


if __name__ == "__main__":
    import sys
    build_all(sys.argv[1:] or None)
