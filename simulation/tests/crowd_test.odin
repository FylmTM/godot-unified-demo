// The crowd at scale: a floor's cap from its area, the held crowds of the Setup (director.odin, Crowd) and the arena in
// play, the director raising only into the table's free rows, and the standard scenarios and a pinned reference run
// with a crowd of hundreds fighting (unified's scenarios on a Setup: CROWD_SUITE, CROWD_REFERENCE), so rollback, late
// joins and every platform's floats are proven at the size the game plays. The rule tests run on sync-tested runs
// that end synced, as every rule test does.
package test_crypt_crew

import "core:fmt"
import "core:strings"
import "core:testing"
import "unified:dmath"
import "unified:headless"
import "unified:headless/scenarios"
import "unified:nav"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// The arena with a fighting crowd: the Setup the scale scenarios and the crowd's reference run play.
CROWD_FIGHT :: g.Setup {
	floor = .Arena,
	crowd = .Fight,
}

// The standard scenarios on the arena's fighting crowd: the floor's cap of minions in a fight, rolled back, re-joined
// and played by four clients. Short by default (each step re-simulates hundreds), full length under --long.
CROWD_SUITE := scenarios.Suite(g.Game) {
	game    = &g.GAME,
	players = g.PLAYERS,
	seed    = 42,
	ticks   = scenarios.LONG ? 1200 : 300,
	setup   = CROWD_FIGHT,
}

// The crowd's reference run (unified/src/headless/README.md, Reference runs): the arena's fighting crowd for 1200
// ticks, snapshotted midway; every platform must reproduce a separation pass over hundreds of neighbours bit for bit.
CROWD_REFERENCE :: scenarios.Reference {
	seed          = 7,
	players       = 4,
	ticks         = 1200,
	snapshot_tick = 600,
	setup         = "floor=arena,crowd=fight",
	checkpoints   = {0xa4229d296b3207e8, 0x10489c9976b6267a, 0x9a092cf657621104, 0xa52410705af8c44d},
	trace         = 0xf4e3b843a943da8a,
	snapshot      = 0x3ffd84f879f9932c,
	log           = 0xd9ccf76439998f20,
	compat        = 0x4eb571ac8d506523,
}

// What a chaser closes on a neighbour or a spawn in the tick a run seats its heroes.
SEATING_SLACK :: g.MINION_SPEED / g.TICK_HZ

@(test)
the_crowd_reference_run_reproduces :: proc(t: ^testing.T) {scenarios.reference_reproduces(t, &g.GAME, CROWD_REFERENCE)}
@(test)
a_crowd_rolls_back_every_tick :: proc(t: ^testing.T) {scenarios.rollback_every_tick(t, &CROWD_SUITE)}
@(test)
a_late_joiner_agrees_with_a_crowd :: proc(t: ^testing.T) {scenarios.late_join_agrees(
		t,
		&CROWD_SUITE,
		.Wan,
		CLIENTS - 1,
		scenarios.LONG ? 600 : 150,
	)}
@(test)
clients_agree_with_a_crowd_on_a_bad_network :: proc(t: ^testing.T) {scenarios.session_agrees(
		t,
		&CROWD_SUITE,
		CLIENTS,
		.Bad,
	)}

// The crowd suite's scripted run fights: minions fall and rise again in it, so its scenarios roll back over deaths
// and refills, not a crowd that only walks.
@(test)
the_crowd_suite_runs_cross_kills_and_rises :: proc(t: ^testing.T) {
	simulation := sim.create(&g.GAME, CROWD_SUITE.seed, CROWD_FIGHT)
	defer sim.destroy(simulation)
	commands: headless.Scripted_Commands(g.Game)
	defer headless.scripted_commands_destroy(&commands)
	rises := simulation.state.rises
	for tick in 1 ..= CROWD_SUITE.ticks {
		inputs := headless.scripted(&g.GAME, simulation, tick, CROWD_SUITE.players, &commands)
		sim.step(simulation, &inputs)
	}
	testing.expectf(t, simulation.state.kills > 0, "the %d-tick run felled none", CROWD_SUITE.ticks)
	testing.expectf(t, simulation.state.rises > rises, "the %d-tick run raised none", CROWD_SUITE.ticks)
}

