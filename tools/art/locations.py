"""Revision 6: furniture for the coaching inn and the harbour.

Same kit as furniture.py / neglect.py (footprint x 64 px, front faces +Y, inked,
hatched, grain, soft baked drop shadow). The water tile is seamless and opaque
so that a basin of 2x2 tiles reads as one dark surface.
"""
from __future__ import annotations

import math

import numpy as np

from core import (Canvas, INK, blur, catmull, col, ellipse_pts, fbm, mix, noise_tex, pnoise, radial, rng, save,
                  smoothstep)
from furniture import BRASS, IRON, F, box, finish, groove, knob, wood, wtex
from neglect import dust, rust

C = 64
PEWTER = "#8a8d90"
ROPE = "#9a8358"


# --------------------------------------------------------------------------
# inn
# --------------------------------------------------------------------------
def bar_counter():
    cv = F("bar_counter", 4, 1)
    x0, y0, x1, y1 = box(cv)
    rr = cv.rnd
    top = cv.mask().rect(x0, y0, x1, y1, 3, wobble=0.25)
    wood(cv, top, "mahogany", False, ow=3.4, depth=4)
    # inlaid border and the worn, polished middle
    groove(cv, [(x0 + 5, y0 + 6), (x1 - 5, y0 + 6)], 0.8, 0.6)
    sheen = cv.mask().rect(x0 + 20, y0 + 14, x1 - 20, y1 - 14, 8)
    cv.screen(blur(sheen.arr, 6 * cv.ss), 0.12)
    # brass foot/hand rail along the customer's (front) side
    cv.stroke([(x0 + 4, y1 - 4), (x1 - 4, y1 - 4)], 3.2, INK, 0.9)
    cv.stroke([(x0 + 4, y1 - 4.6), (x1 - 4, y1 - 4.6)], 1.6, BRASS, 1.0)
    for k in range(5):
        knob(cv, x0 + 10 + k * (x1 - x0 - 20) / 4, y1 - 4, 1.8)
    # beer engine: a row of pump handles at the back
    for k in range(3):
        px = x0 + 60 + k * 26
        cv.part(cv.mask().rect(px - 6, y0 + 8, px + 6, y0 + 20, 2), BRASS, ow=1.4, shade=0.4, light=0.5, hatch=0, depth=1.2)
        h = cv.mask().ellipse(px, y0 + 26, 3.4, 9)
        cv.part(h, "#e0d6bc", ow=1.2, shade=0.35, light=0.4, hatch=0, depth=1.0)
        cv.paint(cv.mask().ellipse(px, y0 + 32, 2.6, 2.0), "#5a1a14")
    # pewter tankards, a glass, wet rings
    for k in range(9):
        x = rr.uniform(x0 + 150, x1 - 14)
        y = rr.uniform(y0 + 14, y1 - 14)
        cv.stroke(ellipse_pts(x, y, 6, 6, 40) + [ellipse_pts(x, y, 6, 6, 40)[0]], 0.7, "#2a120c", 0.45)
    for (tx, ty) in ((x0 + 170, y0 + 30), (x0 + 196, y0 + 22), (x1 - 34, y0 + 28)):
        m = cv.mask().circle(tx, ty, 7)
        cv.part(m, PEWTER, ow=1.6, shade=0.45, light=0.45, hatch=0.2, depth=1.6)
        cv.paint(cv.mask().circle(tx, ty, 5), "#3a2410")
        cv.paint(cv.mask().circle(tx - 1, ty - 1, 3.6), "#d8c8a0", 0.5)   # froth
        cv.part(cv.mask().rect(tx + 6, ty - 2, tx + 11, ty + 2, 1), PEWTER, ow=1.0, depth=0.6, hatch=0)
    # a ledger and a candle stub at the far end
    lm = cv.mask().rect(x1 - 70, y0 + 12, x1 - 50, y0 + 38, 1)
    cv.part(lm, "#3c2a20", ow=1.2, shade=0.3, light=0.2, hatch=0.2, depth=1.2)
    cv.paint(cv.mask().rect(x1 - 68, y0 + 14, x1 - 52, y0 + 36, 1), "#cdbf9c", 0.25)
    return finish(cv, "furniture/bar_counter.png")


