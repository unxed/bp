/* SPDX-License-Identifier: MIT */
/* Benchmark suite (tests/bench/compare.sh): binary trees, the arena tier, the C version. The nodes of a tree are the
   elements of one grow-only array with 4-byte index links, the layout of bintrees_arena.goose, .rs and .go; dropping
   a tree is setting the length to zero, and a loop of trees keeps the array. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define MAX_DEPTH 16
#define MIN_DEPTH 4
#define NONE 0xFFFFFFFFu

typedef struct {
  uint32_t left, right;
} Node;

typedef struct {
  Node *items;
  uint32_t len, cap;
} Pool;

static uint32_t push(Pool *a) {
  if (a->len == a->cap) {
    a->cap = a->cap ? a->cap * 2 : 16;
    a->items = realloc(a->items, (size_t)a->cap * sizeof(Node));
  }
  a->items[a->len].left = NONE;
  a->items[a->len].right = NONE;
  return a->len++;
}

static uint32_t make(Pool *a, int depth) {
  uint32_t t = push(a);
  if (depth > 0) {
    uint32_t l = make(a, depth - 1);
    a->items[t].left = l;
    uint32_t r = make(a, depth - 1);
    a->items[t].right = r;
  }
  return t;
}

static long long check(const Pool *a, uint32_t t) {
  long long n = 1;
  if (a->items[t].left != NONE)
    n += check(a, a->items[t].left) + check(a, a->items[t].right);
  return n;
}

static long long once(int depth) {
  Pool a = {0, 0, 0};
  long long n = check(&a, make(&a, depth));
  free(a.items);
  return n;
}

static long long many(int depth, long long iterations) {
  Pool a = {0, 0, 0};
  long long total = 0;
  for (long long i = 0; i < iterations; i++) {
    total += check(&a, make(&a, depth));
    a.len = 0;
  }
  free(a.items);
  return total;
}

int main(void) {
  long long total = once(MAX_DEPTH + 1);
  Pool longlived = {0, 0, 0};
  uint32_t root = make(&longlived, MAX_DEPTH);
  for (int depth = MIN_DEPTH; depth <= MAX_DEPTH; depth += 2)
    total += many(depth, 1LL << (MAX_DEPTH - depth + MIN_DEPTH));
  total += check(&longlived, root);
  free(longlived.items);
  printf("bintrees %lld\n", total);
  return 0;
}
