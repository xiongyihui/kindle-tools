#!/bin/sh
# kindle-tools 开机总入口 (/etc/upstart/kindle-tools.conf 调用)
# 通道配置: 同目录 config.sh (ssh / telnet / 轮询 独立开关+端口)

T=/mnt/us/kindle-tools
S=/mnt/us/ssh

# 载入配置(缺失时用默认值)
[ -f $T/config.sh ] && . $T/config.sh
: ${ENABLE_SSH:=1}; : ${ENABLE_TELNET:=0}; : ${ENABLE_POLL:=1}
: ${SSH_PORT:=22};  : ${TELNET_PORT:=23}

fw_open() { # $1=端口
    iptables -C INPUT -i wlan0 -p tcp --dport $1 -j ACCEPT 2>/dev/null || \
        iptables -I INPUT 1 -i wlan0 -p tcp --dport $1 -j ACCEPT
}

# 1. 防休眠(否则整机挂起后全网不可达)
lipc-set-prop -i com.lab126.powerd preventScreenSaver 1 2>/dev/null
lipc-set-prop -i com.lab126.powerd touchScreenSaverTimeout 86400 2>/dev/null

# 2. 防火墙: 按开关放行 (亚马逊固件 INPUT 默认 DROP)
[ "$ENABLE_SSH" = 1 ]    && fw_open $SSH_PORT
[ "$ENABLE_TELNET" = 1 ] && fw_open $TELNET_PORT
iptables -C INPUT -i wlan0 -p icmp -j ACCEPT 2>/dev/null || \
    iptables -I INPUT 1 -i wlan0 -p icmp -j ACCEPT

# 3. ssh (dropbear, 仅密钥登录) — 已在跑则不动
if [ "$ENABLE_SSH" = 1 ] && ! kill -0 $(cat $S/pid 2>/dev/null) 2>/dev/null; then
    [ -f $S/etc/rsa2.key ] || $S/bin/dropbearkey -t rsa -f $S/etc/rsa2.key
    setsid $S/bin/dropbear -r $S/etc/rsa2.key -p $SSH_PORT -s -E >>$S/log 2>&1 </dev/null &
fi

# 4. telnet (minishelld)
if [ "$ENABLE_TELNET" = 1 ] && ! kill -0 $(cat $T/minishelld.pid 2>/dev/null) 2>/dev/null; then
    $T/minishelld $TELNET_PORT >>$T/minishelld.log 2>&1 &
    echo $! > $T/minishelld.pid
fi


exit 0