// GAME.levels is in Level_Id's order: each level's file is named after its id.
@(test)
the_levels_are_in_level_id_order :: proc(t: ^testing.T) {
	testing.expect_value(t, len(g.GAME.levels), len(g.Level_Id))
	for id in g.Level_Id {
		name := strings.to_lower(fmt.tprint(id), context.temp_allocator)
		testing.expect_value(t, g.GAME.levels[int(id)].name, name)
	}
}

// A floor's cap is CROWD_DENSITY to its walkable square metre, at most MINION_CAP: Floor 1's rooms hold about a
// hundred, the arena the most any floor holds.
@(test)
a_floors_cap_comes_from_its_area :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1)
	defer headless.run_end(&run)
	floors := &run.simulation.world.floors
	first := &floors[.Floor_1]
	testing.expect_value(t, first.minion_cap, int(first.area * g.CROWD_DENSITY))
	testing.expectf(t, first.minion_cap > 80 && first.minion_cap < 140, "Floor 1 holds %d", first.minion_cap)
	arena := &floors[.Arena]
	testing.expectf(t, arena.area * g.CROWD_DENSITY >= g.MINION_CAP, "the arena's %v m²", arena.area)
	testing.expect_value(t, arena.minion_cap, g.MINION_CAP)
}

// island_area on a mesh built by hand: a 2 m by 3 m rectangle in two triangles, and apart from it a right triangle
// with legs of 4 m and 2 m, each its own island.
@(test)
island_area_sums_an_islands_polygons :: proc(t: ^testing.T) {
	vertices := [][3]f32{{0, 0, 0}, {2, 0, 0}, {2, 0, 3}, {0, 0, 3}, {10, 0, 0}, {14, 0, 0}, {10, 0, 2}}
	polygons := [][]u32{{0, 1, 2}, {0, 2, 3}, {4, 5, 6}}
	mesh, err := nav.build(vertices, polygons)
	defer nav.destroy(&mesh)
	testing.expect_value(t, err, nav.Build_Error.None)
	testing.expect_value(t, mesh.island_count, 2)
	testing.expect_value(t, g.island_area(&mesh, 0), 6)
	testing.expect_value(t, g.island_area(&mesh, 1), 4)
}

// A held crowd asleep starts at the floor's cap, each minion on the walkable floor, apart from the rest and out of
// sight of the hero spawns; with its heroes standing still nobody wakes.
@(test)
a_sleeping_crowd_stays_asleep :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Arena, crowd = .Idle}, seated = g.PLAYERS)
	defer headless.run_end(&run)
	floor := floor_of(&run)
	state := &run.simulation.state
	testing.expect_value(t, g.minions_alive(&state.minions), floor.minion_cap)
	expect_spread(t, state, floor, g.CROWD_IDLE_CLEAR, SEATING_SLACK)
	play(&run, {}, 2)
	expect_all_in(t, state, .Idle)
	scenarios.expect_synced(t, &run)
}

// A sleeping crowd's felled come back asleep at the graves, never chasing: it stays a sleeping crowd.
@(test)
a_sleeping_crowd_refills_with_sleepers :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Arena, crowd = .Idle}, seated = g.PLAYERS)
	defer headless.run_end(&run)
	state := &run.simulation.state
	headless.run_command(&run, 0, g.Command_Dev_Kill_Minions{})
	for g.minions_alive(&state.minions) < int(state.held) && state.clock.time < sim.Game_Time(30 * g.TICK_HZ) {
		headless.run_step(&run) // they rise a few a tick, at the graves out of sight
	}
	testing.expect_value(t, g.minions_alive(&state.minions), int(state.held))
	expect_all_in(t, state, .Idle)
	scenarios.expect_synced(t, &run)
}

