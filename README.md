# kindle-tools

越狱 Kindle 的远程访问工具集，**仓库即完整交付物**：设备所需的全部脚本与二进制都在这里，装完后运行不依赖网络。

## 完整流程（三步）

### ① 越狱（未越狱设备，需 Mac 服务器）
```sh
cd ../Winterbreak2 && ../启动越狱服务器.command   # 或直接 nohup node api/index.js
# Kindle 浏览器打开 http://<MacIP>:3000 → 点 "Jailbreak 越狱"
```
越狱脚本已内置（`jailbreak/jb.sh`，v1.3.7），无需外网。

### ② 安装 kindle-tools（二选一）

**离线方式（零网络）**：
1. 把 `kindle-tools/` 整个文件夹拷到 Kindle USB 根目录
2. （可选）建 `local/pubkey.pub`（你的 ssh 公钥）与 `local/config.sh`（从 config.sh.example 复制填写）
3. 把 `Install-Kindle-Tools.sh` 拷到 Kindle 的 `documents/`
4. 书库点 **Install-Kindle-Tools** → 自动装好全部组件

**在线方式（服务器在跑时）**：kterm 或越狱完成页跑
```sh
curl -sL http://<MacIP>:3000/t | sh
```

### ③ 使用
- `ssh root@<KindleIP>`（免密）
- 书库 **Remote Shell** = 触屏管理面板（开关 ssh/telnet、看 IP；面板由服务器整体渲染，离线自动降级为本地预生成图）
- 开机自启（upstart framework_ready）已内置，重启免配置

## 仓库结构

```
bin/        设备二进制(已提交): dropbear dropbearkey minishelld rmsh
src/        自研源码: minishelld.c rmsh.c (zig 交叉编译, 见 build.sh; rmsh 支持 --stdin-taps 自动测试)
device/     boot.sh kindle-tools.conf (开机自启)
ui/         预渲染面板(离线回退) + make-ui.sh (整面板渲染器)
jailbreak/  jb.sh (官方越狱脚本内置)
dropbear/   authorized_keys 回退补丁 + 编译说明
deploy/     recovery.sh.template (服务器恢复脚本模板)
local/      (gitignore) 本机实例: config.sh pubkey.pub
```

## 通道配置

`config.sh` 逐通道独立开关（ENABLE_SSH / ENABLE_TELNET + 端口）。**休眠语义：两通道都关后约 5 分钟设备入睡**（poll 已按需移除，不再阻止休眠），boot.sh 按开关启停并放行防火墙。**测试纪律：绝不关 SSH，最多关 Telnet。**

## 服务器集成

`../Winterbreak2/api/index.js` 的所有分发路由（/dropbear /rmsh /ui /panel.png /jb.sh…）均指向本仓库 —— 单一事实源，改这里即全设备生效（panel 渲染有 ui-cache/，改 make-ui.sh 后清缓存）。

## 硬件适配说明

- 二进制: arm-linux-musleabi 纯静态（-static -no-pie），PW2(3.0.35 内核) 与 PW3/4 实测可跑
- 面板: 服务器按屏宽整图渲染（/panel.png?w=），任意分辨率适配；离线回退 758/1072 两套预生成图
- 已知限制: fbink 文字在高分屏物理尺寸受限（-S 以 8px 基数缩放）、-y 行高随设备字体变化 —— 均已被整面板渲染方案绕开
