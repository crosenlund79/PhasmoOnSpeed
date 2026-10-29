"""Core drawing kit for SPECTRAL RUN provisional art.

Everything is procedural (numpy + Pillow).  A ``Canvas`` is authored at a
supersample factor ``ss`` and downsampled with LANCZOS on ``finish()``.
Coordinates passed to the drawing helpers are always in *final* pixels; the
helpers scale by ``ss`` internally.

Look: heavy ink outlines (mask dilation with a wobbling threshold), hatched
shading on the lower-right of every shape (light from the upper-left),
paper grain, soft baked drop shadows.
"""
from __future__ import annotations

import math
import zlib
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "provisional"
FONTS = ROOT / "assets" / "fonts"

INK = (19, 16, 15)


# --------------------------------------------------------------------------
# small utils
# --------------------------------------------------------------------------
def seed_of(name: str) -> int:
    return zlib.crc32(name.encode("utf-8")) & 0xFFFFFFFF


def rng(name: str) -> np.random.Generator:
    return np.random.default_rng(seed_of(name))


def hexc(s: str) -> np.ndarray:
    s = s.lstrip("#")
    if len(s) == 3:
        s = "".join(ch * 2 for ch in s)
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)


def col(c) -> np.ndarray:
    if isinstance(c, str):
        return hexc(c)
    return np.asarray(c, dtype=np.float32)


def mix(a, b, t):
    a, b = col(a), col(b)
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-9), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(FONTS / name), size)


# --------------------------------------------------------------------------
# noise (periodic value noise -> seamless when cells divide the canvas)
# --------------------------------------------------------------------------
def pnoise(w, h, cx, cy, rnd):
    cx, cy = max(1, int(cx)), max(1, int(cy))
    g = rnd.random((cy, cx)).astype(np.float32)
    xs = np.arange(w, dtype=np.float32) * (cx / w)
    ys = np.arange(h, dtype=np.float32) * (cy / h)
    x0 = np.floor(xs).astype(int)
    y0 = np.floor(ys).astype(int)
    fx = xs - x0
    fy = ys - y0
    x0 %= cx
    y0 %= cy
    x1 = (x0 + 1) % cx
    y1 = (y0 + 1) % cy
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    a = g[np.ix_(y0, x0)]
    b = g[np.ix_(y0, x1)]
    c = g[np.ix_(y1, x0)]
    d = g[np.ix_(y1, x1)]
    top = a + (b - a) * fx[None, :]
    bot = c + (d - c) * fx[None, :]
    return top + (bot - top) * fy[:, None]


def fbm(w, h, cx, cy, rnd, octaves=4, gain=0.5, norm=True):
    tot = np.zeros((h, w), np.float32)
    amp, s = 1.0, 0.0
    for o in range(octaves):
        tot += amp * pnoise(w, h, cx * 2 ** o, cy * 2 ** o, rnd)
        s += amp
        amp *= gain
    tot /= s
    if norm:
        lo, hi = np.percentile(tot, 0.5), np.percentile(tot, 99.5)
        tot = np.clip((tot - lo) / (hi - lo + 1e-9), 0, 1)
    return tot


