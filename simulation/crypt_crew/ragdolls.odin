// Ragdolls: a hero that goes down falls as a Box3D ragdoll, and gets up from it when revived. unified's physics.Ragdoll
// (twelve capsule bones on their joints, a plain struct in the block: Hero.ragdoll) is made standing where the hero
// stood, facing its way, as tall as its capsule (RAGDOLL_SCALE) and weighing RAGDOLL_MASS, moving at the hero's
// velocity plus RAGDOLL_KICK away from the blow, and physics takes it from there: it crumples, tumbles off a ledge,
// piles on another, lies where it comes to rest, and sleeps as soon as it is still there (settle_ragdolls: an awake
// ragdoll is a dozen jointed bodies in every step and every re-sim). Meanwhile the hero's capsule is dormant (no
// joints, nothing drives it) and out of the world (physics.body_disable: nothing meets it, no query finds it), left
// where it fell: a dormant capsule is still solid, so one kept on the pelvis would be an invisible post props and
// elites bounce off, and teleporting it there each tick would move its warp epoch on every tick (the view would never
// interpolate).
//
// While down, the hero's `pos` is its pelvis (read_back_ragdolls), so every rule that finds a downed hero by where it
// is (a revive's reach, the heave's cone, the camera) finds it where its body lies. Reviving it destroys the ragdoll
// and stands the capsule, back in the world and awake, on the walkable floor under the pelvis (stand_up).
//
// A ragdoll's bones meet everything but heroes and elites (RAGDOLL_FILTER): nobody trips over a fallen ally, an elite
// walks over one, a thrown prop, a fireball's blast (fireballs.odin) or the roller knocks one about, two fall on each
// other, and one weighs a plate down. A hero is down exactly while it lies as a ragdoll: a Barbarian heaving it holds
// the ragdoll by its chest bone and throws it whole (barbarian.odin), and a body fallen out of the level is laid anew
// at its spawn.
package crypt_crew

import "unified:dmath"
import "unified:physics"
import "unified:sim"

// A ragdoll bone's filter: CAT_RAGDOLL, meeting every category but the heroes' and the elites' (the floor, walls, low
// cover, props, other ragdolls and its own bones that no filter joint keeps apart, and every category a level or a
// later system adds).
RAGDOLL_FILTER :: physics.Filter {
	category = CAT_RAGDOLL,
	mask     = ~(CAT_HERO | CAT_ELITE),
}

// Whether the hero lies as a ragdoll: down (every hero down does, heaved or not).
ragdolled :: proc(hero: ^Hero) -> bool {
	return hero.ragdoll.bones[.Pelvis] != {}
}

// A hero's ragdoll: RAGDOLL_SCALE tall, limp (RAGDOLL_HERTZ) with RAGDOLL_FRICTION_TORQUE in its joints, in
// RAGDOLL_FILTER, its density what weighs it RAGDOLL_MASS: the mass of its capsules at unit density, a foot's at half
// (as ragdoll_create makes them), summed in bone order, so every platform adds the same f32s.
ragdoll_def :: proc() -> physics.Ragdoll_Def {
	def := physics.RAGDOLL_DEFAULT
	def.scale = RAGDOLL_SCALE
	def.hertz = RAGDOLL_HERTZ
	def.friction_torque = RAGDOLL_FRICTION_TORQUE
	def.category, def.mask = RAGDOLL_FILTER.category, RAGDOLL_FILTER.mask
	unit_mass: f32
	for bone in physics.Ragdoll_Bone {
		capsules, count := physics.ragdoll_capsules(bone, RAGDOLL_SCALE)
		unit_mass += physics.compute_capsule_mass(capsules[0], 1).mass
		if count > 1 do unit_mass += physics.compute_capsule_mass(capsules[1], 0.5).mass
	}
	def.density = RAGDOLL_MASS / unit_mass
	return def
}

// `player`'s hero, down, falls as a ragdoll: its capsule goes dormant and out of the world where it is, and a ragdoll
// stands in its place (ragdoll_rest_pose on its feet, facing its way), its bones tagged with the player's key as the
// capsule is, moving at the hero's velocity (at most RAGDOLL_CARRY_MAX of it) plus `kick`; the hero's `pos` and `vel`
// are its pelvis's from now on.
ragdoll_hero :: proc(t: ^Tick, player: sim.Player, kick: [3]f32) {
	hero := sim.player_data(t, player)
	phys := t.world.phys
	physics.character_set_dormant(phys, &hero.body, true)
	physics.body_disable(phys, hero.body.body)
	physics.ragdoll_create(
		phys,
		&hero.ragdoll,
		ragdoll_def(),
		hero.pos,
		dmath.quat_yaw(hero.facing),
		tag = sim.player_key(player),
	)
	hero.still = 0
	carried := hero.vel
	if speed := dmath.length(carried); speed > RAGDOLL_CARRY_MAX do carried *= RAGDOLL_CARRY_MAX / speed
	physics.ragdoll_set_velocity(phys, &hero.ragdoll, carried + kick)
	read_back_ragdoll(phys, hero)
}

