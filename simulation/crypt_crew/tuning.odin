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
HERO_FEET :: HERO_HALF_HEIGHT + HERO_POGO_REST // from the capsule's centre down to the floor it stands on
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
