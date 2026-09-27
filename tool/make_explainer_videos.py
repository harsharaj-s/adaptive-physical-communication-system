"""Build the narrated explainer videos bundled under assets/samples/videos/.

Requires: pip install pillow imageio-ffmpeg, plus Windows (System.Speech voices).
Run from the project root:  python tool/make_explainer_videos.py [stem ...]
(no stems = every topic; also run by make_sample_media.py).

Each Topic is data: scenes that pair one narration line with a named painter.
Narration is spoken offline by Windows TTS, every scene lasts as long as its
line, frames are drawn with Pillow (2x supersampled) and
make_sample_media.encode() squeezes the result under the file-name budget.
"""
import array
import json
import math
import random
import subprocess
import sys
import tempfile
import wave
from contextlib import contextmanager
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from make_sample_media import encode

FPS = 12
SS = 2  # supersampling factor for smooth shapes
RATE = 16000  # narration sample rate
MORSE_UNIT = 0.08  # seconds, about 15 words per minute
FONT_DIR = Path(r"C:\Windows\Fonts")
FONTS = {
    "ui": "segoeui.ttf",
    "bold": "segoeuib.ttf",
    "mono": "consolab.ttf",
    "serif": "georgiab.ttf",
    "wide": "bahnschrift.ttf",
    "arial": "arialbd.ttf",
}
ZIRA = "Microsoft Zira Desktop"  # Windows ASR recalls ~2x more of Zira than David
WHITE = (255, 255, 255)


# ---------------------------------------------------------------- helpers ----

def clamp(v, lo=0.0, hi=1.0):
    return max(lo, min(hi, v))


def seg(v, a, b):
    """0 before a, 1 after b, linear in between."""
    return clamp((v - a) / (b - a))


def ease(v):
    v = clamp(v)
    return v * v * (3 - 2 * v)


def mix(c1, c2, a):
    a = clamp(a)
    return tuple(round(u + (v - u) * a) for u, v in zip(c1, c2))


def lerp_pt(p0, p1, a):
    return (p0[0] + (p1[0] - p0[0]) * a, p0[1] + (p1[1] - p0[1]) * a)


def along(path, a):
    """Point at fraction `a` of the polyline `path`."""
    lens = [math.dist(p, q) for p, q in zip(path, path[1:])]
    d = clamp(a) * sum(lens)
    for (p, q), n in zip(zip(path, path[1:]), lens):
        if d <= n:
            return lerp_pt(p, q, d / n if n else 0)
        d -= n
    return path[-1]


@lru_cache(maxsize=None)
def _font(face, px):
    font = ImageFont.truetype(str(FONT_DIR / FONTS[face]), px)
    if face == "wide":
        try:
            font.set_variation_by_name("SemiBold")
        except (OSError, ValueError):
            pass
    return font


class Canvas:
    """ImageDraw wrapper working in output pixels on a supersampled image."""

    def __init__(self, size, bg):
        self.w, self.h = size
        self.im = Image.new("RGB", (self.w * SS, self.h * SS), bg)
        self.d = ImageDraw.Draw(self.im)

    @staticmethod
    def _xy(pts):
        return [(x * SS, y * SS) for x, y in pts]

    @staticmethod
    def _w(width):
        return max(1, round(width * SS))

    @contextmanager
    def faded(self, alpha):
        """Everything drawn inside is blended in at `alpha`."""
        if alpha >= 0.999:
            yield
            return
        base = self.im
        self.im = base.copy()
        self.d = ImageDraw.Draw(self.im)
        try:
            yield
        finally:
            self.im = Image.blend(base, self.im, clamp(alpha))
            self.d = ImageDraw.Draw(self.im)

    def gradient(self, top, bottom, y0=0, y1=None):
        y1 = self.h if y1 is None else y1
        for y in range(round(y0 * SS), round(y1 * SS)):
            a = (y / SS - y0) / max(1, y1 - y0)
            self.d.line([(0, y), (self.w * SS, y)], fill=mix(top, bottom, a))

    def rect(self, x0, y0, x1, y1, fill=None, outline=None, width=1, r=0):
        box = [x0 * SS, y0 * SS, x1 * SS, y1 * SS]
        if r:
            self.d.rounded_rectangle(box, r * SS, fill=fill, outline=outline,
                                     width=self._w(width))
        else:
            self.d.rectangle(box, fill=fill, outline=outline, width=self._w(width))

    def ellipse(self, x0, y0, x1, y1, fill=None, outline=None, width=1):
        self.d.ellipse([x0 * SS, y0 * SS, x1 * SS, y1 * SS], fill=fill,
                       outline=outline, width=self._w(width))

    def circle(self, x, y, r, fill=None, outline=None, width=1):
        self.ellipse(x - r, y - r, x + r, y + r, fill, outline, width)

    def pie(self, x, y, r, a0, a1, fill):
        self.d.pieslice([(x - r) * SS, (y - r) * SS, (x + r) * SS, (y + r) * SS],
                        a0, a1, fill=fill)

    def arc(self, x, y, r, a0, a1, fill, width=1):
        self.d.arc([(x - r) * SS, (y - r) * SS, (x + r) * SS, (y + r) * SS],
                   a0, a1, fill=fill, width=self._w(width))

    def line(self, pts, fill, width=1):
        self.d.line(self._xy(pts), fill=fill, width=self._w(width), joint="curve")

    def poly(self, pts, fill=None, outline=None):
        self.d.polygon(self._xy(pts), fill=fill, outline=outline)

    def arrow(self, x0, y0, x1, y1, fill, width=2, head=6):
        ang = math.atan2(y1 - y0, x1 - x0)
        bx, by = x1 - head * math.cos(ang), y1 - head * math.sin(ang)
        self.line([(x0, y0), (bx, by)], fill, width)
        px, py = -math.sin(ang) * head * 0.6, math.cos(ang) * head * 0.6
        self.poly([(x1, y1), (bx + px, by + py), (bx - px, by - py)], fill=fill)

    def check(self, x, y, s, fill, width=2.5):
        self.line([(x - s, y), (x - s * 0.35, y + s * 0.65), (x + s, y - s * 0.75)],
                  fill, width)

    def text(self, x, y, s, size, fill, face="bold", anchor="mm"):
        self.d.text((x * SS, y * SS), s, font=_font(face, round(size * SS)),
                    fill=fill, anchor=anchor)

    def text_w(self, s, size, face="bold"):
        return self.d.textlength(s, font=_font(face, round(size * SS))) / SS

    def wrap(self, s, size, maxw, face="bold"):
        lines = []
        for para in s.split("\n"):
            cur = ""
            for word in para.split():
                t = f"{cur} {word}".strip()
                if cur and self.text_w(t, size, face) > maxw:
                    lines.append(cur)
                    cur = word
                else:
                    cur = t
            lines.append(cur)
        return lines

    def pill(self, x, y, s, size, fg, bg, face="bold"):
        half = self.text_w(s, size, face) / 2 + 5
        self.rect(x - half, y - size * 0.7, x + half, y + size * 0.7, fill=bg, r=size * 0.7)
        self.text(x, y, s, size, fg, face)

    def paste(self, im, x, y, mask=None):
        self.im.paste(im, (round(x * SS), round(y * SS)), mask)

    def frame(self):
        return self.im.resize((self.w, self.h), Image.LANCZOS)


# ------------------------------------------------------------------- data ----

@dataclass
class Theme:
    bg: tuple
    fg: tuple
    muted: tuple
    accent: tuple
    accent2: tuple
    panel: tuple
    face: str = "bold"  # headings and captions
    body: str = "ui"  # smaller text
    backdrop: str = "plain"  # painter drawn under every scene
    caption_band: tuple | None = None
    caption_fg: tuple | None = None
    caption_prompt: bool = False  # terminal-style "> caption_"
    caption_y: float = 12.5


@dataclass
class Scene:
    paint: str  # key into PAINTERS
    say: str  # narration, spoken while the scene plays
    caption: str = ""
    args: dict = field(default_factory=dict)
    morse: str = ""  # beeped after the narration, e.g. "... --- ..."
    # Filled in by build_audio(), in seconds from the scene start.
    dur: float = 0.0
    speech_start: float = 0.0
    speech_end: float = 0.0
    beeps: list = field(default_factory=list)


@dataclass
class Topic:
    stem: str  # file name words; the budget suffix is added
    budget_kb: int
    theme: Theme
    scenes: list
    size: tuple = (320, 180)
    voice: str = ZIRA
    rate: int = 0  # SAPI speaking rate, -10..10
    chord: tuple = (261.63, 329.63, 392.0)  # quiet background pad + chimes
    webm: bool = False
    audio_kbps: int = 20  # AAC needs ~20 kbps for clear speech; Opus is fine at 10

    @property
    def name(self):
        return f"{self.stem}_{self.budget_kb}kb"


@dataclass
class Ctx:
    topic: Topic
    scene: Scene
    t: float  # seconds into the scene
    T: float  # seconds into the video

    @property
    def th(self):
        return self.topic.theme

    @property
    def a(self):
        return self.scene.args

    @property
    def p(self):
        return clamp(self.t / self.scene.dur)

    @property
    def sp(self):
        """Narration progress: 0 when the line starts, 1 when it ends."""
        s = self.scene
        return seg(self.t, s.speech_start, max(s.speech_start + 0.1, s.speech_end))

    def lit(self):
        """Index of the morse symbol beeping right now, or -1."""
        for i, (b0, b1) in enumerate(self.scene.beeps):
            if b0 <= self.t < b1:
                return i
        return -1


PAINTERS = {}


def painter(fn):
    PAINTERS[fn.__name__] = fn
    return fn


# ---------------------------------------------------------- common scenes ----

