---
name: unified-feedback
description: Handling the developer's playtest feedback - the F3 notes (text, screenshot, the session's recording) and freeze folders a dev build saves into the game's Godot user data. Find them with uni feedback, read and reproduce each (replay it headless or watch it paused in the game), fix or ask, then mark it done; and an agent's own note (uni drive note) turned into a replay regression. Use whenever the developer asks to look at, address or fix their feedback, notes, what they noted while playing, an F3 note, or a freeze, or when a bug you find while driving the game should become a regression.
---

# Handling feedback notes

"Feedback" is what the developer left while playing a dev build: F3 opens a note, Enter saves it with a screenshot
and the session's recording; a freeze of the session thread saves a `freeze-<time>` folder the same way. They are in
the game's Godot user data, never in the repo, and `./uni feedback` is the only way to reach them: never guess an OS
path. What a note holds and the command's options: `./uni feedback -h`.

1. **List.** `./uni feedback`: the open notes, newest first (kind: `note`, `bug` for one sent with the bug tag,
   `freeze`). It reads the developer's own user data, the one `./uni run` and the editor use; a run you drove or a
   check ran has its own, so your own notes never show there. None listed: say so, with the folder it names.
2. **Read each.** `./uni feedback show <note>`: the text, the screenshot's path (read the PNG: the note is often
   about what it shows), the tick and the game's version. A note is written in a hurry, mid-game: read it with its
   screenshot and its moment. Notes the developer didn't name are theirs too: handle every open one unless told
   otherwise, and say which you took.
3. **Reproduce.** A note with a recording replays (`show` prints both commands):
   - in the game, paused on its tick: `./uni drive start -- --replay "<folder>"`, then `shot`, `state`,
     `changes` and `step` (the `unified-godot` skill, Play-checking): see what the developer saw, measure it there;
   - headless, checked against its checkpoints: `./uni headless -- replay ...`. A recording of an older build
     plays and names the first tick it computes differently; a divergence the change didn't cause is the
     `unified-desync` skill's.
   A freeze replays headless into the frozen tick, which a deterministic sim reproduces under a debugger (on
   Windows `freeze.dmp` is a minidump of the frozen process).
4. **Ask before deciding.** A note says what felt wrong, rarely what to build. When the cause is clear and the fix
   follows the game's design, fix it. When the note asks for a design change, could mean two things, or the fix
   would change how the game plays, explain what you found and ask.
5. **Fix** with the game's usual checks (`unified-godot`, `unified-sim-change`). A bug in what the sim computes
   whose recording shows it: keep the note's folder as a replay regression, so it stays fixed
   (`unified/src/headless/README.md`, Replay regressions).
6. **Mark it done** once it is handled (fixed in your change, answered, or set aside by the developer):
   `./uni feedback done <note,...>` moves it to `feedback/done/`, never deletes it (`./uni feedback --done` lists
   them). Report each note: what it said, what you found, what you did.

## Your own note

A bug you meet while driving the game (the `unified-godot` skill, Play-checking) is kept the way the developer keeps
one, with no one at the keyboard:

1. `./uni drive start -- --autostart`, play up to the moment (`press`, `step`, `command`), then
   `./uni drive note "<what is wrong>" --bug`: the instance saves an F3 note as a player's F3 would (the text, the
   window's frame, the session's recording so far) into its own user data, and prints its folder and the `show` that
   reads it back.
2. `./uni feedback show <note> --instance <name>` (`--instance` on the list and `done` too: the instance's notes, never
   the developer's): read the screenshot, then run the headless replay it prints; it must agree with every checkpoint.
3. Keep it as a replay regression: copy the note's `inputs.unil` (and `snapshot.unis`) into
   `simulation/tests/replays/<name>/` (the line `show` prints), then `./uni test --bless` writes its expectation and
   `./uni test` reproduces it (`unified/src/headless/README.md`, Replay regressions). It records what the sim
   computes now: a bug it shows is fixed by a change that moves it, and the bless after that change is the
   `unified-sim-change` skill's.
4. `./uni feedback done <note> --instance <name>`, and `./uni drive stop`.
