// The Knight's attack: a quick, narrow sword arc (CLASS_SPECS[.Knight], strike_arc).
package crypt_crew

import "unified:sim"

// The Knight's blow lands: its sword's arc.
knight_strike :: proc(t: ^Tick, hero: ^Hero, player: sim.Player) {
	strike_arc(t, hero, player, &CLASS_SPECS[.Knight])
}
