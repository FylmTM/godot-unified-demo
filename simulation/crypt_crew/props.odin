// Props: the barrels and crates heroes carry and throw (hands.odin), dynamic Box3D bodies made from the floor's `prop`
// markers when the party enters it (enter_level), in marker order, so every peer's bodies have the same indices. A
// prop's body is tagged with its handle's key, so a hit names the prop. A thrown prop passes through its thrower until
// it is clear of them, and makes a thud worth showing when it lands or crashes (Event_Prop_Impact).
package crypt_crew

import "unified:dmath"
import "unified:physics"
import "unified:sim"

// A prop, a row of the State's `props`.
Prop :: struct {
	body:           physics.Body_Ref,
	// Its body and its thrower's don't touch from the throw until it is clear of them (age_throws).
	thrower_ignore: physics.Filter_Joint_Ref,
	thrown:         sim.Timer, // its throw's while it runs (THROWN_TICKS): what a hit will be blamed on
	held_by:        sim.Player, // the hero carrying it ({}: nobody)
	thrown_by:      sim.Player, // who threw it last (while `thrown` runs), whether still here or not
	hits:           sim.List(sim.Handle(Minion), PROP_HITS_MAX), // the minions its throw hurt: each once (prop_hits)
	kind:           Prop_Kind,
	_pad:           [3]u8,
}

// A prop hit something hard (it landed, or crashed into a wall or another prop): a thud worth showing.
Event_Prop_Impact :: struct {
	prop:     sim.Handle(Prop),
	position: sim.Position,
	speed:    f32, // the approach speed, metres per second (at least IMPACT_SPEED)
}

// A body for each of the floor's prop markers, in marker order, resting where the marker stands.
spawn_props :: proc(t: ^Tick) {
	for &def in sim.slice(&floor_of(t).places.props) {
		prop, handle, ok := sim.spawn(&t.state.props)
		assert(ok, "crypt_crew: more props than MAX_PROPS") // world_create's list holds as many
		spec := &PROP_SPECS[def.kind]
		prop.kind = def.kind
		body_def := physics.body_def(.Dynamic, def.pos + {0, spec.half.y, 0}, def.rot)
		shape_def := physics.shape_def(CAT_PROP)
		shape_def.base_material.friction = PROP_FRICTION
		shape_def.base_material.restitution = PROP_RESTITUTION
		shape_def.enable_hit_events = true
		switch spec.shape {
		case .Box:
			shape_def.density = physics.box_density(spec.mass, spec.half)
			prop.body, _ = physics.create_box(t.world.phys, body_def, shape_def, spec.half, sim.handle_key(handle))
		case .Cylinder:
			shape_def.density = t.world.barrel_density
			prop.body = physics.create_body(t.world.phys, body_def, sim.handle_key(handle))
			physics.create_hull_shape(t.world.phys, prop.body, shape_def, t.world.barrel_hull)
		}
	}
}

// Every prop's body goes and the table empties (a level change; the holds are let go first: enter_level).
despawn_props :: proc(t: ^Tick) {
	props := sim.iterate(&t.state.props)
	for prop in sim.next(&props) do physics.destroy_refs(t.world.phys, prop)
	sim.despawn_all(&t.state.props)
}

// Whether a prop is in minions' way: held, or slower than PROP_REST_SPEED (a thrown one flies through them).
prop_in_the_way :: proc(phys: ^physics.World, prop: ^Prop) -> bool {
	speed := physics.body_linear_velocity(phys, prop.body)
	return prop.held_by != {} || dmath.length_sq(speed) < PROP_REST_SPEED * PROP_REST_SPEED
}

