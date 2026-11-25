// Every rule number of the game, in metres, seconds and hit points: the one place a designer tunes. A time is written
// in seconds and converted to whole ticks at compile time (`X_TICKS :: u32(X_S * TICK_HZ)`). A level's own numbers are
// its markers' properties (game/levels/markers/).
package crypt_crew

// ---- sizes: the most of each kind of marker the World keeps from a level

MAX_GRAVES :: 16
MAX_PACKS :: 8
MAX_PROPS :: 32
MAX_FIELDS :: 8 // memoized navigation fields: one per hero chased, a few to spare
// Minion rows, the dying included: the most alive and the dying of a fight felling 70 a second for DEATH_S.
MAX_MINIONS :: 640
MINION_CAP :: 500 // the most minions alive (not dying) any floor holds: a floor's own cap is its CROWD_DENSITY's
CROWD_DENSITY :: f32(0.4) // a floor's minion cap per square metre of walkable floor (Floor.minion_cap)

// ---- heroes

HERO_RADIUS :: f32(0.45)
HERO_HEIGHT :: f32(2.2) // the capsule, end to end: a KayKit hero is about 2.4 m to the top of its hood or helmet
HERO_HALF_HEIGHT :: HERO_HEIGHT / 2 - HERO_RADIUS // the capsule's segment half length
// The pogo spring holds the capsule's lower sphere centre this high, so its bottom floats a hand above the floor and a
// low step slides under it.
HERO_POGO_REST :: f32(0.6)
HERO_CENTRE_ABOVE_FEET :: HERO_HALF_HEIGHT + HERO_POGO_REST // from the capsule's centre down to the floor it stands on
// A hero weighs about 80 kg, and its drive's force cap accelerates it at 50 m/s²: full speed from a standstill, or a
// turn about, in about a tenth of a second, so a hero answers its stick at once.
HERO_DENSITY :: f32(66) // kg/m³ of its capsule (about 1.2 m³)
HERO_GROUND_FORCE :: f32(4000) // newtons: the most the drive pushes with
HERO_ACCELERATE :: f32(20) // how fast the drive's target velocity closes on the stick's, in max speeds per second
HERO_HP :: i16(100)
HERO_NAV_REACH :: f32(1.5) // a hero's place on the navigation mesh is the mesh's nearest point within this
RESPAWN_S :: f32(4) // a hero at 0 HP stays down this long, then rises beside the party
RESPAWN_TICKS :: u32(RESPAWN_S * TICK_HZ)
SPAWN_GRACE_S :: f32(2) // a hero who rises takes no damage this long
SPAWN_GRACE_TICKS :: u32(SPAWN_GRACE_S * TICK_HZ)
TURN_STICK :: f32(0.1) // a hero without an aim turns to its move once the stick is pushed further than this

// What a class plays like (CLASS_SPECS).
Class_Spec :: struct {
	max_speed:  f32, // metres per second at a full stick
	// Its attack (attacks.odin): the clip starts at once and the blow lands `windup` ticks later; the attack's action
	// lasts `duration`, and the next may start `cooldown` after this one started.
	windup:     u32,
	duration:   u32,
	cooldown:   u32,
	reach:      f32, // melee: from the hero's centre to a minion's side (metres)
	arc_cos:    f32, // melee: the cosine of the arc's half angle either side of the facing (no trig in the sim)
	damage:     i16, // what the blow, the bolt or the crossbow bolt takes from a minion
	knock:      f32, // the knockback it gives (metres per second)
	prop_knock: f32, // what it gives a prop in its way (metres per second of velocity change)
}

