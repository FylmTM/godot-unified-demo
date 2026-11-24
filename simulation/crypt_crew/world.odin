// The World, everything outside the state block: the Box3D world (its rollback state is the Extra), Floor 1's
// navigation mesh with its memo of fields, the places the sim reads from the floor's markers (and the packs' sleeping
// places laid out from them), the heroes' controller tuning, and per-tick scratch. It holds only what world_create
// builds, what physics rolls back and scratch each pass rebuilds from the block, so a rollback, a late join or a replay
// finds it as every other peer does (unified/src/sim/README.md, World). `init` enters the floor.
package crypt_crew

import "unified:dmath"
import "unified:level"
import "unified:nav"
import "unified:physics"
import "unified:sim"

// Shape categories (filter bits): every query, contact and sensor reports the category of the shape it names, and a
// body's tag says whose it is (a hero's sim.player_key). The level's are the kit parts' `unified_category`
// (docs/ART.md, Kit parts); 32 is kept for the elites.
CAT_FLOOR :: u64(1 << 0)
CAT_WALL :: u64(1 << 1) // blocks walking, sight and shots
CAT_LOW :: u64(1 << 2) // low cover: blocks walking only, shots fly over it
CAT_HERO :: u64(1 << 3)
CAT_PROP :: u64(1 << 4)

// The game's levels, in GAME.levels' order (the State's `level` says which is active).
Level_Id :: enum u8 {
	Floor_1,
}

// What a prop marker places (game/levels/markers/prop.gd's `kind`, by name).
Prop_Kind :: enum u8 {
	Barrel,
	Crate,
	Heavy_Crate,
}

// A pack of skeletons asleep where the floor begins (a `pack` marker).
Pack_Def :: struct {
	pos:    [3]f32,
	count:  i32, // how many skeletons it holds
	marker: i32, // its marker's index: what its minions' places are rolled by (spawn_packs)
}

// A place on the walkable floor: a point of the navigation mesh and its polygon (nav.NO_POLY: none).
Nav_Point :: struct {
	point: [3]f32,
	poly:  nav.Poly,
}

// A prop's place (a `prop` marker).
Prop_Def :: struct {
	pos:  [3]f32,
	rot:  [4]f32,
	kind: Prop_Kind,
}

// What the sim reads from the floor's markers, each list in the level's marker order.
Places :: struct {
	hero_spawns: [PLAYERS][3]f32, // by slot: where a hero appears with nobody up to arrive beside
	graves:      sim.List(Nav_Point, MAX_GRAVES), // where surges rise, on the walkable floor
	packs:       sim.List(Pack_Def, MAX_PACKS),
	props:       sim.List(Prop_Def, MAX_PROPS),
}

// The world outside the block.
World :: struct {
	phys:           ^physics.World,
	mesh:           nav.Mesh, // the floor's baked navigation: where skeletons walk
	fields:         nav.Fields, // the mesh's distance fields, memoized by goal (a pure function of the mesh and the goal)
	places:         Places,
	pack_places:    sim.List(Pack_Place, MAX_PACK_MINIONS), // every pack's sleeping minions' places (pack_places)
	hero_defs:      [Class]physics.Character_Def, // each class's controller (its own max_speed); Any's is never used
	barrel_hull:    ^physics.Hull_Data, // the barrel's cylinder (Box3D copies it into each body's shape)
	barrel_density: f32, // what gives the barrel's hull its PROP_SPECS mass
	// The mesh island the hero spawns stand on: the walkable floor (wall and furniture tops bake islands of their own).
	floor_island:   i32,
	grid_origin:    [2]f32, // the minion grid's corner, its columns and rows: laid over the mesh's extent
	grid_columns:   int,
	grid_rows:      int,
	contacts:       [dynamic]physics.Contact_Event, // scratch: the step's contact events (prop_impacts)
	grid:           Minion_Grid, // scratch: the live minions by cell, rebuilt by move_minions
	hero_spots:     [PLAYERS]Nav_Point, // scratch: each slot's hero up on the mesh (locate_heroes), by slot
}

