#!/usr/bin/env bash
# Render the Blaster deck to PDF, HTML, and PNGs using Marp CLI.
# Requires: Node (brew install node) and Google Chrome (for PDF/PNG export).
#
# Usage:
#   ./render.sh            # render deck to PDF + HTML
#   ./render.sh png        # also export per-slide PNGs into build/png/
set -euo pipefail

cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:$PATH"

# Point Marp at the system Chrome for PDF/PNG export.
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [[ -x "$CHROME" ]]; then
  export CHROME_PATH="$CHROME"
fi

# Pinned deliberately. This was `@latest`, which meant every render pulled
# whatever marp-cli shipped that day — so the deck was not reproducible across
# sessions, and a marp release could silently change the output with no diff to
# explain it. Bump this on purpose, re-render, and eyeball the result.
MARP_VERSION="${MARP_VERSION:-4.5.0}"   # last verified render: 2026-08-12

DECK="deck/blaster-deck.md"
THEME="deck/theme.css"
ONEPAGER="one-pager/blaster-one-pager.md"
ONEPAGER_THEME="one-pager/onepager-theme.css"
OUT="build"
mkdir -p "$OUT"

# Deck uses the base brand theme only.
MARP=(npx --yes @marp-team/marp-cli@${MARP_VERSION} --theme "$THEME" --allow-local-files)
# One-pager's theme @imports the base theme, so BOTH must be registered in the set.
MARP_ONEPAGER=(npx --yes @marp-team/marp-cli@${MARP_VERSION} --theme-set "$THEME" "$ONEPAGER_THEME" --allow-local-files)

echo "→ Deck PDF"
"${MARP[@]}" "$DECK" --pdf -o "$OUT/blaster-deck.pdf"

echo "→ Deck HTML"
"${MARP[@]}" "$DECK" --html -o "$OUT/blaster-deck.html"

echo "→ One-pager PDF"
"${MARP_ONEPAGER[@]}" "$ONEPAGER" --pdf -o "$OUT/blaster-one-pager.pdf"

if [[ "${1:-}" == "png" ]]; then
  echo "→ PNG (per slide)"
  mkdir -p "$OUT/png"
  "${MARP[@]}" "$DECK" --images png -o "$OUT/png/slide.png"
  "${MARP_ONEPAGER[@]}" "$ONEPAGER" --images png -o "$OUT/png/onepager.png"
fi

echo "✓ Done. Output in $OUT/"

# Publish. build/ is gitignored, and the site copies were previously updated by
# hand — which is how deck/index.html and blaster-deck.pdf went stale for weeks
# while the source moved on. Rendering and publishing are one step now.
SITE="${BLASTERAI_SITE:-$HOME/src/blasterai-site}"
if [[ "${1:-}" == "publish" || "${2:-}" == "publish" ]]; then
  if [[ ! -d "$SITE" ]]; then
    echo "✗ Site repo not found at $SITE (set BLASTERAI_SITE)" >&2
    exit 1
  fi
  cp "$OUT/blaster-deck.html" "$SITE/deck/index.html"
  cp "$OUT/blaster-deck.pdf"  "$SITE/docs/blaster-deck.pdf"
  echo "✓ Published → $SITE/deck/index.html + docs/blaster-deck.pdf"
  echo "  Commit and push in $SITE — it deploys on push."
else
  echo "  To publish to the site: ./render.sh publish"
fi
