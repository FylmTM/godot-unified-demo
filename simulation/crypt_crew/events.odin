// What the sim tells the views happened, as opposed to what is (the state, which fill_frame reads). Each event is
// declared beside the system that emits it.
package crypt_crew

import "unified:sim"

// Every event the sim emits: the library's joins and leaves, and the game's own.
Event :: union {
	sim.Event_Player_Joined,
	sim.Event_Player_Left,
	Event_Paused,
	Event_Prop_Grabbed,
	Event_Prop_Dropped,
	Event_Prop_Thrown,
	Event_Prop_Impact,
	Event_Minion_Hit,
	Event_Minion_Died,
	Event_Surge,
	Event_Hero_Hurt,
	Event_Hero_Downed,
	Event_Hero_Spawned,
	Event_Floor_Restarted,
	Event_Hero_Attacked,
	Event_Bolt_Burst,
	Event_Crossbow_Shot,
	// The abilities (abilities.odin, fireballs.odin), going down and being revived (health.odin, revive.odin).
	Event_Ability,
	Event_Blocked,
	Event_Fireball_Burst,
	Event_Hero_Revived,
	Event_Party_Wiped,
	// The Barbarian's heave (barbarian.odin)
	Event_Heaved,
	Event_Heave_Landed,
	// Elites (elites.odin)
	Event_Elite_Hit,
	Event_Elite_Died,
	Event_Guard_Broken,
	Event_Elite_Cast,
	// loot (loot.odin)
	Event_Loot_Dropped,
	Event_Loot_Collected,
}
