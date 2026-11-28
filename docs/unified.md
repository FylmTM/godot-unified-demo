# What Crypt Crew shows of unified

Each of unified's features as this game uses it, and where to read it. Sim files are in `simulation/crypt_crew/`; the
GDScript is under `game/`. unified's side of each: its README (`unified/README.md`) and `./uni doc <package>`.

## The simulation

| Feature | In Crypt Crew | Files |
|---|---|---|
| One state block | The whole game is one plain block that unified copies, restores and checksums | `state.odin` |
| Prediction in the view | A local hero turned by its newest input; the ring where a local Mage's fireball will land, from the rules' own `fireball_target` on that input | `simulation/extension/frame.odin`, `fireballs.odin` |
| Characters | Heroes and elites are `physics.Character` capsules; a sleeping elite is dormant until it wakes (`character_set_dormant`) | `heroes.odin`, `elites.odin` |
| Props and holds | Props are dynamic bodies; a carried prop hangs on a motor joint, and a thrown one ignores its thrower's contacts | `props.odin`, `hands.odin` |
| Blasts | A fireball's blast is an impulse on the props', elites', ragdolls' and barricades' Box3D bodies, walls shielding them; each ragdoll bone takes its share of the body's mass | `fireballs.odin` |
| The heave | An elite the Barbarian heaves goes limp on the hold (`character_set_limp`), then flies through every hero, its filter's mask changed until it lands (`shape_set_filter`); a downed ally's ragdoll is held by its chest bone and thrown whole (`ragdoll_set_velocity`) | `barbarian.odin` |
| Ragdolls | A downed hero falls as a `physics.Ragdoll` in the state block, its capsule dormant and out of the world until it gets up | `ragdolls.odin` |
| Mechanisms | Plates and gates are prismatic joints whose motors bear a load or lift a grille; a barricade is a weld that breaks past a force threshold, read from the step's joint events; spikes are sensors, the roller a kinematic body on a path on the game clock | `plates.odin`, `gates.odin`, `barricades.odin`, `traps.odin` |
| Set pieces | The hoard hangs on two players' motor joints, whose force cap lets one hauler drag it and two carry it clear; the lift is a kinematic deck on a path (`physics.Path`, `drive_kinematic`) that carries whoever stands on it, a sensor seeing the hoard aboard, and its descent changes the level as a sim decision. The workshop level holds one of each piece for their tests | `hoard.odin`, `lift.odin`, `simulation/tests/workshop_test.odin` |
| A choice confirmed for all | The boons offered at the lift are a keyed roll the tick and the HUD both make; the boon panel locks a pick only once it is CONFIRMED (`uni coop --lan -- --lag 150 --verified-players` shows it holding through a pick predicted frames ahead) | `boons.odin`, `game/play/boon_panel.gd` |
| Shots where the shooter saw them | The Rogue's crossbow looks back by its input's `sim.Seen` | `rogue.odin` |
| Navigation | Minions walk the floor's navigation mesh along memoized distance fields, kept apart over a `sim.Grid` | `minions.odin`, `world.odin` |
| Keyed rolls | Surges and packs roll on the state they place, a felled skeleton's drop on the session's count of drop rolls, so when a pause or a command lands moves no outcome | `director.odin`, `loot.odin` |
| Late join and rejoin | A joiner appears beside the party; a leaver's hero is kept for their return | `presence.odin` |
| The co-op pause | Pause for everyone stands the game clock for every peer, and the State keeps who paused, so a late joiner's banner names them too | `pause.odin`, `game/play/pause_menu.gd` |
| Setup and saves | A new game or a save is the session's Setup; the sim gives a save at each of the run's save points, unified hands it over from verified ticks only | `saves.odin`, `game/app/saves.gd` |
| Dev commands | A class swap, spawning, hurting and killing, dropping coins, as dev UI forms and `uni drive command` | `dev.odin` |
| Benchmarks | Four heroes against a held surge among Floor 1's props, and a crowd of MINION_CAP on the arena asleep, chasing, fighting, and downing the party into ragdolls, each row's population chosen by its Setup | `game.odin` (`benches`), `director.odin` (`Crowd`, `place_crowd`, `bench_prepare`) |

## The view

