// The recorded plays: each two-player replay regression in replays/ that a script of game/tools records (`./uni coop
// --rerecord <name>`: coop_lan_pair.gd, coop_haul.gd, coop_king.gd) holds every beat of its play, replayed here, so a
// play that changes what it does fails, and `uni coop --record` keeps no recording that misses a beat. In every one a
// Knight host holds slot 0 and a Barbarian joiner slot 1. the_replays_reproduce (suite_test.odin) holds each one's
// results tick by tick; these hold what it shows.
package test_crypt_crew

import "core:testing"
import "unified:dmath"
import "unified:physics"
import "unified:sim"

import g "../crypt_crew"

// The LAN recording (coop_lan_pair.gd): each grabs and throws props, a thrown prop hits a skeleton, each one's blows
// land, the joiner pauses and the host resumes, the Mage's bolt and the Rogue's shot land, the host's dev kill and its
// downing, and the surges rise; so the regression holds the strikes' results.
@(test)
the_lan_recording_holds_its_play :: proc(t: ^testing.T) {
	replay, ok := replay_open(t, #load("replays/lan_pair/inputs.unil"), #load("replays/lan_pair/snapshot.unis"))
	defer replay_close(&replay)
	if !ok do return
	// What each slot did, by its hero's class at the time: its grabs, throws, hits by source, pauses and resumes.
	Played :: struct {
		classes:         bit_set[g.Class],
		grabs, throws:   int,
		hits:            [g.Hit_Source]int,
		paused, resumed: int,
		downed:          int,
	}
	played: [2]Played
	surges: u32
	for replay_step(&replay) {
		simulation := replay.simulation
		for slot in 0 ..< len(played) {
			if hero := sim.slot_data(simulation, slot); hero != nil && hero.class != .Any do played[slot].classes += {hero.class}
		}
		for &raw in sim.events_at(simulation, simulation.tick) {
			#partial switch event in sim.event_value(&raw, g.Event) {
			case g.Event_Prop_Grabbed:
				if slot, in_play := play_slot(simulation, event.player); in_play do played[slot].grabs += 1
			case g.Event_Prop_Thrown:
				if slot, in_play := play_slot(simulation, event.player); in_play do played[slot].throws += 1
			case g.Event_Minion_Hit:
				if slot, in_play := play_slot(simulation, event.player); in_play do played[slot].hits[event.source] += 1
			case g.Event_Paused:
				if slot, in_play := play_slot(simulation, event.player); in_play {
					if event.paused do played[slot].paused += 1
					else do played[slot].resumed += 1
				}
			case g.Event_Hero_Downed:
				if slot, in_play := play_slot(simulation, event.player); in_play do played[slot].downed += 1
			case g.Event_Surge:
				if event.surge > surges do surges = event.surge
			}
		}
	}
	host, joiner := &played[0], &played[1]
	testing.expectf(t, host.classes == {.Knight, .Mage}, "the host plays the Knight, then the Mage: %v", host.classes)
	testing.expectf(
		t,
		joiner.classes == {.Barbarian, .Rogue},
		"the joiner the Barbarian, then the Rogue: %v",
		joiner.classes,
	)
	for slot in played {
		testing.expectf(t, slot.grabs >= 2 && slot.throws >= 2, "each grabs and throws twice: %v", played)
		testing.expectf(t, slot.hits[.Blow] > 0, "each one's blows land: %v", played)
	}
	testing.expectf(t, host.hits[.Prop] > 0, "the host's thrown prop hits: %v", host.hits)
	testing.expectf(t, host.hits[.Bolt] > 0 && joiner.hits[.Crossbow] > 0, "the bolt and the shot land: %v", played)
	testing.expectf(t, joiner.paused > 0 && host.resumed > 0, "the joiner pauses, the host resumes: %v", played)
	testing.expectf(t, host.hits[.Dev] > 0 && host.downed > 0, "the host's dev kill and its downing: %v", host)
	testing.expectf(t, surges >= 4, "four surges rise: %d", surges)
}

