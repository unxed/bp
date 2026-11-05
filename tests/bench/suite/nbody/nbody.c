/* SPDX-License-Identifier: MIT */
/* Benchmark suite (tests/bench/compare.sh): n-body, the C version (the same bodies, the same order of operations;
   the indices are 64-bit, as usize in Rust, int in Go, i64 in Goose and SizeInt in Bp). */
#include <math.h>
#include <stdio.h>

#define STEPS 5000000
#define DT 0.001
#define COUNT 5

typedef struct {
  double x, y, z, vx, vy, vz, m;
} Body;

static Body bodies[COUNT] = {
    {0, 0, 0, 0, 0, 0, 1000},
    {4, 0, 0.5, 0, 15.8113883, 0.1, 1},
    {0, 8, -0.3, -11.1803399, 0, 0.05, 2},
    {-12, 0, 0.8, 0, -9.12870929, -0.07, 3},
    {0, -16, -1, 7.90569415, 0, 0.04, 0.5},
};

static void advance(void) {
  for (long i = 0; i < COUNT - 1; i++)
    for (long j = i + 1; j < COUNT; j++) {
      double dx = bodies[i].x - bodies[j].x;
      double dy = bodies[i].y - bodies[j].y;
      double dz = bodies[i].z - bodies[j].z;
      double d2 = dx * dx + dy * dy + dz * dz;
      double mag = DT / (d2 * sqrt(d2));
      bodies[i].vx = bodies[i].vx - dx * bodies[j].m * mag;
      bodies[i].vy = bodies[i].vy - dy * bodies[j].m * mag;
      bodies[i].vz = bodies[i].vz - dz * bodies[j].m * mag;
      bodies[j].vx = bodies[j].vx + dx * bodies[i].m * mag;
      bodies[j].vy = bodies[j].vy + dy * bodies[i].m * mag;
      bodies[j].vz = bodies[j].vz + dz * bodies[i].m * mag;
    }
  for (long i = 0; i < COUNT; i++) {
    bodies[i].x = bodies[i].x + DT * bodies[i].vx;
    bodies[i].y = bodies[i].y + DT * bodies[i].vy;
    bodies[i].z = bodies[i].z + DT * bodies[i].vz;
  }
}

static double energy(void) {
  double e = 0;
  for (long i = 0; i < COUNT; i++) {
    e = e + 0.5 * bodies[i].m *
                (bodies[i].vx * bodies[i].vx + bodies[i].vy * bodies[i].vy + bodies[i].vz * bodies[i].vz);
    for (long j = i + 1; j < COUNT; j++) {
      double dx = bodies[i].x - bodies[j].x;
      double dy = bodies[i].y - bodies[j].y;
      double dz = bodies[i].z - bodies[j].z;
      e = e - bodies[i].m * bodies[j].m / sqrt(dx * dx + dy * dy + dz * dz);
    }
  }
  return e;
}

int main(void) {
  long long before = (long long)floor(energy() * 1e6 + 0.5);
  for (int s = 0; s < STEPS; s++)
    advance();
  printf("nbody %lld %lld\n", before, (long long)floor(energy() * 1e6 + 0.5));
  return 0;
}
