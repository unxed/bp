// SPDX-License-Identifier: MIT
// Benchmark suite (tests/bench/compare.sh): a word count, the Go version. The text is read whole, the words are
// slices of it, the table is the built-in map.
package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: wordcount FILE")
		os.Exit(2)
	}
	data, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	text := string(data)
	counts := make(map[string]int64)
	var total int64
	i := 0
	for i < len(text) {
		for i < len(text) && text[i] <= ' ' {
			i++
		}
		start := i
		for i < len(text) && text[i] > ' ' {
			i++
		}
		if i > start {
			counts[text[start:i]]++
			total++
		}
	}
	var maxCount, sumSquares int64
	for _, c := range counts {
		if c > maxCount {
			maxCount = c
		}
		sumSquares += c * c
	}
	fmt.Println("wordcount", total, len(counts), maxCount, sumSquares)
}
