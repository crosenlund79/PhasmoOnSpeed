"""Revision 2: basement / neglect furniture, stairs and neglect decor overlays.

Same kit as furniture.py (footprint x 64 px, front faces +Y, inked, hatched,
grain, soft baked drop shadow).  The theme is "grittier and partially
abandoned": dust sheets, damp, rust, rubble, cobwebs, coal and boilers.
"""
from __future__ import annotations

import math

import numpy as np

from core import (Canvas, INK, blur, catmull, col, dilate, ellipse_pts, erode, fbm, mix, noise_tex, pnoise,
                  radial, rng, rrect_pts, save, smoothstep, edge_band, wood_tex)
from furniture import (BRASS, IRON, F, box, cushion, fab, finish, glow_pass, groove, groove_rect, knob, paper,
                       stone_tex, wood, wtex)

RUST = (120, 62, 30)
DUST = (176, 168, 150)
SHEET = "#7f7c74"


# --------------------------------------------------------------------------
# weathering helpers
# --------------------------------------------------------------------------
def rust(cv, m, amount=0.45, seed="rust", cx=8, cy=5):
    m = m.arr if hasattr(m, "arr") else m
    n = cv.noise(cx, cy, 4, seed=seed)
    streak = fbm(cv.W, cv.H, cx * 3, max(2, cy // 2), rng(f"{cv.name}:{seed}:s"), 3)
    r = smoothstep(0.55, 0.9, n * 0.7 + streak * 0.45) * m
    cv.tint(r, RUST, amount)
    cv.tint(r * smoothstep(0.75, 0.95, n), (70, 34, 18), amount * 0.8)


def dust(cv, m, amount=0.22, seed="dust", cx=5, cy=5):
    m = m.arr if hasattr(m, "arr") else m
    n = cv.noise(cx, cy, 4, seed=seed)
    cv.screen(m * smoothstep(0.35, 0.9, n), amount, DUST)


def rivets(cv, pts, r=1.3, color="#5a5a60"):
    for (x, y) in pts:
        cv.paint(cv.mask().circle(x + 0.4, y + 0.5, r + 0.5), INK, 0.8)
        cv.paint(cv.mask().circle(x, y, r), color)
        cv.paint(cv.mask().circle(x - r * 0.35, y - r * 0.35, r * 0.4), (200, 200, 205), 0.7)


def ring_rivets(cv, cx, cy, rad, n, r=1.2):
    rivets(cv, [(cx + math.cos(k * 2 * math.pi / n) * rad, cy + math.sin(k * 2 * math.pi / n) * rad)
                for k in range(n)], r)


def pipe(cv, pts, w, color="#4a4a50", shade=0.45, hl=0.55, ow=2.0):
    m = cv.mask().line(pts, w)
    cv.part(m, noise_tex(cv.W, cv.H, rng(f"{cv.name}:pipe:{pts[0]}"), color, 0.18, 10, 10), ow=ow,
            shade=shade, light=0.3, hatch=0.3, depth=max(1.0, w * 0.3))
    # specular stripe along the upper-left side
    p = np.array(pts, float)
    d = p[-1] - p[0]
    n = np.array([d[1], -d[0]]) / (np.linalg.norm(d) + 1e-9)
    if n[0] + n[1] > 0:
        n = -n
    cv.stroke([tuple(q + n * w * 0.22) for q in p], max(0.6, w * 0.16), (230, 225, 210), hl)
    return m


def flange(cv, x, y, w, h, color="#3c3c42"):
    m = cv.mask().rect(x - w / 2, y - h / 2, x + w / 2, y + h / 2, 1)
    cv.part(m, color, ow=1.4, shade=0.4, light=0.45, hatch=0, depth=1)
    for yy in (y - h / 2 + 1.6, y + h / 2 - 1.6):
        cv.paint(cv.mask().circle(x, yy, 0.8), "#9a9590")


def valve_wheel(cv, x, y, r, color="#6a2420"):
    ring = cv.mask().circle(x, y, r)
    ring_in = erode(ring.arr, 2.2 * cv.ss)
    rm = ring.arr - ring_in
    for k in range(5):
        a = k * 2 * math.pi / 5 + 0.3
        cv.stroke([(x, y), (x + math.cos(a) * r, y + math.sin(a) * r)], 2.6, INK)
        cv.stroke([(x, y), (x + math.cos(a) * r, y + math.sin(a) * r)], 1.2, color)
    cv.part(rm, color, ow=1.4, shade=0.4, light=0.45, hatch=0, depth=1)
    cv.part(cv.mask().circle(x, y, r * 0.28), "#3a3a3e", ow=1.0, shade=0.3, light=0.4, hatch=0, depth=0.8)


def cobweb_corner(cv, x, y, sx, sy, size=16, op=0.55):
    """small cobweb strung in a corner at (x,y), opening toward (sx,sy)."""
    n = 6
    spokes = []
    for k in range(n):
        a = k / (n - 1) * math.pi / 2
        spokes.append((x + sx * math.cos(a) * size, y + sy * math.sin(a) * size))
    for p in spokes:
        cv.stroke([(x, y), p], 0.45, (215, 212, 205), op)
    for f in (0.35, 0.6, 0.85):
        pts = []
        for k in range(n):
            a = k / (n - 1) * math.pi / 2
            rr = size * f * (0.92 + 0.08 * math.sin(k * 2.1))
            pts.append((x + sx * math.cos(a) * rr, y + sy * math.sin(a) * rr))
        cv.stroke(catmull(pts, 6), 0.4, (215, 212, 205), op * 0.85)


def relief(cv, hmap, m, light=0.35, dark=0.5, k=4.0):
    """shade a height field (upper-left light) inside m."""
    gy, gx = np.gradient(hmap)
    s = (gx + gy) * k * cv.ss
    cv.screen(m * np.clip(s, 0, 1), light, (235, 230, 220))
    cv.mul(m * np.clip(-s, 0, 1), dark, (30, 30, 40))


def sheet_folds(cv, m, rr, n, area, color=SHEET, length=(14, 40)):
    x0, y0, x1, y1 = area
    for _ in range(n):
        sx, sy = x0 + rr.random() * (x1 - x0), y0 + rr.random() * (y1 - y0)
        a = rr.random() * math.pi
        ln = length[0] + rr.random() * (length[1] - length[0])
        bend = rr.normal(0, 0.35)
        pts = [(sx + math.cos(a + bend * t) * ln * t, sy + math.sin(a + bend * t) * ln * t) for t in np.linspace(0, 1, 5)]
        fm = cv.mask().curve(pts, 1.1)
        cv.tint(fm.arr * m, mix(color, INK, 0.55), 0.5)
        lm = cv.mask().curve([(x - 1.2, y - 1.2) for x, y in pts], 0.9)
        cv.screen(lm.arr * m, 0.35)


# --------------------------------------------------------------------------
# basement furniture
# --------------------------------------------------------------------------
def boiler():
    cv = F("boiler", 3, 2)
    x0, y0, x1, y1 = box(cv)
    # pipes leaving through the back wall
    pipe(cv, [(x0 + 38, -4), (x0 + 38, y0 + 30)], 9, "#3e3e44")
    pipe(cv, [(x0 + 70, -4), (x0 + 70, y0 + 22)], 6, "#6a4a32")
    pipe(cv, [(x1 - 30, -4), (x1 - 30, y0 + 30)], 8, "#3e3e44")
    flange(cv, x0 + 38, y0 + 6, 14, 4)
    flange(cv, x1 - 30, y0 + 8, 13, 4)
    # firebox / furnace body
    fx0, fy0, fx1, fy1 = x0 + 2, y0 + 14, x0 + 100, y1
    fb = cv.mask().rect(fx0, fy0, fx1, fy1, 4, wobble=0.3)
    it = noise_tex(cv.W, cv.H, cv.rnd, "#2e2e33", 0.2, 12, 8)
    cv.part(fb, it, ow=3.6, shade=0.5, light=0.3, hatch=0.55, depth=4)
    groove_rect(cv, fx0 + 5, fy0 + 5, fx1 - 5, fy1 - 5, 0.9, r=2)
    rivets(cv, [(fx0 + 5 + k * (fx1 - fx0 - 10) / 9, fy0 + 3) for k in range(10)] +
           [(fx0 + 5 + k * (fx1 - fx0 - 10) / 9, fy1 - 3) for k in range(10)] +
           [(fx0 + 3, fy0 + 10 + k * 14) for k in range(6)] + [(fx1 - 3, fy0 + 10 + k * 14) for k in range(6)])
    # flue collar and pressure gauge on top of the furnace
    cv.part(cv.mask().circle(x0 + 38, y0 + 38, 13), "#26262a", ow=2.6, shade=0.5, light=0.4, hatch=0.3, depth=3)
    cv.paint(cv.mask().circle(x0 + 38, y0 + 38, 8), "#0a0a0b")
    ring_rivets(cv, x0 + 38, y0 + 38, 11, 8, 0.9)
    gx, gy = x0 + 78, y0 + 40
    cv.part(cv.mask().circle(gx, gy, 9), BRASS, ow=1.8, shade=0.45, light=0.5, hatch=0, depth=1.5)
    cv.part(cv.mask().circle(gx, gy, 6.5), "#d8cfb4", ow=0.8, shade=0.2, light=0, hatch=0, depth=1)
    for k in range(9):
        a = math.radians(140 + k * 32)
        cv.stroke([(gx + math.cos(a) * 4.8, gy + math.sin(a) * 4.8), (gx + math.cos(a) * 6, gy + math.sin(a) * 6)],
                  0.5, INK, 0.8)
    cv.stroke([(gx, gy), (gx + 4.6, gy - 2.2)], 0.9, "#7a1a14")
    # firebox door at the front with glowing grate slits
    dx0, dx1 = fx0 + 20, fx1 - 20
    dm = cv.mask().rect(dx0, fy1 - 26, dx1, fy1 - 1, 2)
    cv.part(dm, "#1c1c20", ow=2.2, shade=0.4, light=0.35, hatch=0.3, depth=2)
    for k in range(5):
        xx = dx0 + 7 + k * (dx1 - dx0 - 14) / 4
        sl = cv.mask().rect(xx - 2, fy1 - 20, xx + 2, fy1 - 7, 1)
        cv.paint(sl, (255, 120, 40), 0.9)
        cv.paint(cv.mask().rect(xx - 0.8, fy1 - 18, xx + 0.8, fy1 - 9, 0.5), (255, 210, 120), 0.9)
    cv.part(cv.mask().rect(dx1 - 4, fy1 - 16, dx1 + 6, fy1 - 11, 1), "#8a8a8e", ow=1.0, depth=0.8, hatch=0)
    # connecting pipe furnace -> drum
    pipe(cv, [(fx1 - 8, y0 + 30), (x1 - 70, y0 + 30)], 8, "#45454b")
    # boiler drum (vertical cylinder seen from above)
    bx, by, br = x1 - 46, (y0 + y1) / 2 + 4, 44
    dr = cv.mask().circle(bx, by, br, wobble=0.25)
    cv.part(dr, noise_tex(cv.W, cv.H, rng("boiler:drum"), "#3a3c42", 0.2, 10, 10), ow=3.6, shade=0.5, light=0.35,
            hatch=0.5, depth=6)
    for rr_ in (36, 24):
        groove(cv, ellipse_pts(bx, by, rr_, rr_, 90), 1.0, closed=True)
    ring_rivets(cv, bx, by, 40, 28, 1.1)
    ring_rivets(cv, bx, by, 30, 20, 1.0)
    rust(cv, dr, 0.5, "drum")
    rust(cv, fb, 0.35, "fb")
    # safety valve dome and wheel
    cv.part(cv.mask().circle(bx, by, 14), "#48484e", ow=2.4, shade=0.5, light=0.5, hatch=0.3, depth=3)
    valve_wheel(cv, bx, by, 9)
    # soot around flue, coal dust at the door
    n = cv.noise(6, 4, 3, seed="soot")
    soot = np.clip(1 - radial(cv.W, cv.H, (x0 + 38) * cv.ss, (y0 + 38) * cv.ss, 26 * cv.ss), 0, 1) * fb.arr
    cv.mul(soot * (0.5 + 0.5 * n), 0.5, (10, 10, 10))
    cv.grain(0.07)
    cv.drop_shadow(3, 4, 2.5, 0.55)
    # faint orange firebox glow spilling onto the floor at the front
    g = np.clip(1 - radial(cv.W, cv.H, (dx0 + dx1) / 2 * cv.ss, (fy1 - 4) * cv.ss, 36 * cv.ss), 0, 1) ** 2
    cv.glow(g, (255, 120, 40), 0.28)
    save(cv.image(), "furniture/boiler.png")


def bottle(cv, x, y, length, w, color, rr, dusty=True):
    """wine bottle lying front-to-back (neck toward the front)."""
    body = cv.mask().rect(x - w / 2, y, x + w / 2, y + length * 0.66, w / 2.2)
    body.poly([(x - w / 2, y + length * 0.6), (x + w / 2, y + length * 0.6), (x + w * 0.2, y + length * 0.78),
               (x - w * 0.2, y + length * 0.78)])
    body.rect(x - w * 0.2, y + length * 0.74, x + w * 0.2, y + length, 1)
    cv.part(body, color, ow=1.2, shade=0.45, light=0.35, hatch=0, depth=1.5)
    cv.stroke([(x - w * 0.22, y + 2), (x - w * 0.22, y + length * 0.6)], 0.7, (220, 235, 220), 0.45)
    cv.paint(cv.mask().rect(x - w * 0.22, y + length * 0.86, x + w * 0.22, y + length, 1),
             ["#5a1a1e", "#8a7344", "#3a2a20"][int(rr.integers(0, 3))], 0.95)
    if dusty:
        dust(cv, body.arr, 0.35, f"b{x:.0f}", 3, 3)


def wine_rack():
    cv = F("wine_rack", 3, 1)
    x0, y0, x1, y1 = box(cv)
    rr = cv.rnd
    frame = cv.mask().rect(x0, y0, x1, y1, 2, wobble=0.25)
    wood(cv, frame, "walnut", False, ow=3.4)
    inner = cv.mask().rect(x0 + 5, y0 + 4, x1 - 5, y1 - 4, 1)
    cv.paint(inner, "#110c09")
    n = 16
    span = (x1 - x0 - 10) / n
    greens = ["#1f3a2a", "#26382c", "#2a2e22", "#3a2a1e"]
    for k in range(n):
        x = x0 + 5 + span * (k + 0.5)
        roll = rr.random()
        if roll < 0.14:
            continue  # empty slot
        if roll < 0.2:
            # smashed bottle: shards and a dried wine stain
            st = cv.mask().ellipse(x, y0 + 30, span * 0.6, 10, wobble=1.0)
            cv.paint(st, (60, 14, 18), 0.6)
            for _ in range(6):
                sx, sy = x + rr.normal(0, 3), y0 + 18 + rr.random() * 24
                a = rr.random() * 6.28
                cv.part(cv.mask().poly([(sx, sy), (sx + math.cos(a) * 4, sy + math.sin(a) * 4),
                                        (sx + math.cos(a + 1.4) * 2.5, sy + math.sin(a + 1.4) * 2.5)]),
                        "#2f4a36", ow=0.6, shade=0.2, light=0.5, hatch=0, depth=0.6)
            continue
        bottle(cv, x + rr.normal(0, 0.3), y0 + 6 + rr.random() * 2, y1 - y0 - 12, span * 0.78,
               greens[int(rr.integers(0, len(greens)))], rr)
    # lattice battens every 4 slots
    for k in range(0, n + 1, 4):
        xx = x0 + 5 + span * k
        b = cv.mask().rect(xx - 2.5, y0 + 1, xx + 2.5, y1 - 1, 1)
        wood(cv, b, "walnut", True, f"bt{k}", ow=1.6, depth=1.2)
    for yy in (y0 + 14, y1 - 14):
        cv.stroke([(x0 + 4, yy), (x1 - 4, yy)], 1.6, INK, 0.75)
        cv.stroke([(x0 + 4, yy - 0.8), (x1 - 4, yy - 0.8)], 0.7, "#6b4a33", 0.9)
    dust(cv, frame.arr, 0.3, "rack", 6, 2)
    cobweb_corner(cv, x0 + 2, y0 + 2, 1, 1, 18, 0.6)
    cobweb_corner(cv, x1 - 2, y1 - 2, -1, -1, 12, 0.45)
    return finish(cv, "furniture/wine_rack.png")


def coal_pile():
    cv = F("coal_pile", 2, 2)
    rr = cv.rnd
    cx, cy = 60, 60
    # coal dust spread on the floor
    dm = cv.mask().ellipse(cx + 2, cy + 3, 56, 52, wobble=4.0)
    cv.paint(blur(dm.arr, 4 * cv.ss), (14, 13, 14), 0.5)
    heap = cv.mask().poly(ellipse_pts(cx, cy, 44, 41, 90), wobble=4.5, step=4)
    cv.part(heap, noise_tex(cv.W, cv.H, cv.rnd, "#1b1b1f", 0.25, 16, 16), ow=3.2, shade=0.55, light=0.15,
            hatch=0.4, depth=8)
    # mound relief: brighter toward the summit / upper left
    h = blur(heap.arr, 14 * cv.ss)
    relief(cv, h, heap.arr, 0.25, 0.5, 30.0)
    # individual lumps
    hm = heap.arr
    placed = 0
    tries = 0
    while placed < 150 and tries < 2000:
        tries += 1
        x, y = cx + rr.normal(0, 22), cy + rr.normal(0, 20)
        if not (0 <= x < cv.w and 0 <= y < cv.h) or hm[int(y * cv.ss), int(x * cv.ss)] < 0.9:
            continue
        r = 2.2 + rr.random() * 4.2
        k = int(rr.integers(5, 8))
        a0 = rr.random() * 6.28
        pts = [(x + math.cos(a0 + j * 6.28 / k) * r * (0.6 + 0.5 * rr.random()),
                y + math.sin(a0 + j * 6.28 / k) * r * (0.6 + 0.5 * rr.random())) for j in range(k)]
        c = mix("#141417", "#2c2e36", rr.random())
        cv.part(cv.mask().poly(pts), c, ow=0.7, shade=0.4, light=0.55, hatch=0, depth=1.2)
        if rr.random() < 0.5:
            cv.stroke([pts[0], pts[1]], 0.5, (150, 160, 180), 0.6)
        placed += 1
    # stray lumps on the floor
    for _ in range(14):
        a = rr.random() * 6.28
        d = 44 + rr.random() * 10
        x, y = cx + math.cos(a) * d, cy + math.sin(a) * d * 0.95
        r = 1.6 + rr.random() * 2.4
        cv.part(cv.mask().poly(ellipse_pts(x, y, r, r * 0.8, 6, rr.random() * 90)), "#18181c", ow=0.9, shade=0.3,
                light=0.5, hatch=0, depth=0.8)
    # shovel stuck in the heap
    sh = cv.mask().line([(cx - 2, cy + 6), (cx + 38, cy - 34)], 4.2)
    cv.part(sh, wtex(cv, "pine", seed="sh"), ow=1.6, shade=0.4, light=0.3, hatch=0.2, depth=1.2)
    grip = cv.mask().poly(ellipse_pts(cx + 42, cy - 38, 7, 4.5, 30, -45))
    cv.part(grip, wtex(cv, "pine", seed="gr"), ow=1.6, shade=0.4, light=0.3, hatch=0, depth=1)
    cv.paint(cv.mask().ellipse(cx + 42, cy - 38, 4, 1.6, rot=-45), INK)
    blade = cv.mask().poly([(cx - 4, cy + 2), (cx + 4, cy + 10), (cx - 8, cy + 24), (cx - 20, cy + 12)], wobble=0.3)
    cv.part(blade, "#5a5a60", ow=1.8, shade=0.45, light=0.4, hatch=0.2, depth=1.5)
    rust(cv, blade.arr, 0.5, "blade", 4, 4)
    # half-buried: coal spilling over the blade tip
    for _ in range(8):
        x, y = cx - 14 + rr.normal(0, 3), cy + 16 + rr.normal(0, 3)
        r = 2 + rr.random() * 2
        cv.part(cv.mask().poly(ellipse_pts(x, y, r, r * 0.8, 6, rr.random() * 90)), "#1a1a1e", ow=0.7,
                shade=0.3, light=0.5, hatch=0, depth=0.8)
    return finish(cv, "furniture/coal_pile.png")


def storage_shelf():
    cv = F("storage_shelf", 3, 1)
    x0, y0, x1, y1 = box(cv)
    rr = cv.rnd
    frame = cv.mask().rect(x0, y0, x1, y1, 2, wobble=0.25)
    wood(cv, frame, "grey", False, ow=3.4)
    inner = cv.mask().rect(x0 + 5, y0 + 4, x1 - 5, y1 - 4, 1)
    cv.paint(inner, "#130f0c")
    # sagging shelf board (bows toward the front in the middle)
    sag = catmull([(x0 + 5, y0 + 6), ((x0 + x1) / 2, y0 + 11), (x1 - 5, y0 + 6)], 16)
    sb = cv.mask().poly(catmull([(x0 + 5, y0 + 5), ((x0 + x1) / 2, y0 + 8), (x1 - 5, y0 + 5)], 16)
                        + list(reversed(catmull([(x0 + 5, y1 - 6), ((x0 + x1) / 2, y1 - 1), (x1 - 5, y1 - 6)], 16))))
    cv.part(sb, wtex(cv, "grey", seed="board") * 0.62, ow=1.6, shade=0.5, light=0.1, hatch=0.45, depth=3)
    cv.mul(smoothstep(0.0, 1.0, 1 - np.abs(np.linspace(-1, 1, cv.W))[None, :]) * sb.arr, 0.35, (30, 25, 20))
    _ = sag
    # contents: jars, tins, boxes
    for row, yoff, sc in ((0, -8, 0.8), (1, 3, 1.0)):
        x = x0 + 9 + row * 5
        while x < x1 - 14:
            kind = rr.random()
            sagy = 4 * (1 - abs((x - (x0 + x1) / 2) / ((x1 - x0) / 2)) ** 2)
            if kind < 0.35:
                r = (6 + rr.random() * 2.5) * sc
                cy = y0 + 24 + yoff + sagy + rr.normal(0, 2)
                glass = mix("#7f9a86", "#9a8a5a", rr.random())
                cv.part(cv.mask().circle(x + r, cy, r), glass, ow=1.3, shade=0.35, light=0.55, hatch=0, depth=1.5)
                cv.paint(cv.mask().circle(x + r, cy, r * 0.62), mix(["#5a3a1e", "#6a2a20", "#3a4a22"][int(rr.integers(0, 3))],
                                                                   "#000000", 0.2), 0.8)
                cv.part(cv.mask().circle(x + r, cy, r * 0.45), "#6a6458", ow=0.8, shade=0.3, light=0.4, hatch=0, depth=0.6)
                x += 2 * r + 0.5 + rr.random() * 2
            elif kind < 0.65:
                r = (5 + rr.random() * 2) * sc
                cy = y0 + 22 + yoff + sagy + rr.normal(0, 2)
                cv.part(cv.mask().circle(x + r, cy, r), "#6c6c70", ow=1.3, shade=0.4, light=0.5, hatch=0, depth=1.2)
                cv.stroke(ellipse_pts(x + r, cy, r - 1.6, r - 1.6, 24) + [ellipse_pts(x + r, cy, r - 1.6, r - 1.6, 24)[0]],
                          0.6, INK, 0.6)
                rust(cv, cv.mask().circle(x + r, cy, r).arr, 0.6, f"tin{x:.0f}", 2, 2)
                x += 2 * r + 0.5 + rr.random() * 2
            else:
                bw, bh = (12 + rr.random() * 8) * sc, (14 + rr.random() * 10) * sc
                by = y0 + 12 + yoff + sagy + rr.random() * 4
                rot = rr.normal(0, 4)
                c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
                P = lambda q: [(x + bw / 2 + px * c - py * s, by + bh / 2 + px * s + py * c) for px, py in q]
                bm = cv.mask().poly(P([(-bw / 2, -bh / 2), (bw / 2, -bh / 2), (bw / 2, bh / 2), (-bw / 2, bh / 2)]),
                                    wobble=0.4)
                cv.part(bm, noise_tex(cv.W, cv.H, rng(f"box{x}"), "#8a7250", 0.15), ow=1.5, shade=0.4, light=0.25,
                        hatch=0.3, depth=1.5)
                cv.stroke(P([(0, -bh / 2), (0, bh / 2)]), 1.4, "#b8a678", 0.7)
                cv.mul(bm.arr * smoothstep(0.6, 0.9, cv.noise(4, 4, 3, seed=f"bx{x}")), 0.35, (60, 40, 20))
                x += bw + 1
    # broken partition leaning over
    pm = cv.mask().poly([(x0 + 62, y0 + 4), (x0 + 66, y0 + 4), (x0 + 72, y1 - 5), (x0 + 68, y1 - 5)])
    wood(cv, pm, "grey", True, "part", ow=1.4, depth=1)
    lip = cv.mask().poly(catmull([(x0 + 2, y1 - 7), ((x0 + x1) / 2, y1 - 2), (x1 - 2, y1 - 7)], 16)
                         + list(reversed(catmull([(x0 + 2, y1 - 1), ((x0 + x1) / 2, y1 + 3), (x1 - 2, y1 - 1)], 16))))
    wood(cv, lip, "grey", False, "lip", ow=2.2, depth=1.5)
    dust(cv, cv.a > 0.5, 0.25, "sh", 6, 2)
    cobweb_corner(cv, x1 - 3, y0 + 3, -1, 1, 20, 0.6)
    return finish(cv, "furniture/storage_shelf.png")


def drape_fold(cv, m, pts, w=1.6, op=0.8, color=SHEET):
    """a soft cloth fold: dark crease with a lit ridge on its upper-left side."""
    fm = cv.mask().curve(pts, w)
    cv.mul(blur(fm.arr, 1.2 * cv.ss) * m, op, (30, 30, 36))
    cv.tint(fm.arr * m, mix(color, INK, 0.6), op * 0.6)
    lm = cv.mask().curve([(x - 1.6, y - 1.6) for x, y in pts], w * 1.4)
    cv.screen(blur(lm.arr, 1.0 * cv.ss) * m, 0.28)


def _covered(name, cw, ch, base, forms, folds, hem_pad=3.0):
    """base: fn(mask) for the overall footprint; forms: [(fn(mask), soft)] raised shapes under the sheet;
    folds: list of point lists (drape creases)."""
    cv = F(name, cw, ch)
    union = base(cv.mask()).arr
    # the sheet drapes beyond the hidden shape with a wavy hem
    sheet = dilate(union, hem_pad * cv.ss)
    n = cv.noise(12, 12, 3, seed="hem")
    sheet = smoothstep(0.35, 0.65, blur(sheet, 1.4 * cv.ss) + (n - 0.5) * 0.55)
    tex = fab(cv, SHEET, 0.12, 2.4)
    cv.part(sheet, tex, ow=3.2, shade=0.5, light=0.1, hatch=0.45, soft=0.45, depth=6)
    hm = np.zeros_like(sheet)
    for fn, h in forms:
        fm = fn(cv.mask()).arr
        # each raised form: soft-edged, lit on the upper-left, shaded on the lower-right, thin grey contour
        cv.paint(blur(dilate(fm, 0.9 * cv.ss) * (1 - fm), 0.8 * cv.ss), mix(SHEET, INK, 0.55), 0.3)
        cv.paint(fm, tex)
        d = 5 * cv.ss
        cv.mul(edge_band(fm, d, d, d * 0.8), 0.45, (34, 34, 40))
        cv.hatch(edge_band(fm, d, d, d * 0.8), 45, 3.0, 0.7, 0.4)
        cv.screen(edge_band(fm, -d * 0.7, -d * 0.7, d * 0.6), 0.3)
        cv.mul(fm * (1 - blur(erode(fm, 3 * cv.ss), 4 * cv.ss)), 0.25, (34, 34, 40))
        hm = np.maximum(hm, fm * h)
    for pts in folds:
        drape_fold(cv, sheet, pts)
    # random small creases everywhere so it reads as loose cloth
    rr = cv.rnd
    for _ in range(int(cw * ch * 5)):
        x, y = rr.random() * cv.w, rr.random() * cv.h
        a = rr.random() * math.pi
        ln = 6 + rr.random() * 12
        drape_fold(cv, sheet, catmull([(x, y), (x + math.cos(a) * ln / 2 + rr.normal(0, 1.5),
                                                y + math.sin(a) * ln / 2 + rr.normal(0, 1.5)),
                                       (x + math.cos(a) * ln, y + math.sin(a) * ln)], 6), 1.0, 0.45)
    # dust gathered on the raised tops, mildew blotches
    dust(cv, sheet * np.clip(blur(hm, 4 * cv.ss), 0, 1), 0.3, "top", 4, 4)
    mild = smoothstep(0.8, 0.96, cv.noise(7, 7, 4, seed="mil")) * sheet
    cv.mul(mild, 0.35, (70, 70, 50))
    return cv


def covered_armchair():
    x0, y0, x1, y1 = L_, T_, 2 * 64 - R_, 2 * 64 - B_
    mx = (x0 + x1) / 2
    back = (lambda m: m.poly(catmull([(x0 + 4, y0 + 32), (x0 + 6, y0 + 8), (x0 + 30, y0 + 3), (mx, y0 + 5),
                                      (x1 - 30, y0 + 3), (x1 - 6, y0 + 8), (x1 - 4, y0 + 32)], 8)
                             + [(x1 - 20, y0 + 30), (x1 - 22, y0 + 22), (mx, y0 + 20), (x0 + 22, y0 + 22),
                                (x0 + 20, y0 + 30)], wobble=0.8))
    base = lambda m: m.poly(catmull([(x0 + 2, y0 + 30), (x0 + 5, y0 + 6), (mx, y0 + 2), (x1 - 5, y0 + 6),
                                     (x1 - 2, y0 + 30), (x1 - 1, y1 - 6), (mx, y1 + 1), (x0 + 1, y1 - 6),
                                     (x0 + 2, y0 + 30)], 8), wobble=1.2)
    forms = [
        (back, 1.0),
        (lambda m: m.rect(x0 + 5, y0 + 26, x0 + 22, y1 - 8, 8, wobble=0.8), 0.75),
        (lambda m: m.rect(x1 - 22, y0 + 26, x1 - 5, y1 - 8, 8, wobble=0.8), 0.75),
        (lambda m: m.rect(x0 + 25, y0 + 25, x1 - 25, y1 - 12, 8, wobble=1.0), 0.5),
    ]
    folds = [
        catmull([(x0 + 24, y0 + 34), (x0 + 30, y0 + 60), (x0 + 26, y1 - 4)], 8),
        catmull([(x1 - 24, y0 + 30), (x1 - 32, y0 + 62), (x1 - 28, y1 - 2)], 8),
        catmull([(mx - 8, y1 - 12), (mx - 4, y1 - 6), (mx - 10, y1)], 6),
        catmull([(mx + 10, y1 - 12), (mx + 14, y1 - 4)], 6),
        catmull([(x0 + 8, y1 - 8), (x0 + 3, y1 - 2)], 6),
        catmull([(x1 - 8, y1 - 8), (x1 - 2, y1 - 3)], 6),
        catmull([(x0 + 26, y0 + 8), (x0 + 40, y0 + 14), (mx - 6, y0 + 12)], 6),
    ]
    cv = _covered("covered_armchair", 2, 2, base, forms, folds)
    return finish(cv, "furniture/covered_armchair.png")


def covered_sofa():
    x0, y0, x1, y1 = L_, T_, 4 * 64 - R_, 2 * 64 - B_
    base = lambda m: m.rect(x0 + 1, y0 + 2, x1 - 1, y1 - 1, 14, wobble=1.4)
    forms = [
        (lambda m: m.rect(x0 + 4, y0 + 4, x1 - 4, y0 + 30, 12, wobble=0.9), 1.0),
        (lambda m: m.rect(x0 + 4, y0 + 10, x0 + 27, y1 - 8, 10, wobble=0.9), 0.8),
        (lambda m: m.rect(x1 - 27, y0 + 10, x1 - 4, y1 - 8, 10, wobble=0.9), 0.8),
        (lambda m: m.rect(x0 + 31, y0 + 33, x0 + 92, y1 - 12, 7, wobble=0.9), 0.55),
        (lambda m: m.rect(x0 + 96, y0 + 34, x1 - 96, y1 - 10, 7, wobble=0.9), 0.5),
        (lambda m: m.rect(x1 - 92, y0 + 33, x1 - 31, y1 - 12, 7, wobble=0.9), 0.55),
    ]
    folds = [
        catmull([(x0 + 92, y0 + 36), (x0 + 95, y0 + 60), (x0 + 92, y1 - 2)], 8),
        catmull([(x1 - 92, y0 + 36), (x1 - 96, y0 + 64), (x1 - 92, y1)], 8),
        catmull([(x0 + 30, y0 + 40), (x0 + 34, y0 + 70), (x0 + 30, y1 - 1)], 8),
        catmull([(x1 - 30, y0 + 40), (x1 - 33, y0 + 72), (x1 - 29, y1 - 2)], 8),
        catmull([(x0 + 50, y0 + 10), (x0 + 80, y0 + 18), (x0 + 120, y0 + 14)], 8),
        catmull([(x1 - 70, y0 + 8), (x1 - 50, y0 + 18)], 6),
        catmull([(x0 + 60, y1 - 10), (x0 + 66, y1 - 2)], 6),
        catmull([(x1 - 120, y1 - 10), (x1 - 116, y1 - 1)], 6),
        catmull([(x0 + 6, y0 + 40), (x0 + 1, y0 + 60)], 6),
    ]
    cv = _covered("covered_sofa", 4, 2, base, forms, folds)
    return finish(cv, "furniture/covered_sofa.png")


L_, T_, R_, B_ = 3, 3, 6, 7


def broken_chair():
    cv = F("broken_chair", 1, 1)
    rr = cv.rnd
    cx, cy, rot = 28, 30, 24
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    P = lambda q: [(cx + px * c - py * s, cy + px * s + py * c) for px, py in q]
    # chair toppled onto its back: back panel flat on the floor, seat underside up
    back = cv.mask().poly(P(catmull([(-17, -6), (-16, -24), (0, -28), (16, -24), (17, -6)], 8) + [(13, -6), (-13, -6)]),
                          wobble=0.3)
    wood(cv, back, "walnut", False, "back", ow=2.6, depth=2)
    for k in range(4):
        xx = -9 + k * 6
        cv.stroke(P([(xx, -22 + abs(k - 1.5)), (xx, -8)]), 1.0, INK, 0.6)
    seat = cv.mask().poly(P(rrect_pts(-15, -8, 15, 18, 3, 3)), wobble=0.3)
    wood(cv, seat, "walnut", True, "seat", ow=2.8, depth=2.5)
    # underside braces
    cv.stroke(P([(-12, 5), (12, 5)]), 1.6, INK, 0.7)
    cv.stroke(P([(-12, 5.8), (12, 5.8)]), 0.8, "#6b4a33", 0.9)
    # three legs sticking up (ends), one snapped
    for (lx, ly, ok) in ((-11, -4, True), (11, -4, True), (-11, 14, True), (11, 14, False)):
        if ok:
            lm = cv.mask().poly(P(rrect_pts(lx - 3.2, ly - 3.2, lx + 3.2, ly + 3.2, 1.2, 2)))
            cv.part(lm, wtex(cv, "walnut", seed=f"l{lx}{ly}"), ow=1.6, shade=0.5, light=0.5, hatch=0, depth=1.2)
            cv.paint(cv.mask().poly(P(rrect_pts(lx - 1.6, ly - 1.6, lx + 1.6, ly + 1.6, 0.6, 2))), "#8a6a48", 0.9)
        else:
            st = cv.mask().poly(P([(lx - 3.2, ly - 3.2), (lx + 3.2, ly - 3.2), (lx + 3.2, ly + 1), (lx + 1.5, ly - 0.5),
                                   (lx, ly + 2.5), (lx - 1.5, ly), (lx - 3.2, ly + 2)]))
            cv.part(st, "#b08a5c", ow=1.4, shade=0.3, light=0.2, hatch=0, depth=0.8)
    # snapped leg lying on the floor with splintered end
    lg = cv.mask().poly([(36, 48), (54, 40), (56, 44), (52, 46), (55, 47), (51, 48.5), (38, 53)], wobble=0.2)
    wood(cv, lg, "walnut", False, "leg", ow=1.8, depth=1.2)
    cv.stroke([(52, 45.5), (57, 44.5)], 0.6, "#c8a070", 0.9)
    for _ in range(5):
        x, y = 44 + rr.random() * 12, 50 + rr.random() * 6
        a = rr.random() * math.pi
        cv.stroke([(x, y), (x + math.cos(a) * 3, y + math.sin(a) * 3)], 0.6, "#b89060", 0.9)
    dust(cv, cv.a > 0.5, 0.18, "bc", 3, 3)
    return finish(cv, "furniture/broken_chair.png")


def old_trunk():
    cv = F("old_trunk", 2, 1)
    x0, y0, x1, y1 = box(cv)
    rr = cv.rnd
    # body
    m = cv.mask().rect(x0 + 2, y0 + 2, x1 - 2, y1 - 2, 5, wobble=0.6)
    cv.part(m, noise_tex(cv.W, cv.H, cv.rnd, "#4a3424", 0.22), ow=3.4, shade=0.5, light=0.25, hatch=0.5,
            depth=4, soft=0.35)
    # lid ajar: a dark gap at the front showing the interior with cloth spilling out
    gap = cv.mask().poly([(x0 + 6, y1 - 12), (x1 - 6, y1 - 15), (x1 - 6, y1 - 7), (x0 + 6, y1 - 6)])
    cv.paint(gap, "#0b0807")
    cl = cv.mask().poly(catmull([(x0 + 30, y1 - 11), (x0 + 36, y1 - 3), (x0 + 44, y1 + 3), (x0 + 52, y1 - 2),
                                 (x0 + 56, y1 - 12)], 6), wobble=0.6)
    cv.part(cl, fab(cv, "#7a6a58"), ow=1.4, shade=0.4, light=0.2, hatch=0.3, depth=1.5)
    cv.stroke(catmull([(x0 + 36, y1 - 8), (x0 + 44, y1 - 1), (x0 + 50, y1 - 6)], 6), 0.6, INK, 0.5)
    # lid boards
    for yy in (y0 + 16, y0 + 30):
        cv.stroke([(x0 + 4, yy), (x1 - 4, yy - 0.8)], 0.9, INK, 0.7)
    # leather straps; the right one snapped and curling away
    for xx in (x0 + 26,):
        st = cv.mask().rect(xx - 4, y0 + 1, xx + 4, y1 - 13, 1, wobble=0.3)
        cv.part(st, "#2a1a10", ow=1.4, shade=0.3, light=0.3, hatch=0, depth=1)
        cv.part(cv.mask().rect(xx - 5, y0 + 26, xx + 5, y0 + 33, 1), "#6a6a6e", ow=1.2, depth=1, hatch=0)
        cv.paint(cv.mask().rect(xx - 2.5, y0 + 28, xx + 2.5, y0 + 31, 0.5), "#2a1a10")
    xs = x1 - 30
    st = cv.mask().rect(xs - 4, y0 + 1, xs + 4, y0 + 20, 1)
    st.poly(catmull([(xs - 4, y0 + 18), (xs + 2, y0 + 26), (xs + 12, y0 + 28), (xs + 16, y0 + 24)], 6)
            + catmull([(xs + 14, y0 + 21), (xs + 10, y0 + 23), (xs + 4, y0 + 21), (xs + 4, y0 + 18)], 6))
    cv.part(st, "#2a1a10", ow=1.4, shade=0.3, light=0.3, hatch=0, depth=1)
    # iron corner caps (one missing), dents, scuffs, a peeling label
    for (xx, yy, sx, sy) in ((x0 + 2, y0 + 2, 1, 1), (x1 - 2, y0 + 2, -1, 1), (x0 + 2, y1 - 2, 1, -1)):
        cv.part(cv.mask().poly([(xx, yy), (xx + 10 * sx, yy), (xx, yy + 10 * sy)]), "#4a4a50", ow=1.2, depth=1,
                hatch=0)
    lb = cv.mask().poly([(x1 - 22, y0 + 34), (x1 - 8, y0 + 32), (x1 - 7, y0 + 40), (x1 - 21, y0 + 42)], wobble=0.5)
    cv.part(lb, "#b8a684", ow=1.0, shade=0.3, light=0, hatch=0, depth=1)
    cv.stroke([(x1 - 19, y0 + 37), (x1 - 11, y0 + 36)], 0.6, "#3a3028", 0.7)
    for _ in range(9):
        x, y = x0 + 6 + rr.random() * (x1 - x0 - 12), y0 + 5 + rr.random() * 30
        a = rr.normal(0, 0.4)
        cv.stroke([(x, y), (x + math.cos(a) * (3 + rr.random() * 6), y + math.sin(a) * 3)], 0.6, (170, 140, 110), 0.5)
    rust(cv, m, 0.25, "tr", 5, 3)
    dust(cv, m, 0.25, "trd", 4, 3)
    return finish(cv, "furniture/old_trunk.png")


def water_tank():
    cv = F("water_tank", 2, 2)
    cx, cy, R = 60, 58, 54
    rr = cv.rnd
    # damp ring on the floor around the base
    wet = cv.mask().ellipse(cx + 4, cy + 6, R + 6, R + 4, wobble=3.0)
    cv.paint(blur(wet.arr, 3 * cv.ss), (16, 20, 22), 0.45)
    # inlet pipe through the back wall
    pipe(cv, [(cx + 22, -4), (cx + 22, cy - 30)], 8, "#4a4a50")
    flange(cv, cx + 22, 6, 13, 4)
    m = cv.mask().circle(cx, cy, R, wobble=0.3)
    cv.part(m, noise_tex(cv.W, cv.H, cv.rnd, "#4a5258", 0.18, 10, 10), ow=3.6, shade=0.5, light=0.35, hatch=0.5,
            depth=6)
    for r_ in (R - 6, R - 20):
        groove(cv, ellipse_pts(cx, cy, r_, r_, 100), 1.0, closed=True)
    ring_rivets(cv, cx, cy, R - 3, 36, 1.1)
    ring_rivets(cv, cx, cy, R - 13, 28, 1.0)
    # seam plates
    for a in (0.4, 2.5, 4.3):
        p0 = (cx + math.cos(a) * (R - 20), cy + math.sin(a) * (R - 20))
        p1 = (cx + math.cos(a) * (R - 6), cy + math.sin(a) * (R - 6))
        cv.stroke([p0, p1], 1.2, INK, 0.7)
        rivets(cv, [(p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t) for t in (0.2, 0.5, 0.8)], 0.9)
    # inspection hatch (off-centre), with a ring handle
    hx, hy = cx - 12, cy + 8
    cv.part(cv.mask().circle(hx, hy, 17), "#3e464c", ow=2.6, shade=0.5, light=0.4, hatch=0.35, depth=3)
    ring_rivets(cv, hx, hy, 14.5, 14, 0.9)
    cv.stroke(ellipse_pts(hx, hy, 6, 4, 30) + [ellipse_pts(hx, hy, 6, 4, 30)[0]], 2.4, INK)
    cv.stroke(ellipse_pts(hx, hy, 6, 4, 30) + [ellipse_pts(hx, hy, 6, 4, 30)[0]], 1.2, "#8a8a8e")
    # overflow stub and gauge glass
    cv.part(cv.mask().circle(cx + 24, cy - 26, 6), "#2a2a2e", ow=1.8, shade=0.4, light=0.5, hatch=0, depth=1.5)
    cv.paint(cv.mask().circle(cx + 24, cy - 26, 3), "#0a0b0c")
    rust(cv, m, 0.55, "tank", 6, 6)
    # green-white limescale streaks running down the side from the overflow
    n = cv.noise(14, 3, 3, seed="lime")
    lime = m.arr * smoothstep(0.7, 0.95, n) * np.clip(1 - radial(cv.W, cv.H, (cx + 24) * cv.ss, (cy - 10) * cv.ss,
                                                                30 * cv.ss), 0, 1)
    cv.screen(lime, 0.4, (170, 190, 160))
    _ = rr
    return finish(cv, "furniture/water_tank.png")


def pipes():
    cv = F("pipes", 4, 1)
    W = cv.w
    # two pipes run along the wall (top edge) and continue past both ends so pieces chain up
    pipe(cv, [(-6, 9), (W + 6, 9)], 10, "#4a4a50")
    pipe(cv, [(-6, 23), (W + 6, 23)], 6, "#7a4e30")
    for x in (40, 168):
        flange(cv, x, 9, 5, 15)
    for x in (88, 216):
        flange(cv, x, 23, 4, 10, "#5a3a22")
    # wall brackets
    for x in (14, 120, 240):
        cv.part(cv.mask().rect(x - 2.5, 0, x + 2.5, 28, 1), "#2a2a2e", ow=1.2, shade=0.3, light=0.4, hatch=0, depth=1)
    # branch dropping toward the floor with an elbow and a dripping tap
    pipe(cv, [(196, 23), (196, 40)], 6, "#7a4e30")
    elbow = cv.mask().circle(196, 41, 4.5)
    cv.part(elbow, "#6a4228", ow=1.4, shade=0.4, light=0.4, hatch=0, depth=1)
    pipe(cv, [(196, 41), (212, 41)], 5, "#7a4e30")
    cv.part(cv.mask().rect(211, 37, 218, 45, 1.5), BRASS, ow=1.4, shade=0.4, light=0.5, hatch=0, depth=1)
    valve_wheel(cv, 128, 9, 8)
    rust(cv, cv.a > 0.5, 0.45, "p", 20, 3)
    # verdigris on the copper run
    n = cv.noise(24, 3, 3, seed="verd")
    cv.tint((cv.a > 0.5) * smoothstep(0.75, 0.95, n), (90, 130, 110), 0.5)
    cv.grain(0.07)
    cv.drop_shadow(2.0, 5.0, 2.5, 0.55)
    # damp puddle below the tap (drawn under, very soft)
    pud = cv.mask().ellipse(216, 52, 12, 6, wobble=1.5)
    pa = blur(pud.arr, 1.5 * cv.ss) * (1 - cv.a)
    cv.paint(pa, (18, 22, 26), 0.45)
    cv.paint(cv.mask().ellipse(213, 50, 4, 1.2).arr * (1 - cv.a), (170, 180, 190), 0.25)
    save(cv.image(), "furniture/pipes.png")


def boards():
    cv = F("boards", 2, 1)
    rr = cv.rnd
    for i, (cx, cy, ln, w, rot, broken) in enumerate(((62, 18, 104, 11, -4, False), (56, 33, 92, 10, 7, True),
                                                       (70, 42, 70, 9, -14, False))):
        c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
        P = lambda q: [(cx + px * c - py * s, cy + px * s + py * c) for px, py in q]
        if broken:
            shape = [(-ln / 2, -w / 2), (ln / 2 - 6, -w / 2), (ln / 2, -w / 2 + 2), (ln / 2 - 4, 0), (ln / 2 + 1, 2),
                     (ln / 2 - 5, w / 2), (-ln / 2, w / 2)]
        else:
            shape = rrect_pts(-ln / 2, -w / 2, ln / 2, w / 2, 1, 2)
        m = cv.mask().poly(P(shape), wobble=0.3)
        cv.part(m, wtex(cv, ["oak", "pine", "grey"][i], False, f"pl{i}", rings=3), ow=2.2, depth=1.8, hatch=0.45)
        for ex in (-ln / 2 + 5, ln / 2 - 9):
            cv.paint(cv.mask().circle(*P([(ex, 0)])[0], 1.0), "#2a2a2a")
        if broken:
            cv.stroke(P([(ln / 2 - 8, -1), (ln / 2 + 3, 0)]), 0.6, "#c8a070", 0.9)
    for _ in range(8):
        x, y = 10 + rr.random() * 108, 46 + rr.random() * 8
        a = rr.random() * math.pi
        cv.stroke([(x, y), (x + math.cos(a) * 4, y + math.sin(a) * 4)], 0.7, "#8a6a48", 0.9)
    # a bent nail
    cv.stroke([(20, 50), (24, 48), (26, 51)], 1.0, "#5a5a60")
    dust(cv, cv.a > 0.5, 0.22, "bd", 5, 3)
    return finish(cv, "furniture/boards.png", shadow=(2.0, 2.5, 1.8, 0.5))


def debris():
    cv = F("debris", 2, 2)
    rr = cv.rnd
    cx, cy = 62, 62
    # plaster dust fan
    dm = cv.mask().ellipse(cx, cy, 52, 44, wobble=6.0, rot=20)
    n = cv.noise(8, 8, 4, seed="pd")
    cv.paint(blur(dm.arr, 5 * cv.ss) * (0.4 + 0.6 * n), (168, 160, 146), 0.5)
    # lath strips
    for k in range(3):
        a = rr.normal(0, 0.6) + k * 1.1
        x, y = cx + rr.normal(0, 14), cy + rr.normal(0, 14)
        ln = 34 + rr.random() * 20
        p0 = (x - math.cos(a) * ln / 2, y - math.sin(a) * ln / 2)
        p1 = (x + math.cos(a) * ln / 2, y + math.sin(a) * ln / 2)
        lm = cv.mask().line([p0, p1], 3.6)
        cv.part(lm, wtex(cv, "pine", seed=f"lath{k}"), ow=1.4, shade=0.4, light=0.25, hatch=0, depth=1)
    # plaster/stone chunks
    for i in range(34):
        r_ = 2 + rr.random() ** 2 * 9
        x, y = cx + rr.normal(0, 20), cy + rr.normal(0, 17)
        k = int(rr.integers(5, 8))
        a0 = rr.random() * 6.28
        pts = [(x + math.cos(a0 + j * 6.28 / k) * r_ * (0.6 + 0.5 * rr.random()),
                y + math.sin(a0 + j * 6.28 / k) * r_ * (0.6 + 0.5 * rr.random())) for j in range(k)]
        c = mix("#b0a896", "#7a746a", rr.random()) if i % 5 else mix("#6a4a3a", "#8a5a44", rr.random())
        cv.part(cv.mask().poly(pts), c, ow=1.0 + r_ * 0.08, shade=0.45, light=0.3, hatch=0.3 if r_ > 6 else 0,
                depth=1 + r_ * 0.15)
        if r_ > 6 and i % 5:
            # painted face with a scrap of wallpaper
            cv.paint(cv.mask().poly([(px * 0.55 + x * 0.45, py * 0.55 + y * 0.45) for px, py in pts]), "#5a6a5a", 0.5)
    # splinters & grit
    for _ in range(40):
        x, y = cx + rr.normal(0, 26), cy + rr.normal(0, 22)
        a = rr.random() * math.pi
        if rr.random() < 0.4:
            cv.stroke([(x, y), (x + math.cos(a) * 5, y + math.sin(a) * 5)], 0.7, "#8a6a48", 0.9)
        else:
            cv.paint(cv.mask().circle(x, y, 0.5 + rr.random()), mix("#9a9286", INK, rr.random() * 0.6), 0.9)
    return finish(cv, "furniture/debris.png", shadow=(2.0, 2.5, 1.8, 0.45))


def photo_print(cv, x, y, w, h, rot, seed, subject=0):
    """small sepia photograph with a white border (for the big desk)."""
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    P = lambda q: [(x + px * c - py * s, y + px * s + py * c) for px, py in q]
    m = cv.mask().poly(P([(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]))
    cv.part(m, "#ddd4bc", ow=1.0, shade=0.25, light=0, hatch=0, depth=1.5)
    b = 2.5
    im = cv.mask().poly(P([(-w / 2 + b, -h / 2 + b), (w / 2 - b, -h / 2 + b), (w / 2 - b, h / 2 - b * 3),
                           (-w / 2 + b, h / 2 - b * 3)]))
    cv.paint(im, (118, 96, 70))
    cv.mul(im.arr * smoothstep(0.3, 0.9, cv.noise(6, 6, 3, seed=f"ph{seed}")), 0.4, (60, 40, 25))
    # a gabled house silhouette
    if subject == 0:
        hs = cv.mask().poly(P([(-w * 0.3, h * 0.18), (-w * 0.3, -h * 0.05), (0, -h * 0.3), (w * 0.3, -h * 0.05),
                               (w * 0.3, h * 0.18)]))
    else:
        hs = cv.mask().poly(P([(-w * 0.12, h * 0.2), (-w * 0.12, -h * 0.12), (0, -h * 0.25), (w * 0.12, -h * 0.12),
                               (w * 0.12, h * 0.2)]))
    cv.paint(hs, (40, 28, 20), 0.9)


def desk_large():
    cv = F("desk_large", 6, 4)
    x0, y0, x1, y1 = box(cv)
    rr = cv.rnd
    top = cv.mask().rect(x0, y0, x1, y1, 6, wobble=0.35)
    wood(cv, top, "mahogany", False, ow=4.0, depth=5)
    groove_rect(cv, x0 + 6, y0 + 6, x1 - 6, y1 - 6, 1.0, r=3)
    # leather blotter with brass corners
    bx0, by0, bx1, by1 = x0 + 92, y0 + 46, x1 - 92, y1 - 40
    lt = cv.mask().rect(bx0, by0, bx1, by1, 3)
    cv.part(lt, fab(cv, "#2c4636", 0.22), ow=2.0, shade=0.35, light=0.15, hatch=0.3, depth=3)
    cv.stroke(rrect_pts(bx0 + 4, by0 + 4, bx1 - 4, by1 - 4, 1, 2) + [(bx0 + 5, by0 + 4)], 0.8, BRASS, 0.7)
    cv.mul(lt.arr * smoothstep(0.65, 0.9, cv.noise(5, 4, 3, seed="bl")), 0.3, (20, 30, 20))
    for (xx, yy, sx, sy) in ((bx0, by0, 1, 1), (bx1, by0, -1, 1), (bx0, by1, 1, -1), (bx1, by1, -1, -1)):
        cv.part(cv.mask().poly([(xx, yy), (xx + 14 * sx, yy), (xx, yy + 14 * sy)]), BRASS, ow=1.2, shade=0.35,
                light=0.5, hatch=0, depth=1)
    # case papers and photographs scattered over the blotter
    for (px, py, w, h, r_) in ((bx0 + 50, by0 + 70, 46, 60, -9), (bx0 + 86, by0 + 64, 44, 58, 6),
                               (bx1 - 52, by0 + 58, 42, 56, 14), (bx0 + 118, by1 - 40, 40, 52, -3)):
        paper(cv, px, py, w, h, rot=r_)
    photo_print(cv, bx0 + 30, by1 - 34, 30, 36, 12, 1, 0)
    photo_print(cv, bx1 - 30, by1 - 32, 28, 34, -16, 2, 1)
    # red string across two papers
    cv.stroke([(bx0 + 52, by0 + 50), (bx1 - 50, by0 + 44)], 0.8, (140, 26, 24), 0.9)
    for (pxx, pyy) in ((bx0 + 52, by0 + 50), (bx1 - 50, by0 + 44)):
        cv.part(cv.mask().circle(pxx, pyy, 2.4), "#9a1e1c", ow=0.9, shade=0.3, light=0.6, hatch=0, depth=0.6)
    # brass lamp base with green banker's shade (back left), warm pool of light
    lx, ly = x0 + 46, y0 + 48
    cv.part(cv.mask().circle(lx, ly, 22), BRASS, ow=2.4, shade=0.45, light=0.5, hatch=0.25, depth=3)
    groove(cv, ellipse_pts(lx, ly, 16, 16, 50), 0.8, closed=True)
    sh = cv.mask().rect(lx - 30, ly - 12, lx + 30, ly + 12, 10)
    cv.part(sh, "#2e5a3e", ow=2.4, shade=0.45, light=0.55, hatch=0.2, depth=3)
    cv.stroke([(lx - 24, ly - 6), (lx + 24, ly - 6)], 1.0, (200, 230, 200), 0.4)
    cv.part(cv.mask().circle(lx, ly, 3.2), BRASS, ow=1.0, shade=0.3, light=0.5, hatch=0, depth=0.8)
    # inkwell and quill (back right), books stack (right)
    ix, iy = x1 - 46, y0 + 40
    cv.part(cv.mask().rect(ix - 11, iy - 11, ix + 11, iy + 11, 3), "#2c3238", ow=2.0, shade=0.4, light=0.5, hatch=0,
            depth=2)
    cv.part(cv.mask().circle(ix, iy, 6), BRASS, ow=1.2, shade=0.3, light=0.5, hatch=0, depth=1)
    cv.paint(cv.mask().circle(ix, iy, 3.4), "#08080b")
    q = cv.mask().curve([(ix - 2, iy - 2), (ix + 14, iy - 18), (ix + 30, iy - 28)], 3.0)
    cv.part(q, "#e2dccb", ow=1.0, shade=0.3, light=0, hatch=0, depth=1)
    cv.stroke([(ix, iy - 3), (ix + 28, iy - 27)], 0.6, INK, 0.7)
    from furniture import book
    book(cv, x1 - 42, y1 - 66, 40, 52, "#5a2526", rot=6)
    book(cv, x1 - 40, y1 - 70, 36, 46, "#2b3d52", rot=-7)
    book(cv, x1 - 41, y1 - 72, 30, 40, "#3d4a2c", rot=2)
    # ink spill & ring stains on the wood
    cv.paint(cv.mask().ellipse(ix - 20, iy + 22, 9, 5, wobble=1.2), (14, 12, 16), 0.75)
    for (rx, ry) in ((x0 + 40, y1 - 40), (x0 + 70, y1 - 26)):
        cv.stroke(ellipse_pts(rx, ry, 10, 10, 40, 0, 20, 330), 1.0, (40, 18, 10), 0.4)
    # drawers' brass pulls along the front edge
    for xx in (x0 + 60, x0 + 130, x1 - 130, x1 - 60):
        knob(cv, xx, y1 - 2, 2.6)
    _ = rr
    cv.grain(0.07)
    cv.drop_shadow(3, 4, 2.5, 0.55)
    g = np.clip(1 - radial(cv.W, cv.H, lx * cv.ss, (ly + 26) * cv.ss, 120 * cv.ss), 0, 1) ** 2.2
    cv.glow(g * top.arr, (255, 180, 90), 0.3)
    save(cv.image(), "furniture/desk_large.png")


# --------------------------------------------------------------------------
# stairs & hatch (walkable 1x1 tiles, fill the whole cell)
# --------------------------------------------------------------------------
def _stairs(name, down):
    cv = Canvas(64, 64, 4, name=name)
    rr = cv.rnd
    n = 6
    # treads from far (top, i=0) to near (bottom, i=n-1)
    edge = cv.mask().rect(0, 0, 64, 64)
    cv.paint(edge, stone_tex(cv, "#5a5650", "edge"))
    cv.vary(edge.arr, 0.12, 6, 6)
    ys = np.linspace(0, 64, n + 1)
    for i in range(n):
        t = i / (n - 1)  # 0 far .. 1 near
        # taper: away = narrower for a descent, wider for a climb
        inset = (14 - 9 * t) if down else (4 + 10 * t)
        if down:
            tone = 0.18 + 0.82 * t  # far edge darker
        else:
            tone = 1.25 - 0.8 * t  # far edge lighter
        ya, yb = ys[i] + 0.6, ys[i + 1] - 0.6
        tm = cv.mask().rect(inset, ya, 64 - inset, yb, 0.8)
        tex = wtex(cv, "oak", seed=f"tr{i}", rings=3) * tone
        cv.paint(dilate(tm.arr, 0.9 * cv.ss), INK)
        cv.paint(tm, tex)
        cv.hatch(tm.arr, 45, 2.2, 0.6, 0.55 * (1 - tone) + 0.1)
        if down:
            # nosing (lit front lip) on the far edge of each tread, shadow cast on the next tread down
            cv.paint(cv.mask().rect(inset + 0.5, ya, 64 - inset - 0.5, ya + 1.4), (230, 210, 170), 0.35 * tone + 0.1)
            cv.mul(cv.mask().rect(inset, yb - 2.6, 64 - inset, yb).arr, 0.4, (10, 8, 8))
        else:
            # the next tread up overhangs: lit nosing at the near edge, shadow at the far edge
            cv.paint(cv.mask().rect(inset + 0.5, yb - 1.4, 64 - inset - 0.5, yb), (235, 215, 175), 0.45 * tone)
            cv.mul(cv.mask().rect(inset, ya, 64 - inset, ya + 2.4).arr, 0.45, (10, 8, 8))
        for ex in (inset + 3, 64 - inset - 3):
            cv.paint(cv.mask().circle(ex, (ya + yb) / 2, 0.6), "#1a1a1a", 0.8)
    # side stringers / stone edging
    for side in (0, 1):
        pts = ([(0, 0), (14 if down else 4, 0), (5 if down else 14, 64), (0, 64)] if side == 0 else
               [(64, 0), (50 if down else 60, 0), (59 if down else 50, 64), (64, 64)])
        sm = cv.mask().poly(pts)
        cv.paint(sm, stone_tex(cv, "#6a665e", f"s{side}"))
        cv.stroke([pts[1], pts[2]], 1.4, INK, 0.9)
        cv.screen(edge_band(sm.arr, -2 * cv.ss, 0, 2 * cv.ss), 0.2)
        for k in range(4):
            yy = 8 + k * 16 + rr.normal(0, 1.5)
            x_in = pts[1][0] + (pts[2][0] - pts[1][0]) * yy / 64
            cv.stroke([(pts[0][0], yy), (x_in, yy)], 0.6, INK, 0.6)
    # depth falloff over everything for the descent; light spill for the climb
    yy = np.arange(cv.H)[:, None] / cv.H
    if down:
        cv.mul(np.broadcast_to(smoothstep(0.75, 0.0, yy), (cv.H, cv.W)) * np.ones((cv.H, cv.W)), 0.75, (4, 4, 8))
    else:
        cv.screen(np.broadcast_to(smoothstep(0.7, 0.0, yy), (cv.H, cv.W)) * np.ones((cv.H, cv.W)), 0.3,
                  (220, 210, 190))
        cv.mul(np.broadcast_to(smoothstep(0.45, 1.0, yy), (cv.H, cv.W)) * np.ones((cv.H, cv.W)), 0.45, (10, 10, 14))
    dust(cv, edge.arr, 0.12, "st", 4, 4)
    # outer ink frame
    cv.stroke([(0.8, 0.8), (63.2, 0.8), (63.2, 63.2), (0.8, 63.2), (0.8, 0.8)], 1.6, INK, 0.9)
    cv.grain(0.07)
    save(cv.image(), f"furniture/{name}.png")


def stairs_down():
    _stairs("stairs_down", True)


def stairs_up():
    _stairs("stairs_up", False)


def hatch():
    cv = Canvas(64, 64, 4, name="hatch")
    cv._glows = []
    # floor frame (heavy joists)
    fr = cv.mask().rect(3, 20, 61, 62, 1.5)
    cv.part(fr, wtex(cv, "walnut", False, "fr", rings=4), ow=2.2, depth=1.5, hatch=0.45)
    # the pit: falls off to black
    pit = cv.mask().rect(9, 25, 55, 57, 0.8)
    yy = np.arange(cv.H)[:, None] / cv.H
    cv.paint(pit, (22, 18, 16))
    cv.mul(pit.arr * np.broadcast_to(smoothstep(0.45, 0.95, yy), (cv.H, cv.W)), 0.85, (0, 0, 0))
    cv.mul(edge_band(pit.arr, -3 * cv.ss, -3 * cv.ss, 2 * cv.ss), 0.6, (0, 0, 0))
    # ladder descending (rails + rungs fading into the dark)
    for x in (22, 42):
        lm = cv.mask().line([(x, 25), (x, 57)], 2.6)
        cv.part(lm, wtex(cv, "pine", True, seed=f"r{x}"), ow=1.0, shade=0.3, light=0.3, hatch=0, depth=0.8)
    for k in range(5):
        y = 29 + k * 6.5
        rm = cv.mask().rect(22, y - 1.1, 42, y + 1.1, 0.4)
        cv.part(rm, wtex(cv, "pine", seed=f"rung{k}"), ow=0.8, shade=0.3, light=0.25, hatch=0, depth=0.5)
    cv.mul(pit.arr * np.broadcast_to(smoothstep(0.5, 0.92, yy), (cv.H, cv.W)), 0.8, (0, 0, 0))
    # the hatch door, flipped open, lying back flat on the floor behind the opening
    dr = cv.mask().rect(6, 1, 58, 19, 1.0, wobble=0.15)
    wood(cv, dr, "oak", True, "door", ow=2.2, depth=1.5)
    for x in (19, 32, 45):
        cv.stroke([(x, 2), (x, 18)], 0.7, INK, 0.8)
    for x in (14, 50):
        cv.part(cv.mask().rect(x - 2.5, 14, x + 2.5, 24, 0.6), IRON, ow=0.8, shade=0.3, light=0.5, hatch=0, depth=0.6)
    cv.stroke(ellipse_pts(32, 6, 4, 2.6, 24, 0, 0, 180), 1.2, INK)
    cv.stroke(ellipse_pts(32, 6, 4, 2.6, 24, 0, 0, 180), 0.6, "#8a8a8e")
    cv.grain(0.07)
    cv.drop_shadow(0.8, 1.2, 1.0, 0.5)
    save(cv.image(), "furniture/hatch.png")


# --------------------------------------------------------------------------
# neglect overlays (512x512 tileable, transparent)
# --------------------------------------------------------------------------
def radial_wrap(W, H, cx, cy, r):
    x = np.arange(W)[None, :] - cx
    y = np.arange(H)[:, None] - cy
    x = (x + W / 2) % W - W / 2
    y = (y + H / 2) % H - H / 2
    return np.sqrt(x * x + y * y) / max(r, 1e-6)


def _overlay(name):
    return Canvas(512, 512, 1, tile=True, name=f"decor:{name}")


def grime():
    cv = _overlay("grime")
    rr = cv.rnd
    n = cv.noise(4, 4, 5, seed="soot")
    n2 = cv.noise(12, 12, 3, seed="soot2")
    soot = smoothstep(0.55, 0.95, n * 0.75 + n2 * 0.35)
    cv.paint(soot, (26, 24, 22), 0.32)
    dustm = smoothstep(0.6, 0.95, cv.noise(6, 6, 4, seed="dust"))
    cv.paint(dustm, (150, 142, 126), 0.14)
    # scuffs: short curved arcs
    for _ in range(60):
        x, y = rr.random() * 512, rr.random() * 512
        a = rr.random() * 6.28
        ln = 6 + rr.random() * 22
        pts = [(x + math.cos(a + 0.4 * t) * ln * t, y + math.sin(a + 0.4 * t) * ln * t) for t in np.linspace(0, 1, 5)]
        cv.paint(cv.mask().line(pts, 0.6 + rr.random() * 1.6), (30, 26, 24), 0.12 + rr.random() * 0.12)
    # specks
    for _ in range(900):
        x, y = rr.random() * 512, rr.random() * 512
        dark = rr.random() < 0.7
        cv.paint(cv.mask().circle(x, y, 0.5 + rr.random() ** 3 * 1.6), (24, 22, 20) if dark else (175, 165, 145),
                 0.25 + rr.random() * 0.3)
    save(cv.image(), "decor/grime.png")


def damp():
    cv = _overlay("damp")
    rr = cv.rnd
    n = cv.noise(3, 3, 5, seed="d")
    w = cv.noise(10, 10, 3, seed="dw")
    f = n * 0.85 + w * 0.15
    # stained areas (graded), tide-mark rings at several water levels
    cv.paint(smoothstep(0.55, 0.75, f), (62, 56, 36), 0.22)
    cv.paint(smoothstep(0.7, 0.88, f), (46, 44, 28), 0.2)
    for lvl, op in ((0.57, 0.38), (0.63, 0.28), (0.72, 0.42), (0.8, 0.3)):
        ring = np.exp(-((f - lvl) / 0.006) ** 2)
        cv.paint(ring, (58, 40, 22), op)
    # mould blooms: clusters of dark-green specks with soft halos
    mo = cv.noise(8, 8, 4, seed="m")
    centres = []
    for _ in range(4000):
        x, y = rr.random() * 512, rr.random() * 512
        if mo[int(y), int(x)] > 0.78 and f[int(y), int(x)] > 0.5:
            centres.append((x, y))
        if len(centres) > 26:
            break
    for (cx, cy) in centres:
        halo = np.clip(1 - radial_wrap(512, 512, cx, cy, 18 + rr.random() * 16), 0, 1) ** 1.5
        cv.paint(halo, (44, 48, 32), 0.2)
        for _ in range(int(30 + rr.random() * 50)):
            r_ = abs(rr.normal(0, 9))
            a = rr.random() * 6.28
            cv.paint(cv.mask().circle(cx + math.cos(a) * r_, cy + math.sin(a) * r_, 0.6 + rr.random() * 1.8),
                     mix("#2c3424", "#121410", rr.random()), 0.25 + rr.random() * 0.3)
    # drip streaks
    for _ in range(14):
        x, y = rr.random() * 512, rr.random() * 512
        ln = 20 + rr.random() * 60
        cv.paint(cv.mask().line([(x, y), (x + rr.normal(0, 2), y + ln)], 1.5 + rr.random() * 2.5), (50, 42, 26), 0.14)
    save(cv.image(), "decor/damp.png")


def cracks():
    cv = _overlay("cracks")
    rr = cv.rnd

    def walk(x, y, a, length, width, op, depth):
        pts = [(x, y)]
        for _ in range(int(length / 3)):
            a += rr.normal(0, 0.2)
            x += math.cos(a) * 3
            y += math.sin(a) * 3
            pts.append((x, y))
        cv.paint(cv.mask().line([(px + 0.8, py + 0.8) for px, py in pts], width * 0.9), (190, 182, 166), op * 0.25)
        cv.paint(cv.mask().line(pts, width), (14, 12, 12), op)
        if depth > 0:
            for _ in range(int(rr.integers(1, 4))):
                i = int(rr.integers(1, len(pts)))
                bx, by = pts[i]
                walk(bx, by, a + rr.choice([-1, 1]) * (0.5 + rr.random() * 0.7), length * (0.3 + rr.random() * 0.3),
                     width * 0.65, op * 0.85, depth - 1)

    for _ in range(9):
        walk(rr.random() * 512, rr.random() * 512, rr.random() * 6.28, 80 + rr.random() * 140, 1.5, 0.75, 2)
    # crazing: small polygonal web in a few spots
    for _ in range(5):
        cx, cy = rr.random() * 512, rr.random() * 512
        for _ in range(10):
            walk(cx + rr.normal(0, 8), cy + rr.normal(0, 8), rr.random() * 6.28, 10 + rr.random() * 18, 0.7, 0.4, 0)
    save(cv.image(), "decor/cracks.png")


def cobweb():
    cv = Canvas(64, 64, 4, name="decor:cobweb")
    rr = cv.rnd
    silk = (222, 220, 214)
    n = 9
    spokes = []
    for k in range(n):
        a = (k / (n - 1)) * (math.pi / 2) * 0.96 + 0.02
        L = 60 + rr.normal(0, 4) - 12 * math.sin(2 * a) * 0.4
        spokes.append((a, L))
        cv.paint(cv.mask().line([(0, 0), (math.cos(a) * L, math.sin(a) * L)], 0.75), silk, 0.85)
    # sagging spiral threads between adjacent spokes
    for f in np.linspace(0.14, 0.92, 9):
        for k in range(n - 1):
            (a0, L0), (a1, L1) = spokes[k], spokes[k + 1]
            r0, r1 = L0 * f * (1 + rr.normal(0, 0.03)), L1 * f * (1 + rr.normal(0, 0.03))
            p0 = (math.cos(a0) * r0, math.sin(a0) * r0)
            p1 = (math.cos(a1) * r1, math.sin(a1) * r1)
            mid = ((p0[0] + p1[0]) / 2 * 0.93, (p0[1] + p1[1]) / 2 * 0.93)
            if rr.random() < 0.12:
                continue  # broken strand
            cv.paint(cv.mask().curve([p0, mid, p1], 0.6, n=8), silk, 0.62 + 0.25 * (1 - f))
    # dense dusty mat in the very corner + a couple of torn hanging strands
    cv.paint(blur(cv.mask().poly([(0, 0), (20, 0), (8, 8), (0, 20)]).arr, 2.0 * cv.ss), (205, 200, 190), 0.7)
    for _ in range(3):
        a = rr.random() * math.pi / 2
        p = (math.cos(a) * 30, math.sin(a) * 30)
        cv.paint(cv.mask().curve([p, (p[0] + 6, p[1] + 10), (p[0] + 4, p[1] + 22)], 0.4, n=8), silk, 0.45)
    # dust caught on the threads
    for _ in range(30):
        a = rr.random() * math.pi / 2
        r_ = rr.random() ** 1.5 * 50
        cv.paint(cv.mask().circle(math.cos(a) * r_, math.sin(a) * r_, 0.4 + rr.random() * 0.8), (190, 185, 172), 0.6)
    # an ink-dark husk of a fly
    cv.paint(cv.mask().ellipse(22, 18, 1.6, 1.1, rot=30), INK, 0.85)
    save(cv.image(), "decor/cobweb.png")


def stain(idx):
    cv = Canvas(128, 128, 2, name=f"decor:stain_{idx}")
    rr = cv.rnd
    if idx == 1:  # water stain with tide rings
        m = cv.mask().ellipse(64, 64, 50, 42, wobble=7.0, rot=20)
        cols = ((70, 60, 38), (52, 38, 22))
    elif idx == 2:  # greenish mould-edged damp patch
        m = cv.mask().ellipse(62, 66, 46, 50, wobble=9.0, rot=-30)
        cols = ((52, 60, 38), (36, 46, 26))
    else:  # dark spill (oil / old wine)
        m = cv.mask().ellipse(64, 62, 38, 30, wobble=8.0, rot=60)
        m.ellipse(92, 88, 12, 9, wobble=3.0)
        m.ellipse(30, 34, 6, 5, wobble=2.0)
        cols = ((40, 22, 22), (24, 12, 12))
    a = blur(m.arr, 2.0 * cv.ss)
    n = cv.noise(5, 5, 4, seed="s")
    f = a * (0.75 + 0.5 * n)
    cv.paint(smoothstep(0.1, 0.6, f), cols[0], 0.35 if idx != 3 else 0.6)
    cv.paint(smoothstep(0.55, 0.9, f), cols[0], 0.2)
    # tide edge
    edge = np.exp(-((a - 0.5) / 0.12) ** 2)
    cv.paint(edge, cols[1], 0.55 if idx != 3 else 0.7)
    if idx in (1, 2):
        inner = erode(m.arr, 10 * cv.ss)
        cv.paint(np.exp(-((blur(inner, 3 * cv.ss) - 0.5) / 0.1) ** 2) * 0.8, cols[1], 0.3)
    if idx == 2:
        for _ in range(160):
            ang = rr.random() * 6.28
            rad = 38 + rr.normal(0, 7)
            cv.paint(cv.mask().circle(62 + math.cos(ang) * rad, 66 + math.sin(ang) * rad * 1.05,
                                      0.6 + rr.random() * 1.6), mix("#2a3a1e", "#10120c", rr.random()),
                     0.3 + rr.random() * 0.4)
    if idx == 3:
        cv.paint(cv.mask().ellipse(52, 52, 10, 4, rot=60), (170, 150, 150), 0.12)
    save(cv.image(), f"decor/stain_{idx}.png")


def peel():
    """peeling wallpaper strip: the wall runs along the TOP edge, paper curls off it toward the floor."""
    cv = Canvas(128, 32, 4, name="decor:peel")
    rr = cv.rnd
    # faded damask-stripe wallpaper texture
    xs = np.arange(cv.W)[None, :] / cv.ss
    ys = np.arange(cv.H)[:, None] / cv.ss
    base = np.zeros((cv.H, cv.W, 3), np.float32) + col("#56624f")
    stripe = (np.abs((xs % 14) - 7) < 1.0).astype(np.float32)
    dots = ((np.sin(xs * 0.9) * np.sin(ys * 0.9 + (xs // 14) * 1.5)) > 0.7).astype(np.float32)
    base = base * (1 - 0.2 * stripe[..., None]) + col("#9a8f6c") * (0.3 * stripe + 0.22 * dots)[..., None]
    base *= (0.82 + 0.3 * cv.noise(8, 2, 3, seed="p"))[..., None]
    # three torn flaps hanging off the wall line, each ending in a rolled curl showing the pale backing
    flaps = ((2, 40, 17), (44, 86, 24), (90, 126, 13))
    for i, (fx0, fx1, depth) in enumerate(flaps):
        pts = [(fx0, 0), (fx1, 0)]
        n = 7
        for k in range(n + 1):
            t = 1 - k / n
            x = fx0 + (fx1 - fx0) * t
            env = math.sin(math.pi * (0.08 + 0.84 * t)) ** 0.6 * (0.55 + 0.45 * t if i % 2 else 1.0 - 0.45 * t)
            pts.append((x, 2 + depth * env + rr.normal(0, 1.0)))
        m = cv.mask().poly(pts, wobble=0.5)
        cv.part(m, base, ow=1.5, shade=0.5, light=0.15, hatch=0.4, depth=3)
        # stained top edge where the paste failed (damp)
        cv.mul(m.arr * smoothstep(0.45, 0.0, ys / 32) * (0.5 + 0.5 * cv.noise(10, 2, 3, seed=f"dm{i}")), 0.4,
               (40, 36, 20))
        # rolled curl (a cylinder of paper back) along the lower edge
        cx = (fx0 + fx1) / 2
        w = (fx1 - fx0) * 0.7
        yb = 2 + depth * 0.62
        curl = cv.mask().poly(ellipse_pts(cx, yb, w / 2, 3.4, 40, -4 if i % 2 else 4), wobble=0.3)
        cv.part(curl, "#bfb293", ow=1.2, shade=0.55, light=0.35, hatch=0.3, depth=2.2)
        cv.stroke(catmull([(cx - w / 2 + 2, yb), (cx, yb + 0.8), (cx + w / 2 - 2, yb)], 6), 0.6, INK, 0.55)
        cv.mul(blur(cv.mask().rect(cx - w / 2, yb - 6, cx + w / 2, yb - 3, 1).arr, cv.ss) * m.arr, 0.5, (10, 8, 6))
    # a fallen scrap on the floor
    sc = cv.mask().poly([(84, 26), (95, 24), (99, 30), (88, 31)], wobble=0.4)
    cv.part(sc, base, ow=1.0, shade=0.3, light=0.1, hatch=0, depth=1)
    cv.grain(0.06)
    cv.drop_shadow(1.0, 2.0, 1.5, 0.5)
    save(cv.image(), "decor/peel.png")


def dust_sheet_scrap():
    cv = Canvas(64, 64, 4, name="decor:dust_sheet_scrap")
    rr = cv.rnd
    m = cv.mask().poly(ellipse_pts(32, 32, 24, 18, 40, 25), wobble=4.0, step=2)
    cv.part(m, fab(cv, "#6f6c65", 0.14, 2.0), ow=2.0, shade=0.45, light=0.1, hatch=0.4, soft=0.4, depth=3)
    h = blur(cv.mask().ellipse(28, 28, 10, 8).arr + cv.mask().ellipse(40, 38, 8, 6).arr * 0.7, 3 * cv.ss)
    relief(cv, h, m.arr, 0.22, 0.5, 8.0)
    sheet_folds(cv, m.arr, rr, 8, (12, 16, 52, 48), length=(6, 16))
    cv.mul(m.arr * smoothstep(0.7, 0.95, cv.noise(5, 5, 3, seed="g")), 0.35, (60, 55, 40))
    cv.grain(0.06)
    cv.drop_shadow(1.0, 1.4, 1.2, 0.5)
    save(cv.image(), "decor/dust_sheet_scrap.png")


def rubble():
    cv = Canvas(64, 64, 4, name="decor:rubble")
    rr = cv.rnd
    dm = cv.mask().ellipse(32, 34, 24, 18, wobble=3.0)
    cv.paint(blur(dm.arr, 3 * cv.ss), (160, 152, 138), 0.4)
    for i in range(12):
        r_ = 2 + rr.random() ** 1.5 * 7
        x, y = 32 + rr.normal(0, 9), 33 + rr.normal(0, 7)
        k = int(rr.integers(5, 8))
        a0 = rr.random() * 6.28
        pts = [(x + math.cos(a0 + j * 6.28 / k) * r_ * (0.6 + 0.5 * rr.random()),
                y + math.sin(a0 + j * 6.28 / k) * r_ * (0.6 + 0.5 * rr.random())) for j in range(k)]
        c = mix("#a8a090", "#6e685e", rr.random()) if i % 4 else mix("#6a4636", "#84543e", rr.random())
        cv.part(cv.mask().poly(pts), c, ow=1.0, shade=0.45, light=0.3, hatch=0.2, depth=1.2)
    for _ in range(26):
        x, y = 32 + rr.normal(0, 13), 34 + rr.normal(0, 10)
        cv.paint(cv.mask().circle(x, y, 0.4 + rr.random() * 0.9), mix("#9a9286", INK, rr.random() * 0.6), 0.9)
    cv.grain(0.06)
    cv.drop_shadow(1.0, 1.4, 1.0, 0.5)
    save(cv.image(), "decor/rubble.png")


def papers_scattered():
    cv = Canvas(64, 64, 4, name="decor:papers_scattered")
    cv._glows = []
    for (x, y, w, h, r_) in ((24, 26, 22, 28, -18), (38, 34, 20, 26, 12), (30, 44, 18, 14, 40)):
        paper(cv, x, y, w, h, rot=r_)
    # muddy footprint smear and water spotting so they read as litter, not a pickup
    n = cv.noise(4, 4, 3, seed="m")
    cv.mul((cv.a > 0.5) * smoothstep(0.45, 0.9, n), 0.45, (60, 45, 30))
    cv.mul(cv.mask().ellipse(36, 30, 7, 11, rot=20, wobble=1.0).arr * (cv.a > 0.5), 0.35, (50, 40, 30))
    cv.grain(0.06)
    cv.drop_shadow(0.8, 1.0, 0.8, 0.45)
    save(cv.image(), "decor/papers_scattered.png")


def rat():
    cv = Canvas(64, 64, 4, name="decor:rat")
    rr = cv.rnd
    fur = noise_tex(cv.W, cv.H, cv.rnd, "#4a423a", 0.2, 20, 20)
    # tail
    tail = cv.mask().curve([(22, 38), (14, 44), (10, 52), (16, 58), (26, 57)], 1.6)
    cv.part(tail, "#8a6e64", ow=1.0, shade=0.3, light=0.3, hatch=0, depth=0.6)
    # body (pear shape, head toward upper right)
    body = cv.mask().poly(catmull([(22, 40), (20, 30), (28, 22), (38, 18), (44, 20), (42, 28), (34, 38), (26, 42)],
                                  8), wobble=0.4)
    cv.part(body, fur, ow=1.8, shade=0.45, light=0.3, hatch=0.4, depth=2.5)
    head = cv.mask().poly(catmull([(38, 18), (46, 13), (52, 11), (48, 18), (44, 22)], 8))
    cv.part(head, fur, ow=1.6, shade=0.4, light=0.3, hatch=0.3, depth=1.5)
    for (ex, ey) in ((42, 14), (47, 19)):
        cv.part(cv.mask().ellipse(ex, ey, 2.6, 2.0), "#7a5a54", ow=0.9, shade=0.3, light=0.2, hatch=0, depth=0.6)
    cv.paint(cv.mask().circle(51.5, 11.5, 0.9), "#c08a84")
    for s_ in (-1, 1):
        cv.stroke([(51, 12), (55, 12 + s_ * 3)], 0.3, (200, 195, 185), 0.6)
    cv.paint(cv.mask().circle(47, 14.5, 0.7), (230, 200, 120), 0.9)  # glinting eye
    # fur strokes along the spine
    for k in range(12):
        t = k / 11
        x, y = 24 + 16 * t, 36 - 16 * t
        cv.stroke([(x, y), (x - 2 + rr.normal(0, 0.5), y + 2.5)], 0.4, INK, 0.5)
    cv.grain(0.06)
    cv.drop_shadow(1.0, 1.4, 1.0, 0.5)
    save(cv.image(), "decor/rat.png")


FURNITURE2 = [boiler, wine_rack, coal_pile, storage_shelf, covered_armchair, covered_sofa, broken_chair, old_trunk,
              water_tank, pipes, boards, debris, desk_large, stairs_down, stairs_up, hatch]
DECOR = [grime, damp, cracks, cobweb, lambda: stain(1), lambda: stain(2), lambda: stain(3), peel, dust_sheet_scrap,
         rubble, papers_scattered, rat]


def build_furniture(only=None):
    for f in FURNITURE2:
        if only and f.__name__ not in only:
            continue
        f()


def build_decor(only=None):
    for f in DECOR:
        nm = getattr(f, "__name__", "")
        if only and nm not in only and not (nm == "<lambda>" and "stain" in only):
            continue
        f()


if __name__ == "__main__":
    import sys
    a = sys.argv[1:]
    build_furniture(a or None)
    build_decor(a or None)
