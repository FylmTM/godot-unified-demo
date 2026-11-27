// The run's levels (docs/plan.md, milestone 7: the hub, Floor 2, Floor 3 and the vault): each is laid on the kit's grid
// (game/tools/lay_floor.gd), baked with its navigation (uni bake --nav), and loads as a session's floor.
package test_crypt_crew

import "core:testing"
import "unified:headless"
import "unified:level"
import "unified:nav"
import "unified:sim"

import g "../crypt_crew"

// The levels the run adds, beside Floor 1.
RUN_LEVELS :: [?]g.Level_Id{.Hub, .Floor_2, .Floor_3, .Vault}

// Each run level's file holds a navigation mesh that walks in one piece (one island: no wall or gap cuts its floor in
// two, and no wall top bakes a ledge), and a session started on it enters it with every present hero on its floor. The
// files are checked before any session starts: every session's World builds every level, and asserts on one unbaked.
@(test)
each_run_level_bakes_one_island_and_loads :: proc(t: ^testing.T) {
	baked := true
	for id in RUN_LEVELS {
		data, loaded := level.load(g.GAME.levels[int(id)].bytes)
		defer level.destroy(&data)
		mesh, err := nav.build(data.nav_vertices, data.nav_polygons)
		defer nav.destroy(&mesh)
		walks := loaded && len(data.nav_polygons) > 0 && err == .None && mesh.island_count == 1
		testing.expectf(
			t,
			walks,
			"%v's navigation is %d islands of %d polygons (%v): bake it, uni bake --nav",
			id,
			mesh.island_count,
			len(data.nav_polygons),
			err,
		)
		baked &&= walks
	}
	if !baked do return
	for id in RUN_LEVELS {
		run := headless.run_begin(&g.GAME, 1, g.Setup{floor = id}, 8, g.PLAYERS)
		defer headless.run_end(&run)
		play(&run, {}, 0.5)
		testing.expect_value(t, run.simulation.state.level.id, id)
		heroes := sim.iterate_present(&run.simulation.state.players)
		for hero in sim.next(&heroes) {
			_, on_floor := g.floor_spot(floor_of(&run), hero.pos, g.HERO_NAV_REACH)
			testing.expectf(t, on_floor, "%v: a hero at %v is off its floor", id, hero.pos)
		}
	}
}

// The run's markers are read into each floor's Places, though no rule uses them yet: the hub's lift goes without a
// hoard (Floor 1's waits for one), its two shrines set one setting each, and the vault holds a boss and braziers that
// work no gate.
@(test)
the_run_markers_are_read :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1)
	defer headless.run_end(&run)
	floors := &run.simulation.world.floors
	hub := &floors[.Hub].places
	testing.expect(t, hub.lift.placed && !hub.lift.hoard, "the hub's lift goes without a hoard")
	testing.expect(t, floors[.Floor_1].places.lift.hoard, "Floor 1's lift waits for its hoard")
	for setting in g.Shrine_Setting do testing.expectf(t, hub.shrines[setting].placed, "the hub has no %v shrine", setting)
	vault := &floors[.Vault].places
	testing.expect(t, vault.boss.placed, "the vault holds the boss")
	testing.expect_value(t, vault.braziers.count, 4)
	for brazier in sim.slice(&vault.braziers) do testing.expect_value(t, brazier.gate, -1)
}
