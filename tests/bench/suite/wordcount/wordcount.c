/* SPDX-License-Identifier: MIT */
/* Benchmark suite (tests/bench/compare.sh): a word count, the C version. The words are counted in place (a pointer
   into the text and a length); the table is the one of wordcount.pas (FNV-1a of 32 bits, open addressing). */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TABLE_BITS 17
#define TABLE_SIZE (1u << TABLE_BITS)

typedef struct {
  const char *key; /* NULL marks a free slot */
  size_t len;
  long long count;
} Entry;

static Entry table[TABLE_SIZE];

static uint32_t hash(const char *p, size_t len) {
  uint32_t h = 2166136261u;
  for (size_t i = 0; i < len; i++)
    h = (h ^ (unsigned char)p[i]) * 16777619u;
  return h;
}

/* adds one to the count of the word; 1 when the word is new */
static int add(const char *p, size_t len) {
  uint32_t slot = hash(p, len) & (TABLE_SIZE - 1);
  while (table[slot].key != NULL) {
    if (table[slot].len == len && memcmp(table[slot].key, p, len) == 0) {
      table[slot].count++;
      return 0;
    }
    slot = (slot + 1) & (TABLE_SIZE - 1);
  }
  table[slot].key = p;
  table[slot].len = len;
  table[slot].count = 1;
  return 1;
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: wordcount FILE\n");
    return 2;
  }
  FILE *f = fopen(argv[1], "rb");
  if (f == NULL) {
    perror(argv[1]);
    return 1;
  }
  fseek(f, 0, SEEK_END);
  size_t size = (size_t)ftell(f);
  fseek(f, 0, SEEK_SET);
  char *text = malloc(size + 1);
  if (fread(text, 1, size, f) != size) {
    fprintf(stderr, "read error\n");
    return 1;
  }
  fclose(f);

  long long total = 0, distinct = 0;
  size_t i = 0;
  while (i < size) {
    while (i < size && (unsigned char)text[i] <= ' ')
      i++;
    size_t start = i;
    while (i < size && (unsigned char)text[i] > ' ')
      i++;
    if (i > start) {
      if (add(text + start, i - start)) {
        distinct++;
        if (distinct * 2 > TABLE_SIZE) {
          fprintf(stderr, "wordcount: more different words than the table holds\n");
          return 3;
        }
      }
      total++;
    }
  }
  long long max_count = 0, sum_squares = 0;
  for (uint32_t s = 0; s < TABLE_SIZE; s++)
    if (table[s].key != NULL) {
      if (table[s].count > max_count)
        max_count = table[s].count;
      sum_squares += table[s].count * table[s].count;
    }
  printf("wordcount %lld %lld %lld %lld\n", total, distinct, max_count, sum_squares);
  return 0;
}
