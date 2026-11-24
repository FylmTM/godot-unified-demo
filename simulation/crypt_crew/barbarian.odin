// The Barbarian's attack: a slow, wide cleave with a big knock (CLASS_SPECS[.Barbarian], strike_arc).
package crypt_crew

import "unified:sim"

// The Barbarian's blow lands: its axe's cleave.
barbarian_strike :: proc(t: ^Tick, hero: ^Hero, player: sim.Player) {
	strike_arc(t, hero, player, &CLASS_SPECS[.Barbarian])
}