@painter
def plain(c, x):
    pass


@painter
def title(c, x):
    a, th = x.a, x.th
    if "backdrop" in a:
        PAINTERS[a["backdrop"]](c, x)
    cx, width = a.get("cx", c.w / 2), a.get("width", c.w - 30)
    size = a.get("size", 26)
    lines = c.wrap(a["title"], size, width, th.face)
    subs = c.wrap(a["sub"], 12, width, th.body) if a.get("sub") else []
    lh = size * 1.15
    block = len(lines) * lh + (10 + len(subs) * 15 if subs else 0)
    top = c.h * a.get("y", 0.5) - block / 2
    k = ease(seg(x.t, 0.05, 0.7))
    if a.get("panel"):
        with c.faded(k * 0.92):
            c.rect(cx - width / 2 - 8, top - 10, cx + width / 2 + 8, top + block + 10,
                   fill=th.panel, r=10)
    with c.faded(k):
        for i, ln in enumerate(lines):
            c.text(cx, top + lh * (i + 0.5) + (1 - k) * 8, ln, size, th.fg, th.face)
    y_rule = top + len(lines) * lh + 2
    half = width * 0.22 * ease(seg(x.t, 0.4, 1.1))
    c.rect(cx - half, y_rule, cx + half, y_rule + 2.5, fill=th.accent)
    with c.faded(ease(seg(x.t, 0.8, 1.4))):
        for j, ln in enumerate(subs):
            c.text(cx, y_rule + 14 + j * 15, ln, 12, th.muted, th.body)


def draw_caption(c, x):
    cap, th = x.scene.caption, x.th
    if not cap:
        return
    if th.caption_prompt:
        shown = cap[:int(len(cap) * seg(x.t, 0.05, 0.8))]
        cursor = "_" if int(x.T * 2.5) % 2 == 0 else " "
        c.text(10, 14, f"> {shown}{cursor}", 13, th.accent, th.face, "lm")
        return
    lines = c.wrap(cap, 14, c.w - 20, th.face)
    fg = th.caption_fg or th.fg
    with c.faded(ease(seg(x.t, 0, 0.35))):
        if th.caption_band:
            c.rect(0, 0, c.w, len(lines) * 17 + 8, fill=th.caption_band)
        for i, ln in enumerate(lines):
            c.text(c.w / 2, th.caption_y + i * 17, ln, 14, fg, th.face)


# ---------------------------------------------------------------- QR code ----

def qr_matrix(seed):
    """21x21 (version 1) layout: real finder/timing patterns, random data."""
    n = 21
    m = [[0] * n for _ in range(n)]
    fixed = [[False] * n for _ in range(n)]

    def mark(r, col, v):
        m[r][col], fixed[r][col] = v, True

    for r0, c0 in ((0, 0), (0, 14), (14, 0)):
        for r in range(-1, 8):
            for col in range(-1, 8):
                if 0 <= r0 + r < n and 0 <= c0 + col < n:
                    ring = max(abs(r - 3), abs(col - 3))
                    mark(r0 + r, c0 + col, int(ring in (0, 1, 3)))
    for i in range(8, 13):
        mark(6, i, int(i % 2 == 0))
        mark(i, 6, int(i % 2 == 0))
    mark(13, 8, 1)
    rnd = random.Random(seed)
    for r in range(n):
        for col in range(n):
            if not fixed[r][col]:
                m[r][col] = int(rnd.random() < 0.48)
    return m


QR = qr_matrix(7)
QR_FRAMES = [qr_matrix(s) for s in range(20, 28)]
QR_ORDER = [(r, col) for r in range(21) for col in range(21)]
random.Random(1).shuffle(QR_ORDER)
FINDERS = ((0, 0), (0, 14), (14, 0))


def draw_qr(c, x0, y0, cell, m, dark, light, reveal=1.0, pending=None):
    c.rect(x0 - cell, y0 - cell, x0 + 22 * cell, y0 + 22 * cell, fill=light)
    shown = round(reveal * len(QR_ORDER))
    for idx, (r, col) in enumerate(QR_ORDER):
        px, py = x0 + col * cell, y0 + r * cell
        if idx < shown:
            if m[r][col]:
                c.rect(px, py, px + cell, py + cell, fill=dark)
        elif pending:
            c.rect(px + cell * 0.2, py + cell * 0.2, px + cell * 0.8, py + cell * 0.8,
                   fill=pending)


@painter
def bg_qr(c, x):
    c.rect(0, c.h - 4, c.w, c.h, fill=x.th.accent)


@painter
def qr_title_bg(c, x):
    draw_qr(c, 22, 46, 4.2, QR, x.th.fg, WHITE, ease(seg(x.t, 0, 1.6)), x.th.panel)


@painter
def qr_bits(c, x):
    th = x.th
    x0, y0, cell = 20, 38, 5.8
    reveal = ease(seg(x.sp, 0.0, 0.55))
    draw_qr(c, x0, y0, cell, QR, th.fg, WHITE, reveal, th.panel)
    rx = 176
    with c.faded(ease(seg(x.sp, 0.3, 0.45))):
        c.rect(rx, 44, rx + 16, 60, fill=th.fg)
        c.text(rx + 26, 52, "= 1", 18, th.fg, th.face, "lm")
    with c.faded(ease(seg(x.sp, 0.6, 0.75))):
        c.rect(rx, 70, rx + 16, 86, fill=WHITE, outline=th.fg, width=1.2)
        c.text(rx + 26, 78, "= 0", 18, th.fg, th.face, "lm")
    k = ease(seg(x.sp, 0.55, 0.75))
    if k > 0:
        row = int(x.T * 3) % 21
        with c.faded(k):
            c.rect(x0 - 2, y0 + row * cell - 1, x0 + 21 * cell + 2, y0 + (row + 1) * cell + 1,
                   outline=th.accent2, width=1.5)
            bits = "".join(str(v) for v in QR[row])
            c.text(rx, 108, f"row {row + 1:2d}:", 11, th.muted, "mono", "lm")
            c.text(rx, 124, bits[:11], 13, th.accent, "mono", "lm")
            c.text(rx, 140, bits[11:], 13, th.accent, "mono", "lm")


@painter
def qr_finders(c, x):
    th = x.th
    cell, pad = 5.4, 8
    side = 21 * cell + 2 * pad
    sub = Canvas((round(side), round(side)), th.bg)
    draw_qr(sub, pad, pad, cell, QR, th.fg, WHITE)
    pulse = 1 + 0.1 * math.sin(x.T * 7)
    for i, (r0, c0) in enumerate(FINDERS):
        k = ease(seg(x.sp, 0.08 + 0.1 * i, 0.2 + 0.1 * i))
        if k <= 0:
            continue
        g = cell * (0.6 + 2.5 * (1 - k)) * pulse
        sub.rect(pad + c0 * cell - g, pad + r0 * cell - g,
                 pad + (c0 + 7) * cell + g, pad + (r0 + 7) * cell + g,
                 outline=th.accent2, width=2.2)
    angle = -35 * (1 - ease(seg(x.sp, 0.5, 0.85)))
    rotated = sub.im.rotate(angle, resample=Image.BICUBIC, fillcolor=th.bg)
    ox, oy = 12, 30
    c.paste(rotated, ox, oy)
    br, x1, y1 = 12, ox + side, oy + side
    for (bx, by, sx, sy) in ((ox, oy, 1, 1), (x1, oy, -1, 1), (ox, y1, 1, -1), (x1, y1, -1, -1)):
        c.line([(bx, by + sy * br), (bx, by), (bx + sx * br, by)], th.muted, 1.5)
    rx = 172
    for i, (text, at) in enumerate((("Where it is", 0.25), ("Which way up", 0.65))):
        with c.faded(ease(seg(x.sp, at, at + 0.12))):
            y = 72 + i * 34
            c.check(rx + 6, y, 6, th.accent)
            c.text(rx + 20, y, text, 14, th.fg, th.face, "lm")


@painter
def qr_damage(c, x):
    th = x.th
    x0, y0, cell = 20, 38, 5.6
    draw_qr(c, x0, y0, cell, QR, th.fg, WHITE)
    k = ease(seg(x.sp, 0.05, 0.5))
    side = 21 * cell
    cx, cy, rad = x0 + side * 0.66, y0 + side * 0.7, 32 * k
    for dx, dy, s in ((0, 0, 1.0), (-0.55, 0.35, 0.55), (0.45, -0.4, 0.5)):
        c.circle(cx + dx * rad, cy + dy * rad, rad * s, fill=(160, 112, 64))
    if rad > 2:
        c.circle(cx, cy, rad * 0.6, fill=(140, 96, 52))
    rx = 234
    with c.faded(ease(seg(x.sp, 0.3, 0.45))):
        c.text(rx, 52, "up to", 12, th.muted, th.body)
        c.text(rx, 78, "30%", 30, th.accent, th.face)
        c.text(rx, 102, "can be repaired", 12, th.muted, th.body)
    ok = ease(seg(x.sp, 0.7, 0.85))
    if ok > 0:
        with c.faded(ok):
            c.rect(rx - 62, 124, rx + 62, 148, fill=th.accent, r=12)
            c.check(rx - 44, 136, 5, WHITE, 2.2)
            c.text(rx + 8, 136, "Still readable", 13, WHITE, th.face)


def phone(c, x0, y0, x1, y1, body=(34, 38, 46)):
    c.rect(x0, y0, x1, y1, fill=body, r=8)
    c.rect(x0 + 4, y0 + 10, x1 - 4, y1 - 10, fill=WHITE, r=2)


