#!/bin/zsh
# prepare-usb.sh — 等待 Kindle 插入, 写入越狱入口(dialoger 指向本服务器), 弹出
set -e
cd "$(dirname "$0")"
IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
[ -z "$IP" ] && { echo "错误: 未找到局域网 IP"; exit 1; }
if [ ! -f local/recovery.sh ]; then echo "请先启动服务器: ./server/start.sh"; exit 1; fi

echo "等待 Kindle 通过 USB 插入 (/Volumes/Kindle)..."
until [ -d /Volumes/Kindle ]; do sleep 1; done
sleep 2
mkdir -p /Volumes/Kindle/winterbreak2
sed "s|http://__SERVER__|http://$IP:3000|" jailbreak/winterbreak2/dialoger.html > /Volumes/Kindle/winterbreak2/dialoger.html
rm -f /Volumes/Kindle/winterbreak2/._dialoger.html
echo "已写入: /Volumes/Kindle/winterbreak2/dialoger.html (指向 http://$IP:3000)"
diskutil eject /Volumes/Kindle >/dev/null 2>&1 && echo "已安全弹出"
echo ""
echo "下一步: Kindle 连 Wi-Fi → 浏览器打开 http://$IP:3000 → 点 [Jailbreak 越狱]"