// Each class's numbers. `Any` is a Profile's wish only: a hero's class is resolved on arrival (presence.odin), so no
// hero plays its zero entry. The Knight's sword is quick and narrow; the Barbarian's cleave slow, wide and heavy; the
// Mage's bolt (bolts.odin) and the Rogue's crossbow (rogue.odin) reach far, so their reach and arc go unread.
@(rodata)
CLASS_SPECS := #partial [Class]Class_Spec {
	.Knight = {
		max_speed  = 5,
		windup     = u32(0.25 * TICK_HZ),
		duration   = u32(0.5 * TICK_HZ),
		cooldown   = u32(0.5 * TICK_HZ),
		reach      = 1.8,
		arc_cos    = 0.6427876, // 50°
		damage     = 18,
		knock      = 5,
		prop_knock = 3,
	},
	.Barbarian = {
		max_speed  = 4.5,
		windup     = u32(0.4375 * TICK_HZ),
		duration   = u32(0.875 * TICK_HZ),
		cooldown   = u32(1 * TICK_HZ),
		reach      = 2.3,
		arc_cos    = 0.17364818, // 80°
		damage     = 30,
		knock      = 9,
		prop_knock = 6,
	},
	.Mage = {
		max_speed  = 4.75,
		windup     = u32(0.25 * TICK_HZ),
		duration   = u32(0.5 * TICK_HZ),
		cooldown   = u32(0.625 * TICK_HZ),
		damage     = 20,
		knock      = 3,
		prop_knock = 4,
	},
	.Rogue = {
		max_speed  = 5.5,
		windup     = u32(0.1875 * TICK_HZ),
		duration   = u32(0.625 * TICK_HZ),
		cooldown   = u32(0.75 * TICK_HZ),
		damage     = 30,
		knock      = 3,
		prop_knock = 3,
	},
}
ATTACK_SPEED :: f32(0.6) // a hero attacking moves at this fraction of its speed
CHEST_HEIGHT :: f32(1.2) // where a blow looks from, and what it strikes is looked at, above the feet (walls shield)
// Something touching a hero (its circle within this of the hero's capsule) is struck by its blow in any direction.
STRIKE_TOUCH :: f32(0.15)

// What flies over what: bolts and shots fly FLIGHT_HEIGHT above the floor, so a bolt's orb (BOLT_RADIUS) clears low
// cover (its colliders' tops at most LOW_COVER_TOP, game/tools/art_checks.gd holds the kit to it) and resting light
// props by FLIGHT_CLEARANCE, and meets everything that stands chest-high: walls, heavy crates, a held or flying prop,
// a minion (swept on the floor plan, whatever its height).
FLIGHT_HEIGHT :: f32(1.35)
LOW_COVER_TOP :: f32(1.1)
FLIGHT_CLEARANCE :: f32(0.05)
#assert(FLIGHT_HEIGHT - BOLT_RADIUS >= LOW_COVER_TOP + FLIGHT_CLEARANCE)

// The Mage's bolt (bolts.odin): a row flying straight, swept against minions and the world every tick.
MAX_BOLTS :: 32
BOLT_SPEED :: f32(14) // metres per second along the facing
BOLT_RADIUS :: f32(0.2) // what it hits with (its orb's radius)
BOLT_LIFE_S :: f32(1.5) // it fizzles this long after its cast (21 m)
BOLT_LIFE_TICKS :: u32(BOLT_LIFE_S * TICK_HZ)
BURST_RADIUS :: f32(1.5) // its burst hurts every other minion this close to where it hit ...
BURST_DAMAGE :: i16(8) // ... this much
BURST_KNOCK :: f32(4) // ... and knocks it away this fast

// The Rogue's crossbow (rogue.odin): a hitscan shot where the shooter saw the target.
CROSSBOW_RANGE :: f32(25)
MAX_REWIND_S :: f32(0.125) // the most a shot looks back for what its shooter saw (sim.seen_rewind)

// A thrown prop (props.odin, prop_hits): faster than PROP_HIT_SPEED, it hurts each minion it meets once.
PROP_HIT_SPEED :: f32(4)
PROP_HIT_DAMAGE :: i16(25)
PROP_HIT_KNOCK :: f32(7)
PROP_HIT_KEEP :: f32(0.7) // what a hit leaves of the prop's velocity
PROP_HITS_MAX :: 6 // the most minions one throw hurts

// ---- the world

GRAVITY :: f32(10) // Box3D's default, |g| (metres per second squared, down)
// Contacts approaching slower than this report no hit (Settings.hit_event_threshold): a prop's thud (Event_Prop_Impact)
// is a landing or a crash, never a prop settling or nudged along.
IMPACT_SPEED :: f32(3)

// ---- props: carried and thrown

// A prop's shape: the KayKit model's box, or the barrel's cylinder.
Prop_Shape :: enum u8 {
	Box,
	Cylinder,
}

// What a kind of prop is (PROP_SPECS).
Prop_Spec :: struct {
	half:        [3]f32, // its half extents, measured from its model (a cylinder: its radius in x and z)
	mass:        f32, // kilograms
	carry_speed: f32, // its carrier's speed, as a fraction of their class's max_speed
	footprint:   f32, // the circle minions are pushed out of (metres): a box's reaches between its sides and corners
	shape:       Prop_Shape,
}