// A held crowd chasing starts at the floor's cap, spread over the floor, every minion chasing; its heroes take no
// damage from it (a wipe would empty the floor), however long they stand in it.
@(test)
a_chasing_crowd_never_downs_its_heroes :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Arena, crowd = .Chase}, seated = g.PLAYERS)
	defer headless.run_end(&run)
	state := &run.simulation.state
	testing.expect_value(t, g.minions_alive(&state.minions), floor_of(&run).minion_cap)
	expect_spread(t, state, floor_of(&run), g.CROWD_CLEAR, SEATING_SLACK)
	play(&run, {}, 4)
	testing.expect_value(t, headless.run_events(&run, g.Event_Hero_Hurt), 0)
	for slot in 0 ..< g.PLAYERS do testing.expect_value(t, sim.slot_data(run.simulation, slot).hp, g.HERO_HP)
	scenarios.expect_synced(t, &run)
}

// A held crowd on Floor 1 replaces its packs: the floor's cap of chasers, none of them a pack's.
@(test)
a_crowd_replaces_the_packs :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Floor_1, crowd = .Chase}, seated = g.PLAYERS)
	defer headless.run_end(&run)
	state := &run.simulation.state
	testing.expect_value(t, g.minions_alive(&state.minions), floor_of(&run).minion_cap)
	expect_all_in(t, state, .Chase)
	scenarios.expect_synced(t, &run)
}

// A benchmark's count over a held crowd: bench_prepare places that many, not the floor's cap, spread over the floor
// and clear of the hero spawns.
@(test)
a_benchmark_holds_its_count :: proc(t: ^testing.T) {
	simulation := sim.create_bench(&g.GAME, 1, g.Setup{floor = .Arena, crowd = .Chase}, 200)
	defer sim.destroy(simulation)
	state := &simulation.state
	testing.expect_value(t, int(state.held), 200)
	testing.expect_value(t, g.minions_alive(&state.minions), 200)
	expect_spread(t, state, &simulation.world.floors[state.level.id], g.CROWD_CLEAR, 0)
}

// The script plays a crowd's part: under a held crowd it sends no command, ever (no dev spawn, kill or hurt, no pause:
// the population stays what was asked), where in play it sends them.
@(test)
the_script_sends_no_command_under_a_crowd :: proc(t: ^testing.T) {
	out := sim.Command_Out(g.Command) {
		cap = 16,
	}
	defer delete(out.list)
	for crowd in g.Crowd {
		state: g.State
		sent := 0
		for slot in 0 ..< g.PLAYERS {
			for tick in u32(0) ..< 4 * g.SCRIPT_HURT_EVERY {
				clear(&out.list)
				g.scripted_commands(1, slot, tick, &state, {crowd = crowd}, &out)
				sent += len(out.list)
			}
		}
		if crowd == .None {
			testing.expect(t, sent > 0, "in play the script sends commands")
		} else {
			testing.expectf(t, sent == 0, "under %v the script sent %d commands", crowd, sent)
		}
	}
}

// The arena in play (no crowd): no packs, the first surge rises at its graves along the rim, and its cap is the most
// any floor holds.
@(test)
the_arena_plays_with_surges :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Arena}, seated = g.PLAYERS)
	defer headless.run_end(&run)
	floor := floor_of(&run)
	state := &run.simulation.state
	testing.expect_value(t, int(state.minions.count), 0)
	testing.expect_value(t, floor.minion_cap, g.MINION_CAP)
	for headless.run_events(&run, g.Event_Surge) == 0 && state.clock.time < sim.Game_Time(2 * g.SURGE_FIRST_TICKS) {
		headless.run_step(&run)
	}
	testing.expect_value(t, headless.run_events(&run, g.Event_Surge), 1)
	minions := sim.iterate(&state.minions)
	for minion in sim.next(&minions) {
		nearest := max(f32)
		for &grave in sim.slice(&floor.places.graves) {
			nearest = dmath.min(nearest, dmath.length(grave.point.xz - minion.pos.xz))
		}
		testing.expectf(t, nearest <= g.SURGE_SPREAD + 0.1, "a minion rose %v m from the nearest grave", nearest)
	}
	scenarios.expect_synced(t, &run)
}

