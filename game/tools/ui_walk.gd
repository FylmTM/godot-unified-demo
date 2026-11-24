extends MenuTool
## A walk through Crypt Crew's app with real input events, the godot suite's `walk` step (`./uni tool ui_walk`; with
## `--window --shots` it saves a PNG at each moment worth looking at, into .out/shots/ui_walk/):
##   the title (the focus on New game, a pad moves it) -> New game -> the crypt (a hero, the HUD; Esc pauses and
##   resumes) -> a couch guest joins and leaves (the toasts) -> a setting applies (Show FPS) -> leave -> the title ->
##   a join the menus didn't ask for fails (adopted, then the dialog says why; OK gives the focus back) -> the run
##   ends through Game.quit_app.


func _run() -> void:
	change_scene_to_file(str(ProjectSettings.get_setting("application/run/main_scene")))
	await wait_for_scene("Menu", 5.0)
	await frames(10)
	expect(flow_name() == "MENU", "the app starts on the menu (flow %s)" % flow_name())
	expect(root.gui_get_focus_owner() == title_control("NewGame"), "New game has the focus")
	await shot("01_title")
	step("the title")
	await _walk_pad()
	await _walk_new_game()
	await _walk_couch_guest()
	_walk_setting()
	await _walk_leave()
	await _walk_failed_join()


## A pad moves the focus between the title's buttons, and back.
func _walk_pad() -> void:
	await pad_button(JOY_BUTTON_DPAD_DOWN)
	expect(root.gui_get_focus_owner() == title_control("Quit"), "the d-pad moves the focus to Quit")
	await pad_button(JOY_BUTTON_DPAD_UP)
	expect(root.gui_get_focus_owner() == title_control("NewGame"), "and back to New game")
	step("pad navigation")


## New game: the app goes to the crypt once the session is up, and the local hero arrives with the HUD over it.
func _walk_new_game() -> void:
	await click_title("NewGame")
	await wait_for_scene("Play", 5.0)
	await wait_for(func() -> bool: return local_hero() != null, 8.0, "the local hero")
	expect(flow_name() == "PLAYING", "the flow is PLAYING (%s)" % flow_name())
	expect(session.mode == UnifiedSession.MODE_SINGLE, "a single-player session")
	var hud: Control = find(current_scene, ^"Hud") as Control
	expect(hud != null and hud.is_visible_in_tree(), "the HUD shows")
	await seconds(1.5)
	await shot("02_play")
	step("new game: the crypt, tick %d" % session.tick)
	await press_action(&"pause")
	await wait_for(func() -> bool: return Unified.data.hud.paused, 2.0, "Esc pauses the game")
	expect((find(hud, ^"%Paused") as Control).visible, "the HUD's banner says so")
	await shot("02b_paused")
	await press_action(&"pause")
	await wait_for(func() -> bool: return not Unified.data.hud.paused, 2.0, "Esc again resumes it")
	step("paused and resumed")


## A couch guest joining and leaving is news: a toast each, once the join is certain.
func _walk_couch_guest() -> void:
	var toasts: Control = overlay("Toasts")
	var guest: int = session.add_local_player(3, "Guest", null)
	expect(guest > 0, "a couch guest joins on pad 3")
	await wait_for(func() -> bool: return _toast_shows("Guest joined"), 5.0, "a toast: Guest joined")
	await seconds(0.4)  # the toast faded in
	await shot("03_guest_joined")
	session.remove_local_player(guest)
	await wait_for(func() -> bool: return _toast_shows("Guest left"), 5.0, "a toast: Guest left")
	step("a couch guest joined and left: %d toasts" % toasts.get_child_count())


## A setting applies the moment it is set: Show FPS shows the frame rate in the corner, and hides it again.
func _walk_setting() -> void:
	var fps: Control = find(game, ^"Overlays/Fps") as Control
	set_setting(&"show_fps", true)
	expect(fps.visible, "Show FPS shows the frame rate")
	set_setting(&"show_fps", false)
	expect(not fps.visible, "and hides it")
	step("a setting applies at once")


## Leaving ends the session; the menu follows once it said goodbye, its focus on New game again.
func _walk_leave() -> void:
	game.call(&"leave")
	await wait_for_scene("Menu", 5.0)
	await frames(3)
	expect(flow_name() == "MENU", "the flow is MENU (%s)" % flow_name())
	expect(session.status == UnifiedSession.STATUS_LEFT, "the session left")
	expect(root.gui_get_focus_owner() == title_control("NewGame"), "New game has the focus")
	step("left to the title")


## A start the menus didn't ask for is the app's too: a join by code (this build has no online play) is adopted,
## fails, and the title says why; OK closes the dialog and gives the focus back.
func _walk_failed_join() -> void:
	var dialog: Control = overlay("Dialog")
	session.join_online("ZZZZZZ")
	await wait_for(func() -> bool: return dialog.visible, 10.0, "the dialog says why the join failed")
	expect(scene_is("Menu"), "on the title")
	var heading: String = (find(dialog, ^"%Heading") as Label).text
	expect(heading == "Couldn't join the game", "the dialog's heading: %s" % heading)
	expect(root.gui_get_focus_owner() == find(dialog, ^"%Ok"), "OK has the focus")
	await frames(3)
	await shot("04_failed_join")
	await click(find(dialog, ^"%Ok") as Control)
	expect(not dialog.visible, "OK closes the dialog")
	expect(root.gui_get_focus_owner() == title_control("NewGame"), "the focus is back on New game")
	step("a failed join, adopted: %s" % (find(dialog, ^"%Detail") as Label).text)


func _toast_shows(text: String) -> bool:
	for toast: Node in overlay("Toasts").get_children():
		if (toast.get_node(^"%Text") as Label).text == text:
			return true
	return false
