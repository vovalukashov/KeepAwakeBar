// Session-only privileged broker. No arbitrary commands, no persistent installation.
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/event.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/poll.h>
#include <sys/proc_info.h>
#include <libproc.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

static int run_pmset(char value) {
    pid_t child = fork();
    if (child == 0) {
        char *args[] = {"/usr/bin/pmset", "-a", "disablesleep", value == '1' ? "1" : "0", NULL};
        char *env[] = {"PATH=/usr/bin:/bin", "LANG=C", NULL};
        execve(args[0], args, env);
        _exit(127);
    }
    if (child < 0) return 1;
    int status = 0;
    for (int i = 0; i < 100; i++) {
        pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child) return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
        if (result < 0 && errno != EINTR) return 1;
        usleep(100000);
    }
    kill(child, SIGKILL);
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) {}
    return 1;
}

int main(int argc, char **argv) {
    if (geteuid() != 0 || argc != 5) return 1;
    char *end;
    long parent = strtol(argv[1], &end, 10);
    if (*end || parent <= 1 || parent > INT32_MAX) return 2;
    unsigned long owner = strtoul(argv[2], &end, 10);
    if (*end || owner == 0 || owner > UINT32_MAX) return 2;
    unsigned long long birth = strtoull(argv[3], &end, 10);
    if (*end || !birth) return 2;
    // Socket name is constrained to /private/tmp and a UUID, never an arbitrary path.
    const char *prefix = "/private/tmp/KeepAwakeBar-";
    const char *path = argv[4];
    if (strlen(path) != strlen(prefix) + 36 + 5 || strncmp(path, prefix, strlen(prefix)) || strcmp(path + strlen(path)-5, ".sock")) return 2;
    for (size_t i = strlen(prefix); i < strlen(prefix)+36; i++) {
        if (!((path[i] >= '0' && path[i] <= '9') || (path[i] >= 'A' && path[i] <= 'F') || path[i] == '-')) return 2;
    }
    struct proc_bsdinfo info;
    if (proc_pidinfo((pid_t)parent, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info) || info.pbi_uid != owner || info.pbi_start_tvsec != birth) return 3;
    int queue = kqueue();
    struct kevent event;
    EV_SET(&event, parent, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
    if (queue < 0 || kevent(queue, &event, 1, NULL, 0, NULL) < 0) return 3;
    int listener = socket(AF_UNIX, SOCK_STREAM, 0);
    if (listener < 0) return 4;
    struct sockaddr_un address = {0};
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, path, sizeof(address.sun_path));
    umask(077);
    // Never delete or replace an existing path; bind must create our socket.
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) < 0) return 4;
    // Keep socket owned by root to protect its pathname in the sticky /tmp directory.
    // Other processes may connect but cannot issue commands without matching PID + UID.
    if (chmod(path, 0666) || listen(listener, 8)) { unlink(path); return 4; }
    signal(SIGPIPE, SIG_IGN);
    struct pollfd fds[] = {{queue, POLLIN, 0}, {listener, POLLIN, 0}};
    int authenticated = 0;
    time_t deadline = time(NULL) + 60;
    while (1) {
        if (!authenticated && time(NULL) > deadline) break;
        int ready = poll(fds, 2, 1000);
        if (ready < 0) { if (errno == EINTR) continue; break; }
        if (fds[0].revents) break;
        if (!(fds[1].revents & POLLIN)) continue;
        int client = accept(listener, NULL, NULL);
        if (client < 0) continue;
        uid_t uid; gid_t gid; pid_t pid = 0; socklen_t length = sizeof(pid);
        if (getpeereid(client, &uid, &gid) || getsockopt(client, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) || uid != owner || pid != parent) { close(client); continue; }
        struct timeval timeout = {2, 0};
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
        char command;
        char result = 'E';
        if (read(client, &command, 1) == 1) {
            // Revalidate birth time on every request to guard PID reuse.
            if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) == sizeof(info) && info.pbi_start_tvsec == birth && info.pbi_uid == owner) {
                authenticated = 1;
                if (command == 'P') result = 'K';
                else if (command == '0' || command == '1') result = run_pmset(command) == 0 ? 'K' : 'E';
            }
        }
        write(client, &result, 1);
        close(client);
    }
    close(listener);
    close(queue);
    unlink(path);
    return 0;
}
