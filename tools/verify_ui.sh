#!/bin/bash
# UI 验收：逐个场景启动真实 .app，截图并用 OCR 校验画面文案。
# 依赖：python3 + .build/pylibs（见 tools/README），仅开发验证用。
set -uo pipefail
cd "$(dirname "$0")/.."

APP="$PWD/build/ScheduleMemo.app/Contents/MacOS/ScheduleMemo"

# 清掉上一轮可能残留的开发版实例（不动已安装到 ~/Applications 的正式版）
pkill -f "Documents/ToDoList/build/ScheduleMemo.app" 2>/dev/null || true
sleep 1
OUT="$PWD/.build/verify"
rm -rf "$OUT"
mkdir -p "$OUT/shots" "$OUT/data" "$OUT/reports"

pass=0
fail=0

say() { printf '%s\n' "$*"; }
ok() { pass=$((pass + 1)); say "  ✅ $1"; }
ng() { fail=$((fail + 1)); say "  ❌ $1"; }

# 启动一个场景：$1 名称 $2 数据类型 $3 截图延时（秒） $4 自动退出（秒） 其余为环境变量
launch() {
  local name="$1" kind="$2" shot_delay="$3" quit_after="$4"
  shift 4
  python3 tools/seed_test_data.py "$kind" "$OUT/data/$name"
  env "SCHEDULEMEMO_DATA_DIR=$OUT/data/$name" \
      "SCHEDULEMEMO_DEBUG_REPORT=$OUT/reports/$name.json" \
      "SCHEDULEMEMO_AUTO_QUIT_SECONDS=$quit_after" \
      "SCHEDULEMEMO_DISABLE_AUTO_CLOSE=1" \
      "$@" "$APP" > "$OUT/$name.log" 2>&1 &
  local pid=$!
  sleep "$shot_delay"
  screencapture -x "$OUT/shots/$name.png"
  wait "$pid" 2>/dev/null
}

check_ui() {
  local name="$1" window_class="$2"
  shift 2
  python3 tools/ui_check.py --image "$OUT/shots/$name.png" \
      --report "$OUT/reports/$name.json" --label shown \
      --window-class "$window_class" --expect "$@" \
      --save-crop "$OUT/shots/$name-crop.png" > "$OUT/$name.check.txt" 2>&1
  local rc=$?
  if [ $rc -eq 0 ]; then ok "${name}：$(tail -1 "$OUT/$name.check.txt")"; else ng "$name"; sed 's/^/     /' "$OUT/$name.check.txt"; fi
}

check_menu_text() {
  local name="$1"; shift
  python3 - "$OUT/shots/$name.png" "$@" <<'PY' > "$OUT/$name.menu.txt" 2>&1
import re
import sys
sys.path.insert(0, ".build/pylibs")
from PIL import Image
from rapidocr_onnxruntime import RapidOCR

image_path = sys.argv[1]
expected = sys.argv[2:]
img = Image.open(image_path).convert("RGB")
w, h = img.size
crop = img.crop((int(w * 0.45), 0, w, 34))
crop = crop.resize((crop.width * 2, crop.height * 2), Image.LANCZOS)
tmp = "/tmp/menu_ocr.png"
crop.save(tmp)
res, _ = RapidOCR()(tmp)
text = re.sub(r"\s", "", "".join(t for _, t, _ in (res or [])))
missing = [e for e in expected if re.sub(r"\s", "", e) not in text]
print("菜单栏OCR:", text)
if missing:
    print("FAIL missing:", missing)
    sys.exit(1)
print("PASS")
PY
  if [ $? -eq 0 ]; then ok "${name} 菜单栏：$(tail -1 "$OUT/$name.menu.txt")"; else ng "${name} 菜单栏"; sed 's/^/     /' "$OUT/$name.menu.txt"; fi
}

