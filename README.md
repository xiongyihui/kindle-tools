# kindle-tools

越狱 Kindle（PW2 / 5.12.2.2 / 内核 3.0.35 实测）的远程访问工具集：
静态编译的 ssh/telnet 服务 + 开机自启 + 通道独立配置。
配套的分发服务器见上层目录 `Winterbreak2/`（README 见工作区根）。

## 通道（独立配置）

`config.sh`（模板 `config.sh.example`，真实文件不入库）逐通道开关：

| 通道 | 程序 | 默认 | 端口 | 连接 |
|---|---|---|---|---|
| ssh | dropbear（含补丁） | 开 | 22 | `ssh root@<kindle>` |
| telnet | minishelld | 关 | 23 | `telnet <kindle>` |
| 轮询（管理） | poll.sh | 开 | — | 服务器 `/cmd` 下发、`/report` 回传 |

## 设备侧布局

```
/mnt/us/kindle-tools/   boot.sh poll.sh config.sh [minishelld] *.pid *.log
/mnt/us/ssh/            bin/dropbear bin/dropbearkey etc/rsa2.key authorized_keys log pid
/etc/upstart/kindle-tools.conf   (start on framework_ready → boot.sh)
```

boot.sh 每次开机：防休眠 → 按 config 放行防火墙（INPUT 默认 DROP）→ 按开关拉起各通道。
全部幂等，已运行的进程不动。

## 编译

前置：`pip3 install ziglang`（zig 工具链，PyPI 秒装）。

```sh
./build.sh          # src/ 与 dropbear/src/ → bin/
```

均为 arm-linux-musleabi 纯静态（`-static -no-pie`），不依赖设备 libc。
dropbear 的 authorized_keys 回退补丁见 `dropbear/`。

## 部署 / 恢复

正常路径走服务器（kterm 里一行）：

```sh
curl -sL http://<服务器>:3000/t | sh
```

`deploy/recovery.sh.template` 是该脚本的模板——替换 `YOUR_MAC_IP` 后放入服务器分发目录。
真实 `config.sh`、公钥（`/pubkey` 路由）同样只放在服务器侧，**本仓库不含任何机器相关信息**。

## 已踩过的坑（这台设备）

- 亚马逊固件 iptables INPUT 默认 DROP，只放行 ESTABLISHED → 必须显式放行端口
- 自动休眠会冻结 Wi-Fi → boot.sh 先设 preventScreenSaver
- rootfs 只读 → 公钥走补丁里的 /mnt/us 回退路径；upstart 需 `mntroot rw` 写 `/etc/upstart`
- upstart 事件是 `framework_ready`；`/var/local/upstart` 不被读取
- 官方 ttyd.arm 在 Cortex-A9 上 SIGILL；kpkg dropbear 动态链接跑不动
- 覆盖运行中的二进制会 ETXTBSY → 先 .tmp 再 mv
- 设备无 scp/sftp-server，传文件用 curl 拉