def keg(cv, x0, y0, x1, y1, seed):
    """a cask lying on its side, seen from above (bulging middle, hoops across)."""
    cx = (x0 + x1) / 2
    pts = []
    for k in range(25):
        t = k / 24
        y = y0 + (y1 - y0) * t
        bulge = math.sin(t * math.pi) * 5
        pts.append((x0 + 5 - bulge, y))
    for k in range(25):
        t = 1 - k / 24
        y = y0 + (y1 - y0) * t
        bulge = math.sin(t * math.pi) * 5
        pts.append((x1 - 5 + bulge, y))
    m = cv.mask().poly(pts)
    cv.part(m, wtex(cv, "oak", True, seed), ow=2.4, shade=0.5, light=0.3, hatch=0.4, depth=5, soft=0.4)
    for k in range(1, 6):
        xx = x0 + (x1 - x0) * k / 6
        cv.stroke([(xx, y0 + 2), (xx, y1 - 2)], 0.6, INK, 0.55)
    for t in (0.12, 0.3, 0.7, 0.88):
        y = y0 + (y1 - y0) * t
        b = math.sin(t * math.pi) * 5
        cv.stroke([(x0 + 4 - b, y), (x1 - 4 + b, y)], 2.4, INK, 0.9)
        cv.stroke([(x0 + 4 - b, y - 0.6), (x1 - 4 + b, y - 0.6)], 1.2, IRON, 1.0)
    rust(cv, m, 0.25, seed, 4, 4)
    # bung on top and a brass tap at the front head
    cv.part(cv.mask().circle(cx, (y0 + y1) / 2, 3), "#2a1a10", ow=1.0, depth=0.8, hatch=0)
    cv.part(cv.mask().rect(cx - 2.5, y1 - 3, cx + 2.5, y1 + 4, 1), BRASS, ow=1.0, depth=0.8, hatch=0)


def keg_rack():
    cv = F("keg_rack", 3, 1)
    x0, y0, x1, y1 = box(cv)
    # stillage: two heavy beams the casks rest on
    for yy in (y0 + 10, y1 - 12):
        b = cv.mask().rect(x0, yy - 4, x1, yy + 4, 1)
        wood(cv, b, "walnut", False, f"beam{yy}", ow=2.4, depth=2)
    span = (x1 - x0) / 3
    for k in range(3):
        keg(cv, x0 + span * k + 2, y0 + 2, x0 + span * (k + 1) - 2, y1 - 3, f"k{k}")
    # drip stain under the taps
    cv.paint(cv.mask().ellipse(x0 + span * 1.5, y1 + 1, 14, 3), (40, 18, 10), 0.35)
    dust(cv, cv.a, 0.15, "rack", 6, 2)
    return finish(cv, "furniture/keg_rack.png")


# --------------------------------------------------------------------------
# harbour
# --------------------------------------------------------------------------
def rope_spiral(cv, cx, cy, r0, r1, width, turns, seed):
    pts = []
    n = int(turns * 48)
    for k in range(n):
        t = k / max(1, n - 1)
        a = t * turns * 2 * math.pi
        r = r0 + (r1 - r0) * t
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    cv.stroke(pts, width + 1.6, INK, 0.95, smooth=True)
    cv.stroke(pts, width, ROPE, 1.0, smooth=True)
    # twist of the strands
    rr = rng(f"{cv.name}:{seed}")
    for k in range(0, n, 2):
        x, y = pts[k]
        a = math.atan2(y - cy, x - cx) + 0.8
        cv.stroke([(x - math.cos(a) * width * 0.45, y - math.sin(a) * width * 0.45),
                   (x + math.cos(a) * width * 0.45, y + math.sin(a) * width * 0.45)], 0.5, "#4a3a22", 0.7)
    cv.stroke([(x + 0.8, y - 0.8) for x, y in pts], width * 0.25, "#cdb98a", 0.35, smooth=True)
    return pts


