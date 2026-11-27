# How Crypt Crew is tested

Every layer of testing unified offers a game, as this game uses it: what each proves, the command, the files, and what
the tool prints (real output, trimmed). Commands and their options: `./uni help`, `./uni <command> -h`.

| Layer | What it proves | Command | Files | CI |
|---|---|---|---|---|
| 1 Rules under rollback | each rule, rolled back over on every step | `uni test` | `simulation/tests/*_test.odin`, `support_test.odin` | push |
| 2 Scenarios | sessions agree: rollback every tick, churn, bad network, late join | `uni test` (`--long`: all, full length) | `suite_test.odin`, `crowd_test.odin` | push, nightly `--long` |
| 3 Reference runs | the same results on every platform | `uni test` (`--bless`) | `reference_test.odin`, `crowd_test.odin` | push, 3 platforms |
| 4 Replay regressions | a recorded session computes what was blessed | `uni test`, `uni coop --rerecord lan_pair` | `replays/lan_pair`, `replays/note_swift_boots`, `game/tools/coop_lan_pair.gd` | push |
| 5 Planted bugs | the nets catch a desync and a rule change, and name them | `uni test` | `planted_test.odin` | push |
| 6 Random inputs | noise from four players breaks nothing | `uni test` (`--long`: 16 seeds) | `soak_test.odin` | push, nightly |
| 7 Bots | a whole run, played | `uni test` | `playthrough_test.odin`, `bot.odin` | push |
| 8 Views | the views are functions of the state | `uni test` | `view_test.odin` | push |
| 9 The godot suite | import, editor, session checksums, bake, validate, walk, drive, render | `uni test --suite godot` | `game/tools/validate.gd`, `ui_walk.gd`, the checks and walks | push |
| 10 Two processes | a host and a joiner, real UDP | `uni coop --lan` (`--crash`, `-- --lag 150`) | `game/tools/coop.gd`, `purse_watch.gd` | push, nightly `--crash` |
| 11 Play-checking | an agent plays the real game | `uni drive` | (none: a transcript) | |
| 12 F3 notes | a noted moment kept as a regression | `uni drive note`, `uni feedback` | `replays/note_swift_boots`, `suite_test.odin` | push |
| 13 Benchmarks, budget | speed, and the bytes a session moves | `uni bench`, `uni test` | `game.odin` (benches), `suite_test.odin`, `tuning.odin` | push (reported) |
| 14 Clips | a recording as a GIF or a video | `uni render` | any recording | |
| 15 CI | all of it, per push and nightly | | `.github/workflows/ci.yml` | |