// Builds the world from the levels (unified/src/level/README.md): Floor 1's static geometry, its navigation mesh and
// its places. A marker property's default lives in its marker script (game/levels/markers/), which the export writes
// whole, so the sim reads the properties without defaults of its own and asserts what its rules need.
world_create :: proc(seed: u64, levels: []sim.Level_File, _: sim.No_Setup) -> ^World {
	world := new(World)
	problem: string
	// a shape the level leaves uncategorized blocks everything, as a wall does
	world.phys, problem = physics.create_with_levels(
		{tick_hz = TICK_HZ, hit_event_threshold = IMPACT_SPEED},
		levels,
		CAT_WALL,
	)
	assert(problem == "", problem) // no level, or a shape Box3D refuses
	floor := physics.level_data(world.phys, Level_Id.Floor_1)
	err: nav.Build_Error
	world.mesh, err = nav.build(floor.nav_vertices, floor.nav_polygons)
	assert(err == .None, "crypt_crew: Floor 1's navigation mesh doesn't build (bake it: uni bake --nav)")
	world.fields = nav.fields_make(&world.mesh, MAX_FIELDS)
	lay_grid(world)
	read_places(&world.places, floor)
	spawn_poly, _ := nav.nearest(&world.mesh, world.places.hero_spawns[0], HERO_NAV_REACH)
	assert(spawn_poly != nav.NO_POLY, "crypt_crew: slot 0's hero_spawn is off the navigation mesh")
	world.floor_island = nav.island_of(&world.mesh, spawn_poly)
	for spawn in world.places.hero_spawns {
		_, on_floor := floor_spot(world, spawn, HERO_NAV_REACH)
		assert(on_floor, "crypt_crew: a hero_spawn is off the walkable floor")
	}
	for &grave in sim.slice(&world.places.graves) {
		on_floor: bool
		grave, on_floor = floor_spot(world, grave.point, SURGE_SPREAD)
		assert(on_floor, "crypt_crew: a grave is off the walkable floor")
	}
	pack_places(world, seed)
	for class in Class {
		def := physics.CHARACTER_DEFAULT
		def.radius = HERO_RADIUS
		def.half_height = HERO_HALF_HEIGHT
		def.pogo_rest = HERO_POGO_REST
		def.density = HERO_DENSITY
		def.max_ground_force = HERO_GROUND_FORCE
		def.accelerate = HERO_ACCELERATE
		def.category = CAT_HERO
		def.max_speed = CLASS_SPECS[class].max_speed
		world.hero_defs[class] = def
	}
	barrel := &PROP_SPECS[.Barrel]
	height := 2 * barrel.half.y
	world.barrel_hull = physics.create_cylinder(height, barrel.half.x, -barrel.half.y, PROP_CYLINDER_SIDES)
	world.barrel_density = barrel.mass / physics.compute_hull_mass(world.barrel_hull, 1).mass
	return world
}

// The minion grid's cells, MINION_GRID_CELL square, laid over the mesh's extent on the floor plan with a cell to spare
// on every side (a minion never leaves the mesh, so none falls off the grid).
@(private = "file")
lay_grid :: proc(world: ^World) {
	low, high := [2]f32{max(f32), max(f32)}, [2]f32{-max(f32), -max(f32)}
	for vertex in world.mesh.vertices {
		low = {dmath.min(low.x, vertex.x), dmath.min(low.y, vertex.z)}
		high = {dmath.max(high.x, vertex.x), dmath.max(high.y, vertex.z)}
	}
	world.grid_origin = low - MINION_GRID_CELL
	cells := (high - low) / MINION_GRID_CELL + 3
	world.grid_columns = int(dmath.to_i32_clamped(cells.x, 1, MINION_GRID_CELLS))
	world.grid_rows = int(dmath.to_i32_clamped(cells.y, 1, MINION_GRID_CELLS))
	assert(
		world.grid_columns * world.grid_rows <= MINION_GRID_CELLS,
		"crypt_crew: a level larger than the minion grid",
	)
}

