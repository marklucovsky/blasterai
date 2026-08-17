# Tile Image Sets

This directory contains the image set pipeline for Blaster's AAC tile artwork.

**Working with masters requires Git LFS** — see the "Working on tile image sets" section of `docs/collaborator-workflow.md` for one-time setup. App-only contributors can ignore this directory entirely; the runtime tiles bundled into the app live in `claudeBlast/Assets.xcassets/` and `claudeBlast/TileImageSets/` (regular git, no LFS needed).

## Directory Structure

```
tile_sets/
├── playful_3d/           # Playful 3D set — full-res DALL-E masters (LFS)
│   ├── {key}.png         # 1024×1024 source images, ~470 tiles
│   ├── generations.json  # Per-tile generation history
│   └── rejected.json     # Tiles flagged for regeneration
├── high_contrast/        # High Contrast set — full-res DALL-E masters (LFS)
│   └── {key}.png         # 1024×1024 source images, ~470 tiles
├── optimized/            # Resized for app bundle (gitignored — regenerable)
│   ├── playful_3d/       # 512×512 optimized PNGs
│   └── high_contrast/    # 512×512 optimized PNGs
├── current_p3d/          # Sync staging snapshot of bundled p3d tiles (gitignored)
├── current_arasaac/      # Sync staging snapshot of ARASAAC tiles (gitignored)
├── review_*.html         # Interactive review pages (gitignored, regenerable)
├── last_modified.json    # Tracks which tiles changed in last regen pass
└── README.md             # This file
```

## Master Images

- **`playful_3d/`** and **`high_contrast/`** — Full-resolution (1024×1024) DALL-E generated masters, tracked via **Git LFS**. ~550MB and ~263MB respectively. They check out as real PNGs automatically once `git lfs install` has been run on your machine. See `docs/collaborator-workflow.md` for setup.
- The ARASAAC baseline used for side-by-side comparison in the review tool comes from the app's bundled assets at `claudeBlast/Assets.xcassets/` (regular git).

## How to Generate an Image Set

### Prerequisites

```bash
pip install requests Pillow
export OPENAI_API_KEY=sk-...
```

### 1. Define your prompts

Each tile needs a subject description in `tools/prompts.json`:

```json
{
  "eat": "AAC pictogram: A 3D clay figurine child taking a huge bite of pizza...",
  "happy": "AAC pictogram: A clay child character with a big beaming smile..."
}
```

The generation script extracts the subject from each prompt and wraps it with the set's style prefix. You only need to describe *what* to show — the style (Playful 3D, High Contrast, etc.) is applied automatically.

### 2. Configure a style prefix

Style prefixes are defined in `tools/generate_sets.py`. Each set has a prefix that's prepended to every tile's subject. For example:

- **Playful 3D**: "3D clay/plasticine sculpture, soft rounded shapes, pastel-bright colors..."
- **High Contrast**: "High-contrast pictogram on solid black background, white bold figures..."

To create a new set, add a new style entry to `STYLES` in `generate_sets.py`.

### 3. Generate the set

```bash
# Generate a full set (473 tiles, ~2 hours, ~$19 in DALL-E API costs)
python3 tools/generate_sets.py --set playful_3d --skip-existing

# Generate a single tile (for iteration)
python3 tools/generate_sets.py --set playful_3d --key eat

# Dry run (preview prompts, no API calls)
python3 tools/generate_sets.py --set playful_3d --dry-run --batch 10
```

Output goes to `tools/tile_sets/{set_name}/{key}.png` at 1024×1024.

### 4. Review the set

```bash
# Build an interactive HTML review page
python3 tools/build_review_page.py --set playful_3d

# Open in browser — shows side-by-side current vs new, approve/reject/comment per tile
open tools/tile_sets/review_playful_3d.html
```

The review tool:
- Shows ARASAAC baseline alongside each generated tile
- Approve/reject with comments per tile (persists in localStorage)
- Filter by category, status, modified tiles
- Export rejects as JSON for batch regeneration

### 5. Iterate on rejected tiles

Export rejects from the review tool, then paste the JSON to update prompts and regenerate:

```bash
# Flag tiles for regen
python3 tools/review_tiles.py reject --set playful_3d --keys eat,walk,sit --reason "flat style"

# Regenerate flagged tiles
python3 tools/review_tiles.py regen --set playful_3d

# Check status
python3 tools/review_tiles.py status --set playful_3d
```

### 6. Optimize for the app bundle

```bash
# Resize masters to 512×512 for the app
python3 tools/optimize_tiles.py --set playful_3d
```

Optimized tiles go to `tools/tile_sets/optimized/{set_name}/`. This directory is gitignored — the optimized output is fully regenerable from the LFS-tracked masters, so there's no reason to commit it. Run `sync_to_app.py` afterward to copy the optimized PNGs into `claudeBlast/TileImageSets/`, which **is** committed (regular git) so the app bundle picks them up.

## Programmatic Tiles

Some tile categories are generated programmatically (not via DALL-E) for exact control:

- **Shapes** (circle, square, triangle, etc.) — DALL-E can't reliably draw simple geometry
- **Colors** (red, blue, green, etc.) — solid colored balls/swatches
- **Navigation** (next_page, previous_page) — matched arrow pairs
- **Yes/No** — green checkmark / red X

These are generated by code in `generate_sets.py` and `prototype_styles.py`, and are write-protected (`chmod 444`) to prevent the DALL-E generator from overwriting them.

## Style Guidelines (learned from iteration)

### Playful 3D
- **People/emotions**: Use free-standing 3D clay figurine characters, NOT flat/extruded bas-relief
- **Actions**: Clay figurine actively performing the action, dynamic poses
- **Food/objects**: The item itself as a clay sculpture, no characters needed
- **Places**: Clay diorama miniatures
- **Avoid**: Text, letters, WiFi/app icons, wheelchair symbols (DALL-E hallucinates these)
- **Style prefix must NOT mention** "AAC", "communication", "accessibility" — these trigger icon contamination

### High Contrast
- **Dominant scheme**: White on black, with bold accent colors (red, blue, green, yellow) for key elements
- **People**: Same concept as Playful 3D but rendered in high-contrast style
- **Objects prone to icon grids**: Generate programmatically instead of via DALL-E

## Costs

- DALL-E 3 standard 1024×1024: ~$0.04/image
- Full set (473 tiles): ~$19
- Typical iteration batch (20-50 tiles): $0.80–$2.00
- Total project spend to date: ~$150 across all generation passes

## Master resolution exceptions (2026-08-15)

`playful_3d/{between,middle,not,under}.png` are **512×512**, not 1024 like every
other master. They existed only in the shipped app bundle — never in this
directory — and were recovered from git during the HEIC re-encode, which had
silently dropped them.

They are correct for the current pipeline (which targets 512), but a future
export above 512 will upscale these four. Regenerate them at 1024 if that
matters; the art they replace was already reviewed and shipped, so it was
preserved rather than re-rolled.
