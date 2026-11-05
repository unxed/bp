// SPDX-License-Identifier: MIT
// The same as repro.pas in C: no restrict and noipa (no inlining, no constant propagation into the routine), so gcc
// knows no more about y and x than a Pascal compiler does and checks for an overlap at run time.
// Build: gcc -O3 -o repro_c repro.c; -DINLINE lets gcc inline the routine on the two global arrays (then -O2
// vectorizes it too; -fno-tree-vectorize to compare)
#include <stdio.h>
#include <stdlib.h>

#define N 1024

#ifdef INLINE
static inline
#else
__attribute__((noipa)) static
#endif
void axpy(double *y, const double *x, double a) {
    for (long i = 0; i < N; i++)
        y[i] = y[i] + a * x[i];
}

static double x[N], y[N];

int main(int argc, char **argv) {
    int rounds = argc > 1 ? atoi(argv[1]) : 2000000;
    for (long i = 0; i < N; i++) {
        x[i] = i * 0.5;
        y[i] = 0;
    }
    for (int r = 0; r < rounds; r++)
        axpy(y, x, 1.0e-9);
    double s = 0;
    for (long i = 0; i < N; i++)
        s += y[i];
    printf("%.6f\n", s);
    return 0;
}
