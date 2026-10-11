#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Deterministic renderer for the Playful 3D color tile set.

Renders a matte Lambertian sphere on a warm cream background, matching the
existing p3d_red / p3d_pink aesthetic. One PNG per color, perfect consistency
across the set.

Usage:
    python3 tools/render_color_spheres.py                 # render all colors
    python3 tools/render_color_spheres.py --key red       # render one
    python3 tools/render_color_spheres.py --out DIR       # override output dir
"""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W = 1024
# Playful 3D moved to a pure white canvas with the gpt-image-2 re-shoot (2026-10).
BG = (255, 255, 255)
SPHERE_R = 330
CENTER = (W // 2, W // 2 - 10)
LIGHT = np.array([0.45, -0.55, 0.70])  # upper-right key light
LIGHT /= np.linalg.norm(LIGHT)
AMBIENT = 0.58

# Calibrated to match p3d_red and p3d_pink targets; other colors chosen for
# even perceptual spacing and strong chroma at matte mid-tones.
COLORS = {
    "red":     (222,  72,  64),
    "orange_": (238, 138,  54),
    "yellow":  (240, 205,  70),
    "green":   (110, 180,  95),
    "blue":    ( 90, 140, 215),
    "purple":  (160, 108, 200),
    "pink":    (240, 150, 170),
    "black":   ( 58,  58,  64),
    "brown":   (140,  95,  70),
    "white":   (252, 250, 245),
    "grey":    (175, 175, 180),
    "gold":    (220, 180,  75),
    "silver":  (205, 205, 210),
    "tan":     (215, 185, 150),
}


def render_sphere(color_rgb: tuple[int, int, int]) -> Image.Image:
    cx, cy = CENTER
    yy, xx = np.mgrid[0:W, 0:W].astype(np.float32)
    dx = (xx - cx) / SPHERE_R
    dy = (yy - cy) / SPHERE_R
    r2 = dx * dx + dy * dy
    mask = r2 <= 1.0
    dz = np.sqrt(np.clip(1.0 - r2, 0.0, 1.0))

    # Lambertian term (light points FROM surface TOWARD light source)
    ndotl = dx * LIGHT[0] + dy * LIGHT[1] + dz * LIGHT[2]
    ndotl = np.clip(ndotl, 0.0, 1.0)
    intensity = AMBIENT + (1.0 - AMBIENT) * ndotl
    intensity = np.power(intensity, 0.92)  # gentle matte curve

    # Warm rim on the shadow side — very subtle, matches the reference
    rim = np.clip(1.0 - r2, 0.0, 1.0)
    rim = (rim * 0.08) * (1.0 - ndotl)  # faint warm bleed only on shadow half
    warm_tint = np.array([255, 235, 215], dtype=np.float32) / 255.0

    r, g, b = color_rgb
    base = np.stack(
        [intensity * r, intensity * g, intensity * b], axis=-1
    ).astype(np.float32)
    # blend warm rim in
    base[..., 0] = base[..., 0] * (1 - rim) + warm_tint[0] * 255 * rim
    base[..., 1] = base[..., 1] * (1 - rim) + warm_tint[1] * 255 * rim
    base[..., 2] = base[..., 2] * (1 - rim) + warm_tint[2] * 255 * rim
    base = np.clip(base, 0, 255).astype(np.uint8)

    # Build background
    bg = Image.new("RGB", (W, W), BG)

    # Cast soft contact shadow
    shadow = Image.new("L", (W, W), 0)
    sd = ImageDraw.Draw(shadow)
    # shadow offset toward lower-right (opposite of key light)
    shadow_cx = cx + int(SPHERE_R * 0.35)
    shadow_cy = cy + int(SPHERE_R * 0.92)
    sd.ellipse(
        [
            shadow_cx - int(SPHERE_R * 0.85),
            shadow_cy - 45,
            shadow_cx + int(SPHERE_R * 0.70),
            shadow_cy + 35,
        ],
        fill=140,
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(42))
    # Multiply shadow into bg
    bg_arr = np.array(bg).astype(np.float32)
    shd = np.array(shadow).astype(np.float32) / 255.0
    bg_arr *= 1.0 - 0.55 * shd[..., None]
    bg = Image.fromarray(np.clip(bg_arr, 0, 255).astype(np.uint8))

    # Composite sphere on top using antialiased mask
    aa_mask = np.clip((1.0 - r2) * SPHERE_R * 0.6, 0.0, 1.0)
    aa_mask = (aa_mask * 255).astype(np.uint8)
    sphere_img = Image.fromarray(base)
    bg.paste(sphere_img, (0, 0), Image.fromarray(aa_mask, "L"))
    return bg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--key", help="Render only one color key")
    ap.add_argument(
        "--out",
        default="tools/tile_sets/playful_3d_v2",
        help="Output directory",
    )
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    keys = [args.key] if args.key else list(COLORS.keys())
    for k in keys:
        if k not in COLORS:
            print(f"  skip {k}: no color entry")
            continue
        img = render_sphere(COLORS[k])
        path = out / f"{k}.png"
        img.save(path)
        print(f"  wrote {path}")

    print(f"\nOutput: {out}/")


if __name__ == "__main__":
    main()
