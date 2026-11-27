// The lift: the floor's exit (its `lift` marker), a kinematic deck at floor level over a shaft, and a sensor over the
// deck. The party leaves a floor on it, with the hoard and everyone present aboard: nobody is left behind.
//
// Its phases (Lift_Phase): it waits; once the hoard rests on the deck with no hand on it (a lift whose marker asks for
// none, the hub's, skips this) and every present hero is aboard, at least one of them up (a downed hero aboard counts:
// it rides down as it lies), it boards, and LIFT_HOLD_S later goes down, LIFT_DROP in LIFT_RIDE_S; anyone stepping off
// while it boards puts it back to waiting. Going down, nobody takes damage and the party can't wipe: the floor is won.
// The hub's lift, at its bottom, begins the run (begin_run, run.odin). A crypt floor's opens a boon choice there
// (boons.odin), and once every present hero has picked, or BOON_TIMEOUT_S has run, the party descends: the depth goes
// up, the hoard's HOARD_GOLD (as the difficulty pays it) goes in the purse, the next floor is entered (floor_at) with
// everyone present on it, the downed up at REVIVE_HP, and the save point is marked there. A hero arriving while the
// lift is busy appears on its deck (lift_arrival) and is offered its boons too.
//
// The deck's height is a pure function of its phase and how long it has been in it (lift_target: the marker's Path at
// the phase's age while it goes down), and drive_lift sets the kinematic body's velocity to reach it in the next step
// (physics.drive_kinematic), so the State keeps only the phase and its start. Heroes ride it through their mover joint
// (a character on a kinematic body is carried by it); the hoard and the downed ride it as any body on a floor does.
package crypt_crew

import "unified:dmath"
import "unified:physics"
import "unified:sim"

// The floors a run goes down, in order: begin_run enters the first, each descent the next (floor_at). The last is the
// boss's vault, which has no lift: the run ends there, won at the King's fall or lost.
@(rodata)
FLOOR_ORDER := [?]Level_Id{.Floor_1, .Floor_2, .Floor_3, .Vault}

// The floor a run is on at `depth`: FLOOR_ORDER's, never past its last (no wrap: the vault ends a run).
floor_at :: proc(depth: u32) -> Level_Id {
	return FLOOR_ORDER[dmath.min(int(depth), len(FLOOR_ORDER) - 1)]
}

// Where the lift is in taking the party down.
Lift_Phase :: enum u8 {
	Waiting, // at the top, for the hoard and the party
	Boarding, // everyone and the hoard aboard: it goes down LIFT_HOLD_S after this began, unless someone steps off
	Descending, // going down the shaft, LIFT_RIDE_S
	Choosing, // at the bottom: the heroes pick their boons, then the party descends
}

// The floor's lift, in the State (its body zero on a floor without one).
Lift :: struct {
	body:   physics.Body_Ref, // the deck: kinematic
	sensor: physics.Shape_Ref, // the volume over the deck, which sees the hoard aboard
	since:  sim.Game_Time, // when `phase` began
	phase:  Lift_Phase,
	_pad:   [3]u8,
}

// A lift's place (a `lift` marker on the middle of the deck's top): the deck's path down its shaft.
Lift_Def :: struct {
	path:   physics.Path, // the deck body's centre: at the top, then LIFT_DROP below (Once, smoothstepped)
	rot:    [4]f32,
	placed: bool, // the floor has one
	// Whether the floor's hoard must be aboard before it goes (the marker's `hoard`): the crypt's floors' lifts; the
	// hub's, which takes the party into the run (begin_run), goes without one.
	hoard:  bool,
	_pad:   [2]u8,
}

// The lift's phase changed to `phase`.
Event_Lift :: struct {
	phase: Lift_Phase,
}

// The party went down to depth `depth` with the hoard, the purse now `gold` (the purse shows it once CONFIRMED).
Event_Descended :: struct {
	depth: u32,
	gold:  u32,
}

