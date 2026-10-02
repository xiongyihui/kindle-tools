#!/bin/zsh
# Remote Shell 面板 UI v5 — Apple HIG 风格 (iOS Settings 内嵌分组):
#   浅灰画布(F2F2F7) + 白卡片 + 发丝分隔线; 每服务一行: 名称+状态副标签 + iOS开关
#   开关: ON=黑轨白钮(右) / OFF=浅灰轨深钮(左); 状态副标签明写 Running/Stopped
#   动态IP: 标题下方居中大字(fbink叠加带 y 11-14%)
# 触摸区(rmsh.c 同源): 整卡 ssh y[.19,.49] telnet y[.49,.79]?? → 见 rmsh.c 实际定义
set -e
cd "$(dirname "$0")"
BOLD="/System/Library/Fonts/Supplemental/Arial Bold.ttf"
REG="/System/Library/Fonts/Supplemental/Arial.ttf"
[ -f "$BOLD" ] || BOLD="/System/Library/Fonts/Helvetica.ttc"
[ -f "$REG" ] || REG="$BOLD"
mkdir -p ui

gen() { # W H sshst telst out [ip]
  local W=$1 H=$2 SS=$3 TS=$4 O=$5
  local IP=${6:-}
  local TT=$((W/13))
  local SR=$([ "$SS" = "ON" ] && echo Running || echo Stopped)
  local TR=$([ "$TS" = "ON" ] && echo Running || echo Stopped) NM=$((W/16)) SB=$((W/30)) FB=$((W/32)) HB=$((W/18))

  # iOS 开关: 轨迹 0.125W x 0.048H, 钮 0.036W
  local SW=""
  local -a STS=("$SS" "$TS")
  local -a SY=(0.2748 0.442)   # 两行开关的轨迹 y(卡片行中心)
  for i in 1 2; do
    local st=${STS[$i]} sy=${SY[$i]}
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
  local IPTXT=""
  if [ -n "$IP" ]; then
    IPTXT="drawtext=fontfile='$BOLD':text='${IP}':fontsize=$((W/15)):fontcolor=black:x=(w-text_w)/2:y=h*0.145"
  else
    IPTXT="drawtext=fontfile='$REG':text='no network':fontsize=$SB:fontcolor=0x888888:x=(w-text_w)/2:y=h*0.16"
  fi

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
  # make-ui.sh single <W> <H> <SSH> <TEL> <out> [ip]
  W=$2; H=$3; SS=$4; TS=$5; O=$6; IP=${7:-}
  gen_single() { :; }
  # 直接调用 gen (需展开局部变量作用域, gen 已在上方定义)
  gen "$W" "$H" "$SS" "$TS" "$O" "$IP"
  exit 0
fi
for SS in ON OFF; do for TS in ON OFF; do
  gen 758 1024 $SS $TS ui/rmsh_758_${SS}_${TS}.png
  gen 1072 1448 $SS $TS ui/rmsh_1072_${SS}_${TS}.png
done; done
echo "v5 $(ls ui | wc -l | tr -d ' ') 张生成"
