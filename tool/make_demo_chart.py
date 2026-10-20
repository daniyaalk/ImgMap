"""Generates assets/demo_chart.png, a fictional chart for trying the app.

The chart is drawn in Web Mercator and rotated 8 degrees, like a scanned
plate that was not square on the scanner. Its fixes print their exact
coordinates so they can be used as control points; the app should recover
the rotation from them.

    python3 tool/make_demo_chart.py
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 2400, 1800
ROTATION_DEG = 8
LAT0, LAT1 = 28.40, 28.75
LON0, LON1 = 76.90, 77.30
FONT_DIR = Path("/usr/share/fonts/truetype/dejavu")

FIXES = [
    # name, lat, lon
    ("ALPHA", 28.6833, 76.9667),
    ("BRAVO", 28.7000, 77.2500),
    ("CHARL", 28.4500, 77.2333),
    ("DELTA", 28.4667, 76.9500),
    ("ECHOO", 28.6000, 77.1667),
]
ARP = ("VIDP ARP", 28.5665, 77.1031)


def merc(lat, lon):
    r = 6378137.0
    return (
        r * math.radians(lon),
        r * math.log(math.tan(math.pi / 4 + math.radians(lat) / 2)),
    )


cx, cy = merc((LAT0 + LAT1) / 2, (LON0 + LON1) / 2)
x0, _ = merc(LAT0, LON0)
x1, _ = merc(LAT0, LON1)
SCALE = 0.80 * W / (x1 - x0)
_t = math.radians(ROTATION_DEG)


def px(lat, lon):
    x, y = merc(lat, lon)
    dx, dy = (x - cx) * SCALE, -(y - cy) * SCALE
    return (
        W / 2 + dx * math.cos(_t) - dy * math.sin(_t),
        H / 2 + dx * math.sin(_t) + dy * math.cos(_t),
    )


def dm(value, pos, neg, width):
    hemi = pos if value >= 0 else neg
    value = abs(value)
    deg = int(value)
    minutes = (value - deg) * 60
    return f"{hemi}{deg:0{width}d}°{minutes:05.2f}'"


def main():
    img = Image.new("RGB", (W, H), (250, 248, 240))
    d = ImageDraw.Draw(img)
    small = ImageFont.truetype(str(FONT_DIR / "DejaVuSans.ttf"), 22)
    label = ImageFont.truetype(str(FONT_DIR / "DejaVuSans-Bold.ttf"), 30)
    title = ImageFont.truetype(str(FONT_DIR / "DejaVuSans-Bold.ttf"), 44)
    grid = (170, 190, 210)

    # Graticule every 3 minutes.
    lat = LAT0
    while lat <= LAT1 + 1e-9:
        pts = [px(lat, LON0 + (LON1 - LON0) * i / 50) for i in range(51)]
        d.line(pts, fill=grid, width=2)
        d.text(pts[0], dm(lat, "N", "S", 2), font=small, fill=(90, 110, 140),
               anchor="rs")
        lat += 0.05
    lon = LON0
    while lon <= LON1 + 1e-9:
        pts = [px(LAT0 + (LAT1 - LAT0) * i / 50, lon) for i in range(51)]
        d.line(pts, fill=grid, width=2)
        d.text(pts[-1], dm(lon, "E", "W", 3), font=small, fill=(90, 110, 140),
               anchor="ms")
        lon += 0.05

    # Fictional route joining the fixes.
    route = [px(la, lo) for _, la, lo in FIXES[:4]] + [px(*FIXES[0][1:])]
    d.line(route, fill=(40, 90, 160), width=4)

    # Runways at the ARP, roughly 10/28 and 11/29.
    ax, ay = px(ARP[1], ARP[2])
    for brg, off in [(100, -40), (110, 40)]:
        a = math.radians(brg - 90 + ROTATION_DEG)
        nx, ny = -math.sin(a) * off, math.cos(a) * off
        hx, hy = math.cos(a) * 110, math.sin(a) * 110
        d.line([(ax - hx + nx, ay - hy + ny), (ax + hx + nx, ay + hy + ny)],
               fill=(60, 60, 60), width=14)
    d.text((ax, ay + 90), ARP[0], font=label, fill=(30, 30, 30), anchor="mt")
    d.text((ax, ay + 126), f"{dm(ARP[1], 'N', 'S', 2)} {dm(ARP[2], 'E', 'W', 3)}",
           font=small, fill=(30, 30, 30), anchor="mt")

    for name, la, lo in FIXES:
        x, y = px(la, lo)
        r = 16
        d.polygon([(x, y - r), (x + r * 0.87, y + r / 2), (x - r * 0.87, y + r / 2)],
                  outline=(20, 20, 20), width=4)
        d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(20, 20, 20))
        d.text((x + 26, y - 30), name, font=label, fill=(20, 20, 20))
        d.text((x + 26, y + 6), f"{dm(la, 'N', 'S', 2)}", font=small,
               fill=(20, 20, 20))
        d.text((x + 26, y + 32), f"{dm(lo, 'E', 'W', 3)}", font=small,
               fill=(20, 20, 20))

    d.rectangle([40, 40, 1010, 190], fill=(255, 255, 255), outline=(20, 20, 20),
                width=3)
    d.text((64, 60), "IMGMAP DEMO CHART", font=title, fill=(20, 20, 20))
    d.text((64, 124), "Fictional — NOT FOR NAVIGATION. Tap a fix (centre of the",
           font=small, fill=(120, 20, 20))
    d.text((64, 152), "triangle) and enter the coordinates printed beside it.",
           font=small, fill=(120, 20, 20))

    out = Path(__file__).resolve().parent.parent / "assets" / "demo_chart.png"
    out.parent.mkdir(exist_ok=True)
    img.save(out, optimize=True)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
