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


## The rows again: this couch's players first, by local index (what the session has: a guest dropped out is gone at
## once, also while the clock stands), then everyone else present; names, heroes and the guests' Drop out.
func _show_players() -> void:
	if not is_inside_tree():
		return  # the app is quitting, or the menu closing: nothing to show
	var players: Array[int] = []
	for local: int in _session.local_indices:
		var key: int = _session.get_local_player_key(local)
		if key != 0:
			players.append(key)
	for player: int in _session.players:
		if player not in players and _session.get_local_index(player) < 0:
			players.append(player)
	var rows: Array[Node] = _list.get_children()
	for i: int in maxi(rows.size(), players.size()):
		if i >= players.size():
			_list.remove_child(rows[i])
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
		_list.remove_child(row)  # gone from the list at once: the session drops the guest by the next frame
		row.queue_free()
		_back.grab_focus()
		drop_requested.emit(local))
	return row
