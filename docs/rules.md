# Crypt Crew's rules

What the simulation does, in the order a tick does it (`simulation/crypt_crew/game.odin`); every number is a named
constant in `tuning.odin`. How to play is [`playing.md`](playing.md).

## The tick

1. **Presence.** Leavers drop what they carry (or are let go of, heaved) and their bodies go. An arriving hero takes the
   class its Profile asks for, else the one it played, else a free one, and appears beside the party: the first spot
   around the lowest-slot hero up, ARRIVAL_RING out (then twice that), on the floor, reachable in a straight line,
   ARRIVAL_CLEAR of minions and elites and ARRIVAL_ROOM clear of heroes and props; with none, at its slot's hero spawn.
   Within a floor a leaver comes back as it left: its hit points, its cooldown, down if it was.
2. **Pause.** `Set_Paused` stops or starts the game clock; while paused, nothing after this runs.
3. **Dev commands.**
4. **Heroes.** Interact pressed within REVIVE_RANGE of a downed ally starts a revive (through a held Attack, too), held
   it goes on (at REVIVE_SPEED, no attack meanwhile; a blow breaks it off): each ally tending adds a tick, untended it
   decays by REVIVE_DECAY, and at REVIVE_TICKS the ally rises where it lies (its ragdoll gone, on the walkable floor
   nearest the floor under its pelvis within RAGDOLL_SNAP, else on the nearest spot RAGDOLL_RINGS rings round it find,
   else by its reviver) with REVIVE_HP, safe for SPAWN_GRACE_S; the reviver carries on to another downed ally in range.
   Each hero turns to its aim (else its move, past TURN_STICK). Interact grabs the nearest prop in reach (GRAB_RANGE,
   GRAB_CONE_COS) or drops the one held; Attack while holding throws it (THROW_WINDUP_S, THROW_SPEED and THROW_LIFT; a
   Barbarian's BARBARIAN_THROW times as fast). Ability starts the class's ability (cutting an attack short), on its own
   cooldown: the Knight's block while held (blows from within BLOCK_ARC_COS of its facing take BLOCK_TAKE; BLOCK_SPEED)
   and, on Attack's press behind it, a charge (CHARGE_SPEED for CHARGE_S, a blast of CHARGE_RADIUS from the shield every
   CHARGE_HIT_TICKS, every blow from the front taken); the Rogue's roll (ROLL_SPEED for ROLL_S along the stick, unhurt
   for ROLL_SAFE_S); the Mage's cast (FIREBALL_WINDUP_S, then a fireball lobbed to where its aim reaches, up to
   FIREBALL_RANGE, short of a wall); the Barbarian's heave (the nearest elite or downed ally in the grab's cone, never
   an ally who is up: an elite hangs limp on the hold at HEAVE_HOLD_HEIGHT, weighing HEAVE_MASS and borne by the hold, a
   downed ally's ragdoll by its chest bone at that height, RAGDOLL_MASS being HEAVE_MASS; Attack throws it as a prop is
   thrown, an elite through every hero, until it lands, and held HEAVE_MAX_S it is let down; HEAVE_COOLDOWN_S from its
   landing or its letting down). Otherwise Attack held starts the class's attack (`CLASS_SPECS`: windup, duration,
   cooldown; held, it repeats every cooldown). The hold's joint follows the facing (`HOLD_*`), and the hero walks toward
   the stick's velocity at its class's speed, slowed by a carried prop or by what it does (ATTACK_SPEED, BLOCK_SPEED,
   REVIVE_SPEED, HEAVE_SPEED).