def rope_coil():
    cv = F("rope_coil", 1, 1)
    rope_spiral(cv, 28, 28, 4, 22, 4.2, 3.6, "coil")
    # loose end trailing off
    cv.stroke(catmull([(48, 30), (54, 40), (50, 52), (58, 56)], 8), 5.6, INK, 0.95)
    cv.stroke(catmull([(48, 30), (54, 40), (50, 52), (58, 56)], 8), 4.0, ROPE, 1.0)
    return finish(cv, "furniture/rope_coil.png")


def bollard():
    cv = F("bollard", 1, 1)
    cx, cy = 28, 28
    # a hawser looped twice around the post, running off toward the water (front)
    for r, op in ((20, 1.0), (17, 0.9)):
        cv.stroke(ellipse_pts(cx, cy, r, r * 0.92, 60) + [ellipse_pts(cx, cy, r, r * 0.92, 60)[0]], 5.0, INK, op)
        cv.stroke(ellipse_pts(cx, cy, r, r * 0.92, 60) + [ellipse_pts(cx, cy, r, r * 0.92, 60)[0]], 3.4, ROPE, op)
    cv.stroke([(cx + 6, cy + 18), (cx + 10, 60)], 5.0, INK)
    cv.stroke([(cx + 6, cy + 18), (cx + 10, 60)], 3.4, ROPE)
    post = cv.mask().circle(cx, cy, 14, wobble=0.3)
    cv.part(post, "#2c2d31", ow=3.0, shade=0.5, light=0.45, hatch=0.4, depth=4)
    cap = cv.mask().circle(cx - 1, cy - 1, 9)
    cv.part(cap, "#3c3d42", ow=1.6, shade=0.4, light=0.5, hatch=0.2, depth=2)
    rust(cv, post.arr, 0.55, "post", 4, 4)
    cv.paint(cv.mask().ellipse(cx - 4, cy - 5, 3, 1.6, rot=-35), (200, 205, 210), 0.35)
    return finish(cv, "furniture/bollard.png")


def fishing_net():
    cv = F("fishing_net", 2, 2)
    rr = cv.rnd
    W, H = cv.w, cv.h
    # a heap of mesh: knots on a jittered grid, clipped to a soft blob
    blob = cv.mask().poly(ellipse_pts(W / 2, H / 2, W * 0.44, H * 0.4, 40), wobble=6, step=4).arr
    blob = blur(blob, 3 * cv.ss)
    step = 7.0
    grid = {}
    for i in range(int(W / step) + 2):
        for j in range(int(H / step) + 2):
            grid[(i, j)] = (i * step + rr.normal(0, 1.6), j * step + rr.normal(0, 1.6))
    lines = cv.mask()
    for (i, j), p in grid.items():
        for q in ((i + 1, j + 1), (i + 1, j - 1)):
            if q in grid:
                lines.line([p, grid[q]], 0.9)
    m = lines.arr * blob
    cv.paint(m, "#5a5446", 0.95)
    cv.mul(blob * 0.0 + m, 0.2)
    # thicker folds where the heap doubles over
    for _ in range(5):
        a = rr.random() * math.pi
        x, y = W / 2 + rr.normal(0, 22), H / 2 + rr.normal(0, 20)
        pts = [(x - math.cos(a) * 30, y - math.sin(a) * 30), (x, y + rr.normal(0, 6)),
               (x + math.cos(a) * 30, y + math.sin(a) * 30)]
        cv.stroke(catmull(pts, 8), 2.0, "#3a362c", 0.55, smooth=True)
    # cork floats along the head rope
    head = [(W * 0.12, H * 0.3), (W * 0.35, H * 0.18), (W * 0.62, H * 0.22), (W * 0.88, H * 0.4)]
    hp = catmull(head, 10)
    cv.stroke(hp, 2.2, INK, 0.9, smooth=True)
    cv.stroke(hp, 1.2, ROPE, 1.0, smooth=True)
    for k in range(2, len(hp) - 2, 5):
        x, y = hp[k]
        cv.part(cv.mask().ellipse(x, y, 4.2, 3.0, rot=rr.random() * 60), "#a07a48", ow=1.2, shade=0.4, light=0.4,
                hatch=0, depth=1.2)
    cv.grain(0.06)
    return finish(cv, "furniture/fishing_net.png", shadow=(2.0, 2.5, 2.0, 0.35))


