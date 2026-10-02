#!/bin/zsh
# build.sh — 一键构建设备端二进制 (ARM 静态 musl, 两台 Kindle 通用)
# 依赖: pip3 install ziglang
set -e
cd "$(dirname "$0")"
python3 -m ziglang cc -target arm-linux-musleabi -Os -static -no-pie -o photoviewer photoviewer.c
python3 -m ziglang cc -target arm-linux-musleabi -Os -static -no-pie -o tapinject tapinject.c
echo "构建完成: photoviewer ($(stat -f%z photoviewer)B) tapinject ($(stat -f%z tapinject)B)"
