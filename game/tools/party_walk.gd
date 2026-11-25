class_name PartyWalk
extends MenuTool
## The walk's parts about who plays (game/tools/ui_walk.gd extends this and runs them in its order): the player's name
## field, hero select on pads and on the keyboard and mouse, the party in the crypt, a guest dropping out, and the
## couch's join cards. Each part starts and ends where the walk's order puts it, and uses each pad's own events.

## How far a hero may drift standing still (metres): its capsule settling.
const STILL: float = 0.1
## The name the walk gives the player: long enough to wrap on a seat card.
const WALK_NAME: String = "Sexton of the Old Crypt"


## The name field on the Gameplay tab, the focus on it already (the tab's first control): the focus doesn't start
## editing, so Down, Up, Q and E move on; Enter edits, typed characters (unicode, not only Latin) go in, Enter applies
## it (the session's name follows), Esc puts the setting back; a name too long for the other players is cut and shown
## cut. It leaves the name WALK_NAME and the Gameplay tab shown.
func _walk_name_field(screen: Control) -> void:
	var tabs: TabContainer = find(screen, ^"%Tabs") as TabContainer
	var field: LineEdit = find(tabs, ^"Gameplay/Margin/Rows/PlayerName/Row/Field") as LineEdit
	await frames(2)
	expect(root.gui_get_focus_owner() == field and not field.is_editing(),
		"the focus on the name field doesn't start editing")
	await press_key(KEY_DOWN)
	expect(root.gui_get_focus_owner() != field, "Down moves on past the field")
	await press_key(KEY_UP)
	expect(root.gui_get_focus_owner() == field, "Up comes back to it")
	await press_key(KEY_Q)
	expect(tabs.get_current_tab_control().name == "Controls", "Q steps the tab from the field")
	await press_key(KEY_E)
	expect(root.gui_get_focus_owner() == field and not field.is_editing(), "E steps back to it, not editing")
	await _type_name(field, "Ясень Bell")
	await press_key(KEY_ENTER)
	var applied: String = setting(&"player_name")
	expect(not field.is_editing() and applied == "Ясень Bell", "Enter applies the name: %s" % applied)
	expect(session.local_name == applied, "the session's name follows: %s" % session.local_name)
	await _type_name(field, "Nobody")
	await press_key(KEY_ESCAPE)
	expect(field.text == "Ясень Bell" and not field.is_editing(), "Esc puts the name back: %s" % field.text)
	expect(top_screen() == screen, "and the settings stay open")
	await _type_name(field, "Я".repeat(20))
	await press_key(KEY_ENTER)
	var cut: String = setting(&"player_name")
	expect(cut == "Я".repeat(15) and field.text == cut,
		"a name too long for the other players is cut to %d bytes, and shown cut: %s" % [cut.to_utf8_buffer().size(),
		field.text])
	await _type_name(field, WALK_NAME)
	await press_key(KEY_ENTER)
	step("the name field: %s" % setting(&"player_name"))


## Starts editing `field` with Enter and types `text` over what it held.
func _type_name(field: LineEdit, text: String) -> void:
	await press_key(KEY_ENTER)
	expect(field.is_editing(), "Enter starts editing the name")
	field.select_all()  # as a double-click would: the typing replaces it
	await type_text(text)


