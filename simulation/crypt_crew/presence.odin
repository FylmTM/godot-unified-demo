// Arrivals and leaves, handled before every other system (people come and go while paused too). A hero is owned by
// its sim.Player, never a slot: whoever leaves and comes back gets their hero's data back in whatever slot is free
// (unified/src/sim/README.md, Players). A leaver's body is destroyed at the leave, since the table may forget an absent
// member before any tick runs, and made again on the return.
package crypt_crew

import "unified:physics"
import "unified:sim"

// Leaves, then arrivals in slot order: a leaver's body goes and its class stays; an arrival gets a class
// (arrival_class) and a body at its slot's hero_spawn.
update_presence :: proc(t: ^Tick) {
	for player in t.player_changes.left {
		hero := sim.player_data(t, player)
		class, warp := hero.class, hero_warp(t.world.phys, hero)
		physics.character_destroy(t.world.phys, &hero.body)
		hero^ = {
			class = class,
			warp  = warp,
		}
	}
	for player in t.player_changes.arrived {
		hero := sim.player_data(t, player)
		hero.class = arrival_class(t, hero.class, sim.player_profile(t, player).class)
		spawn_hero(t, player, t.world.places.hero_spawns[sim.player_slot(t, player)])
	}
}

// The class an arriving hero plays: the class its Profile wishes for; with no wish (`Any`), the one it played before
// it left, or for a new hero the first class no present hero plays. There is always one: the others present are fewer
// than the classes.
arrival_class :: proc(t: ^Tick, played: Class, wish: Class) -> Class {
	#assert(len(Class) - 1 >= PLAYERS)
	if wish != .Any do return wish
	if played != .Any do return played
	taken: bit_set[Class;u8]
	heroes := sim.iterate_present(t)
	for hero in sim.next(&heroes) do taken += {hero.class}
	for class in Class {
		if class != .Any && class not_in taken do return class
	}
	unreachable()
}

// A fresh body for `player`'s hero standing at `feet`, at full health, facing up the screen (-Z); its view snaps there.
spawn_hero :: proc(t: ^Tick, player: sim.Player, feet: [3]f32) {
	hero := sim.player_data(t, player)
	warp := hero_warp(t.world.phys, hero) + 1
	physics.character_destroy(t.world.phys, &hero.body)
	hero^ = {
		pos            = feet,
		facing         = {0, -1},
		action_started = t.time,
		hp             = HERO_HP,
		class          = hero.class,
		warp           = warp,
	}
	physics.character_create(
		t.world.phys,
		&hero.body,
		t.world.hero_defs[hero.class],
		feet + {0, HERO_CENTRE_ABOVE_FEET, 0},
		tag = sim.player_key(player),
	)
}