// After the physics step: a thrown prop (its `thrown` running) flying faster than PROP_HIT_SPEED hurts each live minion
// its footprint meets, once per throw and at most PROP_HITS_MAX, knocked along its flight, and keeps PROP_HIT_KEEP of
// its velocity per hit, hurting no more once that is under PROP_HIT_SPEED. The thrower is the damage's. Props never
// hurt heroes.
prop_hits :: proc(t: ^Tick) {
	props := sim.iterate(&t.state.props)
	for prop in sim.next(&props) {
		if !sim.timer_running(t, prop.thrown) do continue
		velocity := physics.body_linear_velocity(t.world.phys, prop.body)
		centre := physics.body_position(t.world.phys, prop.body)
		reach := PROP_SPECS[prop.kind].footprint + MINION_RADIUS
		walk := minions_within(t, centre.xz, reach)
		for minion, handle in next_within(&walk) {
			if dmath.length_sq(velocity) < PROP_HIT_SPEED * PROP_HIT_SPEED do break // slowed by its hits
			bottom := centre.y - PROP_SPECS[prop.kind].half.y
			if bottom - minion.pos.y > MINION_HEIGHT do continue
			if prop_hit(prop, handle) || !sim.append(&prop.hits, handle) do continue
			damage_minion(
				t,
				handle,
				PROP_HIT_DAMAGE,
				dmath.normalize(velocity.xz),
				PROP_HIT_KNOCK,
				prop.thrown_by,
				.Prop,
			)
			velocity *= PROP_HIT_KEEP
			physics.body_set_linear_velocity(t.world.phys, prop.body, velocity)
		}
	}
}

// Whether a prop's throw already hurt `minion`.
@(private = "file")
prop_hit :: proc(prop: ^Prop, minion: sim.Handle(Minion)) -> bool {
	for hit in sim.slice(&prop.hits) {
		if hit == minion do return true
	}
	return false
}

// The point a prop's view stands on: the bottom of its body (its model's origin), wherever the body has turned.
prop_base :: proc(phys: ^physics.World, prop: ^Prop) -> [3]f32 {
	rot := physics.body_rotation(phys, prop.body)
	return physics.body_position(phys, prop.body) + dmath.quat_rotate(rot, {0, -PROP_SPECS[prop.kind].half.y, 0})
}

// The step's hits on props (a landing, a crash into a wall or another prop) faster than IMPACT_SPEED: an impact each.
prop_impacts :: proc(t: ^Tick) {
	physics.world_contact_events(t.world.phys, &t.world.contacts)
	for &hit in t.world.contacts {
		if hit.kind != .Hit do continue
		for shape in ([2]physics.Overlap{hit.a, hit.b}) {
			if shape.category & CAT_PROP == 0 do continue
			handle := sim.handle_of_key(Prop, shape.tag)
			if sim.get(&t.state.props, handle) == nil do continue
			impact := Event_Prop_Impact {
				prop     = handle,
				position = sim.Position(hit.point),
				speed    = hit.speed,
			}
			sim.emit(t, impact)
		}
	}
}

// A thrown prop's ignore of its thrower ends once it is clear of them (THROW_CLEAR_DIST) or its throw ran out
// (THROWN_TICKS). From then a bounce back hits the thrower like anything else. A thrower who leaves ends theirs at once
// (end_throws_by).
age_throws :: proc(t: ^Tick) {
	props := sim.iterate(&t.state.props)
	for prop in sim.next(&props) {
		if prop.thrower_ignore == {} do continue
		clear := !sim.timer_running(t, prop.thrown)
		if !clear {
			away := physics.body_position(t.world.phys, prop.body) - sim.player_data(t, prop.thrown_by).pos
			clear = dmath.length_sq(away.xz) > THROW_CLEAR_DIST * THROW_CLEAR_DIST
		}
		if clear do physics.stop_ignoring(t.world.phys, &prop.thrower_ignore)
	}
}

// `player` leaves: every prop they threw stops ignoring their body before it goes (presence.odin), on any tick, a
// paused one too, so no ignore outlives the body it names.
end_throws_by :: proc(t: ^Tick, player: sim.Player) {
	props := sim.iterate(&t.state.props)
	for prop in sim.next(&props) {
		if prop.thrown_by == player do physics.stop_ignoring(t.world.phys, &prop.thrower_ignore)
	}
}
