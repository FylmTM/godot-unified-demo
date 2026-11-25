class_name Party
extends RefCounted
## The local players a game starts with, as hero select seated them: each seat's device, pick and name. Game starts the
## session with the first seat's Profile; the play scene's Couch brings the others in once the crypt is up.


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
