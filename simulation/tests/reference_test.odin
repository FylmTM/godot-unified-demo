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
	checkpoints   = {0xb8df92bbb79a3a1b, 0x20c5d57c58539f47, 0x0ce3d6aef32ee645, 0xca9fa0a919678abb},
	trace         = 0xe2aa8af23ab01ac7,
	snapshot      = 0x4e2b285cddcad3b6,
	log           = 0x328bc2653386be63,
	compat        = 0xa3a25368275272ac,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
