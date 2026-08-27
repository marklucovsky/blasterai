#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
#
# Unattended screenshot sweep across simulators.
#
# Boots each device, installs a fresh build, launches with -TileScriptAutorun
# so the app drives itself, then copies the captures out of the app container.
#
#   tools/screenshot_sweep.sh [script-resource-name] [out-dir]
#
# Nothing here needs a finger. That is the point: a sweep across form factors is
# the kind of check nobody runs if it costs ten minutes of tapping.

set -e

SCRIPT_NAME="${1:-shots_full}"
OUT="${2:-/tmp/blaster-shots}"
BUNDLE_ID="app.blasterai.ios"
SCHEME="claudeBlast"
OS_VER="26.2"

# Sizes App Store Connect actually accepts. The store requires a 6.9" iPhone
# and a 13" iPad; an 11" iPad or a 6.1" iPhone produces images it will reject,
# which is a thing you discover at upload time rather than here.
#
# Mac needs no entry: a Designed-for-iPad app has no separate Mac screenshot
# set — the Mac App Store listing reuses the iPad images.
DEVICES=(
  "iPad Pro 13-inch (M5)"     # 2064 x 2752
  "iPhone 17 Pro Max"         # 1320 x 2868
  "iPhone 16e"                # narrowest current phone — layout canary
)