## Hero select on pads, from the title with New game focused, to the crypt. An unseated keyboard's Esc and the first
## seat's B go back to the title; pads sit with Start and A (with their sound), and the keyboard can't sit beside a
## pad; the first seat's pad disconnecting passes the seat to the next, a guest's frees it; d-pads and sticks step
## their own seat's pick (a stick once per push); Start is off while a seat chooses; B takes a ready back and then
## gives a seat up; the seats fit at 130 %; pad 0's A starts (with its sound): pad 0's Knight first, pad 1's Any as
## the class nobody picked (the Barbarian), the party's arrival no toast, the picks remembered by place.
func _walk_hero_select() -> void:
	var mark: int = sounds.size()
	await pad_button(JOY_BUTTON_A, 3)
	expect(played(&"confirm", mark) == 1, "New game sounds its confirmation")
	var screen: Control = _hero_select()
	if failed():
		return
	expect(_seat_of(screen, 3) == 0, "pad 3, which came here, has the first seat")
	await press_key(KEY_ENTER)
	expect(_seat_of(screen, UnifiedSession.DEVICE_KEYBOARD) < 0, "the keyboard sits only in the first seat")
	await press_key(KEY_ESCAPE)
	expect(top_screen() == title(), "an unseated keyboard's Esc goes back to the title")
	await pad_button(JOY_BUTTON_A, 3)
	screen = _hero_select()
	await pad_button(JOY_BUTTON_B, 3)
	expect(top_screen() == title(), "the first seat's B goes back to the title")
	await pad_button(JOY_BUTTON_A, 3)
	screen = _hero_select()
	if failed():
		return
	mark = sounds.size()
	await pad_button(JOY_BUTTON_START, 0)
	expect(_seat_of(screen, 0) == 1 and played(&"joined", mark) == 1, "pad 0's Start seats it second, with a sound")
	expect(_who(screen, 1) == "Guest 2", "the second seat is Guest 2: %s" % _who(screen, 1))
	Input.joy_connection_changed.emit(3, false)
	await frames(2)
	expect(_seat_of(screen, 0) == 0 and _seat_of(screen, 3) < 0,
		"pad 3 gone: the first seat passes to pad 0, the next taken seat")
	expect(_who(screen, 0) == WALK_NAME, "the first seat has the player's name: %s" % _who(screen, 0))
	await pad_button(JOY_BUTTON_A, 1)
	await pad_button(JOY_BUTTON_START, 2)
	await pad_button(JOY_BUTTON_START, 3)
	expect(_seat_of(screen, 1) == 1 and _seat_of(screen, 2) == 2 and _seat_of(screen, 3) == 3,
		"pads 1, 2 and 3 take the next free seats")
	Input.joy_connection_changed.emit(3, false)
	await frames(2)
	expect(_seat_of(screen, 3) < 0, "pad 3 gone: its seat is free again")
	mark = sounds.size()
	await _pick(screen, 0, EnumClass.KNIGHT)
	expect(played(&"select", mark) >= 1, "a step sounds")
	expect(_card_pick(screen, 1) == EnumClass.ANY, "each seat steps its own pick: pad 1's is still Any")
	var before: int = _card_pick(screen, 2)
	await pad_axis(JOY_AXIS_LEFT_X, 0.8, 2)
	await pad_axis(JOY_AXIS_LEFT_X, 1.0, 2)
	expect(_card_pick(screen, 2) == _after(before, 1), "a stick pushed and held steps once")
	await pad_axis(JOY_AXIS_LEFT_X, 0.0, 2)
	await pad_axis(JOY_AXIS_LEFT_X, -1.0, 2)
	expect(_card_pick(screen, 2) == before, "pushed again, the other way: one step back")
	await pad_axis(JOY_AXIS_LEFT_X, 0.0, 2)
	await frames(10)
	await shot("07_hero_select_pads")
	var start: Button = find(screen, ^"%Start") as Button
	expect(start.disabled, "Start is off while a seat chooses")
	await pad_button(JOY_BUTTON_A, 0)
	expect(_state(screen, 0) == "READY", "A readies the first seat")
	await pad_button(JOY_BUTTON_B, 0)
	expect(_state(screen, 0) == "CHOOSING", "B takes the ready back")
	mark = sounds.size()
	await pad_button(JOY_BUTTON_B, 2)
	expect(_seat_of(screen, 2) < 0 and played(&"left", mark) == 1, "B again gives a seat up, with a sound")
	await pad_button(JOY_BUTTON_A, 0)
	await pad_button(JOY_BUTTON_A, 1)
	expect(not start.disabled, "every taken seat ready: Start is on")
	await frames(10)
	await shot("08_hero_select_ready")
	await _walk_hero_select_fits(screen)
	step("hero select: seats on pads, ready")
	mark = sounds.size()
	await pad_button(JOY_BUTTON_A, 0)
	expect(played(&"confirm", mark) == 1, "the first seat's A starts, with its sound")
	await wait_for_scene("Play", 5.0)
	await wait_for(func() -> bool: return local_hero() != null and _in_session(1), 8.0,
		"the first player and pad 1's guest in the crypt")
	if failed():
		return
	expect(session.get_local_device(0) == 0, "with a guest in, the first player plays on pad 0")
	expect(Heroes.class_of(session.local_player) == EnumClass.KNIGHT, "the first player is the Knight it picked")
	var guest_class: int = Heroes.class_of(session.get_local_player_key(_local_of(1)))
	expect(guest_class == EnumClass.BARBARIAN, "pad 1's Any is the first class nobody picked: %s"
		% Heroes.name_of(guest_class))
	await seconds(0.5)
	expect(overlay("Toasts").get_child_count() == 0, "the party's own arrival is no news: no toast")
	var picks: Array = setting(&"hero_picks")
	expect(picks == [EnumClass.KNIGHT, EnumClass.ANY, EnumClass.ANY, EnumClass.ANY],
		"the picks remembered by place, Any as Any: %s" % [picks])
	step("the party in the crypt: a Knight and a Barbarian")


