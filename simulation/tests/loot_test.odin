// The loot rule tests (loot.odin): a death's drop is a roll named by state, the same whichever tick the kill lands
// on; a coin is picked up once armed, by the lowest slot when two heroes reach it at once, until its last tick; a
// drop's total splits between its coins; the save carries the purse; a held crowd drops nothing. Each on a sync-tested
// run (headless.Run), so every pickup here is also rolled back over and re-simulated.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:sim"

import g "../crypt_crew"

// A coin worth `value` lying at `at`, dropped `age` ticks before the next tick computes (LOOT_ARM_TICKS: armed then),
// pinned there.
place_coin :: proc(run: ^headless.Run(g.Game), at: [3]f32, value: u16, age: u32) -> sim.Handle(g.Loot) {
	state := &run.simulation.state
	coin, handle, spawned := sim.spawn(&state.loot)
	assert(spawned, "the loot table is full")
	coin^ = {
		pos     = at,
		dropped = state.clock.time + 1 - sim.Game_Time(age),
		value   = value,
	}
	headless.run_pin(run)
	return handle
}

// The coins on the floor, in table order: each one's value and where it lies.
@(private = "file")
Coins :: struct {
	values: [dynamic]u16,
	places: [dynamic][3]f32,
}

@(private = "file")
coins_of :: proc(run: ^headless.Run(g.Game)) -> (coins: Coins) {
	coins.values = make([dynamic]u16, context.temp_allocator)
	coins.places = make([dynamic][3]f32, context.temp_allocator)
	walk := sim.iterate(&run.simulation.state.loot)
	for coin in sim.next(&walk) {
		append(&coins.values, coin.value)
		append(&coins.places, coin.pos)
	}
	return
}

// The floor's sleeping packs felled by a dev kill (a command, so it lands when it is sent) after `idle` ticks: what
// they drop.
@(private = "file")
packs_dropped :: proc(t: ^testing.T, idle: int) -> Coins {
	run := headless.run_begin(&g.GAME, 3, seated = 1)
	defer headless.run_end(&run)
	for _ in 0 ..< idle do headless.run_step(&run)
	headless.run_command(&run, 0, g.Command_Dev_Kill_Minions{})
	felled := run.simulation.state.drops
	testing.expect_value(t, felled, u32(headless.run_events(&run, g.Event_Minion_Died)))
	coins := coins_of(&run)
	testing.expect_value(t, len(coins.values), headless.run_events(&run, g.Event_Loot_Dropped))
	// The rolls by their names, written out here rather than asked of minion_drop: the death behind drop roll `key`
	// drops on index 0's 1 in LOOT_ONE_IN, worth index 1's roll, its coin the next row of the table.
	dropped := 0
	for key in 0 ..< u64(felled) {
		if sim.roll_below_at(3, 0, g.LOOT_ONE_IN, g.Roll.Drop, key, 0) != 0 do continue
		value :=
			g.LOOT_VALUE_MIN +
			int(sim.roll_below_at(3, 0, g.LOOT_VALUE_MAX - g.LOOT_VALUE_MIN + 1, g.Roll.Drop, key, 1))
		if dropped < len(coins.values) {
			testing.expectf(
				t,
				int(coins.values[dropped]) == value,
				"drop roll %d: worth %d, not %d",
				key,
				coins.values[dropped],
				value,
			)
		}
		dropped += 1
	}
	testing.expectf(t, dropped == len(coins.values), "%d coins dropped, the rolls say %d", len(coins.values), dropped)
	scenarios.expect_synced(t, &run)
	return coins
}

// A felled minion's drop is a roll named by the session's count of drop rolls, not by the tick: the same packs felled
// a tick later drop the same coins, worth the same, where the same minions fell, as the rolls named by the count say.
@(test)
a_drop_is_the_same_whichever_tick_the_kill_lands :: proc(t: ^testing.T) {
	now := packs_dropped(t, 10)
	later := packs_dropped(t, 11)
	testing.expect(t, len(now.values) > 0, "the packs dropped coins")
	testing.expectf(t, len(now.values) == len(later.values), "%d coins, then %d", len(now.values), len(later.values))
	for i in 0 ..< min(len(now.values), len(later.values)) {
		testing.expectf(t, now.values[i] == later.values[i], "coin %d: %d, then %d", i, now.values[i], later.values[i])
		testing.expectf(
			t,
			now.places[i] == later.places[i],
			"coin %d at %v, then %v",
			i,
			now.places[i],
			later.places[i],
		)
	}
}

