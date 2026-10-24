#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""生成 CamCoach 的 App 图标（1024×1024，无透明通道）。

为什么要自己画：App Store 上传时 Apple 会强制检查 CFBundleIconName 和
120×120 图标，没有就直接拒收（错误码 90713 / 90022）。这个检查发生在
上传阶段，编译和签名都能过，所以很容易到最后一步才发现。

图形是取景器这个意象：四角的白色取景框 + 中心青色的对焦框。
配色压得很暗，因为取景类工具的图标在深色主屏上更好认。

用法：
  python make-icon.py            # 输出到 CamCoach/Assets.xcassets
"""

import json
import os

from PIL import Image, ImageDraw

SIZE = 1024
SS = 4  # 超采样倍数，先放大画再缩，边缘才干净
S = SIZE * SS

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ASSETS = os.path.join(ROOT, "CamCoach", "Assets.xcassets")
ICONSET = os.path.join(ASSETS, "AppIcon.appiconset")


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rounded_line(d, p1, p2, width, fill):
    """圆头线段。PIL 的 line 默认是平头，端点在图标里会很生硬。"""
    d.line([p1, p2], fill=fill, width=width)
    r = width / 2
    for (x, y) in (p1, p2):
        d.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def draw_icon():
    img = Image.new("RGB", (S, S), (12, 12, 15))

    # 竖向渐变：顶部略亮，底部压暗，避免大面积死黑
    top = (30, 30, 38)
    bottom = (8, 8, 11)
    d = ImageDraw.Draw(img)
    for y in range(S):
        d.line([(0, y), (S, y)], fill=lerp(top, bottom, y / S))

    # ---- 四角取景框
    margin = int(0.165 * S)
    arm = int(0.155 * S)
    lw = int(0.034 * S)
    white = (255, 255, 255)

    corners = [
        (margin, margin, +1, +1),                      # 左上
        (S - margin, margin, -1, +1),                  # 右上
        (margin, S - margin, +1, -1),                  # 左下
        (S - margin, S - margin, -1, -1),              # 右下
    ]
    for (x, y, dx, dy) in corners:
        rounded_line(d, (x, y), (x + dx * arm, y), lw, white)
        rounded_line(d, (x, y), (x, y + dy * arm), lw, white)

    # ---- 中心对焦框（青绿色，取景器里合焦时的那个感觉）
    accent = (0, 217, 192)
    half = int(0.138 * S)
    cx = cy = S // 2
    fw = int(0.016 * S)
    gap = int(0.052 * S)   # 四角断开，像对焦框而不是普通方框

    edges = [
        # (起点, 终点) 四条边，各自留出中间的缺口
        ((cx - half, cy - half), (cx - gap, cy - half)),
        ((cx + gap, cy - half), (cx + half, cy - half)),
        ((cx - half, cy + half), (cx - gap, cy + half)),
        ((cx + gap, cy + half), (cx + half, cy + half)),
        ((cx - half, cy - half), (cx - half, cy - gap)),
        ((cx - half, cy + gap), (cx - half, cy + half)),
        ((cx + half, cy - half), (cx + half, cy - gap)),
        ((cx + half, cy + gap), (cx + half, cy + half)),
    ]
    for p1, p2 in edges:
        rounded_line(d, p1, p2, fw, accent)

    # 中心一个小点，视线落点
    dot = int(0.018 * S)
    d.ellipse([cx - dot, cy - dot, cx + dot, cy + dot], fill=accent)

    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    os.makedirs(ICONSET, exist_ok=True)

    icon = draw_icon()
    # Apple 要求 App Store 图标不能带 alpha 通道，用 RGB 存
    out_png = os.path.join(ICONSET, "icon-1024.png")
    icon.save(out_png, "PNG")
    print("图标已生成:", out_png, icon.size, icon.mode)

    # Xcode 14+ 的单尺寸写法：一张 1024 就够，其余尺寸由 Xcode 生成
    with open(os.path.join(ICONSET, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(
            {
                "images": [
                    {
                        "filename": "icon-1024.png",
                        "idiom": "universal",
                        "platform": "ios",
                        "size": "1024x1024",
                    }
                ],
                "info": {"author": "xcode", "version": 1},
            },
            f,
            indent=2,
        )
        f.write("\n")

    with open(os.path.join(ASSETS, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")

    print("Assets.xcassets 结构已就绪:", ASSETS)


if __name__ == "__main__":
    main()
