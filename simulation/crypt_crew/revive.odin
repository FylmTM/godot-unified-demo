// Reviving a downed ally. A hero up, its hands free, doing nothing else, that presses Interact within REVIVE_RANGE of
// a hero down starts tending them (Action.Revive), and that press grabs nothing (use_hands skips a reviver); it tends
// for as long as it holds Interact and stays in range, moving at REVIVE_SPEED meanwhile. Letting go, walking off,
// Attack held or a blow taken (damage_hero) breaks it off, and only a new press starts it again. Each tick a downed
// hero's revive gains one for each ally tending them, so two revive twice as fast, and loses REVIVE_DECAY untended; at
// REVIVE_TICKS it rises where it lies, at REVIVE_HP, in its grace. revive_target is both what the tick tends and what
// the view's "[E] Revive" prompt asks, so the prompt shows exactly when a press would revive.
package crypt_crew

import "unified:dmath"
import "unified:sim"

// `player`'s hero was revived by `by` at `position` (`by`: the first ally tending them, in slot order; for a dev
// revive, its sender).
Event_Hero_Revived :: struct {
	player:   sim.Player,
	by:       sim.Player,
	position: sim.Position,
}

// The State's players with their heroes (State.players), as revive_target takes them from a tick or a view.
Heroes :: sim.Players(Hero, Profile, Input, PLAYERS)

// The hero down that `player`'s hero would tend now (the nobody Player: none). Nothing unless that hero is present, up,
// its hands free and doing nothing else (or tending already); else the nearest other present hero down within
// REVIVE_RANGE of its feet on the floor plan, on a tie the lower slot. Pure: what the tick (revive_heroes) and the
// view's prompt both ask.
revive_target :: proc(players: ^Heroes, player: sim.Player) -> (target: sim.Player) {
	if !sim.player_present(players, player) do return
	reviver := sim.player_data(players, player)
	if reviver.held != {} || (reviver.action != .None && reviver.action != .Revive) do return
	nearest := REVIVE_RANGE * REVIVE_RANGE
	heroes := sim.iterate_present(players)
	for hero, other in sim.next(&heroes) {
		if other == player || hero.action != .Down do continue
		apart := dmath.length_sq(hero.pos.xz - reviver.pos.xz)
		if apart <= nearest && (target == {} || apart < nearest) do target, nearest = other, apart
	}
	return
}

// Each present hero's revive, then each downed hero's progress. A hero doing nothing that presses Interact with a
// revive_target starts tending it; one tending keeps on while it holds Interact, holds no Attack and still has a
// target, and stops otherwise. Then each hero down gains a tick for each ally tending it, rising at REVIVE_TICKS
// (revive_hero, the first of them its reviver), or loses REVIVE_DECAY with nobody tending.
revive_heroes :: proc(t: ^Tick) {
	tending: [PLAYERS]u16 // by the downed hero's slot: how many tend it this tick ...
	first: [PLAYERS]sim.Player // ... and the first of them (in slot order)
	revivers := sim.iterate_present(t)
	for hero, player in sim.next(&revivers) {
		if hero.action != .None && hero.action != .Revive do continue
		buttons := sim.buttons(t, player)
		target := revive_target(&t.state.players, player)
		tends := target != {} && .Interact in buttons.down && .Attack not_in buttons.down
		if hero.action == .None do tends &&= .Interact in buttons.pressed // a revive starts with a press
		if !tends {
			if hero.action == .Revive do hero.action, hero.action_started = .None, t.time
			continue
		}
		if hero.action != .Revive do hero.action, hero.action_started = .Revive, t.time
		slot, _ := sim.player_slot(t, target)
		if tending[slot] == 0 do first[slot] = player
		tending[slot] += 1
	}
	downed := sim.iterate_present(t)
	for hero, player in sim.next(&downed) {
		if hero.action != .Down do continue
		slot, _ := sim.player_slot(t, player)
		if tending[slot] == 0 {
			hero.revive -= dmath.min(hero.revive, REVIVE_DECAY)
			continue
		}
		hero.revive += tending[slot]
		if hero.revive >= REVIVE_TICKS do revive_hero(t, player, first[slot])
	}
}

// `player`'s hero, down, rises where it lies at REVIVE_HP, in its grace, revived by `by`; whoever was tending it stops.
revive_hero :: proc(t: ^Tick, player: sim.Player, by: sim.Player) {
	hero := sim.player_data(t, player)
	hero.hp = REVIVE_HP
	hero.action, hero.action_started = .None, t.time
	hero.revive = 0
	sim.timer_start_ticks(t, &hero.grace, SPAWN_GRACE_TICKS)
	sim.emit(t, Event_Hero_Revived{player = player, by = by, position = sim.Position(hero.pos)})
	revivers := sim.iterate_present(t)
	for reviver, other in sim.next(&revivers) {
		if reviver.action == .Revive && revive_target(&t.state.players, other) == {} {
			reviver.action, reviver.action_started = .None, t.time
		}
	}
}
