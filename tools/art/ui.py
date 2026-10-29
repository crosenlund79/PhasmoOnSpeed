"""UI pieces, title logo, banners, menu background, vignette and light textures."""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw

from core import (Canvas, INK, blur, catmull, col, dilate, ellipse_pts, erode, fbm, font, gradient, mix,
                  pnoise, radial, rng, rrect_pts, save, smoothstep, edge_band)

GOLD = "#b8964e"
GOLD_HI = "#e8cf8a"
CHAR = "#26231f"


# --------------------------------------------------------------------------
# parchment
# --------------------------------------------------------------------------
def parchment_tex(W, H, seed="parchment", tile=True, ss=1):
    r = rng(seed)
    n1 = fbm(W, H, 4, 4, r, 5)
    n2 = fbm(W, H, 16, 16, r, 3)
    base = col("#d9c7a0")
    c = base[None, None, :] * (0.86 + 0.16 * n1[..., None] + 0.06 * n2[..., None])
    # yellowed / browned blotches
    bl = smoothstep(0.55, 0.9, fbm(W, H, 3, 3, r, 4))
    c = c * (1 - bl[..., None] * 0.18 * np.array([0.6, 0.9, 1.4]))
    # stain rings (tide lines)
    st = fbm(W, H, 5, 5, r, 3)
    ring = smoothstep(0.02, 0.0, np.abs(st - 0.72)) * smoothstep(0.6, 0.75, st + 0.05)
    c = c * (1 - ring[..., None] * 0.1)
    c = c * (1 - smoothstep(0.72, 0.9, st)[..., None] * 0.08)
    # fibres
    img = Image.new("L", (W, H), 128)
    d = ImageDraw.Draw(img)
    offs = [(ox, oy) for ox in (-W, 0, W) for oy in (-H, 0, H)] if tile else [(0, 0)]
    for _ in range(int(W * H / 900)):
        x, y = r.random() * W, r.random() * H
        a = r.random() * math.pi
        ln = (3 + r.random() * 14) * ss
        b = r.normal(0, 0.4)
        pts = [(x + math.cos(a + b * t) * ln * t, y + math.sin(a + b * t) * ln * t) for t in np.linspace(0, 1, 4)]
        v = 128 + int(r.choice([-1, 1]) * (10 + r.random() * 22))
        for ox, oy in offs:
            d.line([(px + ox, py + oy) for px, py in pts], fill=v, width=max(1, ss))
    fib = (np.asarray(img, np.float32) - 128) / 128
    c = c * (1 + fib[..., None] * 0.12)
    # foxing spots
    fx = smoothstep(0.86, 0.92, pnoise(W, H, max(4, W // 10), max(4, H // 10), r))
    c = c * (1 - fx[..., None] * 0.25 * np.array([0.7, 1.0, 1.3]))
    # fine grain
    g = pnoise(W, H, max(4, W // 2), max(4, H // 2), r)
    c = c * (0.96 + 0.08 * g[..., None])
    return np.clip(c, 0, 255).astype(np.float32)


def parchment():
    W = 512
    t = parchment_tex(W, W, "parchment", True, 1)
    save(Image.fromarray(t.astype(np.uint8), "RGB"), "ui/parchment.png", opaque=True)


# --------------------------------------------------------------------------
# nine-slice frames
# --------------------------------------------------------------------------
def nine_clean(img, m):
    """Make the stretchable bands of a 9-slice image uniform along their stretch axis."""
    a = np.asarray(img).copy()
    H, W = a.shape[:2]
    cxm, cym = W // 2, H // 2
    a[:m, m:W - m] = a[:m, cxm:cxm + 1]
    a[H - m:, m:W - m] = a[H - m:, cxm:cxm + 1]
    a[m:H - m, :m] = a[cym:cym + 1, :m]
    a[m:H - m, W - m:] = a[cym:cym + 1, W - m:]
    return Image.fromarray(a, img.mode)


def fleuron(cv, x, y, s, color, ang):
    """small corner ornament: leaf + dot"""
    ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    R = lambda px, py: (x + px * ca - py * sa, y + px * sa + py * ca)
    m = cv.mask()
    m.poly([R(*p) for p in catmull([(0, 0), (s * 0.9, s * 0.25), (s * 1.5, 0), (s * 0.9, -s * 0.25), (0, 0)], 5)])
    m.poly([R(*p) for p in catmull([(0, 0), (s * 0.25, s * 0.9), (0, s * 1.5), (-s * 0.25, s * 0.9), (0, 0)], 5)])
    m.circle(*R(s * 0.75, s * 0.75), s * 0.28)
    cv.paint(dilate(m.arr, 0.5 * cv.ss), INK, 0.8)
    cv.paint(m, color)


def frame(name, W, H, m, center, border="#2a2724", rule=GOLD, glow=None, pressed=False, radius=6.0,
          border_w=7.0, rule_in=10.5, ornaments=True):
    cv = Canvas(W, H, 4, name="ui:" + name)
    # outer charcoal border plate
    outer = cv.mask().rect(1.2, 1.2, W - 1.2, H - 1.2, radius)
    tex = np.clip(col(border)[None, None, :] * (0.85 + 0.3 * fbm(cv.W, cv.H, 6, 6, rng(name), 4)[..., None]), 0, 255)
    cv.paint(dilate(outer.arr, 1.0 * cv.ss), INK)
    cv.paint(outer, tex)
    cv.hatch(outer.arr, 45, 1.3, 0.35, 0.35, color=(10, 9, 8))
    # bevel on plate
    d = 2.0 * cv.ss
    if pressed:
        cv.mul(edge_band(outer.arr, -d, -d, d), 0.6, (0, 0, 0))
        cv.screen(edge_band(outer.arr, d, d, d), 0.18)
    else:
        cv.screen(edge_band(outer.arr, -d, -d, d), 0.22, (220, 200, 170))
        cv.mul(edge_band(outer.arr, d, d, d), 0.5, (0, 0, 0))
    # inner field
    inner = cv.mask().rect(border_w, border_w, W - border_w, H - border_w, max(1, radius - 3))
    if isinstance(center, np.ndarray):
        fill = center
    else:
        fill = np.clip(col(center)[None, None, :] * (0.97 + 0.06 * fbm(cv.W, cv.H, 3, 3, rng(name + "c"), 3)[..., None]),
                       0, 255)
    cv.paint(dilate(inner.arr, 0.8 * cv.ss), INK)
    cv.paint(inner, fill)
    # inner shadow from the frame
    cv.mul(edge_band(inner.arr, -2.2 * cv.ss, -2.2 * cv.ss, 1.6 * cv.ss), 0.45, (20, 14, 8))
    cv.mul(edge_band(inner.arr, 1.2 * cv.ss, 1.2 * cv.ss, 1.0 * cv.ss), 0.2, (20, 14, 8))
    # thin gold rule
    ri = rule_in
    pts = rrect_pts(ri, ri, W - ri, H - ri, max(1, radius - 4), 6)
    cv.stroke(pts + [pts[0]], 1.7, INK, 0.7)
    cv.stroke(pts + [pts[0]], 0.9, rule, 1.0)
    if ornaments:
        for (x, y, a) in ((ri + 1.5, ri + 1.5, 0), (W - ri - 1.5, ri + 1.5, 90), (W - ri - 1.5, H - ri - 1.5, 180),
                          (ri + 1.5, H - ri - 1.5, 270)):
            fleuron(cv, x, y, 5.0, rule, a)
    # corner rivets on the plate
    for (x, y) in ((4.2, 4.2), (W - 4.2, 4.2), (4.2, H - 4.2), (W - 4.2, H - 4.2)):
        cv.paint(cv.mask().circle(x, y, 1.5), INK)
        cv.paint(cv.mask().circle(x - 0.2, y - 0.2, 1.0), rule)
    if glow is not None:
        g = edge_band(inner.arr, 0, 0, 1) * 0
        ring = np.clip(dilate(inner.arr, 2.0 * cv.ss) - erode(inner.arr, 3.0 * cv.ss), 0, 1)
        cv.glow(blur(ring, 2 * cv.ss) * inner.arr, glow, 0.35)
    cv.grain(0.05)
    img = cv.image()
    return nine_clean(img, m)


def panels():
    W = 96
    img = frame("panel_frame", W, W, 24, "#d6c49e", border="#2c2925", rule=GOLD, border_w=7.5, rule_in=11)
    save(img, "ui/panel_frame.png")
    img = frame("panel_dark", W, W, 24, "#1f1d1b", border="#33302c", rule=GOLD, border_w=7.5, rule_in=11)
    save(img, "ui/panel_dark.png")
    # buttons 96x48, 16 px margins
    for nm, cen, rule, glow, pressed in (("button", "#3a2f26", "#9a7c44", None, False),
                                         ("button_hover", "#4a3a2a", GOLD_HI, (255, 190, 100), False),
                                         ("button_pressed", "#2a221c", "#8a6c38", None, True)):
        img = frame(nm, 96, 48, 16, cen, border="#24211e", rule=rule, glow=glow, pressed=pressed, radius=5,
                    border_w=5.0, rule_in=7.5, ornaments=False)
        save(img, f"ui/{nm}.png")
    # hotbar slots
    for nm, rule, glow in (("slot", "#7a6438", None), ("slot_selected", GOLD_HI, (255, 200, 110))):
        cv_img = frame(nm, 64, 64, 16, "#1a1816", border="#2e2b27" if nm == "slot" else "#3e3424", rule=rule,
                       glow=glow, radius=6, border_w=6.0, rule_in=9.0, ornaments=nm == "slot_selected")
        if nm == "slot_selected":
            # amber outer glow
            a = np.asarray(cv_img).astype(np.float32)
            save(Image.fromarray(a.astype(np.uint8), "RGBA"), f"ui/{nm}.png")
        else:
            save(cv_img, f"ui/{nm}.png")


# --------------------------------------------------------------------------
# lettering
# --------------------------------------------------------------------------
def text_mask(W, H, ss, s, fnt_name, size, y=None, tracking=0):
    img = Image.new("L", (W * ss, H * ss), 0)
    d = ImageDraw.Draw(img)
    maxw = W * ss * 0.94
    while True:
        f = font(fnt_name, int(size * ss))
        widths = [d.textlength(ch, font=f) for ch in s]
        total = sum(widths) + tracking * ss * (len(s) - 1)
        if total <= maxw or size < 10:
            break
        size *= maxw / total * 0.995
    x = (W * ss - total) / 2
    yy = (y if y is not None else H / 2) * ss
    for ch, w in zip(s, widths):
        d.text((x, yy), ch, font=f, fill=255, anchor="lm")
        x += w + tracking * ss
    return np.asarray(img, np.float32) / 255


def distress(cv, m, amount=0.25, seed="d"):
    r = rng(cv.name + seed)
    n = pnoise(cv.W, cv.H, cv.W // 14, cv.H // 14, r)
    n2 = fbm(cv.W, cv.H, 20, 6, r, 3)
    holes = smoothstep(0.78, 0.84, n) * smoothstep(0.4, 0.7, n2)
    edge = m * (1 - erode(m, 2.5 * cv.ss))
    nicks = smoothstep(0.7, 0.8, pnoise(cv.W, cv.H, cv.W // 6, cv.H // 6, r)) * edge
    return np.clip(m - holes * amount * 3 - nicks * amount * 2.5, 0, 1)


def lettering(name, W, H, s, fnt_name, size, fill_tex, edge_color, ink_w=6.0, edge_w=3.0, tracking=0, y=None,
              drips=False, ss=2, rays=None, under=None, distress_amt=0.18, glow=None):
    cv = Canvas(W, H, ss, name=name)
    m = text_mask(W, H, ss, s, fnt_name, size, y, tracking)
    m = distress(cv, m, distress_amt)
    if under is not None:
        under(cv, m)
    if drips:
        r = rng(name + "drip")
        dm = Image.new("L", (cv.W, cv.H), 0)
        d = ImageDraw.Draw(dm)
        # find bottom edges of letters: columns where mask transitions to 0 going down
        bottom = (m > 0.5) & ~(np.roll(m, -3 * ss, 0) > 0.5)
        ys, xs = np.nonzero(bottom)
        if len(xs):
            idx = r.choice(len(xs), size=min(len(xs), 70), replace=False)
            for i in idx:
                x, y0 = xs[i], ys[i]
                ln = (6 + r.random() ** 2 * 38) * ss
                w = (2.0 + r.random() * 3.5) * ss
                d.rounded_rectangle([x - w / 2, y0 - 4 * ss, x + w / 2, y0 + ln], radius=w / 2, fill=255)
                d.ellipse([x - w * 0.8, y0 + ln - w * 0.9, x + w * 0.8, y0 + ln + w * 0.7], fill=255)
            # splatters
            for _ in range(40):
                x = r.random() * cv.W
                y = (H * 0.25 + r.random() * H * 0.6) * ss
                rr = (0.6 + r.random() ** 3 * 4) * ss
                d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=255)
        dmask = np.asarray(dm, np.float32) / 255
        m = np.maximum(m, dmask * (blur(m, 30 * ss) > 0.01))
    # drop shadow (+ optional spectral glow)
    if glow is not None:
        cv.paint(blur(dilate(m, ink_w * ss), 14 * ss), glow, 0.45)
    sh = blur(shift_arr(dilate(m, ink_w * ss), 4 * ss, 6 * ss), 6 * ss)
    cv.paint(sh, (0, 0, 0), 0.65)
    # ink outline, gold edge, fill
    cv.paint(dilate(m, (ink_w + edge_w) * ss, wobble=cv.wob()), INK)
    cv.paint(dilate(m, edge_w * ss), edge_color if not isinstance(edge_color, np.ndarray) else edge_color)
    cv.paint(dilate(m, 0.9 * ss), INK, 0.9)
    cv.paint(m, fill_tex)
    # inner bevel lighting on the fill
    cv.screen(edge_band(m, -2.5 * ss, -2.5 * ss, 2 * ss), 0.35, (255, 240, 210))
    cv.mul(edge_band(m, 2.5 * ss, 2.5 * ss, 2 * ss), 0.45, (0, 0, 0))
    cv.hatch(m * smoothstep(0.3, 0.9, fbm(cv.W, cv.H, 10, 4, rng(name + "h"), 3)), 45, 3.0, 0.8, 0.35,
             color=(10, 8, 8))
    cv.grain(0.06)
    return cv, m


def shift_arr(a, dx, dy):
    from core import shift
    return shift(a, dx, dy)


def gold_tex(W, H, seed):
    r = rng(seed)
    g = gradient(W, H, GOLD_HI, "#6a4e1e", 80)
    n = fbm(W, H, 30, 8, r, 3)
    return np.clip(g * (0.85 + 0.3 * n[..., None]), 0, 255).astype(np.float32)


def title_logo():
    W, H = 1200, 300
    ss = 2
    fill = np.clip(gradient(W * ss, H * ss, "#3a363c", "#121014", 90)
                   * (0.85 + 0.35 * fbm(W * ss, H * ss, 30, 8, rng("logo"), 3)[..., None]), 0, 255)
    edge = gold_tex(W * ss, H * ss, "logoedge")

    def under(cv, m):
        # flourish rule under the title
        y = 248
        for (x0, x1) in ((150, 520), (680, 1050)):
            ln = cv.mask().line([(x0, y), (x1, y)], 3.2)
            cv.paint(dilate(ln.arr, 2 * ss), INK, 0.9)
            cv.paint(ln, gold_tex(cv.W, cv.H, "fl"))
        dm = cv.mask().poly([(600, y - 14), (618, y), (600, y + 14), (582, y)])
        dm.poly([(540, y - 7), (552, y), (540, y + 7), (528, y)])
        dm.poly([(660, y - 7), (672, y), (660, y + 7), (648, y)])
        cv.paint(dilate(dm.arr, 2 * ss), INK)
        cv.paint(dm, gold_tex(cv.W, cv.H, "fl"))
        for x in (150, 1050):
            c = cv.mask().circle(x, y, 6)
            cv.paint(dilate(c.arr, 2 * ss), INK)
            cv.paint(c, gold_tex(cv.W, cv.H, "fl"))

    cv, m = lettering("title_logo", W, H, "SPECTRAL RUN", "IMFellEnglishSC-Regular.ttf", 176, fill, edge,
                      ink_w=5.0, edge_w=3.4, tracking=10, y=132, ss=ss, under=under, distress_amt=0.14,
                      glow=(150, 200, 215))
    # a few ink splatters
    r = rng("logo_splat")
    for _ in range(26):
        x, y = 80 + r.random() * 1040, 40 + r.random() * 200
        rr = 0.8 + r.random() ** 3 * 4
        c = cv.mask().circle(x, y, rr)
        cv.paint(c, INK, 0.9 * float(blur(m, 20 * ss)[int(y * ss), int(x * ss)] > 0.02))
    # subtle spectral glow behind
    save(cv.image(), "ui/title_logo.png")


def banners():
    W, H = 1000, 220
    ss = 2
    bone = np.clip(gradient(W * ss, H * ss, "#f4ecd8", "#b7a888", 90)
                   * (0.9 + 0.2 * fbm(W * ss, H * ss, 30, 8, rng("bone"), 3)[..., None]), 0, 255)

    def rays(cv, m):
        cx, cy = W / 2, H / 2
        for k in range(28):
            a = k * 2 * math.pi / 28
            ln = 520
            ray = cv.mask().poly([(cx, cy), (cx + math.cos(a - 0.04) * ln, cy + math.sin(a - 0.04) * ln * 0.42),
                                  (cx + math.cos(a + 0.04) * ln, cy + math.sin(a + 0.04) * ln * 0.42)])
            fall = np.clip(1 - radial(cv.W, cv.H, cx * ss, cy * ss, 480 * ss), 0, 1) ** 1.5
            cv.paint(ray.arr * fall, (232, 205, 140), 0.35)
        for x0, x1 in ((40, 300), (700, 960)):
            for dy in (-62, 62):
                ln_ = cv.mask().line([(x0, cy + dy), (x1, cy + dy)], 2.2)
                cv.paint(dilate(ln_.arr, 1.6 * ss), INK, 0.8)
                cv.paint(ln_, gold_tex(cv.W, cv.H, "bn"))

    cv, m = lettering("banner_vanquished", W, H, "VANQUISHED!", "IMFellEnglishSC-Regular.ttf", 150, bone,
                      gold_tex(W * ss, H * ss, "vqedge"), ink_w=5.5, edge_w=3.5, tracking=6, y=108, ss=ss, under=rays)
    save(cv.image(), "ui/banner_vanquished.png")
    red = np.clip(gradient(W * ss, H * ss, "#c0242a", "#4a0408", 90)
                  * (0.85 + 0.3 * fbm(W * ss, H * ss, 30, 8, rng("blood"), 3)[..., None]), 0, 255)
    cv, m = lettering("banner_perished", W, H, "PERISHED!", "IMFellEnglishSC-Regular.ttf", 150, red,
                      np.full((H * ss, W * ss, 3), col("#2a0406"), np.float32), ink_w=4.5, edge_w=2.0, tracking=8,
                      y=96, drips=True, ss=ss)
    # wet highlights
    cv.screen(m * smoothstep(0.75, 0.95, fbm(cv.W, cv.H, 40, 12, rng("wet"), 3)), 0.35, (255, 200, 200))
    save(cv.image(), "ui/banner_perished.png")


# --------------------------------------------------------------------------
# vignette & lights
# --------------------------------------------------------------------------
def vignette():
    S = 1024
    d = radial(S, S, S / 2 - 0.5, S / 2 - 0.5, S / 2 * 1.414)
    n = fbm(S, S, 6, 6, rng("vig"), 3)
    a = smoothstep(0.42, 1.0, d + (n - 0.5) * 0.05) ** 1.3
    out = np.zeros((S, S, 4), np.uint8)
    out[..., :3] = (6, 5, 8)
    out[..., 3] = np.clip(a * 255, 0, 255).astype(np.uint8)
    save(Image.fromarray(out, "RGBA"), "ui/vignette.png")


def lights():
    S = 512
    d = radial(S, S, S / 2 - 0.5, S / 2 - 0.5, S / 2)
    a = np.clip(1 - d, 0, 1)
    a = a * a * (3 - 2 * a)
    a = a ** 1.4
    out = np.zeros((S, S, 4), np.uint8)
    out[..., :3] = 255
    out[..., 3] = np.clip(a * 255, 0, 255).astype(np.uint8)
    save(Image.fromarray(out, "RGBA"), "lights/soft.png")
    # cone: origin at the left-centre pixel, pointing +X, ~40 deg total spread
    W, H = 1024, 512
    x = np.arange(W, dtype=np.float32)[None, :]
    y = np.arange(H, dtype=np.float32)[:, None] - (H / 2 - 0.5)
    ang = np.degrees(np.abs(np.arctan2(y, np.maximum(x, 1e-3))))
    dist = np.sqrt(x * x + y * y) / W
    edge = smoothstep(21.0, 12.0, ang)
    fall = np.clip(1 - dist, 0, 1) ** 1.6
    near = smoothstep(0.0, 0.03, dist)
    core = smoothstep(8.0, 0.0, ang) * 0.25 + 0.75
    n = fbm(W, H, 8, 4, rng("cone"), 3)
    a = edge * fall * near * core * (0.94 + 0.12 * n)
    a[:, 0] = np.maximum(a[:, 0], 0)
    out = np.zeros((H, W, 4), np.uint8)
    out[..., :3] = 255
    out[..., 3] = np.clip(a * 255, 0, 255).astype(np.uint8)
    save(Image.fromarray(out, "RGBA"), "lights/cone.png")
    # candle: warm, slightly irregular radial
    S = 256
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    dx, dy = xx - S / 2 + 0.5, yy - S / 2 + 0.5
    th = np.arctan2(dy, dx)
    r = rng("candle")
    ph = r.random(4) * 6.283
    mod = 1 + 0.035 * np.sin(3 * th + ph[0]) + 0.02 * np.sin(5 * th + ph[1]) + 0.012 * np.sin(7 * th + ph[2])
    d = np.sqrt(dx * dx + dy * dy) / (S / 2) / mod
    a = np.clip(1 - d, 0, 1)
    a = (a * a * (3 - 2 * a)) ** 1.25
    out = np.zeros((S, S, 4), np.uint8)
    t = np.clip(1 - d, 0, 1)[..., None]
    c = col("#ffb060") + (col("#fff2d8") - col("#ffb060")) * t ** 2
    out[..., :3] = np.clip(c, 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(a * 255, 0, 255).astype(np.uint8)
    save(Image.fromarray(out, "RGBA"), "lights/candle.png")


# --------------------------------------------------------------------------
# menu background
# --------------------------------------------------------------------------
def menu_background():
    import scene
    scene.menu_background()


def build_all(only=None):
    for f in (parchment, panels, title_logo, banners, vignette, lights, menu_background):
        if only and f.__name__ not in only:
            continue
        f()


if __name__ == "__main__":
    import sys
    build_all(sys.argv[1:] or None)
