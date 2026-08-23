#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
#
# Snapshot the device-local store on the booted simulator, so a compaction soak
# has a before/after that is measured rather than eyeballed in the UI.
#
# The app's own About & Stats screen reports the same total, but it rounds, it
# cannot show the SQLite freelist, and it is not readable while the app is being
# relaunched -- which is exactly when the interesting transition happens. The
# freelist is the whole reason compaction takes two launches: launch N folds and
# frees pages, launch N+1 truncates the file. Watching only the file size makes
# a correct fold look like it did nothing.
#
#   tools/compaction_watch.sh            # snapshot now
#   tools/compaction_watch.sh --watch    # re-snapshot every 5s
#
# See claudeBlast/Resources/Scripts/load_natural.yaml for the run it instruments.

set -euo pipefail

BUNDLE_ID="app.blasterai.ios"

container() {
  xcrun simctl get_app_container booted "$BUNDLE_ID" data 2>/dev/null
}

snapshot() {
  local c store
  c="$(container)" || { echo "app not installed on the booted simulator"; return 1; }
  store="$c/Library/Application Support/DeviceLocal.store"
  [ -f "$store" ] || { echo "no DeviceLocal.store yet -- launch the app once"; return 1; }

  # -wal counts: rows written but not yet checkpointed are real bytes on disk
  # and the app's own reporter includes them, so excluding them here would make
  # the two disagree mid-run.
  local bytes wal
  bytes=$(stat -f%z "$store")
  wal=$(stat -f%z "$store-wal" 2>/dev/null || echo 0)

  # Read-only, and via a URI so this never creates or upgrades a store behind
  # the app's back while the app may also have it open.
  local q
  q=$(sqlite3 "file:$store?mode=ro" <<'SQL' 2>/dev/null || true
SELECT (SELECT COUNT(*) FROM ZMETRICEVENT)
    || '|' || (SELECT COUNT(*) FROM ZAPIUSAGEEVENT)
    || '|' || (SELECT COUNT(*) FROM ZCOMPACTIONRUN)
    || '|' || (SELECT * FROM pragma_page_count)
    || '|' || (SELECT * FROM pragma_freelist_count)
    || '|' || (SELECT * FROM pragma_page_size);
SQL
)
  IFS='|' read -r metrics usage runs pages freelist psize <<<"${q:-0|0|0|0|0|0}"

  printf '%s  store %8.2f MB  +wal %6.2f MB  free %8.2f MB (%s/%s pages)  metric %-9s usage %-5s runs %s\n' \
    "$(date +%H:%M:%S)" \
    "$(echo "$bytes/1048576" | bc -l)" \
    "$(echo "$wal/1048576" | bc -l)" \
    "$(echo "$freelist*$psize/1048576" | bc -l)" \
    "$freelist" "$pages" "$metrics" "$usage" "$runs"
}

if [ "${1:-}" = "--watch" ]; then
  while true; do snapshot || true; sleep 5; done
else
  snapshot
fi
