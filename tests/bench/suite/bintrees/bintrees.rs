// SPDX-License-Identifier: MIT
// Benchmark suite (tests/bench/compare.sh): binary trees, the Rust version (Box; the tree is dropped by Drop).

const MAX_DEPTH: u32 = 16;
const MIN_DEPTH: u32 = 4;

struct Node {
    left: Option<Box<Node>>,
    right: Option<Box<Node>>,
}

fn make(depth: u32) -> Box<Node> {
    if depth > 0 {
        Box::new(Node {
            left: Some(make(depth - 1)),
            right: Some(make(depth - 1)),
        })
    } else {
        Box::new(Node { left: None, right: None })
    }
}

fn check(t: &Node) -> i64 {
    match (&t.left, &t.right) {
        (Some(l), Some(r)) => 1 + check(l) + check(r),
        _ => 1,
    }
}

fn once(depth: u32) -> i64 {
    let t = make(depth);
    check(&t)
}

fn many(depth: u32, iterations: i64) -> i64 {
    let mut total = 0;
    for _ in 0..iterations {
        total += once(depth);
    }
    total
}

fn main() {
    let mut total = once(MAX_DEPTH + 1);
    let longlived = make(MAX_DEPTH);
    let mut depth = MIN_DEPTH;
    while depth <= MAX_DEPTH {
        total += many(depth, 1i64 << (MAX_DEPTH - depth + MIN_DEPTH));
        depth += 2;
    }
    total += check(&longlived);
    println!("bintrees {}", total);
}
