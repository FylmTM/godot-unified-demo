// The extension's views as functions of the state: a minion's crowd instance (minion_instance), the contract the
// crowd's shader reads (game/crowd/crowd_minion.gdshader's header).
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:godot"
import "unified:headless"
import "unified:sim"

import g "../crypt_crew"
import ext "../extension"

// A minion's instance is its state: keyed by its handle, at its feet and facing; its clip by its phase (a chaser that
// isn't moving stands); a one-shot's start its phase's tick, a loop's minus its gait phase (the same whichever loop, so
// stopping and going doesn't restart the gait); its hit's stamp, or far past when never struck.
@(test)
a_minion_instance_is_its_state :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	spawn := spawn_of(&run, 0)
	handle := place_minion(&run, spawn + {3, 0, 0}, .Chase, {-1, 0})
	minion := sim.get(&run.simulation.state.minions, handle)
	key := sim.handle_key(handle)
	gait := -f32(key % ext.MINION_PHASE_KEYS) * ext.MINION_PHASE_S * g.TICK_HZ
	Case :: struct {
		phase:  g.Minion_Phase,
		moving: bool,
		clip:   ext.Minion_Clip,
		loops:  bool,
	}
	cases := []Case {
		{.Rise, false, .Rise, false},
		{.Idle, false, .Idle, true},
		{.Chase, true, .Walk, true},
		{.Chase, false, .Idle, true},
		{.Attack, false, .Attack, false},
		{.Dying, false, .Death, false},
	}
	for c in cases {
		minion.phase, minion.since = c.phase, 300
		minion.vel = {ext.MINION_STILL_SPEED * 2, 0, 0} if c.moving else {}
		minion.struck = 0
		item := ext.minion_instance(minion, handle)
		testing.expect_value(t, item.key, key)
		testing.expect_value(t, item.kind, ext.MultiView.Minion)
		testing.expect_value(t, item.pos, sim.Position(minion.pos))
		testing.expect_value(t, item.rot, dmath.quat_yaw(minion.facing))
		testing.expectf(t, item.custom[0] == f32(c.clip), "%v: clip %v, not %v", c.phase, item.custom[0], c.clip)
		testing.expect_value(t, item.custom[1], gait if c.loops else 300)
		testing.expect_value(t, item.custom[2], ext.MINION_NEVER_STRUCK)
		minion.struck = 280
		testing.expect_value(t, ext.minion_instance(minion, handle).custom[2], 280)
	}
}

// Every instance of a crowd the arena holds, fought by four scripted heroes, is the same whether each tick was
// re-simulated over a window of 8 ticks (a rollback every tick) or of 1: an instance is a function of the state, so
// what a view shows right after a rollback is what the re-simulated state says.
@(test)
the_crowd_after_a_rollback_is_the_states :: proc(t: ^testing.T) {
	runs: [2]headless.Run(g.Game)
	for &run, i in runs {
		run = headless.run_begin(&g.GAME, 7, g.Setup{floor = .Arena, crowd = .Fight}, window = 8 if i == 0 else 1)
	}
	defer for &run in runs do headless.run_end(&run)
	compared := 0
	for tick in 0 ..< 6 * g.TICK_HZ {
		for &run in runs do headless.run_scripted(&run, g.PLAYERS)
		if tick % 32 != 31 do continue
		items: [2][dynamic]godot.Multi_View_Item(ext.MultiView)
		defer for list in items do delete(list)
		for &run, i in runs {
			minions := sim.iterate(&run.simulation.state.minions)
			for minion, handle in sim.next(&minions) do append(&items[i], ext.minion_instance(minion, handle))
		}
		testing.expect_value(t, len(items[1]), len(items[0]))
		for item, index in items[0] {
			if index < len(items[1]) && items[1][index] != item {
				testing.expectf(t, false, "tick %d: instance %d differs: %v, %v", tick, index, item, items[1][index])
				return
			}
		}
		compared += len(items[0])
	}
	testing.expectf(t, compared > 1000, "only %d instances compared", compared)
}
