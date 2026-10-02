/* minishelld.c — 极简远程 shell 服务 (raw TCP + pty)
 * 用 nc / telnet 连接即可得到交互式 root shell
 * 编译: zig cc -target arm-linux-musleabi -Os -static
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <netinet/in.h>

int main(int argc, char **argv) {
    int port = (argc > 1) ? atoi(argv[1]) : 2323;

    signal(SIGCHLD, SIG_IGN);

    int ls = socket(AF_INET, SOCK_STREAM, 0);
    if (ls < 0) { perror("socket"); return 1; }
    int one = 1;
    setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_ANY);
    a.sin_port = htons(port);
    if (bind(ls, (struct sockaddr *)&a, sizeof(a)) < 0) { perror("bind"); return 1; }
    if (listen(ls, 4) < 0) { perror("listen"); return 1; }
    dprintf(2, "minisheldd: listening on port %d\n", port);

    for (;;) {
        int c = accept(ls, 0, 0);
        if (c < 0) {
            if (errno == EINTR) continue;
            perror("accept");
            continue;
        }
        pid_t pid = fork();
        if (pid < 0) { close(c); continue; }
        if (pid > 0) { close(c); continue; }

        /* ---- 子进程: 为这个连接分配 pty 并启动 shell ---- */
        close(ls);
        signal(SIGCHLD, SIG_DFL);

        int m = posix_openpt(O_RDWR);
        if (m < 0) { dprintf(c, "minishelld: no pty available\n"); _exit(1); }
        grantpt(m);
        unlockpt(m);
        char *sn = ptsname(m);
        if (!sn) { dprintf(c, "minishelld: ptsname failed\n"); _exit(1); }

        pid_t sp = fork();
        if (sp == 0) {
            /* 孙进程: 在 pty 从端跑 shell */
            setsid();
            int s = open(sn, O_RDWR);
            if (s < 0) _exit(1);
            dup2(s, 0); dup2(s, 1); dup2(s, 2);
            if (s > 2) close(s);
            close(m); close(c);
            setenv("TERM", "vt100", 1);
            execl("/bin/sh", "sh", "-i", (char *)0);
            _exit(127);
        }

        dprintf(c, "\r\n=== minishelld (kindle root shell) ===\r\n");
        dprintf(c, "=== exit: 断开连接即可 ===\r\n\r\n");

        /* 双向泵: socket <-> pty 主端 */
        for (;;) {
            fd_set rf;
            FD_ZERO(&rf); FD_SET(c, &rf); FD_SET(m, &rf);
            if (select((c > m ? c : m) + 1, &rf, 0, 0, 0) < 0) break;
            char buf[4096];
            ssize_t n;
            if (FD_ISSET(c, &rf)) {
                n = read(c, buf, sizeof(buf));
                if (n <= 0) break;
                /* 过滤 telnet IAC 协商序列(兼容 telnet 客户端) */
                char out[4096]; ssize_t w = 0;
                for (ssize_t i = 0; i < n; i++) {
                    unsigned char ch = (unsigned char)buf[i];
                    if (ch == 255) {
                        if (i + 1 >= n) break;
                        unsigned char cmd = (unsigned char)buf[++i];
                        if (cmd == 251 || cmd == 252 || cmd == 253 || cmd == 254) {
                            if (i + 1 < n) i++; /* 跳过选项字节 */
                        }
                        continue;
                    }
                    out[w++] = (char)ch;
                }
                if (w > 0) {
                    ssize_t off = 0;
                    while (off < w) {
                        ssize_t k = write(m, out + off, w - off);
                        if (k <= 0) goto done;
                        off += k;
                    }
                }
            }
            if (FD_ISSET(m, &rf)) {
                n = read(m, buf, sizeof(buf));
                if (n <= 0) break;
                ssize_t off = 0;
                while (off < n) {
                    ssize_t k = write(c, buf + off, n - off);
                    if (k <= 0) goto done;
                    off += k;
                }
            }
        }
    done:
        kill(sp, SIGKILL);
        waitpid(sp, 0, 0);
        _exit(0);
    }
}
