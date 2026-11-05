// SPDX-License-Identifier: MIT
// The start time of a program for tests/bench/size.sh: runs PROGRAM N times one after another (posix_spawn, then wait,
// output to /dev/null) and prints the mean wall time of one run in microseconds. A runner in C keeps the cost of a
// shell out of the number.
// usage: spawn N PROGRAM
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: spawn N PROGRAM\n");
        return 2;
    }
    int n = atoi(argv[1]);
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addopen(&fa, 1, "/dev/null", O_WRONLY, 0);
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < n; i++) {
        pid_t pid;
        int st;
        if (posix_spawn(&pid, argv[2], &fa, NULL, argv + 2, environ) != 0) {
            perror("posix_spawn");
            return 1;
        }
        if (waitpid(pid, &st, 0) < 0 || !WIFEXITED(st) || WEXITSTATUS(st) != 0) {
            fprintf(stderr, "run %d failed\n", i);
            return 1;
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double us = (t1.tv_sec - t0.tv_sec) * 1e6 + (t1.tv_nsec - t0.tv_nsec) / 1e3;
    printf("%.1f\n", us / n);
    return 0;
}