// A coin lies LOOT_ARM_S before a hero standing on it picks it up; then its value goes into the purse, which the
// event carries.
@(test)
a_coin_is_picked_up_once_armed :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	feet := sim.slot_data(run.simulation, 0).pos
	handle := place_coin(&run, feet, 3, 0)
	for _ in 0 ..< g.LOOT_ARM_TICKS {
		headless.run_step(&run)
		testing.expect(t, sim.get(&run.simulation.state.loot, handle) != nil, "a coin lies until it is armed")
	}
	headless.run_step(&run)
	testing.expect(t, sim.get(&run.simulation.state.loot, handle) == nil, "an armed coin is picked up")
	testing.expect_value(t, run.simulation.state.gold, 3)
	collected, found := headless.run_last_event(&run, g.Event_Loot_Collected)
	testing.expect(t, found, "Event_Loot_Collected")
	testing.expect_value(t, collected.loot, handle)
	testing.expect_value(t, collected.player, sim.player_in_slot(run.simulation, 0))
	testing.expect_value(t, collected.value, 3)
	testing.expect_value(t, collected.gold, 3)
	scenarios.expect_synced(t, &run)
}

// Two heroes reaching one coin on the same tick: the lower slot takes it, the nearer or not, so every peer agrees; the
// purse counts it once.
@(test)
the_lower_slot_takes_a_coin_two_reach :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	coin_at := spawn_of(&run, 0) + {2, 0, 0}
	place_hero(&run, 1, coin_at + {0.5, 0, 0}) // the nearer
	place_hero(&run, 0, coin_at - {1, 0, 0})
	handle := place_coin(&run, coin_at, 2, g.LOOT_ARM_TICKS)
	headless.run_step(&run)
	testing.expect(t, sim.get(&run.simulation.state.loot, handle) == nil, "the coin is picked up")
	testing.expect_value(t, headless.run_events(&run, g.Event_Loot_Collected), 1)
	collected, _ := headless.run_last_event(&run, g.Event_Loot_Collected)
	testing.expect_value(t, collected.player, sim.player_in_slot(run.simulation, 0))
	testing.expect_value(t, run.simulation.state.gold, 2)
	scenarios.expect_synced(t, &run)
}

// A coin is there to be picked up through its last tick (LOOT_LIFE_TICKS - 1 old) and gone on the next, touched or
// not; a downed hero picks up nothing.
@(test)
a_coin_lasts_its_life :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	last := place_coin(&run, sim.slot_data(run.simulation, 0).pos, 1, g.LOOT_LIFE_TICKS - 1)
	gone := place_coin(&run, sim.slot_data(run.simulation, 1).pos, 1, g.LOOT_LIFE_TICKS)
	headless.run_step(&run)
	testing.expect(t, sim.get(&run.simulation.state.loot, last) == nil, "its last tick: picked up")
	testing.expect(t, sim.get(&run.simulation.state.loot, gone) == nil, "past it: gone")
	testing.expect_value(t, headless.run_events(&run, g.Event_Loot_Collected), 1)
	testing.expect_value(t, run.simulation.state.gold, 1)
	lying := place_coin(&run, sim.slot_data(run.simulation, 1).pos + {3, 0, 0}, 1, g.LOOT_LIFE_TICKS - 1)
	headless.run_step(&run)
	testing.expect(t, sim.get(&run.simulation.state.loot, lying) != nil, "an untouched coin lies its life ...")
	headless.run_step(&run)
	testing.expect(t, sim.get(&run.simulation.state.loot, lying) == nil, "... and then goes")
	hurt(&run, 1, g.HERO_HP)
	testing.expect_value(t, sim.slot_data(run.simulation, 1).action, g.Action.Down)
	downed := place_coin(&run, sim.slot_data(run.simulation, 1).pos, 1, g.LOOT_ARM_TICKS)
	headless.run_step(&run)
	testing.expect(t, sim.get(&run.simulation.state.loot, downed) != nil, "a downed hero picks up nothing")
	scenarios.expect_synced(t, &run)
}

