/* SPDX-License-Identifier: MIT */
/* Benchmark suite (tests/bench/compare.sh): fannkuch, the C version (the same loops). */
#include <stdio.h>
#include <string.h>

#define N 10

static int flips(const int *p) {
  int q[N];
  memcpy(q, p, sizeof q);
  int result = 0;
  int k = q[0];
  while (k != 0) {
    int i = 0, j = k;
    while (i < j) {
      int t = q[i];
      q[i] = q[j];
      q[j] = t;
      i++;
      j--;
    }
    result++;
    k = q[0];
  }
  return result;
}

static int next(int *p) {
  int i = N - 2;
  while (i >= 0 && p[i] > p[i + 1])
    i--;
  if (i < 0)
    return 0;
  int j = N - 1;
  while (p[j] < p[i])
    j--;
  int t = p[i];
  p[i] = p[j];
  p[j] = t;
  i = i + 1;
  j = N - 1;
  while (i < j) {
    t = p[i];
    p[i] = p[j];
    p[j] = t;
    i++;
    j--;
  }
  return 1;
}

int main(void) {
  int p[N];
  for (int i = 0; i < N; i++)
    p[i] = i;
  long long index = 0, checksum = 0;
  int max_flips = 0;
  do {
    int f = flips(p);
    if (f > max_flips)
      max_flips = f;
    if (index % 2 == 0)
      checksum += f;
    else
      checksum -= f;
    index++;
  } while (next(p));
  printf("fannkuch %lld %d\n", checksum, max_flips);
  return 0;
}
