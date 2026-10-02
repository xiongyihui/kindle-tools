#!/bin/zsh
# gen-flashcards.sh — 婴儿黑白视觉训练卡 (20 张, 高对比度简笔图形)
# 输出 flashcards/frame_{01..20}.png (758×1024, 老机适用; 环境变量 W/H/OUT 可覆盖)
# 部署: tar czf - -C flashcards . | ssh root@<ip> 'rm -f /mnt/us/photo-kit/photos/*; tar xzf - -C /mnt/us/photo-kit/photos'
set -e
cd "$(dirname "$0")"; mkdir -p "${OUT:-flashcards}"
python3 - <<'PYEOF'
from PIL import Image, ImageDraw, ImageFont
import math, os

W = int(os.environ.get('W', 758)); H = int(os.environ.get('H', 1024))
OUT = os.environ.get('OUT', 'flashcards')
CX, CY = W // 2, int(H * 0.44)          # 图形中心 (上部留少量边, 下方留名称)
BASE = int(W * 0.40)                    # 图形基准半径
FONT = "/System/Library/Fonts/STHeiti Light.ttc"

def new():
    img = Image.new("L", (W, H), 255)
    d = ImageDraw.Draw(img)
    return img, d

def label(d, name):
    f = ImageFont.truetype(FONT, int(W * 0.058))
    tw = d.textlength(name, font=f)
    d.text(((W - tw) / 2, H * 0.90), name, fill=0, font=f)

def circle(d, cx, cy, r, fill=0, outline=None, width=1):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill, outline=outline, width=width)

def poly_star(d, cx, cy, r_out, r_in, n=5, fill=0):
    pts = []
    for i in range(2 * n):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(-90 + i * 180 / n)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    d.polygon(pts, fill=fill)

def card(fn, name, draw_fn):
    img, d = new()
    draw_fn(d)
    label(d, name)
    img.save(f"{OUT}/{fn}")
    print(fn, name)

B = BASE  # 简写

# 1 月亮: 黑圆被白圆偏移覆盖成月牙
def moon(d):
    circle(d, CX - B * 0.15, CY, B)
    circle(d, CX + B * 0.38, CY - B * 0.22, int(B * 0.92), fill=255)
card("frame_01.png", "月亮", moon)

# 2 太阳: 实心圆 + 12 道光芒
def sun(d):
    for i in range(12):
        a = math.radians(i * 30)
        d.line([CX + B * 0.55 * math.cos(a), CY + B * 0.55 * math.sin(a),
                CX + B * 0.95 * math.cos(a), CY + B * 0.95 * math.sin(a)],
               fill=0, width=int(B * 0.09))
    circle(d, CX, CY, int(B * 0.5))
card("frame_02.png", "太阳", sun)

# 3 苹果: 双圆果体 + 柄 + 斜叶
def apple(d):
    circle(d, CX - B * 0.30, CY + B * 0.12, int(B * 0.55))
    circle(d, CX + B * 0.30, CY + B * 0.12, int(B * 0.55))
    d.rectangle([CX - B * 0.45, CY - B * 0.35, CX + B * 0.45, CY + B * 0.4], fill=0)
    d.line([CX, CY - B * 0.35, CX + B * 0.05, CY - B * 0.75], fill=0, width=int(B * 0.09))
    d.polygon([(CX, CY - B * 0.72), (CX + B * 0.5, CY - B * 0.92),
               (CX + B * 0.45, CY - B * 0.55)], fill=0)
card("frame_03.png", "苹果", apple)

# 4 香蕉: 粗弯月身 (两圆弧夹出的月牙, 两端收尖)
def banana(d):
    box = [CX - B, CY - B * 0.6, CX + B, CY + B * 1.2]
    d.pieslice(box, 30, 150, fill=0)
    d.pieslice(box, 55, 125, fill=255)   # 挖窄些 → 月牙更粗
card("frame_04.png", "香蕉", banana)

# 5 五角星
card("frame_05.png", "星星", lambda d: poly_star(d, CX, CY, B, B * 0.42))

