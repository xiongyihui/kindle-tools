#!/bin/zsh
# gen-flashcards.sh — 婴儿黑白视觉训练卡 (50 张, 758×1024, 纯黑白, 电子墨水屏适用)
#
# 实现方式: 逐张用无头 Chrome 渲染 flashcards.html?n=N 并截图。
# 输出: flashcards/frame_{01..50}.png
# 部署: COPYFILE_DISABLE=1 tar czf - -C flashcards . | ssh root@<ip> \
#         'rm -f /mnt/us/photo-kit/photos/*; tar xzf - -C /mnt/us/photo-kit/photos && rm -f /mnt/us/photo-kit/photos/._*'
#
# 校验 (PIL 像素实测, 不靠肉眼):
#   1. 尺寸必须 758×1024
#   2. 背景纯度: 白卡四角≈255 / 黑卡四角≈0 (容差 6)
#   3. 图形墨迹存在且落在安全区 x∈[80,678] y∈[64,880] 内
#   4. 标注带 y∈[900,1010] 有墨迹, 且标注墨迹水平中心 = 379 (±5)
#   5. 图形与标注之间 y∈[820,904] 必须干净 (图不侵入标注带)
#   6. 黑底卡序号与 flashcards.html 的 DARK 集一致, 且互不相邻

set -e
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SRC="$(pwd)/flashcards.html"
OUT="flashcards"
N=50
mkdir -p "$OUT"

# 黑底卡序号 (与 flashcards.html 的 DARK 集保持一致)
DARK_LIST="7 16 18 20 24 26 28 31 35 37 48"
typeset -A DARK; for d in ${(s: :)DARK_LIST}; do DARK[$d]=1; done

# 循环导出: ?n=N 让页面只渲染第 N 张, 视口即卡片尺寸
for n in $(seq 1 $N); do
  nn=$(printf "%02d" "$n")
  echo "导出 ${OUT}/frame_${nn}.png (卡 ${n}/${N}) ..."
  "$CHROME" --headless --disable-gpu \
    --force-device-scale-factor=1 \
    --hide-scrollbars --window-size=758,1024 \
    --virtual-time-budget=1500 \
    --screenshot="${OUT}/frame_${nn}.png" \
    "file://${SRC}?n=${n}" >/dev/null 2>&1
done

# ---- PIL 像素实测校验 ----
python3 - "$N" "$DARK_LIST" <<'PY'
import sys
from PIL import Image

N = int(sys.argv[1])
dark_set = set(int(x) for x in sys.argv[2].split())
W, H = 758, 1024
SAFE_X = (80, 678)     # 图形安全区
SAFE_Y = (64, 880)
GAP = (820, 904)       # 图形与标注之间的空带
LABEL = (900, 1010)    # 标注带
CX = 379

def ink_mask(im, dark_card):
    """返回'有字的墨'布尔阵: 白卡找暗像素, 黑卡找亮像素"""
    g = im.convert("L")
    px = g.load()
    return g, px

ok = True
for i in range(1, N + 1):
    p = f"flashcards/frame_{i:02d}.png"
    try:
        im = Image.open(p)
    except Exception as e:
        print(f"FAIL {p} 无法读取: {e}"); ok = False; continue
    dark_card = i in dark_set
    g = im.convert("L"); px = g.load()
    errs = []
    if im.size != (W, H):
        errs.append(f"尺寸{im.size}")
    else:
        # 背景纯度: 四角
        corners = [px[4,4], px[W-5,4], px[4,H-5], px[W-5,H-5]]
        if dark_card:
            if max(corners) > 6: errs.append(f"黑底不纯{corners}")
        else:
            if min(corners) < 249: errs.append(f"白底不纯{corners}")
        # 墨迹判定: 白卡<128, 黑卡>190
        if dark_card:
            has_ink = lambda v: v > 190
        else:
            has_ink = lambda v: v < 128
        art_ink, xs, ys = 0, [], []
        for y in range(SAFE_Y[0], GAP[0], 2):
            for x in range(0, W, 2):
                if has_ink(px[x, y]):
                    art_ink += 1; xs.append(x); ys.append(y)
        if art_ink < 200:
            errs.append("图形墨迹过少")
        else:
            if min(xs) < SAFE_X[0] or max(xs) > SAFE_X[1]:
                errs.append(f"图形越界x[{min(xs)},{max(xs)}]")
            if min(ys) < SAFE_Y[0]:
                errs.append(f"图形越界y顶{min(ys)}")
        # 空带必须干净
        gap_ink = sum(1 for y in range(*GAP, 2) for x in range(0, W, 2) if has_ink(px[x, y]))
        if gap_ink > 0: errs.append(f"图注间空带有墨{gap_ink}处")
        # 画布四边 4px 净空: 任何墨迹贴边都说明形状越出画布
        edge = sum(1 for y in range(0, H, 2) for x in list(range(0,4,2))+list(range(W-4,W,2)) if has_ink(px[x,y])) \
             + sum(1 for x in range(0, W, 2) for y in list(range(0,4,2))+list(range(H-4,H,2)) if has_ink(px[x,y]))
        if edge > 0: errs.append(f"贴边墨迹{edge}处")
        # 标注带: 有墨 + 水平居中
        lxs = [x for y in range(*LABEL, 2) for x in range(0, W, 2) if has_ink(px[x, y])]
        if len(lxs) < 40:
            errs.append("标注缺失")
        else:
            center = (min(lxs) + max(lxs)) / 2
            if abs(center - CX) > 5:
                errs.append(f"标注偏移{center-CX:+.0f}")
    status = "OK  " if not errs else "FAIL"
    if errs: ok = False
    tag = "dark" if dark_card else "    "
    print(f"{status} {p} {tag} " + ("; ".join(errs) if errs else ""))
# 黑底相邻检查
ds = sorted(dark_set)
for a, b in zip(ds, ds[1:]):
    if b - a < 2:
        print(f"FAIL 黑底卡 {a} 与 {b} 相邻"); ok = False
sys.exit(0 if ok else 1)
PY

echo "全部 ${N} 张导出并通过校验 ✔"
