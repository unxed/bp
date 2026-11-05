// SPDX-License-Identifier: MIT
// Benchmark suite (tests/bench/compare.sh): a word count, the Go version of the owned tier. The text is read as bytes and
// each word becomes a string of its own (a copy) before the lookup; the table is the built-in map.
package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: wordcount_owned FILE")
		os.Exit(2)
	}
	data, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	counts := make(map[string]int64)
	var total int64
	i := 0
	for i < len(data) {
		for i < len(data) && data[i] <= ' ' {
			i++
		}
		start := i
		for i < len(data) && data[i] > ' ' {
			i++
		}
		if i > start {
			word := string(data[start:i])
			counts[word]++
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
