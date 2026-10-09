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
sleep 1
rm -rf "$INSTALLED"
ditto "$BUILT" "$INSTALLED"

# The desktop only draws a widget whose version matches the copy LaunchServices has on record.
# Every Xcode build registers its own copy, so a build product or an old build of another version
# makes each widget reload fail ("Bundle version did not match") and leaves grey placeholders.
# Keep the installed app as the only registered copy.
"$LSREGISTER" -dump | awk -v id="$BUNDLE_ID" -v keep="$INSTALLED" '
  function flush() { if (matched && path != "" && index(path, keep) != 1) print path; path = ""; matched = 0 }
  /^-{20,}/ { flush(); next }
  /^path:/ { sub(/^path: +/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); path = $0 }
  /^identifier:/ { if ($2 == id || index($2, id ".") == 1) matched = 1 }
  END { flush() }
' | sort -u | while IFS= read -r stale; do
  "$LSREGISTER" -u "$stale" 2>/dev/null || true
done
"$LSREGISTER" -f "$INSTALLED"

open "$INSTALLED"
echo "Installed $INSTALLED"
