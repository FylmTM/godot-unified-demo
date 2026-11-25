# Crypt Crew

[![ci](https://github.com/FylmTM/godot-unified-demo/actions/workflows/ci.yml/badge.svg?branch=main&event=push)](https://github.com/FylmTM/godot-unified-demo/actions/workflows/ci.yml?query=branch%3Amain+event%3Apush)

The demo game of [unified](https://github.com/FylmTM/godot-unified): co-op games with deterministic rollback netcode,
the rules written in Odin, Godot as the host for rendering, audio, UI and the editor. Crypt Crew is a top-down co-op
dungeon crawler for 1–4 players, and the answer to "what does a real game built on unified look like?".

> [!NOTE]
> **The first playable.** Up to four heroes, on one couch or over the LAN (a host and its joiners, by address; online
> lobbies come with the app layer), fight down Floor 1 of the crypt: skeleton packs asleep in its rooms and surges
> rising from its graves, against the Knight's quick sword, the Barbarian's wide cleave, the Mage's bursting bolts and
> the Rogue's crossbow, and the barrels and crates any hero picks up and throws. A hero at 0 HP goes down and, for
> now, rises beside the party on its own; the whole party down restarts the floor. What the game becomes, and in what
> order, is [`docs/plan.md`](docs/plan.md).

## Play it

You need git, curl and a C toolchain for Odin's linker: clang on macOS and Linux, Visual Studio Build Tools on
Windows. The first `./uni` downloads the pinned Odin; each command fetches what else it needs (Godot, Box3D) the
first time. Nothing is installed by hand. On Windows, run `uni.cmd` instead of `./uni`.

```sh
git clone --recursive https://github.com/FylmTM/godot-unified-demo
cd godot-unified-demo
./uni run                            # play it in a window: the title, then New game
./uni run -- --host-port 7777        # host a game on the LAN, straight past the title...
./uni run -- --join 127.0.0.1:7777   # ...and join it from a second window
./uni tool lookdev --window --shots  # the art, posed in the look-dev scene
./uni help                           # every command
```

**Controls.** Move with WASD, the arrow keys or a pad's left stick; aim with the mouse or the right stick (a hero
that isn't aimed faces where it walks). Attack (the left mouse button, Space, or a pad's right trigger or X) attacks
while held, and throws what you carry. Grab (E, the right mouse button, or a pad's A) picks up the barrel or crate in
front, glowing faintly, and puts it down again. Esc, or Start on a pad that plays, opens the pause menu.
Attack and Grab can be rebound on both the keyboard and mouse and a pad, and the moves on the keyboard (Settings,
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
felled), in one slot; Continue on the title starts it again from there. Only the host, or a player alone, keeps it:
a player in someone else's game keeps the host's last save in memory (from the start, when the host continued a
crypt), and is offered "Continue on your own" if the host leaves: it takes that save as its own (asking first if it
replaces one) and continues it through hero select. Alone (couch included) the pause menu pauses the game; with others the game runs on under it, and
"Pause for everyone" pauses it for every player (anyone may resume it), the banner naming who paused. Alone, the game
also pauses when its window goes to the background (Settings, Gameplay).

## What it shows of unified

- **Rollback and prediction**: the whole game is one plain state block (`simulation/crypt_crew/state.odin`) that
  unified copies, restores and checksums; the views draw the prediction, a local hero turned by its newest input
  (`simulation/extension/frame.odin`).
- **Physics under rollback**: heroes are `physics.Character` capsules (`heroes.odin`) and props dynamic bodies
  (`props.odin`); a carried prop hangs on a motor joint, and a thrown one ignores its thrower's contacts
  (`hands.odin`).
- **Shots resolved where the shooter saw them**: the Rogue's crossbow looks back by its input's `sim.Seen`
  (`rogue.odin`).
- **Navigation**: minions walk the floor's navigation mesh along memoized distance fields, kept apart over a
  `sim.Grid` (`minions.odin`, `world.odin`).
- **Keyed rolls**: surges and packs roll on the state they place (`director.odin`), so when a pause or a command lands
  moves no outcome.
- **Late join and rejoin beside the party** (`presence.odin`), a player's hero kept for their return.
- **Both pauses**: alone, the pause menu stops the session's clock (`UnifiedSession.paused`); with others, its Pause
  for everyone is the co-op pause (`pause.odin`), the game clock standing for every peer, and the State keeps who
  paused, so a late joiner's banner names them too (`game/play/pause_menu.gd`).
- **Setup and save**: a new game or a save is the session's Setup; the sim gives a save at each surge (`saves.odin`),
  unified hands it over from verified ticks only, and the app keeps it as JSON in one slot (`game/app/saves.gd`);
  Continue starts a session on it, and a joiner whose host left continues its last one alone (`game/app/game.gd`).
- **The session outlives the scenes**: the `Game` autoload owns it from boot to quit and switches between the title
  and the crypt on its status, whoever started it: the menus, the command line's session flags (`uni run`, `uni coop`,
  `uni drive`) or a tool. A start that fails, or a game that ends without the player leaving, comes back to the title
  with the reason; a join or a leave is a toast; a reconnect is a plate over the held game (`game/app/game.gd`).
- **Views**: scene views (`game/views/`), props and minions pooled, minions shown once their spawn is verified
  (`Appear.Verified`, `frame.odin`), the Mage's bolts one MultiMesh (`MultiView`); clips posed on the session's shown
  game time, so a correction or a seek lands on the right frame (`game/views/hero.gd`, `minion.gd`).
- **Events**: effects play as soon as they are predicted (EMITTED: `game/play/play.gd`, `effects.gd`); a join or a
  leave is told once it is CONFIRMED (`game/app/game.gd`).
- **Couch co-op**: each local player's device and pads joining (`game/play/couch.gd`), every local hero framed by one
  camera (`camera_rig.gd`); each local player's prompts in the glyphs of the device the session gives them
  (`game/app/prompts.gd`).
- **Dev commands** (`dev.odin`): a class swap, spawning, hurting and killing, as dev UI forms and
  `uni drive command`.
- **A benchmark row**: four heroes against a held surge among the props (`game.odin`, `bench_prepare` in
  `director.odin`).

## The rules

One tick, in order (`simulation/crypt_crew/game.odin`); every number is a named constant in `tuning.odin`.

1. **Presence.** Leavers drop what they carry and their bodies go. An arriving hero takes the class its Profile asks
   for, else the one it played, else a free one, and appears beside the party: the first spot around the lowest-slot
   hero up, ARRIVAL_RING out (then twice that), on the floor, reachable in a straight line, ARRIVAL_CLEAR of minions
   and ARRIVAL_ROOM clear of heroes and props; with none, at its slot's hero spawn.
2. **Pause.** `Set_Paused` stops or starts the game clock; while paused, nothing after this runs.
3. **Dev commands.**
4. **Heroes.** A downed hero rises beside the party after RESPAWN_S, safe for SPAWN_GRACE_S. Each hero turns to its
   aim (else its move, past TURN_STICK). Interact grabs the nearest prop in reach (GRAB_RANGE, GRAB_CONE_COS) or drops
   the one held; Attack while holding throws it (THROW_WINDUP_S, THROW_SPEED). Otherwise Attack held starts the
   class's attack (`CLASS_SPECS`: windup, duration, cooldown; held, it repeats every cooldown). The hold's joint
   follows the facing (`HOLD_*`), and the hero walks toward the stick's velocity at its class's speed, slowed by a
   carried prop or by ATTACK_SPEED.
5. **Director.** A sleeping pack wakes when a hero one of its minions can see comes within AGGRO_RADIUS (each looks
   every SIGHT_S) or one of them is hit. A surge rises SURGE_FIRST_S into a floor and every SURGE_EVERY_S after:
   SURGE_BASE minions plus SURGE_PER_HERO per hero, at a grave out of sight beyond SURGE_NEAR and within SURGE_FAR of
   the party, up to MINION_CAP alive.
6. **Minions.** Each picks the nearest hero up by path (every RETARGET_S), steers along that hero's field, keeps
   SEPARATION from its neighbours and carries its knockback (KNOCK_DECAY).
7. **Physics.** Box3D steps; the heroes' feet and velocities are read back into the state.
8. **Strikes.** A blow lands at its windup on the minions in its reach and arc, or touching the hero (`CLASS_SPECS`,
   STRIKE_TOUCH), and shoves the props there. Bolts fly at BOLT_SPEED for BOLT_LIFE_S and burst at the first thing
   they meet (BURST_RADIUS, BURST_DAMAGE). The crossbow hits the first thing within CROSSBOW_RANGE on the picture its
   shooter saw (at most MAX_REWIND_S back). Walls shield what is behind them from blows, bursts and shots; bolts and
   shots fly at FLIGHT_HEIGHT, over low cover and resting light props, and meet walls, heavy crates and props held or
   in flight. A thrown prop faster than PROP_HIT_SPEED hurts each minion it meets once (PROP_HIT_DAMAGE, at most
   PROP_HITS_MAX, keeping PROP_HIT_KEEP of its velocity) for the whole of its throw (THROWN_S).
9. **Props.** A prop landing faster than IMPACT_SPEED is an impact. A thrown prop passes through its thrower until it
   is THROW_CLEAR_DIST away or its throw ends.
10. **Health.** A chasing minion within MINION_REACH winds up a swing (MINION_WINDUP_S), which lands (MINION_DAMAGE)
    if its hero is still in reach, in front (MINION_STRIKE_COS) and in sight; the dead fall for DEATH_S. A hero at
    0 HP goes down; every hero down at once restarts the floor.

## How it's built

- `simulation/crypt_crew/`: the deterministic simulation, the game's rules (Odin), one system per file.
- `simulation/extension/`: the GDExtension that runs the simulation inside Godot and turns its state into views. Its
  declarations are the view contract, what the sim shows Godot and what Godot sends back (`./uni doc`): views posed
  from the state and the session's shown game time, the events the effects and the HUD play, the sim's numbers the
  views pose by, the HUD's data and the mouse's aim.
- `simulation/headless/`: the same simulation without Godot, for tests, sync-tests, replays and benchmarks.
- `simulation/tests/`: every test of the sim.
- `game/`: the Godot side (the project is the repo root, `project.godot`): the app (`game/app/`: the `Game`,
  `Settings`, `Sfx`, `Prompts` and `LibraryCheck` autoloads, and `Bindings`), the title and hero select (`game/menu/`), the
  interface's theme, screens, settings, overlays and widgets (`game/ui/`), and the play scene with its views, effects
  and HUD. GDScript shows the simulation and never
  changes it; input and commands are the only way in.
- `assets/`: the art packs the game uses (`CREDITS.md`); how they become the game's look is `docs/ART.md`.
- `tools/`: this game's `uni` CLI. `unified/`: unified, as a git submodule.

## How it's tested

Every layer unified offers a game: rule tests on sync-tested headless runs, so each also rolls back over what it
checks; unified's standard scenarios played by the scripted players (`script.odin`), which exercise every control and
dev command; a bot playthrough of the four classes; a replay regression recorded from a real two-player LAN session;
the pinned reference run, the cross-platform check in CI; the godot suite, which holds the art to `docs/ART.md` and the
app layer to its contract (`game/tools/art_checks.gd`, `app_checks.gd`) and walks the app with real input events
(`game/tools/ui_walk.gd`); and `./uni coop`, a host and a joiner in two processes (`game/tools/coop.gd`).
Commands: `./uni help`.

## Benchmarks

The [latest push run on `main`](https://github.com/FylmTM/godot-unified-demo/actions/workflows/ci.yml?query=branch%3Amain+event%3Apush)
has each platform's numbers in its summary. Locally: `./uni bench`.

## License

The code is licensed under either of [Apache License 2.0](LICENSE-APACHE) or [MIT license](LICENSE-MIT), at your
option. Art, sound and music keep their own licences (all CC0), listed with their sources in `CREDITS.md`.

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, as
defined in the Apache-2.0 license, shall be dual licensed as above, without any additional terms or conditions.
