// Loot: the coins felled skeletons drop, and the party's one purse (State.gold) they go into. A coin is a row of the
// State's `loot`, lying where it fell, worth its `value`; any hero up whose feet come within LOOT_RADIUS of it picks it
// up, once it has lain LOOT_ARM_S, and one nobody picks up goes after LOOT_LIFE_S. Two heroes at one coin on the same
// tick: the lower slot takes it (heroes are walked in slot order), so every peer agrees whatever order inputs came in.
//
// Whether a death drops, and what, are keyed rolls named by the session's count of drop rolls (State.drops), never by
// the tick: a dev kill is a command and a pause holds game time, so when a kill lands moves no outcome (unified's
// docs/gameplay.md, Randomness). drop_loot is the one way coins appear: a drop's `count` coins worth `total` between
// them, what an elite's death calls with its own count and total.
//
// What the purse shows is the view's honesty test: a pickup shows as soon as it is predicted (the coin gone, a glint)
// but counts only once it is CONFIRMED (game/play/purse.gd), so a pickup a rollback takes back, or hands to another
// hero, never moves the purse or plays a chime that turns out wrong. Event_Loot_Collected carries the purse's total for
// that reason: the view takes it from the confirmed event rather than adding up predictions.
package crypt_crew

import "unified:dmath"
import "unified:sim"

// A coin on the floor, a row of the State's `loot`.
Loot :: struct {
	pos:     [3]f32, // where it lies, on the walkable floor
	dropped: sim.Game_Time, // when it fell: it is armed LOOT_ARM_TICKS later and gone LOOT_LIFE_TICKS later
	value:   u16, // the gold it is worth
	_pad:    [2]u8,
}

// `loot`, worth `value`, fell at `position`.
Event_Loot_Dropped :: struct {
	loot:     sim.Handle(Loot),
	position: sim.Position,
	value:    u16,
}

// `player`'s hero picked up `loot`, worth `value`, at `position`, bringing the party's purse to `gold`. The view counts
// the purse from this event's CONFIRMED state alone, so `gold` is the total as the verified timeline has it then.
Event_Loot_Collected :: struct {
	loot:     sim.Handle(Loot),
	player:   sim.Player,
	position: sim.Position,
	value:    u16,
	gold:     u32,
}

// A felled minion's drop (damage_minion, at its death): one coin, on a roll of 1 in LOOT_ONE_IN, worth
// LOOT_VALUE_MIN ..= LOOT_VALUE_MAX, lying where it fell. Every death counts a drop roll, dropping or not, so the next
// death's roll is the same whichever tick it lands on. None under a held crowd (director.odin, Crowd): its felled come
// back by the hundred, and a crowd's rows measure the crowd.
drop_minion_loot :: proc(t: ^Tick, at: [3]f32) {
	if t.setup.crowd != .None do return
	key := u64(t.state.drops)
	t.state.drops += 1
	if value := minion_drop(t.seed, key); value > 0 do drop_loot(t, at, 1, value)
}

// What the minion death behind drop roll `key` drops: the gold of its coin, 0 for none. A pure function of the
// session's seed and the key (sim.roll_below_at at tick 0), so a test can ask it of any roll.
minion_drop :: proc(seed: u64, key: u64) -> int {
	if sim.roll_below_at(seed, 0, LOOT_ONE_IN, Roll.Drop, key, 0) != 0 do return 0
	return LOOT_VALUE_MIN + int(sim.roll_below_at(seed, 0, LOOT_VALUE_MAX - LOOT_VALUE_MIN + 1, Roll.Drop, key, 1))
}

// `count` coins worth `total` between them (coin_value) fall at `at`: one coin there, more evenly on a ring `spread`
// round it, each moved onto the walkable floor within `spread` (else at `at`). Each emits Event_Loot_Dropped. A coin
// with no free row is lost: MAX_LOOT is far more than a floor leaves lying.
drop_loot :: proc(t: ^Tick, at: [3]f32, count: int, total: int, spread: f32 = LOOT_SPREAD) {
	if count <= 0 do return
	floor := floor_of(t)
	for i in 0 ..< count {
		value := coin_value(total, count, i)
		if value <= 0 do continue
		pos := at
		if count > 1 {
			dir := dmath.angle_vec(f32(i) / f32(count))
			if spot, on_floor := floor_spot(floor, at + {dir.x, 0, dir.y} * spread, spread); on_floor {
				pos = spot.point
			}
		}
		coin, handle := sim.spawn(&t.state.loot) or_break
		coin^ = {
			pos     = pos,
			dropped = t.time,
			value   = u16(dmath.min(value, 0xffff)),
		}
		sim.emit(t, Event_Loot_Dropped{loot = handle, position = sim.Position(pos), value = coin.value})
	}
}

// The gold of coin `i` of a drop of `count` coins worth `total` between them: total / count, the first total % count
// of them one more, so the coins add up to the total exactly.
coin_value :: proc(total: int, count: int, i: int) -> int {
	return total / count + int(i < total % count)
}

// Every coin: one LOOT_LIFE_TICKS old goes; one armed (LOOT_ARM_TICKS old) is picked up by the first hero up, in slot
// order, within LOOT_RADIUS of it, its value added to the purse. A coin is still there on its last tick, so a touch
// then takes it; the tick after, it is gone. After the step and the strikes: heroes pick up where they stand now, and
// a coin dropped this tick lies its arming out.
collect_loot :: proc(t: ^Tick) {
	coins := sim.iterate(&t.state.loot)
	for coin, handle in sim.next(&coins) {
		age := u32(t.time - coin.dropped)
		if age >= LOOT_LIFE_TICKS {
			sim.despawn(&t.state.loot, handle)
			continue
		}
		if age < LOOT_ARM_TICKS do continue
		heroes := sim.iterate_present(t)
		for hero, player in sim.next(&heroes) {
			if hero.action == .Down || dmath.length_sq(hero.pos.xz - coin.pos.xz) > LOOT_RADIUS * LOOT_RADIUS do continue
			t.state.gold += u32(coin.value)
			collected := Event_Loot_Collected {
				loot     = handle,
				player   = player,
				position = sim.Position(coin.pos),
				value    = coin.value,
				gold     = t.state.gold,
			}
			sim.emit(t, collected)
			sim.despawn(&t.state.loot, handle)
			break
		}
	}
}
