// The skeleton Mage: a caster that keeps its distance. It walks its target's field until the target is in sight within
// MAGE_FAR, backs away inside MAGE_NEAR (along the floor: open_heading turns it off a wall), and stands between, facing
// it. Every BONE_BOLT_EVERY_S, with its target in
// sight within BONE_BOLT_RANGE, it turns on it and casts a bone bolt (its spec's windup, then the bolt leaves along the
// facing it locked, so a hero who moves on dodges it): a row of the State's `bolts` marked as its (Bolt.by_elite),
// which flies as a hero's bolt does but meets heroes instead of skeletons (fly_bone_bolt). Every SUMMON_EVERY_S it
// casts for SUMMON_CAST_S and SUMMON_COUNT minions rise round it, never past the floor's cap. A stagger cuts off either
// cast.
package crypt_crew

import "unified:dmath"
import "unified:physics"
import "unified:sim"

// What a bone bolt stops at: walls, low cover and props met where they stand above FLIGHT_HEIGHT, as a hero's bolt;
// never a skeleton (heroes are swept on the floor plan: fly_bone_bolt).
BONE_BOLT_FILTER :: physics.Filter {
	category = CAT_ELITE,
	mask     = CAT_WALL | CAT_LOW | CAT_PROP,
}

// The Mage's way (`heading`) and where it looks (`look`; zero: along its heading): the path while its target is out of
// sight or past MAGE_FAR; away from it inside MAGE_NEAR, still facing it; between, it stands facing it.
mage_heading :: proc(t: ^Tick, floor: ^Floor, elite: ^Elite, spot: Nav_Point) -> (heading, look: [2]f32) {
	offset := sim.player_data(t, elite.target).pos.xz - elite.pos.xz
	distance := dmath.length(offset)
	if distance > MAGE_FAR || !elite_sees(t, elite, elite.target, MAGE_FAR) {
		return path_heading(t, floor, elite, spot), {}
	}
	look = dmath.normalize(offset)
	if distance < MAGE_NEAR do heading = open_heading(floor, spot, -look)
	return
}

// A chasing Mage with its target in sight within BONE_BOLT_RANGE summons once its summoning's clock ran out, else
// casts a bone bolt once its bolt's clock ran out, facing the target at once. Each cast is announced
// (Event_Elite_Cast).
mage_ready :: proc(t: ^Tick, elite: ^Elite, handle: sim.Handle(Elite)) {
	if !elite_sees(t, elite, elite.target, BONE_BOLT_RANGE) do return
	spell: Elite_Spell
	switch {
	case !sim.timer_running(t, elite.next_summon):
		elite.phase, elite.since = .Summon, t.time
		spell = .Summon
	case !sim.timer_running(t, elite.next_bolt):
		if to_hero := dmath.normalize(sim.player_data(t, elite.target).pos.xz - elite.pos.xz); to_hero != {} {
			elite.facing = to_hero
		}
		start_elite_attack(t, elite)
		sim.timer_start_ticks(t, &elite.next_bolt, BONE_BOLT_EVERY_TICKS)
		spell = .Bone_Bolt
	case:
		return
	}
	sim.emit(t, Event_Elite_Cast{elite = handle, position = sim.Position(elite.pos), spell = spell})
}

// The Mage's bolt leaves its hands at FLIGHT_HEIGHT, just clear of its capsule, along its facing (a full bolts table:
// it fizzles).
cast_bone_bolt :: proc(t: ^Tick, elite: ^Elite, handle: sim.Handle(Elite)) {
	bolt, _, spawned := sim.spawn(&t.state.bolts)
	if !spawned do return
	dir := [3]f32{elite.facing.x, 0, elite.facing.y}
	bolt^ = {
		pos      = elite.pos + {0, FLIGHT_HEIGHT, 0} + dir * (ELITE_RADIUS + BOLT_RADIUS),
		vel      = dir * BONE_BOLT_SPEED,
		cast_at  = t.time,
		by_elite = handle,
	}
}

// The Mage's summoning ends: up to SUMMON_COUNT minions rise on SUMMON_RING round it (the first ahead of it, the rest
// a turn's share on, each on the walkable floor), while fewer than the floor's cap are alive, the table has a row free
// and no population is held; then it chases again, its next summoning SUMMON_EVERY_S off.
mage_summons :: proc(t: ^Tick, elite: ^Elite) {
	floor := floor_of(t)
	for i in 0 ..< SUMMON_COUNT {
		if t.state.held > 0 ||
		   minions_alive(&t.state.minions) >= floor.minion_cap ||
		   free_rows(&t.state.minions) == 0 {
			break
		}
		dir := dmath.rotate2(elite.facing, f32(i) / SUMMON_COUNT)
		spot := floor_spot(floor, elite.pos + {dir.x, 0, dir.y} * SUMMON_RING, SUMMON_RING) or_continue
		spawn_minion(t.state, spot.point, spot.poly, dir, .Rise, t.time)
	}
	elite.phase, elite.since = .Chase, t.time
	sim.timer_start_ticks(t, &elite.next_summon, SUMMON_EVERY_TICKS)
}

// A bone bolt flies its tick's segment and bursts at the first hero up on it (its capsule's circle on the floor plan
// with the orb's radius) or the first wall, low cover or prop (BONE_BOLT_FILTER), or fizzles at BONE_BOLT_LIFE_S. A
// hero it meets takes the Mage's damage from where the bolt came.
fly_bone_bolt :: proc(t: ^Tick, bolt: ^Bolt, handle: sim.Handle(Bolt)) {
	if u32(t.time - bolt.cast_at) >= BONE_BOLT_LIFE_TICKS {
		sim.despawn(&t.state.bolts, handle)
		return
	}
	step := bolt.vel * t.dt
	reach: f32 = 1
	hit, struck := physics.world_cast_ray_closest(t.world.phys, bolt.pos, step, BONE_BOLT_FILTER)
	if struck do reach = hit.fraction
	victim: sim.Player
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		if !hero_up(t, player) do continue
		fraction, meets := segment_meets_circle(bolt.pos.xz, step.xz, hero.pos.xz, HERO_RADIUS + BOLT_RADIUS)
		if meets && fraction < reach do victim, reach = player, fraction
	}
	if victim == {} && !struck {
		bolt.pos += step
		return
	}
	at := bolt.pos + step * reach
	if victim != {} {
		damage_hero(t, victim, ELITE_SPECS[.Mage].damage, bolt.pos)
	} else {
		at -= dmath.normalize(bolt.vel) * BOLT_RADIUS // the ray met the world with the orb's centre
	}
	sim.emit(t, Event_Bolt_Burst{position = sim.Position(at), bone = true})
	sim.despawn(&t.state.bolts, handle)
}
