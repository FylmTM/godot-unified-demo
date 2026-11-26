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
SPAWN_GRACE_S :: f32(2) // a hero who is revived takes no damage this long
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

// ---- abilities: Ability's press or hold, each class its own (abilities.odin)

// The Knight's block (knight.odin): Ability held raises the shield.
BLOCK_ARC_COS :: f32(0.5) // a blow from within 60° of the facing meets the shield (cos 60°)
BLOCK_TAKE :: f32(0.2) // what a blow the shield meets still takes, as a share of its damage
BLOCK_SPEED :: f32(0.5) // a hero blocking moves at this fraction of its speed
// The Knight's shield charge: Attack pressed while blocking drives the hero along its facing, the shield ahead, which
// knocks what is in front aside every CHARGE_HIT_TICKS (a blast from the shield's face: knock_area) and takes every
// blow from the front.
CHARGE_SPEED :: f32(12) // metres per second
CHARGE_S :: f32(0.5)
CHARGE_TICKS :: u32(CHARGE_S * TICK_HZ)
CHARGE_RADIUS :: f32(1.2) // the blast's reach from the shield's face
CHARGE_DAMAGE :: i16(6)
CHARGE_KNOCK :: f32(9)
CHARGE_HIT_TICKS :: u32(8)
CHARGE_COOLDOWN_S :: f32(5) // from one charge's start to the next
CHARGE_COOLDOWN_TICKS :: u32(CHARGE_COOLDOWN_S * TICK_HZ)
#assert(CHARGE_KNOCK * BLAST_RIM > KNOCK_STAGGER) // all of a charge's reach staggers

// The Rogue's dodge roll (rogue.odin): Ability's press rolls along the stick (else the facing); nothing hurts it in the
// roll's first ROLL_SAFE_S, judged by the roll's age.
ROLL_SPEED :: f32(11) // metres per second
ROLL_S :: f32(0.40625)
ROLL_TICKS :: u32(ROLL_S * TICK_HZ)
ROLL_SAFE_S :: f32(0.3125)
ROLL_SAFE_TICKS :: u32(ROLL_SAFE_S * TICK_HZ)
ROLL_COOLDOWN_S :: f32(2.5)
ROLL_COOLDOWN_TICKS :: u32(ROLL_COOLDOWN_S * TICK_HZ)
#assert(ROLL_SAFE_TICKS < ROLL_TICKS)

// The Mage's fireball (mage.odin, fireballs.odin): Ability's press winds up a cast that leaves at its windup's end, lobbed
// to where the Mage then aims (fireball_target), and bursts there FIREBALL_FLIGHT_S later.
MAX_FIREBALLS :: 8
FIREBALL_RANGE :: f32(12) // the farthest it lands (metres along the aim)
FIREBALL_NO_AIM :: f32(6) // with no aim's reach it lands this far along the facing
FIREBALL_WALL_GAP :: f32(0.3) // a wall on its way: it lands this far short of where the wall meets the flight
FIREBALL_WINDUP_S :: f32(0.5)
FIREBALL_WINDUP_TICKS :: u32(FIREBALL_WINDUP_S * TICK_HZ)
FIREBALL_FLIGHT_S :: f32(0.625)
FIREBALL_FLIGHT_TICKS :: u32(FIREBALL_FLIGHT_S * TICK_HZ)
FIREBALL_RADIUS :: f32(3.5) // its burst hurts every minion this close that no wall shields ...
FIREBALL_DAMAGE :: i16(25) // ... this much
FIREBALL_KNOCK :: f32(9) // ... knocked away at this, falling off to BLAST_RIM of it at the rim
// Its blast on the Box3D bodies (fireballs.odin, blast_bodies): each prop and elite within FIREBALL_RADIUS that no wall
// shields takes this impulse (N·s: a barrel leaves at 8 m/s, an elite under 1 m/s) along the floor away from it,
// FIREBALL_LIFT of that upward, fading to none over FIREBALL_FALLOFF beyond. A crate, the lightest, rises at most about
// 0.9 m: no prop is blown over a wall.
FIREBALL_IMPULSE :: f32(240)
FIREBALL_LIFT :: f32(0.35)
FIREBALL_FALLOFF :: f32(1.5)
FIREBALL_COOLDOWN_S :: f32(8) // from one cast's start to the next
FIREBALL_COOLDOWN_TICKS :: u32(FIREBALL_COOLDOWN_S * TICK_HZ)