Also in `uni test`: unified's determinism lint and the extension's install check (`suite_test.odin`), the levels
(`levels_test.odin`), and the Box3D debug library under the same tests (`--suite box3d-debug`, CI's linux-arm64).
Render cost and the look, by hand: `game/tools/crowd_frames.gd`, `lookdev.gd` (`uni tool --window`).

## CI

| Job | Suites | Push to main | Nightly |
|---|---|---|---|
| linux-x64 | fmt --check, vet, odin, bench | yes | odin `--long`, no bench |
| linux-arm64 | odin, box3d-debug, bench | yes | |
| windows-x64 | odin (through `uni.cmd`), bench | yes | |
| macos-arm64 | odin, bench | yes | |
| release / windows-x64, macos-arm64 | `uni release`, then each zip played headless | yes | |
| godot | godot suite, `tool lookdev`, `coop --lan` | yes | the same, and `coop --lan --crash` |

The nightly tests unified's `main` when it differs from the pin (the canary, once per pair of commits), else the pin.
`gh workflow run ci.yml -f unified_ref=<ref>` runs the push set against another unified.

## 1 Rules under rollback

Each rule is a test on a sync-tested `headless.Run`: every step rolls back 8 ticks and re-simulates, so a rule test
also proves the rule survives rollback (`unified/src/headless/README.md`, Runs).

- `./uni test crypt_crew` (the inner loop); one test: `--only each_boon_does_its_part`.
- A file per system: `abilities_test.odin`, `arena_test.odin`, `attacks_test.odin`, `barricades_test.odin`,
  `boons_test.odin`, `boss_test.odin`, `braziers_test.odin`, `director_test.odin`, `elites_test.odin`,
  `gates_test.odin`, `hands_test.odin`, `haul_test.odin`, `health_test.odin`, `heave_test.odin`, `heroes_test.odin`,
  `levels_test.odin`, `loot_test.odin`, `minions_test.odin`, `plates_test.odin`, `ragdolls_test.odin`,
  `revive_test.odin`, `run_test.odin`, `saves_test.odin`, `traps_test.odin`, `workshop_test.odin`; what they share:
  `support_test.odin` (a hero, a prop or a minion placed by the floor's markers).

Swift Boots broken on purpose (`boots_scale` returning 1):

```
$ ./uni test crypt_crew --only each_boon_does_its_part
[ERROR] [boons_test.odin:238:each_boon_does_its_part()] expected g.boots_scale(&hero) to be 1.18, got 1
test: odin FAILED (1.7s)
```

## 2 Scenarios

unified's standard scenarios on the game's scripted players (`script.odin`): a rollback every tick, players coming and
going, four clients on a bad network, inputs changing every tick, a late joiner; at crowd size too.

- `./uni test crypt_crew` (short runs); `./uni test crypt_crew --long`: every scenario at full length, sixteen soak
  seeds (the nightly).
- `suite_test.odin`, `crowd_test.odin`.

```
$ ./uni test crypt_crew --long
Finished 363 tests in 19.1512742s. All tests were successful.
test: odin passed (21.2s)
```

## 3 Reference runs and --bless

A pinned run's checkpoints, trace, snapshot and log hashes: every platform computes the same bytes (CI's three).

- `./uni test` checks them; after a meant rule change, bump `Game.version`, then `./uni test --bless` (the
  `unified-sim-change` skill).
- `reference_test.odin` (Floor 1's scripted party), `crowd_test.odin` (MINION_CAP on the arena), `workshop_test.odin`.

A minion's blow raised from 10 to 11, then a bless without the version bump:

```
 - the_reference_run_reproduces  reference_reproduces (4 players, seed 7, 2400 ticks, snapshot at 1200): this
   platform computes another run (by tick 600) on the build it was pinned on (sim.compat_of did not move):
   checkpoints[0] 0x460ee5d3a7162a59 -> 0xd46df8056dda01ed, checkpoints[1] 0xf740080c019bf378 -> 0x952a29e6894404a5, ...
$ ./uni test crypt_crew --bless
uni: test --bless failed: nothing re-pinned
```

## 4 Replay regressions

A recorded session replayed tick by tick against what was blessed; a difference names the tick, the events and the
State's fields that moved.

- `./uni test` (`the_replays_reproduce`); record lan_pair again: `./uni coop --rerecord lan_pair` (its `coop.args`);
  replay any recording: `./uni headless -- replay --log <dir>/inputs.unil --snapshot <dir>/snapshot.unis`.
- `replays/lan_pair` (a two-process LAN session playing `game/tools/coop_lan_pair.gd`'s script) and
  `replays/note_swift_boots` (section 12); what each holds: `the_lan_recording_holds_its_play`,
  `the_swift_boots_note_holds` (`suite_test.odin`).

The same mutant:

```
 - the_replays_reproduce  replays_reproduce: replays/lan_pair: first differs at tick 1160; its events (blessed, then
   now): event 1 of 1, hero_hurt: damage 10 vs 11; hp 90 vs 89; at tick 1168 (blessed vs now): players.data[0].hp
   80 vs 78; on the build that blessed it (sim.compat_of did not move): a meant change bumps Game.version ...
```

## 5 Proving the nets: the planted desync and the desync hunt

Two bugs planted in copies of the game's descriptor, never in the sim: state kept outside the block (a desync), and a
rule change (no desync, but the recording moves). Each must be caught and named.

- `./uni test crypt_crew --only a_planted_desync_is_caught,a_planted_rule_change_fails_the_replay`; hunting a real
  desync: the `unified-desync` skill.
- `planted_test.odin`.

The walkthrough: the real game sync-tests clean; the planted copy fails at its planted tick, and the report names the
field, forward vs re-simulated (shown by turning the test's check around); the planted rule's replay names tick 3282
and `kills`.

```
$ ./uni headless -- synctest --ticks 600 --window 8
{"mode":"synctest","ticks":600,"window":8,"seed":1,"players":4,"mismatches":0,"first_mismatch":0,...}
$ ./uni test crypt_crew --only a_planted_desync_is_caught
 - a_planted_desync_is_caught  it names a hero's warp: players.data[0].warp 2 vs 3 (and 3 more fields)
```

## 6 Random inputs

Four players sending noise (every Input byte random, held a while; random pauses and boon picks) on a sync-tested run:
no mismatch, no NaN, and the caps, the heroes' health and their feet hold. A failing seed becomes a test of its own.

- `./uni test crypt_crew --only random_inputs_break_nothing` (2 seeds; `--long`: 16, a level each in turn).
- `soak_test.odin`.

```
$ ./uni test crypt_crew --only random_inputs_break_nothing
Finished 1 test in 745.2513ms. The test was successful.
```

## 7 Bots

Bots that read the state play Floor 1 for three minutes as the four classes, each floor's way out, and a whole run to
the King's fall, sync-tested throughout.

- `./uni test crypt_crew --only the_bot_plays_three_minutes,the_bots_play_a_whole_run`.
- `playthrough_test.odin`, `bot.odin`.

```
$ ./uni test crypt_crew --only the_bot_plays_three_minutes,the_bots_play_a_whole_run
Finished 2 tests in 7.5506029s. All tests were successful.
```

## 8 Views

The extension's views as pure functions of the state: a minion's crowd instance, a coin's, the fireball's ring, an
elite shown once verified, the clip table the crowd's shader reads.

- `./uni test crypt_crew --only a_minion_instance_is_its_state,a_coin_instance_is_its_state`.
- `view_test.odin`.

```
$ ./uni test crypt_crew --only a_minion_instance_is_its_state,a_coin_instance_is_its_state,the_fireball_ring_is_where_the_cast_lands
Finished 3 tests in 15.1065ms. All tests were successful.
```

## 9 The godot suite, step by step

The game under headless Godot, each step building on the one before (`./uni test -h` says what each proves).

- `./uni test --suite godot` (`--only validate` after a GDScript change; `--verbose` prints each step).
- validate: `game/tools/validate.gd`, running `art_checks.gd` (`docs/ART.md`'s rules), `app_checks.gd` (the app
  layer's contract), `fx_checks.gd` (the effects' budgets and cancels, the cutaway) and `audio_checks.gd` (voices,
  buses, ducking). walk: `ui_walk.gd` and its parts `party_walk.gd`, `session_walk.gd`, `together_walk.gd`, on
  `menu_tool.gd`; `online_check.gd` is its online twin, run by hand where EOS is set up.

```
$ ./uni test --suite godot --verbose
uni: crypt_crew editor: ok (2.8s)
uni: crypt_crew session: ok (1.9s)
uni: crypt_crew validate: ok (7.9s)
uni: crypt_crew drive: ok (5.0s)
uni: crypt_crew render: ok (7.2s)
uni: crypt_crew walk: ok (52.0s)
```

## 10 Two processes

A host and a joiner, two Godot processes on real UDP, play a scripted match with checks on each side: the friend's
arrival, combat, coins, the vault's gate and hoard, revives, a boon each, the King's ward, the co-op pause, and the
joiner continuing alone once the host leaves.

- `./uni coop --lan` (every push); `--crash` (the joiner's process killed, the same player back: nightly);
  `-- --lag 150` (the joiner a bad link behind: the purse and the boon panel hold through mispredictions); `--rejoin`,
  `--menus` (each side through the game's own menus).
- `game/tools/coop.gd`, `purse_watch.gd`.

```
$ ./uni coop --lan
coop crypt_crew: host ok, joiner ok                                     (122 s)
$ ./uni coop --lan --crash
  [host] ok 121010 ms  friend back 0.5 s after dropping out: 0:Adventurer, 1:Friend
coop crypt_crew --crash: host ok, first joiner crashed as planned, the same player again ok
$ ./uni coop --lan -- --lag 150
  [join] ok 164025 ms  the purse moved on confirmed pickups only, at 314 (12 changes; pickups 66 emitted, 11 confirmed, 55 cancelled)
```

## 11 Play-checking with uni drive

An agent plays the real game in a window (muted, top-left, never focused); paused, every tick is accounted for.

- `./uni drive start -- --autostart`, then `pause`, `press`, `step`, `command`, `state`, `data`, `events`, `shot`,
  `ui`; `stop` judges the game's log (the `unified-godot` skill).

The play behind section 12 (replies trimmed):

```
$ ./uni drive --name f3 start -- --autostart --profile class=knight    -> "status":"connected","scene":"Play"
$ ./uni drive --name f3 pause                                          -> "paused":true,"level":"Floor_1"
$ ./uni drive --name f3 command dev_board; ./uni drive --name f3 step 264
$ ./uni drive --name f3 data hud.heroes[0]          -> "offer":["Keen_Edge","Strong_Back","Swift_Boots"],"picked":false
$ ./uni drive --name f3 press move_right 8 (twice), press interact 8   # the boon panel's own keys
$ ./uni drive --name f3 events --all boon_picked    -> "boon":"Swift_Boots","rank":1,"auto":false
$ ./uni drive --name f3 press move_left 40; ./uni drive --name f3 state players.data[0].vel
{"ok":true,"tick":778,"value":[-5.2999997,0,0]}     # on Floor 2: the Knight's 5 m/s, times 1.06
```

## 12 F3 notes, uni feedback, regression

A moment a player notes (F3 in a dev build; `uni drive note` for an agent) carries the session's recording:
`uni feedback` reads it back, the replay reproduces it, and it is kept as a regression with a test of the noted fact
(the `unified-feedback` skill).

- `./uni drive note "<text>"` (`--bug`), `./uni feedback --instance <name>` (`show`, `done`), then
  `./uni test --bless` writes the kept replay's expectation.
- `replays/note_swift_boots` (`inputs.unil`, `snapshot.unis`, `expected.unie`, and the note's `note.txt`);
  `the_swift_boots_note_holds` (`suite_test.odin`).

```
$ ./uni drive --name f3 note "Took Swift Boots at the Floor 1 lift: on Floor 2 my Knight walks faster than ..."
{"ok":true,"tick":778,"screenshot":true,"recording":true,"show":"./uni feedback show 20261127-224533 --instance f3"}
$ ./uni headless -- replay --game crypt_crew --snapshot <note>/snapshot.unis --log <note>/inputs.unil
{"mode":"replay","ticks":778,"checkpoints":48,"agreed_tick":768,"diverged_tick":0,"ok":true}
$ cp <note>/{inputs.unil,snapshot.unis,note.txt} simulation/tests/replays/note_swift_boots/ && ./uni test --bless
  simulation/tests/replays/note_swift_boots: replays/note_swift_boots blessed
$ ./uni feedback done 20261127-224533 --instance f3
```

With Swift Boots broken on purpose, both nets catch it:

```
 - the_replays_reproduce       replays/note_swift_boots: first differs at tick 739; at tick 752 (blessed vs now):
                               players.data[0].vel[0] -5.2999997 vs -5; ...
 - the_swift_boots_note_holds  the Knight walks 1.06 times faster on Floor 2 (top speeds squared 25, 25)
```

## 13 Benchmarks and the budget

`uni bench` times a step, a rollback's re-simulation and a deep checksum at their p99 for each benchmark row, and the
sessions on the virtual clock; reported in CI's summaries, not gated. The byte budget is gated: four clients on the
bad network, the last joining late, each measure under a ceiling at measured + 15 %.

- `./uni bench`; `./uni test crypt_crew --only a_session_stays_in_its_budget`.
- The rows: `benches` in `simulation/crypt_crew/game.odin`; the ceilings: Bandwidth in `tuning.odin`; the budget's
  test: `suite_test.odin`.

```
$ ./uni bench
crypt_crew   step    76 us + restore   6 us + 14-tick re-sim  1064 us + deep checksum  29 us =  1.18 ms at p99 (target <= 6 ms: yes; ...
crypt_crew/crowd_fight step   167 us + restore   5 us + 14-tick re-sim  1840 us + deep checksum  18 us =  2.03 ms at p99 (target <= 6 ms: yes; ...
             session (4 clients, bad, the game's script) 439 ms: relay 34.8 kB/s, client 4.9 kB/s, 85 resends, 0 inputs replaced
             churn (4 clients, bad, 600 ticks, every input changing every tick) 419 ms: client step p99 575 us, worst 0.90 ms; 1028 rollbacks ...
```

Prediction, measured on lan_pair's real play: a client 7 ticks deep, guessing the other's input by repeating its last
one, would roll back on 495 of 4792 ticks (the game has no `predict_input` hook, so both columns are that guess):

```
$ ./uni headless -- predict-stats --log simulation/tests/replays/lan_pair/inputs.unil
{"mode":"predict-stats","ticks":4792,"depth":7,"hook":false,"rollbacks_repeat_last":495,"rollbacks_predict_input":495,"ok":true}
```

## 14 Clips (uni render)

Any recording (a replay regression, an F3 note, a session) played in the game's own play scene under Godot's movie
writer, frame-exact at any machine speed: a GIF, an AVI with sound, or PNG frames. The godot suite's render step
checks it on the first replay regression.

- `./uni render <recording> --out <file.gif|file.avi|dir/> [--from] [--to] [--player]` (the `unified-godot` skill,
  A clip for a README).

```
$ ./uni render simulation/tests/replays/note_swift_boots --out .out/clips/swift_boots.gif --from 682 --to 778
crypt_crew: 23 frames at 15 fps (ticks 682 to 778), 960x540 -> .out/clips/swift_boots.gif (2.2 MB) in 8.3s; GIF: 23 frames, 255 colours
```

## 15 CI and the canary

The tables at the top; the header of `.github/workflows/ci.yml` says what runs when. A red push run on `main` is fixed
before anything else lands; a red nightly against unified's `main` means a unified change broke the game (fix it
there, or file it). The long tier and `coop --lan --crash` run every night, against the pin when unified's main
hasn't moved.

- `gh workflow run ci.yml -f unified_ref=<branch or full SHA>`: the push set against another unified.
- `.github/workflows/ci.yml`.

```
$ gh run view <run>
✓ unified ref in 12s
✓ linux-x64 in 1m56s
✓ godot in 2m17s
✓ windows-x64 in 2m19s
✓ linux-arm64 in 5m51s
```
