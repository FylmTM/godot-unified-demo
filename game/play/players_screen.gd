class_name PlayersScreen
extends MenuScreen
## The pause menu's Players list: everyone in the game, their name and hero, and Drop out for each guest on this couch
## (it leaves; the others play on). It follows the players coming and going while it shows.

## The player asked to drop out the couch guest `local` (a local index).
signal drop_requested(local: int)

## A row (game/play/player_row.tscn).
@export var row_scene: PackedScene

@onready var _list: VBoxContainer = %List
@onready var _back: Button = %Back
@onready var _session: UnifiedSession = Unified.session


func _ready() -> void:
	super()
	_back.pressed.connect(back_requested.emit)
	_session.local_players_changed.connect(_show_players)
	Unified.data.hud.changed.connect(_show_players)
	_show_players()


## The rows again, one per player present, this couch's first: names, heroes and the guests' Drop out.
func _show_players() -> void:
	var players: Array[int] = []
	for player: int in _session.get_players():
		players.append(player)
	players.sort_custom(func(a: int, b: int) -> bool: return _here(a) and not _here(b))
	var rows: Array[Node] = _list.get_children()
	for i: int in maxi(rows.size(), players.size()):
		if i >= players.size():
			rows[i].queue_free()
			continue
		var row: PlayerRow = rows[i] if i < rows.size() else _add_row()
		var local: int = _session.get_local_index(players[i])
		row.show_player(_session.get_player_name(players[i]), Heroes.class_of(players[i]), local > 0, local >= 0)
		row.set_meta(&"local", local)
	var focus: Control = get_viewport().gui_get_focus_owner()
	if is_visible_in_tree() and (focus == null or not focus.is_visible_in_tree()):
		_back.grab_focus()  # the row that had it went with its guest


func _add_row() -> PlayerRow:
	var row: PlayerRow = row_scene.instantiate()
	_list.add_child(row)
	row.drop_requested.connect(func() -> void:
		var local: int = row.get_meta(&"local")
		drop_requested.emit(local))
	return row


func _here(player: int) -> bool:
	return _session.get_local_index(player) >= 0
