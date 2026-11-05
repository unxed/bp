// SPDX-License-Identifier: MIT
// Benchmark suite (tests/bench/compare.sh): a word count, the Rust version. The text is read whole, the words are
// slices of it, the table is the standard HashMap.
use std::collections::HashMap;

fn main() {
    let name = match std::env::args().nth(1) {
        Some(n) => n,
        None => {
            eprintln!("usage: wordcount FILE");
            std::process::exit(2);
        }
    };
    let text = std::fs::read_to_string(&name).expect("read error");
    let mut counts: HashMap<&str, i64> = HashMap::new();
    let mut total: i64 = 0;
    for word in text.split_ascii_whitespace() {
        *counts.entry(word).or_insert(0) += 1;
        total += 1;
    }
    let mut max_count: i64 = 0;
    let mut sum_squares: i64 = 0;
    for &c in counts.values() {
        if c > max_count {
            max_count = c;
        }
        sum_squares += c * c;
    }
    println!("wordcount {} {} {} {}", total, counts.len(), max_count, sum_squares);
}