@painter
def qr_stream(c, x):
    th = x.th
    phone(c, 36, 36, 104, 164)
    m = QR_FRAMES[int(x.T * 4) % len(QR_FRAMES)]
    draw_qr(c, 45.5, 76, 2.3, m, th.fg, WHITE)
    phone(c, 216, 36, 284, 164)
    for j in range(7):
        for row in (84, 100, 116):
            xx = 110 + ((x.T * 70 + j * 16 + row) % 100)
            c.line([(xx, row), (xx + 7, row)], mix(WHITE, th.accent, 0.4 + 0.6 * (xx - 110) / 100), 2)
    prog = ease(seg(x.sp, 0.05, 0.9))
    c.rect(226, 96, 274, 104, fill=th.panel, r=4)
    c.rect(226, 96, 226 + 48 * prog, 104, fill=th.accent, r=4)
    c.text(250, 116, f"{prog * 100:3.0f}%", 11, th.muted, th.body)
    if prog >= 1:
        c.rect(230, 58, 270, 88, fill=th.accent2, r=3)
        c.check(250, 73, 6, WHITE)
        c.text(250, 136, "photo.jpg", 10, th.fg, th.face)


# ------------------------------------------------------------------ sound ----

WAVE_K = 2 * math.pi / 60
WAVE_W = WAVE_K * 34


def wave_phase(bx, T):
    return WAVE_K * bx - WAVE_W * T


def particle_field(c, x, x0, x1, y0, y1, rows, lo, hi, amp=4.5, spacing=6.5):
    rnd = random.Random(3)
    pts = []
    cols = int((x1 - x0) / spacing) + 1
    for i in range(cols):
        bx = x0 + i * spacing
        for j in range(rows):
            jx, jy = rnd.uniform(-0.5, 0.5), rnd.uniform(-1.2, 1.2)
            ph = wave_phase(bx + jx, x.T)
            squeeze = (1 - math.cos(ph)) / 2
            px = bx + jx + amp * math.sin(ph)
            py = y0 + (y1 - y0) * j / (rows - 1) + jy
            c.circle(px, py, 1.6 + 0.5 * squeeze, fill=mix(lo, hi, squeeze))
            pts.append((i, j, px, py))
    return pts


def speaker(c, x, y, color, push):
    c.rect(x - 10, y - 9, x, y + 9, fill=color)
    c.poly([(x, y - 5), (x + 9 + push, y - 16), (x + 9 + push, y + 16), (x, y + 5)], fill=color)


@painter
def bg_sound(c, x):
    c.gradient(x.th.bg, (22, 40, 88))


@painter
def sound_title_bg(c, x):
    particle_field(c, x, 10, 310, 142, 170, 3, (30, 50, 90), (70, 100, 160))


@painter
def sound_wave(c, x):
    th = x.th
    x0 = 48
    speaker(c, 26, 88, th.muted, 4.5 * math.sin(wave_phase(x0, x.T)))
    particle_field(c, x, x0, 308, 58, 118, 6, (50, 70, 120), th.fg)
    k = ease(seg(x.sp, 0.35, 0.6))
    if k > 0:
        with c.faded(k):
            pts = [(bx, 144 + 9 * math.cos(wave_phase(bx, x.T)))
                   for bx in range(x0, 309, 3)]
            c.line(pts, th.accent2, 1.8)
            c.text(160, 168, "bright = squeezed     dim = spread out", 10, th.muted, th.body)


@painter
def sound_jiggle(c, x):
    th = x.th
    x0 = 48
    speaker(c, 26, 88, th.muted, 4.5 * math.sin(wave_phase(x0, x.T)))
    pts = particle_field(c, x, x0, 308, 58, 118, 6, (40, 58, 100), (110, 130, 180))
    col = 20
    for i, j, px, py in pts:
        if i == col and j == 5:
            bx = x0 + col * 6.5
            c.circle(px, py, 4, fill=th.accent)
            c.line([(bx - 5, 128), (bx + 5, 128)], th.accent, 1.5)
            for ex in (bx - 5, bx + 5):
                c.line([(ex, 124), (ex, 132)], th.accent, 1.5)
            c.text(bx, 142, "jiggles in place", 11, th.accent, th.body)
    k = ease(seg(x.sp, 0.45, 0.65))
    if k > 0:
        with c.faded(k):
            c.arrow(60, 162, 300, 162, th.accent2, 1.5, 6)
            head = 60 + (x.T * 34) % 230
            c.circle(head, 162, 3, fill=th.accent2)
            c.text(60, 152, "the wave moves on", 10, th.accent2, th.body, "lm")


@painter
def sound_speeds(c, x):
    th = x.th
    rows = [("Air", 343, (170, 210, 255), ""), ("Water", 1480, (80, 160, 255), "about 4x"),
            ("Steel", 5960, (205, 210, 222), "about 17x")]
    for i, (name, v, color, times) in enumerate(rows):
        y = 58 + i * 40
        g = ease(seg(x.sp, 0.1 + 0.28 * i, 0.35 + 0.28 * i))
        with c.faded(ease(seg(x.sp, 0.05 + 0.28 * i, 0.15 + 0.28 * i))):
            c.text(14, y, name, 14, th.fg, th.face, "lm")
            end = 70 + 170 * v / 5960 * g
            c.rect(70, y - 7, max(72, end), y + 7, fill=color, r=4)
            c.text(end + 6, y - 1, f"{round(v * g):,} m/s", 12, th.fg, th.face, "lm")
            if times and g >= 1:
                c.text(end + 6, y + 13, times, 10, th.accent, th.body, "lm")


def starfield(c, count=60, seed=5, area=None):
    rnd = random.Random(seed)
    x0, y0, x1, y1 = area or (0, 0, c.w, c.h)
    for _ in range(count):
        v = rnd.randint(120, 255)
        c.circle(rnd.uniform(x0, x1), rnd.uniform(y0, y1), rnd.uniform(0.4, 1.0), fill=(v, v, v))


@painter
def sound_space(c, x):
    th = x.th
    with c.faded(ease(seg(x.t, 0, 0.6))):
        c.rect(0, 0, c.w, c.h, fill=(4, 6, 16))
        starfield(c)
    speaker(c, 70, 100, th.muted, 2 * math.sin(x.T * 20))
    for j in range(3):
        r = 12 + (x.T * 18 + j * 8) % 24
        c.arc(79, 100, r, -40, 40, mix(th.fg, (4, 6, 16), (r - 12) / 24), 2)
    k = ease(seg(x.sp, 0.35, 0.5))
    if k > 0:
        with c.faded(k):
            c.line([(86, 84), (112, 116)], (240, 80, 80), 3)
            c.line([(86, 116), (112, 84)], (240, 80, 80), 3)
    with c.faded(ease(seg(x.sp, 0.5, 0.7))):
        c.text(220, 88, "No air,", 20, th.fg, th.face)
        c.text(220, 114, "no sound", 20, th.accent, th.face)
        c.text(160, 156, "a vacuum has nothing to vibrate", 11, th.muted, th.body)


# ----------------------------------------------------------------- binary ----

def bulbs(c, th, value, y=84, n=8, x0=34, x1=286, r=12, labels=True, label_alpha=None):
    step = (x1 - x0) / (n - 1)
    for i in range(n):
        bit = (value >> (n - 1 - i)) & 1
        bx = x0 + i * step
        if bit:
            c.circle(bx, y, r + 4, fill=mix(th.bg, th.accent, 0.25))
            c.circle(bx, y, r, fill=th.accent)
        else:
            c.circle(bx, y, r, fill=th.panel, outline=mix(th.bg, th.muted, 0.7), width=1.5)
        c.text(bx, y + 1, str(bit), 13, th.bg if bit else th.muted, "mono")
        if labels:
            a = 1 if label_alpha is None else label_alpha[i]
            if a > 0:
                with c.faded(a):
                    c.text(bx, y + r + 13, str(2 ** (n - 1 - i)), 12, th.fg, "mono")


