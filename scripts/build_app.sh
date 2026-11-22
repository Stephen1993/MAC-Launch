#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p "$ROOT/.build/module-cache" "$ROOT/.build/clang-module-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/module-cache"

swift build \
  -c release \
  -debug-info-format none \
  --enable-experimental-strip-products \
  --disable-sandbox \
  --cache-path "$ROOT/.build/cache" \
  --config-path "$ROOT/.build/config" \
  --security-path "$ROOT/.build/security" \
  --manifest-cache local

ICON_PNG="$ROOT/.build/AppIcon-1024.png"
ICONSET="$ROOT/.build/AppIcon.iconset"
ICNS="$ROOT/.build/AppIcon.icns"

swift "$ROOT/scripts/generate_icon.swift" "$ICON_PNG"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

sips -z 16 16 "$ICON_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$ICON_PNG" "$ICONSET/icon_512x512@2x.png"
swift "$ROOT/scripts/make_icns.swift" "$ICONSET" "$ICNS"

APP="$ROOT/dist/Launch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/.build/release/Launch" "$APP/Contents/MacOS/Launch"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP" >/dev/null
rm -rf "$ICONSET" "$ICON_PNG" "$ICNS"

echo "Built: $APP"
