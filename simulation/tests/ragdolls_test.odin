// The ragdolls' rule tests (ragdolls.odin): a hero going down falls as a ragdoll knocked away from the blow, its
// capsule dormant and out of the world; a revive stands it up on the floor where its body lies; a ragdoll rolls back,
// reaches a late joiner and goes with its hero (a leave, a wipe's restart); it meets the floor, props and other
// ragdolls, never a hero; a heave stands the capsule up from it (until milestone 6's last step). Each on a sync-tested
// run (headless.Run) that ends synced, the physics world's refs checked after every restore (an orphaned bone fails).
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// A run of `seated` heroes with no minion, each at its spawn.
@(private = "file")
ragdoll_run :: proc(seated: int) -> headless.Run(g.Game) {
	run := headless.run_begin(&g.GAME, 1, seated = seated)
	clear_minions(&run)
	for slot in 0 ..< seated do place_hero(&run, slot, spawn_of(&run, slot))
	return run
}

// Slot `slot`'s hero, at REVIVE_HP's worth of one minion's blow, goes down to a minion swinging at it from its right
// (the hero faces +X, the minion stands at -Z of it): the tick it falls.
@(private = "file")
downed_by_a_minion :: proc(t: ^testing.T, run: ^headless.Run(g.Game), slot: int) -> (from: [3]f32) {
	hero := sim.slot_data(run.simulation, slot)
	hero.hp = g.MINION_DAMAGE
	headless.run_pin(run)
	from = hero.pos + {0, 0, -(g.HERO_RADIUS + g.MINION_RADIUS + 0.3)}
	place_minion(run, from, .Chase, {0, 1})
	for _ in 0 ..< 3 * g.TICK_HZ {
		headless.run_step(run)
		if hero.action == .Down do return
	}
	testing.expect(t, false, "the minion never downed the hero")
	return
}

// The bodies a ragdoll's bones are: each alive, its bones' mass RAGDOLL_MASS between them.
@(private = "file")
ragdoll_mass :: proc(run: ^headless.Run(g.Game), hero: ^g.Hero) -> (mass: f32) {
	for body in hero.ragdoll.bones do mass += physics.body_mass(run.simulation.world.phys, body)
	return
}

// A hero going down falls as a ragdoll: its capsule dormant and out of the world where it stood, a ragdoll of
// RAGDOLL_MASS in its place in CAT_RAGDOLL, its bones named as intern_ragdoll_names names the anchor, moving
// RAGDOLL_KICK away from the blow (the minion at its right, not along its facing), its pos the pelvis's; the body comes
// to rest lying on the floor.
@(test)
going_down_makes_a_ragdoll :: proc(t: ^testing.T) {
	run := ragdoll_run(1)
	defer headless.run_end(&run)
	phys := run.simulation.world.phys
	hero := sim.slot_data(run.simulation, 0)
	floor_y := hero.pos.y
	from := downed_by_a_minion(t, &run, 0)
	testing.expect(t, g.ragdolled(hero), "down, it lies as a ragdoll")
	testing.expect(t, physics.character_dormant(&hero.body), "its capsule is dormant")
	testing.expect(t, !physics.body_is_enabled(phys, hero.body.body), "its capsule is out of the world")
	testing.expect_value(t, hero.pos, physics.body_position(phys, hero.ragdoll.bones[.Pelvis]))
	mass := ragdoll_mass(&run, hero)
	testing.expectf(t, abs(mass - g.RAGDOLL_MASS) < 0.01 * g.RAGDOLL_MASS, "it weighs %v kg", mass)
	for body, bone in hero.ragdoll.bones {
		testing.expect_value(t, physics.body_name(phys, body), g.RAGDOLL_BONE_NAMES[bone])
	}
	away := dmath.normalize(hero.pos.xz - from.xz)
	kick := hero.vel.xz // the tick it fell: the capsule's standstill plus the kick
	testing.expectf(t, dmath.dot(dmath.normalize(kick), away) > 0.95, "kicked along %v, not away (%v)", kick, away)
	testing.expectf(t, abs(dmath.length(kick) - g.RAGDOLL_KICK) < 0.1, "kicked at %v m/s", dmath.length(kick))
	settle(&run)
	testing.expectf(t, hero.pos.y < floor_y + 0.4, "its pelvis rests %v m up: lying", hero.pos.y - floor_y)
	scenarios.expect_synced(t, &run)
}

