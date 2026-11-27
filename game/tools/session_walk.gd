class_name SessionWalk
extends PartyWalk
## The walk's parts about pausing and saving (game/tools/ui_walk.gd extends this and runs them in its order): the pause
## menu alone and with others in one process, its settings and Players list, the pause on the window going to the
## background, leaving with its question, the save a descent makes, Continue, and New game over a save.



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
## had the focus (a tool run's never had: its first loss means nothing); the setting turned off, it doesn't.
func _walk_focus_pause() -> void:
	root.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	await frames(2)
	expect(_pause_menu() == null, "a window that never had the focus doesn't pause when it loses it")
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
	expect(find(players, ^"%List").get_child_count() == 1, "one row left at once")
	await wait_for(func() -> bool: return session.local_indices.size() == 1, 3.0, "Drop out lets the guest go")
	await press_key(KEY_ESCAPE)
	await press_key(KEY_ESCAPE)
	expect(_pause_menu() == null, "back, and the menu closes")
	step("the Players list drops a couch guest")


## A save: the party goes down a floor (dev_board, then every local player's pick: the descent is a save point, the
## hoard's gold in it; the session hands its save over, kept in the slot), then leave from the pause menu: Leave asks
## first, saying where the run is saved; Stay keeps playing, Leave goes to the title, which offers Continue with the
## save's line, and has its focus.
func _walk_save_and_leave() -> void:
	var depth: int = Unified.data.hud.depth
	session.send_command(CommandDevBoard.new())
	await wait_for(func() -> bool: return Unified.data.hud.choosing, 10.0, "the lift reaches its bottom")
	for local: int in session.local_indices:
		var pick := CommandPickBoon.new()
		session.send_command(pick, local)
	await wait_for(func() -> bool: return Unified.data.hud.depth > depth, 5.0, "the party descends")
	await wait_for(func() -> bool: return _saved() != null and _saved().depth > depth, 3.0, "its save kept in the slot")
	if failed():
		return
	var summary: String = _summary()
	await seconds(0.5)
	await press_key(KEY_ESCAPE)
	await click(_pause_control("Leave") as Control)
	var dialog: Control = overlay("Dialog")
	var text: String = (find(dialog, ^"%Text") as Label).text
	expect(dialog.visible and text.contains(summary), "Leave asks first: %s" % text)
	await shot("17_leave_asks")
	await press_key(KEY_ESCAPE)
	expect(not dialog.visible and flow_name() == "PLAYING", "Esc stays")
	await click(_pause_control("Leave") as Control)
	await click(find(dialog, ^"%Ok") as Control)
	await wait_for_scene("Menu", 5.0)
	await frames(3)
	expect(flow_name() == "MENU", "Leave goes to the title")
	var line: String = (title_control("SaveLine") as Label).text
	expect(title_control("Continue").visible and line == summary, "Continue: %s" % line)
	expect(root.gui_get_focus_owner() == title_control("Continue"), "Continue has the focus")
	await shot("18_continue")
	step("a save at depth %d (%s); leave asks, the title offers Continue" % [_saved().depth, summary])


## New game over a save asks first (Back keeps it); Continue goes through hero select ("Continue your crypt") into the
## save's floor with its run and tally on the HUD, the purse starting at the save's gold (the first game's coin and its
## hoard).
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
	expect(Unified.data.hud.depth == save.depth and Unified.data.hud.lives == save.lives
		and Unified.data.hud.kills >= save.kills, "the HUD carries the save's run on: depth %d, %d lives, %d felled"
		% [Unified.data.hud.depth, Unified.data.hud.lives, Unified.data.hud.kills])
	var gold: int = PurseWatch.gold_of(find(current_scene, ^"Hud/%Purse") as Control)
	expect(save.gold > 0 and gold == save.gold, "the purse starts at the save's gold: %d (saved %d)" % [gold, save.gold])
	step("Continue: the save's floor, depth %d, %d felled" % [save.depth, save.kills])


