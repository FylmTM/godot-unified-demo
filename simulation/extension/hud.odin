// The HUD's session data (session thread): one value per published tick, set on Unified.data.hud when its bytes
// change. It is the newest prediction, so it can roll back: what must be final comes from a CONFIRMED event.
package crypt_crew_extension

import "unified:godot"
import "unified:sim"

import g "../crypt_crew"

// The game's session data types (Unified.data.<name>).
Data :: union {
	Data_Hud,
}

// What the HUD shows.
Data_Hud :: struct {
	kills:   u32, // minions killed this session
	minions: u16, // minions alive
	paused:  bool, // the co-op pause (the State's Clock)
	_pad:    u8,
	heroes:  [g.PLAYERS]Hud_Hero, // by slot
}

// One slot's hero (DataHudHero).
Hud_Hero :: struct {
	player: sim.Player, // its key (0: the slot is empty)
	hp:     i16,
	class:  g.Class, // EnumClass
	local:  bool, // one of this machine's players
}

// The HUD's data from the frame's state.
fill_hud :: proc(f: ^Frame) {
	hud := Data_Hud {
		kills   = f.state.kills,
		minions = u16(g.minions_alive(&f.state.minions)),
		paused  = f.state.clock.paused,
	}
	heroes := sim.iterate_present(&f.state.players)
	for hero, player in sim.next(&heroes) {
		slot, _ := sim.player_slot(&f.state.players, player)
		hud.heroes[slot] = {
			player = player,
			hp     = hero.hp,
			class  = hero.class,
			local  = godot.is_local(f, player),
		}
	}
	godot.push_data(f, hud)
}
