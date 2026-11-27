class_name InteractLatch
extends RefCounted
## The Toggle way of holding Interact (Settings.hold_actions): a press while the HUD offers this player's hero a revive
## or a brazier's light (Hud_Hero.revive, Hud_Hero.kindle) latches Interact, held in the input fill as if the key
## stayed down, until the offer goes (the ally is up, the brazier lit, the hero walked off), a second press, or the
## hero is hurt (a blow breaks a revive or a kindling off anyway). The sim sees only a held button: it is the view's
## convenience, never a rule. Hold, the other way, latches nothing.
##
## step is the whole rule, a pure function of this frame's facts; play.gd keeps one latch per local player and sets
## its output as the player's input value (Input_Values.interact) on the session's input_wanted.

## Latched: Interact is held for the player.
var latched: bool = false


## This frame's latch for a player whose Settings.hold_actions is `toggle`, who pressed Interact (`pressed`, an edge),
## whose hero the HUD offers a revive or a light (`offered`) and who was hurt (`hurt`) since the last frame.
func step(toggle: bool, pressed: bool, offered: bool, hurt: bool) -> bool:
	if not toggle or hurt or not offered:
		latched = false
	elif pressed:
		latched = not latched
	return latched
