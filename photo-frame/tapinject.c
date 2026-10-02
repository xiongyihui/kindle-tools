/* tapinject.c — 向触摸设备注入一次点按 (自动化测试用)
 * 用法: tapinject <x> <y>
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <linux/input.h>
#include <sys/ioctl.h>

static void send(int fd, int type, int code, int value) {
    struct input_event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = type; ev.code = code; ev.value = value;
    if (write(fd, &ev, sizeof(ev)) != sizeof(ev)) perror("write");
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: %s <x> <y>\n", argv[0]); return 1; }
    int x = atoi(argv[1]), y = atoi(argv[2]);
    int fd = -1;
    struct input_absinfo ai;
    for (int i = 0; i < 8 && fd < 0; i++) {
        char path[32];
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        int f = open(path, O_WRONLY);
        if (f < 0) continue;
        char name[64] = "";
        ioctl(f, EVIOCGNAME(sizeof(name) - 1), name);
        if (ioctl(f, EVIOCGABS(ABS_MT_POSITION_X), &ai) != 0 || strstr(name, "onkey")) {
            close(f); continue;
        }
        fprintf(stderr, "inject to %s (%s)\n", path, name);
        fd = f;
    }
    if (fd < 0) { fprintf(stderr, "no touch device (writable)\n"); return 1; }
    send(fd, EV_ABS, ABS_MT_TRACKING_ID, 1);
    send(fd, EV_ABS, ABS_MT_POSITION_X, x);
    send(fd, EV_ABS, ABS_MT_POSITION_Y, y);
    send(fd, EV_KEY, BTN_TOUCH, 1);
    send(fd, EV_SYN, SYN_REPORT, 0);
    usleep(80000);
    send(fd, EV_ABS, ABS_MT_TRACKING_ID, -1);
    send(fd, EV_KEY, BTN_TOUCH, 0);
    send(fd, EV_SYN, SYN_REPORT, 0);
    close(fd);
    return 0;
}
