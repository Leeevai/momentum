#!/bin/zsh
# Builds Momentum (Release), installs it to /Applications and relaunches it.
# Widgets appear in the widget gallery once the system has registered the installed app.
set -euo pipefail
cd "${0:A:h}/.."

xcodebuild -project Momentum.xcodeproj -scheme Momentum -configuration Release \
  -derivedDataPath build -destination 'platform=macOS' -quiet build

osascript -e 'tell application id "dev.hassan.Momentum" to quit' 2>/dev/null || true
sleep 1
rm -rf /Applications/Momentum.app
ditto build/Build/Products/Release/Momentum.app /Applications/Momentum.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Momentum.app
open /Applications/Momentum.app
echo "Installed /Applications/Momentum.app"
