#!/bin/zsh
# Renders docs/images/*.png from demo data: app screens and every widget size.
# The app's views are compiled into a small unsandboxed harness, so nothing needs signing
# and no real data is read.
#
# For other uses, MOMENTUM_OUT renders into another folder, MOMENTUM_WIDGETS=0 skips the widget
# gallery and MOMENTUM_MAX_WIDTH=0 keeps full size; the harness also reads MOMENTUM_WINDOW,
# MOMENTUM_SHOTS and MOMENTUM_PALETTE (see Harness.swift).
set -euo pipefail
# Clocks draw still, so a capture never lands between two digits.
export MOMENTUM_SCREENSHOT=1
ROOT="${0:A:h:h:h}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/momentum-shots.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
OUT="${MOMENTUM_OUT:-$ROOT/docs/images}"
mkdir -p "$OUT" "$WORK/src" "$WORK/widgets"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
TARGET="arm64-apple-macos14.0"

echo "Building MomentumCore…"
xcrun swiftc -sdk "$SDK" -target "$TARGET" -O -parse-as-library -emit-library -emit-module \
  -module-name MomentumCore -o "$WORK/libMomentumCore.dylib" -emit-module-path "$WORK/MomentumCore.swiftmodule" \
  -Xlinker -install_name -Xlinker @rpath/libMomentumCore.dylib \
  "$ROOT"/Packages/MomentumKit/Sources/MomentumCore/**/*.swift

echo "Rendering app screens…"
cp "$ROOT"/Shared/**/*.swift "$WORK/src/"
find "$ROOT/Momentum" -name '*.swift' ! -name 'MomentumApp.swift' -exec cp {} "$WORK/src/" \;
find "$ROOT/SharedUI" -name '*.swift' -exec cp {} "$WORK/src/" \;
cp "$ROOT/scripts/screenshots/Harness.swift" "$WORK/src/main.swift"
xcrun swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 -I "$WORK" -L "$WORK" -lMomentumCore \
  -Xlinker -rpath -Xlinker "$WORK" -o "$WORK/harness" "$WORK"/src/*.swift
"$WORK/harness" "$OUT" ${EXTRAS:+"$EXTRAS"}

if [[ "${MOMENTUM_WIDGETS:-1}" != 0 ]]; then
  echo "Rendering widgets…"
  cp "$ROOT"/Shared/**/*.swift "$WORK/widgets/"
  cp "$ROOT"/MomentumWidgets/*.swift "$WORK/widgets/"
  # The harness picks each widget size itself: drop @main and make widgetFamily a stored property.
  sed -i '' 's/^@main$//' "$WORK/widgets/WidgetSupport.swift"
  sed -i '' 's/@Environment(\\.widgetFamily) private var family/var family: WidgetFamily = .systemMedium/' "$WORK"/widgets/*.swift
  cp "$ROOT/scripts/screenshots/WidgetHarness.swift" "$WORK/widgets/main.swift"
  xcrun swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 -I "$WORK" -L "$WORK" -lMomentumCore \
    -Xlinker -rpath -Xlinker "$WORK" -o "$WORK/widget-harness" "$WORK"/widgets/*.swift
  "$WORK/widget-harness" "$OUT"
fi

# Keep the README light: cap image width, and drop color profiles and metadata.
MAX_WIDTH="${MOMENTUM_MAX_WIDTH:-1600}"
for image in "$OUT"/*.png; do
  width=$(sips -g pixelWidth "$image" | awk '/pixelWidth/ {print $2}')
  if (( MAX_WIDTH > 0 && width > MAX_WIDTH )); then
    sips --resampleWidth "$MAX_WIDTH" "$image" --out "$image" >/dev/null
  fi
done
echo "Done: $OUT"
