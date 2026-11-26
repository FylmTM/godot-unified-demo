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
	checkpoints   = {0xa478effdda5df7f2, 0x0f0a5da7f98911f8, 0x9acbbfc4c9a12fad, 0xdeb5468695c5918d},
	trace         = 0x456d643211901ea2,
	snapshot      = 0x69e31a9324925984,
	log           = 0xa539434de13e54e9,
	compat        = 0x4eb571ac8d506523,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
