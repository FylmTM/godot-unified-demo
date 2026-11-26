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
	checkpoints   = {0xa8d49a72ff6b66b1, 0x38d6bf5d69fe110d, 0x84aa5af49dcf1c4c, 0x18bf8b46076dea12},
	trace         = 0x7859e99998037bca,
	snapshot      = 0xb5a354d12e69718f,
	log           = 0x4faac8f1fde52bf1,
	compat        = 0x601d73f11e28bf8f,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
