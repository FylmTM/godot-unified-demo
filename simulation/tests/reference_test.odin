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
	checkpoints   = {0xa021dbb2a9fea1f0, 0xcaaaef7ba6e9d8b8, 0x08fd5b7b1aedf574, 0x1fce41bb5b8774d7},
	trace         = 0xef249be18587ef38,
	snapshot      = 0x5cf0a00cc0d873cc,
	log           = 0x6bc7bb3ac5fd904f,
	compat        = 0xf1c65fd85a5d584e,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
