class_name SessionWalk
extends PartyWalk
## The walk's parts about pausing and saving (game/tools/ui_walk.gd extends this and runs them in its order): the pause
## menu alone and with others in one process, its settings and Players list, the pause on the window going to the
## background, leaving with its question, the save a surge makes, Continue, and New game over a save.

## A local port for the walk's own host (nobody joins it).
const HOST_PORT: int = 47_311


## The pause menu alone (single player): Esc opens it, the session's clock stops (the tick stands) and the game's
## input is off; its settings open over it and Esc comes back; Esc again resumes, the clock runs.
func _walk_single_pause() -> void:
	await press_key(KEY_ESCAPE)
	var menu: Control = _pause_menu()
	expect(menu != null, "Esc opens the pause menu")
	if failed():
		return
	await wait_for(func() -> bool: return session.paused, 2.0, "alone, the menu stops the clock")
	expect(not session.game_input, "the game's input is off under it")
	var tick: int = session.tick
	await frames(30)
	expect(session.tick == tick, "the tick stands while it shows (%d, then %d)" % [tick, session.tick])
	expect(not (_pause_control("PauseAll") as Control).visible, "alone, no Pause for everyone")
	await shot("02b_paused")
	await click(_pause_control("Settings") as Control)
	expect(_pause_top(menu) == "SettingsScreen", "Settings opens over the pause menu")
	await press_key(KEY_ESCAPE)
	expect(_pause_top(menu) == "PauseScreen", "Esc comes back to the pause menu")
	await press_key(KEY_ESCAPE)
	expect(_pause_menu() == null, "Esc again resumes")
	await wait_for(func() -> bool: return not session.paused and session.tick > tick, 2.0, "the clock runs again")
	expect(session.game_input, "and the game's input is back")
	step("the pause menu alone: the clock stands, settings over it, Esc resumes")


## The window going to the background in a single-player game opens the pause menu (it pauses), once the window has
## had the focus; the setting turned off, it doesn't.
func _walk_focus_pause() -> void:
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	set_setting(&"pause_in_background", false)
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames(2)
	expect(_pause_menu() == null, "with the setting off, the background doesn't pause")
	set_setting(&"pause_in_background", true)
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames(2)
	expect(_pause_menu() != null, "the window in the background opens the pause menu")
	await wait_for(func() -> bool: return session.paused, 2.0, "and pauses")
	await press_key(KEY_ESCAPE)
	expect(_pause_menu() == null, "Esc resumes")
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	step("the window in the background pauses")


## The pause menu's Players list drops a couch guest: pad 1 joins, Esc opens the menu, Players lists the first player
## and the guest (only the guest with Drop out), and its Drop out lets the guest go.
func _walk_players_list() -> void:
	await press_key(KEY_D)
	await _join(1)
	await press_key(KEY_ESCAPE)
	var menu: Control = _pause_menu()
	await click(_pause_control("Players") as Control)
	var players: Control = menu.call(&"top")
	expect(players != null and players.name == "PlayersScreen", "Players opens the list")
	if failed():
		return
	var rows: Array[Node] = find(players, ^"%List").get_children()
	expect(rows.size() == 2, "it lists the first player and the guest (%d rows)" % rows.size())
	var drops: Array[Control] = []
	for row: Node in rows:
		var can_drop: bool = row.call(&"droppable")
		if can_drop:
			drops.append(find(row, ^"%Drop") as Control)
	expect(drops.size() == 1, "only the guest can be dropped (%d)" % drops.size())
	await frames(3)
	await shot("16_players")
	await click(drops[0])
	await wait_for(func() -> bool: return session.get_local_indices().size() == 1, 3.0, "Drop out lets the guest go")
	await press_key(KEY_ESCAPE)
	await press_key(KEY_ESCAPE)
	expect(_pause_menu() == null, "back, and the menu closes")
	step("the Players list drops a couch guest")


## A save: play on until a surge has risen (the session hands its save over, kept in the slot), then leave from the
## pause menu: Leave asks first, saying where the crypt is saved; Stay keeps playing, Leave goes to the title, which
## offers Continue with the save's line, and has its focus.
func _walk_save_and_leave() -> void:
	await wait_for(func() -> bool: return Unified.data.hud.surges > 0, 10.0, "a surge rises")
	await wait_for(func() -> bool: return _saved() != null, 3.0, "its save kept in the slot")
	if failed():
		return
	var surges: int = Unified.data.hud.surges
	await press_key(KEY_ESCAPE)
	await click(_pause_control("Leave") as Control)
	var dialog: Control = overlay("Dialog")
	var text: String = (find(dialog, ^"%Text") as Label).text
	expect(dialog.visible and text.contains("saved at surge %d" % surges), "Leave asks first: %s" % text)
	await shot("17_leave_asks")
	await press_key(KEY_ESCAPE)
	expect(not dialog.visible and flow_name() == "PLAYING", "Esc stays")
	await click(_pause_control("Leave") as Control)
	await click(find(dialog, ^"%Ok") as Control)
	await wait_for_scene("Menu", 5.0)
	await frames(3)
	expect(flow_name() == "MENU", "Leave goes to the title")
	var line: String = (title_control("SaveLine") as Label).text
	expect(title_control("Continue").visible and line.contains("Surge %d" % _saved().surges), "Continue: %s" % line)
	expect(root.gui_get_focus_owner() == title_control("Continue"), "Continue has the focus")
	await shot("18_continue")
	step("a save at surge %d; leave asks, the title offers Continue" % surges)


