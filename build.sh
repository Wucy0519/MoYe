#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/moye-build.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
APP="$ROOT/../墨页.app"
mkdir -p "$BUILD/icon.iconset" "$BUILD/ModuleCache" "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -sdk "$SDK" -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$BUILD/ModuleCache" -O -framework AppKit -o "$BUILD/MakeIcon" "$ROOT/Tools/MakeIcon.swift"
"$BUILD/MakeIcon" "$BUILD/icon-1024.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$BUILD/icon-1024.png" --out "$BUILD/icon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$BUILD/icon-1024.png" --out "$BUILD/icon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 "$ROOT/Tools/PackIcon.py" "$BUILD/icon.iconset" "$APP/Contents/Resources/AppIcon.icns"
swiftc -sdk "$SDK" -target "$(uname -m)-apple-macosx14.0" -module-name MoYe -module-cache-path "$BUILD/ModuleCache" -O -whole-module-optimization -framework AppKit -framework WebKit -lcmark-gfm "$ROOT"/Sources/*.swift -o "$APP/Contents/MacOS/墨页"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/MathJax"
cp "$ROOT/Vendor/MathJax/tex-svg-full.js" "$ROOT/Vendor/MathJax/LICENSE" "$APP/Contents/Resources/MathJax/"
# NSDocument resolves the Swift runtime class name from the module.
/usr/libexec/PlistBuddy -c 'Set :CFBundleDocumentTypes:0:NSDocumentClass MoYe.MarkdownDocument' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDocumentTypes:1:NSDocumentClass MoYe.MarkdownDocument' "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/墨页" --self-test
echo "已生成：$APP"
