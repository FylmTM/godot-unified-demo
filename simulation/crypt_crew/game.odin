// crypt_crew (README.md): a top-down co-op dungeon crawler for 1-4 players, its rules as one deterministic sim that
// unified runs under rollback netcode.
//
// One system per file: game (this: the descriptor and the tick, its table of contents), tuning (every rule number),
// input (the input and the commands), state, events, world (the physics world, each level's floor: its navigation and
// places; init, entering a level and restarting it), presence (arrivals, leaves, where an arrival appears), heroes
// (facing, movement, read back), hands (grab, carry, drop, throw), attacks and abilities (the shared machinery of each)
// and a file per class (knight, barbarian with its heave, mage, rogue), bolts and fireballs (the Mage's), props (their
// bodies, hits, impacts and throws' ends), minions (targets, steering, swings, dying), director (sleeping packs, surges,
// held crowds and the benchmarks' populations), elites (Box3D skeletons: the shared rules) and a file per kind
// (elite_warrior, elite_rogue, elite_mage), health (damage, down, the wipe), revive (allies tending the downed), pause
// (the co-op pause), saves (the Setup a save is: the run, its tally and the heroes' boons), dev (the dev commands) and
// script (the scripted player); loot (coins dropped and the party's purse); the mechanisms: plates, gates, barricades
// and traps (spikes and the roller); ragdolls (a downed hero falls as one, and gets up); hoard (the gold chest hauled by
// its handles), lift (the floor's exit) and boons (picked at the lift); run (the hub, its shrines, a run's lives and
// end, the difficulty and the depth ramp) and arena (the Pit: the endless arena's waves and lulls); braziers (kindled,
// or lit by a fireball, a second way to open a gate), boss (the vault's fight round the Bone King) with elite_king (its
// approach, cleave and slam).
package crypt_crew

import "unified:physics"
import "unified:sim"

PLAYERS :: 4 // input slots: the most heroes in the game at once
TICK_HZ :: 64 // ticks per second of game time

// The game's version (sim.Game.version, part of the netcode's compat): bump it when a rule or constant changes what a
// tick computes without changing the State or Input layout, or two builds desync instead of refusing each other.
VERSION :: "31"

// The game's types for unified:sim: a physics World, a Setup (a new game or a save), a Profile per player.
Game :: sim.Game(State, Input, World, Event, Command, Setup, Profile, PLAYERS)
// What every system gets: the state, the world, the inputs and commands, the tick's player changes.
Tick :: sim.Tick(Game)

