#!/bin/sh
# Install-Kindle-Tools.sh — 离线一键安装 (书库点击运行, 无需网络)
# 前置: 已越狱; 已把 kindle-tools 仓库文件夹拷到 Kindle 根目录,
#       并把本文件拷到 documents/ ; local/ 目录含 pubkey.pub(可选, 不装则仅轮询无ssh)
# 安装内容: ssh(dropbear) + telnet(minishelld) + rmsh面板 + 防火墙/防休眠 + 开机自启 + 轮询

SRC=/mnt/us/kindle-tools          # 仓库拷贝位置
T=/mnt/us/kindle-tools            # 运行位置(就地)
S=/mnt/us/ssh

echo "[1/5] 布置文件..."
mkdir -p $S/bin $S/etc $T/ui
cp -f $SRC/bin/dropbear    $S/bin/dropbear
cp -f $SRC/bin/dropbearkey $S/bin/dropbearkey
cp -f $SRC/bin/minishelld  $T/minishelld
cp -f $SRC/bin/rmsh        $T/rmsh
cp -f $SRC/bin/tinject     $T/tinject
cp -f $SRC/device/boot.sh $SRC/device/poll.sh $SRC/device/watchdog.sh $T/
cp -f $SRC/ui/rmsh_*.png $T/ui/
chmod +x $S/bin/* $T/rmsh $T/minishelld $T/tinject $T/*.sh
# 入口
cp -f $SRC/Remote\ Shell.sh /mnt/us/documents/ 2>/dev/null && chmod +x "/mnt/us/documents/Remote Shell.sh"
# 配置: 仓库 local/config.sh 优先, 否则用默认(ssh开/telnet关/轮询关-离线)
if [ -f $SRC/local/config.sh ]; then cp -f $SRC/local/config.sh $T/config.sh
else printf 'ENABLE_SSH=1\nENABLE_TELNET=0\nENABLE_POLL=0\nSSH_PORT=22\nTELNET_PORT=23\nSRV_IP=192.168.31.191\nSRV_PORT=3000\n' > $T/config.sh
fi

echo "[2/5] 防休眠 + 防火墙..."
lipc-set-prop -i com.lab126.powerd preventScreenSaver 1 2>/dev/null
iptables -I INPUT 1 -i wlan0 -p tcp --dport 22 -j ACCEPT 2>/dev/null
iptables -I INPUT 1 -i wlan0 -p icmp -j ACCEPT 2>/dev/null

echo "[3/5] 主机密钥与公钥..."
[ -f $S/etc/rsa2.key ] || $S/bin/dropbearkey -t rsa -f $S/etc/rsa2.key 2>&1 | tail -1
if [ -f $SRC/local/pubkey.pub ]; then
    cp -f $SRC/local/pubkey.pub $S/authorized_keys && chmod 600 $S/authorized_keys
else
    echo "  (local/pubkey.pub 不存在, 跳过公钥 — ssh仅密钥登录将不可用)"
fi

echo "[4/5] 开机自启 (upstart)..."
mntroot rw 2>/dev/null
printf 'description "kindle-tools: firewall/keepawake/channels"\nstart on framework_ready\ntask\nexec /bin/sh /mnt/us/kindle-tools/boot.sh\n' > /etc/upstart/kindle-tools.conf
mntroot ro 2>/dev/null

echo "[5/5] 拉起服务..."
sh $T/boot.sh
sleep 2
echo "--- 端口:"; netstat -tln 2>/dev/null | grep -E ':(22|23) '
IP=$(ifconfig wlan0 2>/dev/null | grep -oE 'inet addr:[0-9.]+' | head -1 | cut -d: -f2)
echo ""
echo "======================================"
echo " 安装完成! ssh root@${IP:-?}"
echo " 书库: Remote Shell = 管理面板"
echo "======================================"