// Every minion of a crowd the arena holds killed at once: the dying keep their rows for DEATH_S. The refill raises a
// riser at each grave on its turn (the risers watch: each grave's RISE_GAP_TICKS apart, none on another minion's spot),
// never more than the table has rows free (never once per missing minion: the raises a full table would refuse, a nav
// query each, every tick until the dead are gone), the alive never pass the held count, and the crowd stands whole
// again (in about twelve seconds: each grave's spread holds a few risers at once, and they climb out for RISE_S).
@(test)
the_director_raises_only_into_free_rows :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Arena, crowd = .Chase}, seated = g.PLAYERS)
	defer headless.run_end(&run)
	state := &run.simulation.state
	held := int(state.held)
	headless.run_command(&run, 0, g.Command_Dev_Kill_Minions{})
	watch: Rise_Watch
	whole := false
	for _ in 0 ..< 14 * g.TICK_HZ {
		free_before := g.free_rows(&state.minions)
		headless.run_step(&run)
		raised, alive := watch_rises(t, &run, &watch), g.minions_alive(&state.minions)
		if raised > free_before || alive > held {
			testing.expectf(t, false, "%d raised into %d free rows, %d alive", raised, free_before, alive)
			break
		}
		if alive == held {
			whole = true
			break
		}
	}
	testing.expectf(t, whole, "the crowd isn't whole again: %d alive", g.minions_alive(&state.minions))
	scenarios.expect_synced(t, &run)
}

// A surge whose time comes while the table is full of the dying raises nothing and is no surge: no Event_Surge, no
// save point. The arena in play: its cap raised and killed (their rows held for DEATH_S), the last free rows filled,
// the surge clock run out meanwhile.
@(test)
no_surge_into_a_full_table :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Arena}, seated = g.PLAYERS)
	defer headless.run_end(&run)
	state := &run.simulation.state
	for state.clock.time < sim.Game_Time(g.SURGE_FIRST_TICKS - g.TICK_HZ) do headless.run_step(&run)
	for g.minions_alive(&state.minions) < g.MINION_CAP {
		headless.run_command(&run, 0, g.Command_Dev_Spawn_Minions{255})
	}
	headless.run_command(&run, 0, g.Command_Dev_Kill_Minions{})
	for g.free_rows(&state.minions) > 0 do headless.run_command(&run, 0, g.Command_Dev_Spawn_Minions{255})
	for state.clock.time < sim.Game_Time(g.SURGE_FIRST_TICKS + g.TICK_HZ / 4) {
		testing.expect_value(t, g.free_rows(&state.minions), 0) // the dying still hold their rows
		headless.run_step(&run)
	}
	testing.expect_value(t, headless.run_events(&run, g.Event_Surge), 0)
	testing.expect_value(t, state.surges, 0)
	scenarios.expect_synced(t, &run)
}

// Every live minion in `phase`, none of them a pack's.
@(private = "file")
expect_all_in :: proc(t: ^testing.T, state: ^g.State, phase: g.Minion_Phase, loc := #caller_location) {
	minions := sim.iterate(&state.minions)
	for minion in sim.next(&minions) {
		if minion.phase == .Dying do continue
		if minion.phase != phase || minion.pack != 0 {
			testing.expectf(
				t,
				false,
				"a minion %v, of pack %d, at %v",
				minion.phase,
				minion.pack,
				minion.pos,
				loc = loc,
			)
			return
		}
	}
}