// Each kind of prop, its size measured from its model (assets/kaykit/dungeon/: barrel_small, box_small, box_large).
@(rodata)
PROP_SPECS := [Prop_Kind]Prop_Spec {
	.Barrel = {half = {0.5, 0.509, 0.5}, mass = 30, carry_speed = 0.85, footprint = 0.5, shape = .Cylinder},
	.Crate = {half = {0.5, 0.5, 0.5}, mass = 20, carry_speed = 0.85, footprint = 0.6, shape = .Box},
	.Heavy_Crate = {half = {0.75, 0.75, 0.75}, mass = 60, carry_speed = 0.65, footprint = 0.9, shape = .Box},
}

PROP_FRICTION :: f32(0.6)
PROP_RESTITUTION :: f32(0.1)
PROP_CYLINDER_SIDES :: 12 // the barrel's hull: a 12-sided cylinder

// Grabbing: Interact's press takes the nearest free prop in a cone in front of the hero (hands_target).
GRAB_RANGE :: f32(1) // the most from the hero's capsule to the prop's side, on the floor
GRAB_CONE_COS :: f32(0.6427876) // a cone of 50° either side of the facing (cos 50°)
GRAB_ANYWHERE :: f32(0.25) // a prop this close is in reach in any direction
GRAB_HEIGHT :: f32(2.5) // a prop whose centre is more than this above the hero's feet (or below them) is out of reach

// Holding: a motor joint holds the prop's centre in front of the hero at chest height (a heavy crate's top stays
// under the doorway's lintel, 2.75 m).
HOLD_HEIGHT :: f32(1.4) // the prop's centre above the hero's feet
HOLD_GAP :: f32(0.1) // between the hero's capsule and the prop's near side
HOLD_LIFT :: f32(3) // the hold's force cap, in multiples of the prop's weight
HOLD_TORQUE_PER_KG :: f32(20) // the hold's torque cap per kilogram, keeping the prop upright and turned with the hero
HOLD_HERTZ :: f32(6) // the hold's spring, linear and angular
HOLD_DAMPING :: f32(1)

// Throwing: Attack's press while holding starts a throw, which lets go THROW_WINDUP_S into it.
THROW_SPEED :: f32(11) // metres per second along the facing, set as a velocity so every mass flies alike
THROW_LIFT :: f32(3.5) // metres per second up on top
THROW_WINDUP_S :: f32(0.25)
THROW_WINDUP_TICKS :: u32(THROW_WINDUP_S * TICK_HZ)
THROW_S :: f32(0.5) // the throw's action, windup included
THROW_TICKS :: u32(THROW_S * TICK_HZ)
THROWN_S :: f32(1) // a thrown prop is its thrower's this long (Prop.thrown)
THROWN_TICKS :: u32(THROWN_S * TICK_HZ)
THROW_CLEAR_DIST :: f32(2.5) // a thrown prop passes through its thrower until this far from them (or `thrown` ends)
PICK_UP_S :: f32(0.625) // the grab's action
PICK_UP_TICKS :: u32(PICK_UP_S * TICK_HZ)
PROP_REST_SPEED :: f32(1) // a prop slower than this (or held) is in minions' way; a faster one flies through them

// ---- minions: skeletons walking the navigation mesh, rows with no body

MINION_RADIUS :: f32(0.4)
MINION_HEIGHT :: f32(1.8) // a thrown prop whose bottom flies higher than this above a minion's feet passes over it
MINION_SPEED :: f32(3.2) // metres per second chasing
MINION_HP :: i16(30)
MINION_REACH :: f32(0.8) // a minion strikes a hero whose capsule is this close to its own circle
MINION_DAMAGE :: i16(10)
MINION_STRIKE_COS :: f32(0.5) // and in front of it: within 60° of the facing its attack locked (cos 60°)
MINION_WINDUP_S :: f32(0.5) // an attack's telegraph: the swing lands this long after it starts
MINION_WINDUP_TICKS :: u32(MINION_WINDUP_S * TICK_HZ)
MINION_ATTACK_S :: f32(1) // the whole attack, its recovery included, before it chases again
MINION_ATTACK_TICKS :: u32(MINION_ATTACK_S * TICK_HZ)
RISE_S :: f32(1.5) // a risen minion climbs out of the floor this long, harmless, before it chases
RISE_TICKS :: u32(RISE_S * TICK_HZ)
DEATH_S :: f32(2) // a dead minion's row lingers this long (Dying: its fall), then is freed
DEATH_TICKS :: u32(DEATH_S * TICK_HZ)
RETARGET_S :: f32(0.25) // each minion picks its target again this often (time-sliced by its index, sim.due)
RETARGET_TICKS :: u32(RETARGET_S * TICK_HZ)
SEPARATION :: f32(0.9) // minions closer than this push apart ...
SEPARATION_SPEED :: f32(2.5) // ... at up to this speed
KNOCK_DECAY :: f32(6) // a knockback's velocity decays at this rate per second
// The minion grid's cells (metres): at least SEPARATION and the longest reach a query asks of its 3 by 3 cells (a
// Barbarian's cleave and a minion's radius); world_create lays it over a mesh.
MINION_GRID_CELL :: f32(3)
MINION_GRID_CELLS :: 1024 // the most cells it may need: a level's mesh up to 96 m by 96 m

