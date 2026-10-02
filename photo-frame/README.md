# photo-frame — Kindle 电子墨水相框

给越狱 Kindle（老 PW2 758×1024 / 新 PW4 1072×1448，同一静态二进制通吃）的触屏相册：
全屏照片轮播 + 设置页，输入走系统 X11 栈（与 kterm/GTK 同源管线）。

## 组成

| 文件 | 位置 | 作用 |
|---|---|---|
| `photoviewer.c` | Mac 编译 → 设备 `/mnt/us/photo-kit/photoviewer` | 相册本体（50KB 静态）：X11 wire 直连 Xorg multitouch 驱动（GrabPointer 独占 + 按下坐标语义），evdev 影子对照/降级通道，fbink 渲染 |
| `Photo.sh` | 设备 `/mnt/us/documents/` | 书库入口（938×1432 标准封面图标 + 防重入）。自动判别固件抑制 UI 层（老冻结 pillowd / 新停 framework），退出恢复 |
| `process-photos.sh` | Mac | 照片处理：EXIF 转正 → 全屏 cover 裁切 + 灰阶/对比/锐化 → `photos/`（环境变量 `SCREEN_W/SCREEN_H/OUT` 覆盖，新机用 1072×1448） |
| `gen-settings.sh` | Mac | 设置页 UI：每行一张选中态 PNG → `assets/settings-r{0..5}-{W}.png` |
| `tapinject.c` | 设备 | 合成触摸注入器（自动化测试） |
| `screenshot.sh` | Mac | 设备 framebuffer 截图：`./screenshot.sh <ip> [out.png]` |

## 构建

```sh
pip3 install ziglang   # 一次性
./build.sh             # 产出 photoviewer + tapinject (ARM 静态 musl)
```

## 安装（自动，随 ssh 一起）

kindle-tools 统一安装器（服务器 `/t`，或 WB2 网页"安装/修复 SSH"按钮）装 ssh 时自动完成：
- viewer / Photo.sh 书库入口 / 12 张设置页 PNG（按设备分辨率自动选 758/1072）
- **5 张灰阶测试图**（服务器动态生成：渐变/径向/16 级灰阶/网格，开箱即看效果，
  图上自带替换提示）——无需先准备照片
- 默认 conf（600 秒轮播、省电关）

安装后书库点 **Photo** 即用。

## 婴儿黑白训练卡

`./gen-flashcards.sh` 生成 20 张高对比度黑白卡（月亮/太阳/苹果/香蕉/星星/爱心/同心圆/
三角形/方形/雨伞/小鱼/蝴蝶/小花/大树/皮球/礼帽/杯子/勺子/房子/棋盘格，PIL 绘制、
底部带中文名标注）。输出 `flashcards/`，推送到设备 photos/ 即作为相册内容轮播——
训练时直接左右点按翻页。

## 替换成自己的照片

```sh
cd kindle-tools/photo-frame
./process-photos.sh ~/Pictures/你的照片目录        # 老机 758×1024 → photos/
SCREEN_W=1072 SCREEN_H=1448 OUT=photos-hd ./process-photos.sh  # 新机版
# 推送(覆盖设备上的测试图), 推送后重开 Photo 生效:
tar czf - -C photos . | ssh root@<ip> 'rm -f /mnt/us/photo-kit/photos/*; tar xzf - -C /mnt/us/photo-kit/photos && rm -f /mnt/us/photo-kit/photos/._*'
```
源照片支持 JPG/HEIC/PNG（自动 EXIF 转正 + 全屏裁切 + 灰阶优化）。
设置页布局若改过：`./gen-settings.sh` 重新生成，把 assets 中对应尺寸 12 张传到
设备 `settings/r{0..5}s{0|1}.png`。改代码后 `./build.sh` 构建，原子写推送同名路径。
## 交互与布局

- **照片模式**：左 40% 上一张 · 右 40% 下一张 · 中间 20% 退出 · 顶部 12% 设置
- **设置页**（布局常量在 `photoviewer.c` 顶部，与 `gen-settings.sh` 严格同步）：
  标题下状态行显示"时间 电量"；行区 0.16–0.79 七档（30s/1m/5m/10m/30m/1h/省电模式，每行 9% 屏高）；
  点空白处回照片；底部黑色"退出应用"按钮 0.80–0.885
- **省电模式**（第 7 档，实证链路）：RTC 定时深睡换图——写 `wakealarm` → 停 powerd
  （解除 mem 的 EBUSY 锁）→ `echo mem` → RTC 到点唤醒 → 换图 → 再睡，循环。
  **触摸不唤醒深睡，电源键可唤醒**；深睡期间网络断（相框场景无碍）。唤醒后 viewer
  自动拦住 powerd 抢睡。常开 ~50mA vs 省电模式预计续航提升约一个量级
- 配置 `/mnt/us/photo-kit/photo.conf`（`INTERVAL` 秒 + `SLEEP=0/1` 省电开关，设置页写入）
- 日志 `/mnt/us/photo-kit/viewer.log`：`[tap:x11-press]` 动作坐标（按下语义）+
  `[shadow] raw=` evdev 对照——真实手指数据自动积累，可定量核对触摸精度

## 测试

```sh
# 设备上注入合成触摸（经 X 管线，与真实手指同路）
/mnt/us/photo-kit/tapinject 379 80      # 老机: 顶部开设置
# Mac 截图验证
./screenshot.sh <ip> shots/check.png
```
技术细节、X11 协议要点、踩坑清单见 [NOTES.md](NOTES.md)。
