// The World, everything outside the state block: the Box3D world (its rollback state is the Extra), each level's floor
// (its navigation mesh with its memo of fields, the places the sim reads from its markers and the packs' sleeping
// places laid out from them, its minion cap and grid), the heroes' controller tuning, and per-tick scratch. It holds
// only what world_create builds, what physics rolls back and scratch each pass rebuilds from the block, so a rollback,
// a late join or a replay finds it as every other peer does (unified/src/sim/README.md, World). Every level's floor is
// built up front, so the active level (state) picks one by its id and a level change builds nothing. `init` enters the
// Setup's floor.
package crypt_crew

import "unified:dmath"
import "unified:level"
import "unified:nav"
import "unified:physics"
import "unified:sim"

// Shape categories (filter bits): every query, contact and sensor reports the category of the shape it names, and a
// body's tag says whose it is (a hero's sim.player_key). The level's are the kit parts' `unified_category`
// (docs/ART.md, Kit parts).
CAT_FLOOR :: u64(1 << 0)
CAT_WALL :: u64(1 << 1) // blocks walking, sight and shots
CAT_LOW :: u64(1 << 2) // low cover: blocks walking only, shots fly over it
CAT_HERO :: u64(1 << 3)
CAT_PROP :: u64(1 << 4)
CAT_ELITE :: u64(1 << 5) // an elite's capsule (elites.odin)
CAT_RAGDOLL :: u64(1 << 7) // a downed hero's ragdoll's bones (ragdolls.odin)

// The game's levels, in GAME.levels' order (the State's `level` says which is active).
Level_Id :: enum u8 {
	Floor_1,
	Arena, // one great hall where a crowd of hundreds fits: the crowd's benchmark rows and scale tests play it
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
	elites:      sim.List(Elite_Def, MAX_ELITE_MARKERS), // asleep at their markers on entering (elites.odin)
}

// A level's floor as the sim reads it, built once in world_create.
Floor :: struct {
	mesh:         nav.Mesh, // its baked navigation: where skeletons walk
	fields:       nav.Fields, // the mesh's distance fields, memoized by goal (a pure function of the mesh and the goal)
	places:       Places,
	pack_places:  sim.List(Pack_Place, MAX_PACK_MINIONS), // every pack's sleeping minions' places (pack_places)
	// The mesh island the hero spawns stand on: the walkable floor (wall and furniture tops bake islands of their own).
	island:       i32,
	area:         f32, // the walkable floor's area seen from above, square metres
	// The island's polygons, and the area of the island up to and including each (floor_point draws by it).
	walk_polys:   []nav.Poly,
	walk_area_to: []f32,
	// The most minions alive the director raises here: CROWD_DENSITY to the square metre of walkable floor, at most
	// MINION_CAP, so a small floor never holds a crush and a great hall holds a crowd.
	minion_cap:   int,
	grid_origin:  [2]f32, // the minion grid's corner, its columns and rows: laid over the mesh's extent
	grid_columns: int,
	grid_rows:    int,
	// ---- ragdolls (ragdolls.odin)
	lowest:       f32, // the navigation mesh's lowest point: a ragdoll RAGDOLL_KILL_DEPTH below it has left the level
}

// The world outside the block.
World :: struct {
	phys:           ^physics.World,
	floors:         [Level_Id]Floor, // each level's (floor_of: the active one's)
	hero_defs:      [Class]physics.Character_Def, // each class's controller (its own max_speed); Any's is never used
	elite_defs:     [Elite_Kind]physics.Character_Def, // each elite kind's controller (elite_def)
	barrel_hull:    ^physics.Hull_Data, // the barrel's cylinder (Box3D copies it into each body's shape)
	barrel_density: f32, // what gives the barrel's hull its PROP_SPECS mass
	contacts:       [dynamic]physics.Contact_Event, // scratch: the step's contact events (prop_impacts)
	shapes:         [dynamic]physics.Shape_Ref, // scratch: a body's shapes (pass_heroes)
	grid:           Minion_Grid, // scratch: the live minions by cell, rebuilt by move_minions and before the strikes
	hero_spots:     [PLAYERS]Nav_Point, // scratch: each slot's hero up on the mesh (locate_heroes), by slot
	starts:         [MAX_MINIONS][2]f32, // scratch: each minion's place on the floor plan when the moves began, by row
	queues:         [MAX_MINIONS]Queue_Place, // scratch: each minion's place in its hero's queue then, by row
	// scratch: the grid's cells an obstacle's reach touches this tick (set and cleared by move_minions)
	in_way:         [MINION_GRID_CELLS]bool,
	// scratch: the grid holds the minions where the physics step left them (strike_grid; cleared as the strikes begin)
	strike_grid:    bool,
}