// The deck's path for a lift marker standing on the deck's top at `top`: its body's centre from there to LIFT_DROP
// below in LIFT_RIDE_S, easing in and out.
lift_path :: proc(top: [3]f32) -> (path: physics.Path) {
	path.points[0] = top - {0, LIFT_HALF.y, 0}
	path.points[1] = path.points[0] - {0, LIFT_DROP, 0}
	path.seconds[0] = LIFT_RIDE_S
	path.count = 2
	path.mode = .Once
	path.ease = .Smooth
	return
}

// The deck at the top of its shaft, waiting (enter_level, after the hoard): a kinematic box, and the sensor over it,
// which sees only the hoard.
spawn_lift :: proc(t: ^Tick) {
	def := &floor_of(t).places.lift
	if !def.placed do return
	lift := &t.state.lift
	lift.body, _ = physics.create_box(
		t.world.phys,
		physics.body_def(.Kinematic, def.path.points[0], def.rot),
		physics.shape_def(CAT_LIFT),
		LIFT_HALF,
	)
	sensor_def := physics.shape_def(CAT_LIFT, CAT_HOARD)
	sensor_def.is_sensor = true
	sensor_def.enable_sensor_events = true
	volume := physics.make_offset_box_hull(
		{LIFT_HALF.x, LIFT_SENSOR_HEIGHT / 2, LIFT_HALF.z},
		{0, LIFT_HALF.y + LIFT_SENSOR_HEIGHT / 2, 0},
	)
	lift.sensor = physics.create_hull_shape(t.world.phys, lift.body, sensor_def, &volume.base)
	lift.phase, lift.since = .Waiting, t.time
}

// The lift's body goes (enter_level).
despawn_lift :: proc(t: ^Tick) {
	physics.destroy_refs(t.world.phys, &t.state.lift)
	t.state.lift = {}
}

// Where the deck's centre is to be after this tick's step: at the top while it waits or boards, along its path while it
// goes down (at the phase's age), at the bottom while the heroes choose.
lift_target :: proc(t: ^Tick) -> [3]f32 {
	path := &floor_of(t).places.lift.path
	lift := &t.state.lift
	switch lift.phase {
	case .Waiting, .Boarding:
		return path.points[0]
	case .Descending:
		return physics.path_sample(path, u32(t.time - lift.since), TICK_HZ)
	case .Choosing:
		return path.points[1]
	}
	unreachable()
}

// Before the physics step: the deck is driven to lift_target.
drive_lift :: proc(t: ^Tick) {
	if t.state.lift.body == {} do return
	physics.drive_kinematic(t.world.phys, t.state.lift.body, lift_target(t))
}

// Whether `point` (a hero's feet; a downed hero's lies where it fell) is aboard: over the deck, and from a little below
// its top to LIFT_SENSOR_HEIGHT above it.
on_deck :: proc(phys: ^physics.World, lift: ^Lift, point: [3]f32) -> bool {
	local := physics.body_local_point(phys, lift.body, point)
	above := local.y - LIFT_HALF.y
	return(
		abs(local.x) <= LIFT_HALF.x &&
		abs(local.z) <= LIFT_HALF.z &&
		above >= -LIFT_HALF.y &&
		above <= LIFT_SENSOR_HEIGHT \
	)
}

// Where the hoard is against the deck: `seen`, the sensor over the deck sees it (a part of it is on the lift), and
// `wholly`, its whole box is over the deck as well (each corner of its bottom). Seen but not wholly aboard, the HUD
// says so ("the hoard must be wholly on the lift"): a chest hanging over the edge doesn't go. Pure (on the step's
// sensor data, into the World's scratch `overlaps`): what the tick and the HUD both ask.
hoard_on_deck :: proc(
	phys: ^physics.World,
	hoard: ^Hoard,
	lift: ^Lift,
	overlaps: ^[dynamic]physics.Overlap,
) -> (
	seen: bool,
	wholly: bool,
) {
	if hoard.body == {} || lift.body == {} do return
	physics.shape_sensor_data(phys, lift.sensor, overlaps)
	for overlap in overlaps do seen ||= overlap.shape == hoard.shape
	if !seen do return
	for corner in 0 ..< 4 {
		local := HOARD_HALF * {f32(corner & 1) * 2 - 1, -1, f32(corner >> 1) * 2 - 1}
		at := physics.body_local_point(phys, lift.body, physics.body_world_point(phys, hoard.body, local))
		if abs(at.x) > LIFT_HALF.x || abs(at.z) > LIFT_HALF.z do return
	}
	return true, true
}

