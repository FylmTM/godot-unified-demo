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
	minions:     u16, // minions alive (the newest prediction, like all of it)
	paused:      bool, // the co-op pause (the State's Clock)
	_pad:        u8,
	paused_by:   sim.Player, // who paused it (its key; 0: nobody)
	surges:      u32, // the surges the party has faced, a save's included
	kills:       u32, // the skeletons it has felled, a save's included (a prediction: the HUD never counts it back)
	// The party's purse (a prediction, a save's included): the HUD's purse takes it once, when it shows, and from then on
	// counts from CONFIRMED pickups alone (game/play/purse.gd), never from this.
	gold:        u32,
	heroes:      [g.PLAYERS]Hud_Hero, // by slot
	// ---- the lift and boons (lift.odin, boons.odin)
	lift:        g.Lift_Phase, // EnumLiftPhase: Choosing opens the boon panels (a late joiner's too)
	// The hoard rests partly on the deck, unheld, while the lift waits: the HUD says it must be wholly on (the rules'
	// hoard_on_deck: hoard_hanging)
	overhang:    bool,
	_pad_lift:   [2]u8,
	lift_since:  sim.Game_Time, // when the lift's phase began: the choosing's countdown runs from it (constants.boon_timeout)
	depth:       u32, // the floors the party has gone down
	// ---- the boss (boss.odin): its bar across the top while it is awake and alive (boss_hp_max > 0)
	boss_hp:     i16,
	boss_hp_max: i16, // its full health (0: no boss awake: the bar hides)
	boss_stage:  u8, // 1 to 3
	boss_warded: bool, // its ward is up: the bar says how many braziers are lit of how many it needs
	ward_lit:    u8,
	ward_need:   u8,
}

// One slot's hero (DataHudHero).
Hud_Hero :: struct {
	player:      sim.Player, // its key (0: the slot is empty)
	hp:          i16,
	hp_max:      i16, // its full health: the HUD's bar is hp of hp_max
	class:       g.Class, // EnumClass
	local:       bool, // one of this machine's players
	// Its state as the plate shows it: down (until an ally revives it), and how ready its ability is, 0 (its cooldown
	// just began) to 255 (ready: the pip full).
	down:        bool,
	ability:     u8,
	// A local hero's: the ally its Interact would revive now (the rules' revive_target: the "[E] Revive" prompt; 0:
	// nobody, or not a local hero).
	revive:      sim.Player,
	// ---- the hoard and boons (hoard.odin, boons.odin)
	boons:       g.Boons, // its rank in each boon, by EnumBoon: the plate's pips
	// What it is offered at the lift's bottom (the rules' boon_offer, the cards the pick's index names), the first
	// `offer_count` of them.
	offer:       [g.BOON_OFFER]g.Boon,
	offer_count: u8,
	picked:      bool, // it has had its pick at this depth (has_picked, as the state has it: a prediction)
	// A local hero's: the hoard's handle its Interact would take now (the rules' haul_target: the "[E] Haul" prompt;
	// EnumHaulHandle.NONE: none, or not a local hero).
	haul:        g.Haul_Handle,
	// ---- braziers (braziers.odin)
	// A local hero's: the brazier its Interact would kindle now (the rules' kindle_target, unless the press would revive
	// an ally: the "[E] Light" prompt; the null handle: none, or not a local hero).
	kindle:      sim.Handle(g.Brazier),
}

// The HUD's data from the frame's state.
fill_hud :: proc(f: ^Frame) {
	hud := Data_Hud {
		minions    = u16(g.minions_alive(&f.state.minions)),
		paused     = f.state.clock.paused,
		paused_by  = f.state.paused_by,
		surges     = f.state.surges,
		kills      = f.state.kills,
		gold       = f.state.gold,
		lift       = f.state.lift.phase,
		overhang   = hoard_hanging(f),
		lift_since = f.state.lift.since,
		depth      = f.state.depth,
	}
	heroes := sim.iterate_present(&f.state.players)
	for hero, player in sim.next(&heroes) {
		slot, _ := sim.player_slot(&f.state.players, player)
		local := godot.is_local(f, player)
		hud.heroes[slot] = {
			player  = player,
			hp      = hero.hp,
			hp_max  = g.hero_max_hp(hero),
			class   = hero.class,
			local   = local,
			down    = hero.action == .Down,
			ability = u8(dmath.round(g.ability_charge(f.time, hero) * 255)),
			revive  = g.revive_target(&f.state.players, player) if local else {},
			boons   = hero.boons,
			picked  = g.has_picked(hero, f.state.depth),
			haul    = g.haul_target(f.world.phys, &f.state.hoard, &f.state.lift, hero) if local else .None,
		}
		offer := g.boon_offer(f.seed, f.state.depth, player, hero.boons) // the tick's own roll: the same cards
		hud.heroes[slot].offer = offer.boons
		hud.heroes[slot].offer_count = u8(offer.count)
		if local && hud.heroes[slot].revive == {} do hud.heroes[slot].kindle = kindle_of(f, player)
	}
	fill_boss_hud(f, &hud)
	godot.push_data(f, hud)
}

// The brazier `player`'s hero would kindle now (the rules' kindle_target, on the frame's state and floor).
kindle_of :: proc(f: ^Frame, player: sim.Player) -> sim.Handle(g.Brazier) {
	defs := sim.slice(&f.world.floors[f.state.level.id].places.braziers)
	return g.kindle_target(&f.state.players, &f.state.braziers, defs, player)
}

// The boss's bar: the King's health once it is awake and while it lives, its stage, and its ward's braziers (lit, and
// the need for the heroes present, as the rules' ward_need counts it).
fill_boss_hud :: proc(f: ^Frame, hud: ^Data_Hud) {
	boss := &f.state.boss
	king := sim.get(&f.state.elites, boss.elite)
	if boss.stage == 0 || boss.hp_max == 0 || king == nil || king.phase == .Dying do return
	hud.boss_hp, hud.boss_hp_max = dmath.max(king.hp, 0), boss.hp_max
	hud.boss_stage, hud.boss_warded = boss.stage, boss.warded
	lit := 0
	braziers := sim.iterate(&f.state.braziers)
	for brazier in sim.next(&braziers) do lit += int(brazier.lit)
	present := dmath.clamp(sim.present_count(&f.state.players), 1, g.PLAYERS)
	hud.ward_lit, hud.ward_need = u8(lit), u8(g.BOSS_WARD_NEED[present - 1])
}

// Whether the hoard hangs over the deck's edge: the sensor over the deck sees it, its box isn't wholly over the deck,
// nobody holds it and the lift waits (the rules' hoard_on_deck, on the World's scratch, as the tick asks it).
hoard_hanging :: proc(f: ^Frame) -> bool {
	hoard, lift := &f.state.hoard, &f.state.lift
	if hoard.haulers != {} || lift.phase != .Waiting do return false
	seen, wholly := g.hoard_on_deck(f.world.phys, hoard, lift, &f.world.overlaps)
	return seen && !wholly
}