// Builds the world from the levels (unified/src/level/README.md): their static geometry, and each level's floor
// (build_floor). A marker property's default lives in its marker script (game/levels/markers/), which the export
// writes whole, so the sim reads the properties without defaults of its own and asserts what its rules need.
world_create :: proc(seed: u64, levels: []sim.Level_File, _: Setup) -> ^World {
	world := new(World)
	problem: string
	// a shape the level leaves uncategorized blocks everything, as a wall does
	world.phys, problem = physics.create_with_levels(
		{tick_hz = TICK_HZ, hit_event_threshold = IMPACT_SPEED},
		levels,
		CAT_WALL,
	)
	assert(problem == "", problem) // no level, or a shape Box3D refuses
	for &floor, id in world.floors do build_floor(&floor, physics.level_data(world.phys, id), seed)
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
	for kind in Elite_Kind do world.elite_defs[kind] = elite_def(kind)
	barrel := &PROP_SPECS[.Barrel]
	height := 2 * barrel.half.y
	world.barrel_hull = physics.create_cylinder(height, barrel.half.x, -barrel.half.y, PROP_CYLINDER_SIDES)
	world.barrel_density = barrel.mass / physics.compute_hull_mass(world.barrel_hull, 1).mass
	intern_ragdoll_names(world.phys)
	return world
}

// The active level's floor.
floor_of :: proc(t: ^Tick) -> ^Floor {
	return &t.world.floors[t.state.level.id]
}

// A level's floor from its baked data: the navigation mesh, its places, the walkable island (the one slot 0's
// hero_spawn stands on: every spawn and grave must too), its area and minion cap, its grid and its packs' places.
@(private = "file")
build_floor :: proc(floor: ^Floor, data: ^level.Level, seed: u64) {
	err: nav.Build_Error
	floor.mesh, err = nav.build(data.nav_vertices, data.nav_polygons)
	assert(err == .None, "crypt_crew: a level's navigation mesh doesn't build (bake it: uni bake --nav)")
	floor.fields = nav.fields_make(&floor.mesh, MAX_FIELDS)
	lay_grid(floor)
	floor.lowest = max(f32)
	for vertex in floor.mesh.vertices do floor.lowest = dmath.min(floor.lowest, vertex.y)
	read_places(&floor.places, data)
	spawn_poly, _ := nav.nearest(&floor.mesh, floor.places.hero_spawns[0], HERO_NAV_REACH)
	assert(spawn_poly != nav.NO_POLY, "crypt_crew: slot 0's hero_spawn is off the navigation mesh")
	floor.island = nav.island_of(&floor.mesh, spawn_poly)
	floor.area = island_area(&floor.mesh, floor.island)
	index_walkable(floor)
	floor.minion_cap = int(dmath.to_i32_clamped(floor.area * CROWD_DENSITY, 0, MINION_CAP))
	for spawn in floor.places.hero_spawns {
		_, on_floor := floor_spot(floor, spawn, HERO_NAV_REACH)
		assert(on_floor, "crypt_crew: a hero_spawn is off the walkable floor")
	}
	for &grave in sim.slice(&floor.places.graves) {
		on_floor: bool
		grave, on_floor = floor_spot(floor, grave.point, SURGE_SPREAD)
		assert(on_floor, "crypt_crew: a grave is off the walkable floor")
	}
	for &elite in sim.slice(&floor.places.elites) {
		spot, on_floor := floor_spot(floor, elite.pos, HERO_NAV_REACH)
		assert(on_floor, "crypt_crew: an elite marker is off the walkable floor")
		elite.pos = spot.point
	}
	pack_places(floor, seed)
}

// The area of a mesh island seen from above (square metres): the sum of its polygons' (polygon_area), in polygon order,
// so every platform adds the same f32s in the same order.
island_area :: proc(mesh: ^nav.Mesh, island: i32) -> f32 {
	area: f32
	for p in 0 ..< nav.poly_count(mesh) {
		if mesh.islands[p] == island do area += polygon_area(mesh, nav.Poly(p))
	}
	return area
}

