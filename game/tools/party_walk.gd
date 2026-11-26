class_name PartyWalk
extends MenuTool
## The walk's parts about who plays (game/tools/ui_walk.gd extends this and runs them in its order): the player's name
## field, hero select on pads and on the keyboard and mouse, the party in the crypt, a guest dropping out, the couch's
## join cards, and a guest downed and revived. Each part starts and ends where the walk's order puts it, and uses each
## pad's own events.

## How far a hero may drift standing still (metres): its capsule settling.
const STILL: float = 0.1
## How close the first player walks up to a downed guest to revive it (metres between their feet: inside the sim's
## REVIVE_RANGE of 1.5 m, with room for a step's overshoot).
const REVIVE_CLOSE: float = 1.0
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
	expect(_who(screen, 1) == _guest(1), "the second seat is the player's +1: %s" % _who(screen, 1))
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
	_walk_crowd()


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
	set_setting(&"ui_scale", ui_scale)
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
	expect(session.local_indices.size() == 1, "A drops the guest out")
	await wait_for(func() -> bool: return session.get_local_device(0) == UnifiedSession.DEVICE_ANY, 2.0,
		"alone again, the first player plays with every device")
	await wait_for(func() -> bool: return _toast_shows("%s left (Barbarian)" % _guest(1)), 5.0,
		"a toast: %s left (Barbarian)" % _guest(1))
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
	await wait_for(func() -> bool: return _toast_shows("%s joined (Rogue)" % _guest(1)), 5.0,
		"a toast: %s joined (Rogue)" % _guest(1))
	expect(session.get_local_device(0) == UnifiedSession.DEVICE_KEYBOARD,
		"with a guest in, the first player keeps the keyboard")
	await seconds(0.4)  # the toast faded in
	var guest_attack: Label = find(current_scene,
		^"Hud/Heroes/HeroPlate2/Row/Info/Hints/Attack/GlyphBox/Glyphs") as Label
	expect(guest_attack != null and guest_attack.text == _glyph(&"attack", "XBOX"),
		"the guest's plate: its pad's glyphs")
	await shot("03_guest_joined")
	await _walk_revive()
	await _leave_guests()
	await wait_for(func() -> bool: return _toast_shows("%s left (Rogue)" % _guest(1)), 5.0,
		"a toast: %s left (Rogue)" % _guest(1))
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
	expect(_name_on(1) == _guest(1) and _name_on(2) == _guest(2), "named by place: %s, %s" % [_name_on(1),
		_name_on(2)])
	await shot("03b_three_players")
	await pad_button(JOY_BUTTON_START, 3)
	expect(_card(3) != null, "pad 3's card opens")
	Input.joy_connection_changed.emit(3, false)
	await frames(2)
	expect(_card(3) == null and not _in_session(3), "pad 3 gone while picking: its card closes, it gave up")
	await pad_button(JOY_BUTTON_BACK, 1)
	await pad_button(JOY_BUTTON_A, 1)
	await wait_for(func() -> bool: return not _in_session(1), 3.0, "%s drops out" % _guest(1))
	await _join(3)
	expect(_name_on(3) == _guest(1) and _name_on(2) == _guest(2),
		"the next guest takes the free place's name: %s, %s" % [_name_on(3), _name_on(2)])
	await _join(1)
	expect(session.local_indices.size() == UnifiedSession.LOCAL_MAX, "the couch is full")
	await frames(2)
	expect(not (find(current_scene, ^"Hud/%JoinHint") as Control).visible, "a full couch: no join hint")
	await pad_button(JOY_BUTTON_START, 4)
	expect(_card(4) == null, "a fifth pad's Start opens no card")
	expect(_toast_shows("The couch is full"), "a toast says why")
	await _walk_full_hud_fits()
	await _leave_guests()
	step("two cards at once, a pad gone, names by place, a full couch")


## At 130 % with four players: the four plates inside the view (scaled down to fit), each guest's name keeping its
## "+1", and no toast over a plate or the counts.
func _walk_full_hud_fits() -> void:
	set_setting(&"ui_scale", 1.3)
	await frames(4)
	var hud: Control = find(current_scene, ^"Hud") as Control
	var heroes: Control = find(hud, ^"%Heroes") as Control
	var view: Rect2 = hud.get_viewport_rect()
	expect(view.encloses(heroes.get_global_rect()), "at 130 %%, four plates fit the view: %s in %s"
		% [heroes.get_global_rect(), view])
	for plate: String in ["HeroPlate2", "HeroPlate3", "HeroPlate4"]:
		var who: Label = find(heroes, NodePath(plate + "/%Who")) as Label
		expect(who.text.right(3).begins_with(" +"), "a guest's plate keeps its +N: %s" % who.text)
	expect_toasts_clear([heroes, find(hud, ^"%Crypt") as Control])
	await shot("03c_full_couch_130")
	set_setting(&"ui_scale", ui_scale)
	await frames(2)


