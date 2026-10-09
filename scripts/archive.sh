#!/bin/zsh
# Archives Momentum for the App Store and exports both apps for App Store Connect: the Mac app,
# and the iPhone and iPad app with the Apple Watch app inside it.
#
# Usage:
#   ./scripts/archive.sh                          archive and export into build/archives/
#   ./scripts/archive.sh --upload KEY KEY_ID ISSUER
#       archive and upload both builds to App Store Connect, signing in with an App Store Connect
#       API key: KEY is its AuthKey_<id>.p8 file, KEY_ID the key's ID and ISSUER the issuer ID
#       (App Store Connect, Users and Access, Integrations). An uploaded build appears in
#       TestFlight; submitting it for review is still done in App Store Connect.
#
# Signing is automatic and needs a paid Apple Developer Program team in Config/Local.xcconfig
# (DEVELOPMENT_TEAM), with Xcode signed in to it unless a key is given. A free Personal Team can't
# sign for the App Store, so the script stops before building when that's the team.
set -euo pipefail
cd "${0:A:h}/.."

OUT=build/archives
AUTH=()
DESTINATION=export
if [[ "${1:-}" == "--upload" ]]; then
  (( $# == 4 )) || { print -u2 "Usage: $0 --upload KEY KEY_ID ISSUER"; exit 64; }
  [[ -f "$2" ]] || { print -u2 "No API key file at $2"; exit 66; }
  AUTH=(-authenticationKeyPath "${2:A}" -authenticationKeyID "$3" -authenticationKeyIssuerID "$4")
  DESTINATION=upload
elif (( $# > 0 )); then
  print -u2 "Usage: $0 [--upload KEY KEY_ID ISSUER]"
  exit 64
fi

# A build setting of the Mac app target.
setting() {
  xcodebuild -project Momentum.xcodeproj -scheme Momentum -showBuildSettings 2>/dev/null | awk -v key="$1" '
    /^Build settings for / { app = ($0 ~ / target Momentum:$/); next }
    app && $1 == key && $2 == "=" { print $3; exit }'
}
TEAM=$(setting DEVELOPMENT_TEAM)
BUNDLE_ID=$(setting PRODUCT_BUNDLE_IDENTIFIER)
VERSION="$(setting MARKETING_VERSION) ($(setting CURRENT_PROJECT_VERSION))"
[[ -n "$TEAM" ]] || { print -u2 "Set DEVELOPMENT_TEAM in Config/Local.xcconfig."; exit 1; }

# Xcode notes, for each team it knows, whether it's a free Personal Team.
if defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null | awk -v team="$TEAM" '
  /\{/ { block = "" }
  { block = block $0 "\n" }
  /\}/ { if (index(block, "teamID = " team ";") && index(block, "isFreeProvisioningTeam = 1;")) free = 1 }
  END { exit free ? 0 : 1 }'; then
  print -u2 "Team $TEAM is a free Personal Team, which can't sign for the App Store."
  print -u2 "Join the Apple Developer Program, then set the paid team's ID in Config/Local.xcconfig."
  exit 1
fi

echo "Momentum $VERSION, team $TEAM"
mkdir -p "$OUT"
OPTIONS="$OUT/ExportOptions.plist"
cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>$DESTINATION</string>
	<key>teamID</key>
	<string>$TEAM</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
PLIST
plutil -lint -s "$OPTIONS"

# Archives one scheme and exports (or uploads) it.
ship() {
  local scheme="$1" platform="$2" name="$3"
  local archive="$OUT/$name.xcarchive"
  echo "Archiving $scheme…"
  rm -rf "$archive"
  xcodebuild archive -project Momentum.xcodeproj -scheme "$scheme" -configuration Release \
    -destination "generic/platform=$platform" -archivePath "$archive" -derivedDataPath build \
    CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates "${AUTH[@]}" -quiet
  if [[ "$DESTINATION" == upload ]]; then echo "Uploading $name…"; else echo "Exporting $name…"; fi
  xcodebuild -exportArchive -archivePath "$archive" -exportPath "$OUT/$name" \
    -exportOptionsPlist "$OPTIONS" -allowProvisioningUpdates "${AUTH[@]}"
}

ship Momentum macOS Mac
ship MomentumMobile iOS iOS

# Building registered these copies with LaunchServices; the installed app stays the one on record,
# so the desktop widgets keep drawing.
./scripts/unregister-copies.sh "$BUNDLE_ID" /Applications/Momentum.app

if [[ "$DESTINATION" == upload ]]; then
  echo "Uploaded Momentum $VERSION. It appears in TestFlight once App Store Connect has processed it."
else
  echo "Exported to $OUT/Mac and $OUT/iOS. Upload them with Transporter, or run: $0 --upload KEY KEY_ID ISSUER"
fi
