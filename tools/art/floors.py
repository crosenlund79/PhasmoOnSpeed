"""Seamless floors (512x512) and wall cap (128x128)."""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw

from core import (Canvas, blur, col, dilate, fbm, pnoise, rng, save, smoothstep, wood_tex,
                  noise_tex, wobble_pts, ellipse_pts, rrect_pts, INK)

N = 512
SS = 2


# --------------------------------------------------------------------------
# label-map helpers (each tile/plank gets an integer id)
# --------------------------------------------------------------------------
def label_map(cv, polys, wobble=0.0):
    img = Image.new("I", (cv.W, cv.H), 0)
    d = ImageDraw.Draw(img)
    ss = cv.ss
    offs = [(ox, oy) for ox in (-cv.W, 0, cv.W) for oy in (-cv.H, 0, cv.H)]
    for i, pts in enumerate(polys):
        p = np.asarray(pts, float) * ss
        if wobble:
            p = wobble_pts(p, wobble * ss, cv.rnd, step=3 * ss)
        for ox, oy in offs:
            d.polygon([(x + ox, y + oy) for x, y in p], fill=i + 1)
    return np.asarray(img, dtype=np.int32)


def seam_mask(lab):
    e = (lab != np.roll(lab, 1, 0)) | (lab != np.roll(lab, 1, 1)) | (lab == 0)
    return e.astype(np.float32)


def bevel(cv, edges, d=3.0, sigma=2.0, dark=0.45, light=0.25, shade_color=(30, 28, 34)):
    """Shade each cell's lower-right rim, lighten its upper-left rim."""
    dd = int(d * cv.ss)
    b = blur(edges, sigma * cv.ss, True)
    b = np.clip(b * 2.2, 0, 1)
    dk = np.clip(np.roll(b, (-dd, -dd), (0, 1)) - edges, 0, 1)
    lt = np.clip(np.roll(b, (dd, dd), (0, 1)) - edges - dk, 0, 1)
    cv.mul(dk, dark, shade_color)
    cv.screen(lt, light, (235, 222, 196))
    return dk


def per_label(lab, values):
    v = np.asarray(values, np.float32)
    v = np.concatenate([[v.mean() if v.ndim == 1 else 0], v]) if v.ndim == 1 else v
    return v[lab]


def finish_floor(cv, rel, grain=0.07):
    cv.grain(grain)
    img = cv.image().convert("RGB")
    save(img, rel, opaque=True)
    return img


def ink_seams(cv, edges, width=1.6, color=INK, op=0.95):
    m = dilate(edges, width * cv.ss * 0.5, True, cv.wob())
    cv.tint(m, color, op)
    return m


def nail(cv, x, y, r=1.6):
    m = cv.mask().circle(x, y, r + 0.9)
    cv.tint(m, INK, 0.9)
    m2 = cv.mask().circle(x - 0.2, y - 0.2, r)
    cv.tint(m2, (70, 66, 62), 1)
    m3 = cv.mask().circle(x - 0.6, y - 0.6, r * 0.45)
    cv.tint(m3, (150, 140, 125), 0.8)


def knot(cv, x, y, rx, ry, dark):
    for i, k in enumerate((1.9, 1.45, 1.0)):
        m = cv.mask().ellipse(x, y, rx * k, ry * k, wobble=0.4)
        cv.tint(m, dark, 0.25 + 0.2 * i)
    m = cv.mask().ellipse(x, y, rx * 0.55, ry * 0.5, wobble=0.3)
    cv.tint(m, INK, 0.75)
    ring = cv.mask().ellipse(x, y, rx * 2.4, ry * 2.1, wobble=0.6).arr - cv.mask().ellipse(x, y, rx * 2.15, ry * 1.85).arr
    cv.tint(np.clip(ring, 0, 1), dark, 0.45)


