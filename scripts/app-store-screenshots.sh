#!/bin/zsh
# Captures the App Store screenshots from demo data into AppStoreScreenshots/ (gitignored), at the
# sizes App Store Connect asks for: iPhone 6.9" and iPad 13" in light and dark, Apple Watch
# (46 mm), and Mac (2880 × 1800) in light and dark.
#
# The iPhone, its paired watch and the iPad are fresh simulators made for the run and deleted after
# it, so simulators you use are never touched. The Mac screens come from screenshots/render.sh.
#
# Usage: ./scripts/app-store-screenshots.sh
set -euo pipefail
ROOT="${0:A:h:h}"
OUT="$ROOT/AppStoreScreenshots"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/momentum-appstore.XXXXXX")"
BUNDLE_ID="$(xcodebuild -project "$ROOT/Momentum.xcodeproj" -scheme MomentumMobile -showBuildSettings 2>/dev/null \
  | awk '/ PRODUCT_BUNDLE_IDENTIFIER =/ {print $3; exit}')"
DEVICES=()

cleanup() {
  local udid
  for udid in "${DEVICES[@]}"; do
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl delete "$udid" >/dev/null 2>&1 || true
  done
  rm -rf "$BUILD"
  # Building registered the simulator apps with LaunchServices under the Mac app's bundle ID; the
  # installed Mac app stays the one on record, so its desktop widgets keep drawing.
  "$ROOT/scripts/unregister-copies.sh" "$BUNDLE_ID" /Applications/Momentum.app || true
}
trap cleanup EXIT
# Stopped partway (Control-C, kill), it still deletes its simulators.
trap 'exit 130' INT TERM

# Screen name, tab, sheet, and for the goal tab the goal's name (the rest of the line).
SCREENS=(
  "1-today today -"
  "2-focus today focus"
  "3-goal goal - Learn Spanish"
  "4-journal journal -"
  "5-review today review"
  "6-awards awards -"
  "7-insights insights -"
)

# Creates a simulator for this run, deleted at the end; leaves its UDID in REPLY.
new_device() {
  REPLY="$(xcrun simctl create "Momentum Screenshots ($1)" "$1")"
  DEVICES+=("$REPLY")
}

boot() {
  xcrun simctl boot "$1" 2>/dev/null || true
  xcrun simctl bootstatus "$1" -b >/dev/null
}

# A fresh folder for one set, so screens dropped from the list don't linger.
folder() {
  rm -rf "$OUT/$1"
  mkdir -p "$OUT/$1"
}

# The app's screens in light and dark, from demo data held in memory.
capture_screens() {
  local udid="$1" label="$2" appearance screen name tab sheet goal
  # A clean status bar, as on the App Store.
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
  xcrun simctl install "$udid" "$APP"
  folder "$label"
  for appearance in light dark; do
    xcrun simctl ui "$udid" appearance "$appearance"
    for screen in "${SCREENS[@]}"; do
      read -r name tab sheet goal <<< "$screen"
      [[ "$sheet" == "-" ]] && sheet=""
      SIMCTL_CHILD_MOMENTUM_DEMO=1 SIMCTL_CHILD_MOMENTUM_SCREENSHOT=1 SIMCTL_CHILD_MOMENTUM_TAB="$tab" \
        SIMCTL_CHILD_MOMENTUM_SHEET="$sheet" SIMCTL_CHILD_MOMENTUM_GOAL="$goal" \
        xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" >/dev/null
      sleep 5
      xcrun simctl io "$udid" screenshot "$OUT/$label/$name-$appearance.png" >/dev/null 2>&1
      echo "  $label/$name-$appearance.png"
    done
  done
}

# One screen of the watch app: optionally a goal opened by name, and one of its buttons pressed.
watch_screen() {
  local watch="$1" file="$2" goal="${3:-}" action="${4:-}"
  SIMCTL_CHILD_MOMENTUM_WATCH_GOAL="$goal" SIMCTL_CHILD_MOMENTUM_WATCH_ACTION="$action" \
    xcrun simctl launch --terminate-running-process "$watch" "$BUNDLE_ID.watchkitapp" >/dev/null
  sleep 8
  xcrun simctl io "$watch" screenshot "$OUT/$file.png" >/dev/null 2>&1
  echo "  $file.png"
}

# The watch app shows what the iPhone app sends it: the iPhone app writes the demo data to its
# data file (MOMENTUM_DEMO=seed) and sends today from it.
capture_watch() {
  local phone="$1" watch="$2" label="$3"
  xcrun simctl install "$watch" "$WATCH_APP"
  SIMCTL_CHILD_MOMENTUM_DEMO=seed xcrun simctl launch --terminate-running-process "$phone" "$BUNDLE_ID" >/dev/null
  sleep 10
  folder "$label"
  watch_screen "$watch" "$label/1-today"
  watch_screen "$watch" "$label/2-focus" "Deep work" start
  watch_screen "$watch" "$label/3-today-focusing"
  watch_screen "$watch" "$label/4-goal" "Exercise"
}

echo "Building…"
xcodebuild -project "$ROOT/Momentum.xcodeproj" -scheme MomentumMobile -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$BUILD" -quiet build
APP="$BUILD/Build/Products/Debug-iphonesimulator/MomentumMobile.app"
WATCH_APP="$BUILD/Build/Products/Debug-watchsimulator/MomentumWatch.app"

echo "iPhone and Apple Watch…"
new_device "iPhone 18 Pro Max"; PHONE="$REPLY"
new_device "Apple Watch Series 12 (46mm)"; WATCH="$REPLY"
xcrun simctl pair "$WATCH" "$PHONE" >/dev/null
boot "$PHONE"
capture_screens "$PHONE" "iPhone 6.9"
boot "$WATCH"
capture_watch "$PHONE" "$WATCH" "Watch 46mm"
xcrun simctl shutdown "$WATCH" "$PHONE"

echo "iPad…"
new_device "iPad Pro 13-inch (M5)"; IPAD="$REPLY"
boot "$IPAD"
capture_screens "$IPAD" "iPad 13"
xcrun simctl shutdown "$IPAD"

echo "Mac…"
folder "Mac"
MOMENTUM_OUT="$OUT/Mac" MOMENTUM_WIDGETS=0 MOMENTUM_MAX_WIDTH=0 MOMENTUM_WINDOW=1440x900 \
  MOMENTUM_SHOTS=today,goal-time,insights,journal,awards "$ROOT/scripts/screenshots/render.sh"

echo "Done: $OUT"