// Whether the hoard rests aboard: nobody holds it and it is wholly on the deck (hoard_on_deck).
hoard_aboard :: proc(t: ^Tick) -> bool {
	if t.state.hoard.haulers != {} do return false
	_, wholly := hoard_on_deck(t.world.phys, &t.state.hoard, &t.state.lift, &t.world.overlaps)
	return wholly
}

// Whether the lift may go: the hoard aboard (hoard_aboard) if its marker asks for it, every present hero aboard
// (on_deck: a downed one too), and one of them up (a party all down is a wipe, not a ride).
ready_to_go :: proc(t: ^Tick) -> bool {
	if floor_of(t).places.lift.hoard && !hoard_aboard(t) do return false
	up := false
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		if !on_deck(t.world.phys, &t.state.lift, hero.pos) do return false
		up ||= hero_up(t, player)
	}
	return up
}

// After the physics step: the lift's phase moves on (the package header's order), and at the end of the choosing the
// party descends. A run that ended (its results showing) holds it where it is.
update_lift :: proc(t: ^Tick) {
	lift := &t.state.lift
	if lift.body == {} || t.state.run.phase == .Won || t.state.run.phase == .Lost do return
	age := u32(t.time - lift.since)
	switch lift.phase {
	case .Waiting:
		if ready_to_go(t) do set_lift_phase(t, .Boarding)
	case .Boarding:
		if !ready_to_go(t) do set_lift_phase(t, .Waiting)
		else if age >= LIFT_HOLD_TICKS do set_lift_phase(t, .Descending)
	case .Descending:
		if age < LIFT_RIDE_TICKS do return
		if !floor_of(t).places.lift.hoard {
			begin_run(t) // the hub's: down into the run (run.odin)
			return
		}
		t.state.run.offers += 1
		set_lift_phase(t, .Choosing)
		sim.emit(t, Event_Choice{open = true})
	case .Choosing:
		chosen := true
		heroes := sim.iterate_present(t)
		for hero in sim.next(&heroes) do chosen &&= has_picked(hero, t.state.run.offers)
		if !chosen && age < BOON_TIMEOUT_TICKS do return
		pick_for_the_late(t)
		descend(t)
	}
}

// Whether the lift has gone down (or is going): the floor is won, so nobody takes damage and the party can't wipe.
lift_gone :: proc(t: ^Tick) -> bool {
	return t.state.lift.phase >= .Descending
}

// Whether the party is picking its boons, at the lift's bottom or in the Pit's lull (arena.odin): the heroes take no
// input but the pick (the tick skips the systems that read it, and the drive stands every hero still).
choosing :: proc(t: ^Tick) -> bool {
	return choice_open(t.state)
}

// Whether a boon choice is open in `state`: a run playing, its lift at the bottom waiting on picks or the Pit in a
// lull's choice (a run that ended mid-choice has none). Pure: what the tick (choosing) and the HUD both ask.
choice_open :: proc(state: ^State) -> bool {
	return state.run.phase == .Playing && (state.lift.phase == .Choosing || state.pit.stage == .Choosing)
}

// The lift's phase becomes `phase`, from now.
@(private = "file")
set_lift_phase :: proc(t: ^Tick, phase: Lift_Phase) {
	t.state.lift.phase, t.state.lift.since = phase, t.time
	sim.emit(t, Event_Lift{phase = phase})
}

// The party descends with the hoard: the choice closes, depth and purse up (the hoard's gold as the difficulty pays
// it), the next floor entered (each present hero at its spawn, up: at the health it had, or REVIVE_HP if it was down),
// the save point marked there.
@(private = "file")
descend :: proc(t: ^Tick) {
	kept: [PLAYERS]i16 // by slot: each present hero's health on the next floor
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		kept[sim.player_slot(t, player)] = REVIVE_HP if hero.action == .Down else hero.hp
	}
	sim.emit(t, Event_Choice{open = false})
	t.state.depth += 1
	t.state.gold += u32(run_gold(t, HOARD_GOLD))
	enter_level(t, floor_at(t.state.depth))
	arrived := sim.iterate_present(t)
	for hero, player in sim.next(&arrived) do hero.hp = kept[sim.player_slot(t, player)]
	mark_save_point(t)
	sim.emit(t, Event_Descended{depth = t.state.depth, gold = t.state.gold})
}