## No toast covers any of `controls` (the HUD's plates, the counts, the banner).
func expect_toasts_clear(controls: Array[Control]) -> void:
	for toast: Node in overlay("Toasts").get_children():
		var rect: Rect2 = (toast as Control).get_global_rect()
		for control: Control in controls:
			if control.is_visible_in_tree():
				expect(not rect.intersects(control.get_global_rect()), "a toast (%s) clear of %s (%s)"
					% [rect, control.name, control.get_global_rect()])


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
	for local: int in session.local_indices:
		if session.get_local_device(local) == device:
			return local
	return -1


## The name the session knows the player on pad `device` by.
func _name_on(device: int) -> String:
	return session.get_player_name(session.get_local_player_key(_local_of(device)))


func _leave_guests() -> void:
	for local: int in session.local_indices:
		if local > 0:
			session.remove_local_player(local)
	await wait_for(func() -> bool: return session.local_indices.size() == 1, 3.0, "the guests gone")
	await wait_for(func() -> bool: return session.get_local_device(0) == UnifiedSession.DEVICE_ANY, 2.0,
		"alone again, the first player plays with every device")


## The name of this couch's guest at local index `local`: the player's and "+1", "+2"...
func _guest(local: int) -> String:
	return "%s +%d" % [WALK_NAME, local]


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


## A toast says `text`, or says it with the name cut by NameLabel's rule ("Sexton of the... +1 left (Barbarian)").
func _toast_shows(text: String) -> bool:
	for toast: Node in overlay("Toasts").get_children():
		var shown: String = (toast.get_node(^"%Text") as Label).text
		var cut: int = shown.find("...")
		if shown == text or cut > 0 and text.begins_with(shown.left(cut)) and text.ends_with(shown.substr(cut + 3)):
			return true
	return false


## The minions are the crowd, one MultiMesh (game/crowd/minion_crowd_view.gd), each instance the state's minion: newly
## on Floor 1, its packs' sleepers are its only minions, none struck, so the crowd shows as many instances as the HUD
## counts, each in the stance clip with its gait's age running and its last hit far in the past (never: no flash).
func _walk_crowd() -> void:
	var crowd: MultiMeshInstance3D = current_scene.find_child("Minions", true, false) as MultiMeshInstance3D
	expect(crowd != null and crowd.material_override is ShaderMaterial, "the crowd is a MultiMesh with its material")
	if failed():
		return
	var shown: int = crowd.multimesh.visible_instance_count
	var minions: int = Unified.data.hud.minions
	expect(minions > 0 and shown == minions, "the crowd shows the floor's %d minions (%d instances)" % [minions, shown])
	# The host writes the whole buffer (set_buffer): an instance is 12 floats of transform, then its 4 of custom data.
	var buffer: PackedFloat32Array = crowd.multimesh.buffer
	for index: int in shown:
		var custom: PackedFloat32Array = buffer.slice(index * 16 + 12, index * 16 + 16)
		expect(int(custom[0]) == MinionCrowd.Clip.IDLE, "minion %d sleeps in the stance (clip %d)" % [index, int(custom[0])])
		expect(custom[1] > 0.0, "minion %d's gait has an age (%f s)" % [index, custom[1]])
		expect(custom[2] > 1000.0, "minion %d was never struck: its hit is far in the past (%f s)" % [index, custom[2]])
	step("the crowd: %d sleeping minions, one MultiMesh" % shown)


