/* photoviewer-x.c — 墨水屏触屏相册 (Kindle, UI框架输入栈版)
 *
 * 输入架构 (2026-10-02 探索定稿, 见 NOTES.md):
 *   主通道 = X11 wire 协议直连 (与 kterm/GTK 完全同源的服务端输入管线):
 *     /dev/input/event1 → Xorg multitouch 驱动 → GrabPointer 事件流
 *     - 坐标已由 multitouch 驱动换算为屏幕坐标 (实测公式 round(raw*W/(W-1)))
 *     - 按下(ButtonPress)语义, 避开抬起时重心漂移
 *     - 全局 grab, 独占指针
 *   影子通道 = evdev 直读 (只记录 raw 坐标作对照诊断; X 不可用时降级为输入)
 *   渲染 = fbink (照片 GC16+ORDERED 抖动质量不变)
 *
 * 用法: photoviewer [-a 自动轮播间隔秒] <photos_dir> [fbink路径]
 * 交互:
 *   照片模式: 顶部12%=设置  左40%=上一张  右40%=下一张  中间20%=退出
 *   设置模式: 行区0.22–0.64(6档间隔)  底部0.70–1.0=退出
 * 布局分数常量与 gen-settings.sh 严格对应
 * 编译: zig cc -target arm-linux-musleabi -Os -static -no-pie
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <time.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/select.h>
#include <sys/ioctl.h>
#include <linux/input.h>

#define MAXIMGS 512
#define CONF_FILE   "/mnt/us/photo-kit/photo.conf"
#define SETTINGS_DIR "/mnt/us/photo-kit/settings"

/* 设置页布局(与 gen-settings.sh 一致):
 * 行区 0.16–0.79 七行(每行 0.09; 6 档间隔 + 省电模式), 退出按钮区 0.79–1.0 */
#define SETTINGS_TOP 0.12
#define ROWS_START   0.235
#define ROWS_END     0.865
#define EXIT_ZONE    0.865

#define ROW_SLEEP (-1)   /* 省电模式档 */
static const int row_secs[7] = {30, 60, 300, 600, 1800, 3600, ROW_SLEEP};
#define N_ROWS 7

static char *imgs[MAXIMGS];
static int nimgs = 0, cur = 0;
static char fbink[256] = "/var/local/kmc/bin/fbink";
static int auto_sec = 0;
static int screen_w = 758, screen_h = 1024;   /* 运行时由 X/evdev 探测刷新 */
static int in_settings = 0;
static int sel_row = 3;
static int quit_req = 0;
static time_t last_auto = 0;
static int sleep_mode = 0;      /* 省电模式: RTC 定时深睡换图 (2026-10-02 实证链路) */
static int pwfd = -1;           /* 电源键 (max77696-onkey): 按下=退出回 home 的逃生通道 */
static volatile sig_atomic_t g_power = 0;

/* 电源键/SIGUSR1 共用退出路径 (SIGUSR1 = 远程测试钩子) */
static void on_power_sig(int s) { (void)s; g_power = 1; }

/* 深睡一轮: 写 RTC 闹钟 → 停 powerd(解除 mem 的 EBUSY 锁) → 深睡 → 恢复 powerd。
 * 醒来源: RTC 到点(实证精确) 或 电源键; 触摸不唤醒深睡。
 * 返回后进程继续跑, 由调用方决定换图或进交互。 */