## The seats at 130 % interface size: inside the view, clear of the banner and the buttons.
func _walk_hero_select_fits(screen: Control) -> void:
	set_setting(&"ui_scale", 1.3)
	await frames(4)
	var seats: Rect2 = (find(screen, ^"%Seats") as Control).get_global_rect()
	var view: Rect2 = screen.get_global_rect()
	var start: Rect2 = (find(screen, ^"%Start") as Control).get_global_rect()
	expect(view.encloses(seats) and seats.end.y <= start.position.y,
		"at 130 %% the seats fit: %s in %s, above Start at %s" % [seats, view, start.position.y])
	await shot("14b_hero_select_130")
	set_setting(&"ui_scale", 1.0)
	await frames(2)


## Hero select on the keyboard and mouse, from the title's `button` (Continue, for a second game): a click on Back goes
## back to the title; a click on the button seats the keyboard first, its last pick (the Knight) preselected; the
## mouse's arrows step it, its action line readies it, and a click on Start starts the game.
func _walk_hero_select_keyboard(button: String) -> void:
	await click(title_control(button))
	var screen: Control = _hero_select()
	await click(find(screen, ^"%Back") as Control)
	expect(top_screen() == title(), "a click on Back goes back to the title")
	await click(title_control(button))
	screen = _hero_select()
	if button == "Continue":
		var heading: String = (find(screen, ^"%Heading") as Label).text
		expect(heading == "Continue your crypt", "hero select says it continues: %s" % heading)
	if failed():
		return
	expect(_seat_of(screen, UnifiedSession.DEVICE_KEYBOARD) == 0, "the mouse's click: the keyboard's seat first")
	expect(_card_pick(screen, 0) == EnumClass.KNIGHT, "its place's last pick preselected: the Knight")
	var card: Control = screen.call(&"card", 0)
	await click(find(card, ^"%Next") as Control)
	expect(_card_pick(screen, 0) == EnumClass.BARBARIAN, "the mouse's arrow steps the pick")
	await click(find(card, ^"%Previous") as Control)
	expect(_card_pick(screen, 0) == EnumClass.KNIGHT, "and back")
	await seconds(0.7)  # the backdrop's camera has come round to the crew
	await shot("07b_hero_select_keyboard")
	await click(find(card, ^"%Act") as Control)
	expect(_state(screen, 0) == "READY", "a click on [Enter] Ready readies the seat")
	var mark: int = sounds.size()
	await click(find(screen, ^"%Start") as Control)
	expect(played(&"confirm", mark) == 1, "a click on Start starts, with its sound")
	step("hero select on the keyboard and mouse")