# 6 爱心: 双圆 + 下三角
def heart(d):
    r = int(B * 0.42)
    circle(d, CX - r, CY - B * 0.18, r)
    circle(d, CX + r, CY - B * 0.18, r)
    d.polygon([(CX - 2 * r - B * 0.04, CY + B * 0.02), (CX + 2 * r + B * 0.04, CY + B * 0.02),
               (CX, CY + B * 0.85)], fill=0)
    circle(d, CX - r, CY - B * 0.18, int(r * 0.35), fill=255)
card("frame_06.png", "爱心", heart)

# 7 同心圆靶心
def target(d):
    for k, r in enumerate([B, int(B * 0.72), int(B * 0.45), int(B * 0.2)]):
        if k % 2 == 0:
            circle(d, CX, CY, r, fill=0)
        else:
            circle(d, CX, CY, r, fill=255)
card("frame_07.png", "同心圆", target)

# 8 三角形
def tri(d):
    d.polygon([(CX, CY - B * 0.85), (CX - B, CY + B * 0.6), (CX + B, CY + B * 0.6)], fill=0)
card("frame_08.png", "三角形", tri)

# 9 嵌套方形
def squares(d):
    s = B
    d.rectangle([CX - s, CY - s, CX + s, CY + s], fill=0)
    d.rectangle([CX - s * 0.66, CY - s * 0.66, CX + s * 0.66, CY + s * 0.66], fill=255)
    d.rectangle([CX - s * 0.33, CY - s * 0.33, CX + s * 0.33, CY + s * 0.33], fill=0)
card("frame_09.png", "方形", squares)

# 10 雨伞: 上半圆伞面 + 白分瓣 + 柄
def umbrella(d):
    d.pieslice([CX - B, CY - B * 0.55, CX + B, CY + B * 0.9], 180, 360, fill=0)
    for dx in (-B * 0.5, 0, B * 0.5):
        d.line([CX + dx, CY - B * 0.55, CX + dx, CY + B * 0.17], fill=255, width=int(B * 0.06))
    d.line([CX, CY + B * 0.17, CX, CY + B * 0.8], fill=0, width=int(B * 0.09))
    d.arc([CX - B * 0.3, CY + B * 0.55, CX + B * 0.3, CY + B * 1.05], 0, 180, fill=0, width=int(B * 0.09))
card("frame_10.png", "雨伞", umbrella)

# 11 小鱼: 椭圆身 + 三角尾 + 白眼
def fish(d):
    d.ellipse([CX - B * 0.85, CY - B * 0.45, CX + B * 0.45, CY + B * 0.45], fill=0)
    d.polygon([(CX + B * 0.45, CY), (CX + B * 0.95, CY - B * 0.5),
               (CX + B * 0.95, CY + B * 0.5)], fill=0)
    circle(d, int(CX - B * 0.5), CY, int(B * 0.12), fill=255)
card("frame_11.png", "小鱼", fish)

# 12 蝴蝶: 四翅 + 身 + 触角
def butterfly(d):
    circle(d, int(CX - B * 0.5), int(CY - B * 0.35), int(B * 0.42))
    circle(d, int(CX + B * 0.5), int(CY - B * 0.35), int(B * 0.42))
    circle(d, int(CX - B * 0.45), int(CY + B * 0.32), int(B * 0.32))
    circle(d, int(CX + B * 0.45), int(CY + B * 0.32), int(B * 0.32))
    d.ellipse([CX - B * 0.1, CY - B * 0.55, CX + B * 0.1, CY + B * 0.6], fill=0)
    d.line([CX - B * 0.05, CY - B * 0.55, CX - B * 0.35, CY - B * 0.9], fill=0, width=int(B * 0.06))
    d.line([CX + B * 0.05, CY - B * 0.55, CX + B * 0.35, CY - B * 0.9], fill=0, width=int(B * 0.06))
card("frame_12.png", "蝴蝶", butterfly)

