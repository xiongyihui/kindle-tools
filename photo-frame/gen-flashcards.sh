#!/bin/zsh
# gen-flashcards.sh — 婴儿黑白视觉训练卡 (20 张, 758×1024, 纯黑白, 电子墨水屏适用)
#
# 实现方式: 逐张用无头 Chrome 渲染 flashcards.html?n=N 并截图,
#           替代旧版 PIL 直接绘图 (SVG 贝塞尔曲线造型质量更高)。
# 输出: flashcards/frame_{01..20}.png
# 部署: tar czf - -C flashcards . | ssh root@<ip> 'rm -f /mnt/us/photo-kit/photos/*; tar xzf - -C /mnt/us/photo-kit/photos'

set -e
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
SRC="$(pwd)/flashcards.html"
OUT="flashcards"
mkdir -p "$OUT"

# 循环导出 20 张: ?n=N 让页面只渲染第 N 张, 视口即卡片尺寸
for n in $(seq 1 20); do
  nn=$(printf "%02d" "$n")
  echo "导出 ${OUT}/frame_${nn}.png (卡 ${n}/20) ..."
  "$CHROME" --headless --disable-gpu \
    --force-device-scale-factor=1 \
    --hide-scrollbars --window-size=758,1024 \
    --virtual-time-budget=1500 \
    --screenshot="${OUT}/frame_${nn}.png" \
    "file://${SRC}?n=${n}" >/dev/null 2>&1
done

# ---- PIL 校验: 尺寸必须 758×1024, 且最暗像素 <128 (有黑色图形, 非空白) ----
python3 - <<'PY'
from PIL import Image
import sys

ok = True
for i in range(1, 21):
    p = f"flashcards/frame_{i:02d}.png"
    try:
        im = Image.open(p)
        mn, mx = im.convert("L").getextrema()
    except Exception as e:
        print(f"FAIL {p} 无法读取: {e}"); ok = False; continue
    size_ok = im.size == (758, 1024)
    ink_ok = mn < 128          # 存在足够黑的像素 → 非空白
    status = "OK  " if (size_ok and ink_ok) else "FAIL"
    if not (size_ok and ink_ok):
        ok = False
    print(f"{status} {p} size={im.size} min={mn} max={mx}")
sys.exit(0 if ok else 1)
PY

echo "全部 20 张导出并通过校验 ✔"