## The guest drops out: holding its stick, pad 1's Back opens its drop card, and letting the stick go reaches the
## session (its hero stops); its Start doesn't drop it (it opens the pause menu, as a playing pad's Start does) and its
## B keeps it in; Back and A drop it out, and it is gone by itself (a toast names it and its hero).
func _walk_drop_out() -> void:
	var guest: int = session.get_local_player_key(_local_of(1))
	await pad_axis(JOY_AXIS_LEFT_X, 1.0, 1)
	await seconds(0.2)
	await pad_button(JOY_BUTTON_BACK, 1)
	expect(_card(1) != null, "pad 1's Back opens its drop card")
	await pad_axis(JOY_AXIS_LEFT_X, 0.0, 1)
	var hero: Node3D = session.get_player_view(EnumView.HERO, guest) as Node3D
	var moved: float = INF
	for i: int in 8:  # it slows to a stop over a few ticks: however slow the frames, it must stand within 2.4 s
		var from: Vector3 = hero.global_position
		await seconds(0.3)
		moved = hero.global_position.distance_to(from)
		if moved < STILL:
			break
	expect(moved < STILL, "the stick let go with the card open: the guest's hero stops (moved %.2f m)" % moved)
	await shot("09_drop_out")
	await pad_button(JOY_BUTTON_START, 1)
	expect(_card(1) != null and _in_session(1), "Start doesn't drop out")
	await wait_for(func() -> bool: return session.paused, 2.0, "a playing pad's Start opens the pause menu: it pauses")
	await pad_button(JOY_BUTTON_START, 1)
	await wait_for(func() -> bool: return not session.paused, 2.0, "and its Start again resumes")
	await pad_button(JOY_BUTTON_B, 1)
	expect(_card(1) == null and _in_session(1), "B on the drop card: the guest stays")
	await pad_button(JOY_BUTTON_BACK, 1)
	await pad_button(JOY_BUTTON_A, 1)
	expect(session.get_local_indices().size() == 1, "A drops the guest out")
	await wait_for(func() -> bool: return session.get_local_device(0) == UnifiedSession.DEVICE_ANY, 2.0,
		"alone again, the first player plays with every device")
	await wait_for(func() -> bool: return _toast_shows("Guest 2 left (Barbarian)"), 5.0,
		"a toast: Guest 2 left (Barbarian)")
	step("the guest dropped out")


