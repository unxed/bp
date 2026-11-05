// SPDX-License-Identifier: MIT
// Benchmark suite (tests/bench/compare.sh): n-body, the Go version (the same bodies, the same order of operations).
package main

import (
	"fmt"
	"math"
)

const steps = 5000000
const dt = 0.001
const count = 5

type body struct {
	x, y, z, vx, vy, vz, m float64
}

var bodies = [count]body{
	{0, 0, 0, 0, 0, 0, 1000},
	{4, 0, 0.5, 0, 15.8113883, 0.1, 1},
	{0, 8, -0.3, -11.1803399, 0, 0.05, 2},
	{-12, 0, 0.8, 0, -9.12870929, -0.07, 3},
	{0, -16, -1, 7.90569415, 0, 0.04, 0.5},
}

func advance() {
	for i := 0; i < count-1; i++ {
		for j := i + 1; j < count; j++ {
			dx := bodies[i].x - bodies[j].x
			dy := bodies[i].y - bodies[j].y
			dz := bodies[i].z - bodies[j].z
			d2 := dx*dx + dy*dy + dz*dz
			mag := dt / (d2 * math.Sqrt(d2))
			bodies[i].vx = bodies[i].vx - dx*bodies[j].m*mag
			bodies[i].vy = bodies[i].vy - dy*bodies[j].m*mag
			bodies[i].vz = bodies[i].vz - dz*bodies[j].m*mag
			bodies[j].vx = bodies[j].vx + dx*bodies[i].m*mag
			bodies[j].vy = bodies[j].vy + dy*bodies[i].m*mag
			bodies[j].vz = bodies[j].vz + dz*bodies[i].m*mag
		}
	}
	for i := 0; i < count; i++ {
		bodies[i].x = bodies[i].x + dt*bodies[i].vx
		bodies[i].y = bodies[i].y + dt*bodies[i].vy
		bodies[i].z = bodies[i].z + dt*bodies[i].vz
	}
}

func energy() float64 {
	e := 0.0
	for i := 0; i < count; i++ {
		e = e + 0.5*bodies[i].m*(bodies[i].vx*bodies[i].vx+bodies[i].vy*bodies[i].vy+bodies[i].vz*bodies[i].vz)
		for j := i + 1; j < count; j++ {
			dx := bodies[i].x - bodies[j].x
			dy := bodies[i].y - bodies[j].y
			dz := bodies[i].z - bodies[j].z
			e = e - bodies[i].m*bodies[j].m/math.Sqrt(dx*dx+dy*dy+dz*dz)
		}
	}
	return e
}

func main() {
	before := int64(math.Floor(energy()*1e6 + 0.5))
	for s := 0; s < steps; s++ {
		advance()
	}
	fmt.Println("nbody", before, int64(math.Floor(energy()*1e6 + 0.5)))
}
