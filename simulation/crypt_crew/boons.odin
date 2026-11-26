// Boons: what a hero takes away from a floor. At the lift's bottom (Lift_Phase.Choosing, lift.odin) each present hero
// is offered BOON_OFFER boons and picks one (Command_Pick_Boon), which ranks it up, to BOON_RANK_MAX at most; the lift
// leaves once every present hero has picked, or at BOON_TIMEOUT_S, when whoever hasn't gets its first offer. A hero
// keeps its boons through a leave and a wipe (only its player leaving the session for good forgets them); the save
// doesn't hold them yet (docs/plan.md, the run's save at each lift).
//
// The offer is a keyed roll (boon_offer): named by the session's seed, the depth and the player, never by the tick, so
// the tick that grants a pick and the HUD that shows the cards compute the same three, whenever each asks. A pick names
// the card's index, so it means the same on every peer. Picks are read on paused ticks too (pick_boons runs before the
// co-op pause's early return): a command arrives once, and a pick dropped while paused would leave its panel waiting
// on a pick that never comes. What a boon does is read where its rule is: the helpers below, each a pure function of
// the hero's ranks.
package crypt_crew

import "unified:dmath"
import "unified:sim"

// What a hero can be granted at the lift, each ranked 0..BOON_RANK_MAX (Hero.boons).
Boon :: enum u8 {
	Thick_Hide, // THICK_HIDE_HP more health a rank
	Swift_Boots, // SWIFT_BOOTS faster a rank
	Keen_Edge, // KEEN_EDGE more damage a rank, on minions and elites
	Quick_Hands, // QUICK_HANDS shorter ability cooldowns a rank
	Strong_Back, // a rank leaves STRONG_BACK of the slowdown from a carried prop or the hoard
	Field_Medic, // FIELD_MEDIC faster revives a rank
}

// A hero's rank in each boon.
Boons :: [Boon]u8

// What a hero is offered: up to BOON_OFFER boons, `count` of them (fewer only once all but a few are at their top rank).
Boon_Offer :: struct {
	boons: [BOON_OFFER]Boon,
	count: int,
}

// `player`'s hero took `boon`, now at `rank`: its own pick, or its first offer at the timeout (`auto`). The boon panel
// locks its card and ticks the party's row on this event's CONFIRMED state alone.
Event_Boon_Picked :: struct {
	player: sim.Player,
	boon:   Boon,
	rank:   u8,
	auto:   bool,
}

// What `player`, holding `boons`, is offered at depth `depth`: BOON_OFFER distinct boons not at their top rank, drawn
// from those by a keyed roll (sim.roll_distinct_at, purpose Roll.Boon, the player's key and the depth); all of them, in
// order, when no more than that many are left. Pure: the tick (pick_boons) and the HUD both call it.
boon_offer :: proc(seed: u64, depth: u32, player: sim.Player, boons: Boons) -> (offer: Boon_Offer) {
	open: [len(Boon)]Boon
	count := 0
	for boon in Boon {
		if boons[boon] < BOON_RANK_MAX do open[count], count = boon, count + 1
	}
	if count <= BOON_OFFER {
		for i in 0 ..< count do offer.boons[i] = open[i]
		offer.count = count
		return
	}
	picks := sim.roll_distinct_at(seed, count, BOON_OFFER, Roll.Boon, sim.player_key(player), int(depth))
	for pick, i in picks do offer.boons[i] = open[pick]
	offer.count = BOON_OFFER
	return
}

// Whether `hero` has had its pick at depth `depth`: it picked (Hero.picked), or it has nothing left to pick (every boon
// at its top rank).
has_picked :: proc(hero: ^Hero, depth: u32) -> bool {
	if hero.picked == depth + 1 do return true
	for rank in hero.boons {
		if rank < BOON_RANK_MAX do return false
	}
	return true
}