// Every minion on the walkable floor's island, `clear` from every hero_spawn and at least SEPARATION from every other,
// less `slack` (what they may have moved since they were placed).
@(private = "file")
expect_spread :: proc(t: ^testing.T, state: ^g.State, floor: ^g.Floor, clear, slack: f32, loc := #caller_location) {
	minions := sim.iterate(&state.minions)
	for minion, handle in sim.next(&minions) {
		if nav.island_of(&floor.mesh, minion.poly) != floor.island {
			testing.expectf(t, false, "a minion off the floor at %v", minion.pos, loc = loc)
			return
		}
		for spawn in floor.places.hero_spawns {
			if apart := dmath.length(spawn.xz - minion.pos.xz); apart < clear - slack {
				testing.expectf(t, false, "a minion %v m from a hero_spawn", apart, loc = loc)
				return
			}
		}
		others := sim.iterate(&state.minions)
		for other, other_handle in sim.next(&others) {
			if other_handle.index <= handle.index do continue
			if apart := dmath.length(other.pos.xz - minion.pos.xz); apart < g.SEPARATION - 2 * slack {
				testing.expectf(t, false, "two minions %v m apart", apart, loc = loc)
				return
			}
		}
	}
}

// The strikes' walk (walk_within, what minions_within walks) finds exactly the live minions a walk of the whole table
// finds within a reach, at every reach a strike asks (each melee class's blow, a burst, a bolt's tick of flight, a
// thrown prop of each kind), around every minion of a dense crowd and around points between them.
@(test)
the_grid_finds_what_the_table_finds :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Arena, crowd = .Chase}, seated = g.PLAYERS)
	defer headless.run_end(&run)
	play(&run, {}, 3) // the crowd closes in on the heroes: dense, and at cell edges everywhere
	state := &run.simulation.state
	grid := new(g.Minion_Grid)
	defer free(grid)
	g.fill_grid(grid, floor_of(&run), &state.minions)
	reaches: [dynamic]f32
	defer delete(reaches)
	for spec in g.CLASS_SPECS do if spec.reach > 0 do append(&reaches, spec.reach + g.MINION_RADIUS)
	append(&reaches, g.BURST_RADIUS, g.BOLT_SPEED / g.TICK_HZ / 2 + g.MINION_RADIUS + g.BOLT_RADIUS)
	for spec in g.PROP_SPECS do append(&reaches, spec.footprint + g.MINION_RADIUS)
	checked := 0
	centres := sim.iterate(&state.minions)
	for centre_minion in sim.next(&centres) {
		for shift in ([][2]f32{{0, 0}, {0.37, -0.61}}) {
			centre := centre_minion.pos.xz + shift
			for reach in reaches {
				found: [g.MAX_MINIONS]bool
				walk := g.walk_within(grid, &state.minions, centre, reach)
				for _, handle in g.next_within(&walk) do found[handle.index] = true
				minions := sim.iterate(&state.minions)
				for minion, handle in sim.next(&minions) {
					want := minion.phase != .Dying && dmath.length_sq(minion.pos.xz - centre) <= reach * reach
					if found[handle.index] != want {
						testing.expectf(
							t,
							false,
							"minion %d at %v: grid %v, table %v",
							handle.index,
							minion.pos,
							found[handle.index],
							want,
						)
						return
					}
				}
				checked += 1
			}
		}
	}
	testing.expect(t, checked > 1000, "it checked a crowd")
}

// Separation at density: sixty sleepers dropped within 2 m of the arena's first hero spawn (five to the square metre)
// push apart until none is closer than SEPARATION less a hand's breadth within ten seconds, every one still on the
// floor. (Chasers round a hero are kept apart by the queue as well: a_crowd_rings_its_heroes.)
@(test)
separation_spreads_a_crush :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Arena, crowd = .Idle}) // no hero: nobody wakes them
	defer headless.run_end(&run)
	clear_minions(&run)
	run.simulation.state.held = 0 // these sixty only
	centre := floor_of(&run).places.hero_spawns[0] // the open middle, and no hero there: the run seats none
	for i in 0 ..< 60 {
		ring := dmath.sqrt(f32(i) / 60) * 2
		dir := dmath.angle_vec(f32(i) * 0.381966) // the golden angle, in turns: an even spiral
		place_minion(&run, centre + {dir.x, 0, dir.y} * ring, .Idle)
	}
	play(&run, {}, 10)
	floor := floor_of(&run)
	closest := max(f32)
	minions := sim.iterate(&run.simulation.state.minions)
	for minion, handle in sim.next(&minions) {
		testing.expect(t, nav.island_of(&floor.mesh, minion.poly) == floor.island, "a minion left the floor")
		others := sim.iterate(&run.simulation.state.minions)
		for other, other_handle in sim.next(&others) {
			if other_handle.index > handle.index do closest = dmath.min(closest, dmath.length(other.pos.xz - minion.pos.xz))
		}
	}
	testing.expectf(t, closest >= g.SEPARATION - 0.1, "two minions %v m apart", closest)
	scenarios.expect_synced(t, &run)
}