@painter
def bin_rain(c, x):
    rnd = random.Random(9)
    for col in range(0, c.w, 16):
        speed, off = rnd.uniform(18, 40), rnd.uniform(0, 200)
        head = (x.T * speed + off) % (c.h + 60) - 30
        for k in range(6):
            y = head - k * 12
            if 0 < y < c.h:
                ch = "01"[(col // 16 + k + int(y // 12)) % 2]
                c.text(col + 8, y, ch, 11, mix(x.th.bg, x.th.muted, 0.55 - k * 0.08), "mono")


@painter
def bin_places(c, x):
    th = x.th
    alphas = [ease(seg(x.sp, 0.1 + (7 - i) * 0.09, 0.18 + (7 - i) * 0.09)) for i in range(8)]
    lit = 0
    for i in range(8):
        if 0 < alphas[i] < 1:
            lit = 1 << (7 - i)
    bulbs(c, th, lit, label_alpha=alphas)
    k = ease(seg(x.sp, 0.2, 0.9))
    for i in range(7):
        if alphas[i] > 0.5:
            bx = 34 + (i + 0.5) * 36
            c.text(bx, 132, "x2", 10, th.muted, "mono")
            c.arrow(bx + 8, 124, bx - 8, 124, mix(th.bg, th.muted, k), 1, 4)
    with c.faded(ease(seg(x.sp, 0.85, 1.0))):
        c.text(160, 158, "each place = 2 x the one to its right", 11, th.accent2, "mono")


@painter
def bin_count(c, x):
    th = x.th
    value = min(5, int(seg(x.sp, 0.05, 0.6) * 6))
    bulbs(c, th, value, y=70)
    bits = f"{value:08b}"
    step = 16
    for i, b in enumerate(bits):
        on = b == "1"
        c.text(160 + (i - 3.5) * step, 118, b, 22, th.accent if on else mix(th.bg, th.muted, 0.6), "mono")
    with c.faded(ease(seg(x.sp, 0.6, 0.75))):
        c.text(160, 152, "4 + 1 = 5", 18, th.fg, "mono")


@painter
def bin_byte(c, x):
    th = x.th
    value = round(255 * ease(seg(x.sp, 0.05, 0.8)))
    bulbs(c, th, value, y=70)
    c.text(160, 124, f"= {value}", 26, th.accent, "mono")
    with c.faded(ease(seg(x.sp, 0.6, 0.8))):
        c.text(160, 156, "256 values: 0 to 255", 12, th.fg, "mono")


@painter
def bin_letter(c, x):
    th = x.th
    c.text(40, 64, "A", 36, th.fg, "mono")
    with c.faded(ease(seg(x.sp, 0.1, 0.25))):
        c.text(86, 64, "=", 22, th.muted, "mono")
        c.text(130, 64, "65", 30, th.accent, "mono")
    with c.faded(ease(seg(x.sp, 0.25, 0.4))):
        c.text(172, 64, "=", 22, th.muted, "mono")
        c.text(250, 64, "01000001", 18, th.accent2, "mono")
    bulbs(c, th, 65 if x.sp > 0.3 else 0, y=108, r=10, labels=False)
    k = ease(seg(x.sp, 0.55, 0.7))
    if k > 0:
        stream = " ".join(f"{ord(ch):08b}" for ch in "Hi! Light+Sound ") * 2
        off = (x.T * 40) % (len(stream) * 7.2 / 2)
        with c.faded(k * 0.8):
            c.text(10 - off, 150, stream, 12, th.muted, "mono", "lm")


# ------------------------------------------------------------------ morse ----

def morse_events(pattern):
    """(start, end) beep times for '.', '-', ' ' (letter gap) and total length."""
    t, events = 0.0, []
    for ch in pattern:
        if ch in ".-":
            n = 1 if ch == "." else 3
            events.append((t, t + n * MORSE_UNIT))
            t += (n + 1) * MORSE_UNIT
        elif ch == " ":
            t += 2 * MORSE_UNIT
    return events, max(0.0, t - MORSE_UNIT)


def morse_glyphs(c, x, y, pattern, u, color, lit_color, lit=-1, first=0):
    syms = [s for s in pattern if s in ".-"]
    width = sum(u if s == "." else 3 * u for s in syms) + u * (len(syms) - 1)
    xx = x - width / 2
    for i, s in enumerate(syms):
        on = first + i == lit
        col = lit_color if on else color
        if on:
            glow = mix(lit_color, (243, 233, 210), 0.6)
            if s == ".":
                c.circle(xx + u / 2, y, u * 0.9, fill=glow)
            else:
                c.rect(xx - u * 0.4, y - u * 0.9, xx + 3.4 * u, y + u * 0.9, fill=glow, r=u)
        if s == ".":
            c.circle(xx + u / 2, y, u / 2, fill=col)
        else:
            c.rect(xx, y - u / 2, xx + 3 * u, y + u / 2, fill=col, r=u / 2)
        xx += (u if s == "." else 3 * u) + u


@painter
def bg_paper(c, x):
    c.rect(5, 5, c.w - 5, c.h - 5, outline=x.th.muted, width=1)
    c.rect(8, 8, c.w - 8, c.h - 8, outline=mix(x.th.bg, x.th.muted, 0.5), width=1)


@painter
def morse_title_bg(c, x):
    k = seg(x.t, 0.3, 2.0)
    word = "-- --- .-. ... ."  # MORSE
    with c.faded(0.35 * k):
        morse_glyphs(c, c.w / 2, 150, word, 5, x.th.fg, x.th.accent)


@painter
def morse_units(c, x):
    th = x.th
    lit = x.lit()
    with c.faded(ease(seg(x.sp, 0.0, 0.2))):
        morse_glyphs(c, 95, 76, ".", 14, th.fg, th.accent, lit, 0)
        c.text(95, 108, "dot", 16, th.fg, th.face)
        c.text(95, 126, "1 unit", 12, th.muted, th.face)
    with c.faded(ease(seg(x.sp, 0.45, 0.65))):
        morse_glyphs(c, 225, 76, "-", 14, th.fg, th.accent, lit, 1)
        c.text(225, 108, "dash", 16, th.fg, th.face)
        c.text(225, 126, "3 units", 12, th.muted, th.face)
    for i in range(4):
        tick = 204 + i * 14
        c.line([(tick, 144), (tick, 150)], th.muted, 1)
    c.line([(204, 147), (246, 147)], th.muted, 1)
    c.line([(88, 144), (88, 150)], th.muted, 1)
    c.line([(102, 144), (102, 150)], th.muted, 1)
    c.line([(88, 147), (102, 147)], th.muted, 1)


@painter
def morse_letter(c, x):
    th = x.th
    c.text(104, 86, "E", 60, th.fg, th.face)
    with c.faded(ease(seg(x.sp, 0.4, 0.6))):
        c.text(160, 88, "=", 30, th.muted, th.face)
        morse_glyphs(c, 212, 90, ".", 18, th.fg, th.accent, x.lit())
    with c.faded(ease(seg(x.sp, 0.7, 0.95))):
        for i, (letter, code) in enumerate((("T", "-"), ("A", ".-"), ("N", "-."))):
            bx = 70 + i * 90
            c.text(bx - 18, 148, letter, 15, th.fg, th.face)
            morse_glyphs(c, bx + 14, 149, code, 6, th.muted, th.accent)


@painter
def morse_sos(c, x):
    th = x.th
    lit = x.lit()
    for i, (letter, code) in enumerate((("S", "..."), ("O", "---"), ("S", "..."))):
        bx = 75 + i * 85
        with c.faded(ease(seg(x.sp, 0.3 + 0.15 * i, 0.45 + 0.15 * i))):
            c.text(bx, 58, letter, 30, th.fg, th.face)
            morse_glyphs(c, bx, 96, code, 9, th.fg, th.accent, lit, i * 3)
    on = lit >= 0
    lx, ly = 160, 142
    if on:
        for k in range(8):
            ang = k * math.pi / 4
            c.line([(lx + 17 * math.cos(ang), ly + 17 * math.sin(ang)),
                    (lx + 24 * math.cos(ang), ly + 24 * math.sin(ang))], th.accent2, 2)
    c.circle(lx, ly, 12, fill=(255, 214, 90) if on else (214, 202, 178), outline=th.fg, width=1.5)
    c.text(lx - 44, ly, "light", 11, th.muted, th.face)
    c.text(lx + 46, ly, "sound", 11, th.muted, th.face)


@painter
def morse_media(c, x):
    th = x.th
    for i, name in enumerate(("Sound", "Light", "Radio")):
        bx, by = 65 + i * 95, 88
        k = ease(seg(x.sp, 0.12 + 0.2 * i, 0.3 + 0.2 * i))
        col = mix(th.muted, th.accent, k)
        if i == 0:
            speaker(c, bx - 6, by, col, 0)
            for r in (10, 17):
                c.arc(bx + 3, by, r, -45, 45, col, 2)
        elif i == 1:
            c.circle(bx, by - 4, 13, fill=mix(th.panel, (255, 214, 90), k), outline=col, width=2)
            c.rect(bx - 6, by + 9, bx + 6, by + 18, fill=col, r=2)
        else:
            c.poly([(bx, by - 16), (bx - 11, by + 18), (bx + 11, by + 18)], outline=col)
            c.line([(bx, by - 16), (bx - 11, by + 18)], col, 2)
            c.line([(bx, by - 16), (bx + 11, by + 18)], col, 2)
            for r in (8, 14):
                c.arc(bx, by - 16, r, -150, -30, col, 1.8)
        c.text(bx, 132, name, 15, mix(th.muted, th.fg, k), th.face)
    with c.faded(ease(seg(x.sp, 0.8, 1.0))):
        morse_glyphs(c, 160, 160, "... --- ...", 4, th.muted, th.accent)


# ------------------------------------------------------------ water cycle ----

SUN_W = (34, 56)
RIVER = [(188, 132), (180, 150), (188, 166), (172, 182), (158, 196), (142, 206), (130, 216)]
CLOUD = [(-22, 4, 13), (-8, -6, 16), (10, -4, 15), (24, 5, 11), (0, 8, 14)]


def cloud(c, cx, cy, k, color):
    for dx, dy, r in CLOUD:
        c.circle(cx + dx * k, cy + dy * k, r * k, fill=color)


def sun(c, x, y, r, T, color=(255, 214, 60), rays=(255, 196, 40)):
    for j in range(10):
        ang = math.radians(j * 36 + T * 12)
        c.line([(x + (r + 4) * math.cos(ang), y + (r + 4) * math.sin(ang)),
                (x + (r + 10) * math.cos(ang), y + (r + 10) * math.sin(ang))], rays, 2)
    c.circle(x, y, r, fill=color)


@painter
def bg_water(c, x):
    c.gradient((104, 176, 234), (222, 241, 252), 0, 178)
    sun(c, *SUN_W, 14, x.T)
    c.poly([(104, 240), (190, 118), (240, 158), (240, 240)], fill=(96, 138, 92))
    c.poly([(190, 118), (211, 136), (203, 132), (196, 139), (188, 131), (181, 138), (176, 140)],
           fill=WHITE)
    c.ellipse(118, 200, 320, 280, fill=(112, 170, 92))
    c.poly([(0, 176), (150, 176), (124, 240), (0, 240)], fill=(38, 108, 190))
    for row in (188, 202, 218):
        shore = 150 - (row - 176) * 26 / 64
        pts = [(xx, row + 1.5 * math.sin(xx * 0.22 + x.T * 2.2)) for xx in range(4, int(shore) - 4, 3)]
        c.line(pts, (150, 196, 240), 1)
    c.line(RIVER, (58, 128, 210), 3)


def vapour(c, x, xs, y0, y1, color, sky, speed=0.45):
    for j, bx in enumerate(xs):
        for m in range(2):
            prog = (x.T * speed + j * 0.27 + m * 0.5) % 1
            yb = y0 - prog * (y0 - y1)
            pts = [(bx + 3 * math.sin(yy * 0.45 + j), yy) for yy in range(int(yb - 16), int(yb) + 1, 2)]
            c.line(pts, mix(color, sky, prog ** 2.5), 2.6)


@painter
def water_evap(c, x):
    k = ease(seg(x.sp, 0.1, 0.4))
    with c.faded(k):
        vapour(c, x, (22, 50, 78, 106), 180, 96, WHITE, (160, 205, 245))
    glow = 0.5 + 0.5 * math.sin(x.T * 5)
    c.circle(*SUN_W, 14 + 2 * glow, outline=(255, 230, 120), width=1.5)


@painter
def water_cond(c, x):
    k = ease(seg(x.sp, 0.05, 0.75))
    vapour(c, x, (70, 100), 150, 90, WHITE, (170, 210, 245), 0.35)
    cloud(c, 158, 74, 0.35 + 0.65 * k, mix((210, 230, 250), (248, 250, 253), k))
    rnd = random.Random(2)
    for _ in range(int(14 * k)):
        c.circle(158 + rnd.uniform(-24, 24), 76 + rnd.uniform(-6, 8), 1.2, fill=(120, 170, 225))


@painter
def water_rain(c, x):
    k = ease(seg(x.t, 0, 0.8))
    cloud(c, 158, 74, 1.0, mix((248, 250, 253), (158, 170, 190), k))
    rnd = random.Random(4)
    for _ in range(26):
        bx, ph = rnd.uniform(132, 190), rnd.uniform(0, 80)
        y = 88 + (x.T * 110 + ph) % 70
        with c.faded(k):
            c.line([(bx, y), (bx - 1, y + 5)], (52, 110, 210), 1.5)
    for _ in range(6):
        bx, ph = rnd.uniform(180, 204), rnd.uniform(0, 30)
        y = 100 + (x.T * 18 + ph) % 30
        c.circle(bx + 2 * math.sin(x.T * 3 + ph), y, 1.4, fill=WHITE)


@painter
def water_collect(c, x):
    th = x.th
    cloud(c, 158, 74, 1.0, (225, 232, 242))
    for j in range(8):
        a = (x.T * 0.35 + j / 8) % 1
        px, py = along(RIVER, a)
        c.circle(px, py, 1.6, fill=(200, 230, 255))
    steps = [((60, 172), (60, 104), "evaporate", (60, 138)),
             ((82, 84), (130, 70), "condense", (104, 92)),
             ((170, 94), (170, 150), "rain", (190, 116)),
             ((168, 190), (118, 212), "collect", (150, 222))]
    for i, (p0, p1, label, lp) in enumerate(steps):
        k = ease(seg(x.sp, 0.35 + 0.13 * i, 0.48 + 0.13 * i))
        if k > 0:
            with c.faded(k):
                c.arrow(*p0, *lerp_pt(p0, p1, k), th.fg, 2.2, 7)
                c.pill(*lp, label, 10, WHITE, th.fg)


# ---------------------------------------------------------------- seasons ----

LAND = [(0.0, -0.35, 0.5, 0.32), (0.3, 0.35, 0.28, 0.45), (1.1, -0.4, 0.7, 0.3),
        (1.3, 0.1, 0.25, 0.3), (1.8, 0.5, 0.35, 0.18), (0.7, -0.8, 0.7, 0.14)]


def draw_earth(c, x, y, r, tilt, sun_ang, spin=0.0, lat_lines=False, night=0.62, axis=True):
    """Side view; `tilt` leans the north pole toward +x, `sun_ang` points at the Sun."""
    d = max(4, round(2 * r * SS))
    sub = Image.new("RGB", (d, d), (34, 104, 206))
    sd = ImageDraw.Draw(sub)
    unit = d / 2
    for lx, ly, lw, lh in LAND:
        px = ((lx + spin) % 2.4 - 1.2) * unit + unit
        py = ly * unit + unit
        sd.ellipse([px - lw * unit, py - lh * unit, px + lw * unit, py + lh * unit],
                   fill=(76, 160, 84))
    if lat_lines:
        for lat, width in ((0, 2), (23.5, 1), (-23.5, 1)):
            yy = unit - math.sin(math.radians(lat)) * unit
            sd.line([(0, yy), (d, yy)], fill=(200, 225, 255), width=width)
    sub = sub.rotate(-tilt, resample=Image.BICUBIC)
    mask = Image.new("L", (d, d), 0)
    ImageDraw.Draw(mask).ellipse([1, 1, d - 2, d - 2], fill=255)
    c.paste(sub, x - r, y - r, mask)
    with c.faded(night):
        c.pie(x, y, r, sun_ang + 90, sun_ang + 270, fill=(2, 4, 14))
    ax, ay = math.sin(math.radians(tilt)), -math.cos(math.radians(tilt))
    if axis:
        c.line([(x - ax * r * 1.3, y - ay * r * 1.3), (x + ax * r * 1.3, y + ay * r * 1.3)],
               (235, 235, 245), max(1.0, r / 22))
    return (x + ax * r * 1.3, y + ay * r * 1.3), (x - ax * r * 1.3, y - ay * r * 1.3)


@painter
def bg_space(c, x):
    starfield(c, 70, 11)


@painter
def seasons_title_bg(c, x):
    for r, a in ((60, 0.12), (46, 0.2), (36, 0.35)):
        c.circle(330, 90, r, fill=mix(x.th.bg, x.th.accent, a))
    c.circle(330, 90, 28, fill=(255, 214, 90))


@painter
def seasons_distance(c, x):
    th = x.th
    cx, cy, R = 160, 104, 62
    c.circle(cx, cy, R, outline=mix(th.bg, th.muted, 0.6), width=1)
    c.circle(cx, cy, 16, fill=(255, 208, 80))
    ang = math.pi + x.p * 1.2
    ex, ey = cx + R * math.cos(ang), cy + R * math.sin(ang)
    draw_earth(c, ex, ey, 7, 0, math.degrees(math.atan2(cy - ey, cx - ex)), night=0.5)
    with c.faded(ease(seg(x.sp, 0.45, 0.65))):
        c.text(cx - R - 12, cy - 24, "January", 12, th.accent2, th.face, "rm")
        c.text(cx - R - 12, cy - 10, "147 million km", 10, th.fg, th.body, "rm")
        c.text(cx + R + 12, cy - 24, "July", 12, th.accent, th.face, "lm")
        c.text(cx + R + 12, cy - 10, "152 million km", 10, th.fg, th.body, "lm")
    with c.faded(ease(seg(x.sp, 0.8, 1.0))):
        c.text(cx, 172, "closest in January... yet it's winter up north", 11, th.muted, th.body)


@painter
def seasons_tilt(c, x):
    th = x.th
    cx, cy, r = 160, 106, 46
    tilt = 23.5 * ease(seg(x.sp, 0.2, 0.6))
    for y in range(int(cy - 66), int(cy + 66), 8):
        c.line([(cx, y), (cx, y + 4)], th.muted, 1)
    north, _ = draw_earth(c, cx, cy, r, tilt, 180, spin=x.T * 0.25, lat_lines=True, night=0.45)
    c.text(north[0] + 8, north[1] - 4, "N", 13, th.fg, th.face)
    k = ease(seg(x.sp, 0.55, 0.75))
    if k > 0:
        with c.faded(k):
            c.arc(cx, cy, 62, -90, -90 + tilt, th.accent, 2)
            c.text(cx + 58, cy - 66, "23.5°", 15, th.accent, th.face, "lm")


@painter
def seasons_orbit(c, x):
    th = x.th
    cx, cy, rx, ry = 160, 100, 118, 40
    c.ellipse(cx - rx, cy - ry, cx + rx, cy + ry, outline=mix(th.bg, th.muted, 0.55), width=1)
    theta = math.pi - 2 * math.pi * x.p
    ex, ey = cx + rx * math.cos(theta), cy + ry * math.sin(theta)
    er = 10 + 1.8 * math.sin(theta)

    def draw_sun():
        c.circle(cx, cy, 22, fill=mix(th.bg, th.accent, 0.3))
        c.circle(cx, cy, 16, fill=(255, 208, 80))

    def draw_planet():
        draw_earth(c, ex, ey, er, 23.5, math.degrees(math.atan2(cy - ey, cx - ex)))

    if math.sin(theta) < 0:
        draw_planet()
        draw_sun()
    else:
        draw_sun()
        draw_planet()
    for label, lx, ly in (("Jun", cx - rx - 16, cy), ("Dec", cx + rx + 16, cy),
                          ("Sep", cx, cy + ry + 12), ("Mar", cx, cy - ry - 10)):
        c.text(lx, ly, label, 10, th.muted, th.body)
    q = round(x.p * 4) % 4
    north = ("Summer", "Autumn", "Winter", "Spring")[q]
    south = ("Winter", "Spring", "Summer", "Autumn")[q]
    warm = {"Summer": th.accent, "Winter": th.accent2}
    c.text(80, 166, f"North: {north}", 12, warm.get(north, th.fg), th.face)
    c.text(240, 166, f"South: {south}", 12, warm.get(south, th.fg), th.face)


@painter
def seasons_hemis(c, x):
    th = x.th
    for r, a in ((52, 0.2), (44, 1.0)):
        c.circle(-14, 104, r, fill=mix(th.bg, (255, 208, 80), a))
    ex, ey, er = 222, 104, 44
    for k in range(-4, 5):
        y = ey + k * 10
        xe = ex - math.sqrt(max(0, er * er - (y - ey) ** 2))
        c.line([(36, y), (xe, y)], mix(th.bg, (255, 220, 120), 0.35), 1)
        dash = 36 + (x.T * 60 + k * 11) % max(1, xe - 44)
        c.line([(dash, y), (dash + 6, y)], (255, 226, 140), 1.5)
    phase = ease(seg(x.sp, 0.1, 0.6))
    tilt = -23.5 + 47 * phase
    north, south = draw_earth(c, ex, ey, er, tilt, 180, spin=x.T * 0.2, lat_lines=True)
    c.text(north[0], north[1] - 8, "N", 12, th.fg, th.face)
    c.text(south[0], south[1] + 9, "S", 12, th.fg, th.face)
    summer_north = tilt < 0
    c.text(314, 170, "June" if phase < 0.5 else "December", 13, th.muted, th.face, "rm")
    for label, y, is_summer in (("North", 46, summer_north), ("South", 150, not summer_north)):
        c.text(110, y, label, 12, th.fg, th.face)
        c.text(110, y + 15, "Summer" if is_summer else "Winter", 14,
               th.accent if is_summer else th.accent2, th.face)


# --------------------------------------------------------- photosynthesis ----

def leaf(c, bx, by, length, width, ang_deg, fill, vein):
    a = math.radians(ang_deg)
    ux, uy = math.cos(a), math.sin(a)
    px, py = -uy, ux
    left, right = [], []
    for i in range(15):
        s = i / 14
        half = width / 2 * math.sin(math.pi * s) ** 0.8
        cx, cy = bx + ux * length * s, by + uy * length * s
        left.append((cx + px * half, cy + py * half))
        right.append((cx - px * half, cy - py * half))
    c.poly(left + right[::-1], fill=fill)
    c.line([(bx, by), (bx + ux * length * 0.95, by + uy * length * 0.95)], vein, 1.2)


def plant(c, x, sway=0.0):
    c.rect(0, 152, c.w, c.h, fill=(122, 86, 54))
    c.line([(0, 152), (c.w, 152)], (96, 66, 40), 1.5)
    for dx, dy in ((-18, 20), (-6, 24), (8, 22), (20, 16)):
        c.line([(160, 152), (160 + dx * 0.5, 152 + dy * 0.6), (160 + dx, 152 + dy)], (226, 196, 150), 1.4)
    c.line([(160, 152), (160, 76)], (58, 128, 48), 4)
    leaf(c, 160, 96, 64, 28, -32 + sway, (72, 160, 60), (160, 214, 130))
    leaf(c, 160, 120, 50, 22, -150 - sway, (64, 148, 54), (150, 206, 120))
    leaf(c, 160, 78, 30, 14, -80, (86, 176, 70), (170, 222, 140))


@painter
def bg_leafy(c, x):
    c.gradient(x.th.bg, (196, 232, 172))


@painter
def photo_title_bg(c, x):
    sun(c, 36, 40, 16, x.T)
    leaf(c, 30, 172, 130, 60, -62, (120, 196, 96), (180, 230, 150))


@painter
def photo_inputs(c, x):
    th = x.th
    sun(c, 30, 44, 13, x.T)
    plant(c, x, 2 * math.sin(x.T * 1.5))
    k = ease(seg(x.sp, 0.0, 0.2))
    with c.faded(k):
        for j in range(3):
            a = (x.T * 0.28 + j / 3) % 1
            px, py = lerp_pt((10, 72 + j * 14), (188, 86), a)
            c.text(px, py, "CO₂", 11, mix((80, 84, 110), th.bg, abs(a - 0.5) * 1.6 - 0.2), th.face)
    k2 = ease(seg(x.sp, 0.45, 0.65))
    if k2 > 0:
        with c.faded(k2):
            for j in range(4):
                a = (x.T * 0.4 + j / 4) % 1
                px, py = along([(146, 170), (160, 152), (160, 100)], a)
                c.circle(px, py, 2.6, fill=(60, 130, 230))
            c.pill(250, 166, "water from roots", 10, WHITE, (70, 50, 30))
    with c.faded(ease(seg(x.sp, 0.1, 0.3))):
        c.pill(60, 128, "CO₂ from the air", 10, th.fg, WHITE)


@painter
def photo_chloro(c, x):
    th = x.th
    sun(c, 30, 40, 14, x.T)
    c.rect(146, 44, 304, 156, fill=(178, 222, 146), outline=(60, 128, 50), width=2, r=16)
    rnd = random.Random(6)
    for _ in range(9):
        px, py = rnd.uniform(168, 282), rnd.uniform(62, 138)
        c.ellipse(px - 11, py - 6, px + 11, py + 6, fill=(52, 146, 58), outline=(30, 100, 36), width=1)
    c.text(225, 150 - 4, "chloroplasts", 10, (30, 90, 30), th.face)
    rays = [((44, 52), (170, 84), (220, 60, 50), 0.05), ((44, 58), (176, 118), (50, 90, 225), 0.2)]
    for p0, p1, col, at in rays:
        k = ease(seg(x.sp, at, at + 0.25))
        if k > 0:
            c.arrow(*p0, *lerp_pt(p0, p1, k), col, 2.4, 7)
            if k >= 1:
                c.circle(*p1, 4 + 1.5 * math.sin(x.T * 8), fill=(255, 240, 160))
    kg = ease(seg(x.sp, 0.5, 0.75))
    if kg > 0:
        hit, eye = (148, 70), (70, 146)
        c.line([(44, 46), lerp_pt((44, 46), hit, min(1, kg * 2))], (40, 170, 60), 2.4)
        if kg > 0.5:
            c.arrow(*hit, *lerp_pt(hit, eye, (kg - 0.5) * 2), (40, 170, 60), 2.4, 7)
    with c.faded(ease(seg(x.sp, 0.7, 0.9))):
        c.ellipse(46, 140, 70, 154, fill=WHITE, outline=th.fg, width=1.2)
        c.circle(58, 147, 4, fill=(40, 120, 50))
        c.pill(60, 168, "green bounces off", 10, WHITE, (40, 140, 55))
        c.pill(225, 168, "red + blue absorbed", 10, WHITE, (60, 70, 120))


@painter
def photo_outputs(c, x):
    th = x.th
    sun(c, 30, 44, 13, x.T)
    plant(c, x, 2 * math.sin(x.T * 1.5))
    k = ease(seg(x.sp, 0.3, 0.5))
    with c.faded(k):
        for j in range(4):
            a = (x.T * 0.3 + j / 4) % 1
            px = 206 + a * 96
            py = 80 - a * 44 + 3 * math.sin(x.T * 3 + j)
            c.circle(px, py, 8, fill=(226, 240, 252), outline=(90, 150, 210), width=1.2)
            c.text(px, py, "O₂", 8, (40, 90, 150), th.face)
        c.pill(272, 104, "oxygen out", 10, WHITE, (70, 130, 200))
    k2 = ease(seg(x.sp, 0.1, 0.3))
    with c.faded(k2):
        for j in range(4):
            a = (x.T * 0.35 + j / 4) % 1
            px, py = along([(196, 80), (160, 100), (160, 150)], a)
            c.rect(px - 3, py - 3, px + 3, py + 3, fill=th.accent2, r=1)
        c.pill(92, 138, "sugar = food", 10, WHITE, (190, 120, 30))


@painter
def photo_equation(c, x):
    th = x.th
    with c.faded(ease(seg(x.t, 0.0, 0.4))):
        c.text(160, 48, "6CO₂ + 6H₂O", 20, th.fg, th.face)
        c.text(160, 67, "carbon dioxide + water", 11, th.muted, th.body)
    with c.faded(ease(seg(x.t, 0.4, 0.8))):
        c.arrow(160, 78, 160, 104, th.accent2, 2.4, 7)
        sun(c, 196, 91, 6, x.T)
        c.text(212, 91, "light", 11, th.accent2, th.face, "lm")
    with c.faded(ease(seg(x.t, 0.8, 1.2))):
        c.text(160, 122, "C₆H₁₂O₆ + 6O₂", 20, th.fg, th.face)
        c.text(160, 141, "sugar (glucose) + oxygen", 11, th.muted, th.body)
    with c.faded(ease(seg(x.sp, 0.3, 0.6))):
        c.text(160, 166, "made by plants and ocean algae", 11, th.accent, th.face)


# ---------------------------------------------------------- speed of light ----

@painter
def bg_violet(c, x):
    c.gradient(x.th.bg, (50, 16, 78))


@painter
def light_streaks(c, x):
    rnd = random.Random(13)
    for _ in range(7):
        y, speed, n = rnd.uniform(30, 170), rnd.uniform(240, 420), rnd.uniform(40, 90)
        off = rnd.uniform(0, 400)
        head = (x.T * speed + off) % (c.w + 2 * n) - n
        c.line([(head - n, y), (head, y)], mix(x.th.bg, x.th.accent, 0.45), 1.5)
        c.circle(head, y, 1.6, fill=x.th.accent)


@painter
def light_speed(c, x):
    th = x.th
    v = 299792 * ease(seg(x.sp, 0.0, 0.7))
    c.text(160, 74, f"{v:,.0f}", 32, th.accent, th.face)
    c.text(160, 102, "kilometres per second", 13, th.fg, th.body)
    c.text(160, 120, "(in a vacuum)", 10, th.muted, th.body)
    head = (x.T % 0.6) / 0.6 * (c.w + 120) - 60
    for k in range(10):
        c.line([(head - 6 * (k + 1), 150), (head - 6 * k, 150)], mix(th.bg, th.accent, 1 - k / 10), 2.5)
    c.circle(head, 150, 3, fill=WHITE)


@painter
def light_earth(c, x):
    th = x.th
    cx, cy, R = 160, 104, 46
    draw_earth(c, cx, cy, 32, 0, -40, spin=x.T * 0.1, night=0.4, axis=False)
    c.circle(cx, cy, R, outline=mix(th.bg, th.accent, 0.25), width=1)
    sim = seg(x.sp, 0.1, 0.9)
    laps = 7.5 * sim
    ang = -90 + 360 * laps
    for k in range(14, -1, -1):
        if laps * 360 < k * 7:
            continue
        a = math.radians(ang - k * 7)
        c.circle(cx + R * math.cos(a), cy + R * math.sin(a), 3 - k * 0.15,
                 fill=mix(th.accent, th.bg, k / 15))
    c.text(40, 76, "time", 11, th.muted, th.body)
    c.text(40, 94, f"{sim:.2f} s", 16, th.fg, th.face)
    c.text(280, 76, "laps", 11, th.muted, th.body)
    c.text(280, 94, f"{laps:.1f}", 16, th.accent, th.face)


@painter
def light_sun(c, x):
    th = x.th
    for r, a in ((34, 0.25), (26, 1.0)):
        c.circle(22, 104, r, fill=mix(th.bg, (255, 190, 70), a))
    draw_earth(c, 294, 104, 8, 0, 180, night=0.5, axis=False)
    prog = seg(x.sp, 0.1, 0.85)
    px = 50 + (284 - 50) * prog
    c.line([(50, 104), (284, 104)], mix(th.bg, th.muted, 0.35), 1)
    c.line([(50, 104), (px, 104)], th.accent, 2)
    c.circle(px, 104, 3.5, fill=WHITE)
    secs = 500 * prog
    c.text(166, 66, f"{int(secs // 60)} min {int(secs % 60):02d} s", 20, th.fg, th.face)
    c.text(166, 124, "150 million km", 11, th.muted, th.body)


@painter
def light_thunder(c, x):
    th = x.th
    period = 5.0
    ph = x.t % period
    flash = ph < 0.25
    if flash:
        c.rect(0, 0, c.w, c.h, fill=mix(th.bg, (120, 100, 160), 0.5))
    cloud(c, 70, 58, 1.1, (120, 116, 140))
    if flash:
        c.poly([(72, 70), (60, 104), (70, 104), (58, 146), (84, 98), (73, 98), (82, 70)],
               fill=(255, 240, 150))
        c.line([(70, 110), (268, 132)], th.accent, 1.5)
    ox, oy = 272, 150
    c.circle(ox, oy - 22, 5, outline=th.fg, width=1.5)
    c.line([(ox, oy - 17), (ox, oy)], th.fg, 1.5)
    c.line([(ox - 7, oy - 10), (ox + 7, oy - 10)], th.fg, 1.5)
    c.line([(ox, oy), (ox - 6, oy + 12)], th.fg, 1.5)
    c.line([(ox, oy), (ox + 6, oy + 12)], th.fg, 1.5)
    dist = math.dist((70, 140), (ox, oy - 22))
    radius = ph * 48
    for k in range(3):
        r = radius - k * 7
        if 4 < r < dist + 10:
            c.arc(70, 140, r, -60, 30, mix(th.bg, th.accent2, 1 - r / (dist + 20)), 1.5)
    if ph < 1.5:
        c.text(ox - 6, oy - 42, "see it!", 11, th.accent, th.face)
    if dist / 48 <= ph < dist / 48 + 0.9:
        c.text(ox - 6, oy - 42, "hear it!", 11, th.accent2, th.face)
    with c.faded(ease(seg(x.sp, 0.3, 0.55))):
        c.text(236, 50, "light ~ 900,000x", 13, th.accent, th.face)
        c.text(236, 66, "faster than sound", 11, th.fg, th.body)
    with c.faded(ease(seg(x.sp, 0.6, 0.8))):
        c.text(160, 172, "sound: about 3 seconds per kilometre", 10, th.muted, th.body)


# ----------------------------------------------------------------- topics ----

def intro(title_text, sub, say, **args):
    return Scene("title", say, args={"title": title_text, "sub": sub, **args})


TOPICS = [
    Topic("how_qr_codes_work", 140, Theme(
        bg=WHITE, fg=(20, 24, 28), muted=(100, 110, 120), accent=(0, 150, 136),
        accent2=(255, 140, 0), panel=(226, 236, 234), backdrop="bg_qr",
        caption_band=(0, 150, 136), caption_fg=WHITE), [
        intro("How QR codes work", "A picture made of bits", "How does a QR code store information?",
          backdrop="qr_title_bg", cx=222, width=180),
        Scene("qr_bits", "It's a grid of tiny squares. Each dark square is a one, "
              "and each light square is a zero.", "Every square is one bit"),
        Scene("qr_finders", "The three big corner squares show the camera where the code is, "
              "and which way up it is.", "Three corner 'eyes'"),
        Scene("qr_damage", "Extra repair data lets it be read, even when up to thirty percent "
              "is damaged.", "Built-in error correction"),
        Scene("qr_stream", "This app sends files as a stream of these codes, flashing on the screen.",
              "Flashing codes = a file"),
    ], voice=ZIRA, chord=(293.66, 369.99, 440.0)),

    Topic("how_sound_travels", 150, Theme(
        bg=(11, 21, 48), fg=(235, 240, 255), muted=(130, 145, 185), accent=(255, 138, 61),
        accent2=(90, 200, 255), panel=(22, 36, 72), backdrop="bg_sound"), [
        intro("How sound travels", "Waves of squeezed air", "How does sound travel?",
          backdrop="sound_title_bg", y=0.42),
        Scene("sound_wave", "A vibrating object squeezes and stretches the air. "
              "That moving pattern is a sound wave.", "Vibrations squeeze the air"),
        Scene("sound_jiggle", "The air doesn't travel with it. Each molecule just jiggles, "
              "and passes the push along.", "Air jiggles, the wave travels"),
        Scene("sound_speeds", "In air, sound covers about three hundred and forty metres a second. "
              "Water is four times faster, steel seventeen.",
              "Speed depends on the material"),
        Scene("sound_space", "Space has no air to push, so there is no sound at all.",
              "No air, no sound"),
    ], voice=ZIRA, chord=(220.0, 277.18, 329.63)),

    Topic("binary_numbers", 130, Theme(
        bg=(4, 10, 6), fg=(150, 255, 180), muted=(60, 150, 95), accent=(57, 255, 136),
        accent2=(200, 255, 220), panel=(10, 30, 16), face="mono", body="mono",
        caption_prompt=True), [
        intro("Binary numbers", "How computers count with 0 and 1",
          "Computers count using only two digits: zero and one.", backdrop="bin_rain", size=28,
          panel=True, width=250),
        Scene("bin_places", "Each place is worth double the one before: one, two, four, eight, "
              "and so on.", "each place doubles"),
        Scene("bin_count", "To make five, switch on the four and the one: one, zero, one.",
              "5 = 101"),
        Scene("bin_byte", "Eight bits make a byte, holding any number from zero to two hundred "
              "and fifty five.", "8 bits = 1 byte"),
        Scene("bin_letter", "The letter A is stored as sixty five. Every file is just bits like these.",
              "text is numbers too"),
    ], voice=ZIRA, chord=(246.94, 311.13, 369.99)),

    Topic("morse_code", 130, Theme(
        bg=(243, 233, 210), fg=(59, 42, 26), muted=(140, 115, 90), accent=(179, 38, 30),
        accent2=(220, 160, 40), panel=(232, 219, 190), face="serif", body="serif",
        backdrop="bg_paper", caption_y=19), [
        intro("Morse code", "Invented in the 1830s-40s by Samuel Morse and Alfred Vail",
          "Morse code turns letters into short and long signals.", backdrop="morse_title_bg",
          size=30, y=0.44),
        Scene("morse_units", "A dot is short. A dash lasts three times as long.",
              "Dot = 1 unit, dash = 3 units", morse=". -"),
        Scene("morse_letter", "The most common letter, E, is just a single dot.",
              "E is a single dot", morse="."),
        Scene("morse_sos", "The distress signal S O S is three dots, three dashes, three dots.",
              "SOS: the distress call", morse="... --- ..."),
        Scene("morse_media", "It can be sent with sound, light or radio, just like this app.",
              "Send it with anything"),
    ], voice=ZIRA, chord=(196.0, 246.94, 293.66)),

    Topic("the_water_cycle", 160, Theme(
        bg=(222, 241, 252), fg=(15, 40, 80), muted=(70, 100, 140), accent=(38, 108, 190),
        accent2=(255, 214, 60), panel=WHITE, backdrop="bg_water",
        caption_band=WHITE, caption_fg=(15, 40, 80)), [
        intro("The water cycle", "Earth's endless water loop",
          "Earth's water moves in an endless loop, called the water cycle.",
          panel=True, size=24, y=0.4, width=180),
        Scene("water_evap", "The sun heats oceans and lakes, turning water into invisible vapour "
              "that rises into the sky.", "1. Evaporation"),
        Scene("water_cond", "Higher up the air is cooler, so the vapour condenses into tiny "
              "droplets that form clouds.", "2. Condensation"),
        Scene("water_rain", "When the droplets grow heavy, they fall as rain or snow.",
              "3. Precipitation"),
        Scene("water_collect", "Rivers carry the water back to the sea, and the cycle starts again.",
              "4. Collection"),
    ], size=(240, 240), voice=ZIRA, chord=(329.63, 415.30, 493.88)),

    Topic("why_we_have_seasons", 140, Theme(
        bg=(6, 8, 20), fg=(240, 240, 250), muted=(140, 150, 185), accent=(255, 176, 60),
        accent2=(100, 175, 255), panel=(20, 26, 50), face="wide", body="wide",
        backdrop="bg_space"), [
        intro("Why we have seasons", "It's all about the tilt", "Why do we have seasons?",
          backdrop="seasons_title_bg", cx=140, width=230),
        Scene("seasons_distance", "It's not because Earth gets closer to the Sun. We're actually "
              "closest in early January.", "Not about distance!"),
        Scene("seasons_tilt", "Earth's axis is tilted by about twenty three and a half degrees.",
              "Earth's axis is tilted"),
        Scene("seasons_orbit", "The half tilted towards the Sun gets more direct sunlight and "
              "longer days. That's summer.", "Tilted toward the Sun = summer"),
        Scene("seasons_hemis", "Six months later that half tilts away and has winter, so the north "
              "and south have opposite seasons.", "Opposite halves, opposite seasons"),
    ], voice=ZIRA, chord=(174.61, 220.0, 261.63)),

    Topic("photosynthesis", 140, Theme(
        bg=(232, 246, 222), fg=(30, 70, 30), muted=(80, 120, 70), accent=(50, 140, 45),
        accent2=(230, 150, 40), panel=WHITE, backdrop="bg_leafy",
        caption_band=(58, 128, 48), caption_fg=WHITE), [
        intro("Photosynthesis", "How plants make food from light",
          "How do plants make their own food? Photosynthesis.", backdrop="photo_title_bg",
          cx=214, width=180, size=24),
        Scene("photo_inputs", "Leaves take in carbon dioxide from the air, and roots draw up water.",
              "Carbon dioxide + water in"),
        Scene("photo_chloro", "Green chlorophyll captures energy from sunlight. It absorbs red and "
              "blue light, and reflects green.", "Chlorophyll catches light"),
        Scene("photo_outputs", "That energy turns carbon dioxide and water into sugar, and "
              "releases oxygen.", "Sugar made, oxygen out"),
        Scene("photo_equation", "The oxygen we breathe comes from photosynthesis, by plants and "
              "tiny ocean algae.", "The recipe"),
    ], voice=ZIRA, chord=(261.63, 329.63, 440.0)),

    Topic("speed_of_light", 80, Theme(
        bg=(22, 8, 40), fg=(255, 245, 225), muted=(170, 140, 205), accent=(255, 224, 102),
        accent2=(255, 110, 180), panel=(40, 16, 70), face="arial", body="ui",
        backdrop="bg_violet"), [
        intro("The speed of light", "The universe's speed limit",
          "Nothing in the universe travels faster than light.", backdrop="light_streaks"),
        Scene("light_speed", "It covers about three hundred thousand kilometres every second.",
              "299,792 km every second"),
        Scene("light_earth", "That's fast enough to circle the Earth seven and a half times "
              "in one second.", "7.5 laps of Earth in 1 second"),
        Scene("light_sun", "Sunlight takes about eight minutes and twenty seconds to reach us.",
              "Sun to Earth: about 8 min 20 s"),
        Scene("light_thunder", "Light is nearly a million times faster than sound, which is why "
              "you see lightning before you hear thunder.", "Why lightning comes first"),
    ], voice=ZIRA, chord=(233.08, 293.66, 349.23), webm=True, audio_kbps=10),
]


# ------------------------------------------------------------------ audio ----

TTS_PS = r"""
Add-Type -AssemblyName System.Speech
$items = Get-Content -Raw -Encoding UTF8 $args[0] | ConvertFrom-Json
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000,
    [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
    [System.Speech.AudioFormat.AudioChannel]::Mono)
foreach ($it in $items) {
    $s.SelectVoice($it.voice)
    $s.Rate = $it.rate
    $s.SetOutputToWaveFile($it.path, $fmt)
    $s.Speak($it.text)
}
$s.SetOutputToNull()
$s.Dispose()
"""


def speak(topic, tmp):
    """One trimmed 16 kHz mono float track per scene, via Windows TTS."""
    items = [{"text": s.say, "path": str(tmp / f"say{i}.wav"), "voice": topic.voice,
              "rate": topic.rate} for i, s in enumerate(topic.scenes)]
    (tmp / "tts.json").write_text(json.dumps(items), encoding="utf-8")
    (tmp / "tts.ps1").write_text(TTS_PS, encoding="utf-8")
    subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                    str(tmp / "tts.ps1"), str(tmp / "tts.json")], check=True)
    tracks = []
    for it in items:
        with wave.open(it["path"], "rb") as w:
            assert (w.getframerate(), w.getnchannels(), w.getsampwidth()) == (RATE, 1, 2)
            pcm = array.array("h", w.readframes(w.getnframes()))
        loud = [i for i, v in enumerate(pcm) if abs(v) > 500]
        lo = max(0, loud[0] - int(0.04 * RATE))
        hi = min(len(pcm), loud[-1] + int(0.08 * RATE))
        tracks.append([v / 32768 for v in pcm[lo:hi]])
    return tracks


