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


def room(out):
    """A mock room at game scale (32 px per cell), shown 2x."""
    cell = 64  # authoring density; we compose at 2x density then show as-is
    W, H = 18 * cell, 11 * cell
    sheet = Image.new("RGBA", (W, H))
    fl = Image.open(OUT / "floors" / "wood_dark.png").convert("RGBA")
    cp = Image.open(OUT / "floors" / "carpet_red.png").convert("RGBA")
    tl = Image.open(OUT / "floors" / "tile_checker.png").convert("RGBA")
    for yy in range(0, H, 512):
        for xx in range(0, W, 512):
            sheet.paste(fl, (xx, yy))
    # carpeted study on the left, kitchen tiles on the right
    for yy in range(cell, 9 * cell, 512):
        for xx in range(cell, 9 * cell, 512):
            sheet.paste(cp.crop((0, 0, min(512, 9 * cell - xx), min(512, 9 * cell - yy))), (xx, yy))
    for yy in range(cell, 10 * cell, 512):
        sheet.paste(tl.crop((0, 0, 7 * cell, min(512, 10 * cell - yy))), (11 * cell, yy))
    wall = Image.open(OUT / "walls" / "wall_top.png").convert("RGBA").resize((cell, cell))
    for x in range(18):
        sheet.paste(wall, (x * cell, 0))
        sheet.paste(wall, (x * cell, 10 * cell))
    for y in range(11):
        sheet.paste(wall, (0, y * cell))
        sheet.paste(wall, (17 * cell, y * cell))
        if y not in (4, 5):
            sheet.paste(wall, (10 * cell, y * cell))
    def put(name, cx, cy, rot=0):
        im = Image.open(OUT / "furniture" / f"{name}.png").convert("RGBA")
        if rot:
            im = im.rotate(rot, expand=True)
        sheet.alpha_composite(im, (cx * cell, cy * cell))
    put("rug_round", 3, 3)
    put("bookshelf", 1, 1)
    put("fireplace", 5, 1)
    put("armchair", 3, 4)
    put("desk", 6, 6)
    put("chair", 7, 5)
    put("grandfather_clock", 9, 1)
    put("potted_plant", 1, 8)
    put("candelabra", 9, 8)
    put("stove", 11, 1)
    put("counter", 13, 1)
    put("sink_kitchen", 15, 1)
    put("icebox", 16, 3)
    put("dining_table", 11, 5)
    put("barrel", 16, 8)
    for name, x, y, r in (("investigator", 4.5, 8.4, 0), ("occupant_a", 8.2, 3.0, 180), ("vampire", 13.5, 3.3, 90),
                          ("cat", 2.0, 6.0, -90), ("shade", 6.0, 3.4, 45)):
        im = Image.open(OUT / "tokens" / f"{name}.png").convert("RGBA")
        im = im.rotate(r, resample=Image.BICUBIC)
        sheet.alpha_composite(im, (int(x * cell - 64), int(y * cell - 64)))
    for name, x, y in (("salt_pile", 9.5, 6.5), ("ghost_book_written", 2.5, 1.6), ("claw_marks", 12.3, 8.6),
                       ("sigil_candle_lit", 7.6, 8.6)):
        im = Image.open(OUT / "items" / f"{name}.png").convert("RGBA")
        sheet.alpha_composite(im, (int(x * cell - 32), int(y * cell - 32)))
    # darkness + lights
    dark = Image.new("RGBA", (W, H), (6, 8, 14, 150))
    sheet.alpha_composite(dark)
    sheet.convert("RGB").save(out / "room_authoring_res.png")
    sheet.convert("RGB").resize((W // 2, H // 2), Image.LANCZOS).save(out / "room_gamescale.png")


# --------------------------------------------------------------------------
# revision 2 sheets
# --------------------------------------------------------------------------
REV2_FURN = ["boiler", "wine_rack", "coal_pile", "storage_shelf", "covered_armchair", "covered_sofa", "broken_chair",
             "old_trunk", "water_tank", "pipes", "boards", "debris", "desk_large", "stairs_down", "stairs_up", "hatch",
             "armchair", "sofa", "trunk", "crates", "barrel", "stove"]


def _tile_bg(W, H, path):
    fl = Image.open(path).convert("RGBA")
    bg = Image.new("RGBA", (W, H))
    for yy in range(0, H, fl.height):
        for xx in range(0, W, fl.width):
            bg.paste(fl, (xx, yy))
    return bg


def furniture2(out):
    """new basement furniture on a stone floor (authoring res + game scale); old pieces at the end for reference"""
    W = 1600
    x, y, rowh = 20, 20, 0
    place = []
    for nm in REV2_FURN:
        im = Image.open(OUT / "furniture" / f"{nm}.png")
        if x + im.width + 20 > W:
            x, y = 20, y + rowh + 30
            rowh = 0
        place.append((nm, im, x, y + 20))
        x += im.width + 24
        rowh = max(rowh, im.height + 20)
    H = y + rowh + 40
    sheet = _tile_bg(W, H, OUT / "floors" / "stone.png")
    d = ImageDraw.Draw(sheet)
    for nm, im, x, y in place:
        sheet.alpha_composite(im.convert("RGBA"), (x, y))
        d.text((x, y - 18), nm, font=LABEL, fill=(240, 230, 200))
    sheet.convert("RGB").save(out / "furniture2.png")
    sheet.convert("RGB").resize((W // 2, H // 2), Image.LANCZOS).save(out / "furniture2_gamescale.png")
    # a mock cellar at game scale (32 px / cell), shown at 2x for inspection
    cell = 64
    cw, ch = 14, 9
    room = _tile_bg(cw * cell, ch * cell, OUT / "floors" / "stone.png")
    for nm, ov in (("grime", 0.5), ("damp", 0.45), ("cracks", 0.5)):
        o = Image.open(OUT / "decor" / f"{nm}.png").convert("RGBA")
        a = o.getchannel("A").point(lambda v, k=ov: int(v * k))
        o.putalpha(a)
        room.alpha_composite(_tile_rgba(o, cw * cell, ch * cell))
    wall = Image.open(OUT / "walls" / "wall_top.png").convert("RGBA").resize((cell, cell))
    for xx in range(cw):
        room.paste(wall, (xx * cell, 0))
    for yy in range(ch):
        room.paste(wall, (0, yy * cell))
        room.paste(wall, ((cw - 1) * cell, yy * cell))

    def put(dirn, nm, cx, cy, rot=0):
        im = Image.open(OUT / dirn / f"{nm}.png").convert("RGBA")
        if rot:
            im = im.rotate(rot, expand=True)
        room.alpha_composite(im, (int(cx * cell), int(cy * cell)))
    put("furniture", "pipes", 1, 1)
    put("furniture", "pipes", 5, 1)
    put("decor", "peel", 9, 1)
    put("furniture", "boiler", 1, 2)
    put("furniture", "water_tank", 5, 2)
    put("furniture", "coal_pile", 1, 5)
    put("furniture", "wine_rack", 9, 2)
    put("furniture", "storage_shelf", 10, 7, 90)
    put("furniture", "covered_armchair", 7, 5)
    put("furniture", "old_trunk", 4, 7)
    put("furniture", "broken_chair", 6, 7)
    put("furniture", "debris", 10, 3)
    put("furniture", "boards", 4, 5)
    put("furniture", "stairs_up", 12, 1)
    put("furniture", "stairs_down", 12, 2)
    put("furniture", "hatch", 3, 4)
    put("decor", "cobweb", 1, 1)
    cw_ = Image.open(OUT / "decor" / "cobweb.png").convert("RGBA").transpose(Image.FLIP_LEFT_RIGHT)
    room.alpha_composite(cw_, ((cw - 2) * cell, 1 * cell))
    put("decor", "stain_1", 7.5, 7)
    put("decor", "rat", 9, 6)
    put("decor", "rubble", 9.5, 3.5)
    put("decor", "papers_scattered", 6, 4)
    put("decor", "dust_sheet_scrap", 11, 6)
    tok = Image.open(OUT / "tokens" / "investigator.png").convert("RGBA")
    room.alpha_composite(tok, (int(7.5 * cell - 64), int(3.5 * cell - 64)))
    room.alpha_composite(Image.new("RGBA", room.size, (6, 8, 14, 110)))
    room.convert("RGB").save(out / "cellar_authoring_res.png")
    room.convert("RGB").resize((cw * 32, ch * 32), Image.LANCZOS).save(out / "cellar_gamescale.png")
    # stairs/hatch at true game size (32 px) and 2x nearest
    st = _tile_bg(32 * 9, 32 * 3, OUT / "floors" / "wood_dark.png").resize((32 * 9, 32 * 3))
    for i, nm in enumerate(("stairs_down", "stairs_up", "hatch")):
        im = Image.open(OUT / "furniture" / f"{nm}.png").convert("RGBA").resize((32, 32), Image.LANCZOS)
        st.alpha_composite(im, (32 + i * 96, 32))
    st.resize((st.width * 3, st.height * 3), Image.NEAREST).convert("RGB").save(out / "stairs_32px_x3.png")


def _tile_rgba(o, W, H):
    bg = Image.new("RGBA", (W, H))
    for yy in range(0, H, o.height):
        for xx in range(0, W, o.width):
            bg.paste(o, (xx, yy))
    return bg


def overlays(out):
    """each neglect overlay tiled 2x2 over wood_dark at 40% opacity (plus 100% for inspection)"""
    names = ("grime", "damp", "cracks")
    T = 1024
    sheet = Image.new("RGBA", (len(names) * (T // 2 + 10) + 10, 2 * (T // 2 + 34) + 10), (30, 30, 34, 255))
    d = ImageDraw.Draw(sheet)
    for i, nm in enumerate(names):
        for j, op in enumerate((0.4, 1.0)):
            bg = _tile_bg(T, T, OUT / "floors" / "wood_dark.png")
            o = Image.open(OUT / "decor" / f"{nm}.png").convert("RGBA")
            o.putalpha(o.getchannel("A").point(lambda v, k=op: int(v * k)))
            bg.alpha_composite(_tile_rgba(o, T, T))
            x, y = 10 + i * (T // 2 + 10), 10 + j * (T // 2 + 34)
            sheet.paste(bg.resize((T // 2, T // 2), Image.LANCZOS), (x, y + 22))
            _label(d, (x, y), f"{nm} 2x2 @ {int(op * 100)}%")
    sheet.convert("RGB").save(out / "overlays.png")
    # seam check crop at native res (centre of a 2x2 tiling = the seam cross)
    for nm in names:
        bg = _tile_bg(1024, 1024, OUT / "floors" / "wood_light.png")
        bg.alpha_composite(_tile_rgba(Image.open(OUT / "decor" / f"{nm}.png").convert("RGBA"), 1024, 1024))
        bg.crop((256, 256, 768, 768)).convert("RGB").save(out / f"overlay_seam_{nm}.png")
    # small decals on stone and wood
    small = ["cobweb", "stain_1", "stain_2", "stain_3", "peel", "dust_sheet_scrap", "rubble", "papers_scattered", "rat"]
    W = 1400
    s2 = _tile_bg(W, 600, OUT / "floors" / "stone.png")
    wd = _tile_bg(W, 300, OUT / "floors" / "wood_light.png")
    s2.paste(wd, (0, 300))
    d = ImageDraw.Draw(s2)
    x = 20
    for nm in small:
        im = Image.open(OUT / "decor" / f"{nm}.png").convert("RGBA")
        k = 2 if im.width <= 64 else 1
        big = im.resize((im.width * k, im.height * k), Image.LANCZOS)
        s2.alpha_composite(big, (x, 40))
        s2.alpha_composite(im, (x, 340))
        d.text((x, 14), nm, font=LABEL, fill=(240, 230, 200))
        x += big.width + 24
    s2.convert("RGB").save(out / "decor_small.png")


def menu(out):
    """menu props on a desk-coloured background (+ the large desk)"""
    M = OUT / "menu"
    W, H = 1500, 1000
    sheet = Image.new("RGBA", (W, H), (58, 34, 24, 255))
    import numpy as _np
    n = _np.random.default_rng(3).normal(0, 6, (H, W, 1))
    arr = _np.asarray(sheet).astype(_np.float32)
    arr[..., :3] += n
    sheet = Image.fromarray(_np.clip(arr, 0, 255).astype(_np.uint8), "RGBA")
    d = ImageDraw.Draw(sheet)
    lay = [("case_photo_1", 20, 30), ("case_photo_2", 170, 30), ("case_photo_3", 320, 30), ("case_file", 480, 30),
           ("journal_open", 700, 30), ("map_pinned", 1060, 30), ("pocket_watch", 20, 260), ("magnifier", 140, 260),
           ("inkwell", 260, 260)]
    for nm, x, y in lay:
        im = Image.open(M / f"{nm}.png").convert("RGBA")
        sheet.alpha_composite(im, (x, y + 20))
        d.text((x, y), nm, font=LABEL, fill=(240, 230, 200))
    desk = Image.open(OUT / "furniture" / "desk_large.png").convert("RGBA")
    sheet.alpha_composite(desk, (480, 330))
    d.text((480, 310), "desk_large", font=LABEL, fill=(240, 230, 200))
    # an arranged desk at 2x
    big = desk.resize((desk.width * 2, desk.height * 2), Image.LANCZOS)
    s3 = Image.new("RGBA", (big.width + 80, big.height + 80), (24, 18, 16, 255))
    s3.alpha_composite(big, (40, 40))
    for nm, x, y, r in (("case_file", 300, 120, -6), ("journal_open", 380, 260, 3), ("case_photo_1", 240, 300, 12),
                        ("case_photo_3", 620, 90, -9), ("map_pinned", 540, 110, 4), ("pocket_watch", 230, 470, 0),
                        ("magnifier", 640, 380, 30)):
        im = Image.open(M / f"{nm}.png").convert("RGBA").rotate(r, expand=True, resample=Image.BICUBIC)
        s3.alpha_composite(im, (x, y))
    s3.convert("RGB").save(out / "menu_desk_arranged.png")
    sheet.convert("RGB").save(out / "menu_props.png")


def plaques(out):
    M = OUT / "menu"
    names = ("plaque", "plaque_hover", "plaque_pressed", "plaque_dev")

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
    f = ImageFont.truetype(str(FONTS / "IMFellEnglishSC-Regular.ttf"), 30)
    sheet = Image.new("RGBA", (1180, 460), (58, 34, 24, 255))
    d = ImageDraw.Draw(sheet)
    for i, nm in enumerate(names):
        im = Image.open(M / f"{nm}.png").convert("RGBA")
        y = 20 + i * 108
        sheet.alpha_composite(im, (20, y + 20))
        b = nine(im, 340, 64, 24)
        sheet.alpha_composite(b, (380, y + 20))
        txt = (40, 26, 14) if nm != "plaque_dev" else (24, 34, 46)
        d.text((550, y + 52 + (2 if nm == "plaque_pressed" else 0)), ["Begin Investigation", "Begin Investigation",
               "Begin Investigation", "Dev: Skip Night"][i], font=f, fill=txt, anchor="mm")
        b2 = nine(im, 420, 96, 24)
        sheet.alpha_composite(b2, (740, y))
        _label(d, (20, y), nm)
    sheet.convert("RGB").save(out / "plaques.png")


SHEETS = {"floors": floors, "furniture": furniture, "tokens": tokens, "icons": icons, "items": items, "ui": ui, "room": room,
          "furniture2": furniture2, "overlays": overlays, "menu": menu, "plaques": plaques}

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
