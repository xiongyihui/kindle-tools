#!/bin/zsh
setopt null_glob
# process-photos.sh — baby 照片 → 电子墨水相框图片
# 全屏无边模式: 所有方向 cover 裁切填满屏幕(横竖图一致), 灰阶/对比/锐化保留
# 参数在下方可调; SCREEN_W/H OUT 环境变量可覆盖(新机: 1072x1448 OUT=photos-hd)

SRC="${1:-$HOME/Pictures/baby}"
OUT="${OUT:-$(dirname "$0")/photos}"
SCREEN_W=${SCREEN_W:-758}; SCREEN_H=${SCREEN_H:-1024}
CONTRAST=1.14                         # 对比度增强
BRIGHTNESS=0.03                       # 轻提亮(肤色友好)
SHARPEN=0.6                           # 锐化强度(对抗抖动损失)
mkdir -p "$OUT"; rm -f "$OUT"/*.png

n=0
for f in "$SRC"/*.[jJ][pP][gG] "$SRC"/*.[jJ][pP][eE][gG] "$SRC"/*.[hH][eE][iI][cC] "$SRC"/*.[pP][nN][gG]; do
  [ -f "$f" ] || continue
  n=$((n+1))
  tmp=/tmp/pf_$$.png
  # 1) EXIF 转正 + 预缩(sips 必定尊重 EXIF 方向)
  sips -s format png --resampleWidth 1600 "$f" --out "$tmp" >/dev/null 2>&1 || continue
  # 2) cover 裁切填满 + 艺术化(无白边, 全屏)
  ffmpeg -y -loglevel error -i "$tmp" -frames:v 1 -update 1 -vf "scale=${SCREEN_W}:${SCREEN_H}:force_original_aspect_ratio=increase,crop=${SCREEN_W}:${SCREEN_H},format=gray,eq=contrast=${CONTRAST}:brightness=${BRIGHTNESS},unsharp=5:5:${SHARPEN}" "$OUT/frame_$(printf %02d $n).png" </dev/null || echo "失败: $(basename "$f")"
  rm -f "$tmp"
done
echo "完成: $(ls "$OUT" | wc -l | tr -d ' ') 张 → $OUT"
