#!/bin/sh
# watchdog.sh — ssh 生命线看门狗: 每 60s 确保 dropbear 存活
# dropbear 死亡(网络异常/未知信号, 2026-10-02 实证发生过) → 重跑 boot.sh 幂等恢复
T=/mnt/us/kindle-tools
while true; do
    if ! pidof dropbear >/dev/null 2>&1; then
        echo "$(date) watchdog: dropbear 死亡, 重跑 boot.sh" >> $T/watchdog.log
        sh $T/boot.sh >>$T/watchdog.log 2>&1
    fi
    sleep 60
done
