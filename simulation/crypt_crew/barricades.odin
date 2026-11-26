// Barricades: a fence welded to the World's anchor, broken free by a blow: its weld strained past BARRICADE_BREAK_N
// (Box3D's joint force threshold: the step reports the joint, world_joint_events) while a blow touches it, a thrown
// prop (its throw running), a Knight's charge or a body a Barbarian threw; a fireball's blast breaks it outright
// (blast_barricades). The blow decides and the threshold is its floor: the strain alone can't tell a blow from a walk,
// since a hero at a run carries more momentum than a thrown crate and Box3D's contacts stop a capsule within a substep,
// so walking into the fence strains its weld harder than a thrown crate does. Broken, the weld goes and the fence falls
// free as debris: a loose body in CAT_PROP that props, heroes and elites knock about and the hoard passes through
// (DEBRIS_FILTER) (no table's, so nobody grabs it, and its tag is cleared, so no prop's rule mistakes it for a prop).
// Until then it is in minions' way (barricade_obstacles). A level stands a fence clear of its walls: one pressed into a
// wall strains its weld at rest, and every tick would report it.
//
// The break is Box3D's own, so a rollback across it restores the weld (it is a joint in the snapshot) and the step
// that re-simulates the blow breaks it again; nothing about the break is kept outside the block.
package crypt_crew

import "unified:physics"
import "unified:sim"

// A barricade's place (a `barricade` marker): its fence spans the marker's local X, 4 m.
Barricade_Def :: struct {
	pos: [3]f32,
	rot: [4]f32,
}

// A barricade, a row of the State's `barricades` (its index is its marker's in the floor's Places).
Barricade :: struct {
	body:   physics.Body_Ref, // the fence, standing or, once broken, debris
	weld:   physics.Weld_Joint_Ref, // to the World's anchor (zero once broken)
	broken: bool,
	_pad:   [7]u8,
}

// A broken barricade's fence: a prop to everything but the hoard, which a hauler drags through it (a dragged chest
// would catch on a fence lying across its way, and the passage it barred is the hoard's way round the traps).
DEBRIS_FILTER :: physics.Filter {
	category = CAT_PROP,
	mask     = ~CAT_HOARD,
}

// `player` ({}: nobody, or nobody touching it) broke `barricade` at `position` (its fence's centre as it broke).
Event_Barricade_Broken :: struct {
	barricade: sim.Handle(Barricade),
	position:  sim.Position,
	player:    sim.Player,
}

// A body for each of the floor's barricade markers, in marker order: the fence standing on the floor, welded rigidly
// to the anchor where it stands, the weld reporting a joint event past BARRICADE_BREAK_N.
spawn_barricades :: proc(t: ^Tick) {
	for &def in sim.slice(&floor_of(t).places.barricades) {
		barricade, handle, ok := sim.spawn(&t.state.barricades)
		assert(ok, "crypt_crew: more barricades than MAX_BARRICADES") // world_create's list holds as many
		centre := def.pos + {0, BARRICADE_HALF.y, 0}
		shape_def := physics.shape_def(CAT_PIECE)
		shape_def.density = physics.box_density(BARRICADE_MASS, BARRICADE_HALF)
		body_def := physics.body_def(.Dynamic, centre, def.rot)
		barricade.body, _ = physics.create_box(
			t.world.phys,
			body_def,
			shape_def,
			BARRICADE_HALF,
			sim.handle_key(handle),
		)
		weld := physics.default_weld_joint_def() // stiffness 0: rigid
		weld.base.local_frame_a = {centre, def.rot} // on the anchor: the world's frame
		weld.base.force_threshold = BARRICADE_BREAK_N
		barricade.weld = physics.create_weld_joint(
			t.world.phys,
			physics.world_anchor(t.world.phys),
			physics.link(barricade.body),
			weld,
		)
	}
}