## The pause menu with others (a LAN host in this process, nobody joined yet: the session isn't single player): an
## overlay, the game runs on; Pause for everyone pauses it for every player, the HUD's banner and the menu naming who;
## Resume for everyone, then Resume. Back to the title.
func _walk_online_pause() -> void:
	session.host_direct(_free_port())
	await wait_for(func() -> bool: return flow_name() == "PLAYING" and local_hero() != null, 8.0, "hosting on the LAN")
	if failed():
		return
	expect(session.game_input, "the game's input is on (blocked by %s)" % [game.get(&"_input_blocks")])
	await press_key(KEY_ESCAPE)
	expect(_pause_menu() != null, "Esc opens the pause menu")
	if failed():
		return
	var tick: int = session.tick
	var hero: Node3D = local_hero()
	var from: Vector3 = hero.global_position
	await key(KEY_D, true)
	await key(KEY_SPACE, true)
	await frames(20)
	expect(not session.paused and session.tick > tick, "online, the menu is an overlay: the game runs on")
	expect(hero.global_position.distance_to(from) < STILL, "a key held under it moves nobody")
	expect(_hero_action(hero) != EnumAction.ATTACK, "and an attack held under it attacks nobody")
	var pause_all: Button = _pause_control("PauseAll") as Button
	expect(pause_all.visible and pause_all.text == "Pause for everyone", "Pause for everyone is its own button")
	await click(pause_all)
	await wait_for(func() -> bool: return Unified.data.hud.paused, 2.0, "the game pauses for everyone")
	var banner: NameLabel = find(current_scene, ^"Hud/%PausedText") as NameLabel
	var heading: NameLabel = _pause_control("Heading") as NameLabel
	var me: String = setting(&"player_name")
	expect(banner.player_name == me and banner.text.begins_with("Paused by"),
		"the banner names who: %s" % banner.text)
	expect(heading.text == banner.text or heading.player_name == banner.player_name, "and the menu's heading: %s"
		% heading.text)
	expect(pause_all.text == "Resume for everyone", "the button resumes it for everyone")
	await shot("19_paused_for_everyone")
	await press_key(KEY_ESCAPE)
	expect(banner.is_visible_in_tree(), "with the menu closed, the banner shows who paused")
	await shot("19b_banner")
	await _walk_hosted_hud_fits(banner)
	await press_key(KEY_ESCAPE)
	pause_all = _pause_control("PauseAll") as Button
	await click(pause_all)
	await wait_for(func() -> bool: return not Unified.data.hud.paused, 2.0, "anyone resumes it for everyone")
	expect((_pause_control("Resume") as Button).text == "Back to the game", "online and running: Back to the game")
	await press_key(KEY_ESCAPE)
	expect(_pause_menu() == null, "Esc closes the overlay")
	from = hero.global_position
	await seconds(0.3)
	expect(hero.global_position.distance_to(from) > STILL, "a direction still held reads at once once it closes")
	expect(_hero_action(hero) != EnumAction.ATTACK, "an attack still held from under the menu acts only once let go")
	await key(KEY_D, false)
	await key(KEY_SPACE, false)
	await key(KEY_SPACE, true)
	await wait_for(func() -> bool: return _hero_action(hero) == EnumAction.ATTACK, 2.0, "pressed again, it attacks")
	await key(KEY_SPACE, false)
	game.call(&"leave")
	await wait_for_scene("Menu", 5.0)
	await frames(3)
	step("the pause menu online: an overlay, Pause and Resume for everyone, the banner names who")


