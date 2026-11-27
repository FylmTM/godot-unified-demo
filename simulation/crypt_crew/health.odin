// A hero's health: damage_hero is the only way a hero takes damage and goes down (a spawn sets its hit points whole, a
// revive to REVIVE_HP). A blow first meets what the hero is doing: the early part of a Rogue's roll lets nothing
// through, and a Knight's raised shield (or its charge) takes a blow from the front (abilities.odin). A hero at 0 HP
// goes down: it lets go of what it carries, falls as a ragdoll knocked away from the blow (ragdolls.odin), and minions
// stop chasing it. It stays down until an ally revives it (revive.odin): there is no bleeding out and no rising on its
// own. When every hero present is down, the wipe's WIPE_S runs (a hero up again, a joiner arriving, stops it), and then
// a life goes (party_fell, run.odin: the floor starts over, or the run is lost). Nothing hurts the party while it is
// harmless (run.odin: the hub, a run's end, the Pit's choice).
package crypt_crew

import "unified:dmath"
import "unified:sim"

// `player`'s hero took `damage` from something at `position`, leaving `hp`.
Event_Hero_Hurt :: struct {
	player:   sim.Player,
	position: sim.Position,
	damage:   i16,
	hp:       i16,
}

// `player`'s hero went down at `position`.
Event_Hero_Downed :: struct {
	player:   sim.Player,
	position: sim.Position,
}

// Every hero present went down: the floor starts over in WIPE_S unless one is up again first.
Event_Party_Wiped :: struct {}

// The whole party stayed down: the floor started over.
Event_Floor_Restarted :: struct {}

// Whether `player` is present with a hero that is up (not down).
hero_up :: proc(t: ^Tick, player: sim.Player) -> bool {
	if !sim.player_present(t, player) do return false
	return sim.player_data(t, player).action != .Down
}

// `player`'s hero takes `damage` from something at `from`, unless it is down or in its grace, or a crowd is held but
// for Wipe (director.odin, Crowd), or the lift has gone down (lift_gone: the floor is won), or nothing can hurt the
// party now (harmless, run.odin: the hub, a run's end, the Pit's choice); a roll's safe start lets it
// all by, a shield takes its share (guarded_damage). A hurt hero tending an ally breaks off the revive. At 0 HP it goes
// down.
damage_hero :: proc(t: ^Tick, player: sim.Player, damage: i16, from: [3]f32) {
	if damage <= 0 || !hero_up(t, player) || lift_gone(t) || harmless(t) do return
	if t.setup.crowd != .None && t.setup.crowd != .Wipe do return
	hero := sim.player_data(t, player)
	if sim.timer_running(t, hero.grace) || rolled_clear(t, hero) do return
	taken := guarded_damage(t, hero, player, damage, from)
	if taken <= 0 do return
	if hero.action == .Revive do hero.action = .None // and a new press of Interact is needed to tend again
	hero.hp = dmath.max(hero.hp - taken, 0)
	sim.emit(t, Event_Hero_Hurt{player = player, position = sim.Position(from), damage = taken, hp = hero.hp})
	if hero.hp > 0 do return
	drop_prop(t, player)
	feet := hero.pos
	ragdoll_hero(t, player, ragdoll_kick(feet, from, hero.facing))
	hero.action, hero.action_started = .Down, t.time
	hero.revive = 0
	sim.emit(t, Event_Hero_Downed{player = player, position = sim.Position(feet)})
}

// Every hero present down (the wipe): WIPE_S after the last one fell, a life goes (party_fell, run.odin: the floor
// starts over, or the run is lost). A hero up again, by a revive or a joiner's arrival, stops the wipe; so does nobody
// being present, the lift going down (lift_gone: the party left with its downed aboard, and the one up leaving the ride
// wipes nobody), nothing being able to hurt the party (harmless: the hub, a run's end, the Pit's choice), and a held
// crowd (a restart would empty the floor of it: director.odin, Crowd).
check_wipe :: proc(t: ^Tick) {
	if sim.present_count(t) == 0 || lift_gone(t) || harmless(t) || t.setup.crowd != .None {
		sim.timer_stop(&t.state.wipe)
		return
	}
	heroes := sim.iterate_present(t)
	for _, player in sim.next(&heroes) {
		if hero_up(t, player) {
			sim.timer_stop(&t.state.wipe)
			return
		}
	}
	if t.state.wipe == {} { 	// stopped (the zero timer): the wipe begins
		sim.timer_start_ticks(t, &t.state.wipe, WIPE_TICKS)
		sim.emit(t, Event_Party_Wiped{})
	} else if !sim.timer_running(t, t.state.wipe) {
		party_fell(t) // run.odin: a restart (enter_level stops the wipe), or the run's end (harmless from then)
	}
}
