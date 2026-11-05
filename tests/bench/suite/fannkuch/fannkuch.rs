// SPDX-License-Identifier: MIT
// Benchmark suite (tests/bench/compare.sh): fannkuch, the Rust version (the same loops; indexing is bounds-checked).

const N: usize = 10;

fn flips(p: &[i32; N]) -> i32 {
    let mut q = *p;
    let mut result = 0;
    let mut k = q[0] as usize;
    while k != 0 {
        let mut i = 0;
        let mut j = k;
        while i < j {
            let t = q[i];
            q[i] = q[j];
            q[j] = t;
            i += 1;
            j -= 1;
        }
        result += 1;
        k = q[0] as usize;
    }
    result
}

fn next(p: &mut [i32; N]) -> bool {
    let mut i = N as isize - 2;
    while i >= 0 && p[i as usize] > p[i as usize + 1] {
        i -= 1;
    }
    if i < 0 {
        return false;
    }
    let i = i as usize;
    let mut j = N - 1;
    while p[j] < p[i] {
        j -= 1;
    }
    let t = p[i];
    p[i] = p[j];
    p[j] = t;
    let mut a = i + 1;
    let mut b = N - 1;
    while a < b {
        let t = p[a];
        p[a] = p[b];
        p[b] = t;
        a += 1;
        b -= 1;
    }
    true
}

fn main() {
    let mut p = [0i32; N];
    for i in 0..N {
        p[i] = i as i32;
    }
    let mut index: i64 = 0;
    let mut checksum: i64 = 0;
    let mut max_flips = 0;
    loop {
        let f = flips(&p);
        if f > max_flips {
            max_flips = f;
        }
        if index % 2 == 0 {
            checksum += f as i64;
        } else {
            checksum -= f as i64;
        }
        index += 1;
        if !next(&mut p) {
            break;
        }
    }
    println!("fannkuch {} {}", checksum, max_flips);
}
