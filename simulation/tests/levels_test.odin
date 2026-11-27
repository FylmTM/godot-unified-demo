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

// The crypt's new floors are the size the run's design gives them: the Ossuary (Floor 2) holds about 200 skeletons and
// the Deep Halls (Floor 3) about 240, from their walkable area as every floor's cap is (a_floors_cap_comes_from_its_area);
// every pack's skeletons stand on its floor (pack_places asserts it, this counts them); and the hub is the run's lobby:
// no grave (it has no director), a barrel to throw for each of its four spawns.
@(test)
the_run_floors_are_their_size :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1)
	defer headless.run_end(&run)
	floors := &run.simulation.world.floors
	CAPS :: [?]struct {
		id:        g.Level_Id,
		low, high: int,
	}{{.Floor_2, 180, 220}, {.Floor_3, 220, 260}}
	for want in CAPS {
		floor := &floors[want.id]
		testing.expectf(
			t,
			floor.minion_cap >= want.low && floor.minion_cap <= want.high,
			"%v holds %d skeletons (%v m² walkable), not %d to %d",
			want.id,
			floor.minion_cap,
			floor.area,
			want.low,
			want.high,
		)
		members := 0
		for pack in sim.slice(&floor.places.packs) do members += int(pack.count)
		testing.expectf(t, members > 0, "%v has no pack", want.id)
		testing.expect_value(t, len(sim.slice(&floor.pack_places)), members)
	}
	hub := &floors[.Hub].places
	testing.expect_value(t, len(sim.slice(&hub.graves)), 0)
	testing.expect_value(t, len(sim.slice(&hub.props)), g.PLAYERS)
}

// Every plate and brazier on every level works what it names, as world_create resolved it (link_plates,
// link_braziers): a plate a gate or spikes, and a brazier a gate on every floor with a hoard (the vault's, on the boss's
// floor, work none: a brazier there with a gate, or one on a crypt floor without, is a level mistake). The new floors'
// gates are wired as the design has them: the Ossuary's vault gate opens to its three braziers and stays open; the Deep
// Halls' vault gate to its two plates and two braziers, all four, and stays open; its held gate to either of the plates
// on its two sides, and only while one is pressed.
@(test)
every_plate_and_brazier_works_its_gate :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1)
	defer headless.run_end(&run)
	floors := &run.simulation.world.floors
	for &floor, id in floors {
		places := &floor.places
		for plate in sim.slice(&places.plates) {
			testing.expectf(t, plate.gate >= 0 || plate.trap >= 0, "%v's plate at %v works nothing", id, plate.pos)
		}
		for brazier in sim.slice(&places.braziers) {
			testing.expectf(
				t,
				(brazier.gate >= 0) == places.hoard.placed,
				"%v's brazier at %v works gate %d (a floor with a hoard lights its gates; the vault's none)",
				id,
				brazier.pos,
				brazier.gate,
			)
		}
	}
	expect_gate(t, &floors[.Floor_2], 0, need = 3, latch = true, plates = 0, braziers = 3)
	expect_gate(t, &floors[.Floor_3], 0, need = 4, latch = true, plates = 2, braziers = 2)
	expect_gate(t, &floors[.Floor_3], 1, need = 1, latch = false, plates = 2, braziers = 0)
}

// The floor's gate `index` needs `need` and latches as `latch` says, worked by `plates` plates and `braziers` braziers.
@(private = "file")
expect_gate :: proc(
	t: ^testing.T,
	floor: ^g.Floor,
	index: int,
	need: i32,
	latch: bool,
	plates, braziers: int,
	loc := #caller_location,
) {
	places := &floor.places
	gates := sim.slice(&places.gates)
	if !testing.expectf(t, index < len(gates), "no gate %d", index, loc = loc) do return
	gate := gates[index]
	testing.expect_value(t, gate.need, need, loc = loc)
	testing.expect_value(t, gate.latch, latch, loc = loc)
	working := [2]int{}
	for plate in sim.slice(&places.plates) do working[0] += int(plate.gate == i32(index))
	for brazier in sim.slice(&places.braziers) do working[1] += int(brazier.gate == i32(index))
	testing.expect_value(t, working, [2]int{plates, braziers}, loc = loc)
}

// Every grave on every level stands on its floor's walkable island, within GRAVE_ON_FLOOR of where its marker was put:
// world_create snaps a grave within SURGE_SPREAD, so one put on a wall's top or just past a floor's edge would load and
// raise its surges at the island's nearest point, not where its level shows it.
@(test)
every_grave_stands_on_its_floor :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1)
	defer headless.run_end(&run)
	for id in g.Level_Id {
		data, loaded := level.load(g.GAME.levels[int(id)].bytes)
		defer level.destroy(&data)
		if !testing.expectf(t, loaded, "%v's level doesn't load", id) do continue
		floor := &run.simulation.world.floors[id]
		for &marker in data.markers {
			if marker.kind != "grave" do continue
			_, on_floor := g.floor_spot(floor, marker.pos, GRAVE_ON_FLOOR)
			testing.expectf(t, on_floor, "%v's grave %s at %v is off its floor", id, marker.name, marker.pos)
		}
	}
}

// How near its floor's island a grave's marker stands (m): the navigation report's "on the mesh".
GRAVE_ON_FLOOR :: f32(0.75)
