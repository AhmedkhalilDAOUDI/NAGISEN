"""Renders the NAGISEN Instagram posts and stories from posts.json.

Photos go in photos/, finished files land in out/. Run: python3 render.py
Needs only Pillow and the macOS system fonts (SF Pro, New York).
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).parent
POST = (1080, 1350)   # 4:5 feed post
STORY = (1080, 1920)  # 9:16 story / reel cover

INK = (236, 230, 218)      # the app's cream text
BLACK = (9, 8, 9)
WINE = (139, 43, 73)       # Theme.accent 0x8B2B49

# Tritone maps for the grade: shadows, midtones, highlights.
TONES = {
    "wine": [(0.0, (6, 5, 6)), (0.38, (52, 14, 27)), (0.72, (128, 92, 96)), (1.0, (236, 228, 216))],
    "ash": [(0.0, (6, 6, 7)), (0.40, (38, 37, 40)), (0.75, (122, 118, 114)), (1.0, (234, 229, 220))],
}


def font(name, size, variation):
    path = {"sans": "/System/Library/Fonts/SFNS.ttf",
            "serif": "/System/Library/Fonts/NewYork.ttf",
            "serif-italic": "/System/Library/Fonts/NewYorkItalic.ttf"}[name]
    f = ImageFont.truetype(path, size)
    f.set_variation_by_name(variation)
    return f


def fill(image, size, focus):
    """Crops to the target ratio around focus (x, y in 0...1), then scales."""
    w, h = image.size
    tw, th = size
    scale = max(tw / w, th / h)
    cw, ch = tw / scale, th / scale
    fx, fy = focus
    left = min(max(fx * w - cw / 2, 0), w - cw)
    top = min(max(fy * h - ch / 2, 0), h - ch)
    return image.crop((round(left), round(top), round(left + cw), round(top + ch))).resize(size, Image.Resampling.LANCZOS)


def lut(stops, channel, crush):
    table = []
    for i in range(256):
        x = max(0.0, (i / 255 - crush) / (1 - crush)) ** 1.15
        for (a, ca), (b, cb) in zip(stops, stops[1:]):
            if x <= b:
                t = (x - a) / (b - a)
                table.append(round(ca[channel] + (cb[channel] - ca[channel]) * t))
                break
    return table


def grade(image, tone="wine", keep=0.22, crush=0.04):
    """Dark tritone grade with a little of the original colour kept, a vignette and film grain."""
    luma = image.convert("L")
    stops = TONES[tone]
    toned = Image.merge("RGB", [luma.point(lut(stops, c, crush)) for c in range(3)])
    out = Image.blend(toned, image, keep)
    vignette = Image.radial_gradient("L").resize(out.size, Image.Resampling.BICUBIC)
    vignette = vignette.point(lambda v: 255 - int(min(v * 1.25, 255) * 0.62))
    out = ImageChops.multiply(out, Image.merge("RGB", [vignette] * 3))
    return grain(out)


def grain(image, strength=26):
    noise = Image.effect_noise(image.size, strength).filter(ImageFilter.GaussianBlur(0.6))
    return ImageChops.soft_light(image, Image.merge("RGB", [noise] * 3))


def tracked(draw, xy, text, f, fill_color, tracking, anchor_center=True):
    """Draws letter-spaced text; xy is the centre of the line when anchor_center."""
    widths = [draw.textlength(ch, font=f) for ch in text]
    total = sum(widths) + tracking * (len(text) - 1)
    x, y = xy
    if anchor_center:
        x -= total / 2
    for ch, w in zip(text, widths):
        draw.text((x, y), ch, font=f, fill=fill_color, anchor="lm")
        x += w + tracking
    return total


def monogram(image, alpha=0.72):
    """The quiet signature on every post: a serif N with the burgundy dot, bottom centre."""
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w, h = image.size
    f = font("serif", 46, "Regular")
    y = h - (250 if h > POST[1] else 78)  # stories: clear of the reply bar
    d.text((w / 2, y), "N", font=f, fill=INK + (round(255 * alpha),), anchor="mm")
    d.ellipse((w / 2 + 20, y - 20, w / 2 + 29, y - 11), fill=WINE + (255,))
    return Image.alpha_composite(image.convert("RGBA"), layer).convert("RGB")


def caption_line(image, text, position):
    """A short uppercase statement over the photo, BRUTT-style but in NAGISEN's thin tracked sans."""
    d = ImageDraw.Draw(image)
    w, h = image.size
    f = font("sans", 30, "Medium")
    y = {"center": h / 2, "low": h * 0.78, "high": h * 0.2}[position]
    tracked(d, (w / 2, y), text.upper(), f, INK, 7)
    return image


def wordmark(size, sub=None):
    image = Image.new("RGB", size, BLACK)
    d = ImageDraw.Draw(image)
    w, h = size
    f = font("sans", 112, "Semibold")
    total = sum(d.textlength(c, font=f) for c in "NAGISEN") + 40 * 6
    tracked(d, (w / 2 + 22, h / 2), "NAGISEN", f, INK, 40)
    x = w / 2 + 22 - total / 2 - 58
    d.ellipse((x - 14, h / 2 - 14, x + 14, h / 2 + 14), fill=WINE)
    if sub:
        tracked(d, (w / 2, h / 2 + 120), sub.upper(), font("sans", 24, "Regular"), (138, 133, 126), 9)
    return grain(image, 20)


def statement(size, text, kicker=None):
    image = Image.new("RGB", size, BLACK)
    d = ImageDraw.Draw(image)
    w, h = size
    f = font("serif-italic", 64, "Regular Italic")
    lines = text.split("\n")
    lead = 84
    top = h / 2 - lead * (len(lines) - 1) / 2
    for i, line in enumerate(lines):
        d.text((w / 2, top + i * lead), line, font=f, fill=INK, anchor="mm")
    if kicker:
        tracked(d, (w / 2, top - 150), kicker.upper(), font("sans", 22, "Medium"), (220, 144, 162), 9)
    return monogram(grain(image, 20))


def render(entry, size):
    kind = entry["kind"]
    if kind == "photo":
        photo = Image.open(HERE / "photos" / entry["photo"]).convert("RGB")
        image = grade(fill(photo, size, entry.get("focus", (0.5, 0.5))), entry.get("tone", "wine"))
        if entry.get("line"):
            image = caption_line(image, entry["line"], entry.get("line_position", "center"))
        return monogram(image)
    if kind == "wordmark":
        return wordmark(size, entry.get("sub"))
    if kind == "statement":
        return statement(size, entry["text"], entry.get("kicker"))
    raise ValueError(f"unknown kind {kind}")


def main():
    plan = json.loads((HERE / "posts.json").read_text())
    out = HERE / "out"
    out.mkdir(exist_ok=True)
    only = set(sys.argv[1:])
    for entry in plan:
        if only and entry["id"] not in only:
            continue
        if entry["kind"] == "photo" and not (HERE / "photos" / entry["photo"]).exists():
            print(f"skip {entry['id']}: add photos/{entry['photo']}")
            continue
        for label, size in (("post", POST), ("story", STORY)):
            render(entry, size).save(out / f"{entry['id']}-{label}.jpg", quality=94)
        print(f"rendered {entry['id']}")


if __name__ == "__main__":
    main()
