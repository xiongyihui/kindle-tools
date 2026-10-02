#!/bin/zsh
# screenshot.sh — Kindle framebuffer 截图: ./screenshot.sh <ip> <输出.png>
IP=${1:-192.168.31.147}; OUT=${2:-shots/$(echo $IP | tr . _)_$(date +%H%M%S).png}
mkdir -p "$(dirname $OUT)"
case "$IP" in
  *.96|*.98) W=1072; H=1448; STRIDE=1088 ;;
  *)    W=758;  H=1024; STRIDE=768  ;;
esac
ssh -o BatchMode=yes -o ConnectTimeout=6 root@$IP 'cat /dev/fb0' > /tmp/fbshot.raw 2>/dev/null
python3 - "$W" "$H" "$STRIDE" "$OUT" <<'PY'
import zlib, struct, sys
W,H,STRIDE,OUT = map(int if False else (lambda x:x), sys.argv[1:]) if False else (int(sys.argv[1]),int(sys.argv[2]),int(sys.argv[3]),sys.argv[4])
raw = open('/tmp/fbshot.raw','rb').read()
out = bytearray()
def chunk(t, d):
    return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
for y in range(H):
    out.append(0); out += raw[y*STRIDE : y*STRIDE + W]
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 0, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(bytes(out))) + chunk(b'IEND', b'')
open(OUT,'wb').write(png)
print('截图:', OUT)
PY
