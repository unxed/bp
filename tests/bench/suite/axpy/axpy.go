// SPDX-License-Identifier: MIT
// Benchmark suite (tests/bench/compare.sh): axpy, the Go version (the same loop and numbers as axpy.c).
package main

import (
	"fmt"
	"math"
)

const n = 1024
const rounds = 2000000

func main() {
	x := make([]float64, n)
	y := make([]float64, n)
	for i := 0; i < n; i++ {
		x[i] = float64(i) * 0.5
	}
	for r := 0; r < rounds; r++ {
		for i := range y {
			y[i] = y[i] + 1.0e-9*x[i]
		}
	}
	s := 0.0
	for i := 0; i < n; i++ {
		s += y[i]
	}
	fmt.Printf("axpy %d\n", int64(math.Floor(s*1e6+0.5)))
}
