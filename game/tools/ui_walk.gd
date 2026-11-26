extends TogetherWalk
## A walk through Crypt Crew's app with real input events (keys, pad buttons and sticks of several pads, the mouse),
## the godot suite's `walk` step (`./uni tool ui_walk`; with `--window --shots` it saves a PNG at each moment worth
## looking at, into .out/shots/ui_walk/). In order:
##   - the title: New game focused, its frame pulsing without a change to the theme; the mouse over a button takes the
##     focus and sounds; a screen that enters the tree
##     again is wired once; the d-pad moves the focus; the prompts' device flips (a stick's noise and a mouse's nudge
##     don't flip it, a trigger and a real move do);
##   - the settings: every tab on the keyboard's prompts (E and Q) and on a pad's (the shoulders, the d-pad through
##     every row, the focus never lost); a choice applies; the panel fits at 130 % interface size; rebinding on both
##     schemes (a key, a swap, a click outside cancelling, Esc and a reserved key, a mouse button and a trigger in the
##     second slot, a pad button, a refused clear, the prompt bar's Cancel and Clear, the resets); attack left on F;
##     the name field (PartyWalk);
##   - pad A on New game: hero select on pads (PartyWalk), the party in the crypt, the guest dropping out, F attacks,
##     the hints follow the device and the setting, the pause menu alone (SessionWalk), the reconnecting plate takes
##     nothing;
##   - the couch's join cards (PartyWalk), with the toasts and the guests' own glyphs; the Players list drops a guest;
##     a key held while a guest leaves and released while the first player is free walks nobody once the guest is
##     back; the window in the background pauses;
##   - a surge's save, leaving from the pause menu (it asks), the title's Continue, New game over a save (it asks), the
##     continued game (SessionWalk); a settings file that didn't read is told once; the pause menu online (a LAN host
##     alone: Pause and Resume for everyone, input under it moving nobody); the pause menu over a replay;
##   - Play together (TogetherWalk): online greyed with the library's sentence (or offered), the code field and a join
##     by code that fails, a LAN host from the menus on the saved crypt (the session panel, Invite friends, Copy, Stop
##     inviting), a game alone whose opening fails and then opens while paused, a join by address that fails, Rejoin;
##   - a join that waits (the Connecting overlay; Esc and Cancel cancel it at once), a join that fails at once (one
##     dialog, one error sound, the reason as a sentence; pad B and pad A close it); the run ends through
##     Game.quit_app.
## That the app adopts a session its menus didn't start is coop.gd's (`uni coop`: both processes start from uni's
## flags); `uni coop --menus` proves the menus' host and join across two processes. A look pass runs it at another
## window or interface size: `./uni tool --window --shots --offline --size 2560x1440 ui_walk -- --ui-scale=0.8`.

## A local port nothing listens on: a join to it waits until cancelled.
const SILENT_PORT: int = 9
## How long the focus frame is watched pulsing, in frames.
const PULSE_FRAMES: int = 30


func _run() -> void:
	record_sounds()
	await look_at_scale()
	change_scene_to_file(str(ProjectSettings.get_setting("application/run/main_scene")))
	await wait_for_scene("Menu", 5.0)
	await frames(10)
	expect(flow_name() == "MENU", "the app starts on the menu (flow %s)" % flow_name())
	expect(root.gui_get_focus_owner() == title_control("NewGame"), "New game has the focus")
	await shot("01_title")
	step("the title")
	for walk: Callable in [_walk_focus_pulse, _walk_title_wiring, _walk_pad, _walk_prompt_device, _walk_settings, _walk_new_game,
			_walk_couch, _walk_players_list, _walk_stuck_key, _walk_focus_pause, _walk_setting, _walk_leave,
			_walk_new_game_again, _walk_online_pause, _walk_replay_pause, _walk_play_together, _walk_join_code,
			_walk_lan_host, _walk_open_to_friends, _walk_join_address, _walk_connecting, _walk_failed_join]:
		if failed():
			return
		await walk.call()