// A drop of several coins splits its total between them, the first ones a gold more, adding up to it exactly (an
// elite's drop); the dev drop lays its coins, a gold each, evenly on DEV_DROP_RING round the sender's hero.
@(test)
a_drop_splits_its_total :: proc(t: ^testing.T) {
	values: [5]int
	for &value, i in values do value = g.coin_value(23, 5, i)
	testing.expect_value(t, values, [5]int{5, 5, 5, 4, 4})
	testing.expect_value(t, g.coin_value(3, 1, 0), 3)
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	feet := sim.slot_data(run.simulation, 0).pos
	headless.run_command(&run, 0, g.Command_Dev_Drop_Loot{5})
	coins := coins_of(&run)
	testing.expect_value(t, len(coins.values), 5)
	for value in coins.values do testing.expect_value(t, value, 1)
	for place in coins.places {
		apart := place.xz - feet.xz
		off := apart.x * apart.x + apart.y * apart.y - g.DEV_DROP_RING * g.DEV_DROP_RING
		testing.expectf(t, off * off < 0.01, "a coin %v from the hero, not on DEV_DROP_RING", apart)
	}
	scenarios.expect_synced(t, &run)
}

// The save carries the purse as it stood at the last save point (the descent's, the hoard's gold in it), not the
// coins lying on the floor, and a session started from it starts with that gold and none lying.
@(test)
the_save_carries_the_purse :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	clear_elites(&run)
	place_coin(&run, sim.slot_data(run.simulation, 0).pos, 3, g.LOOT_ARM_TICKS)
	headless.run_step(&run)
	testing.expect_value(t, run.simulation.state.gold, 3)
	descend(&run)
	saved := run.simulation.setup
	testing.expect(t, sim.save_changed(run.simulation, run.simulation.tick, &saved), "the descent saves")
	testing.expect_value(t, saved.gold, 3 + g.HOARD_GOLD)
	place_coin(&run, spawn_of(&run, 0) + {4, 0, 0}, 5, 0) // lying when the session ends: not the save's
	place_coin(&run, sim.slot_data(run.simulation, 0).pos, 2, g.LOOT_ARM_TICKS)
	headless.run_step(&run)
	testing.expect_value(t, run.simulation.state.gold, 5 + g.HOARD_GOLD)
	testing.expect(t, !sim.save_changed(run.simulation, run.simulation.tick, &saved), "a pickup makes no save")
	testing.expect_value(t, saved.gold, 3 + g.HOARD_GOLD)
	scenarios.expect_synced(t, &run)

	continued := headless.run_begin(&g.GAME, 2, saved, seated = 1)
	defer headless.run_end(&continued)
	testing.expect_value(t, continued.simulation.state.gold, 3 + g.HOARD_GOLD)
	testing.expect_value(t, continued.simulation.state.saved.gold, 3 + g.HOARD_GOLD) // the save, until its next point
	testing.expect_value(t, continued.simulation.state.loot.count, 0)
	place_coin(&continued, sim.slot_data(continued.simulation, 0).pos, 1, g.LOOT_ARM_TICKS)
	headless.run_step(&continued)
	collected, _ := headless.run_last_event(&continued, g.Event_Loot_Collected)
	testing.expect_value(t, collected.gold, 4 + g.HOARD_GOLD)
	scenarios.expect_synced(t, &continued)
}

// A held crowd's felled drop nothing: its felled come back by the hundred.
@(test)
a_held_crowd_drops_nothing :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Arena, crowd = .Fight}, seated = 1)
	defer headless.run_end(&run)
	headless.run_command(&run, 0, g.Command_Dev_Kill_Minions{})
	testing.expect(t, headless.run_events(&run, g.Event_Minion_Died) > 0, "the crowd fell")
	testing.expect_value(t, headless.run_events(&run, g.Event_Loot_Dropped), 0)
	testing.expect_value(t, run.simulation.state.drops, 0)
	scenarios.expect_synced(t, &run)
}

