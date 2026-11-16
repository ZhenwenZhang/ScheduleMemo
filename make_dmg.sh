#!/bin/bash
# 生成可分发的 DMG 安装包：build/ScheduleMemo-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ScheduleMemo"
DISPLAY_NAME="日程备忘录"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
DMG="build/${APP_NAME}-${VERSION}.dmg"
STAGE=".build/dmg/stage"
MOUNT_POINT=".build/dmg/mnt"
TEMP_DMG=".build/dmg/temp.dmg"
VOLNAME="${DISPLAY_NAME} ${VERSION}"

if [ ! -d "build/${APP_NAME}.app" ]; then
  echo "▸ 未找到 App，先执行 build.sh…"
  ./build.sh
fi

echo "▸ 准备 DMG 内容（${VERSION} / build ${BUILD}）…"
rm -rf ".build/dmg"
mkdir -p "$STAGE" "$MOUNT_POINT"

ditto "build/${APP_NAME}.app" "$STAGE/${APP_NAME}.app"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/安装说明.txt" <<TXT
${DISPLAY_NAME} ${VERSION} 安装说明
====================================

1. 把左侧的 ${APP_NAME}.app 拖到右侧的 Applications 文件夹；
2. 打开「应用程序」，双击 ${DISPLAY_NAME}，菜单栏右上角会出现清单图标；
3. 首次打开若提示「无法验证开发者」：
   · 在 Finder 中右键点击 App → 选择「打开」→ 再确认打开；
   · 或在终端执行：xattr -dr com.apple.quarantine /Applications/${APP_NAME}.app
4. 如需开机自启：点开面板 → 齿轮「设置」→ 打开「开机自动启动」。

数据保存在：~/Library/Application Support/ScheduleMemo/
项目主页：https://github.com/ZhenwenZhang/ScheduleMemo
TXT

# 先做可读写镜像，写入卷图标后再压缩
echo "▸ 生成镜像…"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$TEMP_DMG" >/dev/null

if [ -f Resources/AppIcon.icns ]; then
  if hdiutil attach "$TEMP_DMG" -nobrowse -readwrite -mountpoint "$MOUNT_POINT" >/dev/null 2>&1; then
    cp Resources/AppIcon.icns "$MOUNT_POINT/.VolumeIcon.icns"
    SetFile -a C "$MOUNT_POINT" 2>/dev/null || true
    # 简单整理图标位置：App 在左，Applications 在右
    if command -v osascript >/dev/null 2>&1; then
      osascript <<APPLESCRIPT >/dev/null 2>&1 || true
tell application "Finder"
  tell disk "${VOLNAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 520}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set position of item "${APP_NAME}.app" of container window to {170, 210}
    set position of item "Applications" of container window to {460, 210}
    set position of item "安装说明.txt" of container window to {315, 380}
    close
  end tell
end tell
APPLESCRIPT
    fi
    sync
    hdiutil detach "$MOUNT_POINT" >/dev/null
  else
    echo "  （卷图标设置跳过：无法挂载临时镜像）"
  fi
fi

echo "▸ 压缩为只读 DMG…"
rm -f "$DMG"
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -rf ".build/dmg"

echo "▸ 生成校验值…"
# 校验文件里只保留文件名，下载后可直接 shasum -c
( cd build && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" )
cat "${DMG}.sha256"

echo ""
echo "✅ DMG：$(pwd)/${DMG}"
echo "   大小：$(du -h "$DMG" | cut -f1)"