## The couch: a join card steps once per stick push and gives up with B (the first player free again); a pad picks on
## it and joins (a toast; the first player fixed to the keyboard; the guest's plate in its pad's glyphs); with pad 0
## last, pad 0's Start pauses and pad 1's joins; two cards at once; a pad that disconnects while picking gives up; a
## guest dropped and a new one joining takes its name (no two of a name); a full couch shows no card and says so.
func _walk_couch() -> void:
	expect(session.get_local_device(0) == UnifiedSession.DEVICE_ANY, "alone, the first player plays with every device")
	await press_key(KEY_D)  # the keyboard played last
	await pad_button(JOY_BUTTON_START, 1)
	var card: Control = _card(1)
	expect(card != null, "pad 1's Start opens its join card")
	if failed():
		return
	var remembered: Array = setting(&"hero_picks")
	var place_pick: int = remembered[1]
	expect(_pick_of(card) == place_pick, "its pick: the one remembered for the place it would take")
	var first: int = _pick_of(card)
	await pad_axis(JOY_AXIS_LEFT_X, 0.8, 1)
	await pad_axis(JOY_AXIS_LEFT_X, 1.0, 1)
	expect(_pick_of(card) == _after(first, 1), "a stick held steps the card once")
	await pad_axis(JOY_AXIS_LEFT_X, 0.0, 1)
	for i: int in Heroes.choices().size():
		if _pick_of(card) != EnumClass.ROGUE:
			await pad_button(JOY_BUTTON_DPAD_RIGHT, 1)
	expect(_pick_of(card) == EnumClass.ROGUE, "pad 1 steps its card to the Rogue")
	await frames(5)
	await shot("03a_join_card")
	await pad_button(JOY_BUTTON_B, 1)
	expect(_card(1) == null and not _in_session(1), "B gives the join up")
	await wait_for(func() -> bool: return session.get_local_device(0) == UnifiedSession.DEVICE_ANY, 2.0,
		"the first player has every device again")
	await pad_button(JOY_BUTTON_START, 1)
	for i: int in Heroes.choices().size():
		if _pick_of(_card(1)) != EnumClass.ROGUE:
			await pad_button(JOY_BUTTON_DPAD_RIGHT, 1)
	await pad_button(JOY_BUTTON_A, 1)
	await wait_for(func() -> bool: return _in_session(1), 3.0, "pad 1's A joins it")
	await wait_for(func() -> bool: return _toast_shows("Guest 2 joined (Rogue)"), 5.0, "a toast: Guest 2 joined (Rogue)")
	expect(session.get_local_device(0) == UnifiedSession.DEVICE_KEYBOARD,
		"with a guest in, the first player keeps the keyboard")
	await seconds(0.4)  # the toast faded in
	var guest_attack: Label = find(current_scene,
		^"Hud/Heroes/HeroPlate2/Row/Info/Hints/Attack/GlyphBox/Glyphs") as Label
	expect(guest_attack != null and guest_attack.text == _glyph(&"attack", "XBOX"),
		"the guest's plate: its pad's glyphs")
	await shot("03_guest_joined")
	await _leave_guests()
	await wait_for(func() -> bool: return _toast_shows("Guest 2 left (Rogue)"), 5.0, "a toast: Guest 2 left (Rogue)")
	await pad_button(JOY_BUTTON_A, 0)  # pad 0 played last
	await pad_button(JOY_BUTTON_START, 0)
	await wait_for(func() -> bool: return session.paused, 2.0, "pad 0's Start pauses: it is the first player's")
	await pad_button(JOY_BUTTON_START, 0)
	await wait_for(func() -> bool: return not session.paused, 2.0, "and resumes")
	await _join(1)
	expect(session.get_local_device(0) == 0, "with a guest in, the first player keeps pad 0")
	await _leave_guests()
	step("pads join on their cards")
	await _walk_full_couch()


## Two cards at once, a pad gone while picking, names after a drop and a join, and a full couch.
func _walk_full_couch() -> void:
	await press_key(KEY_D)
	await pad_button(JOY_BUTTON_START, 1)
	await pad_button(JOY_BUTTON_START, 2)
	expect(_card(1) != null and _card(2) != null, "two pads, two cards at once")
	await pad_button(JOY_BUTTON_A, 1)
	await pad_button(JOY_BUTTON_A, 2)
	await wait_for(func() -> bool: return _in_session(1) and _in_session(2), 3.0, "both join")
	expect(_name_on(1) == "Guest 2" and _name_on(2) == "Guest 3", "named by place: %s, %s" % [_name_on(1),
		_name_on(2)])
	await shot("03b_three_players")
	await pad_button(JOY_BUTTON_START, 3)
	expect(_card(3) != null, "pad 3's card opens")
	Input.joy_connection_changed.emit(3, false)
	await frames(2)
	expect(_card(3) == null and not _in_session(3), "pad 3 gone while picking: its card closes, it gave up")
	await pad_button(JOY_BUTTON_BACK, 1)
	await pad_button(JOY_BUTTON_A, 1)
	await wait_for(func() -> bool: return not _in_session(1), 3.0, "Guest 2 drops out")
	await _join(3)
	expect(_name_on(3) == "Guest 2" and _name_on(2) == "Guest 3",
		"the next guest takes the free place's name: %s, %s" % [_name_on(3), _name_on(2)])
	await _join(1)
	expect(session.get_local_indices().size() == UnifiedSession.LOCAL_MAX, "the couch is full")
	await frames(2)
	expect(not (find(current_scene, ^"Hud/%JoinHint") as Control).visible, "a full couch: no join hint")
	await pad_button(JOY_BUTTON_START, 4)
	expect(_card(4) == null, "a fifth pad's Start opens no card")
	expect(_toast_shows("The couch is full"), "a toast says why")
	await _leave_guests()
	step("two cards at once, a pad gone, names by place, a full couch")


