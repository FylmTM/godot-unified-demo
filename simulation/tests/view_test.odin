// The extension's views as functions of the state: a minion's crowd instance (minion_instance), the contract the
// crowd's shader reads (game/crowd/crowd_minion.gdshader's header), and a coin's (loot_instance, game/views/
// coin.gdshader's). An instance is a function of its row and handle alone, so what a view shows after a rollback is the
// re-simulated state's: the sim's own rollback tests hold that.
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

// A clip's number is the shader's index into the clip table: MinionCrowd.Clip's numbers in game/crowd/minion_crowd.gd,
// which the art checks pin to these same numbers (game/tools/art_checks.gd's CROWD_CLIPS), so neither list can reorder
// alone.
@(test)
the_clips_are_the_crowds_numbers :: proc(t: ^testing.T) {
	numbers := [ext.Minion_Clip]int {
		.Idle   = 0,
		.Walk   = 1,
		.Attack = 2,
		.Rise   = 3,
		.Death  = 4,
	}
	for number, clip in numbers {
		testing.expectf(t, int(clip) == number, "%v is %d, not the crowd's %d", clip, int(clip), number)
	}
}

// A coin's instance is its state: keyed by its handle (its events' subject), where it lies, its value and when it fell
// (the stamp the host ages); and its kind appears only once its drop is verified, aging that stamp. A solo session's
// every tick is verified as it is computed, so no walk tells Verified from Predicted there: this holds the policy.
@(test)
a_coin_instance_is_its_state :: proc(t: ^testing.T) {
	coin := g.Loot {
		pos     = {4, 0, -2},
		dropped = 700,
		value   = 3,
	}
	handle := sim.Handle(g.Loot) {
		index      = 5,
		generation = 2,
	}
	item := ext.loot_instance(&coin, handle)
	testing.expect_value(t, item.key, sim.handle_key(handle))
	testing.expect_value(t, item.kind, ext.MultiView.Loot)
	testing.expect_value(t, item.pos, sim.Position(coin.pos))
	testing.expect_value(t, item.custom, [4]f32{3, 700, 0, 0})
	policy := ext.MULTI_POLICY[.Loot]
	testing.expect_value(t, policy.appear, godot.Appear.Verified)
	testing.expect_value(t, policy.ages, bit_set[0 ..< 4;u8]{1})
}
