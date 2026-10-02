# dropbear 定制版

基于 dropbear 2024.86，唯一改动：`authorized_keys-fallback.patch`

**背景**：Kindle 5.12.2.2 的 rootfs 只读，`/root/.ssh/authorized_keys` 写不进。
**改动**：`checkpubkey()` 里标准路径打开失败时，回退读 `/mnt/us/ssh/authorized_keys`（用户分区，可写）。

## 编译

```sh
# 源码: dropbear-2024.86.tar.xz 解压为 src/ 后打补丁
cd src && patch -p1 < ../authorized_keys-fallback.patch
cd .. && ./build.sh    # 或手动:
python3 -m ziglang cc 作为 CC, -target arm-linux-musleabi -static -no-pie
./configure --host=arm-linux-musleabi --disable-zlib \
  --disable-utmp --disable-utmpx --disable-wtmp --disable-wtmpx --disable-lastlog
make PROGRAMS="dropbear dropbearkey" -j8 LDFLAGS="-static -no-pie"
```

产物纯静态（无解释器、无 libc 依赖），适配老 Kindle（armv7 / 内核 3.0.35 / glibc 古老）。

## 运行参数要点

- `-r <key>` 指定主机密钥；`-s` 禁用密码（仅密钥）；`-E` 输出到 stderr（**开关型参数，不能跟路径**）
- 主机密钥用自带 dropbearkey 生成
