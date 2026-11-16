#!/bin/bash
# 发布新版本：构建通用 App + DMG，打 tag 推送，并创建 GitHub Release。
# 需要：已登录的 gh（gh auth login），且当前工作区已提交。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="ScheduleMemo"
REPO="ZhenwenZhang/ScheduleMemo"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
TAG="v${VERSION}"
DMG="build/${APP_NAME}-${VERSION}.dmg"

if ! command -v gh >/dev/null 2>&1; then
  echo "❌ 未安装 gh（GitHub CLI）"; exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "❌ gh 未登录，请先执行 gh auth login"; exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ 工作区有未提交修改，请先提交后再发布"; git status --short; exit 1
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "❌ tag $TAG 已存在，请先提升 Resources/Info.plist 里的版本号"; exit 1
fi

echo "▸ 构建 App（通用二进制）…"
./build.sh

echo "▸ 生成 DMG…"
./make_dmg.sh

echo "▸ 推送 main 与 tag ${TAG}…"
git push origin main
git tag -a "$TAG" -m "Release ${TAG}"
git push origin "$TAG"

NOTES_FILE="docs/release-notes-${TAG}.md"
if [ -f "$NOTES_FILE" ]; then
  NOTES_ARGS=(--notes-file "$NOTES_FILE")
else
  NOTES_ARGS=(--generate-notes)
fi

echo "▸ 创建 GitHub Release…"
gh release create "$TAG" "$DMG" "${DMG}.sha256" \
  --repo "$REPO" \
  --title "日程备忘录 ${TAG}" \
  "${NOTES_ARGS[@]}"

echo ""
echo "✅ 发布完成：https://github.com/${REPO}/releases/tag/${TAG}"