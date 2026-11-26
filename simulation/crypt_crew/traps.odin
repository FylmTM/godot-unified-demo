// Traps: spikes and the roller, each a pure function of the game clock (which a co-op pause holds) and its marker, so
// every peer, a re-simulation and a late joiner agree on them with nothing kept but what they struck.
//
// Spikes are a sensor box on a static body over the spike tile's middle, up SPIKES_UP_S of every SPIKES_PERIOD_S from
// their marker's `phase` (spikes_up), or while their plate is pressed (plates.odin). They strike as they rise and every
// SPIKES_HIT_TICKS while up (`rearm`): every hero and elite the sensor holds (Box3D's shape_sensor_data: capsules made
// with sensor events on) and every minion over the tile (a row with no body: the strike grid) takes SPIKES_DAMAGE, the
// skeletons knocked off. The view raises the spikes from `up` and `since` at the shown time.
//
// The roller is a kinematic pillar driven along its marker's path, there and back (physics.drive_kinematic onto
// path_sample at the clock's tick plus its phase), so it shoves bodies as a moving body does: heroes, props, elites.
// Every ROLLER_HIT_TICKS at most it strikes what touches it (within ROLLER_TOUCH of its sides), ROLLER_DAMAGE, the
// skeletons knocked away; minions are kept out of it as out of a hero (roller_obstacles). It has a velocity, so a
// crossbow shot rewound to what its shooter saw finds it where it was (world_cast_ray_closest_rewound).
package crypt_crew

import "unified:dmath"
import "unified:level"
import "unified:physics"
import "unified:sim"

// What a trap marker places (game/levels/markers/trap.gd's `kind`, by name).
Trap_Kind :: enum u8 {
	Spikes,
	Roller,
}

// A trap's place (a `trap` marker): spikes stand at the marker; a roller's path is the marker's Path3D, each leg taking
// the marker's `leg_s`. `phase` (the marker's, in seconds) is how far into its cycle it is at game time 0.
Trap_Def :: struct {
	pos:    [3]f32,
	rot:    [4]f32,
	marker: i32, // its marker's index: what a plate's `target` names (link_plates)
	phase:  u32, // ticks
	path:   physics.Path, // a roller's: where its pillar's foot goes
	kind:   Trap_Kind,
}

// A trap, a row of the State's `traps` (its index is its marker's in the floor's Places).
Trap :: struct {
	body:   physics.Body_Ref, // spikes: the sensor's static body; a roller: its kinematic pillar
	sensor: physics.Shape_Ref, // spikes: the sensor box (zero for a roller)
	since:  sim.Game_Time, // spikes: when they last rose or fell (the view's animation)
	rearm:  sim.Timer, // no strike while it runs: spikes strike again as it runs out, a roller once it has
	kind:   Trap_Kind,
	up:     bool, // spikes: up after the last tick
	_pad:   [2]u8,
}

// `trap` struck something at `position` (the spike tile's middle, or the roller's foot).
Event_Trap_Hit :: struct {
	trap:     sim.Handle(Trap),
	position: sim.Position,
}

// A trap marker's place, kind and phase, and for a roller its path: the marker's Path3D points, each leg `leg_s` long,
// there and back, easing at each end. A roller without a path of two points or more fails the level.
read_trap :: proc(marker: ^level.Marker) -> (def: Trap_Def) {
	known: bool
	def.kind, known = level.prop_enum(marker, "kind", Trap_Kind.Spikes) // trap.gd's export_enum
	assert(known, "crypt_crew: a trap's kind is no Trap_Kind")
	def.pos, def.rot, def.marker = marker.pos, marker.rot, i32(marker.index)
	phase := level.prop_f32(marker, "phase")
	def.phase = u32(dmath.to_i32_clamped(dmath.round(phase * TICK_HZ), 0, max(i32)))
	if def.kind != .Roller do return
	points := len(marker.path)
	assert(points >= 2 && points <= physics.MAX_PATH_POINTS, "crypt_crew: a roller's path needs 2 to 16 points")
	leg := level.prop_f32(marker, "leg_s")
	assert(leg > 0, "crypt_crew: a roller's legs take no time")
	def.path.count, def.path.mode, def.path.ease = u8(points), .Ping_Pong, .Smooth
	for point, i in marker.path {
		def.path.points[i] = point
		def.path.seconds[i] = leg
	}
	return
}

