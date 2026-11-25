class_name Party
extends RefCounted
## The local players a game starts with, as hero select seated them: each seat's device, pick and name. Game starts the
## session with the first seat's Profile; the play scene's Couch brings the others in once the crypt is up.
##
## A seat's place in the party is the local index its player gets: the first player 0, each guest the next (the
## session gives a guest the lowest free index, so a guest joining mid-game takes the place one who left freed). Its
## name and its remembered pick (Settings.hero_picks) go by that place.


## One seat: who plays, on what, as which hero.
class Seat:
	## UnifiedSession.DEVICE_KEYBOARD, or a pad's id.
	var device: int
	## The pick (EnumClass, Any included).
	var hero_class: int
	## The name the player goes by in the session.
	var player_name: String

	func _init(seat_device: int, seat_class: int, seat_name: String) -> void:
		device = seat_device
		hero_class = seat_class
		player_name = seat_name


## The seats, the first player's first.
var seats: Array[Seat] = []


## Each Any among the seats as a class, now that the party is known: picked classes stand, and each Any takes the
## first class no seat picked (in seat order). With every class picked, an Any stays Any (the sim resolves it).
func resolve_any() -> void:
	var taken: Array[int] = []
	for seat: Seat in seats:
		taken.append(seat.hero_class)
	for seat: Seat in seats:
		if seat.hero_class != EnumClass.ANY:
			continue
		for hero_class: int in Heroes.classes():
			if hero_class not in taken:
				seat.hero_class = hero_class
				taken.append(hero_class)
				break


## The name of the player at party place `local` (a local index): this machine's player's own for the first, then
## theirs and "+1", "+2"... for their couch guests ("Sexton +1"), so two machines' guests never share a name. Cut, as
## the player's own is, to what the session sends (UnifiedSession.NAME_MAX bytes), the "+1" kept.
static func name_of(local: int) -> String:
	if local == 0:
		return Settings.player_name
	var suffix: String = " +%d" % local
	var base: String = Settings.player_name
	while (base + suffix).to_utf8_buffer().size() > UnifiedSession.NAME_MAX:
		base = base.left(-1)
	return base.strip_edges() + suffix


## The lowest local index none of `taken` holds: where the next guest goes.
static func free_place(taken: Array[int]) -> int:
	var place: int = 0
	while place in taken:
		place += 1
	return place