check_report() {
  local name="$1" expr="$2" label="$3"
  local result
  result=$(python3 - "$OUT/reports/$name.json" "$expr" <<'PY'
import json, sys
path, expr = sys.argv[1], sys.argv[2]
data = json.load(open(path))
entry = next((r for r in data.get("reports", []) if r.get("label") == "shown"), data["reports"][-1])
print(bool(eval(expr, {"r": entry, "data": data})))
PY
)
  if [ "$result" = "True" ]; then ok "$name 报告：$label"; else ng "$name 报告：$label"; fi
}

say "▶ 场景 1：主面板（含逾期 / 今天 / 已完成）"
launch popover_demo demo 3.4 8 SCHEDULEMEMO_SHOW_POPOVER_ON_LAUNCH=1
check_ui popover_demo _NSPopoverWindow "日程备忘录" "新建" "今天" "7天内" "全部" "已逾期" "今天 · 11月13日" "18:00" "10:30" "14:00" "全天" "已完成" "未完成 7"
check_report popover_demo 'r["statusTitle"] == "3 项逾期"' "菜单栏显示逾期数量"
check_menu_text popover_demo "3项逾期"
check_report popover_demo 'r["popoverShown"] and r["popoverContentWidth"] == 240 and 380 <= r["popoverContentHeight"] <= 540' "面板尺寸合理（宽 240）"

say "▶ 场景 2：新建日程表单"
launch editor demo 3.6 8 SCHEDULEMEMO_SHOW_POPOVER_ON_LAUNCH=1 SCHEDULEMEMO_OPEN_EDITOR=1
check_ui editor _NSPopoverWindow "新建日程" "日期" "快捷" "今天" "明天" "后天" "下周一" "时间" "全天" "提醒" "优先级" "备注" "取消"
check_report editor 'r["popoverContentHeight"] == 556' "表单高度 556"

say "▶ 场景 3：设置页"
launch settings demo 3.6 8 SCHEDULEMEMO_SHOW_POPOVER_ON_LAUNCH=1 SCHEDULEMEMO_OPEN_SETTINGS=1
check_ui settings _NSPopoverWindow "设置" "菜单栏显示" "显示内容" "提醒" "默认提前" "通用" "开机自动启动" "数据" "关于" "快捷键"

say "▶ 场景 4：空状态"
launch empty empty 3.4 8 SCHEDULEMEMO_SHOW_POPOVER_ON_LAUNCH=1
check_ui empty _NSPopoverWindow "今天暂无安排" "添加日程" "回车即可添加" "未完成 0 项"

say "▶ 场景 5：菜单栏显示下一项日程"
launch future future 3.4 8 SCHEDULEMEMO_SHOW_POPOVER_ON_LAUNCH=1 SCHEDULEMEMO_INITIAL_FILTER=week
check_report future 'r["statusTitle"].startswith("明天 09:00 交季度总结")' "菜单栏文案：明天 09:00 交季度总结"
check_menu_text future "明天09:00交季度总结"
check_ui future _NSPopoverWindow "明天 · 11月14日" "交季度总结" "09:00" "整理书架" "牙医复诊" "全天" "未完成 3 项"

say "▶ 场景 6：点击图标开关面板（同一代码路径）"
launch smoke demo 4.0 7 SCHEDULEMEMO_SMOKE_CLICK=1
check_report smoke 'data.get("smoke", {}).get("clickPathOK") is True' "点击打开 / 再次点击关闭"

say "▶ 场景 7：输入框快速添加（模拟键入「明天 10:00 评审」并回车）"
launch typed empty 3.8 8 SCHEDULEMEMO_SHOW_POPOVER_ON_LAUNCH=1 SCHEDULEMEMO_SMOKE_TYPE=1
check_report typed 'data.get("typing", {}).get("itemCount") == 1 and data["typing"].get("firstTitle") == "评审" and data["typing"].get("firstAllDay") is False' "解析并新增「评审」"
check_ui typed _NSPopoverWindow "评审" "明天" "10:00" "已添加"

say "▶ 场景 8：Esc 收起面板"
launch esc_close demo 3.6 8 SCHEDULEMEMO_SHOW_POPOVER_ON_LAUNCH=1 SCHEDULEMEMO_SMOKE_ESCAPE=1
check_report esc_close 'data.get("escape", {}).get("shownAfterEscape") is False' "Esc 后面板已收起"