static void sleep_once(int secs) {
    FILE *f = fopen("/sys/class/rtc/rtc0/since_epoch", "r");
    if (!f) return;
    long now = 0;
    if (fscanf(f, "%ld", &now) != 1) { fclose(f); return; }
    fclose(f);
    f = fopen("/sys/class/rtc/rtc0/wakealarm", "w");
    if (!f) return;
    fprintf(f, "%ld", now + secs);
    fclose(f);
    system("stop powerd 2>/dev/null");
    sleep(1);
    fprintf(stderr, "[sleep] mem %ds ...\n", secs);
    fflush(stderr);
    f = fopen("/sys/power/state", "w");
    if (f) { fprintf(f, "mem"); fclose(f); }   /* 阻塞至唤醒 */
    fprintf(stderr, "[sleep] awake\n");
    system("start powerd 2>/dev/null");
    /* 拦住刚复活的 powerd 按自己的 idle 策略抢先 suspend(会无闹钟睡死) */
    system("lipc-set-prop -i com.lab126.powerd preventScreenSaver 1 2>/dev/null");
    fflush(stderr);
}

/* ================= X11 wire 客户端 (零依赖) =================
 * 协议要点 (血泪教训, 改前先读):
 *  - setup 回复的附加数据长度是 u16@offset6 (不是普通 reply 的 u32@4)
 *  - GrabPointer: opcode=26 (29 是 UngrabButton!), 请求 24 字节 length=6,
 *    event-mask 是紧打包 CARD16
 *  - 事件首字节 = type | (send_event<<7), type: 4=ButtonPress 5=ButtonRelease
 *  - root-x/root-y 在事件 offset 20/22 (u16 LE)
 */
static int xfd = -1;

static int x11_connect(void) {
    const char *disp = getenv("DISPLAY");
    int dnum = disp ? atoi(strchr(disp, ':') ? strchr(disp, ':') + 1 : "0") : 0;
    char path[64];
    snprintf(path, sizeof(path), "/tmp/.X11-unix/X%d", dnum);
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    struct sockaddr_un sa;
    memset(&sa, 0, sizeof(sa));
    sa.sun_family = AF_UNIX;
    strncpy(sa.sun_path, path, sizeof(sa.sun_path) - 1);
    if (connect(fd, (struct sockaddr *)&sa, sizeof(sa)) < 0) { close(fd); return -1; }
    return fd;
}