// ---- the director: sleeping packs, and surges rising from graves

MAX_PACK_MINIONS :: 64 // the most sleeping minions a level's packs place
PACK_SPACING :: f32(1) // a pack's minions stand on rings this far apart (more than SEPARATION, so they never shuffle)
PACK_SNAP :: f32(0.3) // a pack's spot moves at most this far onto the floor (a level whose pack doesn't fit fails)
PACK_TURNS :: 12 // the turns of a pack's rings tried, in order, until its members fit (pack_places)
AGGRO_RADIUS :: f32(9) // a sleeping minion wakes (and its pack with it) when a hero it can see comes this close
SIGHT_S :: f32(0.125) // each sleeping minion looks this often (time-sliced by its index)
SIGHT_TICKS :: u32(SIGHT_S * TICK_HZ)
EYE_HEIGHT :: f32(1.5) // where a minion sees from, and a hero is seen at, above the feet
SURGE_FIRST_S :: f32(6) // the first surge rises this long after a floor begins
SURGE_FIRST_TICKS :: u32(SURGE_FIRST_S * TICK_HZ)
SURGE_EVERY_S :: f32(20) // and the next ones this long after each other
SURGE_EVERY_TICKS :: u32(SURGE_EVERY_S * TICK_HZ)
SURGE_NEAR :: f32(10) // a surge rises at graves at least this far from every hero up, in a straight line ...
SURGE_FAR :: f32(30) // ... and no farther than this from the nearest along the floor (metres of path)
SURGE_BASE :: 3 // a surge's minions ...
SURGE_PER_HERO :: 2 // ... and this many more per hero present
SURGE_SPREAD :: f32(1.5) // a surge's minions rise within this of their grave
DEV_SPAWN_RING :: f32(5) // dev_spawn_minions raises its minions this far from the sender's hero
DEV_KILL_KNOCK :: f32(4) // dev_kill_minions knocks its dead this fast (metres per second) away from the sender
BENCH_FLOOR_MINIONS :: 40 // the floor's benchmark row holds this many: the first floor's old cap, so the row compares
BENCH_SPREAD :: f32(12) // Floor 1's row's minions start within this many metres of slot 0's spawn, along x and z
BENCH_TRIES :: 20 // places tried per benchmark minion (some fall off the floor)
CROWD_CLEAR :: f32(6) // a held crowd's chasers start at least this far from every hero_spawn ...
CROWD_IDLE_CLEAR :: AGGRO_RADIUS + 3 // ... and its sleepers this far: out of sight of the heroes standing there
CROWD_SNAP :: f32(0.5) // a held crowd's drawn place counts when the walkable floor is this close
CROWD_TRIES :: 8 // places drawn per held minion before the floor counts as full

// ---- arriving beside the party

ARRIVAL_RING :: f32(2.5) // the eight spots tried around the anchor hero are this far from it, then twice as far
ARRIVAL_SLOT_TURN :: 3 // an arrival's first spot is this many eighths of a turn on per slot, so two at once differ
ARRIVAL_SNAP :: f32(1) // a spot counts when the navigation mesh is this close to it
ARRIVAL_CLEAR :: f32(2) // and no live minion is this close
ARRIVAL_ROOM :: f32(0.1) // and it clears every hero's capsule and every prop's footprint by this
ARRIVAL_RAY_HEIGHT :: f32(0.5) // the way from the anchor is tested this high above the floor (under low cover's top)
