"""Menu background: moonlit gothic manor on a hill (1920x1080)."""
from __future__ import annotations

import math

import numpy as np

from core import (Canvas, INK, blur, catmull, col, dilate, fbm, gradient, pnoise, radial, rng, save, smoothstep,
                  edge_band)

W, H = 1920, 1080
MOON = (1680.0, 215.0, 100.0)


def tree(m, x, y, ang, ln, w, depth, r):
    if depth == 0 or ln < 4:
        return
    pts = [(x, y)]
    a = ang
    seg = 5
    for i in range(seg):
        a += r.normal(0, 0.12)
        x += math.cos(a) * ln / seg
        y += math.sin(a) * ln / seg
        pts.append((x, y))
    m.line(pts, max(0.8, w))
    n = 2 if depth > 2 else int(r.integers(1, 3))
    for k in range(n + (1 if r.random() < 0.3 else 0)):
        na = a + r.normal(0, 0.55) + (-0.45 if k == 0 else 0.45)
        tree(m, x, y, na, ln * (0.62 + r.random() * 0.2), w * 0.62, depth - 1, r)


def crow(m, x, y, s, flap):
    pts = [(x - 14 * s, y - 4 * s * flap), (x - 7 * s, y - 1 * s), (x - 2 * s, y + 1 * s), (x, y - 1 * s),
           (x + 2 * s, y + 1 * s), (x + 7 * s, y - 1 * s), (x + 14 * s, y - 5 * s * flap), (x + 8 * s, y + 1.5 * s),
           (x + 3 * s, y + 3 * s), (x, y + 2.2 * s), (x - 3 * s, y + 3 * s), (x - 8 * s, y + 1.5 * s)]
    m.poly(pts)


def manor(cv, x0, base_y):
    """Return (silhouette mask, window list)."""
    m = cv.mask()
    wins = []
    # main hall block
    m.rect(x0, base_y - 150, x0 + 330, base_y)
    # steep gabled roof over main block
    m.poly([(x0 - 10, base_y - 150), (x0 + 165, base_y - 250), (x0 + 340, base_y - 150)])
    # left wing with two gables
    m.rect(x0 - 170, base_y - 110, x0 + 5, base_y)
    m.poly([(x0 - 180, base_y - 110), (x0 - 125, base_y - 185), (x0 - 70, base_y - 110)])
    m.poly([(x0 - 80, base_y - 110), (x0 - 35, base_y - 170), (x0 + 10, base_y - 110)])
    # right tower with spire
    tx = x0 + 300
    m.rect(tx, base_y - 260, tx + 80, base_y)
    m.poly([(tx - 8, base_y - 260), (tx + 40, base_y - 440), (tx + 88, base_y - 260)])
    m.line([(tx + 40, base_y - 440), (tx + 40, base_y - 478)], 3)
    m.line([(tx + 30, base_y - 466), (tx + 50, base_y - 466)], 2.5)
    # small turret on the left wing
    m.rect(x0 - 205, base_y - 170, x0 - 160, base_y)
    m.poly([(x0 - 212, base_y - 170), (x0 - 182, base_y - 255), (x0 - 152, base_y - 170)])
    # chimneys
    for cx_, h in ((x0 + 60, 225), (x0 + 250, 205), (x0 - 140, 175)):
        m.rect(cx_, base_y - h - 30, cx_ + 18, base_y - h + 30)
        m.rect(cx_ - 4, base_y - h - 36, cx_ + 22, base_y - h - 28)
    # dormers on main roof
    for dx in (95, 230):
        m.poly([(x0 + dx - 20, base_y - 150), (x0 + dx - 20, base_y - 185), (x0 + dx, base_y - 205),
                (x0 + dx + 20, base_y - 185), (x0 + dx + 20, base_y - 150)])
        wins.append((x0 + dx - 8, base_y - 185, 16, 24, 0.7))
    # finials
    for (fx, fy) in ((x0 + 165, base_y - 250), (x0 - 125, base_y - 185), (x0 - 35, base_y - 170),
                     (x0 - 182, base_y - 255)):
        m.line([(fx, fy), (fx, fy - 22)], 2.4)
    # windows: rows
    r = rng("manor_win")
    for row in range(2):
        for k in range(6):
            wx = x0 + 22 + k * 52
            wy = base_y - 128 + row * 64
            lit = r.random() < 0.45
            wins.append((wx, wy, 22, 40, 1.0 if lit else 0.0))
    for k in range(3):
        wins.append((x0 - 150 + k * 52, base_y - 80, 22, 40, 1.0 if r.random() < 0.5 else 0.0))
    for row in range(3):
        wins.append((tx + 28, base_y - 230 + row * 70, 24, 44, 1.0 if row != 1 else 0.0))
    wins.append((x0 - 190, base_y - 140, 14, 28, 1.0))
    # great door
    m2 = cv.mask()
    return m, wins


