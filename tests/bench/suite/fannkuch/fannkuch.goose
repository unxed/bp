// SPDX-License-Identifier: MIT
// Benchmark suite (tests/bench/compare.sh): fannkuch, the Goose version (the same loops as fannkuch.pas, fannkuch.c,
// fannkuch.rs and fannkuch.go). A permutation is a fixed array of i32; the copy to flip is a plain assignment.
// Output: one line, the alternating sum of the flip counts and the largest count.
import std;

let N = 10;

fn flips(p: i32[10]) -> i64 {
    var q = p;
    var result = 0;
    var k = q[0];
    while k != 0 {
        var i = 0;
        var j = k as i64;
        while i < j {
            let t = q[i];
            q[i] = q[j];
            q[j] = t;
            i++;
            j--;
        }
        result++;
        k = q[0];
    }
    return result;
}

// The next permutation in lexicographic order; false after the last one.
fn next(p: i32[10]&) -> bool {
    var i = N - 2;
    while i >= 0 && p[i] > p[i + 1] { i--; }
    if i < 0 { return false; }
    var j = N - 1;
    while p[j] < p[i] { j--; }
    var t = p[i];
    p[i] = p[j];
    p[j] = t;
    i = i + 1;
    j = N - 1;
    while i < j {
        t = p[i];
        p[i] = p[j];
        p[j] = t;
        i++;
        j--;
    }
    return true;
}

fn main() {
    var p: i32[10] = [0; 10];
    for i in N { p[i] = i as i32; }
    var index: i64 = 0;
    var checksum: i64 = 0;
    var max_flips: i64 = 0;
    loop {
        let f = flips(p);
        if f > max_flips { max_flips = f; }
        if index % 2 == 0 { checksum += f; } else { checksum -= f; }
        index++;
        guard next(p) else { break; }
    }
    print("fannkuch ", checksum, " ", max_flips);
}