// The Barbarian's heave (barbarian.odin): Ability's press grabs the nearest elite or downed ally in the grab cone
// (GRAB_RANGE, GRAB_CONE_COS, as a prop), its body limp on the hold's joint; Attack throws it as a prop is thrown
// (THROW_WINDUP_S, THROW_SPEED, THROW_LIFT), and where it lands it knocks what is round it (knock_area).
HEAVE_MAX_S :: f32(1.5) // held this long unthrown, the body is let down where it hangs
HEAVE_MAX_TICKS :: u32(HEAVE_MAX_S * TICK_HZ)
// From a heave's end (its body landed, or let down) to the next grab: the body stands again (an elite's stagger runs
// out) before its thrower may grab it again, and the throw's flight counts for nothing.
HEAVE_COOLDOWN_S :: f32(3)
HEAVE_COOLDOWN_TICKS :: u32(HEAVE_COOLDOWN_S * TICK_HZ)
HEAVE_SPEED :: f32(0.6) // a hero heaving moves at this fraction of its speed
// What a held body weighs in the hands (kg; a heavy crate's): its mass while it hangs on the hold, so the hold's joint
// carries it as it carries a prop and a 320 kg skeleton doesn't drag the Barbarian about (gravity off: the hold bears
// it). Its own comes back as it is let go: a thrown elite flies with its full weight.
HEAVE_MASS :: f32(60)
HEAVE_HOLD_HEIGHT :: f32(1.6) // a held body's centre above the hero's feet: its capsule clears the doorways' lintel
HEAVE_LAND_RADIUS :: f32(2) // a thrown body landing knocks every skeleton this close ...
HEAVE_LAND_DAMAGE :: i16(15) // ... this much (a thrown elite takes it too, and staggers) ...
HEAVE_LAND_KNOCK :: f32(8) // ... knocked away at this, falling off to BLAST_RIM of it at the rim
// A thrown body has landed once it falls with this little floor (or a prop) under its capsule (metres) ...
HEAVE_LAND_GAP :: f32(0.25)
// A thrown downed hero's ragdoll has landed once its pelvis falls with this little floor (or a prop) under it
// (metres): about a body lying on its back's, plus a hand ...
RAGDOLL_LAND_REACH :: f32(0.5)
HEAVE_FLIGHT_MAX_S :: f32(2) // ... or once it has flown this long, wherever it is (wedged off the floor)
HEAVE_FLIGHT_MAX_TICKS :: u32(HEAVE_FLIGHT_MAX_S * TICK_HZ)
#assert(ELITE_STAGGER_TICKS < HEAVE_COOLDOWN_TICKS)
BARBARIAN_THROW :: f32(1.3) // the Barbarian throws a prop this much faster along the floor (it flies this much farther)
#assert(HEAVE_LAND_KNOCK * BLAST_RIM > KNOCK_STAGGER) // all of a landing's reach staggers

// ---- downed and revive (revive.odin)