def tone(freq, dur, amp, decay=0.0):
    n = int(dur * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / 0.006, (dur - t) / 0.006)
        if decay:
            env *= math.exp(-t * decay)
        out.append(amp * env * math.sin(2 * math.pi * freq * t))
    return out


def add_into(buf, samples, start):
    end = start + len(samples)
    if end > len(buf):
        buf.extend([0.0] * (end - len(buf)))
    for i, v in enumerate(samples):
        buf[start + i] += v


def build_audio(topic, tmp):
    """Lay out narration + beeps, time every scene to it, add chimes and pad."""
    speech = speak(topic, tmp)
    peak = max(max(abs(v) for v in tr) for tr in speech)
    gain = 0.8 / peak
    buf = []
    for i, (scene, track) in enumerate(zip(topic.scenes, speech)):
        start = len(buf)
        buf.extend([0.0] * int((0.8 if i == 0 else 0.25) * RATE))
        scene.speech_start = (len(buf) - start) / RATE
        buf.extend(v * gain for v in track)
        scene.speech_end = (len(buf) - start) / RATE
        if scene.morse:
            buf.extend([0.0] * int(0.35 * RATE))
            events, length = morse_events(scene.morse)
            at = (len(buf) - start) / RATE
            scene.beeps = [(at + b0, at + b1) for b0, b1 in events]
            beeps = [0.0] * int(length * RATE + 1)
            for b0, b1 in events:
                add_into(beeps, tone(660, b1 - b0, 0.4), int(b0 * RATE))
            buf.extend(beeps)
        buf.extend([0.0] * int((1.3 if i == len(topic.scenes) - 1 else 0.45) * RATE))
        scene.dur = (len(buf) - start) / RATE
    total = len(buf) / RATE
    notes = list(topic.chord) + [topic.chord[0] * 2]
    for j, f in enumerate(notes):
        add_into(buf, tone(f, 0.7, 0.16, 6), int(j * 0.11 * RATE))
    outro = int((total - 1.1) * RATE)
    for j, f in enumerate(reversed(notes)):
        add_into(buf, tone(f, 0.6, 0.12, 6), outro + int(j * 0.1 * RATE))
    buf = buf[:int(total * RATE)]
    w = [2 * math.pi * f for f in topic.chord]
    for i in range(len(buf)):
        t = i / RATE
        env = min(1.0, t / 1.5, (total - t) / 1.5) * (0.8 + 0.2 * math.sin(0.9 * t))
        buf[i] += 0.012 * env * (math.sin(w[0] * t) + math.sin(w[1] * t) + math.sin(w[2] * t))
    pcm = array.array("h", (round(clamp(v, -0.98, 0.98) * 32767) for v in buf))
    path = tmp / "narration.wav"
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())
    return path, total


