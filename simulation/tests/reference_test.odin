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
	checkpoints   = {0x4d1b7cef272dd833, 0x6b42b6573be2b402, 0xba2f38890ae2f5cb, 0x4be19b7b7a9873e5},
	trace         = 0xa91bdbe9674b0d0d,
	snapshot      = 0x6b7c4a752b265e81,
	log           = 0x0dc953c5c48598f8,
	compat        = 0x19369c48f1daa904,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
