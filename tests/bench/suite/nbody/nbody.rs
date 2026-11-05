// SPDX-License-Identifier: MIT
// Benchmark suite (tests/bench/compare.sh): n-body, the Rust version (the same bodies, the same order of operations).

const STEPS: i32 = 5_000_000;
const DT: f64 = 0.001;
const COUNT: usize = 5;

#[derive(Clone, Copy)]
struct Body {
    x: f64,
    y: f64,
    z: f64,
    vx: f64,
    vy: f64,
    vz: f64,
    m: f64,
}

fn body(x: f64, y: f64, z: f64, vx: f64, vy: f64, vz: f64, m: f64) -> Body {
    Body { x, y, z, vx, vy, vz, m }
}

fn advance(b: &mut [Body; COUNT]) {
    for i in 0..COUNT - 1 {
        for j in i + 1..COUNT {
            let dx = b[i].x - b[j].x;
            let dy = b[i].y - b[j].y;
            let dz = b[i].z - b[j].z;
            let d2 = dx * dx + dy * dy + dz * dz;
            let mag = DT / (d2 * d2.sqrt());
            b[i].vx = b[i].vx - dx * b[j].m * mag;
            b[i].vy = b[i].vy - dy * b[j].m * mag;
            b[i].vz = b[i].vz - dz * b[j].m * mag;
            b[j].vx = b[j].vx + dx * b[i].m * mag;
            b[j].vy = b[j].vy + dy * b[i].m * mag;
            b[j].vz = b[j].vz + dz * b[i].m * mag;
        }
    }
    for i in 0..COUNT {
        b[i].x = b[i].x + DT * b[i].vx;
        b[i].y = b[i].y + DT * b[i].vy;
        b[i].z = b[i].z + DT * b[i].vz;
    }
}

fn energy(b: &[Body; COUNT]) -> f64 {
    let mut e = 0.0;
    for i in 0..COUNT {
        e = e + 0.5 * b[i].m * (b[i].vx * b[i].vx + b[i].vy * b[i].vy + b[i].vz * b[i].vz);
        for j in i + 1..COUNT {
            let dx = b[i].x - b[j].x;
            let dy = b[i].y - b[j].y;
            let dz = b[i].z - b[j].z;
            e = e - b[i].m * b[j].m / (dx * dx + dy * dy + dz * dz).sqrt();
        }
    }
    e
}

fn main() {
    let mut b = [
        body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1000.0),
        body(4.0, 0.0, 0.5, 0.0, 15.8113883, 0.1, 1.0),
        body(0.0, 8.0, -0.3, -11.1803399, 0.0, 0.05, 2.0),
        body(-12.0, 0.0, 0.8, 0.0, -9.12870929, -0.07, 3.0),
        body(0.0, -16.0, -1.0, 7.90569415, 0.0, 0.04, 0.5),
    ];
    let before = (energy(&b) * 1e6 + 0.5).floor() as i64;
    for _ in 0..STEPS {
        advance(&mut b);
    }
    println!("nbody {} {}", before, (energy(&b) * 1e6 + 0.5).floor() as i64);
}