// What a blow from `from` gives the ragdoll of the hero it downs at `feet`, facing `facing`: RAGDOLL_KICK along the
// floor, away from the blow; from right where the hero stands (a blow from no side: a dev hurt, a rejoin while down),
// RAGDOLL_TIP backwards, so the body topples at once rather than stand a moment balanced on its feet.
ragdoll_kick :: proc(feet, from: [3]f32, facing: [2]f32) -> [3]f32 {
	if away := dmath.normalize(feet.xz - from.xz); away != {} do return {away.x, 0, away.y} * RAGDOLL_KICK
	return {-facing.x, 0, -facing.y} * RAGDOLL_TIP
}

// What finds the floor under a ragdoll's pelvis: the floor alone, through a tomb's top or a wall it lies on or in.
FLOOR_FILTER :: physics.Filter {
	category = CAT_RAGDOLL,
	mask     = CAT_FLOOR,
}

// The floor under `pelvis`: where FLOOR_FILTER's ray down meets it within RAGDOLL_FLOOR_BELOW (through a tomb's top or
// a wall the body lies on or in); `pelvis` itself with none there. Also where the view lays a downed hero's ring.
floor_under :: proc(phys: ^physics.World, pelvis: [3]f32) -> [3]f32 {
	hit, found := physics.world_cast_ray_closest(phys, pelvis, {0, -RAGDOLL_FLOOR_BELOW, 0}, FLOOR_FILTER)
	return hit.point if found else pelvis
}

// Where a hero whose ragdoll's pelvis is at `pelvis` stands up, helped by a hero standing at `helper` (its reviver):
// the walkable floor nearest the floor under the pelvis (floor_under) within RAGDOLL_SNAP;
// else (floor_spot refuses a point a tomb's or a wall's top is nearer than the floor: a body on a wide tomb) the spot
// nearest it of the first of RAGDOLL_RINGS rings round it, RAGDOLL_RING apart, with one on the walkable floor (each
// within RAGDOLL_RING of its ring's point); else the floor at the helper's feet. Not ok with none of them, for a body
// gone where no helper stands near (stand_up then stands it at its spawn).
@(private = "file")
standing_spot :: proc(t: ^Tick, pelvis, helper: [3]f32) -> (feet: [3]f32, ok: bool) {
	floor := floor_of(t)
	under := floor_under(t.world.phys, pelvis)
	if spot, on_floor := floor_spot(floor, under, RAGDOLL_SNAP); on_floor do return spot.point, true
	for ring in 1 ..= RAGDOLL_RINGS {
		nearest := max(f32)
		for dir in dmath.DIR8 {
			at := under + [3]f32{dir.x, 0, dir.y} * (f32(ring) * RAGDOLL_RING)
			spot := floor_spot(floor, at, RAGDOLL_RING) or_continue
			if apart := dmath.length(spot.point.xz - under.xz); apart < nearest do feet, nearest = spot.point, apart
		}
		if nearest < max(f32) do return feet, true
	}
	if spot, on_floor := floor_spot(floor, helper, HERO_NAV_REACH); on_floor do return spot.point, true
	return {}, false
}

// `player`'s hero gets up from its ragdoll, if it lies as one, helped by `helper` (its reviver; the nobody Player:
// none): the ragdoll goes, and its capsule stands at its standing_spot, or at its slot's hero_spawn with none
// (stand_capsule). Before that tick's move (revive_heroes, the dev revive), so the woken capsule's drive finds its
// ground in this tick's update.
stand_up :: proc(t: ^Tick, player: sim.Player, helper: sim.Player) {
	hero := sim.player_data(t, player)
	if !ragdolled(hero) do return
	helped := hero.pos
	if sim.player_present(t, helper) do helped = sim.player_data(t, helper).pos
	feet, found := standing_spot(t, hero.pos, helped)
	if !found do feet = floor_of(t).places.hero_spawns[sim.player_slot(t, player)]
	physics.ragdoll_destroy(t.world.phys, &hero.ragdoll)
	stand_capsule(t.world.phys, hero, feet)
}

// The hero's capsule, dormant and out of the world while it lay as a ragdoll, back in the world and awake, standing at
// a standstill on `feet`; its view snaps there (the teleport moves the body's warp epoch on).
@(private = "file")
stand_capsule :: proc(phys: ^physics.World, hero: ^Hero, feet: [3]f32) {
	physics.body_enable(phys, hero.body.body)
	physics.character_teleport(phys, &hero.body, feet + {0, HERO_CENTRE_ABOVE_FEET, 0})
	physics.character_set_dormant(phys, &hero.body, false)
	hero.pos, hero.vel = feet, {}
}

