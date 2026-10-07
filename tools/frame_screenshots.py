#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Frame raw screenshots into App Store listing images.

    python3 tools/frame_screenshots.py                        # tools/appstore/shots.json
    python3 tools/frame_screenshots.py --spec other.json --out /tmp/framed
    python3 tools/frame_screenshots.py --only 03              # one shot, by id prefix

A brand-color canvas, one caption line across the top, and the whole screen in
a drawn device frame beneath it, lifted by a soft shadow — the layout Procreate
uses. Every shot shows the entire app, top to bottom.

The other common layout, where the device runs off the edge opposite the
caption, was tried first and dropped (2026-10-06): alternating it crops the
top of every other screenshot, and on this board the top is the sentence tray —
half of what the app is.

WHY THE SIZES ARE FIXED
-----------------------
App Store Connect accepts a short list of pixel sizes per display class and
rejects anything else at upload. The output is always one of them, whatever the
source:

    iPad 13"     2752 x 2064   landscape — the board's designed orientation
    iPhone 6.9"  1320 x 2868   portrait

The Mac listing of a Designed-for-iPad app reuses the iPad set.

WHY THE FRAME IS DRAWN
----------------------
Apple publishes product bezels, but they sit behind a download page, change
with every hardware generation, and would be a second binary asset to keep in
step. A rounded, dark border reads as "a device" at listing size, and nobody
evaluates a listing by its bezel.

WHY INTER
---------
It is the site's typeface, so the listing and blasterai.app look like one
product. It is OFL-licensed and vendored in `tools/appstore/fonts/` with its
licence, so a render a year from now uses the same glyphs. SF Pro is licensed
for UI mockups, which a marketing image is arguably not.

THE SPEC
--------
`tools/appstore/shots.json`, in listing order:

    {"background": "#0f172a", "text": "#ffffff", "accent": "#2dd4bf",
     "shots": [{"id": "01-board", "device": "ipad",
                "src": "build/shots/raw/ipad/01-board.png",
                "caption": "Words stay *where they're learned*."}]}

An optional `"subtitle"` adds a second, lighter line under the caption — the
headline makes the claim, the subtitle says what is behind it. When any shot
has one, every shot moves its device down to the subtitle layout, so the set
lines up.

A `*word*` in a caption renders in the accent color. Keep a caption to one
line; a long one shrinks to fit rather than wrapping. Sources may be any size;
each is scaled to fit its frame.

MANUAL CAPTURES
---------------
Screens a script cannot reach are captured by hand with Simulator's Device →
Trigger Screenshot, which saves into the simulator's own photo library:

    ~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Media/DCIM/100APPLE/

