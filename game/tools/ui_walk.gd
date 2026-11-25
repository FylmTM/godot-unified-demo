extends MenuTool
## A walk through Crypt Crew's app with real input events (keys, pad buttons and sticks of several pads, the mouse),
## the godot suite's `walk` step (`./uni tool ui_walk`; with `--window --shots` it saves a PNG at each moment worth
## looking at, into .out/shots/ui_walk/). In order:
##   - the title: New game focused; the mouse over a button takes the focus and sounds; a screen that enters the tree
##     again is wired once; the d-pad moves the focus; the prompts' device flips (a stick's noise and a mouse's nudge
##     don't flip it, a trigger and a real move do);
##   - the settings: every tab on the keyboard's prompts (E and Q) and on a pad's (the shoulders, the d-pad through
##     every row, the focus never lost); a choice applies; the panel fits at 130 % interface size; rebinding on both
##     schemes (a key, a swap, a click outside cancelling, Esc and a reserved key, a mouse button and a trigger in the
##     second slot, a pad button, a refused clear, the prompt bar's Cancel and Clear, the resets); attack left on F;
##   - pad A on New game: the crypt, F attacks, the hints follow the device, Esc pauses and resumes, the reconnecting
##     plate takes nothing;
##   - the couch: pads join with Start (keyboard last: pad 1 joins; pad 0 last: its Start pauses and pad 1 joins;
##     the keyboard and two pads), with the toasts and the guests' own glyphs; a key held while a guest leaves and
##     released while the first player is free walks nobody once the guest is back;
##   - leave, the title (toasts gone; a settings file that didn't read is told once), a second game, a join that waits
##     (the Connecting overlay; Esc and Cancel cancel it at once), a join that fails at once (one dialog, one error
##     sound, the reason as a sentence; pad B and pad A close it); the run ends through Game.quit_app.
## That the app adopts a session its menus didn't start is coop.gd's: both its processes start from uni's flags.

## A local port nothing listens on: a join to it waits until cancelled.
const SILENT_PORT: int = 9
## How far a hero may drift standing still in the stuck-key check (metres): its capsule settling.
const STILL: float = 0.1


func _run() -> void:
	record_sounds()
	change_scene_to_file(str(ProjectSettings.get_setting("application/run/main_scene")))
	await wait_for_scene("Menu", 5.0)
	await frames(10)
	expect(flow_name() == "MENU", "the app starts on the menu (flow %s)" % flow_name())
	expect(root.gui_get_focus_owner() == title_control("NewGame"), "New game has the focus")
	await shot("01_title")
	step("the title")
	for walk: Callable in [_walk_title_wiring, _walk_pad, _walk_prompt_device, _walk_settings, _walk_new_game,
			_walk_couch, _walk_stuck_key, _walk_setting, _walk_leave, _walk_new_game_again, _walk_connecting,
			_walk_failed_join]:
		if failed():
			return
		await walk.call()


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
	expect(root.gui_get_focus_owner() == title_control("Settings"), "the d-pad moves the focus to Settings")
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
	step("back to the title")


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
	set_setting(&"ui_scale", 1.0)
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


## Hero select: pad A on New game opens it with pad 0 in the first seat; Enter seats the keyboard and pad 1's Start
## the third; each steps its own pick; the keyboard gives its seat up; both pads ready, and pad 0's A starts the game
## with them: the first player a Knight on pad 0, pad 1's guest a Mage.
func _walk_hero_select() -> void:
	await pad_button(JOY_BUTTON_A)
	var screen: Control = top_screen()
	expect(screen != null and screen.name == "HeroSelect", "New game opens hero select")
	if failed():
		return
	expect(_seat_of(screen, 0) == 0, "pad 0, which came here, has the first seat")
	await press_key(KEY_ENTER)
	expect(_seat_of(screen, UnifiedSession.DEVICE_KEYBOARD) == 1, "Enter seats the keyboard next")
	await pad_button(JOY_BUTTON_START, 1)
	expect(_seat_of(screen, 1) == 2, "pad 1's Start seats it third")
	for device: int in [0, 1]:
		await _pick(screen, device, EnumClass.KNIGHT if device == 0 else EnumClass.MAGE)
	await press_key(KEY_RIGHT)
	expect(_card_pick(screen, 1) == EnumClass.KNIGHT, "each seat steps its own pick: the keyboard's too")
	await frames(10)
	await shot("07_hero_select_three")
	await press_key(KEY_ESCAPE)
	expect(_seat_of(screen, UnifiedSession.DEVICE_KEYBOARD) < 0, "Esc gives the keyboard's seat up")
	await pad_button(JOY_BUTTON_A, 0)
	await pad_button(JOY_BUTTON_A, 1)
	await frames(10)
	await shot("08_hero_select_ready")
	step("hero select: three seats, two ready")
	await pad_button(JOY_BUTTON_A, 0)
	await wait_for_scene("Play", 5.0)
	await wait_for(func() -> bool: return local_hero() != null and _in_session(1), 8.0,
		"the first player and pad 1's guest in the crypt")
	if failed():
		return
	expect(session.get_local_device(0) == 0, "with a guest in, the first player plays on pad 0")
	expect(Heroes.class_of(session.local_player) == EnumClass.KNIGHT, "the first player is the Knight it picked")
	expect(Heroes.class_of(session.get_local_player_key(_local_of(1))) == EnumClass.MAGE, "pad 1's guest is the Mage")
	var picks: Array = setting(&"hero_picks")
	var first_pick: int = picks[0]
	expect(first_pick == EnumClass.KNIGHT, "the first seat's pick is remembered: %s" % [picks])
	step("the party in the crypt: a Knight and a Mage")


