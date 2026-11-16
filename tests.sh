#!/bin/bash
# 运行纯逻辑单元测试（自然语言解析、分组、数据仓库）
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p .build

echo "▸ 编译并运行逻辑测试…"
swiftc \
  -swift-version 5 \
  -target arm64-apple-macos14.0 \
  -module-cache-path .build/mcache \
  -o .build/logictests \
  Sources/Models.swift \
  Sources/ScheduleLogic.swift \
  Sources/QuickAddParser.swift \
  Sources/TaskStore.swift \
  Tests/LogicTests/main.swift

./.build/logictests