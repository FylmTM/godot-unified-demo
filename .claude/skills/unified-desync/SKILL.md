---
name: unified-desync
description: Finding and shrinking a determinism bug - a sync-test failure, a desync report in a session, a checksum mismatch, a reference run failing on one platform only, or a replay diverging when it shouldn't. Find the first diverging tick and field with the headless binary, traces and replay regressions, shrink it, keep it as a test. Use whenever a run, test, session or CI job reports a desync, mismatch or divergence the change was not meant to cause.
---

# Finding a desync

The same inputs computed different bytes: find the first tick, then the first field, then why. The usual causes by
symptom: `unified/docs/gameplay.md` (Gotchas). The headless modes: `./uni headless -- help`.

## Read the failure

- A **sync-test** failure (one machine: a rollback re-simulated a tick differently) names the tick and the first
  State field that differs, forward vs re-simulated ("tick 1 re-simulated differently at 8: heroes[2].warp 0 vs 1";
  `headless.Synctest_Result.first_diff`): `tick` reads state the rollback doesn't restore. "The State agrees" means
  the Extra (the physics world) or the tick's events differ.
- A **session desync** names the tick, and with typed reports the field (`unified/src/netcode/README.md`, Checksums
  and desyncs). Run the sync-test first: most reproduce on one machine.
- A **reference run failing on one platform only**: a float trap (`unified/src/dmath/README.md`).
- A **replay regression** names the first tick and fields, with both values.

## The first tick

- One machine: `./uni headless -- synctest --ticks 600 --window 8` (`first_mismatch`).
- Two builds or machines: `./uni headless -- sim --ticks 600 --trace a.txt` on each (same `--seed`, `--players`),
  then `git diff --no-index a.txt b.txt`. A physics-only difference shows first on a `sim.DEEP_CHECKSUM_EVERY` tick.
- A recording (a dev UI build's session recording or F3 note): `./uni headless -- replay --log <folder>/inputs.unil`
  (`--snapshot <folder>/snapshot.unis` when it has one) gives `diverged_tick`, the first checkpoint that differs.

## The first field

A replay regression's report names the tick and the fields, between any two builds:

1. `./uni headless -- sim --ticks 600 --log inputs.unil` (or take a recording's folder).
2. Put it in `simulation/tests/replays/<name>/`.
3. On the good build `./uni test --bless`; on the bad one `./uni test`.

## Shrink

Fewer ticks (just past the first bad one), `--window 1`, `--players 1`, another `--seed`; skip systems in `tick`
locally until it goes. Then write it as a rule test on `headless.Run` (sync-tested on every step).

## After the fix

Keep the reproduction as a test. Nothing is re-pinned: if the reference run moves, the fix changed the results too
(the `unified-sim-change` skill).
