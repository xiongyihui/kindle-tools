#!/usr/bin/env bash
# kindle-tools 服务器一键启动 (bash; Windows 请用 Git Bash 运行)
set -e
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
LOCAL="$ROOT/local"

# 1) node
NODE=""
for n in "$(command -v node 2>/dev/null)" "$HOME/.nvm/versions/node/"*/bin/node /usr/local/bin/node /opt/homebrew/bin/node; do
  [ -x "$n" ] && NODE="$n" && break
done
[ -z "$NODE" ] && { echo "错误: 找不到 node (安装 Node.js 后重试)"; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || echo "警告: 无 ffmpeg, 面板动态渲染将不可用(离线面板不受影响)"
echo "node: $($NODE --version)"

# 2) 跨平台探测局域网 IP
detect_ip() {
  local ip
  ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null) && { echo "$ip"; return; }
  if command -v ipconfig >/dev/null 2>&1; then   # Windows(GitBash): 从 ipconfig 输出抓私网 IPv4
    ipconfig 2>/dev/null | grep -i "ipv4" | grep -oE '(192\.168|10\.|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+' | head -1 && return
  fi
  hostname -I 2>/dev/null | awk '{print $1}'      # Linux 兜底
}
IP=$(detect_ip)
[ -z "$IP" ] && { echo "错误: 未找到局域网 IP (检查网络)"; exit 1; }
echo "本机 IP: $IP"

# 3) 生成本地实例
mkdir -p "$LOCAL"
[ -f "$LOCAL/config.sh" ] || sed "s/YOUR_MAC_IP/$IP/" "$ROOT/config.sh.example" > "$LOCAL/config.sh"
if [ ! -f "$LOCAL/recovery.sh" ]; then
  sed "s|http://YOUR_MAC_IP:3000|http://$IP:3000|g" "$ROOT/deploy/recovery.sh.template" > "$LOCAL/recovery.sh"
  chmod +x "$LOCAL/recovery.sh"
  cp "$LOCAL/recovery.sh" "$LOCAL/jb.sh.install"
fi
if [ ! -f "$LOCAL/pubkey.pub" ]; then
  for k in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
    [ -f "$k" ] && cp "$k" "$LOCAL/pubkey.pub" && break
  done
fi
[ -f "$LOCAL/pubkey.pub" ] && echo "公钥: $(head -c 30 "$LOCAL/pubkey.pub")..." || echo "警告: 无公钥(~/.ssh 无 id_*), 安装后 ssh 将无法免密登录!"

# 4) 依赖
if [ ! -d node_modules ]; then
  echo "安装依赖(首次需网络)..."
  npm install --no-audit --no-fund 2>/dev/null || "$NODE" "$(dirname "$(command -v npm 2>/dev/null || echo npm)")/npm" install --no-audit --no-fund
fi

# 5) 启动
echo "======================================"
echo " 服务器启动: http://$IP:3000"
echo " 越狱流程: ./prepare-usb.sh 写入设备入口"
echo "======================================"
exec "$NODE" api/index.js
