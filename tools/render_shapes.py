#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Deterministic renderer for the Playful 3D shape tile set.

Renders an extruded matte shape (beveled prism) on a warm cream background,
matching the color sphere aesthetic from render_color_spheres.py. Same key
light direction (upper-right), same shadow placement, same matte palette.

Usage:
    python3 tools/render_shapes.py
    python3 tools/render_shapes.py --key star
    python3 tools/render_shapes.py --out DIR
"""

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy.ndimage import distance_transform_edt

W = 1024
# Playful 3D moved to a pure white canvas with the gpt-image-2 re-shoot (2026-10).
BG = (255, 255, 255)
SHAPE_FIT = 660          # bounding-box edge length the shape is fit into
CENTER = (W // 2, W // 2 - 10)
LIGHT = np.array([0.45, -0.55, 0.70])
LIGHT /= np.linalg.norm(LIGHT)
AMBIENT = 0.58
BEVEL_PX = 95            # bevel width — distance over which edge rises to top
TOP_HEIGHT = 1.0         # plateau height in normal-units

# Per-shape color palette — distinct, all matte mid-tones.
SHAPE_COLORS = {
    "circle":    ( 90, 140, 215),  # blue
    "square":    (222,  72,  64),  # red
    "triangle":  (110, 180,  95),  # green
    "rectangle": (238, 138,  54),  # orange
    "oval":      (160, 108, 200),  # purple
    "diamond":   ( 90, 195, 215),  # cyan
    "star":      (240, 205,  70),  # yellow
    "heart":     (240, 110, 130),  # warm pink
    "octagon":   (200,  60,  50),  # stop-sign red
}


def shape_mask(name: str) -> np.ndarray:
    """Return a (W, W) bool mask of the shape silhouette centered at CENTER."""
    cx, cy = CENTER
    img = Image.new("L", (W, W), 0)
    draw = ImageDraw.Draw(img)
    half = SHAPE_FIT // 2

    if name == "circle":
        r = half
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)

    elif name == "square":
        s = int(half * 0.95)
        draw.rectangle([cx - s, cy - s, cx + s, cy + s], fill=255)

    elif name == "rectangle":
        rx = int(half * 1.05)
        ry = int(half * 0.62)
        draw.rectangle([cx - rx, cy - ry, cx + rx, cy + ry], fill=255)

    elif name == "oval":
        rx = int(half * 1.05)
        ry = int(half * 0.66)
        draw.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255)

    elif name == "triangle":
        # Equilateral, point up
        h = int(half * 1.0 * math.sqrt(3))
        # Fit so vertical extent = SHAPE_FIT
        h = SHAPE_FIT
        side = int(h / (math.sqrt(3) / 2))
        top = (cx, cy - h // 2)
        bl = (cx - side // 2, cy + h // 2)
        br = (cx + side // 2, cy + h // 2)
        draw.polygon([top, bl, br], fill=255)

    elif name == "diamond":
        h = half
        draw.polygon(
            [(cx, cy - h), (cx + h, cy), (cx, cy + h), (cx - h, cy)], fill=255
        )

    elif name == "star":
        pts = []
        outer = half * 1.0
        inner = half * 0.42
        for i in range(10):
            angle = -math.pi / 2 + i * math.pi / 5
            r = outer if i % 2 == 0 else inner
            pts.append((cx + r * math.cos(angle), cy + r * math.sin(angle)))
        draw.polygon(pts, fill=255)

    elif name == "heart":
        # Parametric heart: x = 16 sin^3 t,  y = -(13 cos t - 5 cos 2t - 2 cos 3t - cos 4t)
        scale = half * 0.052
        pts = []
        for i in range(360):
            t = i * math.pi / 180
            hx = 16 * math.sin(t) ** 3
            hy = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
            pts.append((cx + hx * scale, cy + hy * scale))
        draw.polygon(pts, fill=255)

    elif name == "octagon":
        r = half
        pts = [
            (cx + r * math.cos(math.pi / 8 + i * math.pi / 4),
             cy + r * math.sin(math.pi / 8 + i * math.pi / 4))
            for i in range(8)
        ]
        draw.polygon(pts, fill=255)

    else:
        raise ValueError(f"unknown shape: {name}")

    return np.array(img) > 127


def build_height(mask: np.ndarray) -> np.ndarray:
    """Distance-from-edge bevel: rises smoothly from 0 at edge to TOP_HEIGHT."""
    d = distance_transform_edt(mask).astype(np.float32)
    h = np.clip(d / BEVEL_PX, 0.0, 1.0) * TOP_HEIGHT
    # Smoothstep for rounded bevel
    t = h / TOP_HEIGHT
    h = (t * t * (3 - 2 * t)) * TOP_HEIGHT
    return h


def shade(mask: np.ndarray, color_rgb: tuple[int, int, int]) -> Image.Image:
    h = build_height(mask)
    # Convert height to Z by scaling — bevel width corresponds to a unit of Z
    # so the slope is finite; effectively normal slope = dh/dx_pixel * (1 / BEVEL_PX_z)
    # We'll compute gradients in pixels and scale to get normal.
    gy, gx = np.gradient(h)
    z_scale = 1.0 / BEVEL_PX  # treat extrusion depth ~= bevel width
    nx = -gx * z_scale * BEVEL_PX  # cancel — slope is just -gx
    ny = -gy * z_scale * BEVEL_PX
    nz = np.ones_like(h)
    nlen = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / nlen, ny / nlen, nz / nlen

    ndotl = nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]
    ndotl = np.clip(ndotl, 0.0, 1.0)
    intensity = AMBIENT + (1.0 - AMBIENT) * ndotl
    intensity = np.power(intensity, 0.92)

    r, g, b = color_rgb
    rgb = np.stack(
        [intensity * r, intensity * g, intensity * b], axis=-1
    ).astype(np.float32)
    rgb = np.clip(rgb, 0, 255).astype(np.uint8)

    # Background
    bg = Image.new("RGB", (W, W), BG)

    # Soft contact shadow follows shape silhouette, offset down-right
    shadow_mask = Image.fromarray((mask.astype(np.uint8) * 140), "L")
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(40))
    shadow_off = Image.new("L", (W, W), 0)
    shadow_off.paste(
        shadow_mask,
        (int(SHAPE_FIT * 0.04), int(SHAPE_FIT * 0.06)),
    )
    bg_arr = np.array(bg).astype(np.float32)
    shd = np.array(shadow_off).astype(np.float32) / 255.0
    bg_arr *= 1.0 - 0.55 * shd[..., None]
    bg = Image.fromarray(np.clip(bg_arr, 0, 255).astype(np.uint8))

    # Antialias mask: dilate-soften the silhouette edge slightly
    aa = (mask.astype(np.float32))
    aa_img = Image.fromarray((aa * 255).astype(np.uint8), "L").filter(
        ImageFilter.GaussianBlur(0.8)
    )
    bg.paste(Image.fromarray(rgb), (0, 0), aa_img)
    return bg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--key", help="Render only one shape key")
    ap.add_argument(
        "--out",
        default="tools/tile_sets/playful_3d_v2",
        help="Output directory",
    )
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    keys = [args.key] if args.key else list(SHAPE_COLORS.keys())
    for k in keys:
        if k not in SHAPE_COLORS:
            print(f"  skip {k}: no color entry")
            continue
        mask = shape_mask(k)
        img = shade(mask, SHAPE_COLORS[k])
        path = out / f"{k}.png"
        img.save(path)
        print(f"  wrote {path}")

    print(f"\nOutput: {out}/")


if __name__ == "__main__":
    main()
