// SPDX-License-Identifier: MIT
// Benchmark suite (tests/bench/compare.sh): axpy, the Goose version (the same loop and numbers as axpy.c).
// Output: one line, the sum of y in millionths.
import std;
import math;

let N = 1024;
let ROUNDS = 2000000;

fn main() {
    var x: f64[1024] = [0.0; 1024];
    var y: f64[1024] = [0.0; 1024];
    for i in N { x[i] = i as f64 * 0.5; }
    for r in ROUNDS {
        for i in N { y[i] = y[i] + 1.0e-9 * x[i]; }
    }
    var s: f64 = 0.0;
    for i in N { s = s + y[i]; }
    print("axpy ", floor(s * 1e6 + 0.5) as i64);
}
