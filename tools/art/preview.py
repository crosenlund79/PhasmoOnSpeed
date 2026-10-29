"""Contact sheets for eyeballing the generated art.

    python3 tools/art/preview.py <out_dir> [sheet ...]
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from core import OUT, FONTS

LABEL = ImageFont.truetype(str(FONTS / "IMFellDWPica-Regular.ttf"), 16)


def _label(d, xy, s, fill=(230, 220, 200)):
    d.text(xy, s, font=LABEL, fill=fill)


def floors(out):
    files = sorted((OUT / "floors").glob("*.png"))
    t = 384
    cols = 4
    rows = (len(files) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (t + 10) + 10, rows * (t + 34) + 10), (30, 30, 34))
    d = ImageDraw.Draw(sheet)
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGB")
        big = Image.new("RGB", (im.width * 2, im.height * 2))
        for x in (0, 1):
            for y in (0, 1):
                big.paste(im, (x * im.width, y * im.height))
        big = big.resize((t, t), Image.LANCZOS)
        x, y = 10 + (i % cols) * (t + 10), 10 + (i // cols) * (t + 34)
        sheet.paste(big, (x, y + 22))
        _label(d, (x, y), f.stem + " (2x2 tiled)")
    sheet.save(out / "floors.png")
    # one floor at native res to inspect detail
    for nm in ("wood_dark", "carpet_red", "stone", "tile_checker"):
        im = Image.open(OUT / "floors" / f"{nm}.png").convert("RGB")
        big = Image.new("RGB", (1024, 1024))
        for x in (0, 1):
            for y in (0, 1):
                big.paste(im, (x * 512, y * 512))
        big.crop((256, 256, 768, 768)).save(out / f"floor_seam_{nm}.png")


def furniture(out):
    files = sorted((OUT / "furniture").glob("*.png"))
    floor = Image.open(OUT / "floors" / "wood_dark.png").convert("RGBA")
    W = 1600
    x, y, rowh = 20, 20, 0
    place = []
    for f in files:
        im = Image.open(f)
        if x + im.width + 20 > W:
            x, y = 20, y + rowh + 30
            rowh = 0
        place.append((f, im, x, y + 20))
        x += im.width + 24
        rowh = max(rowh, im.height + 20)
    H = y + rowh + 40
    sheet = Image.new("RGBA", (W, H))
    for yy in range(0, H, 512):
        for xx in range(0, W, 512):
            sheet.paste(floor, (xx, yy))
    d = ImageDraw.Draw(sheet)
    for f, im, x, y in place:
        sheet.alpha_composite(im.convert("RGBA"), (x, y))
        d.text((x, y - 18), f.stem, font=LABEL, fill=(240, 230, 200))
    sheet.convert("RGB").save(out / "furniture.png")
    # also at game scale (0.5)
    sheet.convert("RGB").resize((W // 2, H // 2), Image.LANCZOS).save(out / "furniture_gamescale.png")


def tokens(out):
    files = sorted((OUT / "tokens").glob("*.png"))
    floor = Image.open(OUT / "floors" / "wood_light.png").convert("RGBA")
    cols = 6
    t = 128 + 30
    W = cols * t + 20
    H = ((len(files) + cols - 1) // cols) * (t + 20) + 20
    sheet = Image.new("RGBA", (W, H + 120))
    for yy in range(0, H + 120, 512):
        for xx in range(0, W, 512):
            sheet.paste(floor, (xx, yy))
    d = ImageDraw.Draw(sheet)
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGBA")
        x, y = 20 + (i % cols) * t, 20 + (i // cols) * (t + 20)
        sheet.alpha_composite(im, (x, y + 18))
        d.text((x, y), f.stem, font=LABEL, fill=(250, 240, 210))
    # game-scale row (64 px) rotated variants
    yy = H
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGBA").resize((64, 64), Image.LANCZOS)
        sheet.alpha_composite(im.rotate(-90 * (i % 4)), (20 + i * 70, yy + 10))
    sheet.convert("RGB").save(out / "tokens.png")


def icons(out):
    files = sorted((OUT / "icons").glob("*.png"))
    parch = Image.open(OUT / "ui" / "parchment.png").convert("RGBA")
    cols = 10
    t = 96 + 40
    W = cols * t + 20
    H = ((len(files) + cols - 1) // cols) * (t + 10) + 20
    sheet = Image.new("RGBA", (W, H + 90))
    for yy in range(0, H + 90, 512):
        for xx in range(0, W, 512):
            sheet.paste(parch, (xx, yy))
    # dark strip to check legibility on dark UI
    dark = Image.new("RGBA", (W, 90), (34, 32, 36, 255))
    sheet.alpha_composite(dark, (0, H))
    d = ImageDraw.Draw(sheet)
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGBA")
        x, y = 20 + (i % cols) * t, 10 + (i // cols) * (t + 10)
        sheet.alpha_composite(im.resize((96, 96), Image.LANCZOS), (x, y + 20))
        d.text((x, y), f.stem, font=ImageFont.truetype(str(FONTS / "IMFellDWPica-Regular.ttf"), 12),
               fill=(40, 30, 20))
    x = 10
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGBA")
        sz = 24 if i % 2 else 48
        if x + sz > W:
            break
        sheet.alpha_composite(im.resize((sz, sz), Image.LANCZOS), (x, H + 20))
        x += sz + 6
    sheet.convert("RGB").save(out / "icons.png")


def items(out):
    files = sorted((OUT / "items").glob("*.png"))
    floor = Image.open(OUT / "floors" / "wood_dark.png").convert("RGBA")
    stone = Image.open(OUT / "floors" / "tile_checker.png").convert("RGBA")
    cols = 10
    t = 128 + 20
    W = cols * t + 20
    H = ((len(files) + cols - 1) // cols) * (t + 20) + 20
    sheet = Image.new("RGBA", (W, H * 2))
    for yy in range(0, H, 512):
        for xx in range(0, W, 512):
            sheet.paste(floor, (xx, yy))
    for yy in range(H, 2 * H, 512):
        for xx in range(0, W, 512):
            sheet.paste(stone, (xx, yy))
    d = ImageDraw.Draw(sheet)
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGBA")
        x, y = 20 + (i % cols) * t, 10 + (i // cols) * (t + 20)
        sheet.alpha_composite(im.resize((128, 128), Image.LANCZOS), (x, y + 18))
        sheet.alpha_composite(im, (x + 30, y + 18 + H))
        d.text((x, y), f.stem, font=LABEL, fill=(250, 240, 210))
    sheet.convert("RGB").save(out / "items.png")


def ui(out):
    U = OUT / "ui"
    bg = Image.open(U / "menu_background.png").convert("RGBA")
    sheet = bg.copy()
    logo = Image.open(U / "title_logo.png").convert("RGBA")
    sheet.alpha_composite(logo, ((1920 - 1200) // 2, 80))
    # nine-slice test
    def nine(img, w, h, m):
        out_ = Image.new("RGBA", (w, h))
        W_, H_ = img.size
        xs = [(0, m, 0, m), (m, W_ - m, m, w - m), (W_ - m, W_, w - m, w)]
        ys = [(0, m, 0, m), (m, H_ - m, m, h - m), (H_ - m, H_, h - m, h)]
        for sx0, sx1, dx0, dx1 in xs:
            for sy0, sy1, dy0, dy1 in ys:
                piece = img.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.LANCZOS)
                out_.paste(piece, (dx0, dy0))
        return out_
    pf = nine(Image.open(U / "panel_frame.png").convert("RGBA"), 520, 360, 24)
    sheet.alpha_composite(pf, (120, 480))
    pd = nine(Image.open(U / "panel_dark.png").convert("RGBA"), 520, 360, 24)
    sheet.alpha_composite(pd, (700, 480))
    f = ImageFont.truetype(str(FONTS / "IMFellEnglishSC-Regular.ttf"), 30)
    for i, nm in enumerate(("button", "button_hover", "button_pressed")):
        b = nine(Image.open(U / f"{nm}.png").convert("RGBA"), 320, 64, 16)
        sheet.alpha_composite(b, (1300, 500 + i * 90))
        ImageDraw.Draw(sheet).text((1460, 532 + i * 90), ["Begin", "Hover", "Pressed"][i], font=f,
                                   fill=(235, 220, 190), anchor="mm")
    for i, nm in enumerate(("slot", "slot_selected", "slot", "slot")):
        sheet.alpha_composite(Image.open(U / f"{nm}.png").convert("RGBA"), (1300 + i * 72, 790))
    sheet.alpha_composite(Image.open(U / "vignette.png").convert("RGBA").resize((1920, 1080)), (0, 0))
    sheet.convert("RGB").save(out / "ui_menu.png")
    # banners on dark + raw pieces
    s2 = Image.new("RGBA", (1100, 900), (25, 24, 28, 255))
    s2.alpha_composite(Image.open(U / "banner_vanquished.png").convert("RGBA"), (50, 20))
    s2.alpha_composite(Image.open(U / "banner_perished.png").convert("RGBA"), (50, 250))
    x = 20
    for nm in ("panel_frame", "panel_dark", "button", "button_hover", "button_pressed", "slot", "slot_selected"):
        im = Image.open(U / f"{nm}.png").convert("RGBA")
        im2 = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
        s2.alpha_composite(im2, (x, 500))
        x += im2.width + 10
    L = OUT / "lights"
    x = 20
    for nm in ("soft", "cone", "candle"):
        im = Image.open(L / f"{nm}.png").convert("RGBA")
        im.thumbnail((400, 200))
        s2.alpha_composite(im, (x, 690))
        x += im.width + 20
    s2.convert("RGB").save(out / "ui_pieces.png")
    lg = Image.new("RGBA", (1200, 300), (60, 70, 90, 255))
    lg.alpha_composite(logo)
    lg.convert("RGB").save(out / "logo.png")


SHEETS = {"floors": floors, "furniture": furniture, "tokens": tokens, "icons": icons, "items": items, "ui": ui}

if __name__ == "__main__":
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    names = sys.argv[2:] or list(SHEETS)
    for n in names:
        try:
            SHEETS[n](out)
            print("sheet", n)
        except FileNotFoundError as e:
            print("skip", n, e)
