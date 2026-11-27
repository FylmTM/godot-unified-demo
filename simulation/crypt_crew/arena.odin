// The Pit: the endless arena (Level_Id.Arena) as a run's mode, the director's waves without end and one life. Wave n
// rises every PIT_SURGE_S (the first SURGE_FIRST_S in, as a floor's first surge): PIT_BASE + PIT_GROWTH × n, and
// SURGE_PER_HERO for each hero present, times the difficulty's surge scale (run.odin, surge_size), up to the arena's cap;
// every PIT_ELITE_EVERY-th brings an elite (elite_every). The director raises them (director.odin); this file holds the
// lulls between them.
//
// After every PIT_BOON_EVERY-th wave the next one holds (Pit_Stage.Lull) until at most PIT_LULL skeletons are alive, or
// PIT_LULL_MAX_S has passed; then the rest fall at once (minions and elites, struck down with no hero to blame), the
// downed rise at REVIVE_HP, and a boon choice opens (Pit_Stage.Choosing: as at a lift's bottom, nobody can be hurt and
// the heroes take no input but the pick, boons.odin). Once every present hero has picked, or BOON_TIMEOUT_S has run,
// the held wave rises. A wipe ends the run (one life), and the Pit keeps no save but the hub's (saves.odin): the score is
// the results panel's, from the run's end.
package crypt_crew

import "unified:sim"

// Where the Pit is between its waves.
Pit_Stage :: enum u8 {
	Waves, // the director raises them on its clock
	Lull, // the wave due holds while the last ones are fought down (at most PIT_LULL_MAX_S)
	Choosing, // the heroes pick their boons, then the held wave rises
}

// The Pit's lulls, in the State (State.pit): zero outside a Pit run.
Pit :: struct {
	since: sim.Game_Time, // when `stage` began
	lulls: u32, // the lulls held this run: the wave after each PIT_BOON_EVERY-th holds once
	stage: Pit_Stage,
	_pad:  [3]u8,
}

// A boon choice opened (`open`: a lift's bottom, a lull of the Pit), or closed (the descent, the lull's end, the run's).
// The boon panels open and close on this event's CONFIRMED state.
Event_Choice :: struct {
	open: bool,
}

// Wave `n`'s size (1: the first) with `heroes` present, before the difficulty and the cap: PIT_BASE, PIT_GROWTH a wave,
// SURGE_PER_HERO a hero.
pit_wave :: proc(n: int, heroes: int) -> int {
	return PIT_BASE + PIT_GROWTH * n + SURGE_PER_HERO * heroes
}

// Before the director (raise_surges reads the stage): the wave due after a PIT_BOON_EVERY-th holds (Lull); a lull ends
// once few enough are alive, or PIT_LULL_MAX_S on, into the boon choice; the choice ends once every present hero has
// picked, or BOON_TIMEOUT_S on, and the held wave is due at once.
update_pit :: proc(t: ^Tick) {
	if !in_pit(t) do return
	pit := &t.state.pit
	age := u32(t.time - pit.since)
	switch pit.stage {
	case .Waves:
		faced := t.state.floor_surges
		due := !sim.timer_running(t, t.state.surge)
		if due && faced > 0 && faced % PIT_BOON_EVERY == 0 && pit.lulls < faced / PIT_BOON_EVERY {
			pit.stage, pit.since = .Lull, t.time
		}
	case .Lull:
		alive := minions_alive(&t.state.minions) + elites_alive(&t.state.elites)
		if alive > PIT_LULL && age < PIT_LULL_MAX_TICKS do return
		end_lull(t)
	case .Choosing:
		chosen := true
		heroes := sim.iterate_present(t)
		for hero in sim.next(&heroes) do chosen &&= has_picked(hero, t.state.run.offers)
		if !chosen && age < BOON_TIMEOUT_TICKS do return
		pick_for_the_late(t)
		pit.lulls += 1
		pit.stage, pit.since = .Waves, t.time
		sim.emit(t, Event_Choice{open = false})
	}
}

// A lull ends: every skeleton still standing falls (a killing blow from nobody, Hit_Source.Fall), whatever the waves
// still owed goes, every downed hero rises at REVIVE_HP (revived by nobody), and the boon choice opens.
@(private = "file")
end_lull :: proc(t: ^Tick) {
	minions := sim.iterate(&t.state.minions)
	for minion, handle in sim.next(&minions) do damage_minion(t, handle, minion.hp, {}, 0, {}, .Fall)
	elites := sim.iterate(&t.state.elites)
	for elite, handle in sim.next(&elites) do damage_elite(t, handle, elite.hp, {}, 0, {}, .Fall, elite.pos.xz)
	t.state.rising = 0
	downed := sim.iterate_present(t)
	for hero, player in sim.next(&downed) {
		if hero.action == .Down do revive_hero(t, player, {})
	}
	t.state.run.offers += 1
	t.state.pit.stage, t.state.pit.since = .Choosing, t.time
	sim.emit(t, Event_Choice{open = true})
}