// Each present player's Command_Pick_Boon, on every tick (paused ones too): while the lift waits on picks
// (Lift_Phase.Choosing), the pick of its hero's offer at `index` ranks that boon up, once per depth; any other pick (the
// lift not choosing, a second one, an index past the offer) is dropped.
pick_boons :: proc(t: ^Tick) {
	players := sim.iterate_present(t)
	for hero, player in sim.next(&players) {
		for sent in sim.commands(t, player) {
			pick := sent.(Command_Pick_Boon) or_continue
			if t.state.lift.phase != .Choosing || has_picked(hero, t.state.depth) do continue
			offer := boon_offer(t.seed, t.state.depth, player, hero.boons)
			if int(pick.index) < offer.count do grant_boon(t, player, offer.boons[pick.index], auto = false)
		}
	}
}

// The lift's wait ran out (BOON_TIMEOUT_S): every present hero that hasn't picked takes its first offer.
pick_for_the_late :: proc(t: ^Tick) {
	players := sim.iterate_present(t)
	for hero, player in sim.next(&players) {
		if has_picked(hero, t.state.depth) do continue
		offer := boon_offer(t.seed, t.state.depth, player, hero.boons)
		grant_boon(t, player, offer.boons[0], auto = true) // has_picked: something is left to offer
	}
}

// `player`'s hero takes `boon` at this depth: a rank up (Thick_Hide's pick heals the health it adds).
@(private = "file")
grant_boon :: proc(t: ^Tick, player: sim.Player, boon: Boon, auto: bool) {
	hero := sim.player_data(t, player)
	hero.boons[boon] += 1
	hero.picked = t.state.depth + 1
	if boon == .Thick_Hide && hero.action != .Down do hero.hp += THICK_HIDE_HP
	sim.emit(t, Event_Boon_Picked{player = player, boon = boon, rank = hero.boons[boon], auto = auto})
}

// A hero's full health: HERO_HP, and Thick_Hide's.
hero_max_hp :: proc(hero: ^Hero) -> i16 {
	return HERO_HP + THICK_HIDE_HP * i16(hero.boons[.Thick_Hide])
}

// What Swift_Boots multiplies a hero's speed by.
boots_scale :: proc(hero: ^Hero) -> f32 {
	return 1 + SWIFT_BOOTS * f32(hero.boons[.Swift_Boots])
}

// `damage` as `player`'s hero deals it: Keen_Edge's more, rounded (anyone else's, or nobody's, as it is).
edged_damage :: proc(t: ^Tick, player: sim.Player, damage: i16) -> i16 {
	hero := sim.player_data(t, player)
	if hero == nil || hero.boons[.Keen_Edge] == 0 do return damage
	edged := dmath.round(f32(damage) * (1 + KEEN_EDGE * f32(hero.boons[.Keen_Edge])))
	return i16(dmath.to_i32_clamped(edged, i32(damage), i32(max(i16))))
}

// An ability cooldown of `ticks` for `hero`: Quick_Hands' shorter, rounded.
hands_cooldown :: proc(hero: ^Hero, ticks: u32) -> u32 {
	if hero.boons[.Quick_Hands] == 0 do return ticks
	scaled := dmath.round(f32(ticks) * (1 - QUICK_HANDS * f32(hero.boons[.Quick_Hands])))
	return u32(dmath.to_i32_clamped(scaled, 1, i32(ticks)))
}

// What a load leaves of `hero`'s speed when it alone would leave `speed` (a prop's carry_speed, a haul's): Strong_Back
// takes off STRONG_BACK of the slowdown a rank.
back_speed :: proc(hero: ^Hero, speed: f32) -> f32 {
	slowdown := 1 - speed
	for _ in 0 ..< hero.boons[.Strong_Back] do slowdown *= STRONG_BACK
	return 1 - slowdown
}

// What a tick of `hero` tending a downed ally adds to its revive: REVIVE_UNIT, and Field_Medic's share more.
revive_rate :: proc(hero: ^Hero) -> u16 {
	rate := dmath.round(f32(REVIVE_UNIT) * (1 + FIELD_MEDIC * f32(hero.boons[.Field_Medic])))
	return u16(dmath.to_i32_clamped(rate, i32(REVIVE_UNIT), max(i32)))
}