# The list above is the *store* set — the sizes App Store Connect accepts.
# Chasing a layout bug usually means neither: one device, and often one the
# store does not want (an iPad mini is where narrow-iPad bugs live). So
# BLASTER_DEVICES both narrows and extends — a substring picks from the list,
# anything else is taken as a simulator name verbatim:
#
#   BLASTER_DEVICES=16e              tools/screenshot_sweep.sh shots_child_surface /tmp/out
#   BLASTER_DEVICES="iPad mini (A17 Pro)" tools/screenshot_sweep.sh shots_child_surface /tmp/out
if [[ -n "${BLASTER_DEVICES:-}" ]]; then
  # Resolution order matters, and exactness comes first at every step.
  # A plain substring pass made BLASTER_DEVICES="iPhone 17 Pro" run the Pro
  # *Max* — a different width, which is the one property this sweep exists to
  # test, and a silent substitution is worse than an error.
  #
  #   1. an exact name in the store list
  #   2. an exact simulator name, even if it is not a store size
  #   3. a substring of a store-list name, as a convenience ("16e")
  filtered=()
  for d in "${DEVICES[@]}"; do
    [[ "$d" == "$BLASTER_DEVICES" ]] && filtered+=("$d")
  done
  if [[ ${#filtered[@]} -eq 0 ]] \
     && xcrun simctl list devices available | grep -qF "$BLASTER_DEVICES ("; then
    filtered=("$BLASTER_DEVICES")
  fi
  if [[ ${#filtered[@]} -eq 0 ]]; then
    for d in "${DEVICES[@]}"; do
      [[ "$d" == *"$BLASTER_DEVICES"* ]] && filtered+=("$d")
    done
  fi
  if [[ ${#filtered[@]} -eq 0 ]]; then
    echo "!! No simulator named '$BLASTER_DEVICES', and it matches none of: ${DEVICES[*]}" >&2
    exit 1
  fi
  DEVICES=("${filtered[@]}")
fi

cd "$(dirname "$0")/.."
mkdir -p "$OUT"

# Resolve the built app from THIS checkout's build settings.
#
# Do not go hunting in ~/Library/Developer/Xcode/DerivedData with `find | head`:
# every worktree and checkout gets its own hashed directory — there are dozens —
# and the first match is arbitrary. That silently installed a three-week-old app
# from an unrelated checkout, which looked exactly like "the feature doesn't
# work" for as long as it took to notice.
app_path_for() {
  local device="$1"
  local built
  built=$(xcodebuild -project claudeBlast.xcodeproj -scheme "$SCHEME" \
            -destination "platform=iOS Simulator,name=$device,OS=$OS_VER" \
            -showBuildSettings 2>/dev/null \
          | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')
  echo "$built/claudeBlast.app"
}

for DEVICE in "${DEVICES[@]}"; do
  echo "=== $DEVICE ==="
  SAFE="${DEVICE// /-}"

  xcodebuild -project claudeBlast.xcodeproj -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,name=$DEVICE,OS=$OS_VER" \
    build > /dev/null

  APP=$(app_path_for "$DEVICE")
  if [[ ! -d "$APP" ]]; then
    echo "  !! built app not found at $APP"
    continue
  fi
  echo "  app: $APP"

  # Scoped to the OS section, not the first name match. Xcode keeps one
  # simulator per name per runtime, so a bare `grep | head -1` picks whichever
  # runtime happens to be listed first — which handed back an iPadOS 18.2 mini
  # and failed the install with "Requires a Newer Version of iPadOS". Same
  # class of mistake as the DerivedData hunt above.
  UDID=$(xcrun simctl list devices available \
         | awk -v os="-- iOS $OS_VER --" '$0 == os {inblock=1; next} /^-- /{inblock=0} inblock' \
         | grep -F "$DEVICE (" | head -1 \
         | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  if [[ -z "$UDID" ]]; then
    echo "  !! no simulator named '$DEVICE'"
    continue
  fi

  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b > /dev/null

  # Clean install: a sweep should photograph the app a new tester sees, not
  # whatever a previous run left behind.
  xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP"

  # Prime permissions, or a dialog stops a run nobody is watching.
  #
  # `photos-add` is the one that matters: ScreenCapture asks for `.addOnly`
  # authorization, and granting full `photos` does not satisfy it. Both are
  # granted because the cost is nil and the failure mode — a run that silently
  # captures nothing — is expensive to diagnose.
  #
  # Note there is no simctl service for speech recognition. That prompt was
  # fixed in the app instead: it was requested on every Admin appearance for a
  # dictation feature that does not exist.
  xcrun simctl privacy "$UDID" grant photos-add "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl privacy "$UDID" grant photos "$BUNDLE_ID" 2>/dev/null || true

  # Dynamic Type. Default is "large"; a caregiver who has turned text up is a
  # different layout, and a tray that fits at the default can burst at
  # xLarge — which is a real bug reported from a real iPad and invisible to a
  # sweep that only ever runs at the default.
  #
  #   BLASTER_CONTENT_SIZE=extra-extra-large tools/screenshot_sweep.sh …
  #   BLASTER_CONTENT_SIZE=accessibility-medium …
  xcrun simctl ui "$UDID" content_size "${BLASTER_CONTENT_SIZE:-large}" 2>/dev/null || true

  # A store screenshot should not advertise 47% battery and one bar. Apple's
  # own marketing convention is a full, uncluttered status bar.
  xcrun simctl status_bar "$UDID" override \
    --time "9:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 \
    --batteryState charged --batteryLevel 100 2>/dev/null || true

  xcrun simctl launch "$UDID" "$BUNDLE_ID" -TileScriptAutorun "$SCRIPT_NAME" > /dev/null

  echo "  running $SCRIPT_NAME…"
  CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
  SHOTS="$CONTAINER/Documents/Screenshots"

  # Poll rather than sleeping a fixed span: scripts differ in length, and a
  # fixed wait is either slower than it needs to be or wrong. Consider the run
  # finished once the capture count has held steady for STABLE_POLLS polls —
  # long enough to cover the slowest single step (an admin push plus its
  # settle), so a slow step is not mistaken for the end.
  local_prev=-1
  stable=0
  STABLE_POLLS=8
  for i in {1..90}; do
    sleep 1
    if [[ -d "$SHOTS" ]]; then
      count=$(ls "$SHOTS" 2>/dev/null | wc -l | tr -d ' ')
    else
      count=0
    fi
    if [[ "$count" == "$local_prev" ]]; then
      stable=$((stable + 1))
      [[ $count -gt 0 && $stable -ge $STABLE_POLLS ]] && break
    else
      stable=0
    fi
    local_prev=$count
  done

  DEST="$OUT/$SAFE"
  rm -rf "$DEST"; mkdir -p "$DEST"
  if [[ -d "$SHOTS" ]]; then
    cp "$SHOTS"/*.png "$DEST"/ 2>/dev/null || true
    echo "  captured $(ls "$DEST" | wc -l | tr -d ' ') image(s) → $DEST"
  else
    echo "  !! no Screenshots directory — did the script run?"
  fi

  xcrun simctl status_bar "$UDID" clear 2>/dev/null || true
  xcrun simctl shutdown "$UDID" 2>/dev/null || true
done

echo
echo "open $OUT"
