/* rmsh.c — REMOTE SHELL 触屏管理面板 (SSH + Telnet)
 * 首页入口 documents/Remote Shell.sh 启动。
 * UI 与触摸区同源(归一化坐标, 与 ui/make-ui.sh 的面板渲染一致):
 *   SSH 行     y[0.21,0.38] 全宽
 *   TELNET 行  y[0.39,0.56] 全宽
 *   EXIT 按钮  y[0.79,0.90]
 *
 * 通道开关设计 (2026-10-02 修"ssh 关不掉"):
 *   单一事实源 = config.sh。开关动作 = 写 config.sh + 重跑 boot.sh
 *   (boot.sh 按开关对称启/停服务并开/撤防火墙, 并管理 watchdog 生命周期)。
 *   状态因此跨重启保持; watchdog 每轮重读 config.sh, 只保 ENABLE_SSH=1 的 dropbear。
 *
 * 电源键逃生 (max77696-onkey, event0): 面板内按 power 立即退出面板,
 * 交给系统 休眠/唤醒 流程回 home (实测唤醒时框架必定全屏重绘回书库;
 * 任何自绘恢复都不触发框架重绘, 故退出时不再画任何东西)。
 * SIGUSR1 = 同一路径的远程测试钩子。
 *
 * 编译: zig cc -target arm-linux-musleabi -Os -static -no-pie
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <dirent.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <sys/select.h>

#define UI_DIR "/mnt/us/kindle-tools/ui"
#define T "/mnt/us/kindle-tools"
#define SRV "http://192.168.31.191:3000"

static char FBINK[256] = "/var/local/kmc/bin/fbink";
static int xmax = 758, ymax = 1024;
static volatile sig_atomic_t g_power_exit = 0;

static void on_sig(int s) { (void)s; g_power_exit = 1; }

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

/* 改 config.sh 里的单个 KEY= 值, 其余行原样保留 (原子替换) */
static void set_conf(const char *key, int val) {
    char path[160], tmp[168];
    snprintf(path, sizeof(path), "%s/config.sh", T);
    snprintf(tmp, sizeof(tmp), "%s.tmp", path);
    FILE *in = fopen(path, "r"), *out = fopen(tmp, "w");
    if (!out) { if (in) fclose(in); return; }
    char ln[256];
    int found = 0;
    size_t klen = strlen(key);
    if (in) {
        while (fgets(ln, sizeof(ln), in)) {
            if (strncmp(ln, key, klen) == 0 && ln[klen] == '=') {
                fprintf(out, "%s=%d\n", key, val);
                found = 1;
            } else {
                fputs(ln, out);
            }
        }
        fclose(in);
    }
    if (!found) fprintf(out, "%s=%d\n", key, val);
    fclose(out);
    rename(tmp, path);
    sync();   /* FAT32 尽快落盘 */
}

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

/* 开关 = 写 config + 重跑 boot.sh (启停/防火墙/watchdog 全在 boot.sh 对称处理) */
static void apply_boot(void) {
    runcmd("sh %s/boot.sh >>%s/boot-toggle.log 2>&1", T, T);
    sleep(1);
    sync_keepawake();
}

static void ssh_toggle(void) {
    int on = ssh_on();
    set_conf("ENABLE_SSH", on ? 0 : 1);
    fprintf(stderr, "-> ssh %s (config 已写, 应用 boot.sh)\n", on ? "off" : "on");
    apply_boot();
}

static void telnet_toggle(void) {
    int on = telnet_on();
    if (!on) {
        /* minishelld 缺失则从服务器拉 */
        runcmd("[ -x %s/minishelld ] || curl -sfL --max-time 60 -o %s/minishelld.tmp %s/shd && mv -f %s/minishelld.tmp %s/minishelld && chmod +x %s/minishelld",
               T, T, SRV, T, T, T);
    }
    set_conf("ENABLE_TELNET", on ? 0 : 1);
    fprintf(stderr, "-> telnet %s (config 已写, 应用 boot.sh)\n", on ? "off" : "on");
    apply_boot();
}

