#!/bin/zsh
# Builds Momentum (Release), installs it to /Applications and relaunches it.
# Widgets appear in the widget gallery once the system has registered the installed app.
set -euo pipefail
cd "${0:A:h}/.."

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
BUILT=build/Build/Products/Release/Momentum.app
INSTALLED=/Applications/Momentum.app

xcodebuild -project Momentum.xcodeproj -scheme Momentum -configuration Release \
  -derivedDataPath build -destination 'platform=macOS' -quiet build
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUILT/Contents/Info.plist")

osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
for _ in {1..10}; do pgrep -f "$INSTALLED/Contents/MacOS/" >/dev/null || break; sleep 0.5; done
# Quitting through AppleScript needs Automation permission. Whatever still runs from the old copy
# is stopped, the widget extension included (the system keeps it alive): an old extension left
# running fails every widget reload against the new copy.
pkill -TERM -f "$INSTALLED/Contents/MacOS/" 2>/dev/null || true
pkill -TERM -f "$INSTALLED/Contents/PlugIns/" 2>/dev/null || true
sleep 1
rm -rf "$INSTALLED"
ditto "$BUILT" "$INSTALLED"

# Every Xcode build registers its own copy, and one of another version on record leaves the desktop
# widgets as grey placeholders: keep the installed app the only registered copy.
./scripts/unregister-copies.sh "$BUNDLE_ID" "$INSTALLED"
"$LSREGISTER" -f "$INSTALLED"

open "$INSTALLED"
echo "Installed $INSTALLED"