def water():
    """seamless 128 px tile of black harbour water: slow swell, ink ripple lines, a few glints."""
    cv = Canvas(2 * C, 2 * C, 2, tile=True, name="water")
    W, H = cv.W, cv.H
    r = rng("water:swell")
    swell = fbm(W, H, 2, 2, r, 4)
    base = np.zeros((H, W, 3), np.float32)
    deep, shallow = col("#0b1416"), col("#1d2d30")
    base[:] = deep + (shallow - deep) * swell[..., None]
    cv.paint(np.ones((H, W), np.float32), base)
    # ripple contours of a second, finer field
    fine = fbm(W, H, 4, 4, rng("water:ripple"), 3)
    for lvl, op in ((0.3, 0.45), (0.5, 0.35), (0.7, 0.45)):
        band = np.clip(1 - np.abs(fine - lvl) / 0.018, 0, 1)
        cv.tint(band, INK, op)
    for lvl in (0.4, 0.6):
        band = np.clip(1 - np.abs(fine - lvl) / 0.012, 0, 1) * smoothstep(0.55, 0.9, swell)
        cv.screen(band, 0.22, (150, 175, 180))
    # faint horizontal hatching (ink wash)
    cv.hatch(np.ones((H, W), np.float32), 0, 5.0, 0.7, 0.12)
    glints = pnoise(W, H, 16, 16, rng("water:glint"))
    cv.screen(smoothstep(0.86, 0.97, glints) * swell, 0.25, (200, 215, 220))
    cv.grain(0.05)
    save(cv.image(), "furniture/water.png")