// The places a floor's markers name.
@(private = "file")
read_places :: proc(places: ^Places, floor: ^level.Level) {
	spawned: [PLAYERS]bool
	for &marker in floor.markers {
		switch marker.kind {
		case "hero_spawn":
			slot := level.prop_int(&marker, "slot")
			assert(
				slot >= 0 && slot < PLAYERS && !spawned[slot],
				"crypt_crew: a hero_spawn's slot is out of range or taken",
			)
			spawned[slot] = true
			places.hero_spawns[slot] = marker.pos
		case "grave":
			added := sim.append(&places.graves, Nav_Point{marker.pos, nav.NO_POLY}) // snapped in world_create
			assert(added, "crypt_crew: more graves than MAX_GRAVES")
		case "pack":
			pack := Pack_Def{marker.pos, i32(level.prop_int(&marker, "count")), i32(marker.index)}
			assert(pack.count > 0, "crypt_crew: a pack holds no skeleton")
			added := sim.append(&places.packs, pack)
			assert(added, "crypt_crew: more packs than MAX_PACKS")
		case "prop":
			kind, known := level.prop_enum(&marker, "kind", Prop_Kind.Barrel) // prop.gd's export_enum: the names, lowercased
			assert(known, "crypt_crew: a prop's kind is no Prop_Kind")
			added := sim.append(&places.props, Prop_Def{pos = marker.pos, rot = marker.rot, kind = kind})
			assert(added, "crypt_crew: more props than MAX_PROPS")
		case:
			assert(false, "crypt_crew: a marker of a kind the sim doesn't know (game/levels/markers/)")
		}
	}
	for has_spawn in spawned do assert(has_spawn, "crypt_crew: a floor needs a hero_spawn per slot")
	assert(places.graves.count > 0, "crypt_crew: a floor needs a grave for its surges to rise from")
}

// The walkable floor's place nearest `near` within `reach` (on the floor's island: never a wall's top); false for none.
floor_spot :: proc(world: ^World, near: [3]f32, reach: f32) -> (spot: Nav_Point, ok: bool) {
	spot.poly, spot.point = nav.nearest(&world.mesh, near, reach)
	return spot, spot.poly != nav.NO_POLY && nav.island_of(&world.mesh, spot.poly) == world.floor_island
}

// Frees what world_create made: the physics world (the levels with it), the barrel's hull, the navigation, the scratch
// and the World itself.
world_destroy :: proc(world: ^World) {
	physics.destroy(world.phys)
	physics.destroy_hull(world.barrel_hull)
	delete(world.contacts)
	nav.fields_destroy(&world.fields)
	nav.destroy(&world.mesh)
	free(world)
}

// The block's view of the physics world: every body rolls back with the state.
extra :: proc(world: ^World) -> sim.Extra {
	return physics.extra(world.phys, State)
}

// The tick-0 state: the party starts on Floor 1; heroes arrive as their players do (presence.odin).
init :: proc(t: ^Tick) {
	enter_level(t, .Floor_1)
}

// Takes the party to level `to` (init, the wipe's floor restart; the next floor later): every hero lets go and its body
// goes, the props and the minions go, the static geometry is swapped (physics.level_change), then the new level's
// props are made in marker order, its packs put to sleep, its surge clock started, and every present hero gets a body
// at its slot's spawn. What the block keeps across it (the heroes' classes, the clock, the session's counts) stays.
enter_level :: proc(t: ^Tick, to: Level_Id) {
	leaving := sim.iterate_present(t)
	for hero, player in sim.next(&leaving) {
		release_hold(t, player)
		destroy_hero_body(t.world.phys, hero)
	}
	despawn_props(t)
	sim.despawn_all(&t.state.minions)
	physics.level_change(t, t.world.phys, to)
	spawn_props(t)
	spawn_packs(t)
	sim.timer_start_ticks(t, &t.state.surge, SURGE_FIRST_TICKS)
	entering := sim.iterate_present(t)
	for _, player in sim.next(&entering) {
		spawn_hero(t, player, t.world.places.hero_spawns[sim.player_slot(t, player)], false)
	}
}

// The whole party is down: the floor starts over (enter_level, the same floor), every hero at its hero_spawn.
restart_floor :: proc(t: ^Tick) {
	enter_level(t, t.state.level.id)
	sim.emit(t, Event_Floor_Restarted{})
}
