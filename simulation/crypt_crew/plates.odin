// Pressure plates: a slab on a vertical prismatic joint to the World's anchor, held up by its joint's motor, which bears
// PLATE_LOAD on top of the slab's own weight and no more (Box3D's prismatic spring has no force cap; a motor has one).
// Whatever weighs more sinks it: a prop resting on it, a hero or an elite standing on it (a character's pogo spring is a
// joint to the body it stands on, so it pushes the slab down with the character's weight), and later the hoard and a
// ragdoll. Nothing reads who is on it: the joint's translation after the step is the whole rule (read_plates), so
// anything with weight works it and a minion (a row with no body) never does. Pressed and released at two depths,
// PLATE_ON and PLATE_OFF, so a slab bobbing under a hero who walks on and off its edge never flickers.
//
// A plate works one thing, its marker's `target`: a gate (gates.odin: it opens while `need` of its plates are pressed)
// or spikes (traps.odin: they rise while it is pressed). The slab rests PLATE_TRAVEL above the floor and sinks down to
// it, so a level needs no pit for it; its body is made with the floor's other mechanisms (enter_level), in marker order.
package crypt_crew

import "unified:dmath"
import "unified:physics"
import "unified:sim"

// A plate's place (a `plate` marker) and what it works: the index of its gate in the floor's gates, or of its spikes in
// its traps (-1: not that kind). `target` is the marker its NodePath names, which link_plates resolves.
Plate_Def :: struct {
	pos:    [3]f32,
	rot:    [4]f32,
	target: i32, // the marker it works (level.prop_ref: -1 for none)
	gate:   i32,
	trap:   i32,
}

// A plate, a row of the State's `plates` (its index is its marker's in the floor's Places).
Plate :: struct {
	body:    physics.Body_Ref,
	joint:   physics.Prismatic_Joint_Ref, // to the World's anchor: translation 0 at rest, -PLATE_TRAVEL sunk
	pressed: bool, // sunk past PLATE_ON, and not yet back above PLATE_OFF (plate_pressed)
	_pad:    [7]u8,
}

// `plate` was pressed (`pressed`) or released, at `position` (its slab's centre).
Event_Plate :: struct {
	plate:    sim.Handle(Plate),
	position: sim.Position,
	pressed:  bool,
}

// The rotation that turns a joint frame's +X (a prismatic joint's axis) to +Y: a quarter turn about +Z.
UP_AXIS :: [4]f32{0, 0, 0.70710678, 0.70710678}

// Resolves each plate's target marker to the gate or the spikes it works (world_create, after every marker is read).
// A plate with no target, or one naming anything else (a roller, a prop), fails the level, as does a gate needing more
// than the plates and braziers that name it.
link_plates :: proc(places: ^Places) {
	for &plate in sim.slice(&places.plates) {
		plate.gate, plate.trap = -1, -1
		for gate, i in sim.slice(&places.gates) {
			if gate.marker == plate.target do plate.gate = i32(i)
		}
		for trap, i in sim.slice(&places.traps) {
			if trap.marker == plate.target && trap.kind == .Spikes do plate.trap = i32(i)
		}
		assert(plate.gate >= 0 || plate.trap >= 0, "crypt_crew: a plate's target is no gate or spikes marker")
	}
	for gate in sim.slice(&places.gates) {
		plates := 0
		for plate in sim.slice(&places.plates) do plates += int(plate.target == gate.marker)
		// ---- the run's levels (milestone 7, step 3): a brazier naming the gate counts toward its need too
		for brazier in sim.slice(&places.braziers) do plates += int(brazier.target == gate.marker)
		assert(
			gate.need >= 1 && int(gate.need) <= plates,
			"crypt_crew: a gate needs more plates and braziers than work it, or none",
		)
	}
}

// A body for each of the floor's plate markers, in marker order: its slab resting PLATE_TRAVEL (and a hand) above the
// floor on a vertical slide (vertical_slide) whose motor lifts it at PLATE_RISE_SPEED with at most the force that bears
// the slab and PLATE_LOAD.
spawn_plates :: proc(t: ^Tick) {
	for &def in sim.slice(&floor_of(t).places.plates) {
		plate, handle, ok := sim.spawn(&t.state.plates)
		assert(ok, "crypt_crew: more plates than MAX_PLATES") // world_create's list holds as many
		rest := def.pos + {0, PLATE_TRAVEL + PLATE_CLEARANCE + PLATE_HALF.y, 0}
		shape_def := physics.shape_def(CAT_PIECE)
		shape_def.density = physics.box_density(PLATE_MASS, PLATE_HALF)
		body_def := physics.body_def(.Dynamic, rest, def.rot)
		// Never asleep: a load lifted off a sleeping slab (a prop carried away, teleported) would leave it down, its motor
		// unsolved; a plate awake costs one small body and its joint.
		body_def.enable_sleep = false
		plate.body, _ = physics.create_box(t.world.phys, body_def, shape_def, PLATE_HALF, sim.handle_key(handle))
		joint_def := vertical_slide(rest, def.rot, -PLATE_TRAVEL, 0)
		joint_def.motor_speed = PLATE_RISE_SPEED
		joint_def.max_motor_force = (PLATE_MASS + PLATE_LOAD) * GRAVITY
		plate.joint = physics.create_prismatic_joint(
			t.world.phys,
			physics.world_anchor(t.world.phys),
			physics.link(plate.body),
			joint_def,
		)
	}
}

// A prismatic joint holding a body (resting at `rest`, turned by `rot`) to the World's anchor on a vertical slide with
// a motor: translation 0 at `rest`, up positive, limited to [lower, upper]; the body keeps its turn. The motor's speed
// and force are the caller's (a plate's and a gate's).
vertical_slide :: proc(rest: [3]f32, rot: [4]f32, lower, upper: f32) -> physics.Prismatic_Joint_Def {
	def := physics.default_prismatic_joint_def()
	def.base.local_frame_a = {rest, UP_AXIS} // on the anchor, which stands at the origin unturned: the world's frame
	// on the body: the same frame seen from the body (its turn undone), so the two frames agree at rest
	def.base.local_frame_b = {{}, dmath.quat_mul({-rot.x, -rot.y, -rot.z, rot.w}, UP_AXIS)}
	def.enable_limit = true
	def.lower_translation, def.upper_translation = lower, upper
	def.enable_motor = true
	return def
}

// After the physics step: each plate is pressed or released by how far its slab has sunk (plate_pressed), announced
// when it changes.
read_plates :: proc(t: ^Tick) {
	plates := sim.iterate(&t.state.plates)
	for plate, handle in sim.next(&plates) {
		depth := -physics.prismatic_joint_translation(t.world.phys, plate.joint)
		pressed := plate_pressed(plate.pressed, depth)
		if pressed == plate.pressed do continue
		plate.pressed = pressed
		at := physics.body_position(t.world.phys, plate.body)
		sim.emit(t, Event_Plate{plate = handle, position = sim.Position(at), pressed = pressed})
	}
}

// Whether a plate is pressed with its slab sunk `depth` metres, having been pressed (`was`) or not: a released plate is
// pressed past PLATE_ON, a pressed one released above PLATE_OFF, and between the two it stays as it was.
plate_pressed :: proc(was: bool, depth: f32) -> bool {
	return depth > PLATE_OFF if was else depth > PLATE_ON
}
