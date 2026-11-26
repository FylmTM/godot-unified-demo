// The extension's views as functions of the state: a minion's crowd instance (minion_instance), the contract the
// crowd's shader reads (game/crowd/crowd_minion.gdshader's header), a coin's (loot_instance, game/views/
// coin.gdshader's), the fireball's landing ring, filled from a frame's local input, and how an elite's scene view
// appears. An instance is a function of its row and handle alone, so what a view shows after a rollback is the
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

// The ring where a local Mage's fireball will land is the cast's landing: the frame's fill (fill_fireballs), given the
// Mage's newest input sample as Frame.local_inputs, rings the spot the cast leaves for when that input reaches the
// tick its windup ends, brighter while it winds up.
@(test)
the_fireball_ring_is_where_the_cast_lands :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Mage})
	clear_minions(&run)
	place_hero(&run, 0, spawn_of(&run, 0), {1, 0})
	aim := g.Input {
		aim   = dmath.dir2({1, 0.3}),
		reach = g.reach_steps(4.5),
	}
	pressed := aim
	pressed.buttons = {.Ability}
	headless.run_step(&run, [g.PLAYERS]g.Input{0 = pressed})
	for _ in 1 ..< g.FIREBALL_WINDUP_TICKS do headless.run_step(&run, [g.PLAYERS]g.Input{0 = aim})
	out := godot.Frame_Data {
		alloc = context.allocator,
	}
	defer {
		delete(out.views)
		delete(out.data)
	}
	poses: godot.Pose_Memory
	godot.pose_memory_init(&poses, 8, 8)
	defer godot.pose_memory_destroy(&poses)
	godot.pose_memory_begin(&poses)
	mage := sim.player_in_slot(run.simulation, 0)
	frame := ext.Frame {
		state = &run.simulation.state,
		world = run.simulation.world,
		tick = run.simulation.tick,
		local_players = {0 = mage},
		local_inputs = {0 = aim},
		time = run.simulation.state.clock.time,
		out = &out,
		poses = &poses,
	}
	ext.fill_fireballs(&frame)
	ring: [3]f32
	casting, found := false, false
	for view in out.views[:out.n_views] {
		if view.data_type != ext.View_Fireball_Target do continue
		ring, found = view.pos, true
		casting = (^ext.View_Fireball_Target)(&out.data[view.data_offset]).casting
	}
	testing.expect(t, found && casting, "the frame rings a casting Mage's landing")
	headless.run_step(&run, [g.PLAYERS]g.Input{0 = aim}) // the windup's end: the fireball leaves
	walk := sim.iterate(&run.simulation.state.fireballs)
	left: g.Fireball
	for row in sim.next(&walk) do left = row^
	testing.expectf(t, ring == left.to, "the ring at %v, the fireball lands at %v", ring, left.to)
}

// An elite's view appears once its spawn is verified (as a minion's): a remote dev spawn or a surge a late command
// moved would otherwise flash and vanish. The extension's policy says so; the host's appear-on-verified is unified's.
@(test)
an_elite_appears_once_verified :: proc(t: ^testing.T) {
	for policy in ext.VIEW_POLICY {
		if policy.kind == ext.View_Elite {
			testing.expect_value(t, policy.policy.appear, godot.Appear.Verified)
			return
		}
	}
	testing.expect(t, false, "View_Elite has no policy: it would appear on the prediction")
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

// A downed ally a Barbarian heaves shows no revive ring: its hero's view carries the heave (View_Hero.heave, which
// game/views/hero.gd reads to hide the ring), Held while it hangs and None again once it is let down.
@(test)
a_heaved_allys_view_says_so :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 2)
	defer headless.run_end(&run)
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Barbarian})
	clear_minions(&run)
	place_hero(&run, 0, spawn_of(&run, 0), {1, 0})
	place_hero(&run, 1, spawn_of(&run, 0) + {1.3, 0, 0})
	hurt(&run, 1, g.HERO_HP)
	press(&run, 0, .Ability)
	ally := sim.player_in_slot(run.simulation, 1)
	testing.expect_value(t, ally_view_heave(&run, ally), g.Heave_Phase.Held)
	for _ in 0 ..< g.HEAVE_MAX_TICKS do headless.run_step(&run)
	testing.expect_value(t, ally_view_heave(&run, ally), g.Heave_Phase.None)
}

// The heave `player`'s hero view shows, from the heroes of a frame of the run's newest state (fill_heroes).
@(private = "file")
ally_view_heave :: proc(run: ^headless.Run(g.Game), player: sim.Player) -> g.Heave_Phase {
	out := godot.Frame_Data {
		alloc = context.allocator,
	}
	defer {
		delete(out.views)
		delete(out.data)
	}
	poses: godot.Pose_Memory
	godot.pose_memory_init(&poses, 64, 64)
	defer godot.pose_memory_destroy(&poses)
	godot.pose_memory_begin(&poses)
	frame := ext.Frame {
		state = &run.simulation.state,
		world = run.simulation.world,
		tick  = run.simulation.tick,
		time  = run.simulation.state.clock.time,
		out   = &out,
		poses = &poses,
	}
	ext.fill_heroes(&frame)
	for view in out.views[:out.n_views] {
		if view.data_type == ext.View_Hero && view.key == sim.player_key(player) {
			return (^ext.View_Hero)(&out.data[view.data_offset]).heave
		}
	}
	return .None
}
