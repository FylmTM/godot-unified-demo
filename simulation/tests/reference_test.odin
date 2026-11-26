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
	checkpoints   = {0x05c2766e1c37e76d, 0x634840a28656745f, 0xb2cfa446fdaf7e5e, 0x0bc9f2a6f7aaf654},
	trace         = 0x7777311a7da46ceb,
	snapshot      = 0x12382695fffa8b96,
	log           = 0x9e68f44a3aea493d,
	compat        = 0xf2ac05075450cc40,
}

@(test)
the_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, REFERENCE)}
