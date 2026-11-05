// SPDX-License-Identifier: MIT
// Benchmark suite (tests/bench/compare.sh): axpy, the Rust version (the same loop and numbers as axpy.c).
const N: usize = 1024;
const ROUNDS: usize = 2000000;

fn main() {
    let mut x = vec![0.0f64; N];
    let mut y = vec![0.0f64; N];
    for i in 0..N {
        x[i] = i as f64 * 0.5;
    }
    for _ in 0..ROUNDS {
        for (yi, xi) in y.iter_mut().zip(x.iter()) {
            *yi = *yi + 1.0e-9 * *xi;
        }
    }
    let mut s = 0.0f64;
    for i in 0..N {
        s += y[i];
    }
    println!("axpy {}", (s * 1e6 + 0.5).floor() as i64);
}