// A revive stands the hero up where its body lies, not where it fell: its ragdoll shoved a few metres off, it rises on
// the walkable floor under the pelvis, its capsule back in the world, awake and standing, and it walks; a hero downed
// in mid-air falls to the floor first and rises there.
@(test)
a_revive_stands_the_hero_where_its_body_lies :: proc(t: ^testing.T) {
	run := ragdoll_run(2)
	defer headless.run_end(&run)
	phys := run.simulation.world.phys
	hero := sim.slot_data(run.simulation, 1)
	place_hero(&run, 1, spawn_of(&run, 1) + {0, 1.5, 0}) // in the air
	hurt(&run, 1, g.HERO_HP)
	settle(&run)
	floor_y := spawn_of(&run, 1).y
	testing.expectf(
		t,
		hero.pos.y < floor_y + 0.4,
		"fallen from the air, its pelvis rests %v m up",
		hero.pos.y - floor_y,
	)
	physics.ragdoll_set_velocity(phys, &hero.ragdoll, {5, 1, 0}) // shoved along the hall
	headless.run_pin(&run)
	settle(&run)
	fell_at := physics.body_position(phys, hero.body.body)
	lying := hero.pos
	testing.expectf(
		t,
		dmath.length(lying.xz - fell_at.xz) > 1.5,
		"the body lies %v m from its capsule",
		lying - fell_at,
	)
	headless.run_command(&run, 0, g.Command_Dev_Revive{})
	testing.expect(t, !g.ragdolled(hero), "up, no ragdoll")
	testing.expect(t, physics.body_is_enabled(phys, hero.body.body), "its capsule is back in the world")
	testing.expect(t, !physics.character_dormant(&hero.body), "and awake")
	under := on_floor(&run, lying)
	testing.expectf(
		t,
		dmath.length(hero.pos.xz - under.xz) < 0.1,
		"rose at %v, not under its body (%v)",
		hero.pos,
		under,
	)
	play(&run, {}, 0.5)
	testing.expect(t, physics.character_grounded(&hero.body), "it stands on the floor")
	_, walkable := g.floor_spot(floor_of(&run), hero.pos, 0.2)
	testing.expect(t, walkable, "on the walkable floor")
	start := hero.pos
	play(&run, {1 = {move_z = 127}}, 0.5)
	testing.expectf(t, dmath.length(hero.pos.xz - start.xz) > 1, "it walks: %v from %v", hero.pos, start)
	scenarios.expect_synced(t, &run)
}

// A ragdoll mid-tumble rolls back (the run re-simulates every tick of it) and reaches a late joiner: a snapshot taken
// as it tumbles continues to the same checksums as the run it came from, its refs clean.
@(test)
a_tumbling_ragdoll_reaches_a_late_joiner :: proc(t: ^testing.T) {
	run := ragdoll_run(2)
	defer headless.run_end(&run)
	downed_by_a_minion(t, &run, 0)
	clear_minions(&run)
	play(&run, {}, 4.0 / g.TICK_HZ) // mid-tumble
	hero := sim.slot_data(run.simulation, 0)
	testing.expectf(t, dmath.length(hero.vel) > 1, "tumbling at %v m/s", dmath.length(hero.vel))
	snapshot := sim.snapshot_encode(run.simulation, run.simulation.tick)
	defer delete(snapshot)
	late, err := headless.run_begin_from_snapshot(&g.GAME, snapshot)
	defer headless.run_end(&late)
	testing.expect_value(t, err, sim.Snap_Error.None)
	testing.expect_value(t, physics.check_refs(late.simulation.world.phys, &late.simulation.state), "")
	for tick in 0 ..< g.TICK_HZ {
		inputs := headless.run_inputs(&run)
		headless.run_step(&run, &inputs)
		headless.run_step(&late, &inputs)
		if sim.checksum(late.simulation) != sim.checksum(run.simulation) {
			testing.expectf(t, false, "the late joiner differs %d ticks on", tick + 1)
			break
		}
	}
	scenarios.expect_synced(t, &run)
	scenarios.expect_synced(t, &late)
}

