#!/usr/bin/env python3
"""生成 AppIcon.icns（无需 Xcode，使用 Pillow + iconutil）。"""

import os
import subprocess
from PIL import Image, ImageDraw

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES = os.path.join(BASE, "Resources")
ICONSET = os.path.join(BASE, ".build", "AppIcon.iconset")
ICNS = os.path.join(RESOURCES, "AppIcon.icns")

SCALE = 2
SIZE = 1024
W = SIZE * SCALE


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def make_icon():
    # 圆角方形渐变底
    top = (86, 128, 255)
    bottom = (46, 74, 214)
    grad = Image.new("RGB", (W, W), top)
    gd = ImageDraw.Draw(grad)
    for y in range(W):
        gd.line([(0, y), (W, y)], fill=lerp(top, bottom, y / W))

    # 柔和高光
    glow = Image.new("L", (W, W), 0)
    ImageDraw.Draw(glow).ellipse([-W // 3, -W // 2, W * 5 // 4, W // 2], fill=70)
    white = Image.new("RGB", (W, W), (255, 255, 255))
    grad = Image.composite(white, grad, glow.point(lambda v: int(v * 0.45)))

    mask = rounded_mask(W, int(W * 0.225))
    icon = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    icon.paste(grad, (0, 0), mask)

    draw = ImageDraw.Draw(icon)
    s = W / 1024.0

    # 白色日历卡片
    card = [int(206 * s), int(232 * s), int(818 * s), int(806 * s)]
    draw.rounded_rectangle(card, radius=int(58 * s), fill=(255, 255, 255, 242))

    # 卡片顶部色条
    draw.rounded_rectangle(
        [card[0], card[1], card[2], int(330 * s)],
        radius=int(58 * s),
        fill=(35, 60, 150, 255),
    )
    draw.rectangle([card[0], int(280 * s), card[2], int(330 * s)], fill=(35, 60, 150, 255))

    # 顶部两个小圆点（挂环）
    for cx in (int(410 * s), int(614 * s)):
        draw.rounded_rectangle(
            [cx - int(16 * s), int(190 * s), cx + int(16 * s), int(292 * s)],
            radius=int(16 * s),
            fill=(226, 234, 255, 255),
        )

    # 三条待办：勾选圆 + 文字条
    rows = [
        (int(400 * s), (255, 255, 255)),
        (int(512 * s), (255, 255, 255)),
        (int(624 * s), (214, 224, 255)),
    ]
    for index, (cy, color) in enumerate(rows):
        r = int(30 * s)
        cx = int(282 * s)
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)
        if index < 2:
            draw.line(
                [(cx - int(14 * s), cy), (cx - int(2 * s), cy + int(13 * s)), (cx + int(16 * s), cy - int(13 * s))],
                fill=(46, 74, 214),
                width=int(11 * s),
                joint="curve",
            )
        bar_color = (60, 84, 160, 255) if index < 2 else (200, 210, 240, 255)
        draw.rounded_rectangle(
            [int(344 * s), cy - int(13 * s), int(740 * s), cy + int(13 * s)],
            radius=int(13 * s),
            fill=bar_color,
        )

    return icon.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    os.makedirs(RESOURCES, exist_ok=True)
    icon = make_icon()

    if os.path.isdir(ICONSET):
        subprocess.run(["rm", "-rf", ICONSET], check=True)
    os.makedirs(ICONSET, exist_ok=True)

    # macOS iconset 需要的尺寸
    for size in (16, 32, 64, 128, 256, 512, 1024):
        icon.resize((size, size), Image.LANCZOS).save(
            os.path.join(ICONSET, f"icon_{size}x{size}.png")
        )
        if size <= 512:
            icon.resize((size * 2, size * 2), Image.LANCZOS).save(
                os.path.join(ICONSET, f"icon_{size}x{size}@2x.png")
            )

    subprocess.run(["iconutil", "-c", "icns", ICONSET, "-o", ICNS], check=True)
    print(f"✅ 图标已生成：{ICNS}")


if __name__ == "__main__":
    main()