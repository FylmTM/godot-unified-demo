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
	checkpoints   = {0x2f2aa2e080865425, 0x3c6bcbb404b72cf2, 0x6b8936a37fe52ced, 0x97cb8f05d8df45e9},
	trace         = 0x82d6900eb4892ddb,
	snapshot      = 0xc08ec258cb224c86,
	log           = 0xc2232402ca8b7fbe,
	compat        = 0x27001f4e685b02f8,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
