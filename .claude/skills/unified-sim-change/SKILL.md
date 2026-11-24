---
name: unified-sim-change
description: What to do when a change alters what the game's deterministic simulation computes - its reference run or a replay regression fails, its rules or tuning change, or a unified bump moves its results. Deciding whether it was meant, re-pinning, blessing, Game.version, the long suite and the benchmark. Use before committing a change to the sim package, and whenever ./uni test reports a reference run or replay regression mismatch.
---

# Changing what the simulation computes

The reference run (`REFERENCE` in `simulation/tests/`) and the replay regressions (`simulation/tests/replays/`)
change only on purpose, never to make a test pass. How they work and are re-pinned: `unified/src/headless/README.md`
(Reference runs, Replay regressions, Re-pinning).

1. **Was it meant to?** A rules, tuning or physics change: yes. A refactor, a tooling or view-only change, a unified
   bump you thought neutral: no, so find the cause (the `unified-desync` skill). To run the old code:
   `git worktree add --detach .out/old origin/main`, run it there, `git worktree remove --force .out/old`; never
   `git stash`.
2. **If meant:** bump `Game.version` for a rule or tuning change (`unified/src/sim/README.md`, Build identity), then
   `./uni test --bless`: it re-pins the reference run and blesses the replay regressions that moved, and prints each
   value it changed. Review the diff (what moved, the README's Re-pinning) and commit it with the change. Results that
   moved on the build that pinned them are refused until a version is bumped. A recording whose Input, commands, Setup
   or Profile changed layout can't be blessed: record it again.
3. **Before handing back:** `./uni test --long` and `./uni bench` (a re-sim there that disagrees with the forward run
   is a determinism bug, not a speed problem).
4. **Say why** in the commit message: what the simulation computes now, and why the old results are no longer right.
