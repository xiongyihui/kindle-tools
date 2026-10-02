#!/usr/bin/env bash
# prepare-usb.sh — 等待 Kindle 插入, 写入越狱入口(dialoger 指向本服务器), 尽力弹出
# bash; Windows 请用 Git Bash 运行
set -e
cd "$(dirname "$0")"

detect_ip() {
  local ip
  ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null) && { echo "$ip"; return; }
  if command -v ipconfig >/dev/null 2>&1; then
    ipconfig 2>/dev/null | grep -i "ipv4" | grep -oE '(192\.168|10\.|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+' | head -1 && return
  fi
  hostname -I 2>/dev/null | awk '{print $1}'
}
IP=$(detect_ip)
[ -z "$IP" ] && { echo "错误: 未找到局域网 IP"; exit 1; }
[ -f local/recovery.sh ] || { echo "请先启动服务器: bash server/start.sh"; exit 1; }

find_kindle() {
  if [ -d /Volumes/Kindle ]; then echo "/Volumes/Kindle"; return 0; fi
  local d
  for d in /c /d /e /f /g /h /i /j /k; do          # Windows 盘符(GitBash 挂载为 /盘符小写)
    if [ -d "$d/Kindle/documents" ] && [ -d "$d/Kindle/system" ]; then echo "$d/Kindle"; return 0; fi
  done
  return 1
}

echo "等待 Kindle 通过 USB 插入 ..."
until K=$(find_kindle); do sleep 1; done
sleep 2
mkdir -p "$K/winterbreak2"
sed "s|http://__SERVER__|http://$IP:3000|" jailbreak/winterbreak2/dialoger.html > "$K/winterbreak2/dialoger.html"
rm -f "$K/winterbreak2"/._dialoger.html 2>/dev/null || true
echo "已写入: $K/winterbreak2/dialoger.html (指向 http://$IP:3000)"

if command -v diskutil >/dev/null 2>&1; then
  diskutil eject "$K" >/dev/null 2>&1 && echo "已安全弹出"
else
  echo "(Windows 请在资源管理器中安全移除硬件)"
fi
echo ""
echo "下一步: Kindle 连 Wi-Fi → 浏览器打开 http://$IP:3000 → 点 [Jailbreak 越狱]"