# --------------------------------------------------------------------------
# wood planks
# --------------------------------------------------------------------------
def planks(name, base, dark, light, board=32, wear=0.18, knot_rate=0.35, scuff=0.35):
    cv = Canvas(N, N, SS, tile=True, name=name)
    r = cv.rnd
    rows = N // board
    polys, ends = [], []
    for ri in range(rows):
        while True:
            k = r.integers(2, 4)
            cuts = np.sort(r.integers(0, N, k))
            gaps = np.diff(np.concatenate([cuts, [cuts[0] + N]]))
            if gaps.min() >= 110:
                break
        y0, y1 = ri * board, (ri + 1) * board
        for i, c0 in enumerate(cuts):
            c1 = c0 + gaps[i]
            polys.append([(c0, y0), (c1, y0), (c1, y1), (c0, y1)])
            ends.append((c0, c1, y0, y1))
    lab = label_map(cv, polys)
    nvar = 7
    texs = [wood_tex(cv.W, cv.H, rng(f"{name}:v{i}"), base, dark, light, rings=int(r.integers(14, 26)))
            for i in range(nvar)]
    var = r.integers(0, nvar, len(polys) + 1)
    tone = 0.84 + 0.3 * r.random(len(polys) + 1)
    out = np.zeros((cv.H, cv.W, 3), np.float32)
    for i in range(nvar):
        sel = (var[lab] == i)
        out[sel] = texs[i][sel]
    out *= tone[lab][..., None]
    cv.rgb[:] = out
    cv.a[:] = 1
    # wear / grime
    n = cv.noise(4, 4, 4, seed="wear")
    cv.mul(smoothstep(0.55, 0.95, n), 0.35)
    cv.screen(smoothstep(0.45, 0.05, n), wear, (190, 170, 140))
    edges = seam_mask(lab)
    bevel(cv, edges, 2.5, 1.6, 0.5, 0.22)
    grime = blur(edges, 3 * cv.ss, True)
    cv.mul(np.clip(grime * 3, 0, 1), 0.35, (20, 16, 14))
    # hatching in darker wear zones and along lower plank edges
    hz = smoothstep(0.5, 0.85, cv.noise(3, 5, 3, seed="hz"))
    cv.hatch(hz, angle=-12, spacing=3.0, width=0.6, op=0.28, dash=18)
    # knots & nails
    for (c0, c1, y0, y1) in ends:
        if r.random() < knot_rate:
            kx = c0 + 20 + r.random() * max(10, (c1 - c0 - 40))
            ky = y0 + 7 + r.random() * (board - 14)
            knot(cv, kx % N, ky, 3 + r.random() * 3, 1.6 + r.random() * 1.2, dark)
        for xx in (c0 + 6, c1 - 6):
            nail(cv, xx % N, y0 + board * 0.28)
            nail(cv, xx % N, y0 + board * 0.72)
    # scratches
    for _ in range(int(60 * scuff)):
        x, y = r.random() * N, r.random() * N
        a = r.normal(0, 0.25)
        ln = 8 + r.random() * 26
        m = cv.mask().line([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], 0.6)
        cv.tint(m, (215, 195, 160) if r.random() < 0.5 else INK, 0.25)
    ink_seams(cv, edges, 2.0)
    return finish_floor(cv, f"floors/{name}.png")


# --------------------------------------------------------------------------
# herringbone parquet
# --------------------------------------------------------------------------
def _shear_tex(T, sign):
    """Map a horizontally-grained periodic texture onto a 45deg grain."""
    H, W = T.shape[:2]
    y = np.arange(H)[:, None]
    x = np.arange(W)[None, :]
    return T[(y - sign * x) % H, x]


def parquet():
    """Classic 45deg herringbone (blocks 4u x u, lattice chosen so it tiles 512)."""
    name = "parquet"
    cv = Canvas(N, N, SS, tile=True, name=name)
    r = cv.rnd
    n = 4
    u = N / (24 * math.sqrt(2))
    c45 = math.sqrt(0.5)

    def rot(p):
        x, y = p
        return ((x + y) * c45, (y - x) * c45)

    polys, orient = [], []
    g = 0.0
    for b in range(-14, 16):
        for k in range(-60, 60):
            ox, oy = k * u + b * n * u, k * u - b * n * u
            cx, cy = rot((ox + n * u / 2, oy + n * u / 2))
            if not (-120 < cx < N + 120 and -120 < cy < N + 120):
                continue
            hb = [(ox + g, oy + g), (ox + n * u - g, oy + g), (ox + n * u - g, oy + u - g), (ox + g, oy + u - g)]
            vb = [(ox + g, oy + u + g), (ox + u - g, oy + u + g), (ox + u - g, oy + u + n * u - g),
                  (ox + g, oy + u + n * u - g)]
            polys.append([rot(p) for p in hb])
            orient.append(0)
            polys.append([rot(p) for p in vb])
            orient.append(1)
    lab = label_map(cv, polys)
    nv = 4
    base = [wood_tex(cv.W, cv.H, rng(f"pq:h{i}"), "#6d4c33", "#2f1f15", "#8d6a4a", rings=48) for i in range(nv)]
    th = [_shear_tex(t, 1) for t in base]
    tv = [_shear_tex(t, -1) for t in base]
    var = r.integers(0, nv, len(polys) + 1)
    ori = np.array([0] + orient)
    tone = 0.8 + 0.34 * r.random(len(polys) + 1)
    out = np.zeros((cv.H, cv.W, 3), np.float32)
    vl, ol = var[lab], ori[lab]
    for i in range(nv):
        s = (vl == i) & (ol == 0)
        out[s] = th[i][s]
        s = (vl == i) & (ol == 1)
        out[s] = tv[i][s]
    out *= tone[lab][..., None]
    cv.rgb[:] = out
    cv.a[:] = 1
    n_ = cv.noise(3, 3, 4, seed="wear")
    cv.mul(smoothstep(0.5, 0.95, n_), 0.35)
    cv.screen(smoothstep(0.4, 0.0, n_), 0.16, (200, 175, 140))
    edges = seam_mask(lab)
    bevel(cv, edges, 2.0, 1.4, 0.45, 0.25)
    cv.hatch(smoothstep(0.55, 0.9, cv.noise(4, 4, 3, seed="h")), 0, 3.0, 0.6, 0.25)
    ink_seams(cv, edges, 1.7)
    return finish_floor(cv, "floors/parquet.png")


