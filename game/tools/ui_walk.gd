extends MenuTool
## A walk through Crypt Crew's app with real input events (keys, pad buttons, the mouse), the godot suite's `walk`
## step (`./uni tool ui_walk`; with `--window --shots` it saves a PNG at each moment worth looking at, into
## .out/shots/ui_walk/):
##   the title (New game focused; the mouse over a button takes the focus and sounds; a screen that enters the tree
##   again is wired once; the d-pad moves the focus) -> pad A on New game -> the crypt (a hero, the HUD; Esc pauses
##   and resumes; the reconnecting plate takes nothing) -> a couch guest joins and leaves (the toasts) -> a setting
##   applies -> leave -> the title (toasts gone) -> New game again, and leave -> a join that waits (the Connecting
##   overlay; Esc cancels it at once, and so does its Cancel) -> a join that fails at once (one dialog, one error
##   sound, the reason as a sentence; pad B closes it), and again (pad A on OK) -> the run ends through Game.quit_app.
## That the app adopts a session its menus didn't start is coop.gd's: both its processes start from uni's flags.

## A local port nothing listens on: a join to it waits until cancelled.
const SILENT_PORT: int = 9


func _run() -> void:
	record_sounds()
	change_scene_to_file(str(ProjectSettings.get_setting("application/run/main_scene")))
	await wait_for_scene("Menu", 5.0)
	await frames(10)
	expect(flow_name() == "MENU", "the app starts on the menu (flow %s)" % flow_name())
	expect(root.gui_get_focus_owner() == title_control("NewGame"), "New game has the focus")
	await shot("01_title")
	step("the title")
	await _walk_title_wiring()
	await _walk_pad()
	await _walk_new_game()
	await _walk_couch_guest()
	_walk_setting()
	await _walk_leave()
	await _walk_new_game_again()
	await _walk_connecting()
	await _walk_failed_join()


## The title's buttons are the game's: the mouse over one takes the focus (with the select sound), and a screen that
## leaves the tree and enters again is still wired once.
func _walk_title_wiring() -> void:
	var quit_button: Button = title_control("Quit") as Button
	var mark: int = sounds.size()
	await hover(quit_button)
	expect(root.gui_get_focus_owner() == quit_button, "the mouse over Quit gives it the focus")
	expect(played(&"select", mark) == 1, "the focus moving sounds once (%s)" % [sounds.slice(mark)])
	await hover(title_control("NewGame"))
	expect(root.gui_get_focus_owner() == title_control("NewGame"), "and over New game, back")
	var wired: int = quit_button.pressed.get_connections().size()
	var screen: Control = title()
	var layer: Node = screen.get_parent()
	layer.remove_child(screen)
	layer.add_child(screen)
	expect(quit_button.pressed.get_connections().size() == wired, "a button entering the tree again is wired once")
	title_control("NewGame").grab_focus()
	step("the title's buttons: the mouse, the focus, the sound")


## A pad moves the focus between the title's buttons, and back.
func _walk_pad() -> void:
	await pad_button(JOY_BUTTON_DPAD_DOWN)
	expect(root.gui_get_focus_owner() == title_control("Quit"), "the d-pad moves the focus to Quit")
	await pad_button(JOY_BUTTON_DPAD_UP)
	expect(root.gui_get_focus_owner() == title_control("NewGame"), "and back to New game")
	step("pad navigation")


## Pad A on New game: the app goes to the crypt once the session is up, the local hero arrives with the HUD over it,
## and Esc pauses and resumes the game.
func _walk_new_game() -> void:
	var mark: int = sounds.size()
	await pad_button(JOY_BUTTON_A)
	expect(played(&"confirm", mark) == 1, "New game sounds its confirmation")
	await wait_for_scene("Play", 5.0)
	await wait_for(func() -> bool: return local_hero() != null, 8.0, "the local hero")
	expect(flow_name() == "PLAYING", "the flow is PLAYING (%s)" % flow_name())
	expect(session.mode == UnifiedSession.MODE_SINGLE, "a single-player session")
	var hud: Control = find(current_scene, ^"Hud") as Control
	expect(hud != null and hud.is_visible_in_tree(), "the HUD shows")
	await seconds(1.5)
	await shot("02_play")
	step("pad A on New game: the crypt, tick %d" % session.tick)
	await press_key(KEY_ESCAPE)
	await wait_for(func() -> bool: return Unified.data.hud.paused, 2.0, "Esc pauses the game")
	expect((find(hud, ^"%Paused") as Control).visible, "the HUD's banner says so")
	await shot("02b_paused")
	await press_key(KEY_ESCAPE)
	await wait_for(func() -> bool: return not Unified.data.hud.paused, 2.0, "Esc again resumes it")
	step("Esc paused and resumed")
	await _walk_link_status()