// A body for each of the floor's trap markers, in marker order: spikes a static sensor box that feels heroes and
// elites, a roller its pillar where its path has it now.
spawn_traps :: proc(t: ^Tick) {
	for &def in sim.slice(&floor_of(t).places.traps) {
		trap, handle, ok := sim.spawn(&t.state.traps)
		assert(ok, "crypt_crew: more traps than MAX_TRAPS") // world_create's list holds as many
		trap.kind = def.kind
		tag := sim.handle_key(handle)
		switch def.kind {
		case .Spikes:
			shape_def := physics.shape_def(CAT_PIECE, CAT_HERO | CAT_ELITE)
			shape_def.is_sensor = true
			shape_def.enable_sensor_events = true
			half := [3]f32{SPIKES_HALF, SPIKES_SENSOR_HEIGHT / 2, SPIKES_HALF}
			body_def := physics.body_def(.Static, def.pos + {0, half.y, 0}, def.rot)
			trap.body, trap.sensor = physics.create_box(t.world.phys, body_def, shape_def, half, tag)
		case .Roller:
			body_def := physics.body_def(.Kinematic, roller_centre(&def, t.time), def.rot)
			trap.body, _ = physics.create_box(t.world.phys, body_def, physics.shape_def(CAT_PIECE), ROLLER_HALF, tag)
		}
	}
}

// Where a roller's pillar stands at game time `time`: its path at the clock's tick plus its phase, the pillar's centre
// ROLLER_HALF.y above its foot.
roller_centre :: proc(def: ^Trap_Def, time: sim.Game_Time) -> [3]f32 {
	return physics.path_sample(&def.path, u32(time) + def.phase, TICK_HZ) + {0, ROLLER_HALF.y, 0}
}

// Before the physics step: each roller is driven so the step lands it where its path has it at this tick.
drive_rollers :: proc(t: ^Tick) {
	traps := sim.iterate(&t.state.traps)
	for trap, handle in sim.next(&traps) {
		if trap.kind != .Roller do continue
		def := &sim.slice(&floor_of(t).places.traps)[handle.index]
		physics.drive_kinematic(t.world.phys, trap.body, roller_centre(def, t.time))
	}
}

// Whether spikes are up at game time `time`: SPIKES_UP_TICKS at the start of every SPIKES_PERIOD_TICKS from their
// phase, or while their plate is pressed.
spikes_up :: proc(t: ^Tick, trap: sim.Handle(Trap), time: sim.Game_Time) -> bool {
	def := &sim.slice(&floor_of(t).places.traps)[trap.index]
	if (u32(time) + def.phase) % SPIKES_PERIOD_TICKS < SPIKES_UP_TICKS do return true
	for plate_def, i in sim.slice(&floor_of(t).places.plates) {
		if plate_def.trap != i32(trap.index) do continue
		plate, _, _ := sim.item_at(&t.state.plates, i)
		if plate.pressed do return true
	}
	return false
}

// After the physics step: spikes rise or fall (spikes_up), striking as they rise and as their `rearm` runs out while
// up; a roller strikes what touches it once its `rearm` has run out.
spring_traps :: proc(t: ^Tick) {
	traps := sim.iterate(&t.state.traps)
	for trap, handle in sim.next(&traps) {
		switch trap.kind {
		case .Spikes:
			up := spikes_up(t, handle, t.time)
			if up != trap.up do trap.up, trap.since = up, t.time
			if !up || (trap.since != t.time && sim.timer_running(t, trap.rearm)) do continue
			sim.timer_start_ticks(t, &trap.rearm, SPIKES_HIT_TICKS)
			strike_spikes(t, trap, handle)
		case .Roller:
			if sim.timer_running(t, trap.rearm) || !strike_roller(t, trap, handle) do continue
			sim.timer_start_ticks(t, &trap.rearm, ROLLER_HIT_TICKS)
		}
	}
}

// The spikes strike: SPIKES_DAMAGE to each hero and elite their sensor holds (each body once) and each minion over the
// tile (its circle within the cluster's square), the skeletons knocked away from its middle at SPIKES_KNOCK; announced
// when it hurt anything.
@(private = "file")
strike_spikes :: proc(t: ^Tick, trap: ^Trap, handle: sim.Handle(Trap)) {
	centre := physics.body_position(t.world.phys, trap.body)
	rot := physics.body_rotation(t.world.phys, trap.body)
	struck := false
	physics.shape_sensor_data(t.world.phys, trap.sensor, &t.world.sensed)
	last: physics.Body_Link // sorted by body: a body's other shapes follow its first
	for visitor in t.world.sensed {
		if visitor.body == last do continue
		last = visitor.body
		struck |= strike_body(t, visitor, centre, SPIKES_DAMAGE, SPIKES_KNOCK)
	}
	walk := minions_within(t, centre.xz, (SPIKES_HALF + MINION_RADIUS) * SQRT_2)
	for minion, minion_handle in next_within(&walk) {
		if !within_square(centre, rot, SPIKES_HALF + MINION_RADIUS, minion.pos) do continue
		damage_minion(t, minion_handle, SPIKES_DAMAGE, away_from(centre, minion.pos), SPIKES_KNOCK, {}, .Trap)
		struck = true
	}
	floor := centre - {0, SPIKES_SENSOR_HEIGHT / 2, 0}
	if struck do sim.emit(t, Event_Trap_Hit{trap = handle, position = sim.Position(floor)})
}