// The names ragdoll_create gives a ragdoll's bones (Box3D body names), which debug draws and traces show:
// ragdolls_test.odin holds them to the names a ragdoll's bones get.
@(rodata)
RAGDOLL_BONE_NAMES := [physics.Ragdoll_Bone]cstring {
	.Pelvis          = "pelvis",
	.Spine           = "spine",
	.Chest           = "chest",
	.Head            = "head",
	.Left_Thigh      = "left thigh",
	.Left_Calf       = "left calf",
	.Right_Thigh     = "right thigh",
	.Right_Calf      = "right calf",
	.Left_Upper_Arm  = "left upper arm",
	.Left_Forearm    = "left forearm",
	.Right_Upper_Arm = "right upper arm",
	.Right_Forearm   = "right forearm",
}

// After the physics step (and read_back_heroes, which leaves a ragdolled hero alone): each ragdolled hero's `pos` and
// `vel`, its pelvis's. A ragdoll fallen RAGDOLL_KILL_DEPTH below the floor's navigation mesh has left the level: it
// goes (a Barbarian heaving it lets go first), and its hero, still down, lies as a ragdoll laid anew at its slot's
// hero_spawn (tipped backwards, as from a blow from no side), where an ally can revive it.
read_back_ragdolls :: proc(t: ^Tick) {
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		if !ragdolled(hero) do continue
		read_back_ragdoll(t.world.phys, hero)
		if hero.pos.y >= floor_of(t).lowest - RAGDOLL_KILL_DEPTH do continue
		end_hero_heave(t, player)
		physics.ragdoll_destroy(t.world.phys, &hero.ragdoll)
		hero.pos, hero.vel = floor_of(t).places.hero_spawns[sim.player_slot(t, player)], {}
		ragdoll_hero(t, player, ragdoll_kick(hero.pos, hero.pos, hero.facing))
	}
}

// After read_back_ragdolls: each awake ragdoll come to rest (every bone still, RAGDOLL_STILL_TICKS in a row) on nothing
// but the level sleeps at once, without the half second Box3D's own sleep waits out. Sleep is an island's: one touching
// another body (a prop, another ragdoll, the lift's deck) is left to Box3D, so nothing it touches stops mid-move. One a
// Barbarian heaves is never still (its hold's spring swings it), nor one in flight. A sleeping ragdoll wakes as any
// body does, when something meets it.
settle_ragdolls :: proc(t: ^Tick) {
	phys := t.world.phys
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		if !ragdolled(hero) || !physics.body_is_awake(phys, hero.ragdoll.bones[.Pelvis]) do continue
		if !ragdoll_still(phys, &hero.ragdoll) {
			hero.still = 0
			continue
		}
		if hero.still < RAGDOLL_STILL_TICKS do hero.still += 1
		if hero.still < RAGDOLL_STILL_TICKS || !ragdoll_alone(t, player) do continue
		physics.body_set_awake(phys, hero.ragdoll.bones[.Pelvis], false)
		hero.still = 0
	}
}

// Whether every bone of the ragdoll moves slower than RAGDOLL_STILL_SPEED and turns slower than RAGDOLL_STILL_SPIN.
@(private = "file")
ragdoll_still :: proc(phys: ^physics.World, ragdoll: ^physics.Ragdoll) -> bool {
	for bone in ragdoll.bones {
		if dmath.length_sq(physics.body_linear_velocity(phys, bone)) >= RAGDOLL_STILL_SPEED * RAGDOLL_STILL_SPEED do return false
		if dmath.length_sq(physics.body_angular_velocity(phys, bone)) >= RAGDOLL_STILL_SPIN * RAGDOLL_STILL_SPIN do return false
	}
	return true
}

// Whether `player`'s ragdoll touches nothing but itself (its bones carry the player's key) and static bodies (the
// level): its island is its own, so putting it to sleep sleeps nothing else. Its joints are all its own but a heave's
// hold, and a held ragdoll is never still (settle_ragdolls).
@(private = "file")
ragdoll_alone :: proc(t: ^Tick, player: sim.Player) -> bool {
	phys := t.world.phys
	key := sim.player_key(player)
	for bone in sim.player_data(t, player).ragdoll.bones {
		physics.body_contact_data(phys, bone, &t.world.touching)
		for &contact in t.world.touching {
			for side in ([2]physics.Overlap{contact.a, contact.b}) {
				if side.tag == key && side.category & CAT_RAGDOLL != 0 do continue
				body := physics.resolve(phys, side.body) or_return
				if physics.body_type(phys, body) != .Static do return false
			}
		}
	}
	return true
}

// The hero's `pos` and `vel` from its ragdoll's pelvis.
@(private = "file")
read_back_ragdoll :: proc(phys: ^physics.World, hero: ^Hero) {
	pelvis := hero.ragdoll.bones[.Pelvis]
	hero.pos = physics.body_position(phys, pelvis)
	hero.vel = physics.body_linear_velocity(phys, pelvis)
}
