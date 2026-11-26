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
	checkpoints   = {0x8ed89821bd1fe4e4, 0xe49833e450707066, 0x7a67338d854baec4, 0x9fc0d9b923bf3861},
	trace         = 0xade06e2bf3fe7c1b,
	snapshot      = 0xd1deeb00c787f23c,
	log           = 0xc96e7cd654d79c68,
	compat        = 0x399d45c55a76bef8,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
