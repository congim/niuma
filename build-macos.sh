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
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
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
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' macos/Info.plist)
archive="dist/NiuMa-macOS-universal-$version.zip"
ditto -c -k --sequesterRsrc --keepParent "dist/牛马脱敏器.app" "$archive"
cp "$archive" "dist/牛马脱敏器-macOS-universal.zip"
for architecture in arm64 x86_64; do
  image_root="$staging/$architecture"
  image_app="$image_root/牛马脱敏器.app"
  mkdir -p "$image_root"
  ditto "$app" "$image_app"
  xcrun lipo "$app/Contents/MacOS/NiuMa" -thin "$architecture" -output "$image_app/Contents/MacOS/NiuMa"
  codesign --force --sign - --timestamp=none "$image_app"
  codesign --verify --strict --verbose=2 "$image_app"
  ln -s /Applications "$image_root/Applications"
  cat > "$image_root/安装说明.txt" <<'INSTALL'
牛马脱敏器 · macOS 13 或以上

将「牛马脱敏器.app」拖入「Applications」后，从应用程序中打开。
应用入口在屏幕顶部菜单栏的钞票图标，不显示 Dock 图标。

当前版本使用本地 ad-hoc 签名，尚未通过 Apple Developer ID 签名和公证。
首次打开可能受到 macOS 安全检查限制。

通知和登录启动默认关闭，可在设置中启用。
问题反馈与源码：https://github.com/congim/niuma
INSTALL
  image="dist/NiuMa-macOS-$architecture-$version.dmg"
  hdiutil create -volname "牛马脱敏器 $architecture" -srcfolder "$image_root" -format UDZO -ov "$image"
  hdiutil verify "$image"
done
shasum -a 256 "dist/NiuMa-macOS-arm64-$version.dmg" "dist/NiuMa-macOS-x86_64-$version.dmg" \
  "$archive" | sed 's|  dist/|  |' > dist/SHA256SUMS.txt
xcrun lipo -info "dist/牛马脱敏器.app/Contents/MacOS/NiuMa"
echo "已生成：$PWD/dist/牛马脱敏器.app"
echo "分发包：$PWD/$archive"
echo "安装包：$PWD/dist/NiuMa-macOS-{arm64,x86_64}-$version.dmg"
