// The World, everything outside the state block: the Box3D world (its rollback state is the Extra), Floor 1's
// navigation mesh with its memo of fields, the places the sim reads from the floor's markers, and the heroes'
// controller tuning. It holds only what world_create builds and what physics rolls back, so a rollback, a late join
// or a replay finds it as every other peer does (unified/src/sim/README.md, World). `init` enters the floor.
package crypt_crew

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
	pos:   [3]f32,
	count: i32, // how many skeletons it holds
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
	graves:      sim.List([3]f32, MAX_GRAVES), // where surges rise
	packs:       sim.List(Pack_Def, MAX_PACKS),
	props:       sim.List(Prop_Def, MAX_PROPS),
}

// The world outside the block.
World :: struct {
	phys:      ^physics.World,
	mesh:      nav.Mesh, // the floor's baked navigation: where skeletons walk
	fields:    nav.Fields, // the mesh's distance fields, memoized by goal (a pure function of the mesh and the goal)
	agent:     level.Nav_Agent, // what the mesh was baked for
	places:    Places,
	hero_defs: [Class]physics.Character_Def, // each class's controller (its own max_speed); Any's is never used
}

// Builds the world from the levels (unified/src/level/README.md): Floor 1's static geometry, its navigation mesh and
// its places. A marker property's default lives in its marker script (game/levels/markers/), which the export writes
// whole, so the sim reads the properties without defaults of its own and asserts what its rules need.
world_create :: proc(seed: u64, levels: []sim.Level_File, _: sim.No_Setup) -> ^World {
	world := new(World)
	problem: string
	// a shape the level leaves uncategorized blocks everything, as a wall does
	world.phys, problem = physics.create_with_levels({tick_hz = TICK_HZ}, levels, CAT_WALL)
	assert(problem == "", problem) // no level, or a shape Box3D refuses
	floor := physics.level_data(world.phys, Level_Id.Floor_1)
	err: nav.Build_Error
	world.mesh, err = nav.build(floor.nav_vertices, floor.nav_polygons)
	assert(err == .None, "crypt_crew: Floor 1's navigation mesh doesn't build (bake it: uni bake --nav)")
	world.fields = nav.fields_make(&world.mesh, MAX_FIELDS)
	world.agent = floor.nav_agent
	read_places(&world.places, floor)
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
	return world
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
			added := sim.append(&places.graves, marker.pos)
			assert(added, "crypt_crew: more graves than MAX_GRAVES")
		case "pack":
			pack := Pack_Def{marker.pos, i32(level.prop_int(&marker, "count"))}
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

// Frees what world_create made: the physics world (the levels with it), the navigation and the World itself.
world_destroy :: proc(world: ^World) {
	physics.destroy(world.phys)
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
	physics.level_change(t, t.world.phys, Level_Id.Floor_1)
}
