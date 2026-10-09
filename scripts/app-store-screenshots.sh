#!/bin/zsh
# Captures App Store screenshots of the iPhone and iPad app from demo data, in light and dark,
# into AppStoreScreenshots/ (gitignored). Uses the 6.9" iPhone and 13" iPad simulators, the
# sizes App Store Connect asks for.
#
# Usage: ./scripts/app-store-screenshots.sh
set -euo pipefail
ROOT="${0:A:h:h}"
OUT="$ROOT/AppStoreScreenshots"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/momentum-appstore.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
BUNDLE_ID="$(xcodebuild -project "$ROOT/Momentum.xcodeproj" -scheme MomentumMobile -showBuildSettings 2>/dev/null \
  | awk '/ PRODUCT_BUNDLE_IDENTIFIER =/ {print $3; exit}')"

# Screen name, tab, sheet.
SCREENS=(
  "1-today today -"
  "2-focus today focus"
  "3-goal goal -"
  "4-journal journal -"
  "5-review today review"
  "6-awards awards -"
  "7-insights insights -"
)

capture() {
  local device="$1" label="$2"
  echo "Building for $device…"
  xcodebuild -project "$ROOT/Momentum.xcodeproj" -scheme MomentumMobile -configuration Debug \
    -destination "platform=iOS Simulator,name=$device" -derivedDataPath "$BUILD" -quiet build
  local app="$BUILD/Build/Products/Debug-iphonesimulator/MomentumMobile.app"
  local udid
  udid="$(xcrun simctl list devices available | grep -F "    $device (" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)"
  local booted_here=0
  if ! xcrun simctl list devices booted | grep -q "$udid"; then
    xcrun simctl boot "$udid"
    booted_here=1
    sleep 15
  fi
  # A clean status bar, as on the App Store.
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
  xcrun simctl install "$udid" "$app"
  mkdir -p "$OUT/$label"
  local appearance screen name tab sheet
  for appearance in light dark; do
    xcrun simctl ui "$udid" appearance "$appearance"
    for screen in "${SCREENS[@]}"; do
      read -r name tab sheet <<< "$screen"
      [[ "$sheet" == "-" ]] && sheet=""
      SIMCTL_CHILD_MOMENTUM_DEMO=1 SIMCTL_CHILD_MOMENTUM_TAB="$tab" SIMCTL_CHILD_MOMENTUM_SHEET="$sheet" \
        xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" >/dev/null
      sleep 5
      xcrun simctl io "$udid" screenshot "$OUT/$label/$name-$appearance.png" >/dev/null
      echo "  $label/$name-$appearance.png"
    done
  done
  xcrun simctl status_bar "$udid" clear
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl uninstall "$udid" "$BUNDLE_ID"
  if (( booted_here )); then xcrun simctl shutdown "$udid"; fi
}

capture "iPhone 18 Pro Max" "iPhone 6.9"
capture "iPad Pro 13-inch (M5)" "iPad 13"
echo "Done: $OUT"