Those carry the status bar; the app's scripted captures do not. Mark such a
shot `"status_bar": "strip"` and the band is painted out with the screen's own
background, sampled just below it, so a hand capture and a scripted one match.
"""

import argparse
import json
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
except ImportError:
    sys.exit("pip install pillow")

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "tools/appstore/fonts/Inter-ExtraBold.ttf"
SUB_FONT = ROOT / "tools/appstore/fonts/Inter-Medium.ttf"
DEFAULT_SPEC = ROOT / "tools/appstore/shots.json"
DEFAULT_OUT = ROOT / "build/shots/framed"

# Canvas, and where things sit in it, as fractions so a change of canvas size
# keeps the proportions. Measured off Procreate's listing: caption centred at
# about 8.5% of the height, device top at 15.5%, a bottom margin of about 6%,
# device at most 77% of the width. `border` and `radius` are fractions of the
# screen width, so both devices read the same at any size. `type` is the
# caption's font size as a fraction of canvas height.
DEVICES = {
    "ipad":   {"canvas": (2752, 2064), "caption_y": 0.085, "device_top": 0.155,
               "bottom": 0.06, "max_w": 0.77, "border": 0.030, "radius": 0.030,
               "type": 0.054},
    "iphone": {"canvas": (1320, 2868), "caption_y": 0.065, "device_top": 0.12,
               "bottom": 0.045, "max_w": 0.84, "border": 0.045, "radius": 0.13,
               "type": 0.036},
}

# With subtitles: the headline rises, the subtitle sits under it, and the
# device starts lower. Applied to EVERY shot in a spec that has any subtitle,
# so the devices line up when the listing scrolls sideways.
WITH_SUBTITLE = {
    "ipad":   {"caption_y": 0.062, "subtitle_y": 0.118, "device_top": 0.168, "sub_type": 0.028},
    # Laid out for a two-line headline and a two-line subtitle, which is what
    # fits a 1320-wide canvas at a readable size.
    "iphone": {"caption_y": 0.048, "subtitle_y": 0.132, "device_top": 0.188, "sub_type": 0.019,
               "type": 0.038},
}

BEZEL = (28, 28, 30)          # near-black, the color of a real bezel
BEZEL_EDGE = (72, 72, 76)     # a hairline so the frame separates from navy


def hex_rgb(s: str) -> tuple[int, int, int]:
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def runs(line: str) -> list[tuple[str, bool]]:
    """Split `a *b* c` into [(a, False), (b, True), (c, False)]."""
    parts = line.split("*")
    return [(p, i % 2 == 1) for i, p in enumerate(parts) if p]


def line_width(draw: ImageDraw.ImageDraw, line: str, font) -> int:
    return int(draw.textlength(line.replace("*", ""), font=font))


def fit_font(draw, lines: list[str], max_w: int, size: int, path: Path = FONT):
    """The largest size up to `size` at which every line fits `max_w`."""
    while size > 20:
        font = ImageFont.truetype(str(path), size)
        if all(line_width(draw, l, font) <= max_w for l in lines):
            return font
        size -= 4
    return ImageFont.truetype(str(path), size)


def draw_caption(canvas: Image.Image, caption: str, center_y: int,
                 type_px: int, text_rgb, accent_rgb, path: Path = FONT) -> None:
    """Centred lines, the first centred on `center_y` by its cap height.

    Centring the text box puts the descender space below the words and the
    line visibly high; centring on the capitals is what the eye measures.
    A `\\n` breaks the line — a phone canvas is too narrow for most captions
    on one line, and shrinking them to fit makes them unreadable at listing
    size. Every line is set at the size that fits the widest.
    """
    draw = ImageDraw.Draw(canvas)
    cw = canvas.width
    lines = caption.split("\n")
    font = fit_font(draw, lines, int(cw * 0.90), type_px, path)
    cap_top, cap_bottom = font.getbbox("H")[1], font.getbbox("H")[3]
    leading = int(font.size * 1.18)
    for n, line in enumerate(lines):
        y = center_y + n * leading - (cap_top + cap_bottom) // 2
        x = (cw - line_width(draw, line, font)) // 2
        for text, accented in runs(line):
            draw.text((x, y), text, font=font, fill=accent_rgb if accented else text_rgb)
            x += int(draw.textlength(text, font=font))


def strip_status_bar(im: Image.Image) -> Image.Image:
    """Paint out the status bar of a hardware-style screenshot.

    The band is a fraction of the height so it holds on any device of a kind,
    and stays above the app's first row of content. The fill is sampled from the left edge just below the band,
    which is the screen background in every view this app has.
    """
    # A phone's status bar sits beside the Dynamic Island and is deeper: about
    # 6% of a portrait iPhone's height, against 3.6% of a landscape iPad's.
    band = int(im.height * (0.06 if im.height > im.width * 1.6 else 0.036))
    fill = im.getpixel((2, band + 2))
    im = im.copy()
    ImageDraw.Draw(im).rectangle([0, 0, im.width, band], fill=fill)
    return im


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius, fill=255)
    return mask


def render(shot: dict, style: dict, out_dir: Path) -> Path:
    dev = dict(DEVICES[shot["device"]])
    if any("subtitle" in s for s in style["shots"]):
        dev.update(WITH_SUBTITLE[shot["device"]])
    cw, ch = dev["canvas"]
    bg = hex_rgb(style.get("background", "#0f172a"))
    canvas = Image.new("RGB", (cw, ch), bg)

    src = Image.open(ROOT / shot["src"]).convert("RGB")
    if shot.get("status_bar") == "strip":
        src = strip_status_bar(src)

    # The largest frame that fits both the width cap and the space between the
    # caption and the bottom margin. Solved for the screen, since the border
    # scales with it: frame = screen * (1 + 2 * border).
    grow = 1 + 2 * dev["border"]
    avail_w = cw * dev["max_w"]
    avail_h = ch * (1 - dev["device_top"] - dev["bottom"])
    screen_w = int(min(avail_w / grow, avail_h / grow * src.width / src.height))
    screen_h = int(src.height * screen_w / src.width)
    screen = src.resize((screen_w, screen_h), Image.LANCZOS)

    border = int(screen_w * dev["border"])
    radius = int(screen_w * dev["radius"])
    frame_w, frame_h = screen_w + 2 * border, screen_h + 2 * border
    fx = (cw - frame_w) // 2
    fy = int(ch * dev["device_top"])

    # A soft shadow, offset downward: the device sits on the page rather than
    # being cut out of it. Drawn on its own layer and blurred.
    shadow = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    blur = max(8, frame_w // 40)
    ImageDraw.Draw(shadow).rounded_rectangle(
        [fx, fy + blur, fx + frame_w, fy + frame_h + blur], radius + border, fill=(0, 0, 0, 150))
    canvas.paste(shadow.filter(ImageFilter.GaussianBlur(blur)), (0, 0),
                 shadow.filter(ImageFilter.GaussianBlur(blur)))

    frame = Image.new("RGBA", (frame_w, frame_h), (0, 0, 0, 0))
    fd = ImageDraw.Draw(frame)
    fd.rounded_rectangle([0, 0, frame_w - 1, frame_h - 1], radius + border,
                         fill=BEZEL, outline=BEZEL_EDGE, width=max(2, border // 10))
    frame.paste(screen, (border, border), rounded_mask(screen.size, radius))
    canvas.paste(frame, (fx, fy), frame)

    draw_caption(canvas, shot["caption"], int(ch * dev["caption_y"]), int(ch * dev["type"]),
                 hex_rgb(style.get("text", "#ffffff")),
                 hex_rgb(style.get("accent", "#2dd4bf")))
    if shot.get("subtitle"):
        sub_rgb = hex_rgb(style.get("subtitle", "#cbd5e1"))
        draw_caption(canvas, shot["subtitle"], int(ch * dev["subtitle_y"]),
                     int(ch * dev["sub_type"]), sub_rgb, sub_rgb, SUB_FONT)

    out = out_dir / shot["device"] / f"{shot['id']}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out, optimize=True)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Frame screenshots for App Store Connect.")
    ap.add_argument("--spec", type=Path, default=DEFAULT_SPEC)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--only", help="render only shots whose id starts with this")
    args = ap.parse_args()

    spec = json.loads(args.spec.read_text())
    missing = []
    for shot in spec["shots"]:
        if args.only and not shot["id"].startswith(args.only):
            continue
        if not (ROOT / shot["src"]).exists():
            missing.append(f"{shot['device']}/{shot['id']}: {shot['src']}")
            continue
        out = render(shot, spec, args.out)
        with Image.open(out) as im:
            print(f"  {out.relative_to(ROOT) if out.is_relative_to(ROOT) else out}  {im.size[0]}x{im.size[1]}")
    if missing:
        # Not found is reported as not found — never as a blank frame, which
        # would upload as a perfectly valid, perfectly empty listing image.
        print("\nno source yet for:\n  " + "\n  ".join(missing))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
