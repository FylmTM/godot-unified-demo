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
	checkpoints   = {0x90e00a927abb56f6, 0xd0bac480ff5ab6d8, 0xc0704418137184fd, 0x7596f4c8b8ec6683},
	trace         = 0x34b478ece6a72a42,
	snapshot      = 0x88fbbafa0358c311,
	log           = 0xd83c8be97909a048,
	compat        = 0x68112cb466cb07d8,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
