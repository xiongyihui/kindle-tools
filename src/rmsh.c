/* rmsh.c — REMOTE SHELL 触屏管理面板 (SSH + Telnet)
 * 首页入口 documents/Remote Shell.sh 启动。
 * UI 与触摸区同源(归一化坐标):
 *   SSH 按钮    x[0.08,0.44] y[0.30,0.50]
 *   TELNET 按钮 x[0.56,0.92] y[0.30,0.50]
 *   EXIT 按钮   x[0.15,0.85] y[0.72,0.84]
 * 编译: zig cc -target arm-linux-musleabi -Os -static -no-pie
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <dirent.h>
#include <linux/input.h>
#include <sys/ioctl.h>

#define UI_DIR "/mnt/us/kindle-tools/ui"
#define T "/mnt/us/kindle-tools"
#define SRV "http://192.168.31.191:3000"

static char FBINK[256] = "/var/local/kmc/bin/fbink";
static int xmax = 758, ymax = 1024;

static void runcmd(const char *fmt, ...) {
    char cmd[640];
    va_list ap; va_start(ap, fmt);
    vsnprintf(cmd, sizeof(cmd), fmt, ap);
    va_end(ap);
    system(cmd);
}

/* 进程存活检测: 扫 /proc 找 cmdline 含关键串 */
static int proc_alive(const char *needle) {
    char path[32], buf[512];
    for (int i = 1; i < 65536; i++) {
        snprintf(path, sizeof(path), "/proc/%d/cmdline", i);
        int fd = open(path, O_RDONLY);
        if (fd < 0) continue;
        ssize_t n = read(fd, buf, sizeof(buf) - 1);
        close(fd);
        if (n <= 0) continue;
        buf[n] = 0;
        for (ssize_t j = 0; j < n; j++) if (buf[j] == 0) buf[j] = ' ';
        if (strstr(buf, needle)) return 1;
    }
    return 0;
}

static int ssh_on(void)    { return proc_alive("ssh/bin/dropbear"); }
static int telnet_on(void) { return proc_alive("minishelld"); }

static void get_ip(char *out, size_t n) {
    FILE *p = popen("ifconfig wlan0 2>/dev/null | grep -oE 'inet addr:[0-9.]+' | head -1 | cut -d: -f2", "r");
    out[0] = 0;
    if (p) { if (fgets(out, n, p)) { char *nl = strchr(out, '\n'); if (nl) *nl = 0; } pclose(p); }
    if (!out[0]) snprintf(out, n, "no-wifi");
}

static void keepawake(int on) {
    runcmd("lipc-set-prop -i com.lab126.powerd preventScreenSaver %d 2>/dev/null", on ? 1 : 0);
    /* 休眠超时必须同步恢复, 否则 86400 会残留导致关服务后 24h 不睡 */
    runcmd("lipc-set-prop -i com.lab126.powerd touchScreenSaverTimeout %d 2>/dev/null", on ? 86400 : 300);
}

static void sync_keepawake(void) { keepawake(ssh_on() || telnet_on()); }

/* 按当前状态换 UI 图 + 底部 IP 行 */
static void draw(void) {
    int hd = xmax > 1000;
    int w = hd ? 1072 : 758;
    char ip[40]; get_ip(ip, sizeof(ip));
    char state[16];
    snprintf(state, sizeof(state), "%s,%s", ssh_on() ? "on" : "off", telnet_on() ? "on" : "off");
    /* 优先: 服务器整面板渲染(含IP与状态, 设备无关单一渲染源, 无叠加无行数计算) */
    char cmd[768];
    snprintf(cmd, sizeof(cmd),
             "curl -sfL --max-time 6 -o /tmp/panel.png '%s/panel.png?w=%d&state=%s&ip=%s' && %s -c -f -W GC16 -D ORDERED -i /tmp/panel.png",
             SRV, w, state, ip, FBINK);
    if (system(cmd) == 0) return;
    /* 离线回落: 本地预生成状态图 + fbink 小字 IP */
    runcmd("%s -c -f -W GC16 -D ORDERED -i %s/rmsh_%s_%s_%s.png",
           FBINK, UI_DIR, hd ? "1072" : "758", ssh_on() ? "ON" : "OFF", telnet_on() ? "ON" : "OFF");
    runcmd("%s -q -S 3 -y 6 -m '%s'", FBINK, ip);
}

static void ssh_toggle(void) {
    if (ssh_on()) {
        runcmd("killall dropbear 2>/dev/null");
    } else {
        runcmd("[ -f /mnt/us/ssh/etc/rsa2.key ] || /mnt/us/ssh/bin/dropbearkey -t rsa -f /mnt/us/ssh/etc/rsa2.key");
        runcmd("setsid /mnt/us/ssh/bin/dropbear -r /mnt/us/ssh/etc/rsa2.key -p 22 -s -E >>/mnt/us/ssh/log 2>&1 </dev/null &");
    }
    sync_keepawake();
}

