// The Rogue's attack: a crossbow shot, hitscan on the strike tick, resolved on the picture its shooter saw. Rollback
// already takes the network out of a shot (the shooter's input is resolved against the state it predicted); what is
// left is the input delay, which the input's sim.Seen measures. So the shot looks back sim.seen_rewind (capped at
// MAX_REWIND_S): the shooter's eye moved back by its own velocity, each minion tested where it was (its position less
// its velocity, which is its real displacement per second), the bodies by world_cast_ray_closest_rewound. The nearest
// hit wins: a minion or an elite (a body: the rewound ray meets it where it was) takes the bolt; a prop it meets is
// shoved; a wall stops it; it flies over low cover and resting light props (FLIGHT_HEIGHT). It never pierces. The view
// draws a tracer.
//
// The Rogue's ability: a dodge roll. Ability's press rolls (Action.Roll) along the stick, else the facing, which the
// roll takes for its own and keeps: a dash at ROLL_SPEED for ROLL_S, nothing hurting the Rogue for its first
// ROLL_SAFE_S (rolled_clear, judged by the roll's age: no state of its own).
package crypt_crew

import "unified:dmath"
import "unified:physics"
import "unified:sim"

// `player`'s crossbow shot from `from` to `to` (where it stopped, or its range's end), `hit` when it struck a minion or
// an elite.
Event_Crossbow_Shot :: struct {
	player: sim.Player,
	from:   sim.Position,
	to:     sim.Position,
	hit:    bool,
}

// The Rogue's blow lands: one shot along its facing, CROSSBOW_RANGE long, on the world as its shooter saw it.
rogue_strike :: proc(t: ^Tick, hero: ^Hero, player: sim.Player) {
	spec := &CLASS_SPECS[.Rogue]
	rewind := sim.seen_rewind(t, sim.input(t, player).seen, MAX_REWIND_S)
	eye := hero.pos + {0, FLIGHT_HEIGHT, 0} - hero.vel * rewind
	shot := [3]f32{hero.facing.x, 0, hero.facing.y} * CROSSBOW_RANGE
	reach: f32 = 1 // of the shot, before something stops it
	hit, struck := physics.world_cast_ray_closest_rewound(
		t.world.phys,
		eye,
		shot,
		rewind,
		SHOT_FILTER,
		physics.link(hero.body.body),
	)
	if struck do reach = hit.fraction
	victim: sim.Handle(Minion)
	minions := sim.iterate(&t.state.minions)
	for minion, handle in sim.next(&minions) {
		if minion.phase == .Dying do continue
		seen_at := minion.pos.xz - minion.vel.xz * rewind
		if fraction, meets := segment_meets_circle(eye.xz, shot.xz, seen_at, MINION_RADIUS);
		   meets && fraction < reach {
			victim, reach = handle, fraction
		}
	}
	elite: sim.Handle(Elite) // the elite it struck, when no minion stood first
	if victim == {} && struck && hit.category & CAT_ELITE != 0 do elite = sim.handle_of_key(Elite, hit.tag)
	if victim != {} {
		damage_minion(t, victim, spec.damage, hero.facing, spec.knock, player, .Crossbow)
	} else if elite != {} {
		damage_elite(t, elite, spec.damage, hero.facing, spec.knock, player, .Crossbow, eye.xz)
	} else if struck && hit.category & CAT_PROP != 0 {
		if prop := sim.get(&t.state.props, sim.handle_of_key(Prop, hit.tag)); prop != nil {
			shove_prop(t, prop, hero.facing, spec.prop_knock)
		}
	}
	shot_event := Event_Crossbow_Shot {
		player = player,
		from   = sim.Position(eye),
		to     = sim.Position(eye + shot * reach),
		hit    = victim != {} || elite != {},
	}
	sim.emit(t, shot_event)
}

// The Rogue's ability: Ability pressed while free (can_start_ability) and its cooldown ran out rolls along the stick
// (pushed past TURN_STICK), else along the facing; the hero turns to the roll and keeps that facing through it.
rogue_ability :: proc(t: ^Tick, hero: ^Hero, player: sim.Player, buttons: sim.Button_State(Buttons)) {
	if .Ability not_in buttons.pressed || !can_start_ability(hero) || sim.timer_running(t, hero.ability_ready) do return
	input := sim.input(t, player)
	if move := dmath.stick(input.move_x, input.move_z); dmath.length_sq(move) > TURN_STICK * TURN_STICK {
		hero.facing = dmath.normalize(move)
	}
	start_ability(t, hero, player, .Roll, ROLL_COOLDOWN_TICKS)
	dash(t, hero, ROLL_SPEED)
}