REVIVE_RANGE :: f32(1.5) // an ally up holding Interact this close (feet to feet, on the floor plan) revives a hero down
REVIVE_S :: f32(2.5) // one ally's revive takes this long; each more beside it adds as much a tick
REVIVE_TICKS :: u16(REVIVE_S * TICK_HZ)
// A revive's progress (Hero.revive) counts in these per tick of one ally's tending, so a Field_Medic's tending can count
// a share more (revive_rate); it is up at REVIVE_FULL.
REVIVE_UNIT :: u16(10)
REVIVE_FULL :: REVIVE_TICKS * REVIVE_UNIT
REVIVE_DECAY :: u16(2) * REVIVE_UNIT // what a revive nobody tends loses a tick: two ticks of tending
REVIVE_SPEED :: f32(0.3) // a hero reviving moves at this fraction of its speed
REVIVE_HP :: i16(40) // the revived rise with this, in their grace (SPAWN_GRACE_S)
WIPE_S :: f32(2.5) // every hero present down this long: the floor starts over
WIPE_TICKS :: u32(WIPE_S * TICK_HZ)

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
MINION_STAND :: f32(0.4) // a chaser this far inside its reach stands to swing, no nearer: the front row keeps its ring
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
STEER_NEAR :: f32(3) // a chaser this close to its target steers every tick ...
STEER_S :: f32(0.0625) // ... and a farther one this often (time-sliced by its index), walking its facing between
STEER_TICKS :: u32(STEER_S * TICK_HZ)
SEPARATION :: f32(0.9) // minions closer than this push apart ...
SEPARATION_SPEED :: f32(2.5) // ... at up to this speed
QUEUE_REACH :: f32(1) // a chaser gives way to a neighbour ahead from this far ...
QUEUE_STOP :: SEPARATION // ... to a stop this close: the back rows wait, never pressing the front onto the hero
#assert(QUEUE_REACH <= MINION_GRID_CELL) // the grid's 3 by 3 cells hold every neighbour this close
#assert(QUEUE_REACH > QUEUE_STOP)
QUEUE_ALONG :: f32(0.001) // a chase heads at a neighbour when its part toward it is more than this (metres a second)
QUEUE_HELD :: f32(0.01) // a chaser slowed by more than this share of its speed is held up, and steps sideways ...
QUEUE_SIDE :: f32(1.0) // ... at up to this share of its speed
QUEUE_PASSES :: 3 // how many times a chaser's last look goes over its close neighbours
QUEUE_NEIGHBOURS :: 16 // the most neighbours within QUEUE_REACH a chaser weighs (kept apart, it has six or seven)
KNOCK_DECAY :: f32(6) // a knockback's velocity decays at this rate per second
KNOCK_MAX :: f32(10) // a minion's knockback adds up to at most this fast (metres per second): a pile-up of blows
// A minion knocked faster than this staggers: it neither walks at its target nor starts or lands a swing until its
// knock decays under it (a Knight's blow, 5 m/s, about 0.2 s; a Barbarian's, 9, 0.3 s).
KNOCK_STAGGER :: f32(1.5)
// A blast's knock falls off from its centre to this share of it at its rim (knock_area): a burst's 4 m/s is 2 there,
// over KNOCK_STAGGER, so all of its BURST_RADIUS staggers.
BLAST_RIM :: f32(0.5)
#assert(BURST_KNOCK * BLAST_RIM > KNOCK_STAGGER)
// The minion grid's cells (metres): the separation's reach, which its 3 by 3 cells must cover, and no more, so a dense
// crowd's neighbour query scans 9 m²; a longer reach (a blow, a burst, a bolt, a thrown prop) walks a box of cells
// (minions_within). world_create lays it over each floor's mesh.
MINION_GRID_CELL :: f32(1)
#assert(MINION_GRID_CELL >= SEPARATION)
MINION_GRID_CELLS :: 16384 // the most cells a floor's grid may need: its mesh up to 125 m by 125 m

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
SURGE_PER_HERO :: 2 // ... and this many more per hero present ...
SURGE_GROWTH :: 2 // ... and this many more for each surge faced since the party entered the floor
RISE_GAP_S :: f32(0.125) // each grave raises at most one minion this often (its turn: time-sliced by its index)
RISE_GAP_TICKS :: u32(RISE_GAP_S * TICK_HZ)
RISE_TRIES :: 4 // places tried round a grave for a riser, each clear of every live minion by SEPARATION
SURGE_SPREAD :: f32(1.5) // a surge's minions rise within this of their grave
DEV_SPAWN_RING :: f32(5) // dev_spawn_minions raises its minions this far from the sender's hero
DEV_KILL_KNOCK :: f32(4) // dev_kill_minions knocks its dead this fast (metres per second) away from the sender
BENCH_FLOOR_MINIONS :: 40 // Floor 1's benchmark row holds this many: the floor's old cap, so the row compares
BENCH_SPREAD :: f32(12) // Floor 1's row's minions start within this many metres of slot 0's spawn, along x and z
BENCH_TRIES :: 20 // places tried per benchmark minion (some fall off the floor)
CROWD_CLEAR :: f32(6) // a held crowd's chasers start at least this far from every hero_spawn ...
CROWD_IDLE_CLEAR :: AGGRO_RADIUS + 3 // ... and its sleepers this far: out of sight of the heroes standing there
CROWD_TRIES :: 8 // places drawn per held minion before the floor counts as full

// ---- arriving beside the party

ARRIVAL_RING :: f32(2.5) // the eight spots tried around the anchor hero are this far from it, then twice as far
ARRIVAL_SLOT_TURN :: 3 // an arrival's first spot is this many eighths of a turn on per slot, so two at once differ
ARRIVAL_SNAP :: f32(1) // a spot counts when the navigation mesh is this close to it
ARRIVAL_CLEAR :: f32(2) // and no live minion is this close
ARRIVAL_ROOM :: f32(0.1) // and it clears every hero's capsule and every prop's footprint by this
ARRIVAL_RAY_HEIGHT :: f32(0.5) // the way from the anchor is tested this high above the floor (under low cover's top)

// ---- elites: skeleton Warriors, Rogues and Mages, Box3D characters with rules of their own (elites.odin)