// The roller strikes what touches it now (within ROLLER_TOUCH of its pillar's sides): ROLLER_DAMAGE to each hero up,
// elite and minion, the skeletons knocked away from it at ROLLER_KNOCK. Whether it touched anything (nothing: no
// strike, and it stays armed).
@(private = "file")
strike_roller :: proc(t: ^Tick, trap: ^Trap, handle: sim.Handle(Trap)) -> bool {
	centre := physics.body_position(t.world.phys, trap.body)
	rot := physics.body_rotation(t.world.phys, trap.body)
	struck := false
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		if !hero_up(t, player) || !within_square(centre, rot, ROLLER_HALF.x + HERO_RADIUS + ROLLER_TOUCH, hero.pos) {
			continue
		}
		damage_hero(t, player, ROLLER_DAMAGE, centre)
		struck = true
	}
	elites := sim.iterate(&t.state.elites)
	for elite, elite_handle in sim.next(&elites) {
		if elite.phase == .Dying do continue
		if !within_square(centre, rot, ROLLER_HALF.x + ELITE_RADIUS + ROLLER_TOUCH, elite.pos) do continue
		away := away_from(centre, elite.pos)
		damage_elite(t, elite_handle, ROLLER_DAMAGE, away, ROLLER_KNOCK, {}, .Trap, centre.xz)
		struck = true
	}
	reach := ROLLER_HALF.x + MINION_RADIUS + ROLLER_TOUCH
	walk := minions_within(t, centre.xz, reach * SQRT_2)
	for minion, minion_handle in next_within(&walk) {
		if !within_square(centre, rot, reach, minion.pos) do continue
		damage_minion(t, minion_handle, ROLLER_DAMAGE, away_from(centre, minion.pos), ROLLER_KNOCK, {}, .Trap)
		struck = true
	}
	if struck do sim.emit(t, Event_Trap_Hit{trap = handle, position = sim.Position(centre - {0, ROLLER_HALF.y, 0})})
	return struck
}

// A body a trap's sensor holds takes `damage` from it: a hero up (from below: no shield takes it), or a live elite
// (from its own place: no side, so no shield either), knocked away from `centre` at `knock`. Whether it was one.
@(private = "file")
strike_body :: proc(t: ^Tick, visitor: physics.Overlap, centre: [3]f32, damage: i16, knock: f32) -> bool {
	if visitor.category & CAT_HERO != 0 {
		player := sim.player_of_key(visitor.tag)
		if !hero_up(t, player) do return false
		damage_hero(t, player, damage, sim.player_data(t, player).pos)
		return true
	}
	if visitor.category & CAT_ELITE != 0 {
		handle := sim.handle_of_key(Elite, visitor.tag)
		elite := sim.get(&t.state.elites, handle)
		if elite == nil || elite.phase == .Dying do return false
		damage_elite(t, handle, damage, away_from(centre, elite.pos), knock, {}, .Trap, elite.pos.xz)
		return true
	}
	return false
}

// Whether `point` lies within `reach` of `centre` along both of the floor plan's axes turned by `rot` (a square
// `reach` from its middle to each side).
within_square :: proc(centre: [3]f32, rot: [4]f32, reach: f32, point: [3]f32) -> bool {
	local := dmath.quat_rotate({-rot.x, -rot.y, -rot.z, rot.w}, point - centre)
	return abs(local.x) <= reach && abs(local.z) <= reach
}

// The unit direction on the floor plan from `centre` to `point` (+X when they stand on one spot).
away_from :: proc(centre, point: [3]f32) -> [2]f32 {
	away := dmath.normalize(point.xz - centre.xz)
	return away if away != {} else {1, 0}
}

// The half diagonal of a square over its half side: a square's corners from its middle.
@(private = "file")
SQRT_2 :: f32(1.41421356)

// Every roller, as an obstacle for minions: a circle round its pillar's corners.
roller_obstacles :: proc(t: ^Tick, obstacles: ^sim.List(Obstacle, MAX_OBSTACLES)) {
	traps := sim.iterate(&t.state.traps)
	for trap in sim.next(&traps) {
		if trap.kind != .Roller do continue
		centre := physics.body_position(t.world.phys, trap.body)
		sim.append(obstacles, Obstacle{centre.xz, ROLLER_HALF.x * SQRT_2})
	}
}
