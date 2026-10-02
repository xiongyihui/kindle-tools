#!/bin/zsh
# gen-settings.sh — 设置页 PNG (电子墨水适配)
# 布局与 photoviewer.c 常量严格对应:
#   ROWS_START=0.16 ROWS_END=0.79 EXIT_ZONE=0.79 每行高 0.09 (7 行)
# 前 6 行 = 轮播间隔单选(选中行高亮+√); 第 7 行 = 省电模式 checkbox(右侧方框)
# 生成 12 张/尺寸 (6 选中行 × checkbox 开/关): assets/settings-r{0..5}s{0|1}-{W}.png
# 设备部署为 settings/r{0..5}-{0|1}.png (按设备尺寸选一套)
setopt null_glob
FONT="/System/Library/Fonts/STHeiti Medium.ttc"   # CJK
[ -f "$FONT" ] || FONT="/System/Library/Fonts/STHeiti Light.ttc"
cd "$(dirname "$0")"; mkdir -p assets

gen() { # W H OUT_SUFFIX
    local W=$1 H=$2 SFX=$3
    local TITLE=$(( W*68/758 ))    # 导航标题 "设置"
    local GROUPL=$(( W*23/758 ))   # 组标题 "轮播间隔"
    local ROW=$(( W*42/758 ))      # 行选项文字
    local CHECK=$(( W*44/758 ))    # 勾
    local BOX=$(( W*57/758 ))      # checkbox 方框边长 (勾字号的 1.3 倍)
    local BTN=$(( W*52/758 ))      # 按钮文字
    local PX=$(( W*56/1000 ))      # 左右边距 ~5.6%
    local ROW_H=$(( H*88/1000 ))   # 每行 8.8% 屏高 (7 行)
    local Y0=$(( H*235/1000 ))     # 行区起点
    local labels=("30 秒" "1 分钟" "5 分钟" "10 分钟" "30 分钟" "1 小时")
    for sel in {0..5}; do
      for box in 0 1; do
        local vf="drawtext=fontfile='$FONT':text='设置':fontcolor=black:fontsize=${TITLE}:x=(w-text_w)/2:y=$(( H*105/1000 ))"
        vf+=",drawtext=fontfile='$FONT':text='轮播间隔':fontcolor=0x8E8E93:fontsize=${GROUPL}:x=${PX}:y=$(( H*195/1000 ))"
        # 选中间隔行浅灰背景 (只在前 6 行)
        vf+=",drawbox=x=0:y=$(( Y0+sel*ROW_H )):w=iw:h=${ROW_H}:color=0xE8E8E8:t=fill"
        for j in {1..6}; do
            local ly=$(( Y0 + (j-1)*ROW_H + ROW_H/2 - ROW*6/10 ))
            vf+=",drawtext=fontfile='$FONT':text='${labels[$j]}':fontcolor=black:fontsize=${ROW}:x=${PX}:y=$ly"
            if [ $(( j-1 )) -eq "$sel" ]; then
                vf+=",drawtext=fontfile='$FONT':text='√':fontcolor=black:fontsize=${CHECK}:x=w-$PX-text_w:y=$ly"
            fi
        done
        # 第 7 行: 省电模式 checkbox (文字 + 右侧方框, 框内勾=开)
        local ly7=$(( Y0 + 6*ROW_H + ROW_H/2 - ROW*6/10 ))
        local by7=$(( Y0 + 6*ROW_H + ROW_H/2 - BOX/2 ))
        vf+=",drawtext=fontfile='$FONT':text='省电模式':fontcolor=black:fontsize=${ROW}:x=${PX}:y=$ly7"
        vf+=",drawbox=x=$(( W-PX-BOX )):y=${by7}:w=${BOX}:h=${BOX}:color=black:t=3"
        if [ "$box" = "1" ]; then
            vf+=",drawtext=fontfile='$FONT':text='√':fontcolor=black:fontsize=${CHECK}:x='$(( W-PX-BOX/2 ))-text_w/2':y='$(( by7+BOX/2 ))-text_h/2'"
        fi
        # 行间发丝分隔线 (7 行全部)
        for j in {1..7}; do
            [ "$j" -lt 7 ] && vf+=",drawbox=x=${PX}:y=$(( Y0+j*ROW_H )):w=$(( W-2*PX )):h=1:color=0xCCCCCC:t=fill"
        done
        # 底部全宽黑色退出按钮
        vf+=",drawbox=x=${PX}:y=$(( H*870/1000 )):w=$(( W-2*PX )):h=$(( H*75/1000 )):color=black:t=fill"
        vf+=",drawtext=fontfile='$FONT':text='退出应用':fontcolor=white:fontsize=${BTN}:x=(w-text_w)/2:y='$(( H*870/1000 ))+(($(( H*75/1000 ))-text_h)/2)'"
        ffmpeg -y -loglevel error -f lavfi -i color=white:s=${W}x${H} -frames:v 1 -update 1 -vf "$vf" "assets/settings-r${sel}s${box}-${SFX}.png" || echo "失败 r${sel}s${box}"
      done
    done
    echo "OK ${W}x${H} → 12 张"
}
gen 758 1024 758
gen 1072 1448 1072
