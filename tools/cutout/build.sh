#!/bin/bash
# Build the cutout CLI from the app's own TileCutout.swift (macOS 14+ for Vision's subject mask).
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p tools/cutout/.build
swiftc -O -o tools/cutout/.build/cutout tools/cutout/main.swift claudeBlast/Services/TileCutout.swift
echo "built tools/cutout/.build/cutout"