## The focus frame pulses in its drawing (FocusRing), never by changing the theme: a theme's item that changes
## re-themes every control in the tree, milliseconds a frame on every screen. While New game has the focus the theme
## stays as it is, and the button is redrawn every frame, so the pulse moves.
func _walk_focus_pulse() -> void:
	var focused: Control = root.gui_get_focus_owner()
	var counts: Dictionary[String, int] = {"changes": 0, "draws": 0}
	var on_change: Callable = func() -> void: counts["changes"] += 1
	var on_draw: Callable = func() -> void: counts["draws"] += 1
	ThemeDB.get_project_theme().changed.connect(on_change)
	focused.draw.connect(on_draw)
	await frames(PULSE_FRAMES)
	ThemeDB.get_project_theme().changed.disconnect(on_change)
	focused.draw.disconnect(on_draw)
	expect(counts["changes"] == 0, "the theme never changes while the focus frame pulses (%d changes in %d frames)"
		% [counts["changes"], PULSE_FRAMES])
	expect(counts["draws"] >= PULSE_FRAMES - 1, "the focused button is redrawn every frame (%d draws in %d frames)"
		% [counts["draws"], PULSE_FRAMES])
	step("the focus frame pulses, the theme unchanged")


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
	expect(root.gui_get_focus_owner() == title_control("PlayTogether"), "the d-pad moves the focus to Play together")
	await pad_button(JOY_BUTTON_DPAD_UP)
	expect(root.gui_get_focus_owner() == title_control("NewGame"), "and back to New game")
	step("pad navigation")


## The prompts' device: a key turns them to the keyboard, a stick's noise doesn't turn them to the pad, a trigger
## past half does; a mouse's nudge doesn't turn them back, a real move does.
func _walk_prompt_device() -> void:
	await press_key(KEY_SHIFT)
	expect(last_kind() == Bindings.Kind.KEYBOARD, "a key: the keyboard's prompts")
	await pad_axis(JOY_AXIS_LEFT_X, 0.3)
	await pad_axis(JOY_AXIS_LEFT_X, 0.0)
	expect(last_kind() == Bindings.Kind.KEYBOARD, "a stick's noise (0.3) doesn't turn them to the pad")
	await pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.8)
	await pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	expect(last_kind() == Bindings.Kind.PAD, "a trigger past half does")
	await nudge_mouse(Vector2(3, 0))
	expect(last_kind() == Bindings.Kind.PAD, "a mouse's nudge (3 px) doesn't turn them back")
	await nudge_mouse(Vector2(20, 0))
	expect(last_kind() == Bindings.Kind.KEYBOARD, "a real move (20 px) does")
	step("the prompts' device: the thresholds")


## The settings screen over the title: each tab on the keyboard's prompts and on a pad's, a choice that applies at
## once, the panel at 130 %, rebinding on both schemes, and Back.
func _walk_settings() -> void:
	await click(title_control("Settings"))
	var screen: Control = top_screen()
	expect(screen != null and screen.name == "SettingsScreen", "Settings opens the settings screen")
	if failed():
		return
	var tabs: TabContainer = find(screen, ^"%Tabs") as TabContainer
	var fps: Control = find(tabs, ^"Video/Margin/Rows/ShowFps/Row/Choice") as Control
	await click(fps)
	var shown: bool = setting(&"show_fps")
	expect(shown, "the Show FPS choice turns it on")
	expect((find(game, ^"Overlays/Fps") as Control).visible, "and the frame rate shows at once")
	await click(fps)
	shown = setting(&"show_fps")
	expect(not shown, "and off again")
	for tab: String in ["Video", "Audio", "Controls", "Gameplay"]:
		expect(tabs.get_current_tab_control().name == tab, "E steps to the %s tab" % tab)
		await frames(2)
		await shot("10_settings_%s_keyboard" % tab.to_lower())
		await press_key(KEY_E)
	expect(tabs.current_tab == 0, "E past the last tab wraps to the first")
	await press_key(KEY_Q)
	expect(tabs.get_current_tab_control().name == "Gameplay", "Q steps back, wrapping to the last")
	await _walk_name_field(screen)
	await pad_button(JOY_BUTTON_RIGHT_SHOULDER)
	expect(tabs.current_tab == 0, "RB steps forward, wrapping to the first")
	for tab: String in ["Video", "Audio", "Controls", "Gameplay"]:
		expect(tabs.get_current_tab_control().name == tab, "RB steps to the %s tab" % tab)
		if tab == "Controls":
			var scheme: Control = find(tabs, ^"Controls/Margin/Content/SchemeRow/Row/Scheme") as Control
			expect(root.gui_get_focus_owner() == scheme, "the Controls tab's scheme has the focus")
			await pad_button(JOY_BUTTON_A)  # the gamepad's scheme
		await _walk_tab_with_pad(screen)
		await frames(2)
		await shot("11_settings_%s_pad" % tab.to_lower())
		await pad_button(JOY_BUTTON_RIGHT_SHOULDER)
	await pad_button(JOY_BUTTON_LEFT_SHOULDER)
	expect(tabs.get_current_tab_control().name == "Gameplay", "LB steps back, wrapping to the last")
	expect(last_kind() == Bindings.Kind.PAD, "a pad: its prompts")
	step("the settings' tabs, on both devices' prompts")
	await _walk_interface_size(screen)
	await _walk_rebinding(screen)
	await press_key(KEY_ESCAPE)
	expect(top_screen() == title(), "Esc closes the settings")
	expect(root.gui_get_focus_owner() == title_control("Settings"), "Settings has the focus back")
	title_control("NewGame").grab_focus()
	await _walk_title_fits()
	step("back to the title")


