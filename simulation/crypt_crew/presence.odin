// Arrivals and leaves, handled before every other system (people come and go while paused too). A hero is owned by
// its sim.Player, never a slot: whoever leaves and comes back gets their hero's data back in whatever slot is free
// (unified/src/sim/README.md, Players). A leaver's body is destroyed at the leave, since the table may forget an absent
// member before any tick runs, and made again on the return.
package crypt_crew

import "unified:physics"
import "unified:sim"

// Leaves, then arrivals in slot order: a leaver's body goes and its class stays; an arrival gets a class (its own when
// it comes back, else its Profile's, `Any` resolved) and a body at its slot's hero_spawn.
update_presence :: proc(t: ^Tick) {
	for player in t.player_changes.left {
		hero := sim.player_data(t, player)
		physics.character_destroy(t.world.phys, &hero.body)
		hero^ = {
			class = hero.class,
			warp  = hero.warp, // kept: the next arrival's bump is a change the view sees
		}
	}
	for player in t.player_changes.arrived {
		hero := sim.player_data(t, player)
		if hero.class == .Any do hero.class = arrival_class(t, sim.player_profile(t, player).class)
		spawn_hero(t, player, t.world.places.hero_spawns[sim.player_slot(t, player)])
	}
}

// The class a new hero plays: the one asked for, or for `Any` the first class no present hero plays. There is always
// one: the others present are fewer than the classes.
arrival_class :: proc(t: ^Tick, wish: Class) -> Class {
	#assert(len(Class) - 1 >= PLAYERS)
	if wish != .Any do return wish
	taken: bit_set[Class;u8]
	players := sim.iterate_present(t)
	for hero in sim.next(&players) do taken += {hero.class}
	for class in Class {
		if class != .Any && class not_in taken do return class
	}
	unreachable()
}

// A fresh body for `player`'s hero standing at `feet`, at full health, facing up the screen (-Z); its view snaps there.
spawn_hero :: proc(t: ^Tick, player: sim.Player, feet: [3]f32) {
	hero := sim.player_data(t, player)
	physics.character_destroy(t.world.phys, &hero.body)
	hero^ = {
		pos            = feet,
		facing         = {0, -1},
		action_started = t.time,
		hp             = HERO_HP,
		class          = hero.class,
		warp           = hero.warp + 1,
	}
	physics.character_create(
		t.world.phys,
		&hero.body,
		t.world.hero_defs[hero.class],
		feet + {0, HERO_FEET, 0},
		tag = sim.player_key(player),
	)
}
