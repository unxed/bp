// SPDX-License-Identifier: MIT
// Benchmark suite (tests/bench/compare.sh): binary trees, the Go version (the garbage collector frees the trees).
package main

import "fmt"

const maxDepth = 16
const minDepth = 4

type node struct {
	left, right *node
}

func build(depth int) *node {
	t := &node{}
	if depth > 0 {
		t.left = build(depth - 1)
		t.right = build(depth - 1)
	}
	return t
}

func check(t *node) int64 {
	n := int64(1)
	if t.left != nil {
		n += check(t.left) + check(t.right)
	}
	return n
}

func once(depth int) int64 {
	return check(build(depth))
}

func many(depth int, iterations int64) int64 {
	var total int64
	for i := int64(0); i < iterations; i++ {
		total += once(depth)
	}
	return total
}

func main() {
	total := once(maxDepth + 1)
	longLived := build(maxDepth)
	for depth := minDepth; depth <= maxDepth; depth += 2 {
		total += many(depth, int64(1)<<(maxDepth-depth+minDepth))
	}
	total += check(longLived)
	fmt.Println("bintrees", total)
}