## The title's column follows the interface size: at 130 % it shrinks to fit the view less FitToView's margin, and
## back at the run's size it is whole again.
func _walk_title_fits() -> void:
	var column: Control = find(title(), ^"Column") as Control
	set_setting(&"ui_scale", 1.3)
	await frames(4)
	var view: Rect2 = column.get_viewport_rect()
	var room: Rect2 = view.grow_individual(0.0, -FitToView.MARGIN.y, 0.0, -FitToView.MARGIN.y)
	expect(room.grow(1.0).encloses(column.get_global_rect()), "at 130 %%, the title's column fits: %s in %s"
		% [column.get_global_rect(), room])
	set_setting(&"ui_scale", ui_scale)
	await frames(4)
	expect(column.get_viewport_rect().encloses(column.get_global_rect()), "and back, it still does: %s"
		% column.get_global_rect())


## Down the shown tab with the d-pad, row by row, and back up: the focus is never lost and never leaves the screen.
func _walk_tab_with_pad(screen: Control) -> void:
	for direction: JoyButton in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_UP]:
		for i: int in 10:
			await pad_button(direction)
			var focus: Control = root.gui_get_focus_owner()
			expect(focus != null and screen.is_ancestor_of(focus), "the d-pad keeps the focus on the screen")


## The panel at the largest interface size: the heading, the tabs and Back all on screen, clear of the prompt bar.
func _walk_interface_size(screen: Control) -> void:
	set_setting(&"ui_scale", 1.3)
	await frames(3)
	var view: Rect2 = screen.get_viewport_rect()
	for part: NodePath in [^"Panel/Rows/Heading", ^"%Tabs", ^"%Back"]:
		var rect: Rect2 = (find(screen, part) as Control).get_global_rect()
		expect(view.encloses(rect), "at 130 %%, %s is on screen (%s in %s)" % [part, rect, view])
	var bar: Control = find(current_scene, ^"UI/PromptBar") as Control
	var back: Rect2 = (find(screen, ^"%Back") as Control).get_global_rect()
	expect(not back.intersects(bar.get_global_rect()), "at 130 %, Back is clear of the prompt bar")
	await shot("14_settings_130")
	set_setting(&"ui_scale", ui_scale)
	await frames(2)
	step("the settings at 130 %")


