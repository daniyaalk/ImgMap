"""Draws the app icon: the store icon, and Android launcher icons.

    python3 tool/make_icons.py
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"
NAVY, NAVY_LIGHT = (11, 37, 69), (24, 61, 110)
PAPER, GRID = (246, 243, 234), (176, 196, 220)
ROUTE, OWNSHIP, ROSE = (194, 24, 91), (255, 143, 0), (47, 93, 138)
SS = 4  # supersampling


def background(size):
    """A vertical navy gradient."""
    im = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(im)
    for y in range(size):
        t = y / (size - 1)
        d.line([(0, y), (size, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(NAVY_LIGHT, NAVY)))
    return im.convert("RGBA")


def motif(size, box):
    """The chart and position marker, drawn within the centred fraction
    [box] of a transparent [size] square."""
    n = size * SS
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    s = n * box
    o = (n - s) / 2
    angle = math.radians(-8)

    def p(x, y):
        # Unit coordinates within the box, rotated about its centre.
        x, y = x - 0.5, y - 0.5
        xr = x * math.cos(angle) - y * math.sin(angle)
        yr = x * math.sin(angle) + y * math.cos(angle)
        return (o + (xr + 0.5) * s, o + (yr + 0.5) * s)

    w = s / 100
    sheet = [p(0.12, 0.10), p(0.88, 0.10), p(0.88, 0.90), p(0.12, 0.90)]
    shadow = [(x + 2.5 * w, y + 3.5 * w) for x, y in sheet]
    d.polygon(shadow, fill=(0, 0, 0, 90))
    d.polygon(sheet, fill=PAPER)
    for t in (0.36, 0.64):
        d.line([p(t, 0.10), p(t, 0.90)], fill=GRID, width=round(1.2 * w))
        d.line([p(0.12, t), p(0.88, t)], fill=GRID, width=round(1.2 * w))

    # A VOR compass rose, as charts draw around a radio beacon.
    cx, cy = p(0.56, 0.42)
    R = 0.25 * s
    d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=ROSE, width=round(2.2 * w))
    for deg in range(0, 360, 30):
        a = math.radians(deg) + angle
        outer = R * (1.14 if deg % 90 == 0 else 1.08)
        d.line([(cx + R * math.sin(a), cy - R * math.cos(a)),
                (cx + outer * math.sin(a), cy - outer * math.cos(a))], fill=ROSE, width=round(1.3 * w))
    # Magnetic north, an arrowhead on the rose.
    north = [(0, 1.34), (0.07, 1.14), (-0.07, 1.14)]
    d.polygon([(cx + R * (r * math.sin(angle) + t * math.cos(angle)),
                cy - R * (r * math.cos(angle) - t * math.sin(angle))) for t, r in north], fill=ROSE)
    hexagon = [(cx + 4.5 * w * math.cos(math.radians(60 * i) + angle),
                cy + 4.5 * w * math.sin(math.radians(60 * i) + angle)) for i in range(6)]
    d.polygon(hexagon, outline=ROSE, width=round(2 * w))

    route = [p(0.18, 0.82), (cx, cy), p(0.88, 0.30)]
    d.line(route, fill=ROUTE, width=round(4.2 * w), joint="curve")
    d.polygon(hexagon, fill=PAPER, outline=ROSE, width=round(2 * w))

    # The ownship marker on the first leg, pointing along it.
    (x0, y0), (x1, y1) = route[0], route[1]
    cx, cy = x0 + (x1 - x0) * 0.36, y0 + (y1 - y0) * 0.36
    h = math.atan2(y1 - y0, x1 - x0)
    L = 17 * w

    def q(f, side):
        return (cx + L * (f * math.cos(h) - side * math.sin(h)),
                cy + L * (f * math.sin(h) + side * math.cos(h)))

    half = [(1.0, 0), (0.88, 0.13), (0.3, 0.14), (-0.05, 0.9), (-0.25, 0.9), (-0.22, 0.14),
            (-0.6, 0.12), (-0.78, 0.42), (-0.95, 0.42), (-0.92, 0)]
    plane = [q(f, side) for f, side in half] + [q(f, -side) for f, side in reversed(half[1:-1])]
    d.polygon(plane, fill=OWNSHIP, outline="white", width=round(1.4 * w))
    return im.resize((size, size), Image.LANCZOS)


def rounded(im, radius):
    mask = Image.new("L", (im.width * SS,) * 2, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, mask.width - 1, mask.height - 1], radius * SS, fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, mask=mask.resize(im.size, Image.LANCZOS))
    return out


def main():
    # Play Store: a full square; Play rounds the corners itself.
    store = background(512)
    store.alpha_composite(motif(512, 0.86))
    out = ROOT / "fastlane/metadata/android/en-US/images"
    out.mkdir(parents=True, exist_ok=True)
    store.convert("RGB").save(out / "icon.png")

    # Adaptive icon (Android 8+): the foreground's art stays within the
    # central 66dp safe zone of 108dp.
    for name, scale in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
        folder = RES / f"mipmap-{name}"
        folder.mkdir(exist_ok=True)
        motif(round(108 * scale), 0.54).save(folder / "ic_launcher_foreground.png")
        legacy = background(round(48 * scale))
        legacy.alpha_composite(motif(round(48 * scale), 0.86))
        rounded(legacy, 48 * scale * 0.18).save(folder / "ic_launcher.png")

    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        '</adaptive-icon>\n'
    )
    (RES / "values/ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#%02X%02X%02X</color>\n</resources>\n' % NAVY_LIGHT
    )


if __name__ == "__main__":
    main()
