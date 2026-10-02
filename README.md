# kindle-tools

越狱 Kindle 并开启 Remote Shell（ssh / telnet / 触屏管理面板）的一站式工具仓库。
**clone 即用**：设备所需全部脚本与二进制都在仓库里，服务器自动配置，越狱脚本内置不依赖外网。

## 快速开始（未越狱的 Kindle）

**前置依赖**：Node.js（必备）、ffmpeg（可选，动态面板渲染用）。
平台：macOS / Linux 原生 bash；Windows 用 [Git Bash](https://git-scm.com) 运行（脚本已做 IP / 盘符 / 字体的跨平台探测）。

**第 1 步 · 启动服务器**

```sh
bash server/start.sh     # 自动探测本机 IP、生成配置、读取你的 ~/.ssh 公钥（首次需联网装依赖）
```

**第 2 步 · 写入越狱入口**

```sh
bash prepare-usb.sh      # 插上 Kindle(USB) 即自动写入入口文件并弹出
```

**第 3 步 · 在 Kindle 上操作**

1. 连上与电脑相同的 Wi-Fi，浏览器打开 `http://<电脑IP>:3000`
2. 点 **Jailbreak 越狱**（官方 jb.sh v1.3.7，全程不走外网）
3. 越狱完成后点 **安装 / 修复 SSH**（安装 kindle-tools 全套）

**第 4 步 · 连接**

```sh
ssh root@<KindleIP>      # 免密登录，完成 ✅
```

> **已越狱的设备**：跳过第 1~3 步，在 kterm 里运行 `curl -sL http://<电脑IP>:3000/t | sh` 即可。
>
> **完全离线安装**：把仓库文件夹拷到 Kindle 根目录、`Install-Kindle-Tools.sh` 拷到 `documents/`，书库点按即装（需先在 `local/` 放 `pubkey.pub`）。

## 支持范围

- 实测：PaperWhite 2（5.12.2.2 / 内核 3.0.35）、PaperWhite 3/4 代（5.16.2.1.1 / 300dpi）
- 越狱利用：WinterBreak2（浏览器下载漏洞），适用固件以 [kindlemodding](https://kindlemodding.org) 为准
- 二进制：arm-linux-musleabi 纯静态（zig 编译，见 build.sh），不依赖设备 libc

## 仓库结构

```
server/     越狱入口+分发服务器(Express; start.sh 一键启动)
jailbreak/  jb.sh 官方越狱脚本 + winterbreak2/dialoger.html 入口模板(__SERVER__占位)
bin/        设备二进制: dropbear dropbearkey minishelld rmsh
src/        自研源码(minishelld/rmsh, zig 交叉编译; rmsh 支持 --stdin-taps 自动测试)
device/     boot.sh kindle-tools.conf(开机自启: 防休眠+防火墙+按配置拉起)
ui/         预渲染面板(离线回退) + make-ui.sh(整面板按屏宽渲染, IP/状态烤入)
dropbear/   authorized_keys 只读rootfs回退补丁 + 编译说明
deploy/     recovery.sh.template(唯一安装器, /t 与 /jb.sh install 模式同源)
local/      (gitignore, 自动生成) config.sh pubkey.pub recovery.sh mode.txt
```

## 日常使用

- `ssh root@<KindleIP>`（免密）；书库 **Remote Shell** = 触屏面板（开关 ssh/telnet、显示 IP，面板由服务器整体渲染，离线自动降级）
- 通道开关在 `local/config.sh`（ENABLE_SSH / ENABLE_TELNET + 端口），boot.sh 按开关启停+放行防火墙
- **休眠语义**：ssh 与 telnet 都关后约 5 分钟设备入睡；任一在开则保持清醒
- 开机自启内置（upstart framework_ready），重启免配置
- 改面板后删 `ui-cache/` 才会重新渲染

## 测试纪律

自动测试**绝不同时关 ssh 与 telnet**；优先操作 telnet。

__zcode_status=$?
if [ "$__zcode_status" -eq 0 ]; then pwd -P > '/var/folders/6x/8kg5czr51lj0t2__2xy86nsc0000gn/T/zcode-bdd0f8ba-1cf3-4024-b036-f2fd8dfd485a-cwd'; fi
exit "$__zcode_status"