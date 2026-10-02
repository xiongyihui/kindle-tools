#!/bin/sh
# poll 生命线看门狗: 每 60s 确保命令轮询守护存活
while true; do
    ALIVE=0
    for p in /proc/[0-9]*; do
        c=$(tr "\0" " " < $p/cmdline 2>/dev/null)
        [ "$c" = "sh /mnt/us/kindle-tools/poll.sh " ] && ALIVE=1 && break
    done
    if [ "$ALIVE" = "0" ]; then
        echo "$(date) watchdog: poll 死亡, 重启" >> /mnt/us/kindle-tools/watchdog.log
        setsid sh /mnt/us/kindle-tools/poll.sh >>/mnt/us/kindle-tools/poll.log 2>&1 < /dev/null &
    fi
    sleep 60
done