// The game: what the headless binary, the GDExtension and the tests run (its hooks: `uni doc sim Game`).
@(rodata)
GAME := Game {
	name              = "crypt_crew",
	version           = VERSION,
	tick_hz           = TICK_HZ,
	// game/levels/<name>.tscn's (uni bake), in Level_Id's order
	levels            = {
		{"floor_1", #load("../../game/levels/floor_1.level")},
		{"arena", #load("../../game/levels/arena.level")},
		{"workshop", #load("../../game/levels/workshop.level")},
		{"hub", #load("../../game/levels/hub.level")},
		{"floor_2", #load("../../game/levels/floor_2.level")},
		{"floor_3", #load("../../game/levels/floor_3.level")},
		{"vault", #load("../../game/levels/vault.level")},
	},
	world_create      = world_create,
	world_destroy     = world_destroy,
	extra             = extra,
	init              = init,
	tick              = tick,
	scripted_input    = scripted_input,
	scripted_commands = scripted_commands,
	scripted_profile  = scripted_profile,
	save              = save,
	setup_check       = setup_check, // saves.odin
	bench_prepare     = bench_prepare,
	// The game's row (today's play on Floor 1), and the crowd's on the arena (director.odin, Crowd): what sleepers,
	// a crowd on the move, a crowd in a fight and a fight that downs the party into ragdolls cost at the most any floor
	// holds.
	benches           = {
		{
			what     = "floor 1: four heroes against a held surge among the props",
			entities = BENCH_FLOOR_MINIONS,
			ticks    = 600,
		},
		{
			name     = "crowd_idle",
			what     = "the arena: a crowd asleep out of sight of four heroes standing still",
			setup    = "floor=arena,crowd=idle",
			entities = MINION_CAP,
			ticks    = 600,
		},
		{
			name     = "crowd_chase",
			what     = "the arena: a crowd chasing four heroes who walk and never attack",
			setup    = "floor=arena,crowd=chase",
			entities = MINION_CAP,
			ticks    = 600,
		},
		{
			name     = "crowd_fight",
			what     = "the arena: a crowd around four heroes who hold Attack, the felled rising again",
			setup    = "floor=arena,crowd=fight",
			entities = MINION_CAP,
			ticks    = 600,
		},
		{
			name     = "crowd_wipe",
			what     = "the arena: the crowd's fight, its blows downing the four heroes into ragdolls under it",
			setup    = "floor=arena,crowd=wipe",
			entities = MINION_CAP,
			ticks    = 600,
		},
	},
}

// The tick's timing zones (sim.zone): the dev UI's stacked graph, and the groups its draw toggles name.
Zone :: enum u8 {
	Presence,
	Commands,
	Heroes,
	Director,
	Minions,
	Physics,
	Strikes,
	Props,
	Health,
	Elites,
	Loot,
	Pieces, // the mechanisms: plates, gates, barricades, traps
	Lift, // the hoard's holds and the lift (hoard.odin, lift.odin)
}

// One tick: the systems in their order, each group a timing zone.
tick :: proc(t: ^Tick) {
	{
		sim.zone(t, Zone.Presence)
		update_presence(t) // first: people come and go while paused
		apply_pause(t) // the pause's own command is read on paused ticks too
		pick_boons(t) // and so are the boons' picks: a pick sent during a pause counts (boons.odin)
	}
	if t.paused do return // the co-op pause: no system runs, physics.step included
	{
		sim.zone(t, Zone.Commands)
		apply_dev_commands(t)
	}
	{
		sim.zone(t, Zone.Heroes)
		if !choosing(t) { 	// at the lift's bottom a hero's input is its boon panel's: it only picks (lift.odin)
			revive_heroes(t) // first: the press that starts a revive grabs nothing
			kindle_braziers(t) // then a brazier's kindling, which that press doesn't start (braziers.odin)
			face_heroes(t)
			press_shrines(t) // run.odin: a press the hands would take (shrine_target) turns no shrine
			use_hands(t) // after facing: a grab takes what the hero now faces
			use_abilities(t) // after the hands: hands full start none
			start_attacks(t) // after the hands and abilities: a throw's or a charge's Attack press starts no attack
		}
		update_holds(t)
		move_heroes(t)
	}
	{
		sim.zone(t, Zone.Director)
		locate_heroes(t)
		update_pit(t) // arena.odin: before the director, which a lull holds
		raise_surges(t)
		wake_packs(t)
	}
	{
		sim.zone(t, Zone.Minions)
		target_heroes(t)
		move_minions(t)
	}
	{
		sim.zone(t, Zone.Elites)
		wake_elites(t)
		move_elites(t) // after the minions: their pass read the elites where the last step left them
	}
	{
		sim.zone(t, Zone.Pieces)
		drive_gates(t) // before the step: from the plates as the last step left them
		drive_rollers(t)
	}
	{
		sim.zone(t, Zone.Physics)
		drive_lift(t) // the deck's velocity for this step (lift.odin)
		physics.step(t.world.phys)
		read_back_heroes(t)
		read_back_elites(t)
		read_back_ragdolls(t) // a downed hero's pos is its pelvis
		settle_ragdolls(t) // after the read-back: one that fell out of the level is gone
	}
	t.world.strike_grid = false // the first query after the step builds it (strike_grid): a tick without one builds none
	{
		sim.zone(t, Zone.Pieces)
		read_plates(t) // after the step: what it pressed, broke and carried onto the spikes
		break_barricades(t) // before anything destroys a body: the step's joint events name the joints it reported
		spring_traps(t)
	}
	{
		sim.zone(t, Zone.Lift)
		hold_hauls(t) // a hold stretched too far lets go (hoard.odin)
		settle_hoard(t) // a let-go hoard come to rest weighs its rest again (hoard.odin)
		update_lift(t) // the lift's phase moves on, and the party may descend (lift.odin)
		update_run(t) // a run's end takes the party back to the hub (run.odin)
	}
	{
		sim.zone(t, Zone.Strikes)
		resolve_strikes(t) // after the step: a blow lands on where things are now
		charge_strikes(t)
		fly_bolts(t)
		fly_fireballs(t)
		land_heaves(t)
		prop_hits(t)
	}
	{
		sim.zone(t, Zone.Props)
		prop_impacts(t)
		elite_impacts(t) // after the impacts: it reads the contacts they gathered
		age_throws(t)
	}
	{
		sim.zone(t, Zone.Health)
		age_minions(t) // after the step: a swing lands on where the hero is now
		age_elites(t)
		update_boss(t) // after the elites age: the King woken, its ward broken by the braziers lit (boss.odin)
		check_wipe(t)
	}
	{
		sim.zone(t, Zone.Loot)
		collect_loot(t) // last: a hero picks up where it stands now, after a wipe's restart took the floor's coins
	}
}