## The guest (pad 1's Rogue) rolls with its pad's B, its ability pip draining; a dev hurt downs it, and it lies as its
## ragdoll's view (its hero view's character hidden) in its revive ring; the skeletons are killed (dev), so no blow ends the revive; the first player walks up to it on the keyboard, and "[E] Revive" hangs over the guest; holding E
## fills the ring and revives it, with the toast "<first player> revived <guest>", which waits for CONFIRMED.
func _walk_revive() -> void:
	var guest: int = session.get_local_player_key(_local_of(1))
	var pip: ProgressBar = find(current_scene, ^"Hud/Heroes/HeroPlate2/%AbilityPip") as ProgressBar
	await pad_button(JOY_BUTTON_B, 1)
	await wait_for(func() -> bool: return pip.value < pip.max_value, 2.0, "the guest's roll drains its ability pip")
	await seconds(0.5)  # past the roll: its safe start lets a blow by
	var hurt := CommandDevHurt.new()
	hurt.player = guest
	hurt.damage = 100
	session.send_command(hurt)
	var downed: Node3D = session.get_player_view(EnumView.HERO, guest) as Node3D
	await wait_for(func() -> bool: return _view_action(downed) == EnumAction.DOWN, 3.0, "the guest goes down")
	var ring: Node3D = find(downed, ^"ReviveRing") as Node3D
	expect(ring.visible, "a ring lies round the downed guest")
	var ragdoll: Node3D = session.get_player_view(EnumView.RAGDOLL, guest) as Node3D
	expect(ragdoll != null and ragdoll.is_visible_in_tree(), "the guest lies as its ragdoll's view")
	var character: Node3D = downed.get(&"_rig")
	expect(not character.visible, "and its hero view hides its character")
	# The floor's first surge has risen by now (the elites' part came first): a blow from one of its skeletons would end
	# the revive, so they go (dev) before the first player walks up.
	session.send_command(CommandDevKillMinions.new())
	await wait_for(func() -> bool: return Unified.data.hud.minions == 0, 2.0, "the skeletons are killed (dev)")
	await _walk_up_to(downed, REVIVE_CLOSE)
	var prompts: Node = find(current_scene, ^"Hud/%RevivePrompts")
	var prompt: Control = prompts.get_child(0) as Control
	await wait_for(func() -> bool: return prompt.visible, 2.0, "beside the downed guest, \"[E] Revive\" shows")
	await shot("03d_revive_prompt")
	var seen: Array[UnifiedEvent] = []  # the revive's event, as the session gave it (read-only: kept to show again)
	var keep: Callable = func(event: UnifiedEvent, _state: UnifiedSession.EventState) -> void:
		if event is EventHeroRevived and seen.is_empty():
			seen.append(event)
	session.sim_event.connect(keep)
	await key(KEY_E, true)
	await seconds(1.0)
	var data: ViewHero = downed.get(&"data")
	var fill: float = (ring as GeometryInstance3D).get_instance_shader_parameter(&"fill")
	expect(data.action == EnumAction.DOWN and data.revive > 0 and absf(fill - data.revive / 255.0) < 0.01,
		"holding E fills the ring (%d of 255, the ring at %.2f)" % [data.revive, fill])
	await shot("03e_reviving")
	await wait_for(func() -> bool: return _view_action(downed) != EnumAction.DOWN, 4.0, "holding E revives the guest")
	await key(KEY_E, false)
	expect(not ring.visible, "the ring goes with the revive")
	var toast: String = "%s revived %s" % [session.get_player_name(session.local_player), _guest(1)]
	await wait_for(func() -> bool: return _toast_shows(toast), 3.0, "a toast: %s" % toast)
	session.sim_event.disconnect(keep)
	expect(not seen.is_empty(), "the session told of the revive")
	if not seen.is_empty():
		await _walk_revive_confirmed(seen[0])
	step("the guest rolled, went down and was revived")


## A revive's chime and toast wait for its CONFIRMED showing. A session alone has no peer to wait for (its events come
## EMITTED and CONFIRMED in one frame), so the play scene is shown the revive `revived` again in each state by hand:
## EMITTED alone, nothing; CONFIRMED, the chime and the toast.
func _walk_revive_confirmed(revived: UnifiedEvent) -> void:
	var toasts: Node = overlay("Toasts")
	toasts.call(&"clear")
	var shown: int = 0
	var mark: int = sounds.size()
	current_scene.call(&"_on_sim_event", revived, UnifiedSession.EVENT_EMITTED)
	await frames(2)
	expect(played(&"revived", mark) == 0 and toasts.get_child_count() == shown,
		"a revive only predicted (EMITTED): no chime, no toast")
	current_scene.call(&"_on_sim_event", revived, UnifiedSession.EVENT_CONFIRMED)
	await frames(2)
	expect(played(&"revived", mark) == 1 and toasts.get_child_count() == shown + 1,
		"once CONFIRMED: the chime and the toast")


