"""SPECTRAL RUN game icon: a pale spectre with hollow eyes and trailing wisps inside
a gold ring on near-black — readable down to 16 px. Writes icon.png (project icon)
and icon.ico (multi-size, embedded into the Windows .exe by tools/installer)."""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
S = 1024


def draw(size=S):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    k = size / 1024
    c = size / 2
    # dark disc with a violet bloom at its heart
    d.ellipse([24 * k, 24 * k, size - 24 * k, size - 24 * k], fill=(16, 12, 20, 255))
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([c - 330 * k, c - 330 * k, c + 330 * k, c + 330 * k], fill=(120, 80, 170, 150))
    im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(120 * k)))
    d = ImageDraw.Draw(im)
    # gold ring with a thin inner line
    d.ellipse([40 * k, 40 * k, size - 40 * k, size - 40 * k], outline=(201, 160, 84, 255), width=int(44 * k))
    d.ellipse([104 * k, 104 * k, size - 104 * k, size - 104 * k], outline=(120, 92, 46, 255), width=int(10 * k))
    # the spectre: rounded head, flowing body, a tattered hem streaming left (it runs)
    body = []
    for i in range(0, 181, 6):
        a = math.radians(180 + i)
        body.append((c + 40 * k + math.cos(a) * 230 * k, c - 90 * k + math.sin(a) * 230 * k))
    hem = [(c + 270 * k, c + 140 * k), (c + 180 * k, c + 300 * k), (c + 110 * k, c + 210 * k),
           (c + 20 * k, c + 330 * k), (c - 60 * k, c + 220 * k), (c - 170 * k, c + 300 * k),
           (c - 300 * k, c + 200 * k), (c - 200 * k, c + 120 * k)]
    shape = body + hem
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(x + 18 * k, y + 22 * k) for x, y in shape], fill=(0, 0, 0, 170))
    im.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(16 * k)))
    d = ImageDraw.Draw(im)
    d.polygon(shape, fill=(236, 232, 246, 255))
    d.line(shape + [shape[0]], fill=(22, 18, 28, 255), width=int(16 * k), joint="curve")
    # wisps streaming behind
    for j, (y0, ln) in enumerate([(-40, 120), (60, 150), (160, 110)]):
        d.line([(c - 230 * k, c + y0 * k), (c - 230 * k - ln * k, c + (y0 + 14) * k)], fill=(200, 190, 230, 200 - j * 40), width=int((26 - j * 6) * k))
    # tall hollow eyes, slanting inward, and a long gaping mouth
    for ex, tilt in ((-30, 1), (110, -1)):
        d.polygon([(c + (ex - 40) * k, c - (150 + 20 * tilt) * k), (c + (ex + 40) * k, c - (150 - 20 * tilt) * k),
                   (c + (ex + 30) * k, c - 10 * k), (c + (ex - 30) * k, c - 10 * k)], fill=(18, 12, 24, 255))
    d.ellipse([c + 15 * k, c + 25 * k, c + 75 * k, c + 175 * k], fill=(18, 12, 24, 255))
    return im


def main():
    im = draw()
    im.save(os.path.join(ROOT, "icon.png"))
    sizes = [16, 24, 32, 48, 64, 128, 256]
    im.save(os.path.join(ROOT, "icon.ico"), sizes=[(s, s) for s in sizes])
    print("icon.png + icon.ico written")


if __name__ == "__main__":
    main()