static void telnet_toggle(void) {
    if (telnet_on()) {
        runcmd("killall minishelld 2>/dev/null");
    } else {
        /* minishelld 缺失则从服务器拉 */
        runcmd("[ -x %s/minishelld ] || curl -sfL --max-time 60 -o %s/minishelld.tmp %s/shd && mv -f %s/minishelld.tmp %s/minishelld && chmod +x %s/minishelld",
               T, T, SRV, T, T, T);
        runcmd("iptables -C INPUT -i wlan0 -p tcp --dport 23 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -i wlan0 -p tcp --dport 23 -j ACCEPT");
        runcmd("setsid %s/minishelld 23 >>%s/telnet.log 2>&1 </dev/null &", T, T);
    }
    sync_keepawake();
}

static int open_touch(void) {
    int fd = -1;
    struct input_absinfo ai;
    for (int i = 0; i < 8 && fd < 0; i++) {
        char path[32];
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        int f = open(path, O_RDONLY);
        if (f < 0) continue;
        char name[64] = "";
        ioctl(f, EVIOCGNAME(sizeof(name) - 1), name);
        if (ioctl(f, EVIOCGABS(ABS_MT_POSITION_X), &ai) != 0 || strstr(name, "onkey")) { close(f); continue; }
        fprintf(stderr, "touch: %s (%s)\n", path, name);
        fd = f;
        if (ai.maximum > 0) xmax = ai.maximum;
        if (ioctl(f, EVIOCGABS(ABS_MT_POSITION_Y), &ai) == 0 && ai.maximum > 0) ymax = ai.maximum;
    }
    return fd;
}

static int handle_tap(int x, int y) {
    double nx = (double)x / xmax, ny = (double)y / ymax;
    if (ny >= 0.21 && ny <= 0.38 && nx >= 0.05 && nx <= 0.95) {
        fprintf(stderr, "-> ssh toggle\n"); ssh_toggle(); sleep(1); draw();
    } else if (ny >= 0.39 && ny <= 0.56 && nx >= 0.05 && nx <= 0.95) {
        fprintf(stderr, "-> telnet toggle\n"); telnet_toggle(); sleep(1); draw();
    } else if (ny >= 0.79 && ny <= 0.90 && nx >= 0.06 && nx <= 0.94) {
        fprintf(stderr, "-> exit\n"); return 1;
    }
    return 0;
}

int main(int argc, char **argv) {
    int argc_taps = (argc > 1 && strcmp(argv[1], "--stdin-taps") == 0);
    const char *cands[] = {"/var/local/kmc/bin/fbink", "/mnt/us/libkh/bin/fbink", "/mnt/us/linkss/bin/fbink"};
    for (unsigned i = 0; i < sizeof(cands) / sizeof(cands[0]); i++)
        if (access(cands[i], X_OK) == 0) { strcpy(FBINK, cands[i]); break; }

    int fd = -1;
    if (!argc_taps) {
        fd = open_touch();
        if (fd < 0) { fprintf(stderr, "no touch device\n"); return 1; }
    }
    fprintf(stderr, "geometry: xmax=%d ymax=%d\n", xmax, ymax);

    keepawake(1);   /* 面板期间保持清醒 */
    draw();

    if (argc_taps) {
        /* 测试模式: 从 stdin 读 "x y" 行, 走同一命中判定 */
        char line[64];
        while (fgets(line, sizeof(line), stdin)) {
            int tx, ty;
            if (sscanf(line, "%d %d", &tx, &ty) != 2) continue;
            fprintf(stderr, "[tap-stdin] raw=(%d,%d)\n", tx, ty);
            if (handle_tap(tx, ty) == 1) break;
        }
    } else {
    struct input_event ev;
    int lastx = -1, lasty = -1, down = 0;
    while (1) {
        if (read(fd, &ev, sizeof(ev)) != sizeof(ev)) break;
        if (ev.type == EV_ABS) {
            switch (ev.code) {
                case ABS_MT_POSITION_X: case ABS_X: lastx = ev.value; break;
                case ABS_MT_POSITION_Y: case ABS_Y: lasty = ev.value; break;
                case ABS_MT_TRACKING_ID: if (ev.value < 0) down = 0; break;
            }
        } else if (ev.type == EV_KEY && ev.code == BTN_TOUCH) {
            down = ev.value;
        } else if (ev.type == EV_SYN && ev.code == SYN_REPORT && !down && lastx >= 0 && lasty >= 0) {
            fprintf(stderr, "[tap] raw=(%d,%d) norm=(%.2f,%.2f)\n", lastx, lasty, (double)lastx/xmax, (double)lasty/ymax);
            if (handle_tap(lastx, lasty) == 1) break;
            lastx = -1;
        }
    }
    }
    sync_keepawake();   /* 退出面板: 防休眠跟随服务状态 */
    if (fd >= 0) close(fd);
    /* 画退出说明屏(墨水屏特性: 电源键休眠/唤醒必定全屏重绘回书库) */
    runcmd("%s -c -f -q", FBINK);
    runcmd("%s -q -S 3 -y 16 -m 'Panel closed'", FBINK);
    runcmd("%s -q -S 2 -y 28 -m 'services keep running in background'", FBINK);
    runcmd("%s -q -S 2 -y 40 -m 'press POWER (sleep, wake) to return to library'", FBINK);
    runcmd("%s -q -S 2 -y 48 -m 'or reopen: Remote Shell in Documents'", FBINK);
    return 0;
}