// After the physics step: each barricade whose weld passed its force threshold while a blow touches it breaks
// (barricade_blow).
break_barricades :: proc(t: ^Tick) {
	if t.state.barricades.count == 0 do return
	physics.world_joint_events(t.world.phys, &t.world.joints)
	for joint in t.world.joints {
		barricades := sim.iterate(&t.state.barricades)
		for barricade, handle in sim.next(&barricades) {
			if barricade.weld.joint != joint do continue
			if blow, player := barricade_blow(t, barricade); blow do break_barricade(t, barricade, handle, player)
		}
	}
}

// The weld goes and the fence falls free as debris (CAT_PROP, untagged): `player`'s blow broke it.
@(private = "file")
break_barricade :: proc(t: ^Tick, barricade: ^Barricade, handle: sim.Handle(Barricade), player: sim.Player) {
	phys := t.world.phys
	physics.destroy_joint(phys, &barricade.weld.joint)
	barricade.broken = true
	physics.body_shapes(phys, barricade.body, &t.world.shapes)
	for shape in t.world.shapes do physics.shape_set_filter(phys, shape, DEBRIS_FILTER)
	physics.body_set_tag(phys, barricade.body, 0)
	at := physics.body_position(phys, barricade.body)
	sim.emit(t, Event_Barricade_Broken{barricade = handle, position = sim.Position(at), player = player})
}

// Whether a blow touches the barricade after the step, and whose: the first of its contacts that is a thrown prop (its
// thrower's), a charging hero, or an elite or a downed hero's ragdoll a Barbarian threw (the thrower's), in contact
// order. (A fireball's blast breaks it outright: blast_barricades.)
@(private = "file")
barricade_blow :: proc(t: ^Tick, barricade: ^Barricade) -> (blow: bool, player: sim.Player) {
	physics.body_contact_data(t.world.phys, barricade.body, &t.world.touching)
	for &contact in t.world.touching {
		for side in ([2]physics.Overlap{contact.a, contact.b}) {
			switch {
			case side.category & CAT_PROP != 0:
				prop := sim.get(&t.state.props, sim.handle_of_key(Prop, side.tag))
				if prop != nil && sim.timer_running(t, prop.thrown) do return true, prop.thrown_by
			case side.category & CAT_HERO != 0:
				hero := sim.player_data(t, sim.player_of_key(side.tag))
				if hero == nil do continue
				if hero.action == .Charge do return true, sim.player_of_key(side.tag)
			case side.category & CAT_RAGDOLL != 0:
				hero := sim.player_data(t, sim.player_of_key(side.tag))
				if hero != nil && hero.heave == .Thrown do return true, hero.heaved_by
			case side.category & CAT_ELITE != 0:
				elite := sim.get(&t.state.elites, sim.handle_of_key(Elite, side.tag))
				if elite != nil && elite.phase == .Thrown do return true, elite.heaved_by
			}
		}
	}
	return false, {}
}

// A blast at `heart` (a fireball's, `player`'s): each barricade it reaches (blast_impulse, walls shielding it) breaks
// if it stands, and its fence takes the blast's impulse, standing or already debris. The blast decides, as a blow
// does in break_barricades: it has no body whose contact a break could be read from.
blast_barricades :: proc(t: ^Tick, heart: [3]f32, player: sim.Player) {
	barricades := sim.iterate(&t.state.barricades)
	for barricade, handle in sim.next(&barricades) {
		impulse := blast_impulse(t, heart, barricade.body) or_continue
		if !barricade.broken do break_barricade(t, barricade, handle, player)
		physics.body_apply_linear_impulse_to_center(t.world.phys, barricade.body, impulse)
	}
}

// Every barricade standing, as obstacles for minions: three circles along its fence (piece_obstacles).
barricade_obstacles :: proc(t: ^Tick, obstacles: ^sim.List(Obstacle, MAX_OBSTACLES)) {
	barricades := sim.iterate(&t.state.barricades)
	for barricade, handle in sim.next(&barricades) {
		if barricade.broken do continue
		def := sim.slice(&floor_of(t).places.barricades)[handle.index]
		piece_obstacles(obstacles, def.pos, def.rot, BARRICADE_HALF.x)
	}
}