## Rebinding on the Controls tab, on both schemes. Attack stays on F for the crypt.
func _walk_rebinding(screen: Control) -> void:
	var controls: Node = screen.call(&"show_tab", "Controls")
	controls.call(&"show_scheme", Bindings.Kind.KEYBOARD)
	var attack_row: Node = controls.call(&"row_of", &"attack")
	var grab_row: Node = controls.call(&"row_of", &"interact")
	var attack: Array = attack_row.call(&"slots")
	var grab: Array = grab_row.call(&"slots")
	var attack_first: Button = attack[0]
	var attack_second: Button = attack[1]
	var grab_first: Button = grab[0]
	await _listen_on(attack_first)
	expect(prompt_words() == PackedStringArray(["Cancel", "Clear"]), "the prompt bar says Cancel and Clear")
	await shot("12_rebinding")
	await press_key(KEY_ENTER)
	expect(_listening(attack_first), "a reserved key (Enter) isn't bound: the slot still listens")
	await press_key(KEY_F)
	expect(_tokens(&"attack", Bindings.Kind.KEYBOARD) == ["key:F", "key:Space"], "F binds to attack")
	expect(prompt_words() != PackedStringArray(["Cancel", "Clear"]), "the prompt bar is back")
	await _listen_on(grab_first)
	await press_key(KEY_F)
	expect(_tokens(&"interact", Bindings.Kind.KEYBOARD) == ["key:F", "mouse:2"], "F binds to Grab")
	expect(_tokens(&"attack", Bindings.Kind.KEYBOARD) == ["key:E", "key:Space"], "attack takes Grab's E")
	await frames(2)
	await shot("13_rebound")
	await _listen_on(attack_first)
	await click(find(screen, ^"Panel/Rows/Heading") as Control)
	expect(not _listening(attack_first), "a click outside the slot cancels")
	expect(_tokens(&"attack", Bindings.Kind.KEYBOARD) == ["key:E", "key:Space"], "and binds nothing")
	await _listen_on(attack_first)
	await press_key(KEY_ESCAPE)
	expect(not _listening(attack_first) and top_screen() == screen, "Esc cancels the slot, not the screen")
	await _listen_on(attack_second)
	await click(attack_second)
	expect(_tokens(&"attack", Bindings.Kind.KEYBOARD) == ["key:E", "mouse:1"], "a click on the slot binds the mouse")
	await _reset(controls)
	expect(_tokens(&"attack", Bindings.Kind.KEYBOARD) == ["mouse:1", "key:Space"], "Reset puts the keyboard's back")
	controls.call(&"show_scheme", Bindings.Kind.PAD)
	await _listen_on(attack_first)
	await pad_button(JOY_BUTTON_DPAD_UP)
	expect(_listening(attack_first), "the d-pad isn't bound: the slot still listens")
	await pad_button(JOY_BUTTON_Y)
	expect(_tokens(&"attack", Bindings.Kind.PAD) == ["button:3", "button:2"], "a pad's Y binds to attack")
	await _listen_on(attack_second)
	await pad_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await pad_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	expect(_tokens(&"attack", Bindings.Kind.PAD) == ["button:3", "axis:4+"], "the left trigger binds to slot two")
	await _listen_on(grab_first)
	await pad_button(JOY_BUTTON_BACK)
	expect(_tokens(&"interact", Bindings.Kind.PAD) == ["button:0"], "Grab's only pad binding can't be cleared")
	expect((find(controls, ^"%Notice") as Control).visible, "and the tab says why")
	await shot("15_refused")
	await _reset(controls)
	expect(_tokens(&"attack", Bindings.Kind.PAD) == ["axis:5+", "button:2"], "Reset puts the pad's back")
	controls.call(&"show_scheme", Bindings.Kind.KEYBOARD)
	await _listen_on(attack_first)
	await press_key(KEY_F)
	expect(_tokens(&"attack", Bindings.Kind.KEYBOARD) == ["key:F", "key:Space"], "attack on F, for the crypt")
	step("rebinding: a key, a swap, cancels, refusals, a mouse button, pad buttons, a trigger, the resets")


## Shows `slot` (its tab scrolls it into view, as the d-pad would) and clicks it: it listens.
func _listen_on(slot: Button) -> void:
	slot.grab_focus()
	await frames(3)
	await click(slot)
	expect(_listening(slot), "a click on %s's slot makes it listen" % slot.get(&"action"))


func _listening(slot: Button) -> bool:
	var listening: bool = slot.call(&"is_listening")
	return listening


func _reset(controls: Node) -> void:
	var reset: Control = find(controls, ^"%Reset") as Control
	reset.grab_focus()
	await frames(3)
	await click(reset)


## The tokens of `action`'s bindings of `kind`, in order.
func _tokens(action: StringName, kind: Bindings.Kind) -> Array[String]:
	var out: Array[String] = []
	for event: InputEvent in Bindings.events(action, kind):
		out.append(Bindings.to_token(event))
	return out