// A polygon's area seen from above (square metres): the shoelace formula over its corners.
@(private = "file")
polygon_area :: proc(mesh: ^nav.Mesh, poly: nav.Poly) -> f32 {
	corners := mesh.corners[mesh.first[poly]:mesh.first[poly + 1]]
	twice: f32
	for corner, k in corners {
		a, b := mesh.vertices[corner], mesh.vertices[corners[(k + 1) % len(corners)]]
		twice += a.x * b.z - b.x * a.z
	}
	return abs(twice) / 2
}

// The floor's walkable polygons and the running total of their areas, for floor_point.
@(private = "file")
index_walkable :: proc(floor: ^Floor) {
	count := 0
	for island in floor.mesh.islands do count += int(island == floor.island)
	floor.walk_polys = make([]nav.Poly, count)
	floor.walk_area_to = make([]f32, count)
	total: f32
	k := 0
	for p in 0 ..< nav.poly_count(&floor.mesh) {
		if floor.mesh.islands[p] != floor.island do continue
		total += polygon_area(&floor.mesh, nav.Poly(p))
		floor.walk_polys[k], floor.walk_area_to[k] = nav.Poly(p), total
		k += 1
	}
}

// A point drawn from `rng` uniformly over the walkable floor: a polygon by its share of the area, then a point of it
// (a triangle of its fan by area, then a point of the triangle), at the floor's height there.
floor_point :: proc(floor: ^Floor, rng: ^sim.Rng) -> Nav_Point {
	FRACTION_STEPS :: 1 << 24 // a fraction's steps: f32's integers are exact up to here
	fraction :: proc(rng: ^sim.Rng) -> f32 {return f32(sim.rng_below(rng, FRACTION_STEPS)) / FRACTION_STEPS}
	mesh := &floor.mesh
	at := fraction(rng) * floor.area
	low, high := 0, len(floor.walk_area_to) - 1 // the first polygon whose running total passes `at`
	for low < high {
		middle := (low + high) / 2
		if floor.walk_area_to[middle] > at do high = middle
		else do low = middle + 1
	}
	poly := floor.walk_polys[low]
	corners := mesh.corners[mesh.first[poly]:mesh.first[poly + 1]]
	origin := mesh.vertices[corners[0]]
	fan := (fraction(rng) * polygon_area(mesh, poly)) * 2 // in twice-areas, as the fan's triangles are measured
	a, b := mesh.vertices[corners[1]], mesh.vertices[corners[2]]
	for k in 1 ..< len(corners) - 1 {
		a, b = mesh.vertices[corners[k]], mesh.vertices[corners[k + 1]]
		twice := abs((a.x - origin.x) * (b.z - origin.z) - (b.x - origin.x) * (a.z - origin.z))
		if fan < twice do break
		fan -= twice
	}
	root, along := dmath.sqrt(fraction(rng)), fraction(rng) // uniform over the triangle
	point := origin * (1 - root) + a * (root * (1 - along)) + b * (root * along)
	point.y = nav.height_at(mesh, poly, point)
	return {point, poly}
}

// The minion grid's cells, MINION_GRID_CELL square, laid over the mesh's extent on the floor plan with a cell to spare
// on every side (a minion never leaves the mesh, so none falls off the grid).
@(private = "file")
lay_grid :: proc(floor: ^Floor) {
	low, high := [2]f32{max(f32), max(f32)}, [2]f32{-max(f32), -max(f32)}
	for vertex in floor.mesh.vertices {
		low = {dmath.min(low.x, vertex.x), dmath.min(low.y, vertex.z)}
		high = {dmath.max(high.x, vertex.x), dmath.max(high.y, vertex.z)}
	}
	floor.grid_origin = low - MINION_GRID_CELL
	cells := (high - low) / MINION_GRID_CELL + 3
	floor.grid_columns = int(dmath.to_i32_clamped(cells.x, 1, MINION_GRID_CELLS))
	floor.grid_rows = int(dmath.to_i32_clamped(cells.y, 1, MINION_GRID_CELLS))
	assert(
		floor.grid_columns * floor.grid_rows <= MINION_GRID_CELLS,
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
		case "elite":
			kind, known := level.prop_enum(&marker, "kind", Elite_Kind.Warrior) // elite.gd's export_enum
			assert(known, "crypt_crew: an elite's kind is no Elite_Kind")
			facing := dmath.normalize(dmath.quat_rotate(marker.rot, {0, 0, 1}).xz) // the marker's +Z, as a model's front
			added := sim.append(&places.elites, Elite_Def{pos = marker.pos, facing = facing, kind = kind})
			assert(added && facing != {}, "crypt_crew: more elites than MAX_ELITE_MARKERS, or one facing straight up")
		case:
			assert(false, "crypt_crew: a marker of a kind the sim doesn't know (game/levels/markers/)")
		}
	}
	for has_spawn in spawned do assert(has_spawn, "crypt_crew: a floor needs a hero_spawn per slot")
	assert(places.graves.count > 0, "crypt_crew: a floor needs a grave for its surges to rise from")
}

