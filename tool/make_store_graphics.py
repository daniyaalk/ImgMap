"""Draws the Play Store feature graphic, and frames raw phone screenshots
(tool/screenshots/raw/NN-name.png) with a caption for the listing.

    python3 tool/make_store_graphics.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from make_icons import NAVY, NAVY_LIGHT, OWNSHIP, motif

ROOT = Path(__file__).resolve().parent.parent
IMAGES = ROOT / "fastlane/metadata/android/en-US/images"
RAW = ROOT / "tool/screenshots/raw"
FONTS = Path("/usr/share/fonts/truetype/noto")

# Captions for the screenshots, by file name.
CAPTIONS = {
    "01-chart": ("See where you are", "Your position, live on published charts"),
    "02-list": ("The right chart, fast", "Charts covering your position come first"),
    "03-aip": ("Straight from the AIP", "Every chart an airport publishes"),
    "04-enroute": ("The en-route network", "Airways and fixes, with search"),
    "05-airports": ("All your airports", "Charts stay on your phone, offline"),
}


def font(weight, size):
    return ImageFont.truetype(str(FONTS / f"NotoSans-{weight}.ttf"), size)


def gradient(w, h):
    im = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(NAVY_LIGHT, NAVY)))
    return im.convert("RGBA")


def feature_graphic():
    im = gradient(1024, 500)
    art = motif(460, 0.9)
    im.alpha_composite(art, (540, 20))
    d = ImageDraw.Draw(im)
    d.text((64, 150), "AIPChart", font=font("Bold", 88), fill="white")
    d.text((68, 262), "Your position on aviation charts", font=font("Regular", 34), fill=(214, 226, 240))
    d.text((68, 330), "For enthusiasts. Not for navigation.", font=font("Regular", 24), fill=OWNSHIP)
    im.convert("RGB").save(IMAGES / "featureGraphic.png")


def framed(shot, title, subtitle, size):
    """[shot] on the navy background under a caption, as a [size] image."""
    w, h = size
    im = gradient(w, h)
    d = ImageDraw.Draw(im)
    portrait = h > w
    top = round(h * (0.06 if portrait else 0.07))
    big, small = (font("Bold", 76), font("Regular", 42)) if portrait else (font("Bold", 64), font("Regular", 36))
    for text, f, fill, y in ((title, big, "white", top), (subtitle, small, (214, 226, 240), top + big.size + 20)):
        tw = d.textlength(text, font=f)
        d.text(((w - tw) / 2, y), text, font=f, fill=fill)

    # The screenshot, scaled to the space left, with rounded corners and a shadow.
    area_top = top + big.size + small.size + 80
    max_w, max_h = w * (0.82 if portrait else 0.86), h - area_top - h * 0.04
    scale = min(max_w / shot.width, max_h / shot.height)
    sw, sh = round(shot.width * scale), round(shot.height * scale)
    shot = shot.convert("RGBA").resize((sw, sh), Image.LANCZOS)
    radius = round(min(sw, sh) * 0.05)
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], radius, fill=255)
    x, y = (w - sw) // 2, area_top
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x, y + 16, x + sw, y + sh + 16], radius, fill=(0, 0, 0, 120))
    im.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(24)))
    im.paste(shot, (x, y), mask)
    return im.convert("RGB")


def screenshots():
    out = IMAGES / "phoneScreenshots"
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.png"):
        old.unlink()
    for raw in sorted(RAW.glob("*.png")):
        title, subtitle = CAPTIONS[raw.stem]
        shot = Image.open(raw)
        size = (1080, 1920) if shot.height > shot.width else (1920, 1080)
        framed(shot, title, subtitle, size).save(out / raw.name)


if __name__ == "__main__":
    feature_graphic()
    screenshots()