// A wipe's restart takes the coins lying on the floor with it, and the purse back to what the save point held (the
// descent's), as it does the felled.
@(test)
a_wipe_takes_the_purse_back_to_the_save :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	clear_minions(&run)
	clear_elites(&run)
	place_coin(&run, sim.slot_data(run.simulation, 0).pos, 2, g.LOOT_ARM_TICKS)
	headless.run_step(&run)
	descend(&run)
	place_coin(&run, sim.slot_data(run.simulation, 0).pos, 3, g.LOOT_ARM_TICKS)
	headless.run_step(&run)
	testing.expect_value(t, run.simulation.state.gold, 5 + g.HOARD_GOLD)
	headless.run_command(&run, 0, g.Command_Dev_Drop_Loot{4})
	testing.expect_value(t, run.simulation.state.loot.count, 4)
	for slot in 0 ..< 2 do hurt(&run, slot, g.HERO_HP)
	for headless.run_events(&run, g.Event_Floor_Restarted) == 0 && run.simulation.state.clock.time < 40 * g.TICK_HZ {
		headless.run_step(&run)
	}
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 1)
	testing.expect_value(t, run.simulation.state.loot.count, 0)
	testing.expect_value(t, run.simulation.state.gold, 2 + g.HOARD_GOLD)
	scenarios.expect_synced(t, &run)
}

// The standard scenarios' scripted run picks coins up (the script's dev drops and its kills), so their rollbacks,
// churn and late joiner cross pickups, not only drops.
@(test)
the_suite_runs_cross_a_pickup :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, SUITE.seed, window = 1)
	defer headless.run_end(&run)
	for _ in 0 ..< SUITE.ticks do headless.run_scripted(&run, CLIENTS)
	testing.expectf(
		t,
		headless.run_events(&run, g.Event_Loot_Collected) >= 1,
		"the %d-tick run picked up no coin",
		SUITE.ticks,
	)
}

// A felled elite (a risen kind: the King's fall pays into the purse, boss_test.odin) drops ELITE_COINS coins on the
// LOOT_SPREAD ring round where it fell, worth its kind's ELITE_GOLD between them, every time (no roll); under a held
// crowd, none.
@(test)
a_felled_elite_drops_its_coins :: proc(t: ^testing.T) {
	for kind in g.Elite_Kind(0) ..< g.Elite_Kind(g.RISEN_KINDS) {
		run := headless.run_begin(&g.GAME, 1, seated = 1)
		defer headless.run_end(&run)
		clear_minions(&run)
		clear_elites(&run)
		place_hero(&run, 0, spawn_of(&run, 0))
		handle := place_elite(&run, kind, spawn_of(&run, 0) + {4, 0, 0}, {-1, 0}, .Rise)
		fell := elite_of(&run, handle).pos
		headless.run_command(&run, 0, g.Command_Dev_Hurt_Elites{g.ELITE_SPECS[kind].hp})
		testing.expect_value(t, headless.run_events(&run, g.Event_Elite_Died), 1)
		testing.expect_value(t, headless.run_events(&run, g.Event_Loot_Dropped), g.ELITE_COINS)
		gold := 0
		coins := sim.iterate(&run.simulation.state.loot)
		for coin in sim.next(&coins) {
			gold += int(coin.value)
			apart := dmath.length(coin.pos.xz - fell.xz)
			testing.expectf(
				t,
				abs(apart - g.LOOT_SPREAD) < 0.05,
				"a %v's coin lies %v m from where it fell",
				kind,
				apart,
			)
		}
		testing.expectf(t, gold == g.ELITE_GOLD[kind], "a %v's coins are worth %d", kind, gold)
		scenarios.expect_synced(t, &run)
	}
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Arena, crowd = .Fight}, seated = 1)
	defer headless.run_end(&run)
	place_elite(&run, .Warrior, sim.slot_data(run.simulation, 0).pos + {3, 0, 0}, {-1, 0}, .Rise)
	headless.run_command(&run, 0, g.Command_Dev_Hurt_Elites{g.ELITE_SPECS[.Warrior].hp})
	testing.expect_value(t, headless.run_events(&run, g.Event_Elite_Died), 1)
	testing.expect_value(t, headless.run_events(&run, g.Event_Loot_Dropped), 0)
	scenarios.expect_synced(t, &run)
}
