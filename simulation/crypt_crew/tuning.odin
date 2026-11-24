// Every rule number of the game, in metres, seconds and hit points: the one place a designer tunes. A time is written
// in seconds and converted to whole ticks at compile time (`X_TICKS :: u32(X_S * TICK_HZ)`). A level's own numbers are
// its markers' properties (game/levels/markers/).
package crypt_crew

// ---- sizes: the most of each kind of marker the World keeps from a level

MAX_GRAVES :: 16
MAX_PACKS :: 8
MAX_PROPS :: 32
MAX_FIELDS :: 8 // memoized navigation fields: one per hero chased, a few to spare

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
TURN_STICK :: f32(0.1) // a hero without an aim turns to its move once the stick is pushed further than this

// What a class plays like (CLASS_SPECS).
Class_Spec :: struct {
	max_speed: f32, // metres per second at a full stick
}

// Each class's numbers. `Any` is a Profile's wish only: a hero's class is resolved on arrival (presence.odin), so no
// hero plays its zero entry.
@(rodata)
CLASS_SPECS := #partial [Class]Class_Spec {
	.Knight = {max_speed = 5},
	.Barbarian = {max_speed = 4.5},
	.Mage = {max_speed = 4.75},
	.Rogue = {max_speed = 5.5},
}

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
	shape:       Prop_Shape,
}

// Each kind of prop, its size measured from its model (assets/kaykit/dungeon/: barrel_small, box_small, box_large).
@(rodata)
PROP_SPECS := [Prop_Kind]Prop_Spec {
	.Barrel = {half = {0.5, 0.509, 0.5}, mass = 30, carry_speed = 0.85, shape = .Cylinder},
	.Crate = {half = {0.5, 0.5, 0.5}, mass = 20, carry_speed = 0.85, shape = .Box},
	.Heavy_Crate = {half = {0.75, 0.75, 0.75}, mass = 60, carry_speed = 0.65, shape = .Box},
}

PROP_FRICTION :: f32(0.6)
PROP_RESTITUTION :: f32(0.1)
PROP_CYLINDER_SIDES :: 12 // the barrel's hull: a 12-sided cylinder

// Grabbing: Interact's press takes the nearest free prop in a cone in front of the hero (grab_target).
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
THROW_CLEAR_DIST :: f32(2.5) // a thrown prop passes through its thrower until it is this far from them (or `thrown` ends)
PICK_UP_S :: f32(0.625) // the grab's action
PICK_UP_TICKS :: u32(PICK_UP_S * TICK_HZ)