// Where `player`'s hero arrives while the lift is busy (boarding, going down or choosing): on the deck, at the deck's
// height now, at the first of its places clear of the hoard and of every hero (an overlap of the arrival's capsule
// against CAT_HOARD | CAT_HERO): its slot's corner (LIFT_SLOT_SPREAD out), then the next slots' corners round from it,
// then the middle; with none clear, its corner anyway. False while it waits (the arrival goes beside the party).
lift_arrival :: proc(t: ^Tick, player: sim.Player) -> (feet: [3]f32, aboard: bool) {
	lift := &t.state.lift
	if lift.body == {} || lift.phase == .Waiting do return
	slot := sim.player_slot(t, player)
	corner :: proc(slot: int) -> [3]f32 {
		return [3]f32{f32(slot & 1) * 2 - 1, 0, f32(slot >> 1) * 2 - 1} * LIFT_SLOT_SPREAD
	}
	capsule := [2][3]f32{{0, HERO_POGO_REST, 0}, {0, HERO_POGO_REST + 2 * HERO_HALF_HEIGHT, 0}}
	proxy := physics.make_proxy(capsule[:], HERO_RADIUS)
	filter := physics.Filter {
		category = CAT_HERO,
		mask     = CAT_HOARD | CAT_HERO,
	}
	for k in 0 ..= PLAYERS {
		place := corner((slot + k) % PLAYERS) if k < PLAYERS else [3]f32{}
		at := physics.body_world_point(t.world.phys, lift.body, place + {0, LIFT_HALF.y, 0})
		physics.world_overlap_shape(t.world.phys, at, proxy, &t.world.overlaps, filter)
		if len(t.world.overlaps) == 0 do return at, true
	}
	return physics.body_world_point(t.world.phys, lift.body, corner(slot) + {0, LIFT_HALF.y, 0}), true
}

// Dev (Command_Dev_Board): while the lift waits, every hold lets go (the hoard's, a prop's, a heave's), the hoard (on a
// floor whose lift wants one) is put on the middle of the deck, turned as the deck is, and every present hero on the
// deck at its slot's corner (lift_arrival's places; a downed one's ragdoll laid there anew), so the lift boards as the
// rules say (nothing is skipped: it still needs the party aboard and one up).
board_lift :: proc(t: ^Tick) {
	lift, hoard := &t.state.lift, &t.state.hoard
	wants_hoard := floor_of(t).places.lift.hoard
	if lift.body == {} || (wants_hoard && hoard.body == {}) || lift.phase != .Waiting do return
	holding := sim.iterate_present(t)
	for _, player in sim.next(&holding) do release_hold(t, player) // every hold first: a heave's joint on a body that goes
	if hoard.body != {} {
		centre := physics.body_world_point(t.world.phys, lift.body, {0, LIFT_HALF.y + HOARD_HALF.y, 0})
		physics.body_teleport(t.world.phys, hoard.body, centre, physics.body_rotation(t.world.phys, lift.body))
	}
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		slot := sim.player_slot(t, player)
		corner := [3]f32{f32(slot & 1) * 2 - 1, 0, f32(slot >> 1) * 2 - 1} * LIFT_SLOT_SPREAD
		hero.pos = physics.body_world_point(t.world.phys, lift.body, corner + {0, LIFT_HALF.y, 0})
		if ragdolled(hero) {
			// A downed hero's body is laid down again there, at rest (its capsule stays out of the world where it
			// fell), no longer flying from a throw
			end_hero_heave(t, player)
			physics.ragdoll_destroy(t.world.phys, &hero.ragdoll)
			hero.vel = {}
			ragdoll_hero(t, player, {})
			continue
		}
		physics.character_teleport(t.world.phys, &hero.body, hero.pos + {0, HERO_CENTRE_ABOVE_FEET, 0})
	}
}