// A ragdoll goes with its hero's body: a hero leaving while down takes its ragdoll with it (no orphaned bone: the refs
// check), and comes back down, falling as a ragdoll where it arrives; a wipe's restart takes every ragdoll and stands
// every hero up at its spawn.
@(test)
no_ragdoll_outlives_its_hero :: proc(t: ^testing.T) {
	run := ragdoll_run(2)
	defer headless.run_end(&run)
	phys := run.simulation.world.phys
	leaver := sim.player_data(&run.simulation.state.players, sim.player_in_slot(run.simulation, 1))
	hurt(&run, 1, g.HERO_HP)
	play(&run, {}, 0.25)
	headless.run_seat(&run, 1, 0)
	headless.run_step(&run)
	testing.expect_value(t, leaver.ragdoll, physics.Ragdoll{})
	testing.expect_value(t, physics.check_refs(phys, &run.simulation.state), "")
	headless.run_seat(&run, 1, 2)
	headless.run_step(&run)
	testing.expect_value(t, leaver.action, g.Action.Down)
	testing.expect(t, g.ragdolled(leaver), "it comes back down, a ragdoll")
	testing.expect(t, !physics.body_is_enabled(phys, leaver.body.body), "its new capsule out of the world")
	hurt(&run, 0, g.HERO_HP)
	for _ in 0 ..< g.WIPE_TICKS do headless.run_step(&run)
	testing.expect_value(t, headless.run_events(&run, g.Event_Floor_Restarted), 1)
	heroes := sim.iterate_present(&run.simulation.state.players)
	for hero in sim.next(&heroes) {
		testing.expect(t, !g.ragdolled(hero) && hero.action == .None, "every hero up again, no ragdoll")
		testing.expect(t, physics.body_is_enabled(phys, hero.body.body), "every capsule in the world")
	}
	testing.expect_value(t, physics.check_refs(phys, &run.simulation.state), "")
	scenarios.expect_synced(t, &run)
}

// A ragdoll meets no hero: an ally walks straight through where one lies, neither slowed nor turned aside, and leaves
// it lying as it was. It meets other ragdolls: another hero's, flung into it, shoves it (it doesn't slide through).
@(test)
a_ragdoll_never_blocks_a_hero :: proc(t: ^testing.T) {
	run := ragdoll_run(3)
	defer headless.run_end(&run)
	walker, lying := sim.slot_data(run.simulation, 0), sim.slot_data(run.simulation, 1)
	start := [3]f32{4, 0, 0} // the great hall
	place_hero(&run, 1, start + {3, 0, 0})
	hurt(&run, 1, g.HERO_HP)
	settle(&run)
	rests := lying.pos
	place_hero(&run, 0, on_floor(&run, rests - {3, 0, 0}), {1, 0})
	play(&run, {0 = {move_x = 127}}, 1.5)
	testing.expectf(t, walker.pos.x > rests.x + 2, "the walker passes through: at %v", walker.pos)
	testing.expectf(t, abs(walker.pos.z - rests.z) < 0.05, "the walker kept its line: at %v", walker.pos)
	testing.expectf(t, dmath.length(lying.pos - rests) < 0.05, "the body was shoved to %v from %v", lying.pos, rests)
	second := sim.slot_data(run.simulation, 2)
	place_hero(&run, 2, on_floor(&run, rests - {2.5, 0, 0}))
	hurt(&run, 2, g.HERO_HP)
	settle(&run)
	toward := dmath.normalize(rests.xz - second.pos.xz) * 6
	physics.ragdoll_set_velocity(run.simulation.world.phys, &second.ragdoll, {toward.x, 0.5, toward.y})
	headless.run_pin(&run)
	settle(&run)
	shoved := dmath.length(lying.pos - rests)
	testing.expectf(t, shoved > 0.05, "a body thrown into it slid through it: it moved %v m", shoved)
	scenarios.expect_synced(t, &run)
}

// A Barbarian heaving an ally lying as a ragdoll stands its capsule up from it and heaves that (until milestone 6's
// last step heaves the ragdoll itself): the ragdoll goes, the capsule hangs on the hold, and let down it lies as that
// capsule, still down, until revived.
@(test)
a_heave_stands_the_capsule_up_from_its_ragdoll :: proc(t: ^testing.T) {
	run := ragdoll_run(2)
	defer headless.run_end(&run)
	phys := run.simulation.world.phys
	headless.run_command(&run, 0, g.Command_Dev_Set_Class{.Barbarian})
	ally := sim.slot_data(run.simulation, 1)
	start := [3]f32{6, 0, 0} // the great hall
	place_hero(&run, 1, start + {1.3, 0, 0})
	hurt(&run, 1, g.HERO_HP)
	settle(&run)
	place_hero(&run, 0, on_floor(&run, ally.pos - {1.3, 0, 0}), {1, 0})
	press(&run, 0, .Ability)
	testing.expect_value(t, ally.heave, g.Heave_Phase.Held)
	testing.expect(t, !g.ragdolled(ally), "the heave holds the capsule, its ragdoll gone")
	testing.expect(t, physics.body_is_enabled(phys, ally.body.body), "the capsule is back in the world")
	play(&run, {}, g.HEAVE_MAX_S + 0.5) // held unthrown: let down
	testing.expect_value(t, ally.heave, g.Heave_Phase.None)
	testing.expect_value(t, ally.action, g.Action.Down)
	testing.expect(t, !g.ragdolled(ally), "let down, it lies as its capsule")
	headless.run_command(&run, 0, g.Command_Dev_Revive{})
	testing.expect_value(t, ally.action, g.Action.None)
	scenarios.expect_synced(t, &run)
}