// The haul (coop_haul.gd), Floor 1's way out: the vault's gate opens to its two plates; the two carry the hoard by its
// two handles, every tick of it clear of a slip, from the vault past the roller and across the spikes (both holding it
// from east of the roller to west of the spikes); the joiner heaves the downed host, throws it and revives it; the two
// carry the hoard onto the lift's deck (both holding it there); and the party descends with it.
@(test)
the_haul_recording_holds_its_play :: proc(t: ^testing.T) {
	replay, ok := replay_open(t, #load("replays/haul/inputs.unil"), #load("replays/haul/snapshot.unis"))
	defer replay_close(&replay)
	if !ok do return
	classes: [2]bit_set[g.Class]
	grabs: [2]int
	gate_open, slipped, heaved, rescued, on_deck: bool
	descended: u32
	carried: bool // both held the hoard at some tick
	east, west: f32 // the hoard's farthest east and west while both held it
	roller, spikes: [3]f32
	for replay_step(&replay) {
		simulation := replay.simulation
		state := &simulation.state
		for slot in 0 ..< 2 {
			if hero := sim.slot_data(simulation, slot); hero != nil && hero.class != .Any do classes[slot] += {hero.class}
		}
		if state.level.id == .Floor_1 && state.hoard.body != {} {
			if roller == {} do for def in sim.slice(&simulation.world.floors[.Floor_1].places.traps) {
				if def.kind == .Roller do roller = def.pos
				else if def.pos.z < spikes.z || spikes == {} do spikes = def.pos // the north spikes, on the lane
			}
			if state.hoard.haulers[0] != {} && state.hoard.haulers[1] != {} {
				phys := simulation.world.phys
				chest := physics.body_position(phys, state.hoard.body)
				east = dmath.max(east, chest.x) if carried else chest.x
				west = dmath.min(west, chest.x) if carried else chest.x
				carried = true
				if state.lift.body != {} {
					deck := physics.body_position(phys, state.lift.body)
					off := chest.xz - deck.xz
					if abs(off.x) < g.LIFT_HALF.x && abs(off.y) < g.LIFT_HALF.z do on_deck = true
				}
			}
		}
		for &raw in sim.events_at(simulation, simulation.tick) {
			#partial switch event in sim.event_value(&raw, g.Event) {
			case g.Event_Gate:
				if event.open do gate_open = true
			case g.Event_Hoard_Grabbed:
				if slot, in_play := play_slot(simulation, event.player); in_play do grabs[slot] += 1
			case g.Event_Hoard_Dropped:
				if event.slipped do slipped = true
			case g.Event_Heave_Landed:
				if slot, in_play := play_slot(simulation, event.player); in_play && slot == 1 do heaved = true
			case g.Event_Hero_Revived:
				host, _ := play_slot(simulation, event.player)
				by, in_play := play_slot(simulation, event.by)
				if in_play && host == 0 && by == 1 do rescued = true
			case g.Event_Descended:
				descended = event.depth
			}
		}
	}
	testing.expectf(t, classes == {{.Knight}, {.Barbarian}}, "a Knight host and a Barbarian joiner: %v", classes)
	testing.expect(t, gate_open, "the vault's gate opens to its two plates")
	testing.expectf(t, grabs[0] >= 2 && grabs[1] >= 2, "each takes its handle, twice: %v", grabs)
	testing.expectf(
		t,
		carried && east > roller.x + g.ROLLER_HALF.x && west < spikes.x - g.SPIKES_HALF,
		"the two carry the hoard from east of the roller (%v) to west of the spikes (%v): %v to %v",
		roller.x,
		spikes.x,
		east,
		west,
	)
	testing.expect(t, !slipped, "no hold slips")
	testing.expect(t, heaved && rescued, "the joiner heaves the downed host and revives it")
	testing.expect(t, on_deck, "the two carry the hoard onto the lift's deck")
	testing.expectf(t, descended == 1, "the party descends with it: depth %d", descended)
}

