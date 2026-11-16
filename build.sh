#!/bin/bash
# 构建「日程备忘录」.app（无需 Xcode，仅用 Command Line Tools）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ScheduleMemo"
DISPLAY_NAME="日程备忘录"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
BIN="$APP/Contents/MacOS/$APP_NAME"

mkdir -p "$BUILD_DIR"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ 编译 Swift 源码（arm64 + x86_64 通用二进制）…"
SDK="$(xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)"

build_arch() {
  local target="$1" output="$2" cache="$3"
  swiftc \
    -O \
    -swift-version 5 \
    -target "$target" \
    -sdk "$SDK" \
    -module-cache-path "$cache" \
    -parse-as-library \
    -o "$output" \
    Sources/*.swift
}

mkdir -p .build
if build_arch "arm64-apple-macos14.0" ".build/$APP_NAME-arm64" ".build/mcache-arm64" \
   && build_arch "x86_64-apple-macos14.0" ".build/$APP_NAME-x86_64" ".build/mcache-x86_64"; then
  lipo -create -output ".build/$APP_NAME" ".build/$APP_NAME-arm64" ".build/$APP_NAME-x86_64"
  rm -f ".build/$APP_NAME-arm64" ".build/$APP_NAME-x86_64"
  echo "  架构：$(lipo -archs ".build/$APP_NAME")"
else
  echo "  ⚠️ x86_64 编译失败，回退为 arm64 单架构"
  build_arch "arm64-apple-macos14.0" ".build/$APP_NAME" ".build/mcache-arm64"
fi

mv ".build/$APP_NAME" "$BIN"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ ! -f Resources/AppIcon.icns ]; then
  if command -v python3 >/dev/null 2>&1 && python3 -c "import PIL" 2>/dev/null; then
    echo "▸ 生成应用图标…"
    python3 tools/make_icon.py
  fi
fi
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

echo "▸ Ad-hoc 签名…"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  （跳过签名，不影响本地使用）"

# 刷新 LaunchServices 缓存，让系统识别应用名与图标
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP" >/dev/null 2>&1 || true

echo ""
echo "✅ 构建完成：$(pwd)/$APP"
echo "   双击打开即可出现在菜单栏（${DISPLAY_NAME}）"