## A pad's A on New game: hero select, then the crypt once the session is up, the HUD over it; the guest drops out,
## F (bound in the settings) attacks, the hints follow the device and the setting, and the pause menu pauses.
func _walk_new_game() -> void:
	await _walk_hero_select()
	if failed():
		return
	expect(flow_name() == "PLAYING", "the flow is PLAYING (%s)" % flow_name())
	expect(session.mode == UnifiedSession.MODE_SINGLE, "a single-player session")
	var hud: Control = find(current_scene, ^"Hud") as Control
	expect(hud.is_visible_in_tree(), "the HUD shows")
	await _walk_drop_out()
	await seconds(0.5)
	await shot("02_play_pad")
	await key(KEY_F, true)
	await wait_for(func() -> bool: return _hero_action(local_hero()) == EnumAction.ATTACK, 2.0,
		"F, bound to attack in the settings, attacks")
	await key(KEY_F, false)
	set_setting(&"bindings", {})
	set_setting(&"hints", setting_value(&"Hints", &"ALWAYS"))
	var hints: Control = find(hud, ^"Heroes/HeroPlate/Row/Info/Hints") as Control
	expect(hints.is_visible_in_tree(), "the hero's plate shows its hints")
	var attack_glyph: Label = find(hints, ^"Attack/GlyphBox/Glyphs") as Label
	expect(attack_glyph.text == _glyph(&"attack", "KEYBOARD"), "F last: the keyboard's glyphs")
	await frames(2)
	await shot("02_play_keyboard")
	await pad_button(JOY_BUTTON_Y)
	expect(attack_glyph.text == _glyph(&"attack", "XBOX"), "a pad turns them to its glyphs")
	set_setting(&"hints", setting_value(&"Hints", &"NEVER"))
	await frames(1)
	expect(not hints.visible, "Off hides them")
	set_setting(&"hints", setting_value(&"Hints", &"BRIEFLY"))
	await press_key(KEY_F)
	await frames(2)
	expect(hints.visible, "Briefly: a change of device shows them again")
	set_setting(&"hints", setting_value(&"Hints", &"ALWAYS"))  # the couch's glyph checks read them
	step("in the crypt: F attacks, the hints follow, tick %d" % session.tick)
	await _walk_single_pause()
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


## A key held while a guest leaves and let go while the first player plays with every device must not keep the hero
## walking once a guest is back (unified forgets what a local player held when its device changes).
func _walk_stuck_key() -> void:
	await press_key(KEY_D)
	await _join(1)
	await key(KEY_D, true)
	await seconds(0.2)
	await _leave_guests()
	await key(KEY_D, false)
	await _join(1)
	await seconds(0.3)
	# The local hero read at each moment, never kept across a wait: the join may replace its view meanwhile.
	var from: Vector3 = local_hero().global_position
	await seconds(0.5)
	var moved: float = local_hero().global_position.distance_to(from)
	expect(moved < STILL, "no key held: the hero stands (it moved %.2f m)" % moved)
	await _leave_guests()
	step("a key let go while the guest was away walks nobody")


## A setting applies the moment it is set: Show FPS shows the frame rate in the corner, and hides it again.
func _walk_setting() -> void:
	var fps: Control = find(game, ^"Overlays/Fps") as Control
	set_setting(&"show_fps", true)
	expect(fps.visible, "Show FPS shows the frame rate")
	set_setting(&"show_fps", false)
	expect(not fps.visible, "and hides it")
	step("a setting applies at once")


## Leaving from the pause menu, once a surge saved the crypt, ends the session; the menu follows once it said goodbye,
## Continue focused, the toasts gone.
func _walk_leave() -> void:
	await _walk_save_and_leave()
	expect(session.status == UnifiedSession.STATUS_LEFT, "the session left")
	expect(overlay("Toasts").get_child_count() == 0, "the toasts are gone with the game")
	step("left to the title")