# 13 小花: 中心圆 + 6 瓣
def flower(d):
    for i in range(6):
        a = math.radians(i * 60)
        circle(d, int(CX + B * 0.55 * math.cos(a)), int(CY + B * 0.55 * math.sin(a)), int(B * 0.32))
    circle(d, CX, CY, int(B * 0.3), fill=255, outline=0, width=int(B * 0.08))
card("frame_13.png", "小花", flower)

# 14 大树: 两层三角 + 树干
def tree(d):
    d.polygon([(CX, CY - B * 0.9), (CX - B * 0.62, CY - B * 0.1), (CX + B * 0.62, CY - B * 0.1)], fill=0)
    d.polygon([(CX, CY - B * 0.55), (CX - B * 0.8, CY + B * 0.35), (CX + B * 0.8, CY + B * 0.35)], fill=0)
    d.rectangle([CX - B * 0.14, CY + B * 0.35, CX + B * 0.14, CY + B * 0.95], fill=0)
card("frame_14.png", "大树", tree)

# 15 皮球: 黑圆 + 白十字白环
def ball(d):
    circle(d, CX, CY, B)
    d.line([CX - B, CY, CX + B, CY], fill=255, width=int(B * 0.07))
    d.line([CX, CY - B, CX, CY + B], fill=255, width=int(B * 0.07))
    d.arc([CX - B * 0.45, CY - B * 0.45, CX + B * 0.45, CY + B * 0.45], 0, 360, fill=255, width=int(B * 0.07))
card("frame_15.png", "皮球", ball)

# 16 礼帽: 帽筒 + 帽檐 + 白带
def hat(d):
    d.rectangle([CX - B * 0.42, CY - B * 0.75, CX + B * 0.42, CY + B * 0.25], fill=0)
    d.rectangle([CX - B, CY + B * 0.25, CX + B, CY + B * 0.42], fill=0)
    d.rectangle([CX - B * 0.42, CY - B * 0.05, CX + B * 0.42, CY + B * 0.1], fill=255)
card("frame_16.png", "礼帽", hat)

# 17 杯子: 杯身 + 把手
def cup(d):
    d.rectangle([CX - B * 0.55, CY - B * 0.5, CX + B * 0.55, CY + B * 0.55], fill=0)
    d.arc([CX + B * 0.3, CY - B * 0.25, CX + B * 1.05, CY + B * 0.5], 270, 90, fill=0, width=int(B * 0.12))
    d.rectangle([CX - B * 0.55, CY + B * 0.55, CX + B * 0.55, CY + B * 0.65], fill=0)
card("frame_17.png", "杯子", cup)

# 18 勺子: 椭圆头 + 柄
def spoon(d):
    d.ellipse([CX - B * 0.32, CY - B * 0.85, CX + B * 0.32, CY - B * 0.05], fill=0)
    d.rectangle([CX - B * 0.09, CY - B * 0.1, CX + B * 0.09, CY + B * 0.9], fill=0)
    circle(d, CX, CY - B * 0.45, int(B * 0.16), fill=255)
card("frame_18.png", "勺子", spoon)

# 19 房子: 三角顶 + 方身 + 门
def house(d):
    d.polygon([(CX, CY - B * 0.85), (CX - B * 0.85, CY - B * 0.05), (CX + B * 0.85, CY - B * 0.05)], fill=0)
    d.rectangle([CX - B * 0.6, CY - B * 0.05, CX + B * 0.6, CY + B * 0.8], fill=0)
    d.rectangle([CX - B * 0.18, CY + B * 0.2, CX + B * 0.18, CY + B * 0.8], fill=255)
card("frame_19.png", "房子", house)

# 20 棋盘格
def checker(d):
    n, s = 4, B // 2
    x0, y0 = CX - 2 * s, CY - 2 * s
    for r in range(n):
        for c in range(n):
            if (r + c) % 2 == 0:
                d.rectangle([x0 + c * s, y0 + r * s, x0 + (c + 1) * s, y0 + (r + 1) * s], fill=0)
card("frame_20.png", "棋盘格", checker)

print(f"完成: 20 张 → {OUT}/ ({W}x{H})")
PYEOF