// A crowd of Floor 1's cap chasing heroes round its corners and doorways for 6 s stays on the floor: every tick every
// minion has floor under it (nav.locate finds a polygon there) on the walkable island, and no minion's step crosses a
// wall or low cover. nav.move's guarantee, whatever steers them (a_far_chaser_takes_the_short_way holds the slicing).
@(test)
a_crowd_stays_on_the_floor :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Floor_1, crowd = .Chase}, seated = g.PLAYERS)
	defer headless.run_end(&run)
	floor := floor_of(&run)
	state := &run.simulation.state
	blocking := physics.Filter {
		category = g.CAT_HERO,
		mask     = g.CAT_WALL | g.CAT_LOW,
	}
	was: [g.MAX_MINIONS]struct {
		handle: sim.Handle(g.Minion),
		pos:    [3]f32,
	}
	for _ in 0 ..< 6 * g.TICK_HZ {
		headless.run_step(&run)
		minions := sim.iterate(&state.minions)
		for minion, handle in sim.next(&minions) {
			if nav.locate(&floor.mesh, minion.pos, 0.1) == nav.NO_POLY ||
			   nav.island_of(&floor.mesh, minion.poly) != floor.island {
				testing.expectf(t, false, "a minion off the floor at %v", minion.pos)
				return
			}
			before := &was[handle.index]
			if before.handle == handle && before.pos != minion.pos {
				from := before.pos + {0, 0.5, 0}
				if _, hit := physics.world_cast_ray_closest(
					run.simulation.world.phys,
					from,
					minion.pos - before.pos,
					blocking,
				); hit {
					testing.expectf(t, false, "a minion stepped through a wall from %v to %v", before.pos, minion.pos)
					return
				}
			}
			before^ = {handle, minion.pos}
		}
	}
	scenarios.expect_synced(t, &run)
}

// How near two live minions stand at the closest, and how many stand within swinging reach of the hero they chase.
@(private = "file")
ring_of :: proc(state: ^g.State) -> (closest: f32, front: int) {
	closest = max(f32)
	minions := sim.iterate(&state.minions)
	for minion, handle in sim.next(&minions) {
		if minion.phase == .Dying do continue
		if minion.target != {} {
			hero := sim.player_data(&state.players, minion.target)
			front += int(dmath.length(hero.pos.xz - minion.pos.xz) <= g.MINION_RADIUS + g.HERO_RADIUS + g.MINION_REACH)
		}
		others := sim.iterate(&state.minions)
		for other, other_handle in sim.next(&others) {
			if other_handle.index <= handle.index || other.phase == .Dying do continue
			closest = dmath.min(closest, dmath.length(other.pos.xz - minion.pos.xz))
		}
	}
	return
}

// RING_APART: how near the queue lets two minions stand round their heroes (SEPARATION less a hand's breadth or two).
RING_APART :: g.SEPARATION - 0.2

