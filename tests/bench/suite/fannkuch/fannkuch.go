// SPDX-License-Identifier: MIT
// Benchmark suite (tests/bench/compare.sh): fannkuch, the Go version (the same loops).
package main

import "fmt"

const n = 10

func flips(p *[n]int32) int32 {
	q := *p
	var result int32
	k := q[0]
	for k != 0 {
		i, j := 0, int(k)
		for i < j {
			q[i], q[j] = q[j], q[i]
			i++
			j--
		}
		result++
		k = q[0]
	}
	return result
}

func next(p *[n]int32) bool {
	i := n - 2
	for i >= 0 && p[i] > p[i+1] {
		i--
	}
	if i < 0 {
		return false
	}
	j := n - 1
	for p[j] < p[i] {
		j--
	}
	p[i], p[j] = p[j], p[i]
	a, b := i+1, n-1
	for a < b {
		p[a], p[b] = p[b], p[a]
		a++
		b--
	}
	return true
}

func main() {
	var p [n]int32
	for i := range p {
		p[i] = int32(i)
	}
	var index, checksum int64
	var maxFlips int32
	for {
		f := flips(&p)
		if f > maxFlips {
			maxFlips = f
		}
		if index%2 == 0 {
			checksum += int64(f)
		} else {
			checksum -= int64(f)
		}
		index++
		if !next(&p) {
			break
		}
	}
	fmt.Println("fannkuch", checksum, maxFlips)
}