## New game over a save asks first (Back keeps it); Continue goes through hero select ("Continue your crypt") into the
## save's floor with its tally on the HUD.
func _walk_continue() -> void:
	await click(title_control("NewGame"))
	var dialog: Control = overlay("Dialog")
	expect(dialog.visible and (find(dialog, ^"%Heading") as Label).text == "Start a new crypt?",
		"New game over a save asks first")
	await press_key(KEY_ESCAPE)
	expect(top_screen() == title(), "Back stays on the title")
	var save: UnifiedSetup = _saved()
	await _walk_hero_select_keyboard("Continue")
	await wait_for_scene("Play", 5.0)
	await wait_for(func() -> bool: return local_hero() != null, 8.0, "the local hero, on the save")
	if failed():
		return
	expect(Unified.data.hud.surges == save.surges and Unified.data.hud.kills >= save.kills,
		"the HUD carries the save's tally on: surge %d, %d felled" % [Unified.data.hud.surges, Unified.data.hud.kills])
	step("Continue: the save's floor, surge %d, %d felled" % [save.surges, save.kills])


## The pause menu with others (a LAN host in this process, nobody joined yet: the session isn't single player): an
## overlay, the game runs on; Pause for everyone pauses it for every player, the HUD's banner and the menu naming who;
## Resume for everyone, then Resume. Back to the title.
func _walk_online_pause() -> void:
	session.host_direct(HOST_PORT)
	await wait_for(func() -> bool: return flow_name() == "PLAYING" and local_hero() != null, 8.0, "hosting on the LAN")
	if failed():
		return
	expect(session.game_input, "the game's input is on (blocked by %s)" % [game.get(&"_input_blocks")])
	await press_key(KEY_ESCAPE)
	expect(_pause_menu() != null, "Esc opens the pause menu")
	if failed():
		return
	var tick: int = session.tick
	await frames(20)
	expect(not session.paused and session.tick > tick, "online, the menu is an overlay: the game runs on")
	var pause_all: Button = _pause_control("PauseAll") as Button
	expect(pause_all.visible and pause_all.text == "Pause for everyone", "Pause for everyone is its own button")
	await click(pause_all)
	await wait_for(func() -> bool: return Unified.data.hud.paused, 2.0, "the game pauses for everyone")
	var pauser: String = "Paused by %s" % setting(&"player_name")
	var banner: Label = find(current_scene, ^"Hud/%PausedText") as Label
	expect(banner.text == pauser, "the banner names who: %s" % banner.text)
	expect((_pause_control("Heading") as Label).text == pauser, "and the menu's heading")
	expect(pause_all.text == "Resume for everyone", "the button resumes it for everyone")
	await shot("19_paused_for_everyone")
	await click(pause_all)
	await wait_for(func() -> bool: return not Unified.data.hud.paused, 2.0, "anyone resumes it for everyone")
	await press_key(KEY_ESCAPE)
	expect(_pause_menu() == null, "Esc closes the overlay")
	game.call(&"leave")
	await wait_for_scene("Menu", 5.0)
	await frames(3)
	step("the pause menu online: an overlay, Pause and Resume for everyone, the banner names who")


## The play scene's pause menu while it shows (null: closed, or not in play).
func _pause_menu() -> Control:
	if not scene_is("Play"):
		return null
	var menu: Control = current_scene.call(&"pause_menu")
	return menu


## The pause screen's control `unique_name` (null, failing the run, when the menu isn't open).
func _pause_control(unique_name: String) -> Control:
	var menu: Control = _pause_menu()
	return find(menu.get_node_or_null(^"Stack/PauseScreen") if menu != null else null, "%" + unique_name) as Control


## The name of the pause menu's screen on top.
func _pause_top(menu: Control) -> String:
	var top: Control = menu.call(&"top")
	return top.name


## The save in the slot (null: none).
func _saved() -> UnifiedSetup:
	var saves: RefCounted = game.get(&"saves")
	var save: UnifiedSetup = saves.get(&"setup")
	return save
