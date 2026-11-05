// SPDX-License-Identifier: MIT
// Benchmark suite (tests/bench/compare.sh): a word count, the Goose version. The text is read whole into one buffer, the
// words are slices of it, and the table is the standard `dictionary` of the language keyed by those slices (the
// natural program of the language, as Rust and Go use their standard maps in wordcount.rs and wordcount.go; wordcount.pas
// and wordcount.c have tables of their own).
// Output: one line, the number of words, the number of different words, the largest count and the sum of the squares
// of the counts.
// usage: wordcount FILE
import std;
import dictionary;
import os;

fn main() {
    if arg_count() < 2 {
        write_stderr("usage: wordcount FILE\n");
        exit(2);
    }
    var path: u8[>..] = [];
    arg(1, path);
    var text: u8[>..] = [];
    guard read_file(path, text) else {
        write_stderr("wordcount: cannot read the file\n");
        exit(1);
    }
    var counts = dictionary<u8[:], i64> {};
    var total: i64 = 0;
    var i = 0;
    while i < text.len {
        while i < text.len && text[i] <= ' ' { i++; }
        let start = i;
        while i < text.len && text[i] > ' ' { i++; }
        if i > start {
            counts.update(text[start..i], 0) { it += 1; };
            total++;
        }
    }
    var max_count: i64 = 0;
    var sum_squares: i64 = 0;
    counts.each() { w, n => {
        if n > max_count { max_count = n; }
        sum_squares += n * n;
    } };
    print("wordcount ", total, " ", counts.count, " ", max_count, " ", sum_squares);
}
