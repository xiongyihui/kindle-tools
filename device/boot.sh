#!/bin/sh
# kindle-tools 开机总入口 (/etc/upstart/kindle-tools.conf 调用)
# 通道配置: 同目录 config.sh (ssh / telnet 独立开关+端口)
#
# boot.sh 是通道状态的单一同步点: 按开关对称地 启动+停止 服务、放行+撤除 防火墙。
# rmsh 面板开关 = 写 config.sh + 重跑本脚本; watchdog 每轮重读 config.sh。
# 重启后: 进程与 iptables 规则均清零, 本脚本按 config.sh 重建。
#
# 顺序纪律: 必须先清 watchdog 再停服务 — 否则旧 watchdog 会在两步之间复活 dropbear。

T=/mnt/us/kindle-tools
S=/mnt/us/ssh

# 载入配置(缺失时用默认值)
[ -f $T/config.sh ] && . $T/config.sh
: ${ENABLE_SSH:=1}; : ${ENABLE_TELNET:=0}
: ${SSH_PORT:=22};  : ${TELNET_PORT:=23}

fw_open() { # $1=端口 (幂等)
    iptables -C INPUT -i wlan0 -p tcp --dport $1 -j ACCEPT 2>/dev/null || \
        iptables -I INPUT 1 -i wlan0 -p tcp --dport $1 -j ACCEPT
}
fw_close() { # $1=端口 (清掉全部匹配规则, 历史运行可能累积重复)
    while iptables -D INPUT -i wlan0 -p tcp --dport $1 -j ACCEPT 2>/dev/null; do :; done
}
wd_kill() { # 清掉所有 watchdog 实例 (sh 脚本 comm=sh, 只能按 cmdline 匹配)
    for p in /proc/[0-9]*/cmdline; do
        c=$(tr '\0' ' ' < "$p" 2>/dev/null)
        case "$c" in *"$T/watchdog.sh"*)
            pn=${p#/proc/}; kill "${pn%/cmdline}" 2>/dev/null ;;
        esac
    done
}

# 0. 先清 watchdog: 旧实例(可能是老版脚本)会在服务停止后复活 dropbear
wd_kill

# 1. 防休眠: 任一通道在开才保清醒; 全关恢复休眠语义 (~5 分钟入睡)
if [ "$ENABLE_SSH" = 1 ] || [ "$ENABLE_TELNET" = 1 ]; then
    lipc-set-prop -i com.lab126.powerd preventScreenSaver 1 2>/dev/null
    lipc-set-prop -i com.lab126.powerd touchScreenSaverTimeout 86400 2>/dev/null
else
    lipc-set-prop -i com.lab126.powerd preventScreenSaver 0 2>/dev/null
    lipc-set-prop -i com.lab126.powerd touchScreenSaverTimeout 300 2>/dev/null
fi

# 2. 防火墙: 按开关放行/撤除 (亚马逊固件 INPUT 默认 DROP)
if [ "$ENABLE_SSH" = 1 ]; then fw_open $SSH_PORT; else fw_close $SSH_PORT; fi
if [ "$ENABLE_TELNET" = 1 ]; then fw_open $TELNET_PORT; else fw_close $TELNET_PORT; fi
iptables -C INPUT -i wlan0 -p icmp -j ACCEPT 2>/dev/null || \
    iptables -I INPUT 1 -i wlan0 -p icmp -j ACCEPT

# 3. ssh (dropbear, 仅密钥登录) — 按开关 启动/停止
if [ "$ENABLE_SSH" = 1 ]; then
    if ! pidof dropbear >/dev/null 2>&1; then
        [ -f $S/etc/rsa2.key ] || $S/bin/dropbearkey -t rsa -f $S/etc/rsa2.key
        setsid $S/bin/dropbear -r $S/etc/rsa2.key -p $SSH_PORT -s -E >>$S/log 2>&1 </dev/null &
    fi
else
    pidof dropbear >/dev/null 2>&1 && killall dropbear 2>/dev/null
fi

# 4. telnet (minishelld) — 按开关 启动/停止
if [ "$ENABLE_TELNET" = 1 ]; then
    if ! pidof minishelld >/dev/null 2>&1; then
        setsid $T/minishelld $TELNET_PORT >>$T/minishelld.log 2>&1 </dev/null &
    fi
else
    pidof minishelld >/dev/null 2>&1 && killall minishelld 2>/dev/null
fi

# 5. watchdog (ssh 生命线): ENABLE_SSH=1 时恰好 1 个新实例 (=0 时上面已清零)。
#    注意 watchdog 只直启 dropbear, 不再回调 boot.sh (避免递归/自杀循环)
if [ "$ENABLE_SSH" = 1 ]; then
    setsid sh $T/watchdog.sh >>$T/watchdog.log 2>&1 </dev/null &
fi

exit 0