## At 130 % in a game hosted on the LAN, paused for everyone: toasts clear of the plates, the counts, the session
## panel and the banner; a pad's join card clear of the counts and the panel, scaled no smaller than 0.8; the pause
## menu's panel inside the view less FitToView's margin.
func _walk_hosted_hud_fits(banner: Control) -> void:
	set_setting(&"ui_scale", 1.3)
	await frames(4)
	var hud: Control = find(current_scene, ^"Hud") as Control
	var crypt: Control = find(hud, ^"%Crypt") as Control
	var panel: Control = find(hud, ^"%SessionPanel") as Control
	for i: int in 3:
		game.call(&"toast", "%s +%d is back (Barbarian)" % [setting(&"player_name"), i + 1])
	await frames(4)
	expect_toasts_clear([find(hud, ^"%Heroes") as Control, crypt, panel, banner.get_parent().get_parent() as Control])
	await pad_button(JOY_BUTTON_START, 1)
	var cards: Control = find(hud, ^"%JoinCards") as Control
	await frames(3)
	var card_rect: Rect2 = cards.get_global_rect()
	expect(not card_rect.intersects(crypt.get_global_rect()) and not card_rect.intersects(panel.get_global_rect()),
		"a join card hangs below the counts and the panel: %s" % card_rect)
	expect(cards.scale.x >= 0.8, "and is scaled no smaller than 0.8: %.2f" % cards.scale.x)
	await shot("19c_hud_130")
	await pad_button(JOY_BUTTON_B, 1)
	await press_key(KEY_ESCAPE)
	var pause_panel: Control = find(_pause_menu(), ^"Stack/PauseScreen/Center/Panel") as Control
	var room: Rect2 = hud.get_viewport_rect().grow_individual(-FitToView.MARGIN.x, -FitToView.MARGIN.y,
		-FitToView.MARGIN.x, -FitToView.MARGIN.y)
	expect(room.grow(1.0).encloses(pause_panel.get_global_rect()), "the pause menu inside the view: %s in %s"
		% [pause_panel.get_global_rect(), room])
	await press_key(KEY_ESCAPE)
	set_setting(&"ui_scale", ui_scale)
	await frames(2)


## The pause menu over a replay (the walk's last game, recorded when it ended): Replay paused, Resume and Leave only;
## Leave goes to the title at once (no question).
func _walk_replay_pause() -> void:
	var recordings: PackedStringArray = DirAccess.get_directories_at("user://recordings")
	expect(recordings.size() > 0, "the walk's games were recorded")
	if failed():
		return
	recordings.sort()
	session.replay("user://recordings/" + recordings[recordings.size() - 1])
	await wait_for(func() -> bool: return scene_is("Play") and session.mode == UnifiedSession.MODE_REPLAY, 8.0,
		"a replay plays")
	if failed():
		return
	await frames(10)
	await press_key(KEY_ESCAPE)
	expect(_pause_menu() != null, "Esc opens the pause menu over the replay")
	if failed():
		return
	var heading: String = (_pause_control("Heading") as Label).text
	expect(heading == "Replay paused", "it says so: %s" % heading)
	for hidden: String in ["PauseAll", "Players", "Settings", "Quit"]:
		expect(not _pause_control(hidden).visible, "no %s over a replay" % hidden)
	await shot("20_replay_paused")
	await click(_pause_control("Leave"))
	await wait_for_scene("Menu", 5.0)
	expect(not overlay("Dialog").visible and flow_name() == "MENU", "Leave goes to the title, no question")
	step("the pause menu over a replay")


## A UDP port nobody uses now, for the walk's own host.
func _free_port() -> int:
	var probe := PacketPeerUDP.new()
	probe.bind(0)
	var port: int = probe.get_local_port()
	probe.close()
	return port


## The action a hero view shows (EnumAction; NONE without a view).
func _hero_action(view: Node3D) -> int:
	if view == null:
		return EnumAction.NONE
	var data: ViewHero = view.get(&"data")
	return data.action if data != null else EnumAction.NONE


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


## The slot's line ("Floor 1 · Normal · 3 lives · 101 gold").
func _summary() -> String:
	var saves: RefCounted = game.get(&"saves")
	var line: String = saves.call(&"summary")
	return line


## The save in the slot (null: none).
func _saved() -> UnifiedSetup:
	var saves: RefCounted = game.get(&"saves")
	var save: UnifiedSetup = saves.get(&"setup")
	return save