## Steps pad `device`'s seat to `hero_class` with its d-pad.
func _pick(screen: Control, device: int, hero_class: int) -> void:
	var seat: int = _seat_of(screen, device)
	for i: int in 5:
		if _card_pick(screen, seat) == hero_class:
			return
		await pad_button(JOY_BUTTON_DPAD_RIGHT, device)
	expect(_card_pick(screen, seat) == hero_class, "pad %d picks %s" % [device, EnumClass.name(hero_class)])


func _seat_of(screen: Control, device: int) -> int:
	var seat: int = screen.call(&"seat_of", device)
	return seat


func _card_pick(screen: Control, seat: int) -> int:
	var card: Node = screen.call(&"card", seat)
	var pick: int = card.get(&"pick")
	return pick



## The guest drops out: pad 1's Back opens its card, A confirms; the first player plays with every device again.
func _walk_drop_out() -> void:
	await pad_button(JOY_BUTTON_BACK, 1)
	var cards: Node = find(current_scene, ^"Hud/%JoinCards")
	var card: Node = cards.call(&"card_of", 1)
	expect(card != null, "pad 1's Back opens its drop-out card")
	await frames(5)
	await shot("09_drop_out")
	await pad_button(JOY_BUTTON_A, 1)
	await _leave_guests()
	await wait_for(func() -> bool: return _toast_starts("Guest 2 left"), 5.0, "a toast: Guest 2 left")
	step("the guest dropped out")


## Pad A on New game: the app goes to the crypt once the session is up, the local hero arrives with the HUD over it,
## F (bound in the settings) attacks, the hints follow the device, and Esc pauses and resumes the game.
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
	var hints: Control = find(hud, ^"Heroes/HeroPlate/Row/Info/Hints") as Control
	expect(hints.is_visible_in_tree(), "the hero's plate shows its hints")
	var attack_glyph: Label = find(hints, ^"Attack/GlyphBox/Glyphs") as Label
	expect(attack_glyph.text == _glyph(&"attack", "KEYBOARD"), "F last: the keyboard's glyphs")
	await frames(2)
	await shot("02_play_keyboard")
	await pad_button(JOY_BUTTON_Y)
	expect(attack_glyph.text == _glyph(&"attack", "XBOX"), "a pad turns them to its glyphs")
	set_setting(&"show_hints", false)
	expect(not hints.visible, "the hints setting hides them")
	set_setting(&"show_hints", true)
	step("in the crypt: F attacks, the hints follow, tick %d" % session.tick)
	await press_key(KEY_ESCAPE)
	await wait_for(func() -> bool: return Unified.data.hud.paused, 2.0, "Esc pauses the game")
	expect((find(hud, ^"%Paused") as Control).visible, "the HUD's banner says so")
	await shot("02b_paused")
	await press_key(KEY_ESCAPE)
	await wait_for(func() -> bool: return not Unified.data.hud.paused, 2.0, "Esc again resumes it")
	step("Esc paused and resumed")
	await _walk_link_status()


## The glyph `action` shows in family `family_name` (Prompts.Family's member).
func _glyph(action: StringName, family_name: String) -> String:
	var prompts: Node = root.get_node(^"Prompts")
	var script: Script = prompts.get_script()
	var families: Dictionary = script.get_script_constant_map()["Family"]
	var family: int = families[family_name]
	var glyphs: String = prompts.call(&"glyphs", Array([action], TYPE_STRING_NAME, &"", null), family)
	return glyphs


## The action a hero view shows (EnumAction; NONE without a view).
func _hero_action(view: Node3D) -> int:
	if view == null:
		return EnumAction.NONE
	var data: ViewHero = view.get(&"data")
	return data.action if data != null else EnumAction.NONE


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