MAX_ELITES :: 16 // elite rows, the dying included
MAX_ELITE_MARKERS :: 8 // the most elite markers a level holds
// A surge or a dev spawn raises no elite while this many are alive (a floor's markers place theirs whatever).
ELITES_ALIVE_MAX :: 6
ELITE_SURGE_EVERY :: 3 // every this many surges on a floor, the surge brings an elite too
// A surge's or a dev spawn's elite rises on this ring round its place when the place itself is taken.
ELITE_RISE_RING :: f32(1.5)
ELITE_RADIUS :: f32(0.45)
ELITE_HEIGHT :: f32(2.1) // the capsule, end to end: a KayKit skeleton is about 2 m to the top of its helmet or hood
ELITE_HALF_HEIGHT :: ELITE_HEIGHT / 2 - ELITE_RADIUS
ELITE_CENTRE_ABOVE_FEET :: ELITE_HALF_HEIGHT + HERO_POGO_REST // it floats on the heroes' pogo
// An elite is four times a hero's weight (about 320 kg) and its drive six times as strong (about 75 m/s²), so a hero
// walking into one barely shoves it (its drive holds it where it stands), and a knock's velocity is soon spent.
ELITE_DENSITY :: 4 * HERO_DENSITY
ELITE_GROUND_FORCE :: f32(24000)
// What a skeleton's reach and its swing's arc are, past its circle and the hero's capsule (as a minion's).
ELITE_REACH :: f32(0.9)
ELITE_STAND :: f32(0.4) // a chaser this far inside its reach stands to swing, as a minion does
ELITE_STRIKE_COS :: f32(0.5) // a swing starts, and lands, only on a hero within 60° of its facing (cos 60°)
// An elite turns at most this much a tick (4°, 256° a second; its cosine and sine: no trig in the sim), so a hero can
// get round it: a Warrior's shield isn't always toward the blow.
ELITE_TURN_COS :: f32(0.9975641)
ELITE_TURN_SIN :: f32(0.06975647)
ELITE_FACE_NEAR :: f32(4) // a chaser this close to its target faces it, farther its way along the path
// An elite backing off (a Mage too near its target, a Rogue after its lunge) looks this far along the floor (metres)
// for an open way, and takes one it would get OPEN_GOT of the way along (open_heading).
OPEN_LOOK :: f32(1.5)
OPEN_GOT :: f32(0.8)
// A knock moves an elite less than a minion (it is a Box3D body, about a hero's weight): this share of the blow's
// knock, as a velocity change, the sum at most ELITE_KNOCK_MAX; its drive's friction stops it.
ELITE_KNOCK_TAKE :: f32(0.5)
ELITE_KNOCK_MAX :: f32(6)
// A blow whose knock is at least this staggers an elite for ELITE_STAGGER_S: it walks at nothing, its attack or its
// summoning is cut off, and a Warrior's shield is down. A cleave (9) and a thrown prop (7) do; a sword (5), a bolt (3)
// or a shot (3) don't.
ELITE_STAGGER_KNOCK :: f32(6)
ELITE_STAGGER_S :: f32(0.5)
ELITE_STAGGER_TICKS :: u32(ELITE_STAGGER_S * TICK_HZ)

// What a kind of elite is (ELITE_SPECS).
Elite_Spec :: struct {
	hp:        i16,
	max_speed: f32, // metres per second
	damage:    i16, // what its attack takes from a hero (a Mage's: its bone bolt's)
	// Its attack: it starts at once and lands `windup` ticks later (a Rogue's lunge, a Mage's bolt leaving its
	// hands); the attack lasts `duration`.
	windup:    u32,
	duration:  u32,
}

// Each kind's numbers: the Warrior slow and shielded, the Rogue quick and fragile, the Mage frail and far off.
@(rodata)
ELITE_SPECS := [Elite_Kind]Elite_Spec {
	.Warrior = {hp = 150, max_speed = 2.8, damage = 25, windup = u32(0.75 * TICK_HZ), duration = u32(1.5 * TICK_HZ)},
	.Rogue = {hp = 70, max_speed = 5.5, damage = 20, windup = u32(0.375 * TICK_HZ), duration = u32(0.625 * TICK_HZ)},
	.Mage = {hp = 60, max_speed = 3, damage = 12, windup = u32(0.5 * TICK_HZ), duration = u32(0.875 * TICK_HZ)},
}

// The Warrior's shield (elite_warrior.odin): a blow from its front takes ELITE_GUARD_TAKE of its damage and neither
// knocks nor staggers it, unless it is staggered or its guard is broken (a charge, a fireball, a thrown prop).
ELITE_GUARD_COS :: f32(0.5) // its front: within 60° of its facing (cos 60°)
ELITE_GUARD_TAKE :: f32(0.25)
GUARD_BREAK_S :: f32(2)
GUARD_BREAK_TICKS :: u32(GUARD_BREAK_S * TICK_HZ)

// The Rogue, a flanker (elite_rogue.odin): it circles to FLANK_BEHIND behind its target's facing, lunges, and backs
// off for FLANK_RETREAT_S.
FLANK_BEHIND :: f32(2.5)
FLANK_NEAR :: f32(6) // it circles once this close to its target and in sight of it; farther, it walks the path
FLANK_ARRIVE :: f32(0.75) // it lunges once this close to its spot behind the target ...
FLANK_GIVE_UP_S :: f32(3) // ... or, after circling this long (a target that keeps facing it), from FLANK_LUNGE
FLANK_GIVE_UP_TICKS :: u32(FLANK_GIVE_UP_S * TICK_HZ)
FLANK_LUNGE :: f32(3)
FLANK_PULL :: f32(1.5) // how hard it pulls back onto its circle round the target (per metre off it)
LUNGE_SPEED :: f32(7) // metres per second along its facing during the lunge's windup: FLANK_BEHIND in 0.36 s
FLANK_RETREAT_S :: f32(1.5)
FLANK_RETREAT_TICKS :: u32(FLANK_RETREAT_S * TICK_HZ)

