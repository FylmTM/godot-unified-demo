// Arrivals and leaves, handled before every other system (people come and go while paused too). A hero is owned by
// its sim.Player, never a slot: whoever leaves and comes back gets their hero's data back in whatever slot is free
// (unified/src/sim/README.md, Players). A leaver's body is destroyed at the leave, since the table may forget an absent
// member before any tick runs, and made again on the return. A joiner, a rejoiner and a respawn all arrive beside the
// party (arrival_spot), so a shared camera keeps everyone on screen.
package crypt_crew

import "unified:dmath"
import "unified:nav"
import "unified:physics"
import "unified:sim"

// `player`'s hero appeared at `position`: beside the party (`beside`: a join, a rejoin or a respawn mid-floor), or at
// its slot's hero_spawn (a floor's start, nobody up).
Event_Hero_Spawned :: struct {
	player:   sim.Player,
	position: sim.Position,
	beside:   bool,
}

// What blocks an arrival's way from its anchor: walls and low cover (an arrival must walk to the party, not see it).
ARRIVAL_FILTER :: physics.Filter {
	category = CAT_HERO,
	mask     = CAT_WALL | CAT_LOW,
}

// Leaves, then arrivals in slot order: a leaver drops what it carries, its body goes and its class stays; an arrival
// gets a class (arrival_class) and a body at its arrival_spot.
update_presence :: proc(t: ^Tick) {
	for player in t.player_changes.left {
		drop_prop(t, player)
		hero := sim.player_data(t, player)
		destroy_hero_body(t.world.phys, hero)
		hero^ = {
			class = hero.class,
			warp  = hero.warp,
		}
	}
	for player in t.player_changes.arrived {
		hero := sim.player_data(t, player)
		hero.class = arrival_class(t, hero.class, sim.player_profile(t, player).class)
		feet, beside := arrival_spot(t, player)
		spawn_hero(t, player, feet, beside)
	}
}

// Where `player`'s hero arrives, and whether beside the party. The anchor is the lowest-slot hero up, other than this
// one and other than those arriving this tick (a session's first players each take their own spawn). Around it, eight
// spots ARRIVAL_RING away, starting from one that depends on the arriver's slot: the first that is on the mesh
// (within ARRIVAL_SNAP), joined to the anchor's floor, reachable from the anchor in a straight line over no wall or low
// cover, and with no live minion within ARRIVAL_CLEAR; else the anchor's own place. With nobody up: the slot's
// hero_spawn.
arrival_spot :: proc(t: ^Tick, player: sim.Player) -> (feet: [3]f32, beside: bool) {
	slot := sim.player_slot(t, player)
	anchor, anchored := arrival_anchor(t, player)
	if !anchored do return t.world.places.hero_spawns[slot], false
	mesh := &t.world.mesh
	from := anchor.pos
	anchor_poly, anchor_point := nav.nearest(mesh, from, HERO_NAV_REACH)
	start := slot * 3 // a ring's start per slot, so two arrivals at once try different spots first
	for k in 0 ..< len(dmath.DIR8) {
		dir := dmath.DIR8[(start + k) % len(dmath.DIR8)]
		poly, point := nav.nearest(mesh, from + {dir.x, 0, dir.y} * ARRIVAL_RING, ARRIVAL_SNAP)
		if poly == nav.NO_POLY || !nav.connected(mesh, poly, anchor_poly) do continue
		ray_from := from + {0, ARRIVAL_RAY_HEIGHT, 0}
		if _, blocked := physics.world_cast_ray_closest(t.world.phys, ray_from, point + {0, ARRIVAL_RAY_HEIGHT, 0} - ray_from, ARRIVAL_FILTER); blocked do continue
		if minion_near(t, point, ARRIVAL_CLEAR) do continue
		return point, true
	}
	return anchor_point if anchor_poly != nav.NO_POLY else from, true
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

// The hero's body goes (a leave, a level change), its warp epoch folded into the hero's own (hero_warp), so the
// view of its next body snaps.
destroy_hero_body :: proc(phys: ^physics.World, hero: ^Hero) {
	hero.warp = hero_warp(phys, hero)
	physics.character_destroy(phys, &hero.body)
}

// The hero arrivals are placed beside: the lowest-slot hero up other than `player` that didn't arrive this tick.
@(private = "file")
arrival_anchor :: proc(t: ^Tick, player: sim.Player) -> (anchor: ^Hero, ok: bool) {
	heroes := sim.iterate_present(t)
	candidates: for hero, other in sim.next(&heroes) {
		if other == player || !hero_up(t, other) do continue
		for arrived in t.player_changes.arrived {
			if arrived == other do continue candidates
		}
		return hero, true
	}
	return nil, false
}

// A fresh body for `player`'s hero standing at `feet` (`beside` the party, or at its spawn), at full health, facing up
// the screen (-Z); its view snaps there.
spawn_hero :: proc(t: ^Tick, player: sim.Player, feet: [3]f32, beside: bool) {
	hero := sim.player_data(t, player)
	destroy_hero_body(t.world.phys, hero)
	warp := hero.warp + 1
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
	sim.emit(t, Event_Hero_Spawned{player = player, position = sim.Position(feet), beside = beside})
}
