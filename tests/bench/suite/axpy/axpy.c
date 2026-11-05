/* SPDX-License-Identifier: MIT */
/* Benchmark suite (tests/bench/compare.sh): axpy, the C version. The loop y[i] = y[i] + a * x[i] over two global
   arrays of 1024 doubles, 2,000,000 rounds: gcc -O2 vectorizes it (the arrays are distinct). The same numbers as
   axpy.pas, axpy.rs, axpy.go and axpy.goose; the sum at the end is a plain loop, so every language prints the same
   line. */
#include <math.h>
#include <stdio.h>

#define N 1024
#define ROUNDS 2000000

static double x[N], y[N];

int main(void) {
  for (long i = 0; i < N; i++) {
    x[i] = i * 0.5;
    y[i] = 0;
  }
  for (int r = 0; r < ROUNDS; r++)
    for (long i = 0; i < N; i++)
      y[i] = y[i] + 1.0e-9 * x[i];
  double s = 0;
  for (long i = 0; i < N; i++)
    s += y[i];
  printf("axpy %lld\n", (long long)floor(s * 1e6 + 0.5));
  return 0;
}