# ------------------------------------------------------------------ video ----

def render_frames(topic, tmp, total):
    scenes = topic.scenes
    starts = [0.0]
    for s in scenes[:-1]:
        starts.append(starts[-1] + s.dur)
    idx, last, fade_from = 0, None, None
    frames = math.ceil(total * FPS)
    for n in range(frames):
        now = n / FPS
        k = idx
        while k + 1 < len(scenes) and now >= starts[k + 1]:
            k += 1
        if k != idx:
            idx, fade_from = k, last
        ctx = Ctx(topic, scenes[idx], now - starts[idx], now)
        c = Canvas(topic.size, topic.theme.bg)
        PAINTERS[topic.theme.backdrop](c, ctx)
        PAINTERS[ctx.scene.paint](c, ctx)
        draw_caption(c, ctx)
        im = c.frame()
        if fade_from is not None and ctx.t < 0.3:
            im = Image.blend(fade_from, im, ctx.t / 0.3)
        last = im
        im.save(tmp / f"f{n:04d}.png", compress_level=1)
    return frames


def make_topic(topic):
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        wav, total = build_audio(topic, tmp)
        frames = render_frames(topic, tmp, total)
        print(f"{topic.name}: {total:.1f} s, {frames} frames, "
              + ", ".join(f"{s.dur:.1f}" for s in topic.scenes))
        inputs = ["-framerate", str(FPS), "-i", str(tmp / "f%04d.png"), "-i", str(wav)]
        graph = "[0:v]scale=out_range=tv,format=yuv420p[v];[1:a]anull[a]"
        encode(topic.name, inputs, graph, round(total, 2), topic.budget_kb, topic.audio_kbps,
               webm=topic.webm, speech=True, tune="animation")


def make_explainers(stems=None):
    for topic in TOPICS:
        if not stems or topic.stem in stems:
            make_topic(topic)


if __name__ == "__main__":
    make_explainers(sys.argv[1:])
