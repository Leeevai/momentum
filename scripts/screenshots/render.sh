#!/bin/zsh
# Renders docs/images/*.png from demo data: app screens and every widget size.
# The app's views are compiled into a small unsandboxed harness, so nothing needs signing
# and no real data is read.
set -euo pipefail
ROOT="${0:A:h:h:h}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/momentum-shots.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
OUT="$ROOT/docs/images"
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
cp "$ROOT/scripts/screenshots/Harness.swift" "$WORK/src/main.swift"
xcrun swiftc -sdk "$SDK" -target "$TARGET" -swift-version 5 -I "$WORK" -L "$WORK" -lMomentumCore \
  -Xlinker -rpath -Xlinker "$WORK" -o "$WORK/harness" "$WORK"/src/*.swift
"$WORK/harness" "$OUT"

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


# Keep the README light: cap image width, and drop color profiles and metadata.
for image in "$OUT"/*.png; do
  width=$(sips -g pixelWidth "$image" | awk '/pixelWidth/ {print $2}')
  if (( width > 1600 )); then
    sips --resampleWidth 1600 "$image" --out "$image" >/dev/null
  fi
done
echo "Done: $OUT"
