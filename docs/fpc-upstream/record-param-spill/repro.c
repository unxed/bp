// SPDX-License-Identifier: MIT
// The same as repro.pas in C: the pool passed by value (a struct of a pointer and a count).
// Build: gcc -O2 -o repro_c repro.c; run: ./repro_c [rounds]
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define NONE UINT32_MAX
#define DEPTH 16

typedef struct { uint32_t left, right; } Node;
typedef struct { Node *items; uint32_t len; } Pool;

static uint32_t make(Pool *a, int d) {
    uint32_t r = a->len++;
    a->items[r].left = NONE;
    a->items[r].right = NONE;
    if (d > 0) {
        uint32_t l = make(a, d - 1);
        a->items[r].left = l;
        uint32_t rr = make(a, d - 1);
        a->items[r].right = rr;
    }
    return r;
}

static long long check(const Pool a, uint32_t t) {
    long long n = 1;
    if (a.items[t].left != NONE)
        n += check(a, a.items[t].left) + check(a, a.items[t].right);
    return n;
}

int main(int argc, char **argv) {
    int rounds = argc > 1 ? atoi(argv[1]) : 400;
    Pool a = { malloc(sizeof(Node) << (DEPTH + 1)), 0 };
    uint32_t root = make(&a, DEPTH);
    long long sum = 0;
    for (int i = 0; i < rounds; i++)
        sum += check(a, root);
    printf("%lld\n", sum);
    return 0;
}
