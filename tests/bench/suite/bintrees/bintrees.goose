// SPDX-License-Identifier: MIT
// Benchmark suite (tests/bench/compare.sh): binary trees, the Goose version (the same trees as bintrees.pas,
// bintrees.c, bintrees.rs and bintrees.go). The nodes of one tree are the elements of one grow-only array with 4-byte
// self-relative links, the style of the language; the array belongs to a scope, so dropping the tree is the end of
// that scope (a pointer store, no walk).
// Output: one line, the number of nodes counted.
import std;

let MAX_DEPTH = 16;
let MIN_DEPTH = 4;

struct Node { left: Node&<u32>?, right: Node&<u32>? }

recursive fn make(pool: Node[>..]&, depth: i64) -> Node& {
    let t .= pool.push(Node {});
    if depth > 0 {
        let l .= make(pool, depth - 1);
        t.left .= l;
        let r .= make(pool, depth - 1);
        t.right .= r;
    }
    return t;
}

recursive fn check(t: Node&) -> i64 {
    var n = 1;
    let l = t.left;
    if l {
        n += check(l);
        let r = t.right;
        if r { n += check(r); }
    }
    return n;
}

// The nodes of one tree of the given depth; the tree ends with the call.
fn once(depth: i64) -> i64 {
    var pool: Node[>..] = [];
    let root .= make(pool, depth);
    return check(root);
}

fn many(depth: i64, iterations: i64) -> i64 {
    var total = 0;
    for i in iterations { total += once(depth); }
    return total;
}

fn main() {
    var total = once(MAX_DEPTH + 1);
    var long_lived: Node[>..] = [];
    let root .= make(long_lived, MAX_DEPTH);
    var depth = MIN_DEPTH;
    while depth <= MAX_DEPTH {
        total += many(depth, 1 << (MAX_DEPTH - depth + MIN_DEPTH));
        depth += 2;
    }
    total += check(root);
    print("bintrees ", total);
}