# --------------------------------------------------------------------------
# filters (numpy, float, optional wrap for tileables)
# --------------------------------------------------------------------------
def _box1d(a, r, axis, wrap):
    if r < 1:
        return a
    n = a.shape[axis]
    widths = [(0, 0)] * a.ndim
    widths[axis] = (r + 1, r)
    if wrap and r + 1 > n:
        reps = [1] * a.ndim
        reps[axis] = 3 + (2 * r) // n
        base = np.tile(a, reps)
        off = n * (reps[axis] // 2)
        idx = np.arange(off - r - 1, off + n + r) % base.shape[axis]
        p = np.take(base, idx, axis=axis)
    else:
        p = np.pad(a, widths, mode="wrap" if wrap else "constant")
    c = np.cumsum(p, axis=axis, dtype=np.float64)
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return ((hi - lo) / (2 * r + 1)).astype(np.float32)


def blur(a, sigma, wrap=False):
    if sigma <= 0.3:
        return a
    r = int(round((math.sqrt(4 * sigma * sigma + 1) - 1) / 2))
    r = max(1, r)
    out = a.astype(np.float32)
    axes = (0, 1)
    for _ in range(3):
        for ax in axes:
            out = _box1d(out, r, ax, wrap)
    return out


def shift(a, dx, dy, wrap=False):
    dx, dy = int(round(dx)), int(round(dy))
    out = np.roll(a, (dy, dx), axis=(0, 1))
    if not wrap:
        if dy > 0:
            out[:dy] = 0
        elif dy < 0:
            out[dy:] = 0
        if dx > 0:
            out[:, :dx] = 0
        elif dx < 0:
            out[:, dx:] = 0
    return out


def dilate(m, r, wrap=False, wobble=None):
    """Round-ish dilation by ~r pixels (canvas px).  ``wobble`` (0..1 array)
    varies the line weight for a hand-inked feel."""
    if r <= 0.5:
        return m
    b = blur(m, r / 2.0, wrap)
    if wobble is not None:
        k = 0.35 + 1.3 * wobble
        out = smoothstep(0.012 * k, 0.06 * k, b)
    else:
        out = smoothstep(0.015, 0.07, b)
    return np.maximum(out, m)


def erode(m, r, wrap=False):
    return 1.0 - dilate(1.0 - m, r, wrap)


def edge_band(m, dx, dy, sigma, wrap=False):
    """Part of mask m lying within ~(dx,dy) of its edge in direction (dx,dy)."""
    sh = shift(m, -dx, -dy, wrap)
    band = m * (1.0 - sh)
    return np.clip(blur(band, sigma, wrap) * 1.6, 0, 1) * m


# --------------------------------------------------------------------------
# geometry helpers
# --------------------------------------------------------------------------
def rrect_pts(x0, y0, x1, y1, r=0.0, n=8):
    r = max(0.0, min(r, (x1 - x0) / 2, (y1 - y0) / 2))
    if r < 0.01:
        return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    pts = []
    for (cx, cy, a0) in ((x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0),
                         (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def ellipse_pts(cx, cy, rx, ry, n=72, rot=0.0, a0=0.0, a1=360.0):
    pts = []
    cr, sr = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    full = abs(a1 - a0) >= 360
    m = n if full else n + 1
    for i in range(m):
        a = math.radians(a0 + (a1 - a0) * i / n)
        x, y = rx * math.cos(a), ry * math.sin(a)
        pts.append((cx + x * cr - y * sr, cy + x * sr + y * cr))
    return pts


def subdivide(pts, step, closed=True):
    pts = [np.array(p, float) for p in pts]
    out = []
    rng_ = range(len(pts)) if closed else range(len(pts) - 1)
    for i in rng_:
        a, b = pts[i], pts[(i + 1) % len(pts)]
        d = np.linalg.norm(b - a)
        k = max(1, int(d / step))
        for j in range(k):
            out.append(a + (b - a) * j / k)
    if not closed:
        out.append(pts[-1])
    return np.array(out)


def wobble_pts(pts, amp, rnd, step=4.0, closed=True):
    """Displace polygon points along their normals with smooth noise."""
    p = subdivide(pts, step, closed)
    if len(p) < 3 or amp <= 0:
        return p
    seg = np.linalg.norm(np.diff(np.vstack([p, p[:1]]), axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)[:-1]])
    ph = rnd.random(3) * 6.283
    lam = np.array([37.0, 15.0, 7.0]) * (step / 4.0)
    off = (0.55 * np.sin(s / lam[0] * 6.283 + ph[0]) + 0.3 * np.sin(s / lam[1] * 6.283 + ph[1])
           + 0.15 * np.sin(s / lam[2] * 6.283 + ph[2]))
    nxt = np.roll(p, -1, axis=0)
    prv = np.roll(p, 1, axis=0)
    t = nxt - prv
    nrm = np.stack([t[:, 1], -t[:, 0]], 1)
    nrm /= (np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-9)
    return p + nrm * (off * amp)[:, None]


def A(m):
    if isinstance(m, Mask):
        return m.arr
    return m


# --------------------------------------------------------------------------
# masks
# --------------------------------------------------------------------------
class Mask:
    def __init__(self, cv: "Canvas"):
        self.cv = cv
        self.img = Image.new("L", (cv.W, cv.H), 0)
        self.d = ImageDraw.Draw(self.img)
        self._arr = None

    # offsets for seamless drawing
    def _offs(self):
        if not self.cv.tile:
            return [(0, 0)]
        W, H = self.cv.W, self.cv.H
        return [(ox, oy) for ox in (-W, 0, W) for oy in (-H, 0, H)]

    def _dirty(self):
        self._arr = None

    def _xf(self, pts):
        p = np.asarray(pts, float)
        xf = self.cv.xf
        if xf is not None:
            s_, cx, cy = xf
            p = np.array([cx, cy]) + (p - np.array([cx, cy])) * s_
        return p

    def poly(self, pts, fill=255, wobble=0.0, step=3.0):
        ss = self.cv.ss
        p = self._xf(pts) * ss
        if wobble > 0:
            p = wobble_pts(p, wobble * ss, self.cv.rnd, step=step * ss)
        for ox, oy in self._offs():
            self.d.polygon([(x + ox, y + oy) for x, y in p], fill=fill)
        self._dirty()
        return self

    def rect(self, x0, y0, x1, y1, r=0.0, fill=255, wobble=0.0):
        return self.poly(rrect_pts(x0, y0, x1, y1, r), fill, wobble)

    def ellipse(self, cx, cy, rx, ry, fill=255, wobble=0.0, rot=0.0, n=None):
        n = n or max(24, int((rx + ry) * 1.5))
        return self.poly(ellipse_pts(cx, cy, rx, ry, n, rot), fill, wobble)

    def circle(self, cx, cy, r, fill=255, wobble=0.0):
        return self.ellipse(cx, cy, r, r, fill, wobble)

    def line(self, pts, width, fill=255, cap=True):
        ss = self.cv.ss
        p = [(x * ss, y * ss) for x, y in self._xf(pts)]
        if self.cv.xf is not None:
            width = width * self.cv.xf[0]
        w = max(1, int(round(width * ss)))
        for ox, oy in self._offs():
            q = [(x + ox, y + oy) for x, y in p]
            self.d.line(q, fill=fill, width=w, joint="curve")
            if cap:
                rr = w / 2.0
                for (x, y) in (q[0], q[-1]):
                    self.d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=fill)
        self._dirty()
        return self

    def curve(self, pts, width, fill=255, n=24):
        """Catmull-Rom smooth stroke through pts."""
        return self.line(catmull(pts, n), width, fill)

    def text(self, xy, s, fnt, fill=255, anchor="mm"):
        ss = self.cv.ss
        for ox, oy in self._offs():
            self.d.text((xy[0] * ss + ox, xy[1] * ss + oy), s, font=fnt, fill=fill, anchor=anchor)
        self._dirty()
        return self

    @property
    def arr(self):
        if self._arr is None:
            self._arr = np.asarray(self.img, dtype=np.float32) / 255.0
        return self._arr


def catmull(pts, n=16):
    p = [np.array(q, float) for q in pts]
    if len(p) < 3:
        return [tuple(q) for q in p]
    p = [p[0]] + p + [p[-1]]
    out = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        for j in range(n):
            t = j / n
            t2, t3 = t * t, t * t * t
            q = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                       + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
            out.append(tuple(q))
    out.append(tuple(p[-2]))
    return out


# --------------------------------------------------------------------------
# hatching
# --------------------------------------------------------------------------
@lru_cache(maxsize=64)
def _hatch_cached(W, H, angle, spacing, width, seed, tile, dash):
    rnd = np.random.default_rng(seed)
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    a = math.radians(angle)
    dvec = np.array([math.cos(a), math.sin(a)])
    nvec = np.array([-dvec[1], dvec[0]])
    diag = math.hypot(W, H)
    c = np.array([W / 2, H / 2])
    offs = [(0, 0)]
    if tile:
        offs = [(ox, oy) for ox in (-W, 0, W) for oy in (-H, 0, H)]
    k = -diag / 2
    while k < diag / 2:
        t = -diag / 2
        while t < diag / 2:
            ln = dash * (0.5 + rnd.random())
            gap = dash * 0.25 * rnd.random()
            j1, j2 = rnd.normal(0, spacing * 0.12, 2)
            p0 = c + nvec * (k + j1) + dvec * t
            p1 = c + nvec * (k + j2) + dvec * (t + ln)
            t += ln + gap
            if tile and not (0 <= p0[0] < W and 0 <= p0[1] < H):
                continue
            ww = max(1, int(round(width * (0.7 + 0.6 * rnd.random()))))
            for ox, oy in offs:
                d.line([(p0[0] + ox, p0[1] + oy), (p1[0] + ox, p1[1] + oy)], fill=255, width=ww)
        k += spacing * (0.85 + 0.3 * rnd.random())
    return np.asarray(img, dtype=np.float32) / 255.0


def hatch_lines(cv, angle=45, spacing=4.0, width=1.0, seed=0, dash=14.0):
    ss = cv.ss
    return _hatch_cached(cv.W, cv.H, float(angle), float(spacing * ss), float(width * ss),
                         int(seed), bool(cv.tile), float(dash * ss))


# --------------------------------------------------------------------------
# canvas
# --------------------------------------------------------------------------
class Canvas:
    def __init__(self, w, h, ss=2, tile=False, name="canvas", bg=None):
        self.w, self.h, self.ss = int(w), int(h), int(ss)
        self.W, self.H = self.w * self.ss, self.h * self.ss
        self.tile = tile
        self.name = name
        self.rnd = rng(name)
        self.rgb = np.zeros((self.H, self.W, 3), np.float32)
        self.a = np.zeros((self.H, self.W), np.float32)
        if bg is not None:
            self.rgb[:] = col(bg)
            self.a[:] = 1.0
        self._wob = None
        self._hseed = seed_of(name) % 100000
        self.xf = None  # optional (scale, cx, cy) applied to mask geometry

    def T(self, x, y):
        """transformed point in canvas (supersampled) pixels"""
        if self.xf is not None:
            s_, cx, cy = self.xf
            x, y = cx + (x - cx) * s_, cy + (y - cy) * s_
        return x * self.ss, y * self.ss

    def TR(self, r):
        return r * self.ss * (self.xf[0] if self.xf is not None else 1.0)

    # -- helpers
    def S(self, v):
        return v * self.ss

    def mask(self):
        return Mask(self)

    def noise(self, cx, cy, octaves=3, seed=None):
        r = self.rnd if seed is None else rng(f"{self.name}:{seed}")
        return fbm(self.W, self.H, cx, cy, r, octaves)

    def wob(self):
        if self._wob is None:
            r = rng(self.name + ":wob")
            cx = max(2, self.W // (14 * self.ss))
            cy = max(2, self.H // (14 * self.ss))
            self._wob = fbm(self.W, self.H, cx, cy, r, 2)
        return self._wob

    # -- painting primitives
    def paint(self, m, fill, op=1.0):
        m = A(m)
        if np.isscalar(op) and op != 1.0:
            m = m * op
        elif not np.isscalar(op):
            m = m * op
        f = fill if isinstance(fill, np.ndarray) and fill.ndim == 3 else col(fill)
        mm = m[..., None]
        self.rgb = self.rgb * (1 - mm) + f * mm
        self.a = self.a + m * (1 - self.a)
        return self

    def tint(self, m, color, op=1.0):
        """paint colour without touching alpha (only where already opaque)."""
        m = A(m) * op
        mm = m[..., None]
        f = color if isinstance(color, np.ndarray) and color.ndim == 3 else col(color)
        self.rgb = self.rgb * (1 - mm) + f * mm
        return self

    def mul(self, m, amount, color=(40, 44, 60)):
        """darken (multiply toward ``color``) inside m by amount."""
        m = A(m) * amount
        c = col(color) / 255.0
        f = 1 - m[..., None] * (1 - c)
        self.rgb = self.rgb * f
        return self

    def screen(self, m, amount, color=(255, 240, 210)):
        m = A(m) * amount
        c = col(color)
        self.rgb = self.rgb + (c - self.rgb) * m[..., None]
        return self

    def glow(self, m, color, amount=1.0):
        """additive light (keeps alpha, adds it where none)."""
        m = A(m) * amount
        c = col(color)
        self.rgb = np.clip(self.rgb * (self.a[..., None]) + c * m[..., None], 0, 255)
        newa = np.clip(self.a + m * (1 - self.a), 0, 1)
        # un-premultiply against new alpha
        self.rgb = self.rgb / np.maximum(newa, 1e-4)[..., None]
        self.rgb = np.clip(self.rgb, 0, 255)
        self.a = newa
        return self

    def ink(self, m, width=3.0, color=INK, wobble=True, op=1.0):
        m = A(m)
        d = dilate(m, width * self.ss, self.tile, self.wob() if wobble else None)
        self.paint(d, color, op)
        return d

    def hatch(self, m, angle=45, spacing=3.5, width=0.8, op=0.55, color=INK, dash=12.0, seed=0):
        h = hatch_lines(self, angle, spacing, width, self._hseed + seed, dash)
        self.tint(A(m) * h, color, op)
        return self

    def crosshatch(self, m, op=0.5, spacing=3.5, width=0.8, color=INK, seed=0):
        m = A(m)
        self.hatch(m, 45, spacing, width, op, color, seed=seed)
        self.hatch(m * smoothstep(0.35, 0.8, m), -45, spacing * 1.1, width, op, color, seed=seed + 7)
        return self

    def stroke(self, pts, width=1.5, color=INK, op=1.0, smooth=False):
        m = self.mask()
        if smooth:
            m.curve(pts, width)
        else:
            m.line(pts, width)
        self.paint(m, color, op)
        return m

    def part(self, m, fill, ow=3.0, shade=0.45, light=0.22, hatch=0.45, hatch_angle=45,
             depth=4.0, soft=0.0, ink=True, ink_color=INK, hatch_spacing=3.2, seed=0,
             shade_color=(38, 40, 56)):
        """Draw an inked, shaded shape.  Returns the mask array."""
        m = A(m)
        if ink and ow > 0:
            self.ink(m, ow, ink_color)
        self.paint(m, fill)
        d = depth * self.ss
        if shade:
            band = edge_band(m, d, d, d * 0.6, self.tile)
            self.mul(band, shade, shade_color)
            if hatch:
                self.hatch(band, hatch_angle, hatch_spacing * 0.9, 0.8, min(1.0, hatch * 1.25), seed=seed)
                deep = smoothstep(0.45, 0.9, band)
                self.hatch(deep, hatch_angle - 90, hatch_spacing, 0.7, min(1.0, hatch), seed=seed + 3)
        if soft:
            inner = m * (1 - blur(erode(m, d * 0.6, self.tile), d * 0.8, self.tile))
            self.mul(inner, soft, shade_color)
        if light:
            lb = edge_band(m, -d * 0.7, -d * 0.7, d * 0.5, self.tile)
            self.screen(lb, light)
        return m

    def grain(self, amount=0.06, seed="grain", fine=True):
        r = rng(f"{self.name}:{seed}")
        n1 = pnoise(self.W, self.H, max(2, self.W // 3), max(2, self.H // 3), r)
        n2 = fbm(self.W, self.H, max(2, self.W // 40), max(2, self.H // 40), r, 3)
        g = (n1 - 0.5) * (1.0 if fine else 0.5) + (n2 - 0.5) * 0.8
        self.rgb = np.clip(self.rgb * (1 + g[..., None] * amount * 2), 0, 255)
        return self

    def vary(self, m, amount=0.12, cx=6, cy=6, seed="vary"):
        """blotchy tonal variation inside m (weathering)."""
        n = fbm(self.W, self.H, cx, cy, rng(f"{self.name}:{seed}"), 3)
        f = 1 + (n - 0.5) * 2 * amount * A(m)
        self.rgb = np.clip(self.rgb * f[..., None], 0, 255)
        return self

    # -- output
    def drop_shadow(self, dx=3.0, dy=4.0, sigma=2.5, op=0.55, color=(8, 7, 10)):
        sa = blur(shift(self.a, dx * self.ss, dy * self.ss, self.tile), sigma * self.ss, self.tile) * op
        c = col(color)
        na = self.a + sa * (1 - self.a)
        rgb = (self.rgb * self.a[..., None] + c * (sa * (1 - self.a))[..., None]) / np.maximum(na, 1e-4)[..., None]
        self.rgb, self.a = rgb, na
        return self

    def image(self):
        """Downsample (premultiplied) to final size and return RGBA Image."""
        a = np.clip(self.a, 0, 1)
        pm = np.clip(self.rgb, 0, 255) * a[..., None]
        if self.tile:
            p = 4 * self.ss
            pm = np.pad(pm, ((p, p), (p, p), (0, 0)), mode="wrap")
            a = np.pad(a, p, mode="wrap")
        chans = []
        tw, th = (pm.shape[1] // self.ss, pm.shape[0] // self.ss)
        for i in range(3):
            chans.append(np.asarray(Image.fromarray(pm[..., i].astype(np.float32), "F")
                                    .resize((tw, th), Image.LANCZOS)))
        aa = np.asarray(Image.fromarray(a.astype(np.float32), "F").resize((tw, th), Image.LANCZOS))
        rgb = np.stack(chans, -1)
        if self.tile:
            q = 4
            rgb = rgb[q:-q, q:-q]
            aa = aa[q:-q, q:-q]
        aa = np.clip(aa, 0, 1)
        rgb = rgb / np.maximum(aa, 1e-4)[..., None]
        rgb = np.clip(rgb, 0, 255)
        out = np.dstack([rgb, aa * 255]).round().astype(np.uint8)
        # clean fully transparent pixels
        out[out[..., 3] == 0, :3] = 0
        return Image.fromarray(out, "RGBA")


def save(img: Image.Image, rel: str, opaque=False):
    p = OUT / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    if opaque:
        img = img.convert("RGB")
    img.save(p, optimize=True)
    return p


# --------------------------------------------------------------------------
# textures (H x W x 3 float arrays)
# --------------------------------------------------------------------------
def wood_tex(W, H, rnd, base, dark, light=None, vertical=False, rings=None, streak=1.0):
    if vertical:
        return np.transpose(wood_tex(H, W, rnd, base, dark, light, False, rings, streak), (1, 0, 2))
    base, dark = col(base), col(dark)
    light = col(light) if light is not None else base * 1.18
    rings = rings or max(2, H // 22)
    dist = fbm(W, H, 2, 3, rnd, 3)
    fib = fbm(W, H, 2, max(8, H // 5), rnd, 3)
    fib2 = pnoise(W, H, 3, max(8, H // 2), rnd)
    y = np.arange(H, dtype=np.float32)[:, None] / H
    t = np.sin((y * rings + dist * 1.4 + fib * 0.12) * 2 * math.pi)
    lines = smoothstep(0.55, 0.98, t) * 0.8
    tone = (fib - 0.5) * 0.9 * streak + (fib2 - 0.5) * 0.35
    out = base[None, None, :] * (1 + tone[..., None] * 0.35)
    out = out + (dark - out) * lines[..., None] * 0.75
    hl = smoothstep(0.3, -0.6, t) * 0.18
    out = out + (light - out) * hl[..., None]
    return np.clip(out, 0, 255).astype(np.float32)


def noise_tex(W, H, rnd, color, amount=0.15, cx=8, cy=8, octaves=4):
    n = fbm(W, H, cx, cy, rnd, octaves)
    c = col(color)
    return np.clip(c[None, None, :] * (1 + (n[..., None] - 0.5) * 2 * amount), 0, 255).astype(np.float32)


def fabric_tex(W, H, rnd, color, amount=0.12, weave=3.0, ss=2):
    c = col(color)
    n = fbm(W, H, max(2, W // 60), max(2, H // 60), rnd, 3)
    x = np.arange(W)[None, :]
    y = np.arange(H)[:, None]
    p = weave * ss
    wv = (np.sin(x * 2 * math.pi / p) * np.sin(y * 2 * math.pi / p)) * 0.5
    f = 1 + (n - 0.5) * 2 * amount + wv * 0.05
    return np.clip(c[None, None, :] * f[..., None], 0, 255).astype(np.float32)


def gradient(W, H, c0, c1, angle=45):
    a = math.radians(angle)
    x = np.linspace(-1, 1, W)[None, :]
    y = np.linspace(-1, 1, H)[:, None]
    t = (x * math.cos(a) + y * math.sin(a)) * 0.5 + 0.5
    t = np.clip(t, 0, 1)
    c0, c1 = col(c0), col(c1)
    return (c0 + (c1 - c0) * t[..., None]).astype(np.float32)


def radial(W, H, cx, cy, r):
    x = np.arange(W)[None, :]
    y = np.arange(H)[:, None]
    return np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / max(r, 1e-6)
