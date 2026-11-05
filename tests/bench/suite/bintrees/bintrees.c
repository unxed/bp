/* SPDX-License-Identifier: MIT */
/* Benchmark suite (tests/bench/compare.sh): binary trees, the tier with one heap block per node, the C version (malloc and free, one call per node). */
#include <stdio.h>
#include <stdlib.h>

#define MAX_DEPTH 16
#define MIN_DEPTH 4

typedef struct Node {
  struct Node *left, *right;
} Node;

static Node *make(int depth) {
  Node *t = malloc(sizeof(Node));
  t->left = NULL;
  t->right = NULL;
  if (depth > 0) {
    t->left = make(depth - 1);
    t->right = make(depth - 1);
  }
  return t;
}

static long long check(const Node *t) {
  long long n = 1;
  if (t->left != NULL)
    n += check(t->left) + check(t->right);
  return n;
}

static void drop(Node *t) {
  if (t->left != NULL) {
    drop(t->left);
    drop(t->right);
  }
  free(t);
}

static long long once(int depth) {
  Node *t = make(depth);
  long long n = check(t);
  drop(t);
  return n;
}

static long long many(int depth, long long iterations) {
  long long total = 0;
  for (long long i = 0; i < iterations; i++)
    total += once(depth);
  return total;
}

int main(void) {
  long long total = once(MAX_DEPTH + 1);
  Node *longlived = make(MAX_DEPTH);
  for (int depth = MIN_DEPTH; depth <= MAX_DEPTH; depth += 2)
    total += many(depth, 1LL << (MAX_DEPTH - depth + MIN_DEPTH));
  total += check(longlived);
  drop(longlived);
  printf("bintrees %lld\n", total);
  return 0;
}
