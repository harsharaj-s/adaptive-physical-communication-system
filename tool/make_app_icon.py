"""Draw the app logo and export every launcher, splash, web and in-app size.

Requires: pip install pillow
Run from the project root:  python tool/make_app_icon.py

The mark is a QR finder "eye" (Light) between two pairs of signal arcs (Sound
and Vibration travelling out and back): blue on the send side, teal on the
receive side, matching the Send / Receive buttons on the home screen.
Everything is drawn from geometry at 4x and downsampled, so re-running the
script reproduces the same files.
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SS = 4  # supersampling factor
MASTER = 1024

BG_TOP = (27, 42, 74)
BG_BOTTOM = (10, 16, 32)
GLOW = (59, 130, 246)
SEND = (59, 130, 246)      # 0xFF3B82F6, the theme seed colour
RECEIVE = (45, 212, 191)   # teal, the Receive button
EYE = (248, 250, 252)
SPLASH_BG = "#0B1220"

# Mark geometry in units of 1/1000 of the canvas, centred at (500, 500).
EYE_OUTER, EYE_OUTER_R = 118, 40
EYE_HOLE, EYE_HOLE_R = 76, 20
EYE_DOT, EYE_DOT_R = 42, 14
ARC_RADII = (235, 335)
ARC_WIDTH = 44
ARC_SPAN = 38  # degrees either side of horizontal


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def vertical_gradient(size, top, bottom):
    col = Image.new("RGB", (1, size))
    for y in range(size):
        col.putpixel((0, y), lerp(top, bottom, y / (size - 1)))
    return col.resize((size, size))


def horizontal_gradient(size, left, right, x0, x1):
    row = Image.new("RGB", (size, 1))
    for x in range(size):
        t = min(1.0, max(0.0, (x - x0) / max(1, x1 - x0)))
        row.putpixel((x, 0), lerp(left, right, t))
    return row.resize((size, size))


def mark_masks(size, scale):
    """(arcs, eye) L-masks for a mark `scale` times the reference size."""
    u = size / 1000 * scale
    c = size / 2
    arcs = Image.new("L", (size, size), 0)
    eye = Image.new("L", (size, size), 0)
    da, de = ImageDraw.Draw(arcs), ImageDraw.Draw(eye)

    def rrect(draw, half, radius, fill):
        draw.rounded_rectangle((c - half * u, c - half * u, c + half * u, c + half * u),
                               radius=radius * u, fill=fill)

    rrect(de, EYE_OUTER, EYE_OUTER_R, 255)
    rrect(de, EYE_HOLE, EYE_HOLE_R, 0)
    rrect(de, EYE_DOT, EYE_DOT_R, 255)

    import math
    w = ARC_WIDTH * u
    for r in ARC_RADII:
        ru = r * u
        box = (c - ru - w / 2, c - ru - w / 2, c + ru + w / 2, c + ru + w / 2)
        for mid in (0, 180):
            da.arc(box, mid - ARC_SPAN, mid + ARC_SPAN, fill=255, width=round(w))
            for ang in (mid - ARC_SPAN, mid + ARC_SPAN):
                x = c + ru * math.cos(math.radians(ang))
                y = c + ru * math.sin(math.radians(ang))
                da.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=255)
    return arcs, eye


def render_mark(size, scale, mono=False):
    """Transparent RGBA mark, rendered at SS x and downsampled to `size`."""
    big = size * SS
    arcs, eye = mark_masks(big, scale)
    out = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    if mono:
        white = Image.new("RGBA", (big, big), (255, 255, 255, 255))
        both = Image.new("L", (big, big), 0)
        both.paste(255, mask=arcs)
        both.paste(255, mask=eye)
        out.paste(white, mask=both)
    else:
        span = (ARC_RADII[-1] + ARC_WIDTH / 2) * big / 1000 * scale
        grad = horizontal_gradient(big, SEND, RECEIVE, big / 2 - span, big / 2 + span)
        out.paste(grad.convert("RGBA"), mask=arcs)
        out.paste(Image.new("RGBA", (big, big), EYE + (255,)), mask=eye)
    return out.resize((size, size), Image.LANCZOS)


def render_background(size, shape):
    """Gradient tile with a soft glow. shape: 'square' | 'rounded' | 'circle'."""
    big = size * SS
    bg = vertical_gradient(big, BG_TOP, BG_BOTTOM).convert("RGBA")
    glow = Image.new("L", (big, big), 0)
    r = big * 0.30
    ImageDraw.Draw(glow).ellipse((big / 2 - r, big / 2 - r, big / 2 + r, big / 2 + r), fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(big * 0.12))
    bg.paste(Image.new("RGBA", (big, big), GLOW + (255,)), mask=glow)
    if shape != "square":
        mask = Image.new("L", (big, big), 0)
        d = ImageDraw.Draw(mask)
        if shape == "circle":
            d.ellipse((0, 0, big - 1, big - 1), fill=255)
        else:
            d.rounded_rectangle((0, 0, big - 1, big - 1), radius=big * 0.225, fill=255)
        bg.putalpha(mask)
    return bg.resize((size, size), Image.LANCZOS)


def render_icon(size, shape, scale):
    icon = render_background(size, shape)
    mark = render_mark(size, scale)
    halo = mark.filter(ImageFilter.GaussianBlur(size * 0.025))
    halo.putalpha(halo.getchannel("A").point(lambda a: a * 0.45))
    icon.alpha_composite(halo)
    icon.alpha_composite(mark)
    return icon


def save(img, rel, size=None, rgb=False):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    if size and img.width != size:
        img = img.resize((size, size), Image.LANCZOS)
    if rgb:
        img = img.convert("RGB")
    img.save(path, optimize=True)
    print(f"{rel}  {img.width}x{img.height}")


def main():
    square = render_icon(MASTER, "square", 0.80)
    rounded = render_icon(MASTER, "rounded", 0.80)
    circle = render_icon(MASTER, "circle", 0.74)
    maskable = render_icon(MASTER, "square", 0.62)
    foreground = render_mark(MASTER, 0.58)
    monochrome = render_mark(MASTER, 0.58, mono=True)
    mark = render_mark(MASTER, 1.0)

    # In-app assets (Flutter).
    save(rounded, "assets/branding/app_icon.png", 512)
    save(mark, "assets/branding/app_mark.png", 512)

    # Android: legacy, round, adaptive (API 26+) and themed monochrome (API 33+).
    dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    res = "android/app/src/main/res"
    for name, k in dens.items():
        save(rounded, f"{res}/mipmap-{name}/ic_launcher.png", round(48 * k))
        save(circle, f"{res}/mipmap-{name}/ic_launcher_round.png", round(48 * k))
        save(foreground, f"{res}/mipmap-{name}/ic_launcher_foreground.png", round(108 * k))
        save(monochrome, f"{res}/mipmap-{name}/ic_launcher_monochrome.png", round(108 * k))
        save(mark, f"{res}/drawable-{name}/launch_logo.png", round(160 * k))

    # iOS: every size listed in AppIcon.appiconset/Contents.json (no alpha allowed).
    iconset = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for entry in json.loads((iconset / "Contents.json").read_text())["images"]:
        pt = float(entry["size"].split("x")[0])
        px = round(pt * int(entry["scale"][0]))
        save(square, f"{iconset.relative_to(ROOT).as_posix()}/{entry['filename']}", px, rgb=True)
    launch = "ios/Runner/Assets.xcassets/LaunchImage.imageset"
    for suffix, k in (("", 1), ("@2x", 2), ("@3x", 3)):
        save(mark, f"{launch}/LaunchImage{suffix}.png", 160 * k)

    # Web: favicon, PWA icons and maskable icons (full bleed, 80% safe zone).
    save(rounded, "web/favicon.png", 64)
    save(rounded, "web/icons/Icon-192.png", 192)
    save(rounded, "web/icons/Icon-512.png", 512)
    save(maskable, "web/icons/Icon-maskable-192.png", 192, rgb=True)
    save(maskable, "web/icons/Icon-maskable-512.png", 512, rgb=True)

    print(f"splash background {SPLASH_BG}")


if __name__ == "__main__":
    main()
