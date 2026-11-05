// SPDX-License-Identifier: MIT
// Benchmark suite (tests/bench/compare.sh): binary trees, the arena tier, the Go version. The nodes of a tree are the
// elements of one slice with 4-byte index links, the layout of bintrees_arena.goose, .c and .rs; dropping a tree is
// slicing it to zero length, and a loop of trees keeps the backing array. Indexing is bounds-checked, as written.
package main

import "fmt"

const maxDepth = 16
const minDepth = 4
const none = ^uint32(0)

type node struct {
	left, right uint32
}

func build(pool *[]node, depth int) uint32 {
	t := uint32(len(*pool))
	*pool = append(*pool, node{none, none})
	if depth > 0 {
		l := build(pool, depth-1)
		(*pool)[t].left = l
		r := build(pool, depth-1)
		(*pool)[t].right = r
	}
	return t
}

func check(pool []node, t uint32) int64 {
	n := int64(1)
	if pool[t].left != none {
		n += check(pool, pool[t].left) + check(pool, pool[t].right)
	}
	return n
}

func once(depth int) int64 {
	var pool []node
	root := build(&pool, depth)
	return check(pool, root)
}

func many(depth int, iterations int64) int64 {
	var pool []node
	var total int64
	for i := int64(0); i < iterations; i++ {
		root := build(&pool, depth)
		total += check(pool, root)
		pool = pool[:0]
	}
	return total
}

func main() {
	total := once(maxDepth + 1)
	var longLived []node
	root := build(&longLived, maxDepth)
	for depth := minDepth; depth <= maxDepth; depth += 2 {
		total += many(depth, int64(1)<<(maxDepth-depth+minDepth))
	}
	total += check(longLived, root)
	fmt.Println("bintrees", total)
}