// The King (coop_king.gd), in the vault: it is driven into its second stage and the two break its ward together, each
// lighting a brazier; it slams with braziers burning; driven into its third, they break its ward together again; and
// it falls to their blows, the last a hero's own.
@(test)
the_king_recording_holds_its_play :: proc(t: ^testing.T) {
	replay, ok := replay_open(t, #load("replays/king/inputs.unil"), #load("replays/king/snapshot.unis"))
	defer replay_close(&replay)
	if !ok do return
	classes: [2]bit_set[g.Class]
	stage: u8 // the King's latest stage
	lit: [4][2]int // braziers each slot lit, by the stage they were lit in
	breaks: [4]bool // the ward broke in each stage, both having lit a brazier in it first
	slam_lit, fallen, struck: bool
	last_blow: g.Hit_Source = .Dev
	for replay_step(&replay) {
		simulation := replay.simulation
		for slot in 0 ..< 2 {
			if hero := sim.slot_data(simulation, slot); hero != nil && hero.class != .Any do classes[slot] += {hero.class}
		}
		for &raw in sim.events_at(simulation, simulation.tick) {
			#partial switch event in sim.event_value(&raw, g.Event) {
			case g.Event_Boss_Stage:
				stage = event.stage
			case g.Event_Brazier:
				if slot, in_play := play_slot(simulation, event.player); in_play && event.lit do lit[stage][slot] += 1
			case g.Event_Boss_Ward:
				if !event.up && lit[stage][0] > 0 && lit[stage][1] > 0 do breaks[stage] = true
			case g.Event_Boss_Slam:
				braziers := sim.iterate(&simulation.state.braziers)
				for brazier in sim.next(&braziers) do slam_lit ||= brazier.lit
			case g.Event_Elite_Hit:
				if _, in_play := play_slot(simulation, event.player); in_play && event.damage > 0 {
					last_blow = event.source
					struck ||= event.source == .Blow
				}
			case g.Event_Boss_Defeated:
				fallen = true
			}
		}
	}
	testing.expectf(t, classes == {{.Knight}, {.Barbarian}}, "a Knight host and a Barbarian joiner: %v", classes)
	testing.expectf(
		t,
		breaks[2] && breaks[3],
		"the two break the ward in its second and third stages: %v %v",
		breaks,
		lit,
	)
	testing.expect(t, slam_lit, "the King slams with braziers burning")
	testing.expect(t, fallen && struck, "the King falls to the heroes' blows")
	testing.expectf(t, last_blow == .Blow, "the last blow is a hero's own: %v", last_blow)
}

// A replay regression's recording played back tick by tick (replay_open, replay_step, replay_close).
@(private = "file")
Replay :: struct {
	input_log:  sim.Input_Log(g.Game),
	simulation: ^sim.Sim(g.Game),
	next:       int, // the log's next tick
}

// The recording `inputs` (inputs.unil) from `snapshot` (snapshot.unis), at its first tick; false (the failure
// reported) when either doesn't load.
@(private = "file")
replay_open :: proc(t: ^testing.T, inputs, snapshot: []u8) -> (replay: Replay, ok: bool) {
	decoded: bool
	replay.input_log, decoded = sim.log_decode(inputs, g.Game)
	if !testing.expect(t, decoded, "inputs.unil decodes") do return
	err: sim.Snap_Error
	replay.simulation, err = sim.from_snapshot(&g.GAME, snapshot, any_build = true)
	return replay, testing.expectf(t, err == .None, "snapshot.unis loads: %v", err)
}

// Steps the recording's next tick; false once it has none left.
@(private = "file")
replay_step :: proc(replay: ^Replay) -> bool {
	if replay.simulation == nil || replay.next >= len(replay.input_log.ticks) do return false
	inputs := sim.log_inputs(&replay.input_log, replay.next)
	sim.step(replay.simulation, &inputs)
	replay.next += 1
	return true
}

@(private = "file")
replay_close :: proc(replay: ^Replay) {
	if replay.simulation != nil do sim.destroy(replay.simulation)
	sim.log_destroy(&replay.input_log)
}

// The slot of a play's `player` (its two players hold slots 0 and 1); false for anyone else.
@(private = "file")
play_slot :: proc(simulation: ^sim.Sim(g.Game), player: sim.Player) -> (slot: int, ok: bool) {
	slot, ok = sim.player_slot(simulation, player)
	return slot, ok && slot < 2
}