The extension (`simulation/extension/`) runs the simulation inside Godot and turns its state into views. Its
declarations are the view contract, what the sim shows Godot and what Godot sends back (`./uni doc`): views posed from
the state and the session's shown game time, the events the effects and the HUD play, the sim's numbers the views pose
by, the HUD's data and the mouse's aim. GDScript shows the simulation and never changes it; input and commands are the
only way in.

| Feature | In Crypt Crew | Files |
|---|---|---|
| Views | Scene views, props pooled; the Mage's bolts, the minions and the coins as MultiMeshes (`MultiView`), a minion and a coin shown once their spawn is verified (`Appear.Verified`); clips posed on the session's shown game time, so a correction or a seek lands on the right frame | `game/views/`, `game/views/hero.gd`, `simulation/extension/frame.odin` |
| The crowd | Hundreds of skeletons in one MultiMesh, baked by unified's crowd bake (`UnifiedCrowdBake`, `UnifiedCrowdCheck`, `crowd_skin.gdshaderinc`); each instance's clip and its game-time stamps, which the host ages into seconds at the shown time (`View_Policy.ages`), so a rollback, a pause or a replay seek shows the pose the state says; a loop's stamp is a far-past phase of the minion's own, so the crowd never walks in lockstep | `minion_instance` in `simulation/extension/frame.odin`, `game/crowd/`, [`ART.md`](ART.md#crowds) |
| Events | Effects play as soon as they are predicted (EMITTED); a join or a leave, a revive's toast and chime and the wipe's banner wait for CONFIRMED | `game/play/play.gd`, `effects.gd`, `game/app/game.gd` |
| Rewards shown when confirmed | A coin picked up vanishes and glints as predicted, but the purse counts it, chimes and floats its "+N" only once the pickup is CONFIRMED, so a pickup a rollback takes back (CANCELLED) never moves it; `uni coop --lan -- --lag 150` shows the purse holding through dozens of mispredicted pickups | `game/play/purse.gd`, `game/views/coins.gd`, `game/tools/coop.gd`, `purse_watch.gd` |

## The app

| Feature | In Crypt Crew | Files |
|---|---|---|
| Online and LAN from the menus | Hosting and joining by a lobby code or an address; the code's cells and alphabet, and a paste read as the library reads a code (`UnifiedSession.join_code_alphabet`, `clean_join_code`); whether online play can start, asked before trying (`online_problem`: the greyed rows); EOS lobbies in the extension and the headless binary | `game/menu/play_together.gd`, `join_code.gd`, `join_address.gd`, `game/ui/widgets/code_field.gd`, `simulation/extension/`, `simulation/headless/` |
| Open to friends | A game played alone opened online or on the LAN and closed again while it plays (`open_online`, `open_direct`, `close_online`); hosting online is the same opening, made as the crypt comes up. The HUD's session panel shows the code, the count and a slow link (`link_slow`, `round_trip_ms`) | `game/play/friends_screen.gd`, `game/play/session_panel.gd` |
| Both pauses | Alone, the pause menu stops the session's clock (`UnifiedSession.paused`), and the game pauses when its window loses the focus; with others, Pause for everyone is the co-op pause. A game opened while paused alone is paused for everyone at once | `game/play/pause_menu.gd`, `game/app/game.gd` |
| Continue | Continue starts a session on the save, kept as JSON in one slot; a joiner whose host left continues its last one alone | `game/app/saves.gd`, `game/app/game.gd` |
| Menus over a running game | While a menu shows, the session reads no game input (`game_input`), and a button held through it counts only once released | `game/app/game.gd` |
| The session outlives the scenes | The `Game` autoload owns it from boot to quit and switches between the title and the crypt on its status, whoever started it: the menus, the command line's session flags (`uni run`, `uni coop`, `uni drive`) or a tool. A start that fails, or a game that ends, comes back to the title with the reason; a join or a leave is a toast; a reconnect is a plate over the held game | `game/app/game.gd` |
| Couch co-op | Hero select's seats become local players, each with its device and Profile, and pads join and drop out mid-game (`add_local_player`, `set_local_device`, `remove_local_player`); every local hero framed by one camera | `game/play/couch.gd`, `game/menu/hero_select.gd`, `camera_rig.gd` |
| Prompts and rebinding | Each local player's prompts in the glyphs of the device the session gives them (`get_local_device`); attack, grab and the keyboard's moves rebound in the InputMap that unified's input helpers read | `game/app/prompts.gd`, `game/app/bindings.gd` |

How each of unified's testing layers is used here: [`testing.md`](testing.md).

## Waiting on unified

What the game needs from unified, each an issue there; the game works around it meanwhile, with a comment at the
workaround that links the issue. When one lands and the submodule is bumped, make the change in the last column and
drop the row.

| Issue | Meanwhile | When it lands |
|---|---|---|
| [#590 world_explode with occluders](https://github.com/FylmTM/godot-unified/issues/590) | Each blast casts a wall ray per prop, elite, ragdoll and barricade and applies its own impulse (`fireballs.odin`: `blast_bodies`, `blast_impulse`) | One `world_explode` with the walls as occluders; re-tune and re-bless |
| [#591 nav fields round shut doors](https://github.com/FylmTM/godot-unified/issues/591) | Minions are pushed out of shut gates and standing barricades (`minions.odin`: `obstacles_of`); the bot detours by the gate's front (`simulation/tests/bot.odin`: `go`, `gate_front`) | Gates and barricades become doors, the fields take the shut ones; drop the bot's detour; re-bless |
| [#592 packed array view fields](https://github.com/FylmTM/godot-unified/issues/592) | A ragdoll's bones reach the script as Arrays (`simulation/extension/frame.odin`: `View_Ragdoll`) | Packed fields, read as packed arrays in `game/views/ragdoll.gd` |
| [#593 a Linux x64 zip](https://github.com/FylmTM/godot-unified/issues/593) | `uni release` builds macOS arm64 and Windows x64 (`export_presets.cfg`, the CI release job) | A Linux preset, `linux-x64` in the release matrix, the zip in `playing.md` |
| [#594 uni drive pad, key and type](https://github.com/FylmTM/godot-unified/issues/594) | Couch checks are tool scripts with `pad_button(..., device)` (`game/tools/coop.gd`, `party_walk.gd`) | A couch play-check by hand in `testing.md` |
| [#595 a boot step in the godot suite](https://github.com/FylmTM/godot-unified/issues/595) | Real boot is checked by hand under `uni drive` (`review.md`) | Drop that note; list the step in `testing.md` |
| [#596 friends and invites](https://github.com/FylmTM/godot-unified/issues/596) | The join code is the invite (`game/play/friends_screen.gd`, `game/menu/join_code.gd`) | Friends with Invite, Join a friend, an invite toast |
| [#597 LAN discovery](https://github.com/FylmTM/godot-unified/issues/597) | A LAN join types the host's address (`game/menu/join_address.gd`) | List the games heard, the address field as a fallback |
| [#598 a typed end reason](https://github.com/FylmTM/godot-unified/issues/598) | Endings fold the library's detail into the game's sentence (`game/app/game.gd`: `_on_status_changed`, `_failed_start`) | Match on `end_reason`, the game's sentence for each |
| [#599 verified session data](https://github.com/FylmTM/godot-unified/issues/599) | The purse seeds from the predicted HUD data; a late joiner's boon panels open from it (`game/play/purse.gd`, `boon_panels.gd`) | Show the verified gold, open from the verified choice; drop the seeding |
| [#600 a shared app layer](https://github.com/FylmTM/godot-unified/issues/600) | The game's own flow, settings, bindings, prompts and couch seats (`game/app/`, `game/play/couch.gd`) | Move onto the shared parts, keep the crypt's words and screens |
| [#601 levels from room scenes](https://github.com/FylmTM/godot-unified/issues/601) | Each floor laid whole from an ASCII map (`game/tools/lay_floor.gd`) | Shared rooms as room scenes the floors instance |
| [#602 the net suite for game repos](https://github.com/FylmTM/godot-unified/issues/602) | Real UDP only through `uni coop --lan` and the release job (`.github/workflows/ci.yml`) | `uni test --suite net` in CI and `testing.md` |
| [#603 a doc-comment lint](https://github.com/FylmTM/godot-unified/issues/603) | The doc-comment rule is kept by review | Run the check in the suite, add what it finds |
| [#604 UnifiedSession.tick after a start request](https://github.com/FylmTM/godot-unified/issues/604) | The session walk waits for `replay_last_tick` (`game/tools/session_walk.gd`: `_replay`) | Wait on the replay's tick; drop the comment |