// The Mage, a caster and summoner (elite_mage.odin): it keeps MAGE_NEAR to MAGE_FAR from its target, casts a bone
// bolt every BONE_BOLT_EVERY_S and raises SUMMON_COUNT minions every SUMMON_EVERY_S.
MAGE_NEAR :: f32(8)
MAGE_FAR :: f32(12)
BONE_BOLT_FIRST_S :: f32(1) // its first bolt, this long after it wakes or rises
BONE_BOLT_FIRST_TICKS :: u32(BONE_BOLT_FIRST_S * TICK_HZ)
BONE_BOLT_EVERY_S :: f32(3)
BONE_BOLT_EVERY_TICKS :: u32(BONE_BOLT_EVERY_S * TICK_HZ)
BONE_BOLT_SPEED :: f32(10) // flying at FLIGHT_HEIGHT, as a hero's bolt, and hitting heroes, never skeletons
BONE_BOLT_LIFE_S :: f32(1.5) // 15 m
BONE_BOLT_LIFE_TICKS :: u32(BONE_BOLT_LIFE_S * TICK_HZ)
BONE_BOLT_RANGE :: f32(14) // it casts at a target in sight this close
SUMMON_EVERY_S :: f32(12)
SUMMON_EVERY_TICKS :: u32(SUMMON_EVERY_S * TICK_HZ)
SUMMON_CAST_S :: f32(1)
SUMMON_CAST_TICKS :: u32(SUMMON_CAST_S * TICK_HZ)
SUMMON_RETRY_S :: SUMMON_EVERY_S / 2 // a summoning a stagger cut off is tried again this long after
SUMMON_RETRY_TICKS :: u32(SUMMON_RETRY_S * TICK_HZ)
SUMMON_COUNT :: 3 // at most up to the floor's cap alive, and into the minion table's free rows
SUMMON_RING :: f32(1.5) // its minions rise on this ring round it

// ---- loot: coins felled skeletons drop, picked up into the party's purse (loot.odin)

MAX_LOOT :: 128 // coins on the ground at once: a drop past it is lost (a coin lasts LOOT_LIFE_S, a drop is 1 in 5)
LOOT_ONE_IN :: 5 // a felled minion drops a coin on a roll of 1 in this ...
LOOT_VALUE_MIN :: 1 // ... worth this much gold ...
LOOT_VALUE_MAX :: 3 // ... to this, rolled
LOOT_SPREAD :: f32(0.8) // the coins of a drop of more than one lie evenly on a ring this far round where it fell
LOOT_RADIUS :: f32(1.2) // a hero up whose feet come this close to a coin (on the floor plan) picks it up ...
LOOT_ARM_S :: f32(0.5) // ... once it has lain this long, so a drop is seen landing before it goes
LOOT_ARM_TICKS :: u32(LOOT_ARM_S * TICK_HZ)
LOOT_LIFE_S :: f32(30) // a coin nobody picks up goes this long after it dropped
LOOT_LIFE_TICKS :: u32(LOOT_LIFE_S * TICK_HZ)
DEV_DROP_RING :: f32(2) // dev_drop_loot lays its coins on a ring this far round the sender's hero: beyond LOOT_RADIUS
ELITE_COINS :: 5 // a felled elite drops this many coins, on the LOOT_SPREAD ring round where it fell ...
// ... worth this much gold between them, by kind: the Mage, the summoner a party must reach first, the most
@(rodata)
ELITE_GOLD := [Elite_Kind]int {
	.Warrior = 15,
	.Rogue   = 20,
	.Mage    = 25,
}

// ---- mechanisms: plates, gates, barricades and traps, Box3D bodies made from a floor's markers (plates.odin,
// gates.odin, barricades.odin, traps.odin)

MAX_PLATES :: 8
MAX_GATES :: 8
MAX_BARRICADES :: 8
MAX_TRAPS :: 16
// A gate or an unbroken barricade keeps minions out with three circles of this radius along its width (its middle and
// two thirds of the way to each end), which overlap over a 4 m span (gate_obstacles, barricade_obstacles).
PIECE_OBSTACLE_RADIUS :: f32(0.7)