// The queue holds rings: the arena's crowd chasing four heroes who stand still, 8 m apart, keeps apart where it gathers
// round them (no two live minions closer than RING_APART over the last two of twenty seconds, where without the queue
// they pressed to within a centimetre), and it doesn't stall there: its front rows stand within swinging reach, at
// least two a hero. The heroes then walk a loop through it (their capsules shove minions aside, one way: they pass
// closer meanwhile) and stand again: fourteen seconds on, the rings hold again. (Heroes standing within a minion's
// width of each other make pockets their one-way push wedges minions into: the rings are held round heroes apart.)
@(test)
a_crowd_rings_its_heroes :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Arena, crowd = .Chase}, seated = g.PLAYERS)
	defer headless.run_end(&run)
	state := &run.simulation.state
	centre := floor_of(&run).places.hero_spawns[0]
	for slot in 0 ..< g.PLAYERS do place_hero(&run, slot, centre + {f32(slot % 2) * 8 - 4, 0, f32(slot / 2) * 8 - 4})
	play(&run, {}, 18)
	closest := max(f32)
	front := 0
	for _ in 0 ..< 2 * g.TICK_HZ {
		headless.run_step(&run)
		c, f := ring_of(state)
		closest, front = dmath.min(closest, c), f
	}
	testing.expectf(t, closest >= RING_APART, "standing: two minions %v m apart", closest)
	testing.expectf(t, front >= 2 * g.PLAYERS, "standing: only %d in reach of the heroes", front)
	for leg in 0 ..< 4 {
		way: [g.PLAYERS]g.Input
		dir := dmath.DIR8[leg * 2]
		for &input in way do input.move_x, input.move_z = dmath.axis_i8(dir.x), dmath.axis_i8(dir.y)
		play(&run, way, 2)
	}
	play(&run, {}, 14)
	closest = max(f32)
	for _ in 0 ..< 2 * g.TICK_HZ {
		headless.run_step(&run)
		c, _ := ring_of(state)
		closest = dmath.min(closest, c)
	}
	testing.expectf(t, closest >= RING_APART, "after a walk: two minions %v m apart", closest)
	scenarios.expect_synced(t, &run)
}

// A hero that takes no harm (a test's: it stands among a crowd for seconds).
@(private = "file")
sturdy :: proc(run: ^headless.Run(g.Game), slots: int) {
	for slot in 0 ..< slots do sim.slot_data(run.simulation, slot).hp = max(i16)
	headless.run_pin(run)
}

// A column of eight chasers behind one another on the hero's line fans out round it: five of them stand within
// swinging reach within five seconds (the queue's sideways step: the ones behind don't wait in line).
@(test)
a_column_fans_out_round_its_hero :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Arena}, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	sturdy(&run, 1)
	state := &run.simulation.state
	hero := sim.slot_data(run.simulation, 0).pos
	for k in 0 ..< 8 do place_minion(&run, hero + {0, 0, -4 - f32(k)}, .Chase, {0, 1})
	front := 0
	for _ in 0 ..< 5 * g.TICK_HZ {
		headless.run_step(&run)
		if _, front = ring_of(state); front >= 5 do break
	}
	testing.expectf(t, front >= 5, "only %d of the column in reach", front)
	scenarios.expect_synced(t, &run)
}

// A sleeper standing on a chaser's line to its hero, out of the hero's sight, holds it up a moment at most: it steps
// round it (no waiting for one in no queue) and swings within a second of a clear walk's time.
@(test)
a_chaser_passes_a_sleeper :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, g.Setup{floor = .Arena}, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	sturdy(&run, 1)
	hero := sim.slot_data(run.simulation, 0).pos
	place_minion(&run, hero + {12, 0, 0}, .Idle) // out of sight: AGGRO_RADIUS is 9
	chaser := sim.get(&run.simulation.state.minions, place_minion(&run, hero + {15, 0, 0}, .Chase, {-1, 0}))
	clear_walk := (15 - (g.MINION_RADIUS + g.HERO_RADIUS + g.MINION_REACH)) / g.MINION_SPEED
	ticks := 0
	for chaser.phase != .Attack && ticks < int((clear_walk + 3) * g.TICK_HZ) {
		headless.run_step(&run)
		ticks += 1
	}
	testing.expectf(t, f32(ticks) <= (clear_walk + 1) * g.TICK_HZ, "it swung after %d ticks", ticks)
	scenarios.expect_synced(t, &run)
}

