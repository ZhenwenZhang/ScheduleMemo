#!/usr/bin/env python3
"""UI 验收脚本：裁剪截图 → OCR → 校验文案与边界。

用法：
  python3 tools/ui_check.py --image shot.png --report report.json --label shown \
      --window-class _NSPopoverWindow --expect "日程备忘录" "已逾期" ...
"""

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".build", "pylibs"))

from rapidocr_onnxruntime import RapidOCR  # noqa: E402
from PIL import Image  # noqa: E402

_engine = None


def engine():
    global _engine
    if _engine is None:
        _engine = RapidOCR()
    return _engine


def crop_box(screen_h, frame):
    """把 AppKit 窗口坐标（左下原点）转换成截图坐标（左上原点）。"""
    x = frame["x"]
    y = screen_h - (frame["y"] + frame["h"])
    return (round(x), round(y), round(x + frame["w"]), round(y + frame["h"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True)
    ap.add_argument("--report", required=True)
    ap.add_argument("--label", default="shown")
    ap.add_argument("--window-class", default="_NSPopoverWindow")
    ap.add_argument("--expect", nargs="*", default=[])
    ap.add_argument("--forbid", nargs="*", default=[])
    ap.add_argument("--padding", type=int, default=0)
    ap.add_argument("--max-luma", type=float, default=None, help="要求面板平均亮度不超过该值（深色模式）")
    ap.add_argument("--save-crop")
    args = ap.parse_args()

    report = json.load(open(args.report))
    entry = None
    for item in report.get("reports", []):
        if item.get("label") == args.label:
            entry = item
            break
    if entry is None:
        print(f"❌ 报告里没有 label={args.label}")
        return 1

    screen_h = entry.get("screenHeight", 1080)
    target = None
    for window in entry.get("windows", []):
        if window["class"] == args.window_class:
            target = window
            break
    if target is None:
        print(f"❌ 找不到 {args.window_class} 窗口；现有：{[w['class'] for w in entry.get('windows', [])]}")
        return 1

    frame = target["frame"]
    box = crop_box(screen_h, frame)
    image = Image.open(args.image).convert("RGB")
    pad = args.padding
    box = (max(0, box[0] - pad), max(0, box[1] - pad), min(image.width, box[2] + pad), min(image.height, box[3] + pad))
    crop = image.crop(box)
    scale = 2
    big = crop.resize((crop.width * scale, crop.height * scale), Image.LANCZOS)
    tmp_path = f"/tmp/ui_check_{os.getpid()}.png"
    big.save(tmp_path)
    if args.save_crop:
        big.save(args.save_crop)

    results, _ = engine()(tmp_path)
    luma = None
    if args.max_luma is not None:
        inset = 16
        inner = crop.crop((inset, inset, max(inset + 1, crop.width - inset), max(inset + 1, crop.height - inset))).convert("RGB")
        pixels = list(inner.getdata())
        if pixels:
            luma = sum(0.299 * r + 0.587 * g + 0.114 * b for r, g, b in pixels) / len(pixels)

    lines = []
    for quad, text, score in (results or []):
        xs = [p[0] / scale for p in quad]
        ys = [p[1] / scale for p in quad]
        lines.append({
            "text": text,
            "score": score,
            "x": min(xs), "y": min(ys),
            "w": max(xs) - min(xs), "h": max(ys) - min(ys),
        })
    os.unlink(tmp_path)

    lines.sort(key=lambda l: (round(l["y"] / 6), l["x"]))
    joined_raw = "\n".join(l["text"] for l in lines)
    # OCR 对空格/间隔符不稳定，比对前统一去掉空白与常见分隔符
    joined = re.sub(r"[\s·:：，,、。.]", "", joined_raw)

    print(f"📷 {os.path.basename(args.image)} → {args.window_class} @ {box}（{crop.width}×{crop.height}pt）")
    print("   OCR:", " | ".join(l["text"] for l in lines[:60]))

    failures = []
    if luma is not None:
        print(f"   面板平均亮度：{luma:.1f}（要求 ≤ {args.max_luma}）")
        if luma > args.max_luma:
            failures.append(f"面板不够暗：{luma:.1f}")
    for expected in args.expect:
        if re.sub(r"[\s·:：，,、。.]", "", expected) not in joined:
            failures.append(f"缺少文案：{expected}")
    for forbidden in args.forbid:
        if re.sub(r"[\s·:：，,、。.]", "", forbidden) in joined:
            failures.append(f"不应出现：{forbidden}")

    # 边界检查：所有文字都应落在窗口内（允许 2pt 误差）
    for line in lines:
        if line["x"] < -2 or line["y"] < -2 or line["x"] + line["w"] > crop.width + 2 or line["y"] + line["h"] > crop.height + 2:
            failures.append(f"文字越界：{line['text']}")
            break

    if failures:
        print("❌ " + "；".join(failures))
        return 1
    print(f"✅ 校验通过（{len(args.expect)} 项文案）")
    return 0


if __name__ == "__main__":
    sys.exit(main())