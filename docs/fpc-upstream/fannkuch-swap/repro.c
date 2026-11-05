// SPDX-License-Identifier: MIT
// The swap loop of fannkuch: reverse the first K+1 elements of an array in place, many times.
// Build: gcc -O2 -S repro.c; gcc -O2 -o repro_c repro.c; run: ./repro_c [rounds]
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define N 256

static int32_t run(int32_t rounds)
{
    int32_t a[N];  // int32_t, as LongInt in repro.pas
    int32_t r, i, j, t, result;
    for (i = 0; i <= N - 1; i++)
        a[i] = i;
    result = 0;
    for (r = 1; r <= rounds; r++) {
        i = 0;
        j = r & (N - 1);
        while (i < j) {
            t = a[i];
            a[i] = a[j];
            a[j] = t;
            i++;
            j--;
        }
        result = result + a[0];
    }
    return result;
}

int main(int argc, char **argv)
{
    int32_t rounds = 10000000;
    if (argc > 1)
        rounds = (int32_t)atol(argv[1]);
    printf("%d\n", (int)run(rounds));
    return 0;
}
