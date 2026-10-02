# photo-frame 技术笔记

> 完整探索过程（2026-10-02）的结论沉淀。调试改代码前先读 §2 协议要点和 §5 踩坑。

## 1. 触控输入架构（photoviewer 现行方案）

两台 Kindle 固件都自带并运行完整 X 栈（kterm 也跑在这上面）：

```
/dev/input/event1 (cyttsp4_mt)
  → Xorg 1.8.2 multitouch.so 定制驱动 → XInput core pointer
  → 本应用: 裸 X11 wire 协议 (GrabPointer op26) → ButtonPress 屏幕坐标
  → evdev 影子通道 (只读对照 + X 不可用时降级输入)
```

实测结论（tapinject 注入 → GrabPointer 监听，两台 10 数据点验证）：

- **X 管线坐标映射 = identity±1px**：`screen = min(round(raw × W/(W-1)), W-1)`。
  kterm 触摸准的真因不是坐标变换，而是 **按下(ButtonPress)坐标语义**（避开抬起时
  接触面缩小导致的重心漂移）+ multitouch 驱动滤波 + 全局 grab。
- Xorg 由 upstart `x.conf`（lxinit）拉起，**独立于 framework**——停 framework 后
  X 存活、grab 与事件流正常（新机实测）。事件序列：Motion→ButtonPress(b=1)→Motion→ButtonRelease。
- 两台 ABI 一致：soft-float armel，`/lib/ld-linux.so.3` → glibc 2.20。
  交叉编译结论：**zig glibc 模拟层链接设备 libX11.so.6 会 pre-main 段错误**
  （TLS/init 不兼容；jessie armel crt 也救不了）——所以用裸 wire 协议 + musl 静态，零依赖。

## 2. X11 wire 协议要点（改 x11 代码前必读）

| 项 | 值 |
|---|---|
| 连接 | `/tmp/.X11-unix/X0`（无认证），握手 12 字节 `'l' 0 11 0 ...` |
| setup 回复 | 附加数据长度是 **u16@offset6**（4 字节单位）——按普通 reply 的 u32@4 解析会 malloc 巨块卡死 read |
| GrabPointer | **opcode=26**（29 是 UngrabButton！），请求 **24 字节 length=6**，event-mask 是紧打包 **CARD16**；布局见 Xproto.h `xGrabPointerReq` |
| 事件首字节 | `type \| (send_event<<7)`；type 4=ButtonPress 5=ButtonRelease 6=Motion |
| 事件坐标 | root-x/y 在 offset 20/22（u16 LE）；grab 在 root 上即屏幕坐标 |
| grab 释放 | 客户端断连自动释放，无需显式 Ungrab |
| 格式拿不准时 | 反汇编设备自带 `libX11.so.6` 的对应函数（capstone ARM 模式），一比便知 |

## 3. 构建 / 部署 / 调试

```sh
./build.sh                               # zig -target arm-linux-musleabi 静态
# 设备调试三件套:
/mnt/us/photo-kit/tapinject x y          # 注入合成触摸(经 X 管线, 与真实手指同路)
./screenshot.sh <ip> out.png             # Mac 侧 fb 截图
tail /mnt/us/photo-kit/viewer.log        # [tap:x11-press] + [shadow] raw 对照
# 深度调试: 设备 /bin/gdbserver :PORT --attach PID + Mac lldb "gdb-remote"
#   (先 iptables -I INPUT -p tcp --dport PORT -j ACCEPT)
```

大包传输用 `ssh 'tar xzf - -C 目标' < 本地.tgz` 流式（新机 /tmp 不足 33MB）。
部署纪律：先 `pidof photoviewer` 确认无活跃会话；一律原子写（.tmp + mv），
不 killall 用户正在用的实例。Photo.sh 有 pidof 防重入（重复点击书库不再双开）。

## 4. 状态栏/UI 抑制速查

- 老固件(<5.13)：`killall -STOP pillowd`（恢复 CONT + pillow disable/enable toggle 重绘）
- 新固件(≥5.13)：`stop framework && stop lab126_gui && stop pillow`（等 cvm/pillowd
  退出最多 15s）；恢复三者 `start`
