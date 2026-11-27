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
	checkpoints   = {0xddecc843178dcb6c, 0xcb125af97d419843, 0x2a1777e6ce45039b, 0xf58b48e8995a5961},
	trace         = 0xe37ea70fcc6be2ac,
	snapshot      = 0x1a4cbb667f3598a6,
	log           = 0xe52812f2092950bc,
	compat        = 0xcb56708be85d4269,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