## Pad `device`'s Start opens its join card; its A joins with the card's pick, and its player is in the session (it
## has a key).
func _join(device: int) -> void:
	await pad_button(JOY_BUTTON_START, device)
	expect(_card(device) != null, "pad %d's Start opens its join card" % device)
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


## The name the session knows the player on pad `device` by.
func _name_on(device: int) -> String:
	return session.get_player_name(session.get_local_player_key(_local_of(device)))


func _leave_guests() -> void:
	for local: int in session.get_local_indices():
		if local > 0:
			session.remove_local_player(local)
	await wait_for(func() -> bool: return session.get_local_indices().size() == 1, 3.0, "the guests gone")
	await wait_for(func() -> bool: return session.get_local_device(0) == UnifiedSession.DEVICE_ANY, 2.0,
		"alone again, the first player plays with every device")


## Hero select, on top of the menu (null, failing the run, when it isn't).
func _hero_select() -> Control:
	var screen: Control = top_screen()
	expect(screen != null and screen.name == "HeroSelect", "hero select is open")
	return screen


## Steps pad `device`'s seat to `hero_class` with its d-pad.
func _pick(screen: Control, device: int, hero_class: int) -> void:
	var seat: int = _seat_of(screen, device)
	for i: int in Heroes.choices().size():
		if _card_pick(screen, seat) == hero_class:
			return
		await pad_button(JOY_BUTTON_DPAD_RIGHT, device)
	expect(_card_pick(screen, seat) == hero_class, "pad %d picks %s" % [device, Heroes.name_of(hero_class)])


func _seat_of(screen: Control, device: int) -> int:
	var seat: int = screen.call(&"seat_of", device)
	return seat


func _card_pick(screen: Control, seat: int) -> int:
	var card: Control = screen.call(&"card", seat)
	return _pick_of(card)


## A seat card's pick (EnumClass).
func _pick_of(card: Control) -> int:
	var pick: int = card.get(&"pick")
	return pick


## Seat `seat`'s card's state, by its name in SeatCard.State (the card's class is reached untyped: a tool script
## compiles before the autoloads its widgets use exist).
func _state(screen: Control, seat: int) -> String:
	var card: Control = screen.call(&"card", seat)
	var script: Script = card.get_script()
	var states: Dictionary = script.get_script_constant_map()["State"]
	var state: int = card.get(&"state")
	return str(states.find_key(state))


## The name seat `seat`'s card shows.
func _who(screen: Control, seat: int) -> String:
	var card: Control = screen.call(&"card", seat)
	return (find(card, ^"%Who") as Label).text


## The HUD's card for pad `device` (null: none open).
func _card(device: int) -> Control:
	var card: Control = find(current_scene, ^"Hud/%JoinCards").call(&"card_of", device)
	return card


## The pick `by` steps after `pick`, as a card steps them.
static func _after(pick: int, by: int) -> int:
	var choices: Array[int] = Heroes.choices()
	return choices[posmod(choices.find(pick) + by, choices.size())]


## The glyph `action` shows in family `family_name` (Prompts.Family's member).
func _glyph(action: StringName, family_name: String) -> String:
	var prompts: Node = root.get_node(^"Prompts")
	var script: Script = prompts.get_script()
	var families: Dictionary = script.get_script_constant_map()["Family"]
	var family: int = families[family_name]
	var glyphs: String = prompts.call(&"glyphs", Array([action], TYPE_STRING_NAME, &"", null), family)
	return glyphs


func _toast_shows(text: String) -> bool:
	for toast: Node in overlay("Toasts").get_children():
		if (toast.get_node(^"%Text") as Label).text == text:
			return true
	return false
