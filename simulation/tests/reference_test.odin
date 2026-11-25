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
	checkpoints   = {0x788b665bd68f5e9c, 0x22e812d5026b0cda, 0xc20b52cc4e1cb494, 0x543b56efeebd4922},
	trace         = 0xd7ca016436c6f58d,
	snapshot      = 0x080e4303c88269cb,
	log           = 0x05a0596d0e68c52b,
	compat        = 0xc1b67021e7837add,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