# --------------------------------------------------------------------------
# damask carpets: a mirrored ogee motif generated per carpet
# --------------------------------------------------------------------------
def _ell(d, cx, cy, rx, ry, rot, fill=255):
    d.polygon(ellipse_pts(cx, cy, rx, ry, 36, rot), fill=fill)


def _curl(d, cx, cy, r0, a0, turns, width, sgn=1, fill=255):
    pts = []
    for i in range(60):
        t = i / 59
        a = a0 + sgn * turns * 2 * math.pi * t
        rr = r0 * (1 - 0.8 * t)
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d.line(pts, fill=fill, width=int(width), joint="curve")
    x, y = pts[-1]
    d.ellipse([x - width, y - width, x + width, y + width], fill=fill)


def damask_cell(S, variant):
    """Return (main, accent) masks (S x S float) of a symmetric damask tile."""
    m1 = Image.new("L", (S, S), 0)
    m2 = Image.new("L", (S, S), 0)
    d1, d2 = ImageDraw.Draw(m1), ImageDraw.Draw(m2)
    c = S / 2
    lw = S * 0.03
    # ogee medallion outline (left half; mirrored later)
    def ogee(scale, wmul):
        pts = []
        for i in range(80):
            t = i / 79
            y = S * (0.5 + (t - 0.5) * scale)
            w = S * wmul * math.sin(math.pi * t) ** 0.9 * (1 + 0.45 * math.sin(math.pi * t * 2 - 0.6))
            pts.append((c - w, y))
        return pts + [(c, S * (0.5 + 0.5 * scale)), (c, S * (0.5 - 0.5 * scale))]
    outer = ogee(0.84, 0.22 if variant != 1 else 0.26)
    d1.polygon(outer, fill=255)
    d1.polygon(ogee(0.76, 0.185 if variant != 1 else 0.225), fill=0)
    # inner bouquet: stalk + leaves + bud
    d1.line([(c, S * 0.2), (c, S * 0.8)], fill=255, width=int(lw * 1.2))
    leaves = [(0.62, 0.075, 0.022, 35), (0.5, 0.085, 0.026, 20), (0.38, 0.07, 0.02, 0), (0.71, 0.05, 0.016, 60)]
    if variant == 2:
        leaves = [(0.64, 0.09, 0.03, 40), (0.48, 0.1, 0.032, 15), (0.33, 0.075, 0.024, -10)]
    for (yy, rx, ry, ang) in leaves:
        _ell(d1, c - rx * S * 0.9, yy * S, rx * S, ry * S, ang)
        _ell(d2, c - rx * S * 0.9, yy * S, rx * S * 0.6, ry * S * 0.22, ang)
    # bud
    bud = []
    for i in range(40):
        t = i / 39
        y = S * (0.16 + 0.12 * t)
        w = S * 0.05 * math.sin(math.pi * t) ** 0.6 * (1 - 0.3 * t)
        bud.append((c - w, y))
    d1.polygon(bud + [(c, S * 0.28), (c, S * 0.14)], fill=255)
    _ell(d2, c - S * 0.012, S * 0.22, S * 0.01, S * 0.035, 0)
    # outside scrolls
    _curl(d1, c - S * 0.3, S * 0.3, S * 0.09, 0.4, 0.9, lw, 1)
    _curl(d1, c - S * 0.3, S * 0.7, S * 0.09, -0.4, 0.9, lw, -1)
    _ell(d1, c - S * 0.36, S * 0.5, S * 0.07, S * 0.025, 90)
    _ell(d2, c - S * 0.36, S * 0.5, S * 0.03, S * 0.008, 90)
    # bottom base (vase)
    d1.polygon([(c - S * 0.07, S * 0.86), (c, S * 0.82), (c, S * 0.9), (c - S * 0.1, S * 0.92)], fill=255)
    for k in range(5):
        _ell(d2, c - S * (0.03 + 0.035 * k), S * (0.6 - 0.05 * k), S * 0.01, S * 0.01, 0)
    a1 = np.asarray(m1, np.float32) / 255
    a2 = np.asarray(m2, np.float32) / 255
    fi = Image.new("L", (S, S), 0)
    ImageDraw.Draw(fi).polygon(outer, fill=255)
    a3 = np.asarray(fi, np.float32) / 255
    a3 = np.maximum(a3, a3[:, ::-1])
    a1 = np.maximum(a1, a1[:, ::-1])
    a2 = np.maximum(a2, a2[:, ::-1])
    # corner filler: small 4-way rosette at the corners (drawn once at centre then rolled)
    f = Image.new("L", (S, S), 0)
    df = ImageDraw.Draw(f)
    for k in range(8):
        a = k * 45
        rr = S * (0.075 if k % 2 == 0 else 0.05)
        _ell(df, c + math.cos(math.radians(a)) * rr, c + math.sin(math.radians(a)) * rr, rr * 0.7, rr * 0.25, a)
    _ell(df, c, c, S * 0.025, S * 0.025, 0, 0)
    fa = np.roll(np.asarray(f, np.float32) / 255, (S // 2, S // 2), (0, 1))
    a1 = np.maximum(a1, fa)
    return a1, a2, a3


def carpet(name, field, pat, accent, variant, cell=128, wear=0.35):
    cv = Canvas(N, N, SS, tile=True, name=name)
    r = cv.rnd
    W, H = cv.W, cv.H
    fib = pnoise(W, H, W // 3, H // 3, r) * 0.5 + fbm(W, H, 64, 64, r, 2) * 0.5
    cv.rgb[:] = col(field)[None, None, :] * (0.9 + 0.22 * fib[..., None])
    cv.a[:] = 1
    S = cell * SS
    a1, a2, a3 = damask_cell(S, variant)
    reps = N // cell
    m1 = np.tile(a1, (reps, reps))
    m2 = np.tile(a2, (reps, reps))
    m3 = np.tile(a3, (reps, reps))
    cv.tint(m3, mix3(field, pat, 0.35), 0.9)
    # tone-on-tone diaper ground (small lattice)
    x = np.arange(W)[None, :]
    y = np.arange(H)[:, None]
    p = cell * SS / 8
    lat = (np.abs(((x + y) % p) - p / 2) < SS * 0.6) | (np.abs(((x - y) % p) - p / 2) < SS * 0.6)
    cv.tint(lat.astype(np.float32) * (1 - dilate(m1, 3 * SS, True)), col(field) * 0.78, 0.6)
    patc = col(pat)[None, None, :] * (0.88 + 0.24 * fib[..., None])
    accc = col(accent)[None, None, :] * (0.88 + 0.24 * fib[..., None])
    outline = col(field) * 0.3
    o = dilate(m1, 1.3 * SS, True, cv.wob())
    cv.tint(o, outline, 0.9)
    cv.tint(m1, patc, 1)
    from core import edge_band
    eb = edge_band(m1, 1.5 * SS, 1.5 * SS, 1.0 * SS, True)
    cv.mul(eb, 0.4)
    cv.screen(edge_band(m1, -1.2 * SS, -1.2 * SS, 0.8 * SS, True), 0.18, (240, 220, 190))
    cv.tint(dilate(m2, 0.7 * SS, True) * m1, outline, 0.7)
    cv.tint(m2, accc, 1)
    # wear: faded, threadbare patches + dark traffic
    n = cv.noise(4, 4, 4, seed="wear")
    worn = smoothstep(0.66, 0.98, n) * wear
    cv.screen(worn, 0.5, (160, 140, 120))
    cv.mul(smoothstep(0.4, 0.05, n), 0.32, (20, 15, 15))
    cv.hatch(smoothstep(0.45, 0.1, n), 35, 3.2, 0.6, 0.25)
    st = smoothstep(0.8, 0.84, cv.noise(6, 6, 3, seed="stain"))
    cv.mul(st, 0.22, (40, 25, 20))
    # pile fibres
    fl = pnoise(W, H, W // 2, H // 6, r)
    cv.rgb *= (0.94 + 0.12 * fl[..., None])
    return finish_floor(cv, f"floors/{name}.png", 0.07)



def crack(cv, x, y, length, rnd, width=0.7, color=INK, op=0.85):
    pts = [(x, y)]
    a = rnd.random() * 2 * math.pi
    for _ in range(int(length / 4)):
        a += rnd.normal(0, 0.5)
        x += math.cos(a) * 4
        y += math.sin(a) * 4
        pts.append((x, y))
    m = cv.mask().line(pts, width)
    cv.tint(m, color, op)
    if rnd.random() < 0.6 and len(pts) > 4:
        i = int(rnd.integers(1, len(pts) - 2))
        bx, by = pts[i]
        b = [(bx, by)]
        a2 = a + rnd.choice([-1, 1]) * 1.0
        for _ in range(int(length / 10)):
            a2 += rnd.normal(0, 0.5)
            bx += math.cos(a2) * 3
            by += math.sin(a2) * 3
            b.append((bx, by))
        cv.tint(cv.mask().line(b, width * 0.7), color, op * 0.8)


def tile_checker():
    name = "tile_checker"
    cv = Canvas(N, N, SS, tile=True, name=name)
    r = cv.rnd
    t = 32
    g = 1.2
    polys, kinds = [], []
    for j in range(N // t):
        for i in range(N // t):
            polys.append(rrect_pts(i * t + g, j * t + g, (i + 1) * t - g, (j + 1) * t - g, 1.5))
            kinds.append((i + j) % 2)
    lab = label_map(cv, polys, wobble=0.25)
    kind = np.array([2] + kinds)
    tone = 0.9 + 0.18 * r.random(len(polys) + 1)
    W, H = cv.W, cv.H
    marble = fbm(W, H, 8, 8, r, 5)
    veins = smoothstep(0.9, 1.0, 1 - np.abs(np.sin((marble * 6 + fbm(W, H, 4, 4, r, 3) * 3) * math.pi)))
    ivory = col("#cdc2aa")[None, None, :] * (0.92 + 0.12 * marble[..., None])
    ivory = ivory * (1 - 0.18 * veins[..., None])
    black = col("#1e1d1f")[None, None, :] * (0.85 + 0.4 * marble[..., None])
    black = black + 40 * veins[..., None] * 0.6
    grout = col("#4a4540")
    kl = kind[lab]
    out = np.where((kl == 0)[..., None], ivory, black)
    out = np.where((kl == 2)[..., None], grout[None, None, :], out)
    out = out * tone[lab][..., None]
    cv.rgb[:] = out
    cv.a[:] = 1
    edges = seam_mask(lab)
    bevel(cv, edges, 2.0, 1.2, 0.5, 0.3)
    # grime in grout & noise
    n = cv.noise(5, 5, 4, seed="grime")
    cv.mul(smoothstep(0.55, 0.95, n), 0.4, (60, 48, 35))
    # hatch the black tiles a bit (ink texture)
    cv.hatch((kl == 1).astype(np.float32) * smoothstep(0.3, 0.8, n), 45, 3.0, 0.6, 0.35, color=(70, 66, 64))
    cv.hatch((kl == 0).astype(np.float32) * smoothstep(0.6, 0.9, n), -45, 3.2, 0.5, 0.25)
    for _ in range(16):
        crack(cv, r.random() * N, r.random() * N, 10 + r.random() * 30, r, 0.7)
    # chips
    for _ in range(14):
        i, j = r.integers(0, N // t, 2)
        cx = i * t + (0 if r.random() < 0.5 else t)
        cy = j * t + (0 if r.random() < 0.5 else t)
        m = cv.mask().ellipse(cx, cy, 2 + r.random() * 3, 2 + r.random() * 2, wobble=0.6)
        cv.tint(m, "#3a3530", 0.9)
    ink_seams(cv, edges, 1.1, op=0.8)
    return finish_floor(cv, "floors/tile_checker.png")


def tile_white():
    name = "tile_white"
    cv = Canvas(N, N, SS, tile=True, name=name)
    r = cv.rnd
    cols, rows = 16, 14
    sx = N / (cols * 1.5) * 1.0   # hex radius in x
    sy = N / rows / 2              # half height
    rx = N / cols / 1.5 * 1.0
    polys = []
    g = 1.6
    for ci in range(cols):
        for rj in range(rows):
            cx = ci * N / cols
            cy = rj * N / rows + (N / rows / 2 if ci % 2 else 0)
            R = (N / cols) / 1.5 * 1.0
            pts = []
            for k in range(6):
                a = math.radians(60 * k)
                pts.append((cx + (R - g) * math.cos(a), cy + (sy - g) * math.sin(a) / math.sin(math.radians(60))))
            polys.append(pts)
    lab = label_map(cv, polys, wobble=0.2)
    W, H = cv.W, cv.H
    tone = 0.9 + 0.14 * r.random(len(polys) + 1)
    n = fbm(W, H, 6, 6, r, 5)
    base = col("#d9d5c8")[None, None, :] * (0.93 + 0.1 * n[..., None])
    grout = col("#6f6a62")
    out = np.where((lab == 0)[..., None], grout[None, None, :], base * tone[lab][..., None])
    # some tiles stained/yellowed
    yel = r.random(len(polys) + 1) < 0.15
    out = np.where(yel[lab][..., None], out * col("#e9dcc0") / 235.0, out)
    cv.rgb[:] = out
    cv.a[:] = 1
    edges = seam_mask(lab)
    bevel(cv, edges, 2.0, 1.2, 0.35, 0.35, (60, 66, 80))
    g2 = cv.noise(4, 4, 4, seed="grime")
    cv.mul(smoothstep(0.6, 0.95, g2), 0.35, (90, 80, 60))
    cv.hatch(smoothstep(0.65, 0.95, g2), 50, 3.0, 0.5, 0.25)
    for _ in range(22):
        crack(cv, r.random() * N, r.random() * N, 12 + r.random() * 40, r, 0.6, (40, 36, 34), 0.8)
    ink_seams(cv, edges, 1.2, color=(42, 38, 36), op=0.85)
    return finish_floor(cv, "floors/tile_white.png")


def stone():
    name = "stone"
    cv = Canvas(N, N, SS, tile=True, name=name)
    r = cv.rnd
    heights = [96, 64, 96, 128, 64, 64]
    polys = []
    y = 0
    for h in heights:
        while True:
            k = r.integers(3, 6)
            cuts = np.sort(r.integers(0, N, k))
            gaps = np.diff(np.concatenate([cuts, [cuts[0] + N]]))
            if gaps.min() >= 64:
                break
        for i, c0 in enumerate(cuts):
            c1 = c0 + gaps[i]
            g = 2.5
            polys.append(rrect_pts(c0 + g, y + g, c1 - g, y + h - g, 6 + r.random() * 6))
        y += h
    lab = label_map(cv, polys, wobble=1.4)
    W, H = cv.W, cv.H
    n = fbm(W, H, 10, 10, r, 5)
    n2 = fbm(W, H, 3, 3, r, 3)
    base = col("#5d5e60")[None, None, :] * (0.78 + 0.4 * n[..., None])
    hue = r.random(len(polys) + 1)
    tint = np.stack([0.95 + 0.1 * hue, 0.95 + 0.05 * hue, 1.05 - 0.1 * hue], -1)
    tone = 0.75 + 0.35 * r.random(len(polys) + 1)
    grout = col("#24221f")[None, None, :] * (0.8 + 0.4 * n[..., None])
    out = np.where((lab == 0)[..., None], grout, base * (tone[:, None] * tint)[lab])
    cv.rgb[:] = out
    cv.a[:] = 1
    edges = seam_mask(lab)
    dk = bevel(cv, edges, 4.0, 3.0, 0.55, 0.3)
    cv.hatch(dk, 45, 2.8, 0.7, 0.55)
    cv.crosshatch(smoothstep(0.62, 0.9, n2) * (lab > 0), 0.3, 3.2, 0.6)
    # pitting
    pit = smoothstep(0.83, 0.9, pnoise(W, H, 120, 120, r))
    cv.mul(pit, 0.6, (10, 10, 10))
    # moss near grout
    moss = blur(edges, 4 * cv.ss, True) * smoothstep(0.55, 0.8, cv.noise(5, 5, 3, seed="moss"))
    cv.tint(np.clip(moss * 2, 0, 1), "#3d4630", 0.5)
    for _ in range(20):
        crack(cv, r.random() * N, r.random() * N, 20 + r.random() * 50, r, 0.9)
    ink_seams(cv, edges, 1.8)
    return finish_floor(cv, "floors/stone.png")


# --------------------------------------------------------------------------
# organic grounds (drawn straight onto an RGB image with wrap)
# --------------------------------------------------------------------------
def _wrap_draw(cv):
    img = Image.fromarray(np.clip(cv.rgb, 0, 255).astype(np.uint8), "RGB")
    d = ImageDraw.Draw(img)
    offs = [(ox, oy) for ox in (-cv.W, 0, cv.W) for oy in (-cv.H, 0, cv.H)]
    return img, d, offs


def _close_wrap(cv, img):
    cv.rgb = np.asarray(img, np.float32).copy()


def dirt():
    name = "dirt"
    cv = Canvas(N, N, SS, tile=True, name=name)
    r = cv.rnd
    W, H = cv.W, cv.H
    n = fbm(W, H, 6, 6, r, 6)
    n2 = fbm(W, H, 24, 24, r, 3)
    c0, c1 = col("#2c2219"), col("#5e4a35")
    cv.rgb[:] = c0 + (c1 - c0) * (0.6 * n + 0.4 * n2)[..., None]
    cv.a[:] = 1
    cv.crosshatch(smoothstep(0.55, 0.15, n), 0.35, 3.4, 0.6)
    img, d, offs = _wrap_draw(cv)
    ss = SS
    # pebbles
    for _ in range(260):
        x, y = r.random() * W, r.random() * H
        rr = (1.2 + r.random() ** 2 * 4) * ss
        t = r.random()
        fill = tuple(int(v) for v in mix3("#4a4038", "#8a7a66", t))
        for ox, oy in offs:
            d.ellipse([x + ox - rr - 1.4 * ss, y + oy - rr - 1.4 * ss, x + ox + rr + 1.4 * ss, y + oy + rr * 0.8 + 1.4 * ss], fill=INK)
            d.ellipse([x + ox - rr, y + oy - rr, x + ox + rr, y + oy + rr * 0.8], fill=fill)
            d.ellipse([x + ox - rr * 0.6, y + oy - rr * 0.7, x + ox - rr * 0.05, y + oy - rr * 0.2],
                      fill=tuple(min(255, int(v * 1.3)) for v in fill))
    # straw
    for _ in range(420):
        x, y = r.random() * W, r.random() * H
        a = r.random() * math.pi
        ln = (8 + r.random() * 22) * ss
        bend = r.normal(0, 0.15)
        pts = [(x + math.cos(a + bend * t) * ln * t, y + math.sin(a + bend * t) * ln * t) for t in np.linspace(0, 1, 5)]
        t = r.random()
        fill = tuple(int(v) for v in mix3("#6e5a32", "#b39a5c", t))
        w = int((0.8 + r.random()) * ss)
        for ox, oy in offs:
            q = [(px + ox, py + oy) for px, py in pts]
            d.line([(px + 1.2 * ss, py + 1.2 * ss) for px, py in q], fill=(25, 18, 12), width=w + 2)
            d.line(q, fill=fill, width=w)
    _close_wrap(cv, img)
    cv.mul(smoothstep(0.6, 0.95, cv.noise(4, 4, 3, seed="dk")), 0.35)
    return finish_floor(cv, "floors/dirt.png", 0.09)


def mix3(a, b, t):
    a, b = col(a), col(b)
    return a + (b - a) * t


def grass():
    name = "grass"
    cv = Canvas(N, N, SS, tile=True, name=name)
    r = cv.rnd
    W, H = cv.W, cv.H
    n = fbm(W, H, 5, 5, r, 5)
    c0, c1 = col("#141d15"), col("#2b3a25")
    cv.rgb[:] = c0 + (c1 - c0) * n[..., None]
    cv.a[:] = 1
    cv.hatch(np.ones((H, W), np.float32), 60, 2.6, 0.5, 0.25)
    img, d, offs = _wrap_draw(cv)
    ss = SS
    clump = fbm(W, H, 6, 6, rng("grass:clump"), 3)
    pal = [("#0c110b", "#18221a"), ("#223020", "#34452a"), ("#33452b", "#56673c"), ("#55663b", "#7f8a52")]
    for li in range(4):
        count = [2600, 3400, 2600, 900][li]
        for _ in range(count):
            x, y = r.random() * W, r.random() * H
            cl = clump[int(y) % H, int(x) % W]
            if li >= 2 and cl < 0.25 + 0.1 * li:
                continue
            nb = int(r.integers(5, 11))
            for _b in range(nb):
                a = r.random() * 2 * math.pi
                ln = (2 + r.random() * (3 + 1.5 * li)) * ss
                bend = r.normal(0, 0.4)
                pts = [(x + math.cos(a + bend * t) * ln * t, y + math.sin(a + bend * t) * ln * t)
                       for t in np.linspace(0, 1, 4)]
                fill = tuple(int(v) for v in mix3(pal[li][0], pal[li][1], r.random()))
                w = max(1, int((0.5 + r.random() * 0.7) * ss))
                for ox, oy in offs:
                    q = [(px + ox, py + oy) for px, py in pts]
                    if li >= 2 and _b % 3 == 0:
                        d.line([(px + 0.9 * ss, py + 0.9 * ss) for px, py in q], fill=(6, 9, 7), width=w + 1)
                    d.line(q, fill=fill, width=w)
    # clover / weed rosettes and a few fallen leaves
    for _ in range(40):
        x, y = r.random() * W, r.random() * H
        for k in range(3):
            a = k * 2.1 + r.random()
            px, py = x + math.cos(a) * 2.2 * ss, y + math.sin(a) * 2.2 * ss
            rr = 2.2 * ss
            for ox, oy in offs:
                d.ellipse([px - rr + ox, py - rr + oy, px + rr + ox, py + rr + oy], fill=(48, 66, 40), outline=(10, 14, 10))
    for _ in range(24):
        x, y = r.random() * W, r.random() * H
        rr = (3 + r.random() * 3) * ss
        a = r.random() * 360
        fill = tuple(int(v) for v in mix3("#4a3220", "#7a5a30", r.random()))
        pts = ellipse_pts(x, y, rr, rr * 0.45, 16, a)
        for ox, oy in offs:
            q = [(px + ox, py + oy) for px, py in pts]
            d.polygon(q, fill=fill, outline=INK)
    _close_wrap(cv, img)
    cv.mul(smoothstep(0.4, 0.05, n), 0.3, (5, 8, 10))
    return finish_floor(cv, "floors/grass.png", 0.07)


def gravel():
    name = "gravel"
    cv = Canvas(N, N, SS, tile=True, name=name)
    r = cv.rnd
    W, H = cv.W, cv.H
    n = fbm(W, H, 6, 6, r, 4)
    cv.rgb[:] = col("#1d1b19")[None, None, :] * (0.8 + 0.4 * n[..., None])
    cv.a[:] = 1
    img, d, offs = _wrap_draw(cv)
    ss = SS
    for _ in range(5200):
        x, y = r.random() * W, r.random() * H
        rr = (2.0 + r.random() ** 1.6 * 4.5) * ss
        rot = r.random() * 180
        t = r.random()
        base = mix3("#4c4a47", "#9a9184", t) * (0.85 + 0.25 * n[int(y) % H, int(x) % W])
        if r.random() < 0.2:
            base = base * np.array([1.05, 0.98, 0.88])
        fill = tuple(int(min(255, v)) for v in base)
        pts = ellipse_pts(x, y, rr, rr * (0.6 + 0.35 * r.random()), 12, rot)
        jit = [(px + r.normal(0, 0.25 * ss), py + r.normal(0, 0.25 * ss)) for px, py in pts]
        hl = [(x + (px - x) * 0.45 - rr * 0.3, y + (py - y) * 0.45 - rr * 0.3) for px, py in jit]
        sh = [(px + 1.4 * ss, py + 1.6 * ss) for px, py in jit]
        for ox, oy in offs:
            d.polygon([(px + ox, py + oy) for px, py in sh], fill=(10, 9, 8))
            d.polygon([(px + ox, py + oy) for px, py in jit], fill=fill, outline=(22, 20, 18))
            d.polygon([(px + ox, py + oy) for px, py in hl], fill=tuple(min(255, int(v * 1.18)) for v in fill))
    _close_wrap(cv, img)
    cv.mul(smoothstep(0.55, 0.1, cv.noise(4, 4, 3, seed="dk")), 0.35)
    cv.hatch(smoothstep(0.5, 0.15, cv.noise(4, 4, 3, seed="dk")), 45, 3.2, 0.6, 0.25)
    return finish_floor(cv, "floors/gravel.png", 0.06)


def wall_top():
    name = "wall_top"
    S = 128
    cv = Canvas(S, S, 4, tile=True, name=name)
    r = cv.rnd
    bw, bh = 32, 16
    polys = []
    for j in range(S // bh):
        off = (bw / 2) * (j % 2)
        for i in range(-1, S // bw + 1):
            x0 = i * bw + off
            polys.append(rrect_pts(x0 + 1.2, j * bh + 1.2, x0 + bw - 1.2, (j + 1) * bh - 1.2, 1.5))
    lab = label_map(cv, polys, wobble=0.35)
    W, H = cv.W, cv.H
    n = fbm(W, H, 8, 8, r, 5)
    tone = 0.75 + 0.4 * r.random(len(polys) + 1)
    hue = r.random(len(polys) + 1)
    tint = np.stack([1.0 + 0.12 * hue, 0.96 + 0 * hue, 0.95 - 0.05 * hue], -1)
    base = col("#3b3434")[None, None, :] * (0.8 + 0.4 * n[..., None])
    mortar = col("#151313")
    out = np.where((lab == 0)[..., None], mortar[None, None, :], base * (tone[:, None] * tint)[lab])
    cv.rgb[:] = out
    cv.a[:] = 1
    edges = seam_mask(lab)
    dk = bevel(cv, edges, 2.0, 1.2, 0.55, 0.22)
    cv.hatch(dk, 45, 1.6, 0.4, 0.5)
    cv.crosshatch(smoothstep(0.6, 0.95, n), 0.35, 1.8, 0.35)
    ink_seams(cv, edges, 0.9)
    cv.grain(0.08)
    img = cv.image().convert("RGB")
    save(img, "walls/wall_top.png", opaque=True)
    return img


def build_all():
    planks("wood_dark", "#4b3427", "#1f140e", "#6a4c37", board=32, wear=0.12)
    planks("wood_light", "#8a6c4c", "#4a3423", "#a88a66", board=32, wear=0.2, scuff=0.6)
    parquet()
    carpet("carpet_red", "#4e1918", "#7a3328", "#a8834e", 0)
    carpet("carpet_blue", "#223047", "#4a5e78", "#a39f8a", 1)
    carpet("carpet_green", "#232e1c", "#4b5934", "#9a8650", 2)
    tile_checker()
    tile_white()
    stone()
    dirt()
    grass()
    gravel()
    wall_top()


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        for f in sys.argv[1:]:
            globals()[f]()
    else:
        build_all()
