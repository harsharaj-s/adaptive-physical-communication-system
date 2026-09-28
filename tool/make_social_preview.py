"""Draw the GitHub social preview card (1280 x 640) shown when the repository link is shared.

Requires: pip install pillow   (Windows: uses the Segoe UI fonts)
Run from the project root:  python tool/make_social_preview.py

Upload the result by hand: Settings -> General -> Social preview (GitHub has no API for it).
Text and logo stay at least 80 px inside every edge, because LinkedIn, X and Slack crop
the borders slightly differently. The logo comes from make_app_icon.render_icon, so it
always matches the app icon.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from make_app_icon import BG_BOTTOM, BG_TOP, GLOW, RECEIVE, SEND, lerp, render_icon

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs/images/social-preview.png"
W, H = 1280, 640
SS = 2  # supersampling factor
MARGIN = 88
FONTS = Path("C:/Windows/Fonts")

TITLE = ["Adaptive Physical", "Communication System"]
TAGLINE = "Offline phone-to-phone file transfer using light and sound"
CHIPS = [("Animated QR codes", SEND), ("Data-over-sound modem", RECEIVE), ("No Internet, Wi-Fi or Bluetooth", None)]
FOOTER = "Flutter  ·  Android  ·  iOS  ·  Web  ·  MIT License"
REPO = "github.com/harsharaj-s"
TEXT = (248, 250, 252)
MUTED = (148, 163, 184)


def font(name, size):
    return ImageFont.truetype(str(FONTS / name), size * SS)


def background():
    w, h = W * SS, H * SS
    col = Image.new("RGB", (1, h))
    for y in range(h):
        col.putpixel((0, y), lerp(BG_TOP, BG_BOTTOM, y / (h - 1)))
    bg = col.resize((w, h)).convert("RGBA")
    glow = Image.new("L", (w, h), 0)
    cx, cy, r = 250 * SS, 300 * SS, 230 * SS
    ImageDraw.Draw(glow).ellipse((cx - r, cy - r, cx + r, cy + r), fill=60)
    glow = glow.filter(ImageFilter.GaussianBlur(120 * SS))
    bg.paste(Image.new("RGBA", (w, h), GLOW + (255,)), mask=glow)
    return bg


def chip(draw, x, y, text, accent, f):
    pad_x, pad_y = 18 * SS, 9 * SS
    tw = draw.textlength(text, font=f)
    asc, desc = f.getmetrics()
    box = (x, y, x + tw + 2 * pad_x + (22 * SS if accent else 0), y + asc + desc + 2 * pad_y)
    draw.rounded_rectangle(box, radius=(box[3] - box[1]) // 2, fill=(30, 41, 59), outline=(51, 65, 85), width=2 * SS)
    tx = x + pad_x
    if accent:
        cy = (box[1] + box[3]) // 2
        draw.ellipse((tx, cy - 6 * SS, tx + 12 * SS, cy + 6 * SS), fill=accent)
        tx += 22 * SS
    draw.text((tx, y + pad_y), text, font=f, fill=TEXT)
    return box[2]


def main():
    img = background()
    logo = render_icon(260 * SS, "rounded", 0.80)
    img.alpha_composite(logo, (MARGIN * SS, (H * SS - logo.height) // 2 - 40 * SS))

    draw = ImageDraw.Draw(img)
    x = (MARGIN + 260 + 56) * SS
    y = 150 * SS
    title_f = font("segoeuib.ttf", 58)
    for line in TITLE:
        draw.text((x, y), line, font=title_f, fill=TEXT)
        y += 70 * SS
    y += 14 * SS
    draw.text((x, y), TAGLINE, font=font("segoeui.ttf", 27), fill=MUTED)
    y += 64 * SS

    chip_f = font("seguisb.ttf", 21)
    cx = x
    for i, (text, accent) in enumerate(CHIPS):
        if i == 2:
            cx, y = x, y + 58 * SS
        cx = chip(draw, cx, y, text, accent, chip_f) + 14 * SS

    draw.line((MARGIN * SS, (H - 104) * SS, (W - MARGIN) * SS, (H - 104) * SS), fill=(51, 65, 85), width=2 * SS)
    small = font("segoeui.ttf", 22)
    draw.text((MARGIN * SS, (H - 86) * SS), FOOTER, font=small, fill=MUTED)
    repo_w = draw.textlength(REPO, font=small)
    draw.text(((W - MARGIN) * SS - repo_w, (H - 86) * SS), REPO, font=small, fill=MUTED)

    out = img.resize((W, H), Image.LANCZOS).convert("RGB")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    out.save(OUT, optimize=True)
    print(f"{OUT.relative_to(ROOT).as_posix()}  {out.width}x{out.height}  {OUT.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
