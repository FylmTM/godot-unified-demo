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

// Leaves, then arrivals in slot order: a leaver drops what it carries, ends its throws' ignores (end_throws_by), its
// body goes and its class stays; an arrival gets a class (arrival_class) and a body at its arrival_spot.
update_presence :: proc(t: ^Tick) {
	for player in t.player_changes.left {
		drop_prop(t, player)
		end_throws_by(t, player)
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

// Where `player`'s hero arrives, and whether beside the party. The anchor is the lowest-slot hero up on the walkable
// floor, other than this one and other than those arriving this tick (a session's first players each take their own
// spawn). Around it, eight spots ARRIVAL_RING away, then eight twice as far, each ring starting from a spot that
// depends on the arriver's slot (ARRIVAL_SLOT_TURN): the first that is on the walkable floor (within ARRIVAL_SNAP),
// joined to the anchor's, reachable from the anchor in a straight line over no wall or low cover, with no live minion
// within ARRIVAL_CLEAR, and clear of every hero and every prop. With no such spot, or nobody up: the slot's hero_spawn.
arrival_spot :: proc(t: ^Tick, player: sim.Player) -> (feet: [3]f32, beside: bool) {
	slot := sim.player_slot(t, player)
	floor := floor_of(t)
	spawn := floor.places.hero_spawns[slot]
	anchor, anchored := arrival_anchor(t, player)
	if !anchored do return spawn, false
	anchor_spot, on_floor := floor_spot(floor, anchor.pos, HERO_NAV_REACH)
	if !on_floor do return spawn, false
	start := slot * ARRIVAL_SLOT_TURN
	for ring in 1 ..= 2 {
		for k in 0 ..< len(dmath.DIR8) {
			dir := dmath.DIR8[(start + k) % len(dmath.DIR8)]
			at := anchor.pos + [3]f32{dir.x, 0, dir.y} * (f32(ring) * ARRIVAL_RING)
			spot := floor_spot(floor, at, ARRIVAL_SNAP) or_continue
			if !nav.connected(&floor.mesh, spot.poly, anchor_spot.poly) do continue
			if !arrival_clear(t, anchor.pos, spot.point) do continue
			return spot.point, true
		}
	}
	return spawn, false
}

// Whether an arrival may stand at `point`: walkable from `from` in a straight line over no wall or low cover (tested
// ARRIVAL_RAY_HEIGHT above the floor), no live minion within ARRIVAL_CLEAR, and ARRIVAL_ROOM clear of every hero's
// capsule and every prop's footprint.
@(private = "file")
arrival_clear :: proc(t: ^Tick, from, point: [3]f32) -> bool {
	ray_from, ray_to := from + {0, ARRIVAL_RAY_HEIGHT, 0}, point + {0, ARRIVAL_RAY_HEIGHT, 0}
	if _, walled := physics.world_cast_ray_closest(t.world.phys, ray_from, ray_to - ray_from, ARRIVAL_FILTER); walled {
		return false
	}
	if minion_near(t, point, ARRIVAL_CLEAR) do return false
	heroes := sim.iterate_present(t)
	for hero in sim.next(&heroes) {
		if hero.body != {} && dmath.length(hero.pos.xz - point.xz) < 2 * HERO_RADIUS + ARRIVAL_ROOM do return false
	}
	props := sim.iterate(&t.state.props)
	for prop in sim.next(&props) {
		centre := physics.body_position(t.world.phys, prop.body)
		room := HERO_RADIUS + PROP_SPECS[prop.kind].footprint + ARRIVAL_ROOM
		if dmath.length(centre.xz - point.xz) < room do return false
	}
	return true
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
