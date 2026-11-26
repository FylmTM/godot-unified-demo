// Ragdolls: a hero that goes down falls as a Box3D ragdoll, and gets up from it when revived. unified's
// physics.Ragdoll (twelve capsule bones on their joints, a plain struct in the block: Hero.ragdoll) is made standing
// where the hero stood, facing its way, as tall as its capsule (RAGDOLL_SCALE) and weighing RAGDOLL_MASS, moving at the
// hero's velocity plus RAGDOLL_KICK away from the blow, and physics takes it from there: it crumples, tumbles off a
// ledge, piles on another, lies where it comes to rest. Meanwhile the hero's capsule is dormant (no joints, nothing
// drives it) and out of the world (physics.body_disable: nothing meets it, no query finds it), left where it fell: a
// dormant capsule is still solid, so one kept on the pelvis would be an invisible post props and elites bounce off,
// and teleporting it there each tick would move its warp epoch on every tick (the view would never interpolate).
//
// While down, the hero's `pos` is its pelvis (read_back_ragdolls), so every rule that finds a downed hero by where it
// is (a revive's reach, the heave's cone, the camera) finds it where its body lies. Reviving it destroys the ragdoll
// and stands the capsule, back in the world and awake, on the walkable floor under the pelvis (stand_up).
//
// A ragdoll's bones meet everything but heroes and elites (RAGDOLL_FILTER): nobody trips over a fallen ally, an elite
// walks over one, a thrown prop knocks one about, and two fall on each other. Until milestone 6's last step makes the
// heave hold the ragdoll itself (docs/plan.md, Milestones), a Barbarian heaving a downed ally stands its capsule up
// first and heaves that, as before (barbarian.odin, heave); let down, it lies as that capsule until revived. The
// bones' names are given to the World's anchor before the first save (intern_ragdoll_names): a workaround that keeps
// a rolled-back world's hash its own.
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

// Whether the hero lies as a ragdoll (down, and neither heaved nor let down from a heave).
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

// Where a hero whose ragdoll's pelvis is at `pelvis` stands up, helped by a hero standing at `helper` (its reviver,
// or the Barbarian heaving it): the walkable floor nearest the floor under the pelvis (floor_under) within RAGDOLL_SNAP;
// else (floor_spot refuses a point a tomb's or a wall's top is nearer than the floor: a body on a wide tomb) the spot
// nearest it of the first of RAGDOLL_RINGS rings round it, RAGDOLL_RING apart, with one on the walkable floor (each
// within RAGDOLL_RING of its ring's point); else the floor at the helper's feet. Not ok with none of them, for a body
// gone where no helper stands near (stand_up then stands it at its spawn).
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

// `player`'s hero gets up from its ragdoll, if it lies as one, helped by `helper` (its reviver, the Barbarian heaving
// it; the nobody Player: none): the ragdoll goes, and its capsule stands at its standing_spot, or at its slot's
// hero_spawn with none (stand_capsule). Before that tick's move (revive_heroes, the dev revive, the heave), so the woken
// capsule's drive finds its ground in this tick's update.
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

// The names ragdoll_create gives a ragdoll's bones (Box3D body names): what intern_ragdoll_names names the World's
// anchor in turn. ragdolls_test.odin holds them to the names a ragdoll's bones get.
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

// Gives the World's anchor each bone's name in turn, then its own back, before the harness saves the world for the
// first time (world_create). A workaround (docs/plan.md, Needed from unified: body names in the world's hash): Box3D's
// canonical image, which the netcode's deep checksum hashes, keeps every name a body was ever given, and a snapshot's
// restore takes none back; so the first ragdoll after a save would leave its bones' names in a world rolled back to
// before it, and that world would hash otherwise than one that never saw it (a rollback, a late joiner and a replay
// all disagree on every deep checksum tick). Given here, on every peer's world before any save, the names are in every
// world from the start, and no ragdoll adds one. Renaming the anchor makes and frees no body, so every body after it
// is numbered as it would be without it.
intern_ragdoll_names :: proc(phys: ^physics.World) {
	anchor, _ := physics.resolve(phys, physics.world_anchor(phys))
	before: [64]u8 // a copy of its own name (a rename may free the one the anchor has), zero-terminated
	name := string(physics.body_name(phys, anchor))
	assert(len(name) < len(before), "crypt_crew: the anchor's name is longer than intern_ragdoll_names keeps")
	copy(before[:], name)
	for bone_name in RAGDOLL_BONE_NAMES do physics.body_set_name(phys, anchor, bone_name)
	physics.body_set_name(phys, anchor, cstring(&before[0]))
}

// After the physics step (and read_back_heroes, which leaves a ragdolled hero alone): each ragdolled hero's `pos` and
// `vel`, its pelvis's. A ragdoll fallen RAGDOLL_KILL_DEPTH below the floor's navigation mesh has left the level: it
// goes, and its hero, still down, lies as its capsule at its slot's hero_spawn, where an ally can revive it.
read_back_ragdolls :: proc(t: ^Tick) {
	heroes := sim.iterate_present(t)
	for hero, player in sim.next(&heroes) {
		if !ragdolled(hero) do continue
		read_back_ragdoll(t.world.phys, hero)
		if hero.pos.y >= floor_of(t).lowest - RAGDOLL_KILL_DEPTH do continue
		physics.ragdoll_destroy(t.world.phys, &hero.ragdoll)
		stand_capsule(t.world.phys, hero, floor_of(t).places.hero_spawns[sim.player_slot(t, player)])
	}
}

// The hero's `pos` and `vel` from its ragdoll's pelvis.
@(private = "file")
read_back_ragdoll :: proc(phys: ^physics.World, hero: ^Hero) {
	pelvis := hero.ragdoll.bones[.Pelvis]
	hero.pos = physics.body_position(phys, pelvis)
	hero.vel = physics.body_linear_velocity(phys, pelvis)
}
