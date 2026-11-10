#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ "$(uname -s)" != "Darwin" ]; then
  echo "请在安装了 Xcode Command Line Tools 的 Mac 上构建。" >&2
  exit 1
fi
mkdir -p .build dist
staging=$(mktemp -d .build/macos-bundle.XXXXXX)
trap 'rm -rf "$staging"' EXIT
app="$staging/牛马脱敏器.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
sdk=$(xcrun --show-sdk-path)
for architecture in arm64 x86_64; do
  echo "正在编译 $architecture…"
  xcrun swiftc -swift-version 5 -O -warnings-as-errors \
    -sdk "$sdk" -target "$architecture-apple-macosx13.0" \
    macos/Sources/*.swift -o "$staging/NiuMa-$architecture"
done
xcrun lipo -create "$staging/NiuMa-arm64" "$staging/NiuMa-x86_64" -output "$app/Contents/MacOS/NiuMa"
cp macos/Info.plist "$app/Contents/Info.plist"
cp beij.png "$app/Contents/Resources/beij.png"
mkdir -p "$staging/AppIcon.iconset"
sips -s format png src/app.ico --out "$staging/icon.png" >/dev/null
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$staging/icon.png" --out "$staging/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$staging/icon.png" --out "$staging/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$staging/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --strict --verbose=2 "$app"
ditto "$app" "dist/牛马脱敏器.app"
ditto -c -k --sequesterRsrc --keepParent "dist/牛马脱敏器.app" "dist/牛马脱敏器-macOS-universal.zip"
xcrun lipo -info "dist/牛马脱敏器.app/Contents/MacOS/NiuMa"
echo "已生成：$PWD/dist/牛马脱敏器.app"
echo "分发包：$PWD/dist/牛马脱敏器-macOS-universal.zip"