def boat_hull():
    """a moored fishing lugger seen from above, bow up. The walkable deck is the
    middle 4x10 cells; the gunwale stands over the water around it, with a gap on
    the port (left) side at rows 6-7 for the gangway."""
    cv = F("boat_hull", 6, 14)
    W, H = cv.w, cv.h
    cx = W / 2
    # hull outline: pointed bow (top), rounded transom (bottom)
    right = [(cx, 6), (cx + 70, 40), (cx + 128, 120), (cx + 152, 220), (cx + 156, 400), (cx + 152, 700),
             (cx + 140, 800), (cx + 110, 868), (cx, 884)]
    left = [(2 * cx - x, y) for x, y in reversed(right[1:-1])]
    outline = catmull(right + [(cx, 884)] + left + [(cx, 6)], 10)
    hull = cv.mask().poly(outline, wobble=0.6)
    cv.part(hull, wtex(cv, "ebony", True, "hull"), ow=4.2, shade=0.55, light=0.2, hatch=0.5, depth=6)
    # tarred strakes visible outside the gunwale
    for k, off in enumerate((4, 9)):
        ring = [(cx + (x - cx) * (1 - off / 160), 6 + (y - 6) * (1 - off / 900) + off * 0.6) for x, y in outline]
        cv.stroke(ring, 0.8, "#3a3a3a", 0.6)
    # deck planking inside the gunwale
    inner = [(cx + (x - cx) * 0.83, 40 + (y - 40) * 0.95) for x, y in outline]
    deck = cv.mask().poly(inner)
    cv.part(deck, wtex(cv, "pine", True, "deck", rings=60), ow=2.4, shade=0.45, light=0.25, hatch=0.35, depth=8, soft=0.3)
    for k in range(-6, 7):
        xx = cx + k * 21
        cv.stroke([(xx, 40), (xx, H - 30)], 0.7, INK, 0.5)
    rr = cv.rnd
    for _ in range(40):
        x, y = cx + rr.normal(0, 70), rr.uniform(120, H - 60)
        cv.paint(cv.mask().circle(x, y, 0.9), "#1a1410", 0.8)
    cv.mul(deck.arr * (1 - fbm(cv.W, cv.H, 4, 10, rng("boat:wet"), 3)), 0.35, (20, 30, 34))
    # gunwale rail
    rail = [(cx + (x - cx) * 0.9, 20 + (y - 20) * 0.97) for x, y in outline]
    cv.stroke(rail, 5.0, INK, 1.0, smooth=True)
    cv.stroke(rail, 3.0, "#5e4630", 1.0, smooth=True)
    # gangway gap on the port side (cells 6..7 from the top, i.e. 384..512 px)
    gap = cv.mask().rect(0, 392, 70, 504, 0)
    cv.paint(gap, wtex(cv, "pine", False, "plank"), 1.0)
    cv.stroke([(0, 392), (70, 392)], 1.6, INK, 0.9)
    cv.stroke([(0, 504), (70, 504)], 1.6, INK, 0.9)
    for yy in (420, 448, 476):
        cv.stroke([(0, yy), (68, yy)], 0.7, INK, 0.6)
    # mast step and bowsprit at the bow (over the water, outside the walkable deck)
    cv.stroke([(cx, 6), (cx, -10)], 5.0, INK)
    cv.part(cv.mask().circle(cx, 92, 13), wtex(cv, "oak", seed="mast"), ow=2.8, shade=0.5, light=0.4, hatch=0.3, depth=3)
    cv.paint(cv.mask().circle(cx, 92, 5), "#20160e")
    for a in (-0.6, 0.6, math.pi - 0.4, math.pi + 0.4):
        cv.stroke([(cx + math.cos(a) * 13, 92 + math.sin(a) * 13), (cx + math.cos(a) * 120, 92 + math.sin(a) * 40)],
                  0.8, "#2a2418", 0.7)
    # tiller at the transom, painted name board
    cv.stroke([(cx, 860), (cx + 4, 812)], 4.0, INK)
    cv.stroke([(cx, 860), (cx + 4, 812)], 2.4, "#6e4c31")
    nb = cv.mask().rect(cx - 50, 864, cx + 50, 878, 2)
    cv.part(nb, "#1c1c1c", ow=1.4, shade=0.2, light=0.2, hatch=0, depth=1)
    f = cv.mask().text((cx, 871), "MARY ELLEN", __import__("core").font("IMFellEnglishSC-Regular.ttf", 9 * cv.ss), anchor="mm")
    cv.tint(f, "#c8b88a", 0.8)
    # weed and barnacles along the waterline
    wl = cv.mask().poly(outline).arr
    band = np.clip(wl - blur(wl, 5 * cv.ss) * 1.0, 0, 1)
    cv.tint(band * fbm(cv.W, cv.H, 6, 20, rng("boat:weed"), 3), "#2e3a22", 0.6)
    return finish(cv, "furniture/boat_hull.png", shadow=(3.0, 5.0, 4.0, 0.5))


LOCATIONS = [bar_counter, keg_rack, rope_coil, bollard, fishing_net, water, boat_hull]


def build_all(only=None):
    for f in LOCATIONS:
        if only and f.__name__ not in only:
            continue
        f()


if __name__ == "__main__":
    import sys
    build_all(sys.argv[1:] or None)
