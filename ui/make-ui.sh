#!/usr/bin/env bash
# Remote Shell 面板渲染器 (bash, 跨平台: macOS / Windows-GitBash / Linux)
# 用法: make-ui.sh                       → 生成 8 张预渲染面板到 ui/
#       make-ui.sh single W H SSH TEL OUT [IP]  → 单张(含IP烤入)
set -e
cd "$(dirname "$0")"

# 跨平台字体探测
BOLD=""; REG=""
for f in "/System/Library/Fonts/Supplemental/Arial Bold.ttf" \
         "C:/Windows/Fonts/arialbd.ttf" "/c/Windows/Fonts/arialbd.ttf" \
         "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"; do
  [ -f "$f" ] && BOLD="$f" && break
done
for f in "/System/Library/Fonts/Supplemental/Arial.ttf" \
         "C:/Windows/Fonts/arial.ttf" "/c/Windows/Fonts/arial.ttf" \
         "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"; do
  [ -f "$f" ] && REG="$f" && break
done
REG="${REG:-$BOLD}"
[ -n "$BOLD" ] || { echo "错误: 找不到可用字体"; exit 1; }

gen() { # W H sshst telst out [ip]   (bash 数组 0 起)
  local W=$1 H=$2 SS=$3 TS=$4 O=$5 IP=${6:-}
  local SR=$([ "$SS" = "ON" ] && echo Running || echo Stopped)
  local TR=$([ "$TS" = "ON" ] && echo Running || echo Stopped)
  local TT=$((W/13)) NM=$((W/16)) SB=$((W/30)) FB=$((W/32)) HB=$((W/18)) BW=$((W/240+2))

  local IPTXT=""
  if [ -n "$IP" ]; then
    IPTXT="drawtext=fontfile='$BOLD':text='${IP}':fontsize=$((W/15)):fontcolor=black:x=(w-text_w)/2:y=h*0.145"
  else
    IPTXT="drawtext=fontfile='$REG':text='no network':fontsize=$SB:fontcolor=0x888888:x=(w-text_w)/2:y=h*0.16"
  fi

  # iOS 开关 (bash: 数组 0 起)
  local SW=""
  local STS=("$SS" "$TS")
  local SY=(0.2748 0.442)
  local i st sy
  for i in 0 1; do
    st=${STS[$i]}; sy=${SY[$i]}
    local TX="iw*0.775" TW="iw*0.125" TH="ih*0.048" KN="iw*0.036"
    if [ "$st" = "ON" ]; then
      SW+=",drawbox=x=${TX}:y=ih*${sy}:w=${TW}:h=${TH}:color=black:t=fill"
      SW+=",drawbox=x=${TX}+${TW}-${KN}-iw*0.006:y=ih*${sy}+(ih*0.048-ih*0.036)/2:w=${KN}:h=ih*0.036:color=white:t=fill"
    else
      SW+=",drawbox=x=${TX}:y=ih*${sy}:w=${TW}:h=${TH}:color=0xC8C8C8:t=fill"
      SW+=",drawbox=x=${TX}+iw*0.006:y=ih*${sy}+(ih*0.048-ih*0.036)/2:w=${KN}:h=ih*0.036:color=0x333333:t=fill"
    fi
  done
  SW="${SW#,}"

  ffmpeg -y -loglevel error -f lavfi -i color=c=white:s=${W}x${H} -frames:v 1 -update 1 -vf "
    drawtext=fontfile='$BOLD':text='Remote Shell':fontsize=$TT:fontcolor=black:x=(w-text_w)/2:y=h*0.075,
    ${IPTXT},
    drawbox=x=iw*0.07:y=ih*0.215:w=iw*0.86:h=ih*0.335:color=white:t=fill,
    drawbox=x=iw*0.07:y=ih*0.215:w=iw*0.86:h=ih*0.335:color=0xBBBBBB:t=2,
    drawbox=x=iw*0.09:y=ih*0.3825:w=iw*0.82:h=1.5:color=0xD8D8D8:t=fill,
    drawtext=fontfile='$BOLD':text='SSH':fontsize=$NM:fontcolor=black:x=w*0.105:y=h*0.245,
    drawtext=fontfile='$REG':text='Port 22 — ${SR}':fontsize=$SB:fontcolor=0x777777:x=w*0.105:y=h*0.305,
    drawtext=fontfile='$BOLD':text='Telnet':fontsize=$NM:fontcolor=black:x=w*0.105:y=h*0.415,
    drawtext=fontfile='$REG':text='Port 23 — ${TR}':fontsize=$SB:fontcolor=0x777777:x=w*0.105:y=h*0.475,
    ${SW},
    drawtext=fontfile='$REG':text='services continue running in background':fontsize=$FB:fontcolor=0x888888:x=(w-text_w)/2:y=h*0.595,
    drawbox=x=iw*0.07:y=ih*0.80:w=iw*0.86:h=ih*0.085:color=black:t=fill,
    drawtext=fontfile='$BOLD':text='Back':fontsize=$HB:fontcolor=white:x=(w-text_w)/2:y=h*0.80+(h*0.085-text_h)/2,
    format=gray" "$O"
}

if [ "$1" = "single" ]; then
  gen "$2" "$3" "$4" "$5" "$6" "$7"
  exit 0
fi

for SS in ON OFF; do for TS in ON OFF; do
  gen 758 1024 $SS $TS rmsh_758_${SS}_${TS}.png
  gen 1072 1448 $SS $TS rmsh_1072_${SS}_${TS}.png
done; done
echo "生成 $(ls rmsh_*.png | wc -l | tr -d ' ') 张面板"