- 固件判别：`cut -d' ' -f2 /mnt/us/system/version.txt` 匹配 `5.1[3-9].*`
- **两台都有真 pillowd，不能用进程存在性判断固件代际**

## 5. 踩坑清单（血泪版）

| 坑 | 规避 |
|---|---|
| zsh 双引号 `$var:xxx` 被当修饰符（`:c` 被吃导致 ffmpeg 参数粘住） | 裸 `$var:` 后跟字母一律 `${var}` |
| STHeiti 渲染 `✓`(U+2713)/`✔`(U+2714) 是 tofu | 勾选用 `√`(U+221A) 或 `●`(U+25CF) |
| 照片浅色背景被视觉/图像描述误判为 margin | 验证边距必须像素测量（bounding box / 边缘行亮度） |
| 书库条目 icon 比例 | 标准 = KOReader 的 **938×1432**（300×300 正方形会显示矮小） |
| 双 viewer 实例抢屏抢输入（设置页出"叠影"） | Photo.sh 启动前 pidof 防重入；防重入分支**不调 show_ui**（UI 抑制归正主会话管理） |
| `strings` 丢非 ASCII 字节 | 查中文用 `grep -a` |
| python replace 不匹配时静默失败 | 关键改动必须 grep 验证源码与产物 |
| 覆盖运行中二进制 ETXTBSY | .tmp + mv 原子写 |
| 电子墨水残影骗眼睛 | 判断"没生效"前强制重绘一次 |
| busybox ps 看不到 sh 脚本进程 | /proc/*/cmdline 扫描（ssh 命令自身会自匹配） |
| macOS tar 带 AppleDouble(._*) | 传输后 `find -name '._*' -delete` |
| ffmpeg 单张 PNG 输出 | `-frames:v 1 -update 1` |
| fbink 文字 CLI | `-y 行 -x 列 -m 居中 -S 倍数 -c 清屏`；内置字体无中文（UI 中文烘进 PNG） |
| `pkill -f` 模式匹配到 ssh 会话自身命令行 | 用 `pkill -x 精确名` 或 pidof |
| 书库点 .sh 无反应（viewer.log 零新增） | sh_integration 条目卡死 → 重启设备（~80s 全恢复）；备用：改条目文件名强制重建索引 |

## 6. 低功耗深睡实证（2026-10-02，photoviewer 省电模式已落地）

- `echo mem > /sys/power/state` 直写报 **EBUSY**——根因是 **powerd 持锁**；
  `stop powerd` 后写入成功，真深睡（网络全断，功耗毫安级）。
- `wakealarm`（/sys/class/rtc/rtc0/）内核层可靠：**到点 Alarm0 中断唤醒，实测 60s 精确**。
- **触摸不唤醒深睡，电源键可唤醒**；ssh 探测包可充当唤醒源（实验时勿探测）。
- 坑：suspend 期间单调钟停走（dmesg 时间戳差是假象，用墙钟差判断实际睡眠时长）；
  RTC 与系统钟存在约 60s 偏差（wakealarm 用 RTC 自身读数设置即自洽）。
- 坑：`start powerd` 后 powerd 会按 idle 策略**无闹钟抢睡**（睡死）——唤醒后必须
  立即 `preventScreenSaver 1` 拦住，深睡调度由 viewer 自己掌握。
- viewer 集成：主循环 `sleep_once()` = 写闹钟→停 powerd→mem→醒→start powerd→拦睡→换图；
  设置页第 7 档"省电模式"写 `SLEEP=1`，Photo.sh 传 `-s`。
- powerd 的 `rtcWakeup` lipc 属性在 5.16 上 set 报 NoSuchProperty，不可用。

## 7. 遗留事项

- 老机 poll.sh 派生的 curl 每秒 SIGILL（NEON 类指令，pc 超出 /usr/bin/curl 映射范围；
  手动跑同 curl 正常，STOP poll.sh 即停）——旧机轮询通道因此不可用，ssh/telnet 正常。未根治。
- 触摸精度终验靠真实手指：viewer.log 同时记 x11-press 与 shadow raw，数据会自动积累。
