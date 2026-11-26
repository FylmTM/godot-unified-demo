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
	checkpoints   = {0xed82737a8ef94979, 0xbd96bfef5ff52a9b, 0xc636de1b0fbc92da, 0x7c8231f4cadb808f},
	trace         = 0x706573f3fcd46fe5,
	snapshot      = 0x0258a201d2eb5dd2,
	log           = 0x3f61db552eeb0b15,
	compat        = 0x040eb66f7af28260,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
