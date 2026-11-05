# SPDX-License-Identifier: MIT
# Benchmark suite (tests/bench/compare.sh): the text for the word count, the same bytes on every run.
# usage: awk -f gen.awk [-v words=N] > text.txt
# A vocabulary of 30000 words of lower-case letters (base 26 digits of a number), drawn by a linear congruential
# generator; the cube of the random number makes some words common and most rare. Ten words to a line.
BEGIN {
  if (words == "") words = 4000000
  vocab = 30000
  letters = "abcdefghijklmnopqrstuvwxyz"
  for (i = 0; i < vocab; i++) {
    x = i * 40503 + 17
    w = ""
    while (x > 0) {
      w = w substr(letters, x % 26 + 1, 1)
      x = int(x / 26)
    }
    word[i] = w
  }
  seed = 12345
  line = ""
  for (n = 1; n <= words; n++) {
    seed = (seed * 16807) % 2147483647
    r = seed / 2147483647
    line = line word[int(vocab * r * r * r)]
    if (n % 10 == 0) {
      print line
      line = ""
    } else {
      line = line " "
    }
  }
  if (line != "") print line
}