5. **Director.** A sleeping pack wakes when a hero one of its minions can see comes within AGGRO_RADIUS (each looks
   every SIGHT_S) or one of them is hit. A surge is owed SURGE_FIRST_S into a floor and every SURGE_EVERY_S after:
   SURGE_BASE minions plus SURGE_PER_HERO per hero and SURGE_GROWTH per surge faced on the floor, rising one per grave
   every RISE_GAP_S where no minion stands within SEPARATION (RISE_TRIES places tried) at graves out of sight beyond
   SURGE_NEAR and within SURGE_FAR of the party, up to the floor's cap alive (CROWD_DENSITY to the square metre of
   walkable floor, at most MINION_CAP) and never into more rows than the table has free. Every ELITE_SURGE_EVERY-th
   surge on a floor brings an elite too (a Warrior, a Rogue, a Mage in turn) at one of its graves, while fewer than
   ELITES_ALIVE_MAX are alive. A Setup may hold a crowd instead (`floor=arena,crowd=fight`): the floor's cap placed on
   the first tick, asleep, chasing or fighting, the felled coming back, its heroes taking no damage (but under
   `crowd=wipe`, where the crowd's blows down them into ragdolls), never wiping, no elite and no drop; the benchmark
   rows and the scale tests play it.
6. **Minions.** Each picks the nearest hero up by path (every RETARGET_S), steers along that hero's field (every tick
   within STEER_NEAR of it or in its chase's first ticks, else every STEER_S, walking its facing between), keeps
   SEPARATION from its neighbours (where they stood when the moves began) and out of the props' and elites' footprints,
   gives way to those within QUEUE_REACH (it slides round them, steps aside when held up, and stops at QUEUE_STOP: the
   back rows of a hero's queue wait behind its front), stands MINION_STAND inside its reach to swing, and carries its
   knockback (KNOCK_DECAY, at most KNOCK_MAX); knocked faster than KNOCK_STAGGER it staggers, walking at nothing and
   swinging at nothing.
7. **Elites.** A floor's elites (its `elite` markers) sleep until a hero comes into sight within AGGRO_RADIUS or one is
   hit; a sleeper is a dormant character (no drive, a capsule Box3D lets sleep) until it wakes. Awake, each is a Box3D
   character (ELITE_DENSITY, ELITE_GROUND_FORCE, turning at most ELITE_TURN_COS a tick) after the nearest hero up by
   path, its kind's way (`ELITE_SPECS`: health, speed, damage, windup): the Warrior walks its target's field and swings
   in reach (ELITE_REACH, ELITE_STRIKE_COS); the Rogue circles to FLANK_BEHIND behind its target, lunges at LUNGE_SPEED
   and backs off for FLANK_RETREAT_S; the Mage keeps MAGE_NEAR to MAGE_FAR from its target, casts a bone bolt every
   BONE_BOLT_EVERY_S at one in sight within BONE_BOLT_RANGE, and raises SUMMON_COUNT minions every SUMMON_EVERY_S. A
   heaved elite's rules stand still until it lands or is let down.
8. **Physics.** The lift's deck is driven to where its phase puts it; Box3D steps; the heroes' and elites' feet and
   velocities are read back into the state (a downed hero's are its ragdoll's pelvis's; a ragdoll fallen
   RAGDOLL_KILL_DEPTH below the floor goes, a heave on it let go of, and its hero lies anew at its spawn), and a ragdoll
   come to rest on the level alone sleeps after RAGDOLL_STILL_TICKS still. Then the hoard and the lift: a hold on the
   hoard stretched past HOARD_SLIP lets go, and the lift moves through its phases (below, The hoard, the lift and
   boons).
9. **Strikes.** A blow lands at its windup on the minions and elites in its reach and arc, or touching the hero
   (`CLASS_SPECS`, STRIKE_TOUCH), and shoves the props there. Bolts fly at BOLT_SPEED for BOLT_LIFE_S and burst at the
   first thing they meet (BURST_RADIUS, BURST_DAMAGE; a blast, its knock falling off to BLAST_RIM of it at the rim:
   `knock_area`); a skeleton Mage's bone bolts fly at BONE_BOLT_SPEED for BONE_BOLT_LIFE_S and burst on the first hero
   up or wall. The crossbow hits the first thing within CROSSBOW_RANGE on the picture its shooter saw (at most
   MAX_REWIND_S back). Walls shield what is behind them from blows, bursts, blasts and shots; bolts and shots fly at
   FLIGHT_HEIGHT, over low cover and resting light props, and meet walls, heavy crates, elites and props held or in
   flight. A fireball bursts FIREBALL_FLIGHT_S after its cast: a blast (FIREBALL_RADIUS, FIREBALL_DAMAGE,
   FIREBALL_KNOCK) on the skeletons and an impulse on the bodies (FIREBALL_IMPULSE, FIREBALL_LIFT of it up, fading over
   FIREBALL_FALLOFF): the props free of a hold, the elites, the hoard unheld (at HOARD_MASS until it settles again),
   each downed hero's ragdoll nobody heaves (each bone its share) and each barricade, which breaks to it. A thrown elite
   lands once the floor is HEAVE_LAND_GAP under it, a thrown ragdoll once its pelvis falls within RAGDOLL_LAND_REACH of
   it (or either HEAVE_FLIGHT_MAX_S on): a blast (HEAVE_LAND_RADIUS, HEAVE_LAND_DAMAGE, HEAVE_LAND_KNOCK), a thrown
   elite taking the blow itself and a stagger; an elite stands again, a downed ally lies still down. An elite takes a
   blow as a minion does, except that a Warrior's shield takes all but ELITE_GUARD_TAKE of one from within
   ELITE_GUARD_COS of its facing (staggered or broken, none), and a knock moves its body by ELITE_KNOCK_TAKE of it
   (knocks and pushes together at most ELITE_KNOCK_MAX; none on a held elite), staggering it ELITE_STAGGER_S from
   ELITE_STAGGER_KNOCK. A charge's, a fireball's and a landing's blast break the guard first, for GUARD_BREAK_S. A
   thrown prop faster than PROP_HIT_SPEED hurts each minion it meets once (PROP_HIT_DAMAGE, at most PROP_HITS_MAX,
   keeping PROP_HIT_KEEP of its velocity) for the whole of its throw (THROWN_S).
10. **Props.** A prop landing faster than IMPACT_SPEED is an impact. A thrown prop that hits an elite at PROP_HIT_SPEED
    breaks its guard and hurts it, once per throw. A thrown prop passes through its thrower until it is THROW_CLEAR_DIST
    away or its throw ends.
11. **Health.** A chasing minion within MINION_REACH winds up a swing (MINION_WINDUP_S), which lands (MINION_DAMAGE) if
    its hero is still in reach, in front (MINION_STRIKE_COS) and in sight; an elite's attack lands at its windup as its
    kind says. Every blow on a hero, a bone bolt's too, meets its block and its roll; the dead fall for DEATH_S. A hero
    at 0 HP goes down and stays down until revived: it falls as a Box3D ragdoll (RAGDOLL_SCALE tall, RAGDOLL_MASS, at
    its velocity, at most RAGDOLL_CARRY_MAX, plus RAGDOLL_KICK away from the blow or RAGDOLL_TIP backwards from a blow
    from no side) that meets everything but heroes and elites, its capsule dormant and out of the world meanwhile (its
    sleep and its fall out of the level are step 8's). Every hero down for WIPE_S restarts the floor, but under a held
    crowd.
12. **Loot.** A felled skeleton drops a coin on a roll of 1 in LOOT_ONE_IN, worth LOOT_VALUE_MIN to LOOT_VALUE_MAX gold;
    a felled elite drops ELITE_COINS coins worth its kind's ELITE_GOLD between them, on a LOOT_SPREAD ring (none under a
    held crowd). A hero up within LOOT_RADIUS of a coin that has lain LOOT_ARM_S picks it up into the party's one purse
    (two at once: the lower slot); a coin nobody takes goes after LOOT_LIFE_S. The save carries the purse as it stood at
    the last surge; a wipe takes the coins lying on the floor and keeps the purse.

## Mechanisms

A floor's Box3D pieces (plates.odin, gates.odin, barricades.odin, traps.odin): before the step each gate's motor is set
from its plates and each roller driven along its path; after it, plates, barricades and traps are read. A plate is
pressed once its slab sinks past PLATE_ON under anything weighing more than PLATE_LOAD, and released above PLATE_OFF. A
gate lifts GATE_RISE while `need` of its plates are pressed and its braziers lit (a latched one stays up), and closes
pressing at most GATE_CLOSE_FORCE; below GATE_PASS it keeps minions back. A barricade breaks to a blow (a thrown prop, a
charge, a hurled body) touching it as its weld strains past BARRICADE_BREAK_N: the blow decides, and the threshold is
its floor, since a hero walking into the fence strains it harder than a thrown crate; a fireball's blast that reaches it
breaks it outright. Its fence then lies loose (CAT_PROP), a prop to everything but the hoard, which a hauler drags
through it. Spikes are up SPIKES_UP_S of every SPIKES_PERIOD_S on the game clock from their phase, or while their plate
is pressed, striking SPIKES_DAMAGE as they rise and every SPIKES_HIT_TICKS; the roller, on the clock too, strikes
ROLLER_DAMAGE what touches it every ROLLER_HIT_TICKS. A level keeps a hero's width between a roller's sides and every
wall or low cover along its whole path (a kinematic pillar pushes on through what it squeezes), which
`every_roller_keeps_room_to_pass_it` holds; low cover on a level's edge carries an invisible wall (a `Rims` body,
CAT_WALL) up to a wall's height, so nothing thrown leaves the level over it; and the hoard's lanes keep clear of plates
(a dragged end catches on a slab's edge: `every_haul_lane_is_clear`). The hoard's box is a hull with chamfered bottom
edges (HOARD_CHAMFER): a dragged end slides over the tiles' seams.

Floor 1's way out: the vault east of the great hall, its gate (`need` 2, latched) opened by two plates, one in the spike
gallery before it and one in the passage north of the gallery; the gallery's two spike tiles (phases half a period
apart) and the roller between them and the plates; the passage, round the traps, closed at the hall by a barricade. The
hoard rests in the vault, a sleeping pack beside it.

## The hoard, the lift and boons

The floor's hoard (its `hoard` marker: Floor 1's in its vault) is hauled to its lift (its `lift` marker: a deck over a
shaft by the spawns). Interact beside one of the hoard's two handles takes it (before any prop; the "[E] Haul" prompt
says when): the hero's hold lifts the handle to HOARD_HOLD_HEIGHT with at most HOARD_LIFT of the hoard's weight, so one
hauler lifts an end and drags it at HOARD_DRAG_SPEED, and two carry it clear at HOARD_CARRY_SPEED. A hauler does nothing
else; Interact again, going down, leaving, or the hold stretched past HOARD_SLIP lets go. Unheld and settled, it weighs
HOARD_REST_MASS: it goes where it is hauled, never shoved, and presses a plate it rests on. A hand takes it only while
the lift waits at the top; the deck is floor like any until it goes (minions walk onto it), and the HUD says when the
hoard rests hanging over its edge. The first grab on a floor brings the surges every HAUL_SURGE_S. Once the hoard rests
on the deck with nobody holding it and every present hero is aboard (the downed too), at least one up, the lift goes
down LIFT_HOLD_S later (anyone stepping off waits it again): LIFT_DROP in LIFT_RIDE_S, nobody taking damage and no wipe
from then. At the bottom each present hero picks one of three boons (Thick Hide, Swift Boots, Keen Edge, Quick Hands,
Strong Back, Field Medic, each up to BOON_RANK_MAX ranks), offered by a keyed roll of the seed, the run and its choice,
and the player, its input driving the boon panel alone; once all have picked, or at BOON_TIMEOUT_S (the first offer for
whoever hasn't), the party goes down to the next floor: the depth up, HOARD_GOLD in the purse, the downed up at
REVIVE_HP, and the save made there. A hero arriving while the lift is busy lands on its deck, clear of the hoard and the
others, and is waited for. Boons are kept through a leave and a wipe until the next run begins; the save holds them by
each player's profile id, and a member's first arrival in a continued session takes its own back once.

## The run

A session starts in the hub (`run.odin`), the graveyard between runs: nothing hurts, no skeleton rises, nobody wipes.
Its two shrines (`shrine` markers) set the next run's mode (the crypt, or the Pit) and difficulty: an Interact press
nothing else would take turns one, at most once every SHRINE_COOLDOWN_S, until the hub's lift boards. The hub's lift
(`hoard = false`) goes with everyone aboard and no hoard, and at its bottom the run begins: the tally and the boons go,
the lives are the difficulty's (DIFFICULTY), and the party is on the crypt's first floor. The crypt goes down Floor 1,
the Ossuary (Floor 2), the Deep Halls (Floor 3) and the vault (FLOOR_ORDER, `lift.odin`), a lift's descent each time and
never past the vault, which has no lift: the King's fall there wins the run. A wipe costs a life: the floor starts over
from its save point, the purse and the felled back at the save's; the last life ends the run. Either ending shows the
results for RUN_END_S, then the party is back in the hub. Hard (DIFFICULTY) has fewer lives and tougher, harder-hitting,
more numerous skeletons that pay more; each floor down adds SURGE_PER_DEPTH to a surge and DEPTH_HP to a skeleton's
health. The Pit (`arena.odin`) is the arena's endless waves with one life: wave n every PIT_SURGE_S, PIT_BASE +
PIT_GROWTH × n and SURGE_PER_HERO a hero; after every PIT_BOON_EVERY-th the next holds until at most PIT_LULL stand (or
PIT_LULL_MAX_S), then the rest fall, the downed rise and a boon choice opens. The Pit keeps no save; its score is the
results panel's.

## Braziers and the boss

A floor's braziers (its `brazier` markers, at their stands) are a second way to open a gate: a lit one counts toward its
gate's `need` as a pressed plate does. A hero up, hands free, holding Interact within BRAZIER_RANGE kindles one (the
"[E] Light" prompt says when; a press starts it, as a revive's does), and it lights after BRAZIER_LIGHT_S of kindling,
two kindlers twice as fast; a blow, letting go or walking off breaks the kindling and the brazier loses its progress. A
Mage's fireball bursting within BRAZIER_BLAST lights it at once, unless a wall stands between. A lit brazier stays lit,
and each lighting brings the next surge within BRAZIER_SURGE_S.

The vault's boss, the Bone King (its `boss` marker; boss.odin, elite_king.odin), is an elite of its own kind: a Warrior
BOSS_SCALE times as big, never knocked, staggered or heaved, asleep until a hero comes into sight or hits it. It wakes
with BOSS_HP and BOSS_HP_PER_HERO for each other hero present, times the difficulty's. Its guard is the Warrior's,
broken for BOSS_GUARD_DOWN_S by a thrown prop, a charge or a fireball. It cleaves every hero within BOSS_CLEAVE_REACH in
front of it. At two thirds and one third of its health it roars, every brazier goes out, and it is warded (no blow hurts
it) while it walks to its marker; BOSS_SUMMON skeletons rise at the graves and the surges come every BOSS_SURGE_S until
BOSS_WARD_NEED of the braziers (by the heroes present) are lit. No blow takes it past a stage's end. From its second
stage it slams every BOSS_SLAM_EVERY_S (BOSS_SLAM_FAST_S in its third, where it also moves BOSS_STAGE_SPEED faster): a
ring of BOSS_SLAM_RADIUS on the floor for BOSS_SLAM_WINDUP_S, then BOSS_SLAM_DAMAGE to every hero up inside that no wall
shields, thrown back, and Box3D's explosion through the props and ragdolls. Its fall puts BOSS_GOLD in the purse and
wins the run (no surge rises after it; the save is the hub's again); a wipe starts the vault over, at a life's cost.
