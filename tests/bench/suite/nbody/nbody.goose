// SPDX-License-Identifier: MIT
// Benchmark suite (tests/bench/compare.sh): n-body, the Goose version (the same bodies, 64-bit floats and the same
// order of operations as nbody.pas, nbody.c, nbody.rs and nbody.go). The bodies are one fixed array of structs.
// Output: one line, the energy of the system before and after the steps, in millionths.
import std;
import math;

let STEPS = 5000000;
let DT: f64 = 0.001;
let COUNT = 5;

struct Body { x: f64, y: f64, z: f64, vx: f64, vy: f64, vz: f64, m: f64 }

var bodies: Body[5] = [
    Body { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1000.0 },
    Body { 4.0, 0.0, 0.5, 0.0, 15.8113883, 0.1, 1.0 },
    Body { 0.0, 8.0, -0.3, -11.1803399, 0.0, 0.05, 2.0 },
    Body { -12.0, 0.0, 0.8, 0.0, -9.12870929, -0.07, 3.0 },
    Body { 0.0, -16.0, -1.0, 7.90569415, 0.0, 0.04, 0.5 },
];

fn advance() {
    for i in 0..COUNT - 1 {
        for j in i + 1..COUNT {
            let dx = bodies[i].x - bodies[j].x;
            let dy = bodies[i].y - bodies[j].y;
            let dz = bodies[i].z - bodies[j].z;
            let d2 = dx * dx + dy * dy + dz * dz;
            let mag = DT / (d2 * sqrt(d2));
            bodies[i].vx = bodies[i].vx - dx * bodies[j].m * mag;
            bodies[i].vy = bodies[i].vy - dy * bodies[j].m * mag;
            bodies[i].vz = bodies[i].vz - dz * bodies[j].m * mag;
            bodies[j].vx = bodies[j].vx + dx * bodies[i].m * mag;
            bodies[j].vy = bodies[j].vy + dy * bodies[i].m * mag;
            bodies[j].vz = bodies[j].vz + dz * bodies[i].m * mag;
        }
    }
    for i in 0..COUNT {
        bodies[i].x = bodies[i].x + DT * bodies[i].vx;
        bodies[i].y = bodies[i].y + DT * bodies[i].vy;
        bodies[i].z = bodies[i].z + DT * bodies[i].vz;
    }
}

fn energy() -> f64 {
    var e: f64 = 0.0;
    for i in 0..COUNT {
        e = e + 0.5 * bodies[i].m *
            (bodies[i].vx * bodies[i].vx + bodies[i].vy * bodies[i].vy + bodies[i].vz * bodies[i].vz);
        for j in i + 1..COUNT {
            let dx = bodies[i].x - bodies[j].x;
            let dy = bodies[i].y - bodies[j].y;
            let dz = bodies[i].z - bodies[j].z;
            e = e - bodies[i].m * bodies[j].m / sqrt(dx * dx + dy * dy + dz * dz);
        }
    }
    return e;
}

fn main() {
    let before = floor(energy() * 1e6 + 0.5) as i64;
    for s in STEPS { advance(); }
    let after = floor(energy() * 1e6 + 0.5) as i64;
    print("nbody ", before, " ", after);
}