say "▶ 场景 9：Esc 退出新建表单（面板保留）"
launch esc_editor demo 4.2 9 SCHEDULEMEMO_SHOW_POPOVER_ON_LAUNCH=1 SCHEDULEMEMO_OPEN_EDITOR=1 SCHEDULEMEMO_SMOKE_ESCAPE_EDITOR=1
check_report esc_editor 'data.get("escapeEditor", {}).get("shownAfterEscape") is True and data["escapeEditor"].get("contentHeight", 0) < 556' "Esc 退出表单、面板仍在"
check_ui esc_editor _NSPopoverWindow "已逾期" "今天 · 11月13日"

say "▶ 场景 10：深色模式"
launch dark demo 3.6 8 SCHEDULEMEMO_SHOW_POPOVER_ON_LAUNCH=1 SCHEDULEMEMO_DARK=1
python3 tools/ui_check.py --image "$OUT/shots/dark.png" --report "$OUT/reports/dark.json" \
    --label shown --window-class _NSPopoverWindow --max-luma 140 \
    --expect "日程备忘录" "已逾期" "今天 · 11月13日" "未完成 7" \
    --save-crop "$OUT/shots/dark-crop.png" > "$OUT/dark.check.txt" 2>&1
if [ $? -eq 0 ]; then ok "dark：$(tail -1 "$OUT/dark.check.txt")"; else ng "dark"; sed 's/^/     /' "$OUT/dark.check.txt"; fi

say "▶ 场景 11：右键菜单内容"
launch menu demo 1.6 4
check_report menu 'all(t in r["contextMenuItems"] for t in ["打开日程面板", "新建日程…", "设置…", "打开数据文件夹", "退出日程备忘录"])' "右键菜单项齐全"
check_report menu 'any("逾期" in t for t in r["contextMenuItems"] if t)' "右键菜单含今日概况"

say "▶ 场景 12：深色模式下的新建表单"
launch dark_editor demo 3.8 9 SCHEDULEMEMO_SHOW_POPOVER_ON_LAUNCH=1 SCHEDULEMEMO_OPEN_EDITOR=1 SCHEDULEMEMO_DARK=1
python3 tools/ui_check.py --image "$OUT/shots/dark_editor.png" --report "$OUT/reports/dark_editor.json" \
    --label shown --window-class _NSPopoverWindow --max-luma 140 \
    --expect "新建日程" "日期" "时间" "提醒" "优先级" "备注" "取消" \
    --save-crop "$OUT/shots/dark_editor-crop.png" > "$OUT/dark_editor.check.txt" 2>&1
if [ $? -eq 0 ]; then ok "dark_editor：$(tail -1 "$OUT/dark_editor.check.txt")"; else ng "dark_editor"; sed 's/^/     /' "$OUT/dark_editor.check.txt"; fi

say "▶ 场景 13：菜单栏显示模式切换（设置即时生效）"
launch menubar today 3.4 6 SCHEDULEMEMO_SMOKE_MENUBAR=1
check_report menubar 'data.get("menuBarModes", {}).get("nextModeTitle") == "整理桌面"' "下一项模式：整理桌面"
check_report menubar 'data.get("menuBarModes", {}).get("countModeTitle") == "1"' "数量模式：1"
check_report menubar 'data.get("menuBarModes", {}).get("iconOnlyTitle") == ""' "仅图标模式：无文字"
check_report menubar 'data.get("menuBarModes", {}).get("nextModeTitle") == "整理桌面"' "切回下一项模式"

say "▶ 场景 14：到期提醒浮窗"
launch reminder empty 3.4 8 SCHEDULEMEMO_TEST_REMINDER=1
check_ui reminder ReminderPanel "日程提醒" "项目周会" "今天" "会议室 A" "完成" "10 分钟后"

say ""
say "=============================="
say "UI 验收：通过 $pass 项，失败 $fail 项"
say "截图目录：$OUT/shots"
[ "$fail" -eq 0 ]