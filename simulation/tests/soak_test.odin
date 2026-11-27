// The soak: four players sending noise, on a sync-tested run. Every slot's Input is filled with random bytes, any bits a
// modified client could send (held a random while, so heroes travel, hold blocks and revives, and press in between),
// and each slot sends the commands a player's build can send (no dev command) at random, out-of-range values
// included. Every tick must re-simulate the same (scenarios.expect_synced: no mismatch, no failed restore check, no NaN
// in the block) and keep the game's invariants (soak_problem). Each seed plays one of the levels (SOAK_LEVELS), so
// `uni test --long`'s sixteen seeds cover every one.
//
// A seed that fails is kept as a test of its own, named for what it found, beside random_inputs_break_nothing, so it
// runs on every `uni test` from then on, whatever the seed range becomes:
//
//   @(test)
//   random_inputs_seed_9_downed_hero_below_floor :: proc(t: ^testing.T) {soak(t, 9)}
//
// then shrink it into a rule test (the unified-desync skill, Shrink) once the cause is known.
package test_crypt_crew

import "core:fmt"
import "core:testing"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:sim"

import g "../crypt_crew"

SOAK_TICKS :: 1200 // per seed: about 19 s of play, past a surge
SOAK_SEEDS :: 16 when scenarios.LONG else 2
SOAK_HOLD_MAX :: 32 // the longest a slot holds one random Input, in ticks
// A present hero's feet stay at most this far below its floor's lowest walkable point: the lift's ride down
// (LIFT_DROP) and a hand's slack. A downed hero's are its ragdoll's pelvis, which settle_ragdolls lays anew before it
// falls RAGDOLL_KILL_DEPTH.
SOAK_BELOW_FLOOR :: g.LIFT_DROP + 0.5

// The level each seed plays, by seed: the default seeds play Floor 1 and the hub.
@(rodata)
SOAK_LEVELS := [?]g.Level_Id{.Floor_1, .Hub, .Floor_2, .Floor_3, .Vault, .Arena, .Workshop}

@(test)
random_inputs_break_nothing :: proc(t: ^testing.T) {
	for seed in 0 ..< u64(SOAK_SEEDS) do soak(t, seed)
}

// SOAK_TICKS of random play with `seed` (the stream's and the session's) on its level; fails at the first tick that
// re-simulates differently or breaks an invariant, naming the seed and the tick.
soak :: proc(t: ^testing.T, seed: u64, loc := #caller_location) {
	level := SOAK_LEVELS[seed % len(SOAK_LEVELS)]
	run := headless.run_begin(&g.GAME, seed, g.Setup{floor = level}, seated = g.PLAYERS)
	defer headless.run_end(&run)
	noise := sim.rng_seed(seed)
	held: [g.PLAYERS]g.Input
	hold: [g.PLAYERS]u32
	for _ in 0 ..< SOAK_TICKS {
		inputs := headless.run_inputs(&run)
		for slot in 0 ..< g.PLAYERS {
			if hold[slot] == 0 {
				bytes := ([^]u8)(&held[slot])[:size_of(g.Input)]
				for &b in bytes do b = u8(sim.rng_next(&noise))
				hold[slot] = 1 + sim.rng_below(&noise, SOAK_HOLD_MAX)
			}
			hold[slot] -= 1
			inputs.input[slot] = held[slot]
			switch sim.rng_below(&noise, 600) {
			case 0:
				sim.add_command(&inputs, slot, g.Command_Set_Paused{true})
			case 1 ..= 15:
				sim.add_command(&inputs, slot, g.Command_Set_Paused{false})
			case 16 ..= 27:
				sim.add_command(&inputs, slot, g.Command_Pick_Boon{u8(sim.rng_next(&noise))})
			}
		}
		headless.run_step(&run, &inputs)
		tick := run.simulation.tick
		if !scenarios.expect_synced(t, &run, loc) {
			testing.expectf(t, false, "soak seed %d (%v): out of sync by tick %d", seed, level, tick, loc = loc)
			return
		}
		if problem := soak_problem(&run); problem != "" {
			testing.expectf(t, false, "soak seed %d (%v), tick %d: %s", seed, level, tick, problem, loc = loc)
			return
		}
	}
}

// The first invariant the run's newest tick breaks ("": none; temp-allocated): the live minions within the floor's
// cap and the live elites within ELITES_ALIVE_MAX, every present hero's health within 0 and its most, and its feet,
// and every minion's and elite's, finite and not below the floor.
@(private = "file")
soak_problem :: proc(run: ^headless.Run(g.Game)) -> string {
	state := &run.simulation.state
	floor := floor_of(run)
	if alive := g.minions_alive(&state.minions); alive > floor.minion_cap {
		return fmt.tprintf("%d minions alive, past the floor's cap of %d", alive, floor.minion_cap)
	}
	if alive := g.elites_alive(&state.elites); alive > g.ELITES_ALIVE_MAX {
		return fmt.tprintf("%d elites alive, past ELITES_ALIVE_MAX", alive)
	}
	heroes := sim.iterate_present(&state.players)
	for hero, player in sim.next(&heroes) {
		if hero.hp < 0 || hero.hp > g.hero_max_hp(hero) {
			return fmt.tprintf("player %v's hero has %d HP of %d", player, hero.hp, g.hero_max_hp(hero))
		}
		if problem := below_floor(floor, hero.pos); problem != "" do return fmt.tprintf("player %v's hero %s", player, problem)
	}
	minions := sim.iterate(&state.minions)
	for minion, handle in sim.next(&minions) {
		if problem := below_floor(floor, minion.pos); problem != "" do return fmt.tprintf("minion %v %s", handle, problem)
	}
	elites := sim.iterate(&state.elites)
	for elite, handle in sim.next(&elites) {
		if problem := below_floor(floor, elite.pos); problem != "" do return fmt.tprintf("elite %v %s", handle, problem)
	}
	return ""
}

// What is wrong with feet at `pos` on `floor` ("": nothing): not finite, or below the floor.
@(private = "file")
below_floor :: proc(floor: ^g.Floor, pos: [3]f32) -> string {
	for x in pos do if !(x - x == 0) do return fmt.tprintf("is at %v", pos) // NaN or infinite
	if pos.y < floor.lowest - SOAK_BELOW_FLOOR {
		return fmt.tprintf("is at %v, below the floor's lowest point %v", pos, floor.lowest)
	}
	return ""
}
