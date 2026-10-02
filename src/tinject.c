/* tinject.c — 触摸事件注入器: 向 /dev/input/eventX 写入合成的触摸事件
 * 用法: tinject <event设备> <x> <y> [y2]   (单点; 带 y2 则从(y)滑到(y2))
 * 编译: zig cc -target arm-linux-musleabi -Os -static -no-pie
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <linux/input.h>
#include <sys/ioctl.h>

static int fd;
static struct input_event ev;

static void emit(unsigned short type, unsigned short code, int value) {
    memset(&ev, 0, sizeof(ev));
    ev.type = type; ev.code = code; ev.value = value;
    if (write(fd, &ev, sizeof(ev)) != sizeof(ev)) perror("write");
}

static void esync(void) { emit(EV_SYN, SYN_REPORT, 0); usleep(30000); }

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage: %s <eventN> <x> <y> [y2]\n", argv[0]); return 1; }
    const char *dev = argv[1];
    int x = atoi(argv[2]), y1 = atoi(argv[3]);
    int y2 = (argc > 4) ? atoi(argv[4]) : y1;

    fd = open(dev, O_WRONLY);
    if (fd < 0) { perror("open"); return 1; }

    /* 触摸按下 */
    emit(EV_ABS, ABS_MT_TRACKING_ID, 1);
    emit(EV_ABS, ABS_MT_POSITION_X, x);
    emit(EV_ABS, ABS_MT_POSITION_Y, y1);
    emit(EV_KEY, BTN_TOUCH, 1);
    esync();
    usleep(80000);

    /* 可选滑动 */
    if (y2 != y1) {
        int steps = 5;
        for (int i = 1; i <= steps; i++) {
            emit(EV_ABS, ABS_MT_POSITION_X, x);
            emit(EV_ABS, ABS_MT_POSITION_Y, y1 + (y2 - y1) * i / steps);
            esync();
            usleep(30000);
        }
    }

    /* 抬起 */
    emit(EV_KEY, BTN_TOUCH, 0);
    emit(EV_ABS, ABS_MT_TRACKING_ID, -1);
    esync();
    close(fd);
    return 0;
}