## A second game continues the first (New game asks first; Continue through hero select on the keyboard); back on the
## title, a settings file and a save that didn't read are told once each, the save's when the settings' closes.
func _walk_new_game_again() -> void:
	await _walk_continue()
	if failed():
		return
	root.get_node(^"Settings").set(&"read_problem", "Expected key, line 1")
	var saves: RefCounted = game.get(&"saves")
	saves.set(&"problem", "it is version 9, this game reads version 1")
	game.call(&"leave")
	await wait_for_scene("Menu", 5.0)
	var dialog: Control = overlay("Dialog")
	await wait_for(func() -> bool: return dialog.visible, 2.0, "the title says the settings didn't read")
	var heading: String = (find(dialog, ^"%Heading") as Label).text
	var text: String = (find(dialog, ^"%Text") as Label).text
	expect(heading == "Your settings didn't read", "the dialog's heading: %s" % heading)
	expect(text.contains(OS.get_user_data_dir()), "it names the folder the file is kept in: %s" % text)
	await shot("06_settings_problem")
	await press_key(KEY_ESCAPE)
	var problem: String = setting(&"read_problem")
	expect(problem == "", "told once: the problem is cleared")
	await wait_for(func() -> bool: return dialog.visible, 2.0, "then the save's problem, as the first closes")
	heading = (find(dialog, ^"%Heading") as Label).text
	expect(heading == "Your save can't continue", "the second dialog's heading: %s" % heading)
	await press_key(KEY_ESCAPE)
	expect(not dialog.visible, "told once too")
	expect(root.gui_get_focus_owner() == title_focus(), "the title's first control has the focus")
	step("left again: a settings file and a save that didn't read, each told once")


## A join that waits shows the Connecting overlay over the title, Cancel focused; Esc cancels it: the overlay goes
## and the flow is back on the menu at once (the session says goodbye under the title, which says nothing of it). Its
## Cancel button does the same, with its sound.
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
	expect(not connecting.visible and flow_name() == "MENU", "Esc hides the overlay and leaves the start at once")
	await wait_for(func() -> bool: return session.status == UnifiedSession.STATUS_LEFT, 5.0,
		"the join says goodbye under the title")
	expect(not overlay("Dialog").visible, "its goodbye is no news: no dialog")
	expect(root.gui_get_focus_owner() == title_focus(), "the title's first control has the focus")
	step("a join that waits: the overlay, Esc cancels")
	session.join_direct("127.0.0.1:%d" % SILENT_PORT)
	await wait_for(func() -> bool: return connecting.visible, 3.0, "the Connecting overlay, again")
	var mark: int = sounds.size()
	await click(cancel)
	expect(not connecting.visible and played(&"press", mark) == 1, "Cancel sounds and hides the overlay")
	await wait_for(func() -> bool: return flow_name() == "MENU", 5.0, "back on the title")
	step("Cancel cancels")


## A join that fails at once (an address no network has): one dialog saying why as a sentence, one error sound and no
## focus sound; pad B closes it and the focus is back on the title's first control. Again, the same (OK pressed with
## pad A). Its look is 25_join_failed's (TogetherWalk).
func _walk_failed_join() -> void:
	var dialog: Control = overlay("Dialog")
	var ok: Control = find(dialog, ^"%Ok") as Control
	for attempt: int in 2:
		var mark: int = sounds.size()
		session.join_direct(NOWHERE)  # fails at once, online play set up here or not
		await wait_for(func() -> bool: return dialog.visible, 10.0, "the dialog says why the join failed")
		if failed():
			return
		await frames(3)
		var heading: String = (find(dialog, ^"%Heading") as Label).text
		var text: String = (find(dialog, ^"%Text") as Label).text
		expect(heading == "Couldn't join the game", "the dialog's heading: %s" % heading)
		expect(text != "" and text.ends_with("."), "the dialog's reason, a sentence: %s" % text)
		expect(played(&"error", mark) == 1 and played(&"select", mark) == 0,
			"one error sound and no other (%s)" % [sounds.slice(mark)])
		expect(root.gui_get_focus_owner() == ok, "OK has the focus")
		if attempt == 0:
			await pad_button(JOY_BUTTON_B)
		else:
			mark = sounds.size()
			await pad_button(JOY_BUTTON_A)
			expect(played(&"press", mark) == 1, "OK sounds")
		expect(not dialog.visible, "the dialog closes")
		expect(root.gui_get_focus_owner() == title_focus(), "the focus is back on the title's first control")
		step("a join that fails at once (%d): %s" % [attempt + 1, text])