## Pads join with Start: with the keyboard last, pad 1 joins (a toast; the first player fixed to the keyboard; the
## guest's plate in its pad's glyphs); with pad 0 last, pad 0's Start pauses and pad 1's joins; the keyboard and two
## pads at once.
func _walk_couch() -> void:
	expect(session.get_local_device(0) == UnifiedSession.DEVICE_ANY, "alone, the first player plays with every device")
	await press_key(KEY_D)  # the keyboard played last
	await pad_button(JOY_BUTTON_START, 1)
	var card: Node = find(current_scene, ^"Hud/%JoinCards").call(&"card_of", 1)
	expect(card != null, "pad 1's Start opens its join card")
	for i: int in 4:
		if _pick_of(card) != EnumClass.ROGUE:
			await pad_button(JOY_BUTTON_DPAD_RIGHT, 1)
	expect(_pick_of(card) == EnumClass.ROGUE, "pad 1 steps its card to the Rogue")
	await frames(5)
	await shot("03a_join_card")
	await pad_button(JOY_BUTTON_A, 1)
	await wait_for(func() -> bool: return _in_session(1), 3.0, "pad 1's A joins it")
	await wait_for(func() -> bool: return _toast_shows("Guest 2 joined as the Rogue"), 5.0,
		"a toast: Guest 2 joined as the Rogue")
	expect(session.get_local_device(0) == UnifiedSession.DEVICE_KEYBOARD,
		"with a guest in, the first player keeps the keyboard")
	await seconds(0.4)  # the toast faded in
	var guest_attack: Label = find(current_scene,
		^"Hud/Heroes/HeroPlate2/Row/Info/Hints/Attack/GlyphBox/Glyphs") as Label
	expect(guest_attack != null and guest_attack.text == _glyph(&"attack", "XBOX"),
		"the guest's plate: its pad's glyphs")
	await shot("03_guest_joined")
	await _leave_guests()
	await wait_for(func() -> bool: return _toast_starts("Guest 2 left"), 5.0, "a toast: Guest 2 left")
	await pad_button(JOY_BUTTON_A, 0)  # pad 0 played last
	await pad_button(JOY_BUTTON_START, 0)
	await wait_for(func() -> bool: return Unified.data.hud.paused, 2.0,
		"pad 0's Start pauses: it is the first player's")
	await pad_button(JOY_BUTTON_START, 0)
	await wait_for(func() -> bool: return not Unified.data.hud.paused, 2.0, "and resumes")
	await _join(1)
	expect(session.get_local_device(0) == 0, "with a guest in, the first player keeps pad 0")
	await _leave_guests()
	await press_key(KEY_D)
	await _join(1)
	await _join(2)
	expect(session.get_local_indices().size() == 3, "the keyboard and two pads play")
	await shot("03b_three_players")
	await _leave_guests()
	step("pads join with Start")


## Pad `device`'s Start opens its join card; its A joins with the card's pick, and its player is in the session (it
## has a key).
func _join(device: int) -> void:
	await pad_button(JOY_BUTTON_START, device)
	var card: Node = find(current_scene, ^"Hud/%JoinCards").call(&"card_of", device)
	expect(card != null, "pad %d's Start opens its join card" % device)
	expect(not _in_session(device), "the card first: pad %d isn't in yet" % device)
	await pad_button(JOY_BUTTON_A, device)
	await wait_for(func() -> bool: return _in_session(device), 3.0, "pad %d's A joins it" % device)


## Whether a local player on pad `device` is in the session (it has a key).
func _in_session(device: int) -> bool:
	return _local_of(device) > 0 and session.get_local_player_key(_local_of(device)) != 0


## The local player playing on `device` (-1: none).
func _local_of(device: int) -> int:
	for local: int in session.get_local_indices():
		if session.get_local_device(local) == device:
			return local
	return -1


func _leave_guests() -> void:
	for local: int in session.get_local_indices():
		if local > 0:
			session.remove_local_player(local)
	await wait_for(func() -> bool: return session.get_local_indices().size() == 1, 3.0, "the guests gone")
	await wait_for(func() -> bool: return session.get_local_device(0) == UnifiedSession.DEVICE_ANY, 2.0,
		"alone again, the first player plays with every device")


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
	var hero: Node3D = local_hero()
	await seconds(0.3)
	var from: Vector3 = hero.global_position
	await seconds(0.5)
	var moved: float = hero.global_position.distance_to(from)
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


## A second game after a leave starts like the first; back on the title, a settings file that didn't read is told
## once.
func _walk_new_game_again() -> void:
	await click(title_control("NewGame"))
	await press_key(KEY_ENTER)  # the keyboard's seat: ready
	await press_key(KEY_ENTER)  # and start
	await wait_for_scene("Play", 5.0)
	await wait_for(func() -> bool: return local_hero() != null, 8.0, "the local hero, again")
	if failed():
		return
	step("New game again")
	root.get_node(^"Settings").set(&"read_problem", "Expected key, line 1")
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
	expect(not dialog.visible and problem == "", "told once: the problem is cleared")
	expect(root.gui_get_focus_owner() == title_control("NewGame"), "New game has the focus")
	step("left again: a settings file that didn't read, told once")


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
		if failed():
			return
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


func _pick_of(card: Node) -> int:
	var pick: int = card.get(&"pick")
	return pick


func _toast_starts(text: String) -> bool:
	for toast: Node in overlay("Toasts").get_children():
		if (toast.get_node(^"%Text") as Label).text.begins_with(text):
			return true
	return false


func _toast_shows(text: String) -> bool:
	for toast: Node in overlay("Toasts").get_children():
		if (toast.get_node(^"%Text") as Label).text == text:
			return true
	return false