// A plate (plates.odin): a slab (the decorated tile, 2 m square) on a vertical prismatic joint, held up by its joint's
// motor, which bears PLATE_LOAD on top of the slab's own weight and no more: a crate, a barrel or a hero standing on it
// (its pogo spring pushes on whatever it stands on) sinks it, a lighter load doesn't. Box3D's prismatic spring has no
// force cap, so the motor is the spring: it lifts the slab back at PLATE_RISE_SPEED once the load is off.
PLATE_HALF :: [3]f32{0.95, 0.02, 0.95} // thin: a minion (a row on the floor) shows sunk in it no deeper than it stands
PLATE_TRAVEL :: f32(0.12) // how far the slab sinks: its joint's limits, from its rest to a hand above the floor
PLATE_CLEARANCE :: f32(0.01) // between the slab, sunk all the way, and the floor under it
PLATE_ON :: f32(0.07) // sunk deeper than this, a plate is pressed ...
PLATE_OFF :: f32(0.03) // ... and released once it rises above this (hysteresis: a bobbing slab never flickers)
PLATE_MASS :: f32(10)
PLATE_LOAD :: f32(15) // kilograms the motor bears on top of the slab's weight
PLATE_RISE_SPEED :: f32(0.5) // metres per second: a released slab is back up in about a quarter second
#assert(0 < PLATE_OFF && PLATE_OFF < PLATE_ON && PLATE_ON < PLATE_TRAVEL)

// A gate (gates.odin): a grille (the gated wall, 4 m wide) on a vertical prismatic joint whose motor lifts it while
// enough of its plates are pressed and lowers it otherwise, gravity off (the motor alone moves it).
GATE_HALF :: [3]f32{1.95, 2, 0.5} // the gated wall's block, a hand narrower than its 4 m gap: it never rubs the walls beside it
GATE_MASS :: f32(120)
GATE_SPEED :: f32(2) // metres per second, up or down
GATE_RISE :: f32(2.6) // how high it lifts: its bottom clears a hero's head
GATE_LIFT_FORCE :: f32(1500) // the motor's cap lifting it: full speed in about a sixth of a second
// ... and lowering it: what it presses on whatever is under it, so a crate wedges it and a hero walks out from under it.
GATE_CLOSE_FORCE :: f32(300)
GATE_PASS :: f32(1.8) // lifted less than this, it is in minions' way (gate_obstacles)
#assert(GATE_PASS < GATE_RISE)

// A barricade (barricades.odin): a fence (the barrier, 4 m wide) welded to the world, broken free by a blow (a thrown
// prop, a charge, a hurled body) that strains its weld past BARRICADE_BREAK_N: the blow decides, and the strain is its
// floor, so a thrown prop that only nudges the fence leaves it. What Box3D measures (its joint event's force): a crate
// thrown into it from 3 to 5 m, 20 to 32 kN; one nudged against it at 3 m/s, 6 to 8 kN; a hero walking into it at a
// run, about 50 kN (no blow, so it holds).
// The fence's body: a hand narrower than its 4 m gap, and taller than the barrier's 1.1 m model, so a crate thrown from
// across a room meets it instead of sailing over (bolts and shots stop at it too).
BARRICADE_HALF :: [3]f32{1.95, 0.85, 0.25}
BARRICADE_MASS :: f32(80)
BARRICADE_BREAK_N :: f32(12000)

// Spikes (traps.odin): a sensor box over the spike tile's middle, up SPIKES_UP_S of every SPIKES_PERIOD_S (a pure
// function of the game clock and the marker's phase), or while its plate is pressed. Up, they strike as they rise and
// every SPIKES_HIT_TICKS after: SPIKES_DAMAGE to each hero, elite and minion over them, knocking skeletons off at
// SPIKES_KNOCK.
SPIKES_HALF :: f32(1.1) // half the spike cluster's width (it is square)
SPIKES_SENSOR_HEIGHT :: f32(0.6) // the sensor's height above the floor: it meets every capsule standing there
SPIKES_PERIOD_S :: f32(3)
SPIKES_PERIOD_TICKS :: u32(SPIKES_PERIOD_S * TICK_HZ)
SPIKES_UP_S :: f32(1)
SPIKES_UP_TICKS :: u32(SPIKES_UP_S * TICK_HZ)
SPIKES_HIT_TICKS :: u32(32)
SPIKES_DAMAGE :: i16(20)
SPIKES_KNOCK :: f32(5)
#assert(SPIKES_UP_TICKS < SPIKES_PERIOD_TICKS)

// The roller (traps.odin): a kinematic pillar driven along its marker's path, there and back, its phase a pure function
// of the game clock; it shoves bodies as any moving body does, and strikes what touches it (within ROLLER_TOUCH of its
// sides) every ROLLER_HIT_TICKS: ROLLER_DAMAGE, knocking skeletons away at ROLLER_KNOCK.
ROLLER_HALF :: [3]f32{0.75, 2, 0.75} // the pillar, 1.5 m square and 4 m tall
ROLLER_TOUCH :: f32(0.15)
ROLLER_HIT_TICKS :: u32(48)
ROLLER_DAMAGE :: i16(15)
ROLLER_KNOCK :: f32(6)