## Walks the first player's hero (on the keyboard's moves) until its feet are within `close` of `target`'s.
func _walk_up_to(target: Node3D, close: float) -> void:
	var held: Dictionary[Key, bool] = {KEY_W: false, KEY_A: false, KEY_S: false, KEY_D: false}
	var until: int = Time.get_ticks_msec() + 5000
	while _floor_distance(local_hero(), target) > close and Time.get_ticks_msec() < until and not failed():
		var offset: Vector3 = target.global_position - local_hero().global_position
		var want: Dictionary[Key, bool] = {KEY_W: offset.z < -0.2, KEY_A: offset.x < -0.2, KEY_S: offset.z > 0.2,
			KEY_D: offset.x > 0.2}
		for key_code: Key in held:
			if held[key_code] != want[key_code]:
				held[key_code] = want[key_code]
				await key(key_code, want[key_code])
		await process_frame
	for key_code: Key in held:
		if held[key_code]:
			await key(key_code, false)
	expect(_floor_distance(local_hero(), target) <= close, "the first player walks up to the downed guest")


## How far apart two views' feet are on the floor plan.
static func _floor_distance(from: Node3D, to: Node3D) -> float:
	return Vector2(from.global_position.x, from.global_position.z).distance_to(
		Vector2(to.global_position.x, to.global_position.z))


## The action a hero view shows (EnumAction; NONE without a view).
static func _view_action(view: Node3D) -> int:
	var data: ViewHero = view.get(&"data") if view != null else null
	return data.action if data != null else EnumAction.NONE


## The floor's elites (its two markers) are scene views (game/views/elite.tscn), asleep where they stand, their health
## bars full; a dev hurt shows on each bar as its health left (the bar's per-instance fill is the view data's hp of
## hp_max), and a killing one lays them down and their views go after DEATH_S. Then a dev-spawned Mage casts: its bone
## bolt shows in the BoneBolts MultiMesh (MultiView.Bone_Bolt), never as a hero's bolt.
func _walk_elites() -> void:
	var elites: Array[Node] = views(EnumView.ELITE)
	expect(elites.size() == 2, "Floor 1 shows its two elites (%d views)" % elites.size())
	for view: Node in elites:
		var data: ViewElite = view.get(&"data")
		expect(data.phase == EnumElitePhase.IDLE and data.hp == data.hp_max, "an elite sleeps at full health")
		expect(_bar_of(view) == 1.0, "its bar is full (%f)" % _bar_of(view))
	var hurt := CommandDevHurtElites.new()
	hurt.damage = 30
	session.send_command(hurt)
	await wait_for(_elites_hurt, 2.0, "the elites are hurt")
	await frames(2)
	for view: Node in views(EnumView.ELITE):
		var data: ViewElite = view.get(&"data")
		var left: float = float(data.hp) / float(data.hp_max)
		expect(data.hp == data.hp_max - 30 and absf(_bar_of(view) - left) < 0.001,
			"its bar tracks its health: %f of %d/%d" % [_bar_of(view), data.hp, data.hp_max])
	hurt = CommandDevHurtElites.new()
	hurt.damage = 500
	session.send_command(hurt)
	await wait_for(func() -> bool: return views(EnumView.ELITE).is_empty(), 2.0 + Unified.constants.minion_death,
		"the felled elites' views go")
	step("the elites: asleep, their bars tracking their health, felled")
	var mage := CommandDevSpawnElite.new()
	mage.kind = EnumEliteKind.MAGE
	session.send_command(mage)
	var bone_bolts: MultiMeshInstance3D = current_scene.find_child("BoneBolts", true, false) as MultiMeshInstance3D
	await wait_for(func() -> bool: return bone_bolts.multimesh.visible_instance_count > 0, 6.0,
		"a skeleton Mage's bone bolt in the BoneBolts MultiMesh")
	expect(multi_count(EnumMultiView.BOLT) == 0, "a bone bolt is no hero's bolt")
	hurt = CommandDevHurtElites.new()
	hurt.damage = 500
	session.send_command(hurt)
	await wait_for(func() -> bool: return views(EnumView.ELITE).is_empty(), 2.0 + Unified.constants.minion_death,
		"the felled Mage's view goes")
	step("a skeleton Mage's bone bolt: its own MultiMesh")


## Whether every elite view shows a wound.
func _elites_hurt() -> bool:
	for view: Node in views(EnumView.ELITE):
		var data: ViewElite = view.get(&"data")
		if data.hp == data.hp_max:
			return false
	return true


## The fill of an elite view's health bar (its MeshInstance3D's per-instance `fraction`).
func _bar_of(view: Node) -> float:
	var bar: MeshInstance3D = view.get_node(^"Bar") as MeshInstance3D
	var fill: float = bar.get_instance_shader_parameter(&"fraction")
	return fill
