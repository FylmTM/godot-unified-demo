// crypt_crew's reference run (unified/src/headless/README.md, Reference runs): four scripted heroes for 2400 ticks, long
// enough to cross several surges and a wipe (the script downs all four every third round), snapshotted midway.
package test_crypt_crew

import "core:testing"
import "unified:headless/scenarios"

import g "../crypt_crew"

REFERENCE :: scenarios.Reference {
	seed          = 7,
	players       = 4,
	ticks         = 2400,
	snapshot_tick = 1200,
	checkpoints   = {0x3d2b1adad497b3e6, 0xa53b7c1d8ea93f34, 0x44046dab5309ee47, 0x174c44b1eaf4c3cc},
	trace         = 0x0ef87ba15e362c00,
	snapshot      = 0x17fd0e58f7ed4c81,
	log           = 0x0955c08cee2272d6,
	compat        = 0xc5aa92518984487b,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