// ---- ragdolls: a hero down falls as one (ragdolls.odin)

RAGDOLL_SCALE :: HERO_HEIGHT / 1.8 // unified's ragdoll is a 1.8 m human: this makes it as tall as a hero's capsule
RAGDOLL_MASS :: f32(60) // kilograms: its bones' density is what weighs it this (a heaved body's HEAVE_MASS)
#assert(RAGDOLL_MASS == HEAVE_MASS) // the hold a heave makes is capped for HEAVE_MASS: a ragdoll hangs on it as it is
RAGDOLL_KICK :: f32(3) // metres per second away from the blow that downed it, on top of the hero's own velocity ...
RAGDOLL_CARRY_MAX :: f32(4) // ... of which it carries at most this much (a charge doesn't fling a body into a horde)
RAGDOLL_TIP :: f32(0.8) // a blow from no side (a dev hurt, a rejoin while down) tips it backwards this fast instead
// Torque each joint's motor holds against (Ragdoll_Def.friction_torque, newton-metres): the sample's 5 for a 146 kg
// body, scaled to this one's weight, so a fallen body neither flops like cloth nor holds a pose like a doll.
RAGDOLL_FRICTION_TORQUE :: f32(2)
// Its joints' springs back toward the standing pose it was made in (0: none, it lies as it falls).
RAGDOLL_HERTZ :: f32(0)
// A ragdoll whose every bone moves slower than RAGDOLL_STILL_SPEED and turns slower than RAGDOLL_STILL_SPIN for
// RAGDOLL_STILL_TICKS in a row has come to rest: it sleeps then (settle_ragdolls), rather than spend Box3D's half second
// of stillness awake, solving its twelve bones in every step and every re-sim.
RAGDOLL_STILL_SPEED :: f32(0.02) // metres per second
RAGDOLL_STILL_SPIN :: f32(0.1) // radians per second
RAGDOLL_STILL_TICKS :: 8 // an eighth of a second: a limb at the top of its swing is still for a tick or two, not this long
// A revived hero stands on the walkable floor's point nearest the floor under its pelvis (found within
// RAGDOLL_FLOOR_BELOW of it, through a tomb's top or a wall the body lies on), within RAGDOLL_SNAP of it; failing that
// (a body on a wide tomb's top), on the nearest of the spots RAGDOLL_RINGS rings round it, RAGDOLL_RING apart, find.
RAGDOLL_SNAP :: f32(3)
RAGDOLL_FLOOR_BELOW :: f32(10)
RAGDOLL_RING :: f32(0.75)
RAGDOLL_RINGS :: 5
// A ragdoll this far below the floor's navigation mesh has fallen out of the level: it goes, and its hero lies at its
// spawn as a ragdoll laid anew. Deep enough for anything a floor lowers a body through (a lift's ride).
RAGDOLL_KILL_DEPTH :: f32(20)

// ---- the hoard, the lift and boons (hoard.odin, lift.odin, boons.odin)

