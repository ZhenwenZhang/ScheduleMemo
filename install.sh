#!/bin/bash
# 把「日程备忘录」安装到 ~/Applications 并启动
set -euo pipefail
cd "$(dirname "$0")"

APP="build/ScheduleMemo.app"
DEST_DIR="${HOME}/Applications"
DEST="$DEST_DIR/ScheduleMemo.app"

if [ ! -d "$APP" ]; then
  echo "▸ 未找到构建产物，先执行构建…"
  ./build.sh
fi

echo "▸ 退出正在运行的实例…"
pkill -f "ScheduleMemo.app/Contents/MacOS/ScheduleMemo" 2>/dev/null || true
sleep 0.6

echo "▸ 复制到 ${DEST_DIR}…"
mkdir -p "$DEST_DIR"
rm -rf "$DEST"
ditto "$APP" "$DEST"
codesign --force --sign - "$DEST" >/dev/null 2>&1 || true

echo "▸ 注册到 LaunchServices…"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$DEST" >/dev/null 2>&1 || true

echo "▸ 启动…"
open "$DEST"

echo ""
echo "✅ 已安装：$DEST"
echo "   菜单栏右上角会出现清单图标，点击即可使用。"
echo "   如需开机自启：点开面板 → 齿轮「设置」→ 打开「开机自动启动」。"
echo ""
echo "卸载：退出应用后，删除上面这个 .app 与 ~/Library/Application Support/ScheduleMemo 即可。"