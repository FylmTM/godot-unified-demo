// The dev commands (`Command_Dev_*`): cheats and test shortcuts, offered as forms in the dev UI and left out by a
// public build, which then computes differently and refuses a dev build (unified/src/sim/README.md, Commands).
// Otherwise ordinary commands: relayed, logged and replayed, the same tick on every peer.
package crypt_crew

import "unified:sim"

// Each present player's dev commands: `Command_Dev_Set_Class` turns their hero into another class.
apply_dev_commands :: proc(t: ^Tick) {
	players := sim.iterate_present(t)
	for hero, player in sim.next(&players) {
		for sent in sim.commands(t, player) {
			#partial switch command in sent {
			case Command_Dev_Set_Class:
				if command.class != .Any do hero.class = command.class
			}
		}
	}
}