def menu_background():
    cv = Canvas(W, H, 2, name="menu_bg")
    ss = cv.ss
    r = cv.rnd
    WW, HH = cv.W, cv.H
    mx, my, mr = MOON
    # --- sky
    y = np.linspace(0, 1, HH, dtype=np.float32)[:, None]
    top, hor = col("#060a12"), col("#22324a")
    sky = top + (hor - top) * (y ** 1.3)[..., None]
    sky = np.broadcast_to(sky, (HH, WW, 3)).copy()
    halo = np.clip(1 - radial(WW, HH, mx * ss, my * ss, 760 * ss), 0, 1) ** 2.2
    sky += halo[..., None] * col("#5a6f8c") * 0.75
    cv.rgb[:] = sky
    cv.a[:] = 1
    # stars
    stars = cv.mask()
    for _ in range(420):
        sx, sy = r.random() * W, r.random() * 640
        if math.hypot(sx - mx, sy - my) < 260:
            continue
        rr = 0.5 + r.random() ** 4 * 1.6
        stars.circle(sx, sy, rr, fill=int(90 + 165 * r.random()))
    cv.paint(stars, (220, 228, 240))
    # clouds: stretched fbm, lit near the moon
    cl = fbm(WW, HH, 3, 9, rng("clouds"), 6)
    cl2 = fbm(WW, HH, 2, 6, rng("clouds2"), 5)
    band = smoothstep(0.0, 0.25, y) * smoothstep(0.75, 0.35, y)
    cm = smoothstep(0.55, 0.85, cl * 0.7 + cl2 * 0.5 - 0.1) * band[:, :]
    lit = np.clip(halo * 1.6, 0, 1)
    ccol = col("#2a3446")[None, None, :] * (1 - lit[..., None]) + col("#9aa8bc")[None, None, :] * lit[..., None]
    cv.tint(cm * 0.85, ccol, 1.0)
    rim = np.clip(cm - np.roll(cm, (int(6 * ss), int(-6 * ss)), (0, 1)), 0, 1)
    cv.screen(rim * lit, 0.6, (230, 236, 245))
    # sky engraving hatch
    cv.hatch(np.clip(1 - halo * 1.4, 0, 1) * smoothstep(0.7, 0.0, y[:, 0])[:, None] * np.ones((1, WW)), 20, 7.0,
             0.7, 0.14, color=(0, 0, 0), dash=40)
    # --- moon
    moon = cv.mask().circle(mx, my, mr)
    mt = col("#ece6d2")[None, None, :] * (0.88 + 0.16 * fbm(WW, HH, 60, 34, rng("moon"), 4)[..., None])
    cv.paint(blur(moon.arr, 18 * ss), (230, 236, 240), 0.5)
    cv.paint(moon, mt)
    for _ in range(22):
        a = r.random() * 2 * math.pi
        d = r.random() ** 0.7 * mr * 0.8
        cr = 4 + r.random() ** 2 * 22
        c = cv.mask().circle(mx + math.cos(a) * d, my + math.sin(a) * d, cr)
        cv.mul(c.arr * moon.arr, 0.18, (120, 120, 140))
        cv.screen(edge_band(c.arr, 2 * ss, 2 * ss, 2 * ss) * moon.arr, 0.25)
    cv.mul(edge_band(moon.arr, -18 * ss, 18 * ss, 14 * ss), 0.35, (90, 100, 130))
    cv.hatch(edge_band(moon.arr, -16 * ss, 16 * ss, 12 * ss), -40, 3.2, 0.7, 0.35, color=(70, 76, 96))
    # thin cloud across the moon
    tc = smoothstep(0.55, 0.8, fbm(WW, HH, 3, 14, rng("thincloud"), 5)) * smoothstep(0.32, 0.22, np.abs(y - my / H))
    cv.tint(tc * 0.3, (70, 80, 100), 1.0)
    # --- far hills
    xs = np.arange(WW, dtype=np.float32)[None, :] / ss
    far = 700 + 40 * np.sin(xs / 210 + 1.3) + 25 * np.sin(xs / 87 + 0.4) + 12 * (pnoise(WW, 1, 30, 1, r)[0][None, :] - 0.5) * 4
    farm = (np.arange(HH)[:, None] / ss > far).astype(np.float32)
    farm = blur(farm, 0.7 * ss)
    cv.paint(farm, col("#141d2b"))
    cv.hatch(farm, 70, 5.0, 0.6, 0.2, color=(0, 0, 0))
    # mist band in front of far hills
    mist = fbm(WW, HH, 4, 14, rng("mist1"), 5)
    yy = np.arange(HH)[:, None] / ss
    mb = smoothstep(640, 730, yy) * smoothstep(860, 760, yy)
    cv.tint(mb * smoothstep(0.3, 0.8, mist) * 0.55, (120, 138, 162), 1.0)
    # --- main hill (rises toward the manor at centre-right)
    hill = 830 - 245 * np.exp(-((xs - 1200) / 650) ** 2) + 14 * np.sin(xs / 140) + 8 * np.sin(xs / 53 + 2)
    hill = np.maximum(hill, 643.0)
    hm = blur((yy > hill).astype(np.float32), 0.7 * ss)
    cv.paint(hm, col("#0a0c11"))
    # moonlit rim on the hill crest
    crest = np.clip(hm - np.roll(hm, int(5 * ss), 0), 0, 1)
    cv.paint(blur(crest, 1.0 * ss), (120, 138, 165), 0.7)
    cv.hatch(hm * smoothstep(0, 1, (xs / W)) * 0.6, -25, 4.5, 0.6, 0.35, color=(40, 48, 64))
    # --- manor
    base_y = 640.0
    mm, wins = manor(cv, 1110, base_y)
    cv.paint(dilate(mm.arr, 0.6 * ss), INK)
    cv.paint(mm, col("#0b0d12"))
    # moonlit rim on manor edges facing the moon (upper-right)
    rimm = np.clip(mm.arr - np.roll(mm.arr, (int(3 * ss), int(-3 * ss)), (0, 1)), 0, 1)
    cv.paint(rimm, (130, 150, 180), 0.75)
    cv.hatch(mm.arr, 0, 3.0, 0.6, 0.35, color=(34, 40, 54), dash=12)
    litm, darkm, bars = cv.mask(), cv.mask(), cv.mask()
    for (wx, wy, ww, wh, lit) in wins:
        w = litm if lit > 0 else darkm
        w.rect(wx, wy + ww / 2, wx + ww, wy + wh, 0)
        w.ellipse(wx + ww / 2, wy + ww / 2, ww / 2, ww / 2)
        if lit > 0:
            bars.rect(wx + ww / 2 - 1, wy + 2, wx + ww / 2 + 1, wy + wh)
            bars.rect(wx, wy + wh * 0.55, wx + ww, wy + wh * 0.55 + 2)
    cv.paint(darkm, (24, 30, 42))
    cv.paint(litm, (255, 186, 92))
    cv.paint(bars, (60, 30, 10), 0.8)
    cv.glow(blur(litm.arr, 14 * ss) * 1.4, (255, 160, 70), 0.55)
    # door with warm light
    dm = cv.mask().rect(1110 + 150, base_y - 56, 1110 + 180, base_y, 0)
    dm.ellipse(1110 + 165, base_y - 56, 15, 15)
    cv.paint(dm, (200, 120, 50), 0.8)
    # path down the hill
    path = cv.mask().poly(catmull([(1265, base_y), (1240, 700), (1160, 780), (1060, 860), (980, 1080)], 10)
                          + catmull([(1080, 1080), (1150, 870), (1250, 780), (1290, 700), (1285, base_y)], 10))
    cv.paint(path, (34, 38, 46), 0.75)
    # --- dead trees
    tm = cv.mask()
    tree(tm, 210, 1080, -math.pi / 2 + 0.06, 360, 30, 8, rng("tree1"))
    tree(tm, 1720, 640, -math.pi / 2 + 0.1, 150, 10, 6, rng("tree2"))
    tree(tm, 880, 760, -math.pi / 2 - 0.15, 120, 8, 5, rng("tree3"))
    cv.paint(tm, INK)
    # --- low mist rolling over the foreground
    m2 = fbm(WW, HH, 5, 12, rng("mist2"), 5)
    lm = smoothstep(820, 1000, yy) * smoothstep(0.35, 0.85, m2)
    cv.tint(lm * 0.45, (130, 146, 170), 1.0)
    m3 = fbm(WW, HH, 3, 10, rng("mist3"), 5)
    cv.tint(smoothstep(700, 840, yy) * smoothstep(940, 820, yy) * smoothstep(0.45, 0.9, m3) * 0.35,
            (150, 166, 188), 1.0)
    # --- foreground: gravestones and iron fence
    fg = cv.mask()
    for (gx, gy, gw, gh) in ((520, 960, 46, 70), (610, 990, 38, 56), (700, 975, 30, 64), (430, 1000, 40, 48),
                             (1560, 940, 44, 66), (1650, 980, 36, 52)):
        fg.rect(gx - gw / 2, gy - gh + gw / 2, gx + gw / 2, gy + 60, 0)
        fg.ellipse(gx, gy - gh + gw / 2, gw / 2, gw / 2)
    fg.rect(744 - 6, 870, 744 + 6, 1000)          # a cross
    fg.rect(744 - 26, 900, 744 + 26, 912)
    for k in range(34):
        fx = 1280 + k * 19
        if fx > W:
            break
        top = 900 + 12 * math.sin(k * 0.4)
        fg.line([(fx, top), (fx, 1080)], 3.4)
        fg.poly([(fx - 5, top), (fx, top - 16), (fx + 5, top)])
    fg.line([(1280, 930), (W, 940)], 4)
    fg.line([(1280, 1000), (W, 1010)], 4)
    gnd = 980 + 30 * np.sin(xs / 300) + 8 * np.sin(xs / 41)
    fgm = np.maximum(fg.arr, blur((yy > gnd).astype(np.float32), 0.7 * ss))
    cv.paint(fgm, (6, 7, 10))
    cv.paint(np.clip(fgm - np.roll(fgm, (int(3 * ss), int(-3 * ss)), (0, 1)), 0, 1), (80, 96, 120), 0.6)
    cv.tint(smoothstep(950, 1080, yy) * smoothstep(0.5, 0.9, m2) * 0.22, (130, 146, 170), 1.0)
    # --- crows
    cm_ = cv.mask()
    for k in range(14):
        a = r.random() * 2 * math.pi
        d = 150 + r.random() * 330
        bx, by = mx - 200 + math.cos(a) * d, 200 + math.sin(a) * d * 0.45
        crow(cm_, bx, by, 0.8 + r.random() * 0.9, r.random() * 1.2 + 0.2)
    cv.paint(cm_, INK)
    # --- vignette & paper
    v = smoothstep(0.55, 1.25, radial(WW, HH, WW / 2, HH / 2, WW / 2))
    cv.mul(v, 0.7, (0, 0, 0))
    cv.grain(0.07)
    save(cv.image().convert("RGB"), "ui/menu_background.png", opaque=True)


if __name__ == "__main__":
    menu_background()
