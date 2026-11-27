// Gates: a grille on a vertical prismatic joint to the World's anchor, gravity off, so its joint's motor alone moves it:
// up at GATE_SPEED to GATE_RISE while at least `need` of its plates are pressed and its braziers lit (gate_count: a lit
// brazier counts as a pressed plate), and down otherwise, pressing on what is under it with at most GATE_CLOSE_FORCE. So a crate left under a closing gate wedges it, and a hero under it is pressed
// on, never crushed, and walks out. A gate whose marker sets `latch` stays open once it has opened, until the party
// enters the floor again (a vault's door). Before the step (drive_gates) each gate's motor is set from the plates as the
// last step left them (and the braziers); the state keeps only what the gate is told (`open`), and where the grille is comes from Box3D,
// so a gate half open on one peer is half open on a late joiner's too.
//
// A gate lifted less than GATE_PASS is in minions' way (gate_obstacles): they walk the navigation mesh, which the gate's
// opening is part of, and are pushed back from the grille as from a hero. Bolts and shots stop at it (SHOT_FILTER).
package crypt_crew

import "unified:dmath"
import "unified:physics"
import "unified:sim"

// A gate's place (a `gate` marker): its grille spans the marker's local X, 4 m; how many of its plates must be pressed
// at once to open it, and whether it stays open once opened.
Gate_Def :: struct {
	pos:    [3]f32,
	rot:    [4]f32,
	marker: i32, // its marker's index: what its plates' `target` names (link_plates)
	need:   i32,
	latch:  bool,
}

// A gate, a row of the State's `gates` (its index is its marker's in the floor's Places).
Gate :: struct {
	body:    physics.Body_Ref,
	joint:   physics.Prismatic_Joint_Ref, // to the World's anchor: translation 0 shut, GATE_RISE open
	open:    bool, // told to open: its motor lifts it (the grille follows over the next second or so)
	latched: bool, // a latch gate that has opened: it stays open
	_pad:    [6]u8,
}

// `gate` was told to open (`open`) or to close, at `position` (its grille's foot, in the middle).
Event_Gate :: struct {
	gate:     sim.Handle(Gate),
	position: sim.Position,
	open:     bool,
}

// A body for each of the floor's gate markers, in marker order: the grille shut on its slide (vertical_slide), its
// motor pressing it down.
spawn_gates :: proc(t: ^Tick) {
	for &def in sim.slice(&floor_of(t).places.gates) {
		gate, handle, ok := sim.spawn(&t.state.gates)
		assert(ok, "crypt_crew: more gates than MAX_GATES") // world_create's list holds as many
		shut := def.pos + {0, GATE_HALF.y + PLATE_CLEARANCE, 0}
		body_def := physics.body_def(.Dynamic, shut, def.rot)
		body_def.gravity_scale = 0 // the motor holds it wherever it is
		// Never asleep: a close lands on whatever tick it lands, and the closing motor's first tick moves the grille
		// slower than Box3D's sleep threshold, so a gate whose island fell asleep that tick would stay open for good.
		body_def.enable_sleep = false
		shape_def := physics.shape_def(CAT_PIECE)
		shape_def.density = physics.box_density(GATE_MASS, GATE_HALF)
		gate.body, _ = physics.create_box(t.world.phys, body_def, shape_def, GATE_HALF, sim.handle_key(handle))
		joint_def := vertical_slide(shut, def.rot, 0, GATE_RISE)
		joint_def.motor_speed = -GATE_SPEED
		joint_def.max_motor_force = GATE_CLOSE_FORCE
		gate.joint = physics.create_prismatic_joint(
			t.world.phys,
			physics.world_anchor(t.world.phys),
			physics.link(gate.body),
			joint_def,
		)
	}
}

// Before the physics step: each gate is told to open while at least its `need` plates are pressed or braziers lit
// (gate_count; a latched one stays open), else to close; a change sets its motor (lifting, or pressing down) and wakes it, and is announced.
drive_gates :: proc(t: ^Tick) {
	gates := sim.iterate(&t.state.gates)
	for gate, handle in sim.next(&gates) {
		def := sim.slice(&floor_of(t).places.gates)[handle.index]
		open := gate.latched || gate_count(t, i32(handle.index)) >= def.need
		gate.latched |= open && def.latch
		if open == gate.open do continue
		gate.open = open
		phys := t.world.phys
		physics.prismatic_joint_set_motor_speed(phys, gate.joint, GATE_SPEED if open else -GATE_SPEED)
		physics.prismatic_joint_set_max_motor_force(phys, gate.joint, GATE_LIFT_FORCE if open else GATE_CLOSE_FORCE)
		sim.emit(t, Event_Gate{gate = handle, position = sim.Position(def.pos), open = open})
	}
}

// What counts toward gate `gate`'s need (its index in the floor's gates): each of its plates pressed and each of its
// braziers lit (braziers.odin).
gate_count :: proc(t: ^Tick, gate: i32) -> i32 {
	return gate_plates_pressed(t, gate) + braziers_lit(t, gate)
}

// How many of the plates that work gate `gate` (its index in the floor's gates) are pressed.
gate_plates_pressed :: proc(t: ^Tick, gate: i32) -> (pressed: i32) {
	for def, i in sim.slice(&floor_of(t).places.plates) {
		if def.gate != gate do continue
		plate, _, _ := sim.item_at(&t.state.plates, i)
		pressed += i32(plate.pressed)
	}
	return
}

// How high a gate's grille is lifted (metres; 0: shut).
gate_lift :: proc(phys: ^physics.World, gate: ^Gate) -> f32 {
	return physics.prismatic_joint_translation(phys, gate.joint)
}

// Every gate lifted less than GATE_PASS, as obstacles for minions: three circles along its grille (piece_obstacles).
gate_obstacles :: proc(t: ^Tick, obstacles: ^sim.List(Obstacle, MAX_OBSTACLES)) {
	gates := sim.iterate(&t.state.gates)
	for gate, handle in sim.next(&gates) {
		if gate_lift(t.world.phys, gate) >= GATE_PASS do continue
		def := sim.slice(&floor_of(t).places.gates)[handle.index]
		piece_obstacles(obstacles, def.pos, def.rot, GATE_HALF.x)
	}
}

// A 4 m piece (a gate's grille, a barricade) centred at `pos`, spanning `half` either side along its turn's local X,
// as three overlapping circles of PIECE_OBSTACLE_RADIUS: its middle and two thirds of the way to each end.
piece_obstacles :: proc(obstacles: ^sim.List(Obstacle, MAX_OBSTACLES), pos: [3]f32, rot: [4]f32, half: f32) {
	along := dmath.quat_rotate(rot, {1, 0, 0}).xz * (half * 2 / 3)
	for k in ([3]f32{-1, 0, 1}) do sim.append(obstacles, Obstacle{pos.xz + along * k, PIECE_OBSTACLE_RADIUS})
}
