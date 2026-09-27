"""Build the tiny demo photos and videos bundled under assets/samples/.

Requires: pip install pillow imageio-ffmpeg (videos also need Windows TTS voices)
Run from the project root:  python tool/make_sample_media.py [photo_dir]

Photos are re-encoded as baseline JPEG to hit exact byte budgets (skipped when
photo_dir is missing). Videos are the narrated explainers from
make_explainer_videos.py plus a beeping sync-test clip, all encoded two-pass by
encode() so each lands just under its budget (H.264 + AAC in MP4 for every
phone, VP9 + Opus in WebM for the smallest file that still has sound).
"""
import io
import subprocess
import sys
import tempfile
from pathlib import Path

import imageio_ffmpeg
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parent.parent
OUT_IMG = ROOT / "assets" / "samples" / "images"
OUT_VID = ROOT / "assets" / "samples" / "videos"
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()

PHOTOS = {
    "robot_lab": "1.png",
    "cat_sketch": "5823579daf96d806b45228802e5ff0af.jpg",
    "future_city": "Image.png",
    "night_sky": "romantic-night-sky-3840x2160-25549.jpg",
}
IMAGE_TIERS_KB = [2, 5, 10, 20]

BEEPS = "0.35*sin(2*PI*880*t)*min(1,mod(t,1)*200)*max(0,1-mod(t,1)*8)"


# ---------------------------------------------------------------- photos ----

def load_photo(path: Path) -> Image.Image:
    im = ImageOps.exif_transpose(Image.open(path))
    if im.mode in ("RGBA", "LA", "P") or "transparency" in im.info:
        im = im.convert("RGBA")
        bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
        im = Image.alpha_composite(bg, im)
    return im.convert("RGB")


def jpeg(im: Image.Image, q: int) -> bytes:
    buf = io.BytesIO()
    im.save(buf, format="JPEG", quality=q, optimize=True, progressive=False,
            subsampling=2)
    return buf.getvalue()


def fit_jpeg(base: Image.Image, limit: int, q_floor: int = 45):
    """Largest size (from 640 px long side down) whose best quality >= q_floor."""
    scale = min(1.0, 640 / max(base.size))
    fallback = None
    while min(base.size) * scale >= 16:
        im = base.resize((round(base.width * scale), round(base.height * scale)),
                         Image.LANCZOS)
        lo, hi, best = 5, 92, None
        while lo <= hi:
            mid = (lo + hi) // 2
            data = jpeg(im, mid)
            if len(data) <= limit:
                best, lo = (mid, data, im.size), mid + 1
            else:
                hi = mid - 1
        if best and best[0] >= q_floor:
            return best
        fallback = fallback or best
        scale *= 0.92
    return fallback


def make_images(src_dir: Path):
    OUT_IMG.mkdir(parents=True, exist_ok=True)
    for name, file in PHOTOS.items():
        base = load_photo(src_dir / file)
        for kb in IMAGE_TIERS_KB:
            q, data, (w, h) = fit_jpeg(base, kb * 1024)
            out = OUT_IMG / f"{name}_{kb}kb.jpg"
            out.write_bytes(data)
            print(f"{out.name:28} {len(data):6d} B  {w}x{h}  q{q}")


# ---------------------------------------------------------------- videos ----

def run(args):
    subprocess.run([FFMPEG, "-hide_banner", "-loglevel", "error", "-y", *args],
                   check=True)


def encode(name, inputs, graph, duration, target_kb, audio_kbps, webm=False,
           speech=False, tune=None):
    """Two-pass encode of [v]/[a] from `graph`, shrinking until it fits.

    `speech` tunes the audio codec for narration (Opus voip mode; 16 kHz AAC
    cut at 6 kHz, which keeps low-bitrate AAC speech far more intelligible);
    `tune` is an optional x264 tune such as "animation". Returns the size.
    """
    out = OUT_VID / f"{name}.{'webm' if webm else 'mp4'}"
    budget = target_kb * 1024
    total_kbps = budget * 8 / 1000 / duration * 0.96
    video_kbps = total_kbps - audio_kbps - (1 if webm else 3)
    with tempfile.TemporaryDirectory() as tmp:
        log = str(Path(tmp) / "pass")
        for _ in range(8):
            if webm:
                vcodec = ["-c:v", "libvpx-vp9", "-b:v", f"{video_kbps:.0f}k",
                          "-deadline", "good", "-cpu-used", "1", "-row-mt", "1",
                          "-g", "120"]
                acodec = ["-c:a", "libopus", "-b:a", f"{audio_kbps}k",
                          "-ac", "1", "-application", "voip" if speech else "audio"]
                fmt = "webm"
            else:
                vcodec = ["-c:v", "libx264", "-preset", "veryslow",
                          "-profile:v", "main", "-b:v", f"{video_kbps:.0f}k",
                          *(["-tune", tune] if tune else []),
                          "-pix_fmt", "yuv420p", "-color_range", "tv", "-g", "120"]
                acodec = ["-c:a", "aac", "-b:a", f"{audio_kbps}k", "-ac", "1",
                          *(["-ar", "16000", "-cutoff", "6000"] if speech else ["-ar", "22050"])]
                fmt = "mp4"
            common = [*inputs, "-filter_complex", graph, "-map", "[v]",
                      "-map", "[a]", "-t", f"{duration}", *vcodec, *acodec,
                      "-passlogfile", log]
            run([*common, "-pass", "1", "-f", "null", "NUL"])
            run([*common, "-pass", "2", "-f", fmt,
                 *([] if webm else ["-movflags", "+faststart"]),
                 "-map_metadata", "-1", str(out)])
            size = out.stat().st_size
            if size <= budget:
                break
            video_kbps *= budget / size * 0.97
    print(f"{out.name:32} {size:7d} B  ({size / 1024:.1f} KB, video {video_kbps:.0f}k)")
    return size


def make_sync_clip():
    """testsrc countdown with a beep every second, for checking A/V sync."""
    OUT_VID.mkdir(parents=True, exist_ok=True)
    fps, test_len = 12, 5.0
    test_inputs = ["-f", "lavfi", "-i", f"testsrc=s=192x108:r={fps}:d={test_len}",
                   "-f", "lavfi", "-i", f"aevalsrc='{BEEPS}':s=22050:d={test_len}"]
    encode("countdown_beeps_30kb", test_inputs,
           "[0:v]format=yuv420p[v];[1:a]anull[a]", test_len, 30, 16)


def main():
    from make_explainer_videos import make_explainers

    src = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / "Desktop" / "photdssss"
    if src.is_dir():
        make_images(src)
    else:
        print(f"photo dir {src} not found, keeping existing photos")
    make_explainers()
    make_sync_clip()


if __name__ == "__main__":
    main()