// The hoard: the vault's gold chest, a dynamic body two heroes carry by its handles and one alone drags.
HOARD_MASS :: f32(120) // kilograms: one hold lifts one end of it, two lift it clear (HOARD_LIFT)
// What it weighs at rest, nobody holding a handle: more than four heroes' drives can slide (its floor friction over 4
// HERO_GROUND_FORCE), so it goes where it is hauled, never shoved.
HOARD_REST_MASS :: f32(12000)
#assert(HOARD_FRICTION * HOARD_REST_MASS * GRAVITY > PLAYERS * HERO_GROUND_FORCE)
HOARD_HALF :: [3]f32{0.8, 0.5, 0.6} // its box's half extents, measured from its model (chest_gold)
// A handle, body-local: at its +X end (the other at -X), a little above its centre, so the chest carried by both
// hangs level under its handles instead of turning over.
HOARD_HANDLE :: [3]f32{0.8, 0.15, 0}
HOARD_FRICTION :: f32(0.15) // on the floor: a dragged end slides
HOARD_ANGULAR_DAMPING :: f32(3) // a carried chest's swing under its handles dies down, so it hangs steady
HOARD_FOOTPRINT :: f32(0.9) // the circle minions are pushed out of (metres)
// Let go of, it weighs HOARD_REST_MASS again only once slower than this (metres per second) and turning slower than
// HOARD_SETTLE_SPIN (radians per second): a chest dropped mid-carry slides on at its own weight.
HOARD_SETTLE_SPEED :: f32(0.2)
HOARD_SETTLE_SPIN :: f32(0.3)
HOARD_HOLD_HEIGHT :: f32(0.9) // a hold lifts its handle this high above the hauler's feet
// A hold has its handle between these gaps off the hauler's capsule on the floor plan, and pulls it only when it strays
// out of them: two haulers never fight over where the rigid chest is (two holds each pinning their handle to a spot
// would spend their force pulling it apart, not lifting it), and one walking off drags its end along.
HOARD_HOLD_NEAR :: f32(0.05)
HOARD_HOLD_FAR :: f32(0.3)
// A hold's force cap, in multiples of the hoard's weight: over half (one end up, the other on the floor), under all of
// it (one hauler never lifts it clear), so whether it is carried or dragged is physics' answer, not a rule's.
HOARD_LIFT :: f32(0.6)
#assert(HOARD_LIFT > 0.5 && HOARD_LIFT < 1)
HOARD_DRAG_SPEED :: f32(0.45) // a hauler moves at this fraction of its speed while the hoard drags on the floor ...
HOARD_CARRY_SPEED :: f32(0.8) // ... and at this while it is carried clear
// A hauler's drive pushes with at most this (newtons; HERO_GROUND_FORCE's): the hold pulling back on it slows it as it
// gets the chest going, so the hold doesn't stretch ahead of the chest and spend on pulling what it should on lifting.
HOARD_GROUND_FORCE :: f32(1200)
HOARD_SLIP :: f32(1.2) // a hold stretched further than this (its hauler gone ahead, the hoard caught) lets go
HAUL_SURGE_S :: f32(12) // from the first grab on, the surges rise this often: the crypt wakes behind the haul
HAUL_SURGE_TICKS :: u32(HAUL_SURGE_S * TICK_HZ)
#assert(HAUL_SURGE_TICKS < SURGE_EVERY_TICKS)
HOARD_GOLD :: 100 // the gold the hoard puts in the purse when the party descends with it

// The lift: a kinematic deck in a shaft, the floor's exit.
LIFT_HALF :: [3]f32{1.95, 0.25, 1.95} // the deck's half extents: a large floor tile's top, a hand short of the shaft
LIFT_SENSOR_HEIGHT :: f32(2.5) // the volume above the deck that counts as aboard
// Once the deck has gone down, minions are kept this far from the shaft's middle (its corners' reach): the navigation
// keeps the deck's floor, which they walk while it is up.
LIFT_SHAFT_REACH :: f32(2.9)
#assert(LIFT_SHAFT_REACH * LIFT_SHAFT_REACH >= 2 * LIFT_HALF.x * LIFT_HALF.x)
LIFT_HOLD_S :: f32(1.5) // everyone aboard with the hoard this long: it goes down
LIFT_HOLD_TICKS :: u32(LIFT_HOLD_S * TICK_HZ)
// How far down the shaft it goes: shallow enough that the camera, held at the rim and pitched down, sees the party
// on the deck at the bottom (game/play/camera_rig.gd) ...
LIFT_DROP :: f32(2.5)
LIFT_RIDE_S :: f32(2.5) // ... in this long (smoothstepped: it starts and stops gently, so riders keep their feet)
LIFT_RIDE_TICKS :: u32(LIFT_RIDE_S * TICK_HZ)
// An arrival while the lift is busy (and dev_board's heroes) stands on its deck this far out along x and z, toward its
// slot's corner: clear of the hoard in the middle.
LIFT_SLOT_SPREAD :: f32(1.05)
#assert(LIFT_SLOT_SPREAD + HERO_RADIUS < LIFT_HALF.x)

// Boons: each hero picks one of three at the lift, ranked up to BOON_RANK_MAX each (boons.odin).
BOON_RANK_MAX :: 3
BOON_OFFER :: 3 // the boons offered
BOON_TIMEOUT_S :: f32(30) // a hero who hasn't picked by then gets its first offer
BOON_TIMEOUT_TICKS :: u32(BOON_TIMEOUT_S * TICK_HZ)
THICK_HIDE_HP :: i16(20) // Thick_Hide: this much more health a rank (its pick heals what it adds)
SWIFT_BOOTS :: f32(0.06) // Swift_Boots: this much faster a rank
KEEN_EDGE :: f32(0.15) // Keen_Edge: this much more damage a rank, on minions and elites
QUICK_HANDS :: f32(0.12) // Quick_Hands: this much shorter an ability cooldown a rank
STRONG_BACK :: f32(0.6) // Strong_Back: what a rank leaves of the slowdown from carrying a prop or hauling the hoard
FIELD_MEDIC :: f32(0.3) // Field_Medic: this much faster a revive a rank (REVIVE_UNIT: in tenths of a tick of tending)
#assert(QUICK_HANDS * BOON_RANK_MAX < 1)
