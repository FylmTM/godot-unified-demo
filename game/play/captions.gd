class_name Captions
extends RefCounted
## Captions (Settings.captions): a toast's words for the news a player hears more than sees, each shown once its event
## is CONFIRMED (play.gd): a surge rising (its bell), the King's roar, its ward breaking, a hero going down, a gate
## opening. No sound carries meaning a caption doesn't give (docs/ART.md, The look).


## The caption for `event` ("" for none), with names from `session`.
static func of(event: UnifiedEvent, session: UnifiedSession) -> String:
	if event is EventSurge:
		return "A surge rises"
	if event is EventBossStage:
		return "The King roars"
	if event is EventBossWard and not (event as EventBossWard).up:
		return "The ward breaks"
	if event is EventHeroDowned:
		return "%s is down" % session.get_player_name((event as EventHeroDowned).player)
	if event is EventGate and (event as EventGate).open:
		return "A gate opens"
	return ""


## The toast to show for `event` with captions `on` ("" for none: captions off show nothing).
static func toast(event: UnifiedEvent, session: UnifiedSession, on: bool) -> String:
	return of(event, session) if on else ""
