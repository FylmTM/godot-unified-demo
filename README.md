# Crypt Crew

[![ci](https://github.com/FylmTM/godot-unified-demo/actions/workflows/ci.yml/badge.svg?branch=main&event=push)](https://github.com/FylmTM/godot-unified-demo/actions/workflows/ci.yml?query=branch%3Amain+event%3Apush)

The demo game of [unified](https://github.com/FylmTM/godot-unified): co-op games with deterministic rollback netcode,
the rules written in Odin, Godot as the host for rendering, audio, UI and the editor. Crypt Crew is a top-down co-op
dungeon crawler for 1–4 players, and the answer to "what does a real game built on unified look like?".

> [!NOTE]
> **Floor 1, with the game around it.** Up to four heroes, on one couch, over the LAN or online (from the menus: a host
> and its joiners, by address or by a lobby's code), fight down Floor 1 of the crypt: skeleton packs asleep in its rooms
> and surges rising from its graves, with skeleton Warriors behind their shields, Rogues that flank and Mages that
> cast and summon, against the Knight's quick sword, shield and shield charge, the Barbarian's wide cleave and its
> heave, which throws an elite into a pack or a downed ally to safety, the Mage's bursting bolts and fireball, and the
> Rogue's crossbow and dodge roll, and the barrels and crates any hero picks up and throws. Felled skeletons drop coins
> into the party's purse. A hero at 0 HP goes down until an ally revives it; the whole party down restarts the floor.
> What the game becomes, and in what order, is [`docs/plan.md`](docs/plan.md).

## Play it

You need git, curl and a C toolchain for Odin's linker: clang on macOS and Linux, Visual Studio Build Tools on
Windows. The first `./uni` downloads the pinned Odin; each command fetches what else it needs (Godot, Box3D) the
first time. Nothing is installed by hand. On Windows, run `uni.cmd` instead of `./uni`.

```sh
git clone --recursive https://github.com/FylmTM/godot-unified-demo
cd godot-unified-demo
./uni run                            # play it in a window, from the title
./uni run -- --host-port 7777        # host a game on the LAN, straight past the title...
./uni run -- --join 127.0.0.1:7777   # ...and join it from a second window
./uni run -- --autostart --setup floor=arena,crowd=chase  # the arena, a crowd of hundreds chasing you
./uni tool lookdev --window --shots  # the art, posed in the look-dev scene
./uni help                           # every command
```

**From the menus.** The title offers Continue (the saved crypt), New game, Play together, Settings and Quit. To play
two windows together on one machine, run `./uni run` twice: Play together, Host on this network in one, Join an
address (`127.0.0.1`) in the other.

**Controls.** Move with WASD, the arrow keys or a pad's left stick; aim with the mouse or the right stick (a hero
that isn't aimed faces where it walks). Attack (the left mouse button, Space, or a pad's right trigger or X) attacks
while held, and throws what you carry. Grab (E, the right mouse button, or a pad's A) picks up the barrel or crate in
front, glowing faintly, and puts it down again; held beside a downed ally ("[E] Revive" over them), it revives them.
Ability (Left Shift, or a pad's left trigger or B) is the class's own: the Knight blocks while it is held, and charges
behind the shield on Attack; the Rogue rolls; the Mage casts a fireball where the ring on the floor shows (the mouse's
reach); the Barbarian heaves the elite or the downed ally in front, and throws it on Attack; the HUD's pip says when
it is ready again. Esc, or Start on a pad that plays, opens the pause menu.
Attack, Grab and Ability can be rebound on both the keyboard and mouse and a pad, and the moves on the keyboard (Settings,
Controls: two bindings each; a pad's sticks and D-pad stay); the HUD shows each player's controls in the glyphs of the
device they use: for a few seconds after a player joins or picks up another device, or always, or never (Settings,
Gameplay).

**Hero select.** Every new game starts there: four seats, the device that came there in the first; another pad's
Start or A takes the next free one. The keyboard and mouse sit only in the first seat: they are the first player's.
Each seat answers to its own device: left and right step its hero (Any, or one of the four; two may pick the same),
accept readies it, back takes the ready back and then gives the seat up. Once every seat taken is ready, the first
seat's accept starts the game; an Any becomes a class nobody picked. Each place's last pick is remembered (the
first seat's, the second's, ...), and your name (Settings, Gameplay; a game's own name until you choose one) is what
the other players see.

**Couch co-op.** Alone, the first player plays with any device, the keyboard and mouse or a pad, and can switch at
will. Another pad's Start mid-game opens a card on the HUD where it picks its hero, then joins with A (B gives up);
from then on the first player keeps the device they last played with. A guest's Back (the pad's View or Select)
opens a card to drop out (A drops out, B stays). A toast names who joined or left, and as which hero. Four play at
most. Players joining over the LAN join the same session beside them.

**Saves and pauses.** The crypt saves itself each time a surge rises (the floor, the surges faced, the skeletons
felled, the gold in the purse), in one slot; Continue on the title starts it again from there. Only the host, or a player alone, keeps it: a
player in someone else's game keeps the host's last save in memory (from the start, when the host continued a crypt),
and is offered "Continue on your own" if the host leaves: it takes that save as its own (asking first if it replaces
one) and continues it through hero select. Alone (couch included) the pause menu pauses the game; online (hosted or
joined, on the LAN too) the game runs on under it, and "Pause for everyone" pauses it for every player (anyone may
resume it), the banner naming who paused. Alone, the game also pauses when its window goes to the background
(Settings, Gameplay).

**Playing together.** Play together on the title hosts a game (online, by a lobby code; or on this network, by this
machine's address) or joins one (with a code, or an address), each side's couch picking its heroes first; Rejoin
last game joins the last one again. Hosting online starts the crypt at once and gets its code while it plays. In
play the HUD shows the code or address and how many play; the pause menu's Invite friends opens a game played alone
to friends (online or on this network), with Copy and Stop inviting. A couch guest is named after the first player
("Sexton +1"). A game that can't start, or ends, says why; a lost link shows a plate while the game reconnects.

**Online (EOS).** Online play needs the demo's own Epic product and the EOS SDK, which the repo never holds: without
them the online rows are greyed with the reason, and everything else plays. To try it, follow
[`unified/docs/EOS.md`](unified/docs/EOS.md): create a product "Crypt Crew" in the Epic developer portal, a custom
client policy with only Lobbies and a client using it; download the EOS C SDK at the version `unified/pins.cfg`
pins and unzip it outside the repo; write the repo's `.env` (`UNIFIED_EOS_SDK` and the five `UNIFIED_EOS_*` IDs).
Then `./uni setup` (it says whether the SDK is found), `./uni tool online_check` (hosts online from the menus), and
`./uni coop`, `./uni coop --menus`, `./uni coop --rejoin`, `./uni coop --crash` (one at a time).

## What it shows of unified

- **Rollback and prediction**: the whole game is one plain state block (`simulation/crypt_crew/state.odin`) that
  unified copies, restores and checksums; the views draw the prediction, a local hero turned by its newest input, and
  the ring where a local Mage's fireball will land, from the rules' own fireball_target on that input
  (`simulation/extension/frame.odin`).
- **Physics under rollback**: heroes are `physics.Character` capsules (`heroes.odin`) and props dynamic bodies
  (`props.odin`); a carried prop hangs on a motor joint, and a thrown one ignores its thrower's contacts
  (`hands.odin`); a fireball's blast is an impulse on the props' and elites' Box3D bodies, walls shielding them
  (`fireballs.odin`); elites are `physics.Character` capsules too, a sleeper dormant until it wakes
  (`character_set_dormant`, `elites.odin`), and a body the Barbarian heaves goes limp on the same hold, then flies
  through every hero, its filter's mask changed until it lands (`character_set_limp`, `shape_set_filter`:
  `barbarian.odin`).
- **Shots resolved where the shooter saw them**: the Rogue's crossbow looks back by its input's `sim.Seen`
  (`rogue.odin`).
- **Navigation**: minions walk the floor's navigation mesh along memoized distance fields, kept apart over a
  `sim.Grid` (`minions.odin`, `world.odin`).
- **Keyed rolls**: surges and packs roll on the state they place (`director.odin`), and a felled skeleton's drop on the
  session's count of drop rolls (`loot.odin`), so when a pause or a command lands moves no outcome.
- **Late join and rejoin beside the party** (`presence.odin`), a player's hero kept for their return.
- **Online and LAN, from the menus**: hosting and joining by a lobby code or an address (`game/menu/play_together.gd`,
  `join_code.gd`, `join_address.gd`); the code's cells and alphabet, and a paste read as the library reads a code
  (`UnifiedSession.join_code_alphabet`, `clean_join_code`: `game/ui/widgets/code_field.gd`); whether online play can
  start, asked before trying (`online_problem`: the greyed rows); EOS lobbies in the extension and the headless binary
  (`simulation/extension/`, `simulation/headless/`).
- **Open to friends**: a game played alone opened online or on the LAN and closed again while it plays
  (`open_online`, `open_direct`, `close_online`: `Game.invite`, `game/play/friends_screen.gd`); hosting online is the
  same opening, made as the crypt comes up. The HUD's session panel shows the code, the count and a slow link
  (`link_slow`, `round_trip_ms`: `game/play/session_panel.gd`).
- **Both pauses**: alone, the pause menu stops the session's clock (`UnifiedSession.paused`); with others, its Pause
  for everyone is the co-op pause (`pause.odin`), the game clock standing for every peer, and the State keeps who
  paused, so a late joiner's banner names them too (`game/play/pause_menu.gd`). A game opened while paused alone is
  paused for everyone at once. Alone, the game also pauses when its window loses the focus (`game/app/game.gd`).
- **Setup and save**: a new game or a save is the session's Setup; the sim gives a save at each surge (`saves.odin`),
  unified hands it over from verified ticks only, and the app keeps it as JSON in one slot (`game/app/saves.gd`);
  Continue starts a session on it, and a joiner whose host left continues its last one alone (`game/app/game.gd`).
- **Menus over a running game**: while a menu shows, the session reads no game input (`game_input`), and a button
  held through it counts only once released (`game/app/game.gd`).
- **The session outlives the scenes**: the `Game` autoload owns it from boot to quit and switches between the title
  and the crypt on its status, whoever started it: the menus, the command line's session flags (`uni run`, `uni coop`,
  `uni drive`) or a tool. A start that fails, or a game that ends without the player leaving, comes back to the title
  with the reason; a join or a leave is a toast; a reconnect is a plate over the held game (`game/app/game.gd`).
- **Views**: scene views (`game/views/`), props pooled; the Mage's bolts and the minions MultiMeshes (`MultiView`),
  shown once their spawn is verified (`Appear.Verified`); clips posed on the session's shown game time, so a
  correction or a seek lands on the right frame (`game/views/hero.gd`, `game/crowd/crowd_minion.gdshader`).
- **A crowd of hundreds** (The crowd, below): unified's crowd bake (`UnifiedCrowdBake`, `UnifiedCrowdCheck`,
  `crowd_skin.gdshaderinc`) and the host's ages (`View_Policy.ages`).
- **Events**: effects play as soon as they are predicted (EMITTED: `game/play/play.gd`, `effects.gd`); a join or a
  leave is told once it is CONFIRMED (`game/app/game.gd`), and so are a revive's toast and chime and the wipe's banner
  (`game/play/play.gd`).
- **Rewards shown when confirmed**: a coin picked up vanishes and glints as predicted, but the party's purse counts it,
  chimes and floats its "+N" only once the pickup is CONFIRMED, taking the total the confirmed event carries, so a
  pickup a rollback takes back (CANCELLED) never moves it (`game/play/purse.gd`); coins appear once their drop is
  verified (`Appear.Verified`, `game/views/coins.gd`), and `uni coop --lan -- --lag 150` shows the purse holding
  through dozens of mispredicted pickups (`game/tools/coop.gd`, `purse_watch.gd`).
- **Couch co-op**: hero select's seats become local players, each with its device and Profile, and pads join and drop
  out mid-game (`add_local_player`, `set_local_device`, `remove_local_player`: `game/play/couch.gd`,
  `game/menu/hero_select.gd`); every local hero framed by one camera (`camera_rig.gd`).
- **Prompts and rebinding**: each local player's prompts in the glyphs of the device the session gives them
  (`get_local_device`: `game/app/prompts.gd`); attack, grab and the keyboard's moves rebound in the InputMap that
  unified's input helpers read (`game/app/bindings.gd`).
- **Dev commands** (`dev.odin`): a class swap, spawning, hurting and killing, dropping coins, as dev UI forms and
  `uni drive command`.
- **Benchmark rows**: four heroes against a held surge among Floor 1's props, and a crowd of MINION_CAP on the arena
  asleep, chasing and fighting, each row's population chosen by its Setup (`benches` in `game.odin`; `Crowd`,
  `place_crowd` and `bench_prepare` in `director.odin`).

## The rules

One tick, in order (`simulation/crypt_crew/game.odin`); every number is a named constant in `tuning.odin`.

1. **Presence.** Leavers drop what they carry (or are let go of, heaved) and their bodies go. An arriving hero takes
   the class its Profile asks for, else the one it played, else a free one, and appears beside the party: the first
   spot around the lowest-slot hero up, ARRIVAL_RING out (then twice that), on the floor, reachable in a straight line,
   ARRIVAL_CLEAR of minions and elites and ARRIVAL_ROOM clear of heroes and props; with none, at its slot's hero spawn.
   Within a floor a leaver comes back as it left: its hit points, its cooldown, down if it was.
2. **Pause.** `Set_Paused` stops or starts the game clock; while paused, nothing after this runs.
3. **Dev commands.**
4. **Heroes.** Interact pressed within REVIVE_RANGE of a downed ally starts a revive (through a held Attack, too),
   held it goes on (at REVIVE_SPEED, no attack meanwhile; a blow breaks it off): each ally tending adds a tick,
   untended it decays by REVIVE_DECAY, and at REVIVE_TICKS the ally rises where it lies (its ragdoll gone, on the
   walkable floor nearest the floor under its pelvis within RAGDOLL_SNAP, else on the nearest spot RAGDOLL_RINGS rings
   round it find, else by its reviver) with REVIVE_HP, safe for SPAWN_GRACE_S; the reviver carries on to another downed ally in range. Each hero turns to its aim (else its move,
   past TURN_STICK). Interact grabs the nearest prop in reach (GRAB_RANGE, GRAB_CONE_COS) or drops the one held;
   Attack while holding throws it (THROW_WINDUP_S, THROW_SPEED and THROW_LIFT; a Barbarian's BARBARIAN_THROW times
   as fast). Ability starts the class's ability (cutting an attack short), on its own cooldown: the Knight's block
   while held (blows from within BLOCK_ARC_COS of its facing take BLOCK_TAKE; BLOCK_SPEED) and, on Attack's press
   behind it, a charge (CHARGE_SPEED for CHARGE_S, a blast of CHARGE_RADIUS from the shield every CHARGE_HIT_TICKS,
   every blow from the front taken); the Rogue's roll (ROLL_SPEED for ROLL_S along the stick, unhurt for
   ROLL_SAFE_S); the Mage's cast (FIREBALL_WINDUP_S, then a fireball lobbed to where its aim reaches, up to
   FIREBALL_RANGE, short of a wall); the Barbarian's heave (the nearest elite or downed ally in the grab's cone, never
   an ally who is up: its body hangs limp on the hold at HEAVE_HOLD_HEIGHT, weighing HEAVE_MASS and borne by the
   hold; Attack throws it as a prop is thrown, through every hero until it lands, and held HEAVE_MAX_S it is let
   down; HEAVE_COOLDOWN_S from its landing or its letting down). Otherwise Attack held starts
   the class's attack (`CLASS_SPECS`: windup, duration, cooldown; held, it repeats every cooldown). The hold's joint
   follows the facing (`HOLD_*`), and the hero walks toward the stick's velocity at its class's speed, slowed by a
   carried prop or by what it does (ATTACK_SPEED, BLOCK_SPEED, REVIVE_SPEED, HEAVE_SPEED).
