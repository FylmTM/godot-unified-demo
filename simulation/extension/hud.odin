// The HUD's session data (session thread): one value per published tick, set on Unified.data.hud when its bytes
// change. It is the newest prediction, so it can roll back: what must be final comes from a CONFIRMED event.
package crypt_crew_extension

import "unified:dmath"
import "unified:godot"
import "unified:sim"

import g "../crypt_crew"

// The game's session data types (Unified.data.<name>).
Data :: union {
	Data_Hud,
}

// What the HUD shows.
Data_Hud :: struct {
	minions:   u16, // minions alive (the newest prediction, like all of it)
	paused:    bool, // the co-op pause (the State's Clock)
	_pad:      u8,
	paused_by: sim.Player, // who paused it (its key; 0: nobody)
	surges:    u32, // the surges the party has faced, a save's included
	kills:     u32, // the skeletons it has felled, a save's included (a prediction: the HUD never counts it back)
	// The party's purse (a prediction, a save's included): the HUD's purse takes it once, when it shows, and from then on
	// counts from CONFIRMED pickups alone (game/play/purse.gd), never from this.
	gold:      u32,
	heroes:    [g.PLAYERS]Hud_Hero, // by slot
}

// One slot's hero (DataHudHero).
Hud_Hero :: struct {
	player:  sim.Player, // its key (0: the slot is empty)
	hp:      i16,
	hp_max:  i16, // its full health: the HUD's bar is hp of hp_max
	class:   g.Class, // EnumClass
	local:   bool, // one of this machine's players
	// Its state as the plate shows it: down (until an ally revives it), and how ready its ability is, 0 (its cooldown
	// just began) to 255 (ready: the pip full).
	down:    bool,
	ability: u8,
	// A local hero's: the ally its Interact would revive now (the rules' revive_target: the "[E] Revive" prompt; 0:
	// nobody, or not a local hero).
	revive:  sim.Player,
}

// The HUD's data from the frame's state.
fill_hud :: proc(f: ^Frame) {
	hud := Data_Hud {
		minions   = u16(g.minions_alive(&f.state.minions)),
		paused    = f.state.clock.paused,
		paused_by = f.state.paused_by,
		surges    = f.state.surges,
		kills     = f.state.kills,
		gold      = f.state.gold,
	}
	heroes := sim.iterate_present(&f.state.players)
	for hero, player in sim.next(&heroes) {
		slot, _ := sim.player_slot(&f.state.players, player)
		local := godot.is_local(f, player)
		hud.heroes[slot] = {
			player  = player,
			hp      = hero.hp,
			hp_max  = g.HERO_HP,
			class   = hero.class,
			local   = local,
			down    = hero.action == .Down,
			ability = u8(dmath.round(g.ability_charge(f.time, hero) * 255)),
			revive  = g.revive_target(&f.state.players, player) if local else {},
		}
	}
	godot.push_data(f, hud)
}