static int open_touch(void) {
    int fd = -1;
    struct input_absinfo ai;
    for (int i = 0; i < 8 && fd < 0; i++) {
        char path[32];
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        int f = open(path, O_RDONLY | O_NONBLOCK);
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

/* 电源键设备 (max77696-onkey): open_touch 会跳过它, 这里专门打开 */
static int pw_open(void) {
    for (int i = 0; i < 8; i++) {
        char path[32];
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        int f = open(path, O_RDONLY | O_NONBLOCK);
        if (f < 0) continue;
        char name[64] = "";
        ioctl(f, EVIOCGNAME(sizeof(name) - 1), name);
        if (strstr(name, "onkey")) {
            fprintf(stderr, "power-key: %s (%s)\n", path, name);
            return f;
        }
        close(f);
    }
    fprintf(stderr, "power-key: 未找到 onkey 设备, 电源键逃生不可用\n");
    return -1;
}

static int handle_tap(int x, int y) {
    double nx = (double)x / xmax, ny = (double)y / ymax;
    if (ny >= 0.21 && ny <= 0.38 && nx >= 0.05 && nx <= 0.95) {
        ssh_toggle(); sleep(1); draw();
    } else if (ny >= 0.39 && ny <= 0.56 && nx >= 0.05 && nx <= 0.95) {
        telnet_toggle(); sleep(1); draw();
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

    /* SIGUSR1 = 电源键逃生的远程测试钩子; SIGINT 同路径。不设 SA_RESTART,
     * 让阻塞中的 select 立刻被 EINTR 打断回到循环头检查标志 */
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_sig;
    sigaction(SIGUSR1, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);

    int tfd = -1;
    if (!argc_taps) {
        tfd = open_touch();
        if (tfd < 0) { fprintf(stderr, "no touch device\n"); return 1; }
    }
    int pfd = pw_open();
    fprintf(stderr, "geometry: xmax=%d ymax=%d\n", xmax, ymax);

    keepawake(1);   /* 面板期间保持清醒 */
    draw();

    /* 统一 select 循环: 触摸 / 测试stdin / 电源键 三路输入 */
    char line[64];
    int llen = 0;
    int user_exit = 0;
    struct input_event ev;
    int lastx = -1, lasty = -1, down = 0;
    while (!user_exit && !g_power_exit) {
        fd_set rf;
        FD_ZERO(&rf);
        int maxfd = -1;
        if (argc_taps) { FD_SET(0, &rf); maxfd = 0; }
        else if (tfd >= 0) { FD_SET(tfd, &rf); maxfd = tfd; }
        if (pfd >= 0) { FD_SET(pfd, &rf); if (pfd > maxfd) maxfd = pfd; }
        int r = select(maxfd + 1, &rf, NULL, NULL, NULL);
        if (r < 0) {
            if (errno == EINTR) continue;   /* 信号打断: 回头检查 g_power_exit */
            break;
        }
        if (pfd >= 0 && FD_ISSET(pfd, &rf)) {
            if (read(pfd, &ev, sizeof(ev)) == sizeof(ev) &&
                ev.type == EV_KEY && ev.code == KEY_POWER && ev.value == 1) {
                fprintf(stderr, "[power] exit-to-home\n");
                g_power_exit = 1;
                break;
            }
        }
        if (!argc_taps && tfd >= 0 && FD_ISSET(tfd, &rf)) {
            if (read(tfd, &ev, sizeof(ev)) != sizeof(ev)) break;
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
                if (handle_tap(lastx, lasty) == 1) user_exit = 1;
                lastx = -1;
            }
        }
        if (argc_taps && FD_ISSET(0, &rf)) {
            char ch;
            ssize_t n = read(0, &ch, 1);
            if (n <= 0) { user_exit = 1; break; }   /* stdin EOF */
            if (ch == '\n') {
                line[llen] = 0; llen = 0;
                int tx, ty;
                if (sscanf(line, "%d %d", &tx, &ty) != 2) continue;
                fprintf(stderr, "[tap-stdin] raw=(%d,%d)\n", tx, ty);
                if (handle_tap(tx, ty) == 1) user_exit = 1;
            } else if (llen < (int)sizeof(line) - 1) {
                line[llen++] = ch;
            }
        }
    }

    sync_keepawake();   /* 退出面板: 防休眠跟随服务状态 */
    if (tfd >= 0) close(tfd);
    if (pfd >= 0) close(pfd);
    if (g_power_exit) {
        /* 电源键逃生: 不画任何东西。休眠/唤醒由系统接管, 唤醒时框架
         * 必定全屏重绘回书库; 任何自绘恢复都无法触发框架重绘 (实测)。 */
        fprintf(stderr, "[exit] power-escape (服务保持后台运行)\n");
        return 0;
    }
    /* 正常退出(EXIT 键/EOF): 画退出说明屏(墨水屏特性: 电源键休眠/唤醒必定全屏重绘回书库) */
    runcmd("%s -c -f -q", FBINK);
    runcmd("%s -q -S 3 -y 16 -m 'Panel closed'", FBINK);
    runcmd("%s -q -S 2 -y 28 -m 'services keep running in background'", FBINK);
    runcmd("%s -q -S 2 -y 40 -m 'press POWER (sleep, wake) to return to library'", FBINK);
    runcmd("%s -q -S 2 -y 48 -m 'or reopen: Remote Shell in Documents'", FBINK);
    return 0;
}