## The plate a lost link shows over play takes nothing from the player: no focus, the game's input on; Leave game
## is reached on purpose, with an up or down press.
func _walk_link_status() -> void:
	var link: Control = overlay("LinkStatus")
	link.call(&"show_reconnecting")
	await frames(2)
	expect(link.visible and root.gui_get_focus_owner() == null, "the plate shows and takes no focus")
	expect(session.game_input, "the game's input stays on")
	await shot("02c_reconnecting")
	await pad_button(JOY_BUTTON_DPAD_DOWN)
	expect(root.gui_get_focus_owner() == find(link, ^"%Leave"), "a press down reaches Leave game")
	link.call(&"close")
	expect(not link.visible and root.gui_get_focus_owner() == null, "closing it lets go of the focus")
	step("the reconnecting plate")


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


## Leaving ends the session; the menu follows once it said goodbye, its focus on New game again, the toasts gone.
func _walk_leave() -> void:
	game.call(&"leave")
	await wait_for_scene("Menu", 5.0)
	await frames(3)
	expect(flow_name() == "MENU", "the flow is MENU (%s)" % flow_name())
	expect(session.status == UnifiedSession.STATUS_LEFT, "the session left")
	expect(root.gui_get_focus_owner() == title_control("NewGame"), "New game has the focus")
	expect(overlay("Toasts").get_child_count() == 0, "the toasts are gone with the game")
	step("left to the title")


## A second game after a leave starts like the first.
func _walk_new_game_again() -> void:
	await click(title_control("NewGame"))
	await wait_for_scene("Play", 5.0)
	await wait_for(func() -> bool: return local_hero() != null, 8.0, "the local hero, again")
	step("New game again")
	await _walk_leave()


## A join that waits shows the Connecting overlay over the title, Cancel focused; Esc cancels it, and the overlay goes
## at once (the session says goodbye under the title). Its Cancel button does the same, with its sound.
func _walk_connecting() -> void:
	var connecting: Control = overlay("Connecting")
	var cancel: Control = find(connecting, ^"%Cancel") as Control
	session.join_direct("127.0.0.1:%d" % SILENT_PORT)
	await wait_for(func() -> bool: return connecting.visible, 3.0, "the Connecting overlay")
	await seconds(0.5)
	expect(root.gui_get_focus_owner() == cancel, "Cancel has the focus")
	expect(flow_name() == "STARTING", "the flow is STARTING (%s)" % flow_name())
	await shot("04_connecting")
	await press_key(KEY_ESCAPE)
	expect(not connecting.visible, "Esc hides the overlay at once")
	await wait_for(func() -> bool: return flow_name() == "MENU", 5.0, "back on the title once the join said goodbye")
	expect(session.status == UnifiedSession.STATUS_LEFT, "the join left")
	expect(root.gui_get_focus_owner() == title_control("NewGame"), "New game has the focus")
	step("a join that waits: the overlay, Esc cancels")
	session.join_direct("127.0.0.1:%d" % SILENT_PORT)
	await wait_for(func() -> bool: return connecting.visible, 3.0, "the Connecting overlay, again")
	var mark: int = sounds.size()
	await click(cancel)
	expect(not connecting.visible and played(&"press", mark) == 1, "Cancel sounds and hides the overlay")
	await wait_for(func() -> bool: return flow_name() == "MENU", 5.0, "back on the title")
	step("Cancel cancels")


## A join that fails at once (this build has no online play): one dialog saying why as a sentence, one error sound and
## no focus sound; pad B closes it and the focus is back on New game. Again, the same (OK pressed with pad A).
func _walk_failed_join() -> void:
	var dialog: Control = overlay("Dialog")
	var ok: Control = find(dialog, ^"%Ok") as Control
	for attempt: int in 2:
		var mark: int = sounds.size()
		session.join_online("ZZZZZZ")
		await wait_for(func() -> bool: return dialog.visible, 10.0, "the dialog says why the join failed")
		await frames(3)
		var heading: String = (find(dialog, ^"%Heading") as Label).text
		var text: String = (find(dialog, ^"%Text") as Label).text
		expect(heading == "Couldn't join the game", "the dialog's heading: %s" % heading)
		expect(text == "Online play is not available in this build.", "the dialog's reason: %s" % text)
		expect(played(&"error", mark) == 1 and played(&"select", mark) == 0,
			"one error sound and no other (%s)" % [sounds.slice(mark)])
		expect(root.gui_get_focus_owner() == ok, "OK has the focus")
		if attempt == 0:
			await shot("05_failed_join")
			await pad_button(JOY_BUTTON_B)
		else:
			mark = sounds.size()
			await pad_button(JOY_BUTTON_A)
			expect(played(&"press", mark) == 1, "OK sounds")
		expect(not dialog.visible, "the dialog closes")
		expect(root.gui_get_focus_owner() == title_control("NewGame"), "the focus is back on New game")
		step("a join that fails at once (%d): %s" % [attempt + 1, text])


func _toast_shows(text: String) -> bool:
	for toast: Node in overlay("Toasts").get_children():
		if (toast.get_node(^"%Text") as Label).text == text:
			return true
	return false
