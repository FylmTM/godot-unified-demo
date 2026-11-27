# Playing Crypt Crew

How to play: the controls, the menus, couch co-op, saves and playing together. The rules behind them are
[`rules.md`](rules.md).

## Starting

```sh
./uni run                            # in a window, from the title
./uni run -- --host-port 7777        # host a game on the LAN, straight past the title...
./uni run -- --join 127.0.0.1:7777   # ...and join it from a second window
./uni run -- --autostart --setup floor=arena,crowd=chase  # the arena, a crowd of hundreds chasing you
./uni tool lookdev --window --shots  # the art, posed in the look-dev scene
```

The title offers Continue (the saved run), New game (the hub: set the run at its two shrines, then everyone onto the
crypt's lift), Play together, Settings and Quit. To play two windows together on one machine, run `./uni run` twice:
Play together, Host on this network in one, Join an address (`127.0.0.1`) in the other.

## Controls

| | Keyboard and mouse | Pad |
|---|---|---|
| Move | WASD or the arrow keys | left stick |
| Aim | the mouse | right stick |
| Attack (held), throw what you carry | left mouse button or Space | right trigger or X |
| Grab, put down, revive (held) | E or right mouse button | A |
| Ability | Left Shift | left trigger or B |
| Pause | Esc | Start |

A hero that isn't aimed faces where it walks. Grab picks up the barrel or crate in front, glowing faintly; held beside a
downed ally ("[E] Revive" over them), it revives them. Ability is the class's own, and the HUD's pip says when it is
ready again:

- **Knight**: blocks while it is held, and charges behind the shield on Attack.
- **Rogue**: rolls.
- **Mage**: casts a fireball where the ring on the floor shows (the mouse's reach).
- **Barbarian**: heaves the elite or the downed ally in front, and throws it on Attack.

Attack, Grab and Ability can be rebound on both the keyboard and mouse and a pad, and the moves on the keyboard
(Settings, Controls: two bindings each; a pad's sticks and D-pad stay). The HUD shows each player's controls in the
glyphs of the device they use: for a few seconds after a player joins or picks up another device, or always, or never
(Settings, Gameplay). Settings, Gameplay also holds the accessibility settings: screen shake, flashes (off halves a
hit's flash and drops the light pulses and the plate's hurt pulse), reviving and lighting a brazier by holding Interact
or by a toggle (a press latches it while the prompt shows), and captions for what is heard more than seen. Settings,
Audio holds the master, interface, music and effects volumes.

## Hero select

Every new game starts there: four seats, the device that came there in the first; another pad's Start or A takes the
next free one. The keyboard and mouse sit only in the first seat: they are the first player's. Each seat answers to its
own device: left and right step its hero (Any, or one of the four; two may pick the same), accept readies it, back takes
the ready back and then gives the seat up. Once every seat taken is ready, the first seat's accept starts the game; an
Any becomes a class nobody picked. Each place's last pick is remembered (the first seat's, the second's, ...), and your
name (Settings, Gameplay; a game's own name until you choose one) is what the other players see.

## Couch co-op

Alone, the first player plays with any device, the keyboard and mouse or a pad, and can switch at will. Another pad's
Start mid-game opens a card on the HUD where it picks its hero, then joins with A (B gives up); from then on the first
player keeps the device they last played with. A guest's Back (the pad's View or Select) opens a card to drop out (A
drops out, B stays). A toast names who joined or left, and as which hero. Four play at most. Players joining over the
LAN join the same session beside them.

## Saves and pauses

A run saves itself as it begins, at each lift's descent, at each life lost and as it ends (the floor, the run's
difficulty and lives, the tally, and each player's boons by their profile id), in one slot; Continue on the title starts
it again from there (a run that ended, or the Pit, leaves nothing to continue). Only the host, or a player alone, keeps
it: a player in someone else's game keeps the host's last save in memory (from the start, when the host continued a
run), and is offered "Continue on your own" if the host leaves: it takes that save as its own (asking first if it
replaces one) and continues it through hero select.

Alone (couch included) the pause menu pauses the game; online (hosted or joined, on the LAN too) the game runs on under
it, and "Pause for everyone" pauses it for every player (anyone may resume it), the banner naming who paused. Alone, the
game also pauses when its window goes to the background (Settings, Gameplay).

## Playing together

Play together on the title hosts a game (online, by a lobby code; or on this network, by this machine's address) or
joins one (with a code, or an address), each side's couch picking its heroes first; Rejoin last game joins the last one
again. Hosting online starts the crypt at once and gets its code while it plays. In play the HUD shows the code or
address and how many play; the pause menu's Invite friends opens a game played alone to friends (online or on this
network), with Copy and Stop inviting. A couch guest is named after the first player ("Sexton +1"). A game that can't
start, or ends, says why; a lost link shows a plate while the game reconnects.

## Online (EOS)

Online play needs the demo's own Epic product and the EOS SDK, which the repo never holds: without them the online rows
are greyed with the reason, and everything else plays. To try it, follow
[`unified/docs/EOS.md`](https://github.com/FylmTM/godot-unified/blob/main/docs/EOS.md): create a product "Crypt Crew" in
the Epic developer portal, a custom client policy with only Lobbies and a client using it; download the EOS C SDK at the
version `unified/pins.cfg` pins and unzip it outside the repo; write the repo's `.env` (`UNIFIED_EOS_SDK` and the five
`UNIFIED_EOS_*` IDs). Then `./uni setup` (it says whether the SDK is found), `./uni tool online_check` (hosts online
from the menus), and `./uni coop`, `./uni coop --menus`, `./uni coop --rejoin`, `./uni coop --crash` (one at a time).
