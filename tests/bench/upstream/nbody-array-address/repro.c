// SPDX-License-Identifier: MIT
#include <math.h>
#include <stdio.h>

#define DT 0.001

struct body { double x, y, z, vx, vy, vz, m; };
static struct body b[5];

int main(void) {
  for (int i = 0; i < 5; i++) {
    b[i].x = i; b[i].y = 2 * i; b[i].z = 0.5 * i + 1;
    b[i].vx = 0; b[i].vy = 0; b[i].vz = 0; b[i].m = i + 1;
  }
  for (int s = 1; s <= 4000000; s++)
    for (int i = 0; i <= 3; i++)
      for (int j = i + 1; j <= 4; j++) {
        double dx = b[i].x - b[j].x;
        double dy = b[i].y - b[j].y;
        double dz = b[i].z - b[j].z;
        double d2 = dx * dx + dy * dy + dz * dz;
        double mag = DT / (d2 * sqrt(d2));
        b[i].vx = b[i].vx - dx * b[j].m * mag;
        b[i].vy = b[i].vy - dy * b[j].m * mag;
        b[i].vz = b[i].vz - dz * b[j].m * mag;
        b[j].vx = b[j].vx + dx * b[i].m * mag;
        b[j].vy = b[j].vy + dy * b[i].m * mag;
        b[j].vz = b[j].vz + dz * b[i].m * mag;
      }
  printf("%.6f %.6f\n", b[0].vx, b[4].vz);
  return 0;
}
