// SPDX-License-Identifier: MIT
// Benchmark suite (tests/bench/compare.sh): binary trees, the arena tier, the Rust version. The nodes of a tree are the
// elements of one Vec with 4-byte index links, the layout of bintrees_arena.goose, .c and .go; dropping a tree is
// clearing the Vec, and a loop of trees keeps its buffer. Indexing is bounds-checked, as written.

const MAX_DEPTH: u32 = 16;
const MIN_DEPTH: u32 = 4;
const NONE: u32 = u32::MAX;

struct Node {
    left: u32,
    right: u32,
}

fn make(pool: &mut Vec<Node>, depth: u32) -> u32 {
    let t = pool.len() as u32;
    pool.push(Node { left: NONE, right: NONE });
    if depth > 0 {
        let l = make(pool, depth - 1);
        pool[t as usize].left = l;
        let r = make(pool, depth - 1);
        pool[t as usize].right = r;
    }
    t
}

fn check(pool: &[Node], t: u32) -> i64 {
    let n = &pool[t as usize];
    if n.left != NONE {
        1 + check(pool, n.left) + check(pool, n.right)
    } else {
        1
    }
}

fn once(depth: u32) -> i64 {
    let mut pool = Vec::new();
    let root = make(&mut pool, depth);
    check(&pool, root)
}

fn many(depth: u32, iterations: i64) -> i64 {
    let mut pool = Vec::new();
    let mut total = 0;
    for _ in 0..iterations {
        let root = make(&mut pool, depth);
        total += check(&pool, root);
        pool.clear();
    }
    total
}

fn main() {
    let mut total = once(MAX_DEPTH + 1);
    let mut longlived = Vec::new();
    let root = make(&mut longlived, MAX_DEPTH);
    let mut depth = MIN_DEPTH;
    while depth <= MAX_DEPTH {
        total += many(depth, 1i64 << (MAX_DEPTH - depth + MIN_DEPTH));
        depth += 2;
    }
    total += check(&longlived, root);
    println!("bintrees {}", total);
}
