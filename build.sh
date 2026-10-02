#!/bin/zsh
# build.sh — 交叉编译 kindle-tools 组件 (前置: pip3 install ziglang)
set -e
cd "$(dirname "$0")"
ZCC="python3 -m ziglang cc -target arm-linux-musleabi -Os -static -no-pie"

echo "==> minishelld (telnet 通道)"
$ZCC -o bin/minishelld src/minishelld.c

echo "==> dropbear 2024.86 (含 authorized_keys 回退补丁)"
if [ -d dropbear/src ]; then
    (cd dropbear/src \
     && CC="python3 -m ziglang cc -target arm-linux-musleabi" \
       CFLAGS="-Os -static" LDFLAGS="-static" \
       ./configure --host=arm-linux-musleabi --disable-zlib \
          --disable-utmp --disable-utmpx --disable-wtmp --disable-wtmpx --disable-lastlog \
       && make PROGRAMS="dropbear dropbearkey" -j8 LDFLAGS="-static -no-pie" \
       && cp dropbear dropbearkey ../../bin/)
else
    echo "    (跳过: dropbear/src 不存在, 见 dropbear/README.md)"
fi

echo "==> 完成:"; ls -la bin/
