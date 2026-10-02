#!/bin/sh
# watchdog.sh — ssh 生命线看门狗 (config 感知版)
# 每轮重读 config.sh: 仅 ENABLE_SSH=1 时保活 dropbear。
# 开关的落点在 rmsh 面板(写 config)与 boot.sh(启停), 这里只做直启复活,
# 不回调 boot.sh —— 否则 boot.sh 的 wd_kill 会把看门狗自己杀掉形成递归。
T=/mnt/us/kindle-tools
S=/mnt/us/ssh

while true; do
    ENABLE_SSH=1
    SSH_PORT=22
    [ -f $T/config.sh ] && . $T/config.sh
    if [ "$ENABLE_SSH" = 1 ] && ! pidof dropbear >/dev/null 2>&1; then
        echo "$(date) watchdog: dropbear 死亡, 直接拉起 (port $SSH_PORT)" >> $T/watchdog.log
        [ -f $S/etc/rsa2.key ] || $S/bin/dropbearkey -t rsa -f $S/etc/rsa2.key
        setsid $S/bin/dropbear -r $S/etc/rsa2.key -p $SSH_PORT -s -E >>$S/log 2>&1 </dev/null &
    fi
    sleep 60
done