static int x11_setup(int fd, unsigned int *oroot) {
    unsigned char hs[12] = {'l', 0, 11, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    if (write(fd, hs, 12) != 12) return -1;
    unsigned char r[8];
    if (read(fd, r, 8) != 8 || r[0] != 1) return -1;
    unsigned short extra16;
    memcpy(&extra16, r + 6, 2);            /* u16@6: 附加数据长度(4字节单位) */
    unsigned int total = (unsigned int)extra16 * 4;
    if (total > 65536) return -1;
    unsigned char *body = malloc(total);
    if (!body) return -1;
    unsigned int got = 0;
    while (got < total) {
        int n = read(fd, body + got, total - got);
        if (n <= 0) { free(body); return -1; }
        got += n;
    }
    unsigned short vlen; memcpy(&vlen, body + 16, 2);
    unsigned char nformats = body[21];
    unsigned char *p = body + 32 + ((vlen + 3) & ~3u) + nformats * 8;
    if (p + 24 > body + total) { free(body); return -1; }
    unsigned int root; memcpy(&root, p, 4);
    unsigned short w, h;
    memcpy(&w, p + 20, 2); memcpy(&h, p + 22, 2);
    free(body);
    if (oroot) *oroot = root;
    if (w > 100 && h > 100) { screen_w = w; screen_h = h; }
    return 0;
}

static int x11_grab(int fd, unsigned int root) {
    unsigned char q[24];
    memset(q, 0, sizeof(q));
    unsigned short len = 6, mask = (1 << 2) | (1 << 3); /* press|release */
    q[0] = 26;                    /* GrabPointer */
    q[1] = 1;                     /* owner-events */
    memcpy(q + 2, &len, 2);
    memcpy(q + 4, &root, 4);
    memcpy(q + 8, &mask, 2);
    q[10] = 1; q[11] = 1;         /* async/async */
    if (write(fd, q, 24) != 24) return -1;
    unsigned char rep[32];
    if (read(fd, rep, 32) != 32) return -1;
    if (rep[0] != 1) return -1;
    return rep[1];                /* 0 = GrabSuccess */
}

static int x11_init(void) {
    xfd = x11_connect();
    if (xfd < 0) return -1;
    unsigned int root = 0;
    if (x11_setup(xfd, &root) < 0) { close(xfd); xfd = -1; return -1; }
    int g = x11_grab(xfd, root);
    if (g != 0) {
        fprintf(stderr, "x11: grab failed status=%d\n", g);
        close(xfd); xfd = -1;
        return -1;
    }
    fprintf(stderr, "x11: ok root=0x%x %dx%d (grabbed)\n", root, screen_w, screen_h);
    return 0;
}

/* ================= evdev 影子/回退通道 ================= */
static int evfd = -1;
static int ev_xmax = 757, ev_ymax = 1023;

static int ev_open(void) {
    struct input_absinfo ai;
    for (int i = 0; i < 8 && evfd < 0; i++) {
        char path[32];
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        int f = open(path, O_RDONLY | O_NONBLOCK);
        if (f < 0) continue;
        char name[64] = "";
        ioctl(f, EVIOCGNAME(sizeof(name) - 1), name);
        if (ioctl(f, EVIOCGABS(ABS_MT_POSITION_X), &ai) != 0 || strstr(name, "onkey")) {
            close(f); continue;
        }
        if (ai.maximum > 0) ev_xmax = ai.maximum;
        if (ioctl(f, EVIOCGABS(ABS_MT_POSITION_Y), &ai) == 0 && ai.maximum > 0)
            ev_ymax = ai.maximum;
        fprintf(stderr, "evdev: %s (%s) %dx%d\n", path, name, ev_xmax, ev_ymax);
        evfd = f;
    }
    return evfd;
}

/* 消化可用事件; 返回 1 表示捕捉到一次完整点按(坐标写回), 0 无 */
static int ev_poll(int *ox, int *oy) {
    if (evfd < 0) return 0;
    struct input_event ev;
    static int lastx = -1, lasty = -1, down = 0;
    int hit = 0;
    while (read(evfd, &ev, sizeof(ev)) == sizeof(ev)) {
        if (ev.type == EV_ABS) {
            switch (ev.code) {
                case ABS_MT_POSITION_X: case ABS_X: lastx = ev.value; break;
                case ABS_MT_POSITION_Y: case ABS_Y: lasty = ev.value; break;
                case ABS_MT_TRACKING_ID: if (ev.value < 0) down = 0; break;
            }
        } else if (ev.type == EV_KEY && ev.code == BTN_TOUCH) {
            down = ev.value;
        } else if (ev.type == EV_SYN && ev.code == SYN_REPORT && !down && lastx >= 0) {
            *ox = lastx; *oy = lasty;
            lastx = -1;
            hit = 1;
        }
    }
    return hit;
}

/* 电源键设备 (max77696-onkey, event0): ev_open 会跳过它, 这里专门打开 */
static int pw_open(void) {
    for (int i = 0; i < 8; i++) {
        char path[32];
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        int f = open(path, O_RDONLY | O_NONBLOCK);
        if (f < 0) continue;
        char name[64] = "";
        ioctl(f, EVIOCGNAME(sizeof(name) - 1), name);
        if (strstr(name, "onkey")) {
            fprintf(stderr, "power-key: %s (%s) — 按下=退出回 home\n", path, name);
            return f;
        }
        close(f);
    }
    fprintf(stderr, "power-key: 未找到 onkey 设备, 电源键退出不可用\n");
    return -1;
}

/* ================= 相册逻辑 (沿用 photoviewer.c) ================= */
static int cmpstr(const void *a, const void *b) {
    return strcmp(*(char *const *)a, *(char *const *)b);
}

static void load_dir(const char *d) {
    DIR *dp = opendir(d);
    if (!dp) { perror("opendir"); exit(1); }
    struct dirent *e;
    while ((e = readdir(dp)) && nimgs < MAXIMGS) {
        const char *nm = e->d_name;
        size_t l = strlen(nm);
        if (nm[0] == '.' || l < 4 || strcmp(nm + l - 4, ".png") != 0) continue;
        char full[512];
        snprintf(full, sizeof(full), "%s/%s", d, nm);
        imgs[nimgs++] = strdup(full);
    }
    closedir(dp);
    qsort(imgs, nimgs, sizeof(char *), cmpstr);
}

static void run(const char *fmt, ...) {
    char cmd[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(cmd, sizeof(cmd), fmt, ap);
    va_end(ap);
    fprintf(stderr, "[run] %s\n", cmd);
    int rc = system(cmd);
    (void)rc;
    fflush(stderr); fflush(stdout);
}

static void show(int idx, int flash) {
    cur = ((idx % nimgs) + nimgs) % nimgs;
    run("%s -c %s -W GC16 -D ORDERED -i '%s' >/dev/null 2>&1",
        fbink, flash ? "-f" : "", imgs[cur]);
    printf("[viewer] %d/%d %s\n", cur + 1, nimgs, imgs[cur]);
    last_auto = time(NULL);
}

/* 设置页 PNG: 选中间隔行(浅灰高亮+√)与省电 checkbox 状态已烘焙, 组合取图 */
static void show_settings_page(void) {
    run("%s -c -f -W GC16 -D ORDERED -i '%s/r%ds%d.png' >/dev/null 2>&1",
        fbink, SETTINGS_DIR, sel_row, sleep_mode);
}

static void write_conf(void) {
    FILE *f = fopen(CONF_FILE, "w");
    if (f) {
        fprintf(f, "# Photo 相册配置 (由设置界面写入)\nINTERVAL=%d\nSLEEP=%d\n",
                auto_sec, sleep_mode);
        fclose(f);
    }
}

static void draw_status_line(void);
static void open_settings(void) {
    in_settings = 1;
    show_settings_page();
    draw_status_line();
    printf("[viewer] 设置页 (当前 %d 秒)\n", auto_sec);
}

static void close_settings(int changed) {
    in_settings = 0;
    if (changed) {
        write_conf();
        printf("[viewer] 间隔 %d 秒%s\n", auto_sec,
               sleep_mode ? " + 省电模式(电源键唤醒)" : "");
        last_auto = time(NULL);
    }
    show(cur, 1);
}

/* 设置页状态行: 标题下方居中显示 "HH:MM NN%" (时间+电量, 运行时动态) */
static void draw_status_line(void) {
    time_t now = time(NULL);
    struct tm tmv;
    gmtime_r(&now, &tmv);
    tmv.tm_hour = (tmv.tm_hour + 8) % 24;   /* UTC+8 (musl 静态无 tz 数据库, 硬偏移) */
    char ts[8];
    snprintf(ts, sizeof(ts), "%02d:%02d", tmv.tm_hour, tmv.tm_min);
    int pct = -1;
    FILE *p = popen("gasgauge-info -c 2>/dev/null", "r");
    if (p) {
        if (fscanf(p, "%d", &pct) != 1) pct = -1;
        pclose(p);
    }
    /* 顶部状态行: 放大字号 (fbink -S 是 8px 基础字形倍数, 不随 DPI 换算,
     * 老机 S2=32px / 新机 S3=48px 物理尺寸才接近), 行号两台标定 */
    int sv = (screen_h <= 1024) ? 4 : 5;
    int voff = (screen_h <= 1024) ? 16 : 24;   /* 8pt 网格顶部边距 */
    if (pct >= 0)
        run("%s -m -y 0 -Y %d -S %d -f '%s %d%%' >/dev/null 2>&1", fbink, voff, sv, ts, pct);
    else
        run("%s -m -y 0 -Y %d -S %d -f '%s' >/dev/null 2>&1", fbink, voff, sv, ts);
}

/* x,y 为屏幕坐标 (X 通道已完成 raw->screen 换算; evdev 回退时已按比例折算) */
static void handle_tap(int x, int y, const char *src) {
    float xf = (float)x / screen_w, yf = (float)y / screen_h;
    fprintf(stderr, "[tap:%s] screen=(%d,%d) frac=(%.3f,%.3f) in_settings=%d\n",
            src, x, y, xf, yf, in_settings);
    fflush(stderr);
    if (in_settings) {
        if (yf >= EXIT_ZONE) {                 /* 底部按钮区: 退出应用 */
            printf("[viewer] 退出应用\n");
            quit_req = 1;
            in_settings = 0;
            return;
        }
        if (yf >= ROWS_START && yf < ROWS_END) {   /* 行区 */
            int idx = (int)((yf - ROWS_START) / ((ROWS_END - ROWS_START) / N_ROWS));
            if (idx == N_ROWS - 1) {
                /* 省电模式 checkbox: 切换开关, 停留设置页(与间隔档组合使用) */
                sleep_mode = !sleep_mode;
                write_conf();
                printf("[viewer] 省电模式%s\n", sleep_mode ? "开" : "关");
                show_settings_page();
                draw_status_line();
            } else if (idx >= 0 && idx < N_ROWS - 1) {
                sel_row = idx;
                auto_sec = row_secs[idx];
                show_settings_page();
                draw_status_line();
                sleep(1);
                close_settings(1);
            }
            return;
        }
        close_settings(0);                  /* 其它区域: 回照片展示 */
        return;
    }
    if (yf < SETTINGS_TOP) { open_settings(); return; }
    if (x < screen_w * 40 / 100) show(cur - 1, 0);
    else if (x > screen_w * 60 / 100) show(cur + 1, 0);
    else printf("[viewer] 中区 -> 退出\n"), quit_req = 1;
}

int main(int argc, char **argv) {
    int argi = 1;
    if (argc >= 3 && strcmp(argv[1], "-a") == 0) { auto_sec = atoi(argv[2]); argi = 3; }
    if (argi < argc && strcmp(argv[argi], "-s") == 0) { sleep_mode = 1; argi++; }
    if (argc <= argi) {
        fprintf(stderr, "usage: %s [-a auto_sec] [-s] <photos_dir> [fbink_path]\n", argv[0]);
        return 1;
    }
    load_dir(argv[argi]);
    if (argc > argi + 1) snprintf(fbink, sizeof(fbink), "%s", argv[argi + 1]);
    if (!nimgs) { fprintf(stderr, "no png in %s\n", argv[argi]); return 1; }

    for (int i = 0; i < N_ROWS - 1; i++) if (row_secs[i] == auto_sec) sel_row = i;

    setbuf(stdout, NULL);
    fprintf(stderr, "viewer-x: %d images, auto=%ds, fbink=%s\n", nimgs, auto_sec, fbink);
    system("lipc-set-prop -i com.lab126.powerd preventScreenSaver 1 2>/dev/null");

    /* 电源键逃生 + SIGUSR1 远程测试钩子: 按下=干净退出, Photo.sh 的 show_ui 恢复 home */
    {
        struct sigaction sa;
        memset(&sa, 0, sizeof(sa));
        sa.sa_handler = on_power_sig;
        sigaction(SIGUSR1, &sa, NULL);
        sigaction(SIGINT, &sa, NULL);
        pwfd = pw_open();
    }

    /* 防御: 设置页资产缺失时提前告警(避免 fbink 静默失败后屏幕残留旧画面) */
    {
        char p[128];
        snprintf(p, sizeof(p), "%s/r%ds0.png", SETTINGS_DIR, sel_row);
        if (access(p, R_OK) != 0)
            fprintf(stderr, "警告: 设置页资产缺失 %s (部署命名须为 r{0..5}s{0|1}.png)\n", p);
    }

    int have_x = (x11_init() == 0);
    ev_open();
    if (!have_x) fprintf(stderr, "x11: 不可用, 降级 evdev 输入\n");
    else if (evfd >= 0) fprintf(stderr, "evdev: 影子模式(仅记录raw对照)\n");

    show(0, 1);

    while (!quit_req) {
        fd_set rfds;
        FD_ZERO(&rfds);
        int maxfd = -1;
        if (xfd >= 0) { FD_SET(xfd, &rfds); if (xfd > maxfd) maxfd = xfd; }
        if (evfd >= 0) { FD_SET(evfd, &rfds); if (evfd > maxfd) maxfd = evfd; }
        if (pwfd >= 0) { FD_SET(pwfd, &rfds); if (pwfd > maxfd) maxfd = pwfd; }
        struct timeval tv = {1, 0};
        int r = select(maxfd + 1, &rfds, NULL, NULL, &tv);
        if (r < 0) {
            if (errno == EINTR) {
                if (g_power) {
                    fprintf(stderr, "[power] SIGUSR1 -> exit-to-home\n");
                    quit_req = 1;
                }
                continue;
            }
            break;
        }

        if (pwfd >= 0 && FD_ISSET(pwfd, &rfds)) {
            struct input_event pev;
            while (read(pwfd, &pev, sizeof(pev)) == sizeof(pev)) {
                if (pev.type == EV_KEY && pev.code == KEY_POWER && pev.value == 1) {
                    fprintf(stderr, "[power] pressed -> exit-to-home\n");
                    quit_req = 1;
                }
            }
        }
        if (xfd >= 0 && FD_ISSET(xfd, &rfds)) {
            unsigned char ev[32];
            int n = read(xfd, ev, 32);
            if (n <= 0) {                 /* X 掉线: 降级 evdev */
                fprintf(stderr, "x11: 连接断开, 降级 evdev\n");
                close(xfd); xfd = -1;
            } else if (n == 32) {
                int type = ev[0] & 0x7f;
                if (type == 4 && ev[1] == 1) {      /* ButtonPress button1 = 按下 */
                    unsigned short px, py;
                    memcpy(&px, ev + 20, 2); memcpy(&py, ev + 22, 2);
                    handle_tap(px, py, "x11-press");
                }
            }
        }
        if (evfd >= 0 && FD_ISSET(evfd, &rfds)) {
            int rx, ry;
            if (ev_poll(&rx, &ry)) {
                if (xfd >= 0) {
                    /* 影子模式: 只记录 raw, 与 X press 坐标做对照 */
                    fprintf(stderr, "[shadow] raw=(%d,%d) frac=(%.3f,%.3f)\n",
                            rx, ry, (float)rx / ev_xmax, (float)ry / ev_ymax);
                    fflush(stderr);
                } else {
                    /* 回退模式: raw 折算到屏幕坐标后作为输入 */
                    int sx = rx * screen_w / (ev_xmax + 1);
                    int sy = ry * screen_h / (ev_ymax + 1);
                    handle_tap(sx, sy, "evdev");
                }
            }
        }
        if (auto_sec > 0 && !in_settings &&
            time(NULL) - last_auto >= auto_sec) {
            if (sleep_mode) {
                /* 省电模式: 深睡到点(RTC/电源键唤醒)再换图。
                 * 电源键唤醒的用户有触摸宽限进交互; RTC 唤醒直接继续。 */
                sleep_once(auto_sec);
                show(cur + 1, 0);
            } else {
                show(cur + 1, 0);
            }
        }
    }
    if (xfd >= 0) close(xfd);   /* 断连即自动释放 grab */
    if (evfd >= 0) close(evfd);
    if (pwfd >= 0) close(pwfd);
    printf("[viewer] 退出%s\n", g_power || quit_req ? "(power->home)" : "");
    return 0;
}
