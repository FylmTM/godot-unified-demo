// The state block: everything tick reads across ticks, one pointer-free, padding-free struct (checked by sim.create)
// that a snapshot copies and the checksum hashes. Kept anywhere else (the World, a package variable), it would desync
// after a rollback (unified/docs/gameplay.md).
package crypt_crew

import "unified:physics"
import "unified:sim"

// The whole simulation state.
State :: struct {
	clock:        sim.Clock, // game time and the co-op pause (pause.odin): the harness advances it unless paused
	level:        sim.Active_Level(Level_Id), // the floor the party is on (world.odin)
	players:      sim.Players(Hero, Profile, Input, PLAYERS),
	props:        sim.Table(Prop, MAX_PROPS), // made from the floor's prop markers, in marker order (props.odin)
	minions:      sim.Table(Minion, MAX_MINIONS), // the skeletons, rows with no body (minions.odin)
	bolts:        sim.Table(Bolt, MAX_BOLTS), // the Mage's bolts in flight (bolts.odin)
	fireballs:    sim.Table(Fireball, MAX_FIREBALLS), // the Mage's fireballs in flight (fireballs.odin)
	surge:        sim.Timer, // the next surge rises when it runs out (director.odin)
	wipe:         sim.Timer, // every hero present is down: the floor starts over when it runs out (health.odin)
	surges:       u32, // the surges the party has faced, a save's included (Event_Surge's count)
	rises:        u32, // the minions the director raised this session: what each one's rolls are named by
	// The minions a held population keeps alive (a held crowd, a benchmark's; 0: the director's surges, as in play).
	held:         u32,
	kills:        u32, // the skeletons the party has felled, a save's included
	saved_kills:  u32, // `kills` when the last surge rose: what the save holds (saves.odin)
	paused_by:    sim.Player, // who paused the game for everyone (pause.odin; {}: nobody, or it runs)
	rising:       u32, // the minions the last surges still owe: they rise a few a tick (director.odin)
	// The surges faced since the party last entered the floor (a wipe's restart and a Continue enter it anew): what
	// a surge's growth counts.
	floor_surges: u32,
	saved_floor:  Level_Id, // the floor the party was on when the last surge rose: what the save holds
	_pad:         [7]u8,
	// Elites (elites.odin): the skeleton Warriors, Rogues and Mages, each a Box3D character.
	elites:       sim.Table(Elite, MAX_ELITES),
	// ---- loot (loot.odin)
	loot:         sim.Table(Loot, MAX_LOOT), // the coins on the floor
	gold:         u32, // the party's purse: the gold of every coin it picked up, a save's included
	saved_gold:   u32, // `gold` when the last surge rose: what the save holds (saves.odin)
	drops:        u32, // the drop rolls made this session (felled minions): what each one's rolls are named by
	_pad_loot:    u32,
	// ---- mechanisms (plates.odin, gates.odin, barricades.odin, traps.odin): each table made from the floor's markers
	// of its kind when the party enters it, in marker order, so a row's index is its marker's in the floor's Places
	plates:       sim.Table(Plate, MAX_PLATES),
	gates:        sim.Table(Gate, MAX_GATES),
	barricades:   sim.Table(Barricade, MAX_BARRICADES),
	traps:        sim.Table(Trap, MAX_TRAPS),
	// ---- the hoard, the lift and boons (hoard.odin, lift.odin, boons.odin)
	hoard:        Hoard, // the floor's gold chest
	lift:         Lift, // the floor's exit
	depth:        u32, // the floors the party has gone down this run, a save's included
	saved_depth:  u32, // `depth` at the last save point (a surge's rise, the descent): what the save holds
	_pad_depth:   u32,
}

// What a hero is doing, for the view to pose (a one-shot clip at its age).
Action :: enum u8 {
	None, // walking or standing: the view picks its gait from the velocity
	Pick_Up, // a grab, for PICK_UP_S
	Throw, // a throw, for THROW_S: the prop leaves the hands THROW_WINDUP_S into it
	Down, // at 0 HP, held still, until an ally revives it (health.odin, revive.odin)
	Attack, // its class's attack, for its spec's duration: the blow lands its windup into it (attacks.odin)
	// The abilities (abilities.odin) and the revive (revive.odin).
	Block, // the Knight's shield raised, while Ability is held
	Charge, // the Knight's shield charge, for CHARGE_S
	Roll, // the Rogue's dodge roll, for ROLL_S
	Cast, // the Mage's fireball winding up, for FIREBALL_WINDUP_S: it leaves at the end
	Revive, // tending a downed ally, while Interact is held beside it
	// The Barbarian's heave (barbarian.odin): an elite or a downed ally held on its hold, then thrown.
	Heave, // holding a body up, for at most HEAVE_MAX_S
	Hurl, // throwing it, for THROW_S: it leaves the hands THROW_WINDUP_S into it
	// The hoard (hoard.odin)
	Haul, // holding a handle of the hoard (Hero.handle), until it lets go
}

// A player's hero (the State's sim.Players, by member): zeroed for someone new, kept while they are away. A leave
// destroys its body and keeps only its class and its warp epoch (presence.odin), so whoever comes back plays what they
// played, and their view snaps to where they arrive.
Hero :: struct {
	body:           physics.Character, // zero while absent
	pos:            [3]f32, // its feet, read back after the physics step (read_back_heroes)
	vel:            [3]f32, // its body's velocity, read back with `pos`
	facing:         [2]f32, // unit (x, z): where it looks
	hold:           physics.Motor_Joint_Ref, // the joint holding `held` (hands.odin) or `heaved` in front of it
	held:           sim.Handle(Prop), // the prop it carries (the null handle: none)
	heaved:         Heaved, // a Barbarian's: the body it holds up on its hold (barbarian.odin)
	heaved_by:      sim.Player, // while down and heaved (`heave`): the Barbarian holding it, or who threw it
	ability_ready:  sim.Timer, // no ability starts while it runs (its own cooldown: abilities.odin)
	grace:          sim.Timer, // after a revive: no damage while it runs
	attack_ready:   sim.Timer, // no attack starts while it runs (its class's cooldown)
	action_started: sim.Game_Time, // when `action` began (t.time): the view's clip time
	heave_since:    sim.Game_Time, // when `heave` began: a thrown body lands at the latest HEAVE_FLIGHT_MAX_S after it
	hp:             i16,
	// While down: how far its revive has come, in REVIVE_UNITs (REVIVE_FULL: up again; revive.odin).
	revive:         u16,
	class:          Class, // Any only before its first arrival
	action:         Action,
	// The hero's own warp epoch, which outlives its bodies: a body's (physics.body_warp) starts at 0 when it is made
	// again, so this one takes the old body's count and one more for each new body. The view's epoch is the two added
	// (hero_warp): a teleport of the body bumps the body's, a new body this one.
	warp:           u8,
	heave:          Heave_Phase, // while down: held up by a Barbarian, or thrown by one (barbarian.odin)
	// ---- ragdolls (ragdolls.odin)
	// While down: the ragdoll it lies as (zero: none, and always none while up), its capsule dormant and out of the
	// world meanwhile. Freed on every path that frees the body (destroy_hero_body: a leave, a level change).
	ragdoll:        physics.Ragdoll,
	// ---- the hoard and boons (hoard.odin, boons.odin)
	picked:         u32, // the depth it last picked a boon at, plus one (0: never): a pick counts once a depth
	boons:          Boons, // its rank in each boon, kept through a leave and a wipe
	handle:         Haul_Handle, // the hoard's handle it holds, on `hold` (None: none)
	_pad:           u8,
}