// The walkable floor's place nearest `near` within `reach` (on the floor's island: never a wall's top); false for none.
floor_spot :: proc(floor: ^Floor, near: [3]f32, reach: f32) -> (spot: Nav_Point, ok: bool) {
	spot.poly, spot.point = nav.nearest(&floor.mesh, near, reach)
	return spot, spot.poly != nav.NO_POLY && nav.island_of(&floor.mesh, spot.poly) == floor.island
}

// Frees what world_create made: the physics world (the levels with it), the barrel's hull, each floor's navigation,
// the scratch and the World itself.
world_destroy :: proc(world: ^World) {
	physics.destroy(world.phys)
	physics.destroy_hull(world.barrel_hull)
	delete(world.contacts)
	delete(world.shapes)
	for &floor in world.floors {
		nav.fields_destroy(&floor.fields)
		nav.destroy(&floor.mesh)
		delete(floor.walk_polys)
		delete(floor.walk_area_to)
	}
	free(world)
}

// The block's view of the physics world: every body rolls back with the state.
extra :: proc(world: ^World) -> sim.Extra {
	return physics.extra(world.phys, State)
}

// The tick-0 state: the party starts on the Setup's floor, a save's with its tally (saves.odin), holding the Setup's
// crowd if it names one (director.odin); heroes arrive as their players do (presence.odin).
init :: proc(t: ^Tick) {
	enter_level(t, start_from_setup(t))
	if t.setup.crowd != .None do place_crowd(t, floor_of(t).minion_cap)
}

// Takes the party to level `to` (init, the wipe's floor restart; the next floor later): every hero lets go and its body
// goes, the props, the minions, the bolts and fireballs in flight and the elites (their bodies with them) go, a wipe
// ends, the static geometry is swapped (physics.level_change), then the new level's props are made in marker order, its
// packs and its elite markers' elites put to sleep (neither under a held crowd), its surge clock started, and every
// present hero gets a body at its slot's spawn. The coins on the floor go too. What the block keeps across it (the
// heroes' classes, the clock, the session's counts, the purse) stays.
enter_level :: proc(t: ^Tick, to: Level_Id) {
	holding := sim.iterate_present(t)
	for _, player in sim.next(&holding) do release_hold(t, player) // every hold, before any body it holds goes
	leaving := sim.iterate_present(t)
	for hero in sim.next(&leaving) do destroy_hero_body(t.world.phys, hero)
	despawn_props(t)
	sim.despawn_all(&t.state.minions)
	sim.despawn_all(&t.state.bolts)
	sim.despawn_all(&t.state.fireballs) // in flight: they burst on no floor
	sim.timer_stop(&t.state.wipe) // every hero gets up at its spawn
	forget_leavers(t) // and whoever comes back later, whole
	physics.despawn_all(t.world.phys, &t.state.elites)
	sim.despawn_all(&t.state.loot) // the purse is kept: its gold, like the tally, outlives the floor
	physics.level_change(t, t.world.phys, to)
	spawn_props(t)
	if t.setup.crowd == .None do spawn_packs(t) // a held crowd is the floor's whole population
	if t.setup.crowd == .None do spawn_marker_elites(t) // and none under a held crowd
	sim.timer_start_ticks(t, &t.state.surge, SURGE_FIRST_TICKS)
	t.state.rising, t.state.floor_surges = 0, 0 // a surge owed on the old floor, or before the wipe, is gone with it
	entering := sim.iterate_present(t)
	for _, player in sim.next(&entering) {
		spawn_hero(t, player, floor_of(t).places.hero_spawns[sim.player_slot(t, player)], false)
	}
}

// The whole party stayed down (check_wipe): the floor starts over (enter_level, the same floor), every hero up at its
// hero_spawn.
restart_floor :: proc(t: ^Tick) {
	enter_level(t, t.state.level.id)
	sim.emit(t, Event_Floor_Restarted{})
}