5. **Director.** A sleeping pack wakes when a hero one of its minions can see comes within AGGRO_RADIUS (each looks
   every SIGHT_S) or one of them is hit. A surge is owed SURGE_FIRST_S into a floor and every SURGE_EVERY_S after:
   SURGE_BASE minions plus SURGE_PER_HERO per hero and SURGE_GROWTH per surge faced on the floor, rising one per grave
   every RISE_GAP_S where no minion stands within SEPARATION (RISE_TRIES places tried) at graves out of sight beyond
   SURGE_NEAR and within SURGE_FAR of the party, up to the floor's cap alive (CROWD_DENSITY to the square metre of
   walkable floor, at most MINION_CAP) and never into more rows than the table has free. Every ELITE_SURGE_EVERY-th
   surge on a floor brings an elite too (a Warrior, a Rogue, a Mage in turn) at one of its graves, while fewer than
   ELITES_ALIVE_MAX are alive. A Setup may hold a crowd instead (`floor=arena,crowd=fight`): the floor's cap placed on
   the first tick, asleep, chasing or fighting, the felled coming back, its heroes taking no damage, no elite and no
   drop; the benchmark rows and the scale tests play it.
6. **Minions.** Each picks the nearest hero up by path (every RETARGET_S), steers along that hero's field (every
   tick within STEER_NEAR of it or in its chase's first ticks, else every STEER_S, walking its facing between), keeps
   SEPARATION from its neighbours (where they stood when the moves began) and out of the props' and elites' footprints,
   gives way to those within QUEUE_REACH (it slides round them, steps aside when held up, and stops at QUEUE_STOP: the
   back rows of a hero's queue wait behind its front), stands MINION_STAND inside its reach to swing, and carries its
   knockback (KNOCK_DECAY, at most KNOCK_MAX); knocked faster than KNOCK_STAGGER it staggers, walking at nothing and
   swinging at nothing.
7. **Elites.** A floor's elites (its `elite` markers) sleep until a hero comes into sight within AGGRO_RADIUS or one is
   hit; a sleeper is a dormant character (no drive, a capsule Box3D lets sleep) until it wakes. Awake, each is a Box3D
   character (ELITE_DENSITY, ELITE_GROUND_FORCE, turning at most ELITE_TURN_COS a tick) after the nearest hero up by
   path, its kind's way (`ELITE_SPECS`: health, speed, damage, windup): the Warrior walks its target's field and
   swings in reach (ELITE_REACH, ELITE_STRIKE_COS); the Rogue circles to FLANK_BEHIND behind its target, lunges at LUNGE_SPEED and
   backs off for FLANK_RETREAT_S; the Mage keeps MAGE_NEAR to MAGE_FAR from its target, casts a bone bolt every
   BONE_BOLT_EVERY_S at one in sight within BONE_BOLT_RANGE, and raises SUMMON_COUNT minions every SUMMON_EVERY_S. A
   heaved elite's rules stand still until it lands or is let down.
8. **Physics.** Box3D steps; the heroes' and elites' feet and velocities are read back into the state (a downed
   hero's are its ragdoll's pelvis's).
9. **Strikes.** A blow lands at its windup on the minions and elites in its reach and arc, or touching the hero
   (`CLASS_SPECS`, STRIKE_TOUCH), and shoves the props there. Bolts fly at BOLT_SPEED for BOLT_LIFE_S and burst at the
   first thing they meet (BURST_RADIUS, BURST_DAMAGE; a blast, its knock falling off to BLAST_RIM of it at the rim:
   `knock_area`); a skeleton Mage's bone bolts fly at BONE_BOLT_SPEED for BONE_BOLT_LIFE_S and burst on the first hero
   up or wall. The crossbow hits the first thing within CROSSBOW_RANGE on the picture its shooter saw (at most
   MAX_REWIND_S back). Walls shield what is behind them from blows, bursts, blasts and shots; bolts and shots fly at
   FLIGHT_HEIGHT, over low cover and resting light props, and meet walls, heavy crates, elites and props held or in
   flight. A fireball bursts FIREBALL_FLIGHT_S after its cast: a blast (FIREBALL_RADIUS, FIREBALL_DAMAGE,
   FIREBALL_KNOCK) on the skeletons and an impulse on the props' and elites' bodies (FIREBALL_IMPULSE, FIREBALL_LIFT of
   it up, fading over FIREBALL_FALLOFF). A body a Barbarian threw lands once the floor is HEAVE_LAND_GAP under it (or
   HEAVE_FLIGHT_MAX_S on): a blast (HEAVE_LAND_RADIUS, HEAVE_LAND_DAMAGE, HEAVE_LAND_KNOCK), a thrown elite taking the
   blow itself and a stagger; it stands again, a downed ally still down. An elite takes a blow as a minion does,
   except that a Warrior's shield takes all but ELITE_GUARD_TAKE of one from within ELITE_GUARD_COS of its facing
   (staggered or broken, none), and a knock moves its body by ELITE_KNOCK_TAKE of it (knocks and pushes together at
   most ELITE_KNOCK_MAX; none on a held elite),
   staggering it ELITE_STAGGER_S from ELITE_STAGGER_KNOCK. A charge's, a fireball's and a landing's blast break the
   guard first, for GUARD_BREAK_S. A thrown prop faster than PROP_HIT_SPEED hurts each minion it meets once
   (PROP_HIT_DAMAGE, at most PROP_HITS_MAX, keeping PROP_HIT_KEEP of its velocity) for the whole of its throw
   (THROWN_S).
10. **Props.** A prop landing faster than IMPACT_SPEED is an impact. A thrown prop that hits an elite at PROP_HIT_SPEED
    breaks its guard and hurts it, once per throw. A thrown prop passes through its thrower until it is
    THROW_CLEAR_DIST away or its throw ends.
11. **Health.** A chasing minion within MINION_REACH winds up a swing (MINION_WINDUP_S), which lands (MINION_DAMAGE)
    if its hero is still in reach, in front (MINION_STRIKE_COS) and in sight; an elite's attack lands at its windup
    as its kind says. Every blow on a hero, a bone bolt's too, meets its block and its roll; the dead fall for
    DEATH_S. A hero at 0 HP goes down and stays down until revived: it falls as a Box3D ragdoll (RAGDOLL_SCALE tall,
    RAGDOLL_MASS, at its velocity, at most RAGDOLL_CARRY_MAX, plus RAGDOLL_KICK away from the blow or RAGDOLL_TIP
    backwards from a blow from no side) that meets everything but heroes and elites, its capsule dormant and out of
    the world meanwhile (a Barbarian's heave stands the capsule up from it and holds that); a ragdoll fallen
    RAGDOLL_KILL_DEPTH below the floor goes, its hero lying at its spawn. Every hero down for WIPE_S restarts the
    floor.
12. **Loot.** A felled skeleton drops a coin on a roll of 1 in LOOT_ONE_IN, worth LOOT_VALUE_MIN to LOOT_VALUE_MAX
    gold; a felled elite drops ELITE_COINS coins worth its kind's ELITE_GOLD between them, on a LOOT_SPREAD ring (none
    under a held crowd). A hero up within LOOT_RADIUS of a coin that has lain LOOT_ARM_S picks it up into the party's
    one purse (two at once: the lower slot); a coin nobody takes goes after LOOT_LIFE_S. The save carries the purse as
    it stood at the last surge; a wipe takes the coins lying on the floor and keeps the purse.

**Mechanisms**, a floor's Box3D pieces (plates.odin, gates.odin, barricades.odin, traps.odin): before the step each gate's
motor is set from its plates and each roller driven along its path; after it, plates, barricades and traps are read.
A plate is pressed once its slab sinks past PLATE_ON under anything weighing more than PLATE_LOAD, and released above
PLATE_OFF. A gate lifts GATE_RISE while `need` of its plates are pressed (a latched one stays up), and closes pressing at
most GATE_CLOSE_FORCE; below GATE_PASS it keeps minions back. A barricade breaks to a blow (a thrown prop, a charge, a
hurled body) touching it as its weld strains past BARRICADE_BREAK_N: the blow decides, and the threshold is its floor,
since a hero walking into the fence strains it harder than a thrown crate. Spikes are up SPIKES_UP_S of every
SPIKES_PERIOD_S on the game clock from their phase, or while their plate is pressed, striking SPIKES_DAMAGE as they rise
and every SPIKES_HIT_TICKS; the roller, on the clock too, strikes ROLLER_DAMAGE what touches it every ROLLER_HIT_TICKS.

## The crowd

The skeleton minions are one MultiMesh (the play scene's `Minions`), however many are up: hundreds cost one draw call
a pass and no node each. The minion scene is baked offline by unified's crowd bake, as `MinionBake.recipe()` says
(`game/tools/minion_bake.gd`, bake-time only): its meshes and blade merged into one lighter mesh that keeps its skin,
and every frame of each of its clips as bone matrices in a texture. Each tick the extension writes an instance per minion
(`minion_instance`, `frame.odin`): its feet and facing, the clip it plays (`Minion_Clip`, `MinionCrowd.Clip`'s
numbers), when that clip started and when it was last struck, as game-time stamps the host turns into seconds at the
shown time (the minion kind's `ages`). The crowd's shader skins each vertex from the texture at that clip and time, and
draws the look: the eyes, a hit's flash, the dying sinking out of sight. Where in a clip an action starts, so that the
sim's moments land on the art's (a riser standing as it starts to chase, a swing's blow at the windup's end), is the
crowd view's (`minion_crowd_view.gd`). A minion's pose is a function of its state and the shown time, so a rollback, a
pause or a replay seek shows the pose the state says; a loop's stamp is a far-past phase of the minion's own, so the
crowd never walks in lockstep. The art checks hold the bake fresh and posing as the minion scene does, and the timing
to the sim's (`docs/ART.md`, Crowds).

## How it's built

- `simulation/crypt_crew/`: the deterministic simulation, the game's rules (Odin), one system per file.
- `simulation/extension/`: the GDExtension that runs the simulation inside Godot and turns its state into views. Its
  declarations are the view contract, what the sim shows Godot and what Godot sends back (`./uni doc`): views posed
  from the state and the session's shown game time, the events the effects and the HUD play, the sim's numbers the
  views pose by, the HUD's data and the mouse's aim.
- `simulation/headless/`: the same simulation without Godot, for tests, sync-tests, replays and benchmarks.
- `simulation/tests/`: every test of the sim.
- `game/`: the Godot side (the project is the repo root, `project.godot`): the app (`game/app/`: the `Game`,
  `Settings`, `Sfx`, `Prompts` and `LibraryCheck` autoloads, and `Bindings`), the title, hero select and Play
  together (`game/menu/`), the interface's theme, screens, settings, overlays and widgets (`game/ui/`), and the play
  scene with its views, effects, HUD and pause menu (`game/play/`, `game/views/`). GDScript shows the simulation and
  never changes it; input and commands are the only way in.
- `assets/`: the art packs the game uses (`CREDITS.md`); how they become the game's look is `docs/ART.md`.
- `tools/`: this game's `uni` CLI. `unified/`: unified, as a git submodule.

## How it's tested

Every layer unified offers a game: rule tests on sync-tested headless runs, so each also rolls back over what it checks;
unified's standard scenarios played by the scripted players (`script.odin`), which exercise every control and dev
command; a bot playthrough of the four classes; a replay regression recorded from a real two-player LAN session playing
a fixed script (`game/tools/coop_lan_pair.gd`; `./uni coop --rerecord lan_pair` records it again); the pinned reference
runs (the scripted party on Floor 1, and a crowd of MINION_CAP fighting on the arena: `crowd_test.odin`, which also
plays the standard scenarios at that size), the cross-platform check in CI; the godot suite, which holds the art to
`docs/ART.md` and the app layer to its contract (`game/tools/art_checks.gd`, `app_checks.gd`) and walks the app with
real input events (`game/tools/ui_walk.gd`); and `./uni coop`, a host and a joiner in two processes, from session flags
or, with `--menus`, each side through the game's own menus (`UnifiedCoop._start_host`, `_start_join`:
`game/tools/coop.gd`).
Commands: `./uni help`.

## Benchmarks

The [latest push run on `main`](https://github.com/FylmTM/godot-unified-demo/actions/workflows/ci.yml?query=branch%3Amain+event%3Apush)
has each platform's numbers in its summary. Locally: `./uni bench`.

## License

The code is licensed under either of [Apache License 2.0](LICENSE-APACHE) or [MIT license](LICENSE-MIT), at your
option. Art, sound and music keep their own licences (all CC0), listed with their sources in `CREDITS.md`.

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, as
defined in the Apache-2.0 license, shall be dual licensed as above, without any additional terms or conditions.
