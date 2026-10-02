#!/bin/zsh
# start.sh — kindle-tools 服务器一键启动(仓库根执行或 server/ 内执行均可)
# 做的事: 探测本机局域网 IP → 生成 local/ 实例(config/公钥/恢复脚本) → 检查依赖 → 启动
set -e
cd "$(dirname "$0")"
ROOT="$(pwd)/.."
LOCAL="$ROOT/local"

# 1) 找 node
NODE=""
for n in "$(command -v node 2>/dev/null)" "$HOME/.nvm/versions/node/"*/bin/node /usr/local/bin/node /opt/homebrew/bin/node; do
  [ -x "$n" ] && NODE="$n" && break
done
[ -z "$NODE" ] && { echo "错误: 找不到 node (安装 Node.js 后重试)"; exit 1; }
echo "node: $($NODE --version)"

# 2) 探测局域网 IP
IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
[ -z "$IP" ] && { echo "错误: 未找到局域网 IP (检查 Wi-Fi)"; exit 1; }
echo "本机 IP: $IP"

# 3) 生成实例
mkdir -p "$LOCAL"
[ -f "$LOCAL/config.sh" ] || sed "s/YOUR_MAC_IP/$IP/" "$ROOT/config.sh.example" > "$LOCAL/config.sh"
if [ ! -f "$LOCAL/recovery.sh" ]; then
  sed "s|http://YOUR_MAC_IP:3000|http://$IP:3000|g" "$ROOT/deploy/recovery.sh.template" > "$LOCAL/recovery.sh"
  chmod +x "$LOCAL/recovery.sh"
  cp "$LOCAL/recovery.sh" "$LOCAL/jb.sh.install"
fi
if [ ! -f "$LOCAL/pubkey.pub" ]; then
  for k in "$LOCAL/pubkey.pub" "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
    [ -f "$k" ] && cp "$k" "$LOCAL/pubkey.pub" && break
  done
fi
[ -f "$LOCAL/pubkey.pub" ] && echo "公钥: $(head -c 30 "$LOCAL/pubkey.pub")..." || echo "警告: 无公钥(~/.ssh 无 id_*), 安装后 ssh 将无法免密登录!"

# 4) 依赖
[ -d node_modules ] || { echo "安装依赖(首次需网络)..."; "$NODE" -e "const{execSync}=require('child_process')" 2>/dev/null; npm install --no-audit --no-fund 2>/dev/null || "$NODE" $(dirname $(command -v npm || echo npm))/npm install --no-audit --no-fund; }

# 5) 启动
echo "======================================"
echo " 服务器启动: http://$IP:3000"
echo " 越狱流程: ./prepare-usb.sh 写入设备入口"
echo "======================================"
exec "$NODE" api/index.js
