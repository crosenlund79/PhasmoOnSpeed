"""Revision 2: props for the overhead investigation-desk main menu, plus brass plaque buttons.

All subjects are generic and invented (a gabled house, a silhouette at a
window, a dark doorway); the only words are "SPECTRAL" and "CASE".
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw

from core import (Canvas, INK, blur, catmull, col, dilate, ellipse_pts, erode, fbm, font, gradient, mix,
                  noise_tex, radial, rng, rrect_pts, save, smoothstep, edge_band)
from furniture import BRASS, fab, wtex
from ui import GOLD, GOLD_HI, nine_clean, parchment_tex

SEPIA_LT = (214, 192, 152)
SEPIA_DK = (52, 36, 24)
RED = (150, 30, 26)
INKBLUE = (34, 32, 44)


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
def text_arr(cv, s, fnt_name, size, cx, cy, angle=0.0, tracking=0.0):
    """text mask (canvas res) centred at (cx,cy), rotated by angle degrees."""
    ss = cv.ss
    f = font(fnt_name, int(size * ss))
    tmp = Image.new("L", (cv.W, cv.H), 0)
    d = ImageDraw.Draw(tmp)
    widths = [d.textlength(ch, font=f) for ch in s]
    total = sum(widths) + tracking * ss * (len(s) - 1)
    x = cv.W / 2 - total / 2
    for ch, w in zip(s, widths):
        d.text((x, cv.H / 2), ch, font=f, fill=255, anchor="lm")
        x += w + tracking * ss
    tmp = tmp.rotate(angle, resample=Image.BICUBIC, center=(cv.W / 2, cv.H / 2),
                     translate=(cx * ss - cv.W / 2, cy * ss - cv.H / 2))
    return np.asarray(tmp, np.float32) / 255


def scribble(cv, x, y, w, rr, color=INKBLUE, width=0.7, op=0.85, amp=1.6, rot=0.0):
    """a line of illegible handwriting: loopy sinuous stroke with word gaps."""
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    xx = 0.0
    while xx < w:
        wl = min(w - xx, 8 + rr.random() * 18)
        pts = []
        t = 0.0
        ph = rr.random() * 6.28
        while t < wl:
            loop = math.sin(t * 1.9 + ph)
            pts.append((xx + t - 0.8 * math.cos(t * 1.9 + ph) * (rr.random() < 0.3),
                        -amp * loop * (0.6 + 0.8 * rr.random()) - (amp * 1.4 if rr.random() < 0.07 else 0)))
            t += 1.1
        if len(pts) > 2:
            P = [(x + px * c - py * s, y + px * s + py * c) for px, py in pts]
            cv.stroke(catmull(P, 4), width, color, op)
        xx += wl + 3 + rr.random() * 3


def tape(cv, cx, cy, w, h, rot, op=0.55):
    pts = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
    # serrated torn ends
    pts = [(-w / 2, -h / 2), (w / 2, -h / 2)] + [(w / 2 + (k % 2) * 1.2, -h / 2 + h * k / 5) for k in range(6)] + \
          [(-w / 2, h / 2)] + [(-w / 2 - (k % 2) * 1.2, h / 2 - h * k / 5) for k in range(6)]
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    P = [(cx + x * c - y * s, cy + x * s + y * c) for x, y in pts]
    m = cv.mask().poly(P)
    cv.paint(m, (226, 214, 168), op)
    cv.mul(m.arr * smoothstep(0.5, 0.9, cv.noise(6, 6, 3, seed=f"tape{cx}")), 0.15, (120, 100, 60))
    cv.paint(dilate(m.arr, 0.5 * cv.ss) * (1 - m.arr), (90, 80, 60), 0.35)


def paper_curl(cv, m, corner=(1, 1), amount=0.35):
    """shade a lifted corner (lower-right by default)."""
    x = np.linspace(0, 1, cv.W)[None, :]
    y = np.linspace(0, 1, cv.H)[:, None]
    gx = x if corner[0] > 0 else 1 - x
    gy = y if corner[1] > 0 else 1 - y
    t = smoothstep(1.35, 1.95, gx + gy)
    cv.mul(m * t, amount, (60, 45, 30))
    cv.screen(m * smoothstep(1.85, 1.98, gx + gy), 0.25)


def finish_prop(cv, rel, shadow=(2.0, 3.0, 2.5, 0.55), grain=0.06):
    cv.grain(grain)
    if shadow:
        cv.drop_shadow(*shadow)
    save(cv.image(), rel)


def sepia_fill(cv, m, t):
    """paint mask with a sepia tone t in 0 (dark) .. 1 (light)."""
    c = mix(SEPIA_DK, SEPIA_LT, t)
    cv.paint(m, c)


# --------------------------------------------------------------------------
# photographs
# --------------------------------------------------------------------------
def _photo(idx):
    W, H = 128, 160
    cv = Canvas(W, H, 4, name=f"menu:case_photo_{idx}")
    rr = cv.rnd
    rot = (-2.0, 1.5, -1.0)[idx - 1]
    c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    cx, cy = W / 2, H / 2
    P = lambda q: [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in q]
    card = cv.mask().poly(P(rrect_pts(9, 9, W - 11, H - 11, 1.5, 2)), wobble=0.2)
    cv.paint(dilate(card.arr, 0.6 * cv.ss), (60, 50, 40), 0.8)
    cv.paint(card, noise_tex(cv.W, cv.H, rng(f"ph{idx}"), "#e2d8bf", 0.06, 6, 6))
    ix0, iy0, ix1, iy1 = 17, 17, W - 19, H - 37
    im = cv.mask().poly(P([(ix0, iy0), (ix1, iy0), (ix1, iy1), (ix0, iy1)])).arr
    # image area: graded sepia sky -> ground
    yy = np.linspace(0, 1, cv.H)[:, None]
    sky = np.broadcast_to(smoothstep(0.1, 0.75, yy), (cv.H, cv.W))
    base = mix(SEPIA_LT, SEPIA_DK, 0.25)[None, None, :] * (1 - 0.45 * sky[..., None])
    cv.paint(im, base.astype(np.float32))

    def M():
        return cv.mask()

    def put(mask, t, op=1.0):
        cv.paint(A(mask) * im, mix(SEPIA_DK, SEPIA_LT, t), op)

    def A(m):
        return m.arr if hasattr(m, "arr") else m

    gx0, gx1 = ix0, ix1
    if idx == 1:
        # a gabled house on a rise, bare tree, lit windows
        put(M().poly(P(catmull([(gx0, 92), (40, 86), (70, 84), (gx1, 90)], 6) + [(gx1, iy1), (gx0, iy1)])), 0.12)
        hx = 34
        house = M().poly(P([(hx, 90), (hx, 62), (hx + 14, 46), (hx + 28, 62), (hx + 28, 56), (hx + 42, 42),
                            (hx + 56, 56), (hx + 56, 90)]))
        put(house, 0.04)
        put(M().poly(P([(hx + 44, 47), (hx + 44, 36), (hx + 49, 36), (hx + 49, 52)])), 0.04)
        for (wx, wy) in ((hx + 8, 68), (hx + 36, 64), (hx + 46, 64), (hx + 36, 76)):
            put(M().poly(P(rrect_pts(wx, wy, wx + 5, wy + 7, 0.3, 1))), 0.85 if (wx + wy) % 3 else 0.55)
        put(M().poly(P([(hx + 18, 90), (hx + 18, 78), (hx + 23, 78), (hx + 23, 90)])), 0.0)
        tm = M()
        tx, ty = 96, 92
        tm.line(P([(tx, ty), (tx + 1, 70), (tx - 2, 58)]), 1.6)
        for (a, ln) in ((-2.2, 14), (-1.0, 16), (-1.8, 10), (-0.6, 9)):
            bx, by = tx + rr.normal(0, 1), 66 + rr.normal(0, 4)
            tm.line(P([(bx, by), (bx + math.cos(a) * ln, by + math.sin(a) * ln)]), 0.7)
        put(tm, 0.05)
    elif idx == 2:
        # a window in a dark wall, a figure silhouetted against the lit room
        put(M().poly(P([(gx0, iy0), (gx1, iy0), (gx1, iy1), (gx0, iy1)])), 0.1)
        wx0, wy0, wx1, wy1 = 38, 34, 90, 106
        put(M().poly(P(rrect_pts(wx0 - 5, wy0 - 5, wx1 + 5, wy1 + 7, 1, 1))), 0.3)
        win = M().poly(P(catmull([(wx0, wy1), (wx0, wy0 + 12), ((wx0 + wx1) / 2, wy0), (wx1, wy0 + 12),
                                  (wx1, wy1)], 8)))
        glowc = np.clip(1 - radial(cv.W, cv.H, 64 * cv.ss, 70 * cv.ss, 40 * cv.ss), 0, 1)
        cv.paint(win.arr * im, mix(SEPIA_DK, SEPIA_LT, 0.95))
        cv.mul(win.arr * im * (1 - glowc), 0.4, (120, 90, 60))
        fig = M().poly(P(catmull([(50, wy1), (52, 84), (57, 76), (60, 72)], 5) + catmull(
            [(60, 72), (58, 64), (64, 58), (70, 64), (68, 72)], 5) + catmull([(68, 72), (71, 76), (76, 84), (78, wy1)], 5)))
        put(fig, 0.02)
        mull = M()
        mull.line(P([((wx0 + wx1) / 2, wy0), ((wx0 + wx1) / 2, wy1)]), 1.6)
        mull.line(P([(wx0, 62), (wx1, 62)]), 1.4)
        mull.line(P([(wx0, 84), (wx1, 84)]), 1.4)
        put(mull, 0.15, 0.85)
        put(M().poly(P(rrect_pts(wx0 - 7, wy1 + 2, wx1 + 7, wy1 + 7, 1, 1))), 0.4)
        # ivy on the wall
        for _ in range(40):
            x, y = gx0 + rr.random() * 18, iy0 + rr.random() * (iy1 - iy0)
            put(M().poly(P(ellipse_pts(x, y, 2.4, 1.6, 8, rr.random() * 180))), 0.0 + rr.random() * 0.15)
    else:
        # an arched doorway, standing open on darkness, a few steps
        put(M().poly(P([(gx0, iy0), (gx1, iy0), (gx1, iy1), (gx0, iy1)])), 0.42)
        for k in range(9):
            yb = iy0 + 6 + k * 9
            put(M().line(P([(gx0, yb), (gx1, yb)]), 0.5), 0.25, 0.6)
            for j in range(5):
                xb = gx0 + ((j + (k % 2) * 0.5) * 22) % (gx1 - gx0)
                put(M().line(P([(xb, yb), (xb, yb + 9)]), 0.5), 0.25, 0.5)
        dx0, dx1, dy0, dy1 = 42, 86, 34, 104
        arch = M().poly(P(catmull([(dx0 - 7, dy1), (dx0 - 7, dy0 + 18), ((dx0 + dx1) / 2, dy0 - 10),
                                   (dx1 + 7, dy0 + 18), (dx1 + 7, dy1)], 8)))
        put(arch, 0.55)
        door = M().poly(P(catmull([(dx0, dy1), (dx0, dy0 + 20), ((dx0 + dx1) / 2, dy0 - 2), (dx1, dy0 + 20),
                                   (dx1, dy1)], 8)))
        put(door, 0.0)
        leaf = M().poly(P([(dx1 - 12, dy1), (dx1 - 12, dy0 + 22), (dx1, dy0 + 18), (dx1, dy1)]))
        put(leaf, 0.2)
        for k in range(3):
            put(M().poly(P(rrect_pts(dx0 - 10 - k * 4, dy1 + k * 4, dx1 + 10 + k * 4, dy1 + 4 + k * 4, 0.5, 1))),
                0.5 - k * 0.08)
    # age: vignette, fading, silver mirroring, scratches, dust specks
    vig = np.clip(radial(cv.W, cv.H, cv.W / 2, (iy0 + iy1) / 2 * cv.ss, 64 * cv.ss) - 0.55, 0, 1) * 1.6
    cv.mul(im * np.clip(vig, 0, 1), 0.55, (40, 26, 16))
    cv.screen(im * smoothstep(0.6, 0.95, cv.noise(4, 4, 3, seed="fade")), 0.25, (230, 214, 180))
    for _ in range(6):
        x, y = ix0 + rr.random() * (ix1 - ix0), iy0 + rr.random() * (iy1 - iy0)
        a = rr.normal(1.4, 0.4)
        ln = 10 + rr.random() * 30
        cv.paint(cv.mask().line(P([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)]), 0.4).arr * im,
                 (235, 225, 200), 0.55)
    for _ in range(25):
        x, y = ix0 + rr.random() * (ix1 - ix0), iy0 + rr.random() * (iy1 - iy0)
        cv.paint(cv.mask().circle(x, y, 0.3 + rr.random() * 0.6).arr * im, (240, 230, 210) if rr.random() < 0.5
                 else SEPIA_DK, 0.7)
    cv.mul(im * 0 + cv.mask().poly(P([(ix0, iy0), (ix1, iy0), (ix1, iy0 + 0.8), (ix0, iy0 + 0.8)])).arr, 0.5)
    # handwriting on the bottom margin
    word = ("CASE", None, None)[idx - 1]
    if word:
        cv.paint(text_arr(cv, word, "IMFellEnglish-Italic.ttf", 12, 40, iy1 + 11, -rot) * card.arr, INKBLUE, 0.8)
        scribble(cv, 60, iy1 + 11, 40, rr, rot=rot, amp=1.3)
    else:
        scribble(cv, 26, iy1 + 10, 66 + idx * 4, rr, rot=rot, amp=1.3)
    # curl, wear, tape
    paper_curl(cv, card.arr, (1, 1), 0.35)
    cv.mul(card.arr * (1 - erode(card.arr, 1.5 * cv.ss)), 0.35, (90, 70, 50))
    tape(cv, cx + (-14, 10, 0)[idx - 1], 12, 34, 11, (-8, 6, -3)[idx - 1])
    finish_prop(cv, f"menu/case_photo_{idx}.png")


def case_photo_1():
    _photo(1)


def case_photo_2():
    _photo(2)


def case_photo_3():
    _photo(3)


# --------------------------------------------------------------------------
# case file, journal, map
# --------------------------------------------------------------------------
def case_file():
    W, H = 192, 256
    cv = Canvas(W, H, 4, name="menu:case_file")
    rr = cv.rnd
    manila = "#c4a468"
    # back flap with tab (peeking above at the right)
    back = cv.mask().poly([(10, 26), (112, 26), (120, 12), (172, 12), (178, 26), (182, 26), (182, 246), (10, 246)])
    cv.part(back, noise_tex(cv.W, cv.H, rng("cf:b"), "#b8985e", 0.08, 6, 6), ow=1.6, shade=0.3, light=0.15,
            hatch=0.25, depth=3)
    # inner papers sticking out on the right
    for k, (dx, dy, r_) in enumerate(((10, 8, 2.0), (6, 16, -1.5))):
        pm = cv.mask().poly(rrect_pts(22 + dx, 34 + dy, 178 + dx, 236 + dy, 0.5, 1))
        cv.part(pm, "#ddd3b8", ow=1.0, shade=0.25, light=0, hatch=0, depth=1.5)
        for j in range(6):
            yy = 50 + dy + j * 26
            scribble(cv, 172 + dx - 4, yy, 8, rr, amp=0.8, op=0.6)
    # front cover
    front = cv.mask().rect(8, 30, 178, 248, 2.5, wobble=0.4)
    cv.part(front, noise_tex(cv.W, cv.H, rng("cf:f"), manila, 0.08, 8, 8), ow=1.8, shade=0.35, light=0.2,
            hatch=0.3, depth=4)
    cv.mul(front.arr * smoothstep(0.7, 0.95, cv.noise(5, 5, 3, seed="st")), 0.25, (90, 60, 30))
    # ring stain
    for r_, op in ((17, 0.4), (16, 0.2)):
        cv.stroke(ellipse_pts(130, 200, r_, r_ * 0.95, 60, 0, 10, 320), 1.4, (110, 70, 40), op)
    # typed label strip with handwriting
    lb = cv.mask().rect(28, 46, 140, 70, 1)
    cv.part(lb, "#e2d9c0", ow=1.0, shade=0.2, light=0, hatch=0, depth=1)
    cv.paint(text_arr(cv, "CASE", "IMFellEnglishSC-Regular.ttf", 13, 50, 58), INKBLUE, 0.85)
    scribble(cv, 70, 58, 62, rr, amp=1.4)
    # handwritten notes on the cover
    for j in range(5):
        scribble(cv, 30, 160 + j * 12, 90 + rr.random() * 40, rr, amp=1.2, rot=-1.5, op=0.7)
    # red SPECTRAL stamp inside a double-ruled box, distressed
    sm = text_arr(cv, "SPECTRAL", "IMFellEnglishSC-Regular.ttf", 21, 96, 118, 12, tracking=1.0)
    bx = cv.mask().poly([(96 + x * math.cos(math.radians(-12)) - y * math.sin(math.radians(-12)),
                          118 + x * math.sin(math.radians(-12)) + y * math.cos(math.radians(-12)))
                         for x, y in rrect_pts(-72, -17, 72, 17, 3, 3)])
    ring = np.clip(dilate(bx.arr, 1.2 * cv.ss) - bx.arr, 0, 1) + np.clip(bx.arr - erode(bx.arr, 2.2 * cv.ss), 0, 1) * 0
    stamp = np.clip(sm + ring, 0, 1)
    holes = smoothstep(0.55, 0.75, cv.noise(30, 30, 3, seed="stamp"))
    cv.paint(stamp * (1 - holes * 0.8), RED, 0.82)
    # paperclip over the top edge
    clip_pts = [(40, 22), (40, 52), (46, 56), (52, 52), (52, 28), (47, 24), (44, 28), (44, 46)]
    cv.stroke(catmull(clip_pts, 6), 2.0, INK, 0.8)
    cv.stroke(catmull(clip_pts, 6), 1.1, (170, 172, 176), 1.0)
    paper_curl(cv, front.arr, (1, 1), 0.3)
    finish_prop(cv, "menu/case_file.png")


def journal_open():
    W, H = 320, 224
    cv = Canvas(W, H, 3, name="menu:journal_open")
    rr = cv.rnd
    cover = cv.mask().rect(6, 8, W - 8, H - 10, 8, wobble=0.5)
    leather = noise_tex(cv.W, cv.H, rng("jl"), "#4a2c1c", 0.22, 14, 10)
    cv.part(cover, leather, ow=3.0, shade=0.45, light=0.25, hatch=0.4, depth=4)
    cv.mul(cover.arr * smoothstep(0.6, 0.9, cv.noise(8, 6, 3, seed="scuff")), 0.3, (20, 10, 5))
    # page stacks
    parch = parchment_tex(cv.W, cv.H, "journal", tile=False, ss=cv.ss)
    gut = W / 2 - 1
    for side in (-1, 1):
        for k in range(3, -1, -1):
            off = k * 1.6
            if side < 0:
                pg = cv.mask().poly(catmull([(gut, 18), (gut - 60, 14 - off * 0.3), (16 + off * 0.0, 16 + off)], 8)
                                    + [(16 + off * 0.0, H - 20 - off)]
                                    + catmull([(16, H - 20 - off), (gut - 60, H - 22), (gut, H - 18)], 8))
            else:
                pg = cv.mask().poly(catmull([(gut, 18), (gut + 60, 14 - off * 0.3), (W - 18 - off * 0.0, 16 + off)], 8)
                                    + [(W - 18, H - 20 - off)]
                                    + catmull([(W - 18, H - 20 - off), (gut + 60, H - 22), (gut, H - 18)], 8))
            cv.part(pg, parch * (0.9 + 0.03 * k), ow=0.8 if k else 1.2, shade=0.2, light=0.0, hatch=0.0, depth=1.5)
    # gutter shading
    xx = np.arange(cv.W)[None, :] / cv.ss
    g = np.exp(-((xx - gut) / 9.0) ** 2)
    cv.mul(np.broadcast_to(g, (cv.H, cv.W)) * (cv.a > 0.5), 0.5, (60, 40, 20))
    cv.stroke([(gut, 18), (gut, H - 18)], 0.8, INK, 0.6)
    # left page: written notes
    for j in range(13):
        ww = 110 - rr.random() * 30 if j % 5 != 4 else 60
        scribble(cv, 30, 34 + j * 12.5, ww, rr, amp=1.3, op=0.8)
    # right page: sketch of a gabled house, a sigil ring and notes
    hx, hy = 186, 42
    house = [(hx, hy + 54), (hx, hy + 22), (hx + 18, hy + 4), (hx + 36, hy + 22), (hx + 36, hy + 14), (hx + 52, hy),
             (hx + 68, hy + 14), (hx + 68, hy + 54), (hx, hy + 54)]
    cv.stroke(house, 1.0, INKBLUE, 0.85)
    for (wx, wy) in ((hx + 8, hy + 30), (hx + 46, hy + 22), (hx + 56, hy + 22), (hx + 46, hy + 38)):
        cv.stroke(rrect_pts(wx, wy, wx + 6, wy + 8, 0, 1) + [(wx, wy)], 0.7, INKBLUE, 0.8)
    cv.stroke([(hx + 24, hy + 54), (hx + 24, hy + 38), (hx + 31, hy + 38), (hx + 31, hy + 54)], 0.8, INKBLUE, 0.8)
    for k in range(8):
        cv.stroke([(hx + 2 + k * 4, hy + 54), (hx - 2 + k * 4, hy + 50)], 0.5, INKBLUE, 0.5)
    sx, sy = 270, 150
    for r_ in (20, 15):
        cv.stroke(ellipse_pts(sx, sy, r_, r_, 50) + [ellipse_pts(sx, sy, r_, r_, 50)[0]], 0.8, INKBLUE, 0.8)
    cv.stroke([(sx, sy - 13), (sx, sy + 13)], 0.8, (120, 30, 26), 0.8)
    cv.stroke([(sx - 13, sy), (sx + 13, sy)], 0.8, (120, 30, 26), 0.8)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        cv.paint(cv.mask().circle(sx + math.cos(a) * 17.5, sy + math.sin(a) * 17.5, 1.2), INKBLUE, 0.85)
    for j in range(6):
        scribble(cv, 178, 118 + j * 12.5, 62 - j * 3, rr, amp=1.2, op=0.75)
    # a pressed leaf of dried flower? -> an ink blot and a ribbon bookmark
    cv.paint(cv.mask().ellipse(120, 176, 5, 3.5, wobble=1.0), INKBLUE, 0.8)
    rb = cv.mask().poly([(gut + 4, 10), (gut + 10, 10), (gut + 14, H - 2), (gut + 10, H + 0), (gut + 7, H - 5),
                         (gut + 3, H - 1)])
    cv.part(rb, fab(cv, "#6a1e22", 0.12), ow=1.0, shade=0.3, light=0.2, hatch=0, depth=1)
    finish_prop(cv, "menu/journal_open.png")


def map_pinned():
    W, H = 256, 192
    cv = Canvas(W, H, 3, name="menu:map_pinned")
    rr = cv.rnd
    sheet = cv.mask().poly(rrect_pts(8, 8, W - 10, H - 12, 1, 1), wobble=1.2, step=2)
    parch = parchment_tex(cv.W, cv.H, "mapp", tile=False, ss=cv.ss)
    cv.part(sheet, parch, ow=1.2, shade=0.25, light=0.0, hatch=0.0, depth=2, soft=0.25)
    # fold creases
    for (p0, p1) in (((W / 2, 10), (W / 2, H - 12)), ((10, H / 2), (W - 10, H / 2))):
        cv.stroke([p0, p1], 0.7, (120, 96, 64), 0.5)
        cv.stroke([(p0[0] + 0.8, p0[1] + 0.8), (p1[0] + 0.8, p1[1] + 0.8)], 0.6, (240, 230, 205), 0.4)
    # floorplan in ink: outer walls (double line), rooms, door gaps
    ox0, oy0, ox1, oy1 = 30, 30, 226, 162
    walls = [((ox0, oy0), (ox1, oy0)), ((ox1, oy0), (ox1, oy1)), ((ox1, oy1), (ox0, oy1)), ((ox0, oy1), (ox0, oy0)),
             ((110, oy0), (110, 82)), ((110, 98), (110, oy1)), ((ox0, 96), (70, 96)), ((86, 96), (110, 96)),
             ((110, 110), (160, 110)), ((176, 110), (ox1, 110)), ((170, oy0), (170, 70)), ((170, 86), (170, 110))]
    for (p0, p1) in walls:
        cv.stroke([p0, p1], 2.2, INKBLUE, 0.85)
    # stair hatching and a small hatch square
    for k in range(7):
        cv.stroke([(186 + k * 5, 120), (186 + k * 5, 150)], 0.6, INKBLUE, 0.7)
    cv.stroke(rrect_pts(52, 120, 66, 134, 0, 1) + [(52, 120)], 0.8, INKBLUE, 0.8)
    cv.stroke([(52, 120), (66, 134)], 0.6, INKBLUE, 0.7)
    # room labels (squiggles), a circled X
    for (x, y, w) in ((46, 60, 40), (126, 54, 30), (186, 48, 26), (130, 136, 40), (46, 146, 30)):
        scribble(cv, x, y, w, rr, amp=1.0, op=0.7)
    xx, xy = 142, 76
    cv.stroke([(xx - 5, xy - 5), (xx + 5, xy + 5)], 1.2, (130, 28, 24), 0.9)
    cv.stroke([(xx - 5, xy + 5), (xx + 5, xy - 5)], 1.2, (130, 28, 24), 0.9)
    cv.stroke(ellipse_pts(xx, xy, 10, 9, 40, 0, 0, 340), 0.9, (130, 28, 24), 0.8)
    # red string between pins
    pins = [(60, 64), (142, 76), (196, 134), (80, 140), (200, 50)]
    order = [0, 1, 2, 3, 0]
    for a, b in zip(order[:-1], order[1:]):
        p0, p1 = pins[a], pins[b]
        mid = ((p0[0] + p1[0]) / 2 + 2, (p0[1] + p1[1]) / 2 + 3)
        cv.stroke(catmull([p0, mid, p1], 10), 1.4, INK, 0.35)
        cv.stroke(catmull([p0, mid, p1], 10), 0.9, (170, 30, 28), 0.95)
    cv.stroke(catmull([pins[1], (172, 62), pins[4]], 10), 0.9, (170, 30, 28), 0.95)
    for (px, py) in pins:
        cv.paint(blur(cv.mask().circle(px + 2, py + 3, 3.4).arr, 1.2 * cv.ss), (0, 0, 0), 0.4)
        cv.part(cv.mask().circle(px, py, 3.4), "#a82420", ow=1.0, shade=0.4, light=0.6, hatch=0, depth=1)
        cv.paint(cv.mask().circle(px - 1, py - 1, 1.0), (255, 220, 210), 0.8)
    # corner tacks
    for (px, py) in ((16, 16), (W - 18, 16), (16, H - 20), (W - 18, H - 20)):
        cv.part(cv.mask().circle(px, py, 3.0), BRASS, ow=1.0, shade=0.4, light=0.6, hatch=0, depth=1)
    paper_curl(cv, sheet.arr, (1, 1), 0.25)
    finish_prop(cv, "menu/map_pinned.png")


# --------------------------------------------------------------------------
# small desk props (96x96)
# --------------------------------------------------------------------------
def pocket_watch():
    cv = Canvas(96, 96, 4, name="menu:pocket_watch")
    cx, cy, R = 46, 52, 30
    # chain curling away to the upper right
    links = catmull([(cx, cy - R - 6), (cx + 8, cy - R - 16), (cx + 26, cy - R - 14), (cx + 34, cy - 24),
                     (cx + 44, cy - 10), (cx + 46, cy + 8)], 10)
    for i, (x, y) in enumerate(links[::3]):
        m = cv.mask().ellipse(x, y, 2.4, 1.4, rot=i * 50)
        cv.part(m, BRASS, ow=0.8, shade=0.3, light=0.5, hatch=0, depth=0.5)
    # bow and crown
    cv.stroke(ellipse_pts(cx, cy - R - 6, 6, 5, 30, 0, 180, 360), 2.6, INK)
    cv.stroke(ellipse_pts(cx, cy - R - 6, 6, 5, 30, 0, 180, 360), 1.4, BRASS)
    cv.part(cv.mask().rect(cx - 4, cy - R - 6, cx + 4, cy - R + 2, 1.5), BRASS, ow=1.2, shade=0.4, light=0.5, hatch=0,
            depth=1)
    case = cv.mask().circle(cx, cy, R)
    gold = np.clip(gradient(cv.W, cv.H, GOLD_HI, "#6a4e1e", 50) * (0.9 + 0.2 * cv.noise(10, 10, 3)[..., None]), 0, 255)
    cv.part(case, gold, ow=2.2, shade=0.45, light=0.45, hatch=0.25, depth=3)
    face = cv.mask().circle(cx, cy, R - 5)
    cv.part(face, "#e6dcc4", ow=1.2, shade=0.25, light=0.1, hatch=0, depth=2)
    for k in range(60):
        a = k * 2 * math.pi / 60
        r0 = R - 7.5 if k % 5 else R - 10.5
        cv.stroke([(cx + math.cos(a) * r0, cy + math.sin(a) * r0), (cx + math.cos(a) * (R - 6.5),
                                                                   cy + math.sin(a) * (R - 6.5))],
                  0.4 if k % 5 else 0.9, INK, 0.85)
    # seconds sub-dial, hands at ten to midnight
    cv.stroke(ellipse_pts(cx, cy + 11, 5, 5, 30) + [ellipse_pts(cx, cy + 11, 5, 5, 30)[0]], 0.5, INK, 0.7)
    cv.stroke([(cx, cy + 11), (cx + 3, cy + 8)], 0.5, INK)
    cv.stroke([(cx, cy), (cx - 9, cy - 13)], 1.4, INK)
    cv.stroke([(cx, cy), (cx - 2, cy - 19)], 0.9, INK)
    cv.paint(cv.mask().circle(cx, cy, 1.6), BRASS)
    # crystal gloss and a hairline crack across it
    cv.paint(cv.mask().ellipse(cx - 9, cy - 10, 10, 5, rot=-40), (255, 255, 250), 0.25)
    cv.stroke([(cx + 4, cy - 20), (cx + 8, cy - 4), (cx + 18, cy + 6)], 0.4, (250, 250, 250), 0.6)
    finish_prop(cv, "menu/pocket_watch.png")


def magnifier():
    cv = Canvas(96, 96, 4, name="menu:magnifier")
    cx, cy, R = 38, 38, 26
    # handle toward the lower right
    h = cv.mask().line([(cx + 18, cy + 18), (84, 84)], 9)
    cv.part(h, wtex(cv, "ebony", seed="h"), ow=1.8, shade=0.45, light=0.4, hatch=0.2, depth=1.5)
    cv.part(cv.mask().line([(cx + 17, cy + 17), (cx + 26, cy + 26)], 7), BRASS, ow=1.4, shade=0.4, light=0.5,
            hatch=0, depth=1)
    rim = cv.mask().circle(cx, cy, R + 3)
    gold = np.clip(gradient(cv.W, cv.H, GOLD_HI, "#6a4e1e", 50), 0, 255)
    cv.part(rim, gold, ow=2.2, shade=0.45, light=0.5, hatch=0.2, depth=2)
    lens = cv.mask().circle(cx, cy, R - 1)
    # the lens is mostly transparent: tinted, with a caustic and reflections
    cv.a = cv.a * (1 - lens.arr * 0.55)
    cv.paint(lens.arr * 0.0 + lens.arr, (200, 214, 210), 0.22)
    cv.paint(cv.mask().ellipse(cx - 9, cy - 10, 11, 6, rot=-40), (255, 255, 250), 0.55)
    cv.paint(cv.mask().ellipse(cx + 12, cy + 12, 4, 2, rot=-40), (255, 255, 250), 0.35)
    cv.stroke(ellipse_pts(cx, cy, R - 2.5, R - 2.5, 60, 0, 30, 160), 0.8, (40, 50, 50), 0.4)
    finish_prop(cv, "menu/magnifier.png")


def inkwell():
    cv = Canvas(96, 96, 4, name="menu:inkwell")
    rr = cv.rnd
    cx, cy = 42, 50
    # spill
    sp = cv.mask().ellipse(cx + 20, cy + 22, 12, 6, rot=30, wobble=1.5)
    sp.circle(cx + 34, cy + 30, 2.4)
    cv.paint(sp, (16, 14, 24), 0.85)
    cv.paint(cv.mask().ellipse(cx + 17, cy + 20, 4, 1.4, rot=30), (120, 120, 150), 0.4)
    # octagonal glass bottle seen from above
    oct_ = [(cx + math.cos(math.pi / 8 + k * math.pi / 4) * 24, cy + math.sin(math.pi / 8 + k * math.pi / 4) * 24)
            for k in range(8)]
    glass = cv.mask().poly(oct_)
    cv.part(glass, "#3c4c50", ow=2.4, shade=0.5, light=0.55, hatch=0.2, depth=3)
    inner = [(cx + (x - cx) * 0.72, cy + (y - cy) * 0.72) for x, y in oct_]
    for p, q in zip(oct_, inner):
        cv.stroke([p, q], 0.6, (180, 200, 200), 0.4)
    cv.paint(cv.mask().poly(inner), (32, 40, 44), 0.6)
    # brass collar and open well of ink
    cv.part(cv.mask().circle(cx, cy, 11), BRASS, ow=1.6, shade=0.4, light=0.55, hatch=0, depth=1.5)
    cv.paint(cv.mask().circle(cx, cy, 7), (8, 8, 12))
    cv.paint(cv.mask().ellipse(cx - 2, cy - 3, 2.5, 1.2), (150, 150, 180), 0.4)
    # hinged lid flipped open
    cv.part(cv.mask().circle(cx - 18, cy - 20, 9), BRASS, ow=1.6, shade=0.45, light=0.5, hatch=0, depth=1.2)
    groove_pts = ellipse_pts(cx - 18, cy - 20, 6, 6, 30)
    cv.stroke(groove_pts + [groove_pts[0]], 0.6, INK, 0.6)
    # quill pen resting in the well
    q = cv.mask().poly(catmull([(cx, cy), (cx + 18, cy - 20), (cx + 34, cy - 38), (cx + 46, cy - 44),
                                (cx + 40, cy - 30), (cx + 24, cy - 14), (cx + 2, cy + 1)], 6))
    cv.part(q, "#e4dccb", ow=1.0, shade=0.3, light=0.1, hatch=0, depth=1)
    cv.stroke([(cx + 1, cy), (cx + 44, cy - 43)], 0.6, INK, 0.7)
    for k in range(14):
        t = 0.3 + k * 0.05
        x, y = cx + 44 * t, cy - 43 * t
        cv.stroke([(x, y), (x + 3 + rr.random(), y + 3.5)], 0.35, (150, 140, 120), 0.6)
    finish_prop(cv, "menu/inkwell.png")


# --------------------------------------------------------------------------
# plaque buttons (320x64, 9-slice with 24 px margins)
# --------------------------------------------------------------------------
def _plaque(name, state="normal", steel=False):
    W, H, M = 320, 64, 24
    cv = Canvas(W, H, 4, name="menu:" + name)
    if steel:
        metal = np.clip(gradient(cv.W, cv.H, "#b4bec8", "#3a4452", 80)
                        * (0.95 + 0.08 * fbm(cv.W, cv.H, 60, 12, rng(name + "m"), 2)[..., None]), 0, 255)
        field = col("#aebac2")[None, None, :] * (0.97 + 0.05 * fbm(cv.W, cv.H, 80, 16, rng(name + "p"), 2)[..., None])
        nail = "#8a96a2"
    else:
        hi = GOLD_HI if state != "pressed" else "#c8ac6a"
        lo = "#6a4e1e" if state != "pressed" else "#4a3412"
        metal = np.clip(gradient(cv.W, cv.H, hi, lo, 80)
                        * (0.95 + 0.08 * fbm(cv.W, cv.H, 60, 12, rng(name + "m"), 2)[..., None]), 0, 255)
        # 9-slice-safe parchment: flat tone + fine grain only (no blotches that would streak when stretched)
        field = col("#d8c49a")[None, None, :] * (0.96 + 0.06 * fbm(cv.W, cv.H, 80, 16, rng("plaque_field"), 2)[..., None])
        nail = "#7a6a52"
    if state == "hover":
        metal = np.clip(metal * 1.12 + 10, 0, 255)
        field = np.clip(field * 1.06 + np.array([14, 6, -6]), 0, 255)
    elif state == "pressed":
        field = field * 0.82
    # brass plate
    plate = cv.mask().rect(1.2, 1.2, W - 1.2, H - 1.2, 6)
    cv.paint(dilate(plate.arr, 1.0 * cv.ss), INK)
    cv.paint(plate, metal)
    d = 2.0 * cv.ss
    if state == "pressed":
        cv.mul(edge_band(plate.arr, -d, -d, d), 0.5, (0, 0, 0))
        cv.screen(edge_band(plate.arr, d, d, d), 0.2)
    else:
        cv.screen(edge_band(plate.arr, -d, -d, d), 0.45, (255, 245, 220))
        cv.mul(edge_band(plate.arr, d, d, d), 0.5, (0, 0, 0))
    # engraved rule on the plate
    pts = rrect_pts(4.5, 4.5, W - 4.5, H - 4.5, 4, 6)
    cv.stroke(pts + [pts[0]], 0.9, INK, 0.55)
    cv.stroke([(x + 0.6, y + 0.6) for x, y in pts + [pts[0]]], 0.6, (255, 240, 200), 0.3)
    # recessed parchment (or card) field
    bw = 10.0
    inner = cv.mask().rect(bw, bw, W - bw, H - bw, 3)
    cv.paint(dilate(inner.arr, 1.0 * cv.ss), INK, 0.95)
    cv.paint(inner, field)
    sh = 2.6 if state != "pressed" else 4.2
    cv.mul(edge_band(inner.arr, -sh * cv.ss, -sh * cv.ss, 1.8 * cv.ss), 0.5 if state != "pressed" else 0.7, (30, 20, 10))
    cv.screen(edge_band(inner.arr, 1.2 * cv.ss, 1.2 * cv.ss, 1.0 * cv.ss), 0.2 if state != "pressed" else 0.05)
    if state == "hover":
        ring = np.clip(dilate(inner.arr, 2 * cv.ss) - erode(inner.arr, 3.5 * cv.ss), 0, 1)
        cv.glow(blur(ring, 2.5 * cv.ss) * inner.arr, (255, 190, 100), 0.35)
    # nail heads in the four corners of the plate
    for (x, y) in ((5.8, 5.8), (W - 5.8, 5.8), (5.8, H - 5.8), (W - 5.8, H - 5.8)):
        cv.paint(cv.mask().circle(x + 0.5, y + 0.7, 3.4), (0, 0, 0), 0.5)
        n = cv.mask().circle(x, y, 3.0)
        cv.paint(dilate(n.arr, 0.6 * cv.ss), INK)
        cv.paint(n, nail)
        cv.mul(edge_band(n.arr, 1.2 * cv.ss, 1.2 * cv.ss, 1.0 * cv.ss), 0.5, (0, 0, 0))
        cv.paint(cv.mask().circle(x - 0.9, y - 0.9, 1.0), (240, 230, 210), 0.7)
    if state == "pressed":
        cv.mul(plate.arr, 0.18, (20, 14, 8))
    img = nine_mean(cv.image(), M)
    # light grain after the clean (too fine to streak visibly when the bands stretch)
    a = np.asarray(img).astype(np.float32)
    g = np.random.default_rng(len(name)).normal(0, 1, a.shape[:2])
    g = (g + np.roll(g, 1, 1)) * 0.5
    a[..., :3] = np.clip(a[..., :3] * (1 + 0.035 * g[..., None]), 0, 255)
    save(Image.fromarray(a.round().astype(np.uint8), "RGBA"), f"menu/{name}.png")


def nine_mean(img, m):
    """9-slice clean: replace each stretchable band by its mean along the stretch axis."""
    a = np.asarray(img).astype(np.float32)
    H, W = a.shape[:2]
    pm = a.copy()
    pm[..., :3] *= pm[..., 3:4] / 255
    for sl in ((slice(0, m), slice(m, W - m)), (slice(H - m, H), slice(m, W - m))):
        pm[sl] = pm[sl].mean(axis=1, keepdims=True)
    for sl in ((slice(m, H - m), slice(0, m)), (slice(m, H - m), slice(W - m, W))):
        pm[sl] = pm[sl].mean(axis=0, keepdims=True)
    cen = (slice(m, H - m), slice(m, W - m))
    pm[cen] = pm[cen].mean(axis=(0, 1), keepdims=True)
    al = np.maximum(pm[..., 3:4], 1e-3)
    pm[..., :3] = pm[..., :3] / al * 255
    return Image.fromarray(np.clip(pm, 0, 255).round().astype(np.uint8), "RGBA")


def plaque():
    _plaque("plaque")


def plaque_hover():
    _plaque("plaque_hover", "hover")


def plaque_pressed():
    _plaque("plaque_pressed", "pressed")


def plaque_dev():
    _plaque("plaque_dev", steel=True)


ALL = [case_photo_1, case_photo_2, case_photo_3, case_file, journal_open, map_pinned, pocket_watch, magnifier,
       inkwell, plaque, plaque_hover, plaque_pressed, plaque_dev]


def build_all(only=None):
    for f in ALL:
        if only and f.__name__ not in only:
            continue
        f()


if __name__ == "__main__":
    import sys
    build_all(sys.argv[1:] or None)