// Forty chasers funnel from Floor 1's east corridor through the doorway to a hero standing at its spawn: the doorway's
// half of a ring stands within ten seconds (five in reach), none of the ring (within 4 m of the hero) closer than
// RING_APART. The far half stays empty: the second row can't pass the front one round to it (review.md). The rest
// queue in the doorway and the corridor, its walls holding some a little closer.
@(test)
a_funnel_rings_its_hero :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = 1)
	defer headless.run_end(&run)
	clear_minions(&run)
	sturdy(&run, 1)
	state := &run.simulation.state
	placed := 0
	for i := 0; placed < 40 && i < 400; i += 1 {
		at := [3]f32{-2, 0, -2} + [3]f32{f32(i % 7) - 3, 0, f32(i / 7 % 7) - 3}
		if spot, on_floor := g.floor_spot(floor_of(&run), at, 0.2); on_floor {
			g.spawn_minion(state, spot.point, spot.poly, {-1, 0}, .Chase, state.clock.time)
			placed += 1
		}
	}
	headless.run_pin(&run)
	testing.expect_value(t, placed, 40)
	front, seconds := 0, 0
	for seconds = 0; seconds < 10 && front < 5; seconds += 1 {
		play(&run, {}, 1)
		sturdy(&run, 1)
		_, front = ring_of(state)
	}
	testing.expectf(t, front >= 5, "only %d in reach after %d s", front, seconds)
	play(&run, {}, 4) // settled
	hero := sim.slot_data(run.simulation, 0).pos
	closest := max(f32)
	for _ in 0 ..< g.TICK_HZ {
		headless.run_step(&run)
		minions := sim.iterate(&state.minions)
		for minion, handle in sim.next(&minions) {
			if dmath.length(minion.pos.xz - hero.xz) >= 4 do continue
			others := sim.iterate(&state.minions)
			for other, other_handle in sim.next(&others) {
				if other_handle.index <= handle.index || dmath.length(other.pos.xz - hero.xz) >= 4 do continue
				closest = dmath.min(closest, dmath.length(other.pos.xz - minion.pos.xz))
			}
		}
	}
	testing.expectf(t, closest >= RING_APART, "two of the ring %v m apart", closest)
	scenarios.expect_synced(t, &run)
}

// Floor 1's first surge reaches four heroes standing at their spawns: most of its minions (the packs' sleepers on
// the way or not) stand within 4 m of their hero within five seconds of climbing out, every one within ten.
@(test)
a_surge_reaches_its_heroes :: proc(t: ^testing.T) {
	run := headless.run_begin(&g.GAME, 1, seated = g.PLAYERS)
	defer headless.run_end(&run)
	sturdy(&run, g.PLAYERS)
	state := &run.simulation.state
	until_the_first_surge(&run)
	for state.rising > 0 do headless.run_step(&run)
	out := state.clock.time + sim.Game_Time(g.RISE_TICKS) // the last of them climbs out
	near := [2]int{}
	surge := 0
	for state.clock.time < out + sim.Game_Time(10 * g.TICK_HZ) {
		headless.run_step(&run)
		sturdy(&run, g.PLAYERS)
		if state.clock.time != out + sim.Game_Time(5 * g.TICK_HZ) &&
		   state.clock.time != out + sim.Game_Time(10 * g.TICK_HZ) {
			continue
		}
		within, all := 0, 0
		minions := sim.iterate(&state.minions)
		for minion in sim.next(&minions) {
			if minion.pack != 0 || minion.phase == .Dying do continue
			all += 1
			if minion.target == {} do continue
			within += int(dmath.length(sim.player_data(&state.players, minion.target).pos.xz - minion.pos.xz) < 4)
		}
		near[0 if state.clock.time == out + sim.Game_Time(5 * g.TICK_HZ) else 1], surge = within, all
	}
	testing.expectf(t, near[0] * 2 > surge, "%d of %d within 4 m in 5 s", near[0], surge)
	testing.expectf(t, near[1] == surge, "%d of %d within 4 m in 10 s", near[1], surge)
	scenarios.expect_synced(t, &run)
}
