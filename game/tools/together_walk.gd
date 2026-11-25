class_name TogetherWalk
extends SessionWalk
## The walk's parts about playing together (game/tools/ui_walk.gd extends this and runs them in its order), each from
## the title and back to it, in one process: Play together without online play (its rows greyed with the library's
## sentence), the code field and a join by code that can't start, a LAN host from the menus (the session panel, Invite
## friends' code, Copy, Stop inviting and inviting again), a single-player game opened to friends from the pause menu
## (it stays paused, for everyone) and closed again, and a join by address that fails, back on its screen with the
## address kept, then offered as Rejoin.

## An address no network has (`.invalid` never resolves): a join to it fails at once.
const NOWHERE: String = "nohost.invalid:7777"


## Play together with no online play here (the suite's runs have no EOS SDK): Host online and Join with a code greyed,
## the library's sentence under them; Back to the title.
func _walk_play_together() -> void:
	await click(title_control("PlayTogether"))
	var screen: Control = top_screen()
	expect(screen != null and screen.name == "PlayTogether", "Play together opens its screen")
	if failed():
		return
	var problem: String = session.online_problem
	expect(problem != "", "this run has no online play: %s" % problem)
	for online: String in ["HostOnline", "JoinCode"]:
		expect((find(screen, "%" + online) as Button).disabled, "%s is greyed" % online)
	var said: String = (find(screen, ^"%OnlineProblem") as Label).text
	expect(said == problem, "and the library's sentence says why: %s" % said)
	await frames(3)
	await shot("21_play_together")
	await press_key(KEY_ESCAPE)
	expect(top_screen() == title(), "Back to the title")
	step("Play together: online greyed, %s" % problem)


## The code field (its button greyed here, enabled for the walk): letters typed go in upper case, one outside the
## alphabet is refused, Backspace takes one back, up steps a cell through the alphabet, a paste that holds no code is
## refused with a word; a whole code enables Join, whose start fails at once (no online play), back on the code's
## screen with the code kept.
func _walk_join_code() -> void:
	await click(title_control("PlayTogether"))
	var join_code: Button = find(top_screen(), ^"%JoinCode") as Button
	join_code.disabled = false
	await click(join_code)
	var screen: Control = top_screen()
	expect(screen != null and screen.name == "JoinCode", "Join with a code opens its screen")
	if failed():
		return
	var field: Control = find(screen, ^"%Code") as Control
	var join: Button = find(screen, ^"%Join") as Button
	expect(root.gui_get_focus_owner() == field, "the code field has the focus")
	await type_text("ab0")
	expect(_code_cells(field) == "AB", "letters go in upper case, a 0 (not in the alphabet) is refused: %s"
		% _code_cells(field))
	await press_key(KEY_BACKSPACE)
	expect(_code_cells(field) == "A", "Backspace takes one back: %s" % _code_cells(field))
	await pad_button(JOY_BUTTON_DPAD_UP)
	var stepped: String = _code_cells(field)
	expect(stepped.length() == 2 and stepped[1] == session.join_code_alphabet[0],
		"up steps a cell through the alphabet: %s" % stepped)
	expect(join.disabled, "Join waits for a whole code")
	if DisplayServer.get_name() != "headless":  # a headless run has no clipboard (and no Paste)
		DisplayServer.clipboard_set("hello")
		await click(find(screen, ^"%Paste") as Control)
		var problem: Label = find(screen, ^"%Problem") as Label
		expect(problem.visible and _code_cells(field) == stepped, "a paste with no code is refused: %s" % problem.text)
	await click(field)
	await press_key(KEY_LEFT)  # to the first cell
	var code: String = "K7M2QX"
	await type_text(code.to_lower())
	expect(_code_cells(field) == code and not join.disabled, "a whole code: Join: %s" % _code_cells(field))
	await frames(3)
	await shot("23_join_code")
	await click(join)
	await _walk_hero_select_start("Join %s" % code)
	var dialog: Control = overlay("Dialog")
	await wait_for(func() -> bool: return dialog.visible, 5.0, "the join can't start: the dialog says why")
	await press_key(KEY_ESCAPE)
	expect(top_screen() == screen and _code_cells(field) == code, "back on the code's screen, the code kept")
	await press_key(KEY_ESCAPE)
	await press_key(KEY_ESCAPE)
	expect(top_screen() == title(), "Back, Back: the title")
	step("the code field; a join by code that can't start comes back to it")


## A LAN host from the menus, on a free port: Play together, Host on this network, a new crypt (the slot holds one),
## hero select ("Host a crypt"), the crypt: the session panel shows the address; Invite friends shows it with Copy;
## Stop inviting closes it (the panel says so), inviting again opens it. Leave asks first and goes to the title.
func _walk_lan_host() -> void:
	game.set(&"lan_port", _free_port())
	await click(title_control("PlayTogether"))
	await click(find(top_screen(), ^"%HostLan") as Control)
	expect(top_screen().name == "HostCrypt", "with a crypt saved, the host chooses which")
	await click(find(top_screen(), ^"%New") as Control)
	await _walk_hero_select_start("Host a crypt")
	await wait_for(func() -> bool: return scene_is("Play") and local_hero() != null, 8.0, "hosting from the menus")
	if failed():
		return
	expect(session.mode == UnifiedSession.MODE_HOST_DIRECT, "on this network")
	await wait_for(func() -> bool: return session.join_code != "", 3.0, "its address")
	var panel: Control = find(current_scene, ^"Hud/SessionPanel") as Control
	var value: Label = find(panel, ^"%Value") as Label
	expect(panel.visible and value.text == session.join_code, "the session panel shows it: %s" % value.text)
	await seconds(0.5)
	await shot("22_session_panel")
	await press_key(KEY_ESCAPE)
	await click(_pause_control("Friends"))
	var friends: Control = _pause_menu().call(&"top")
	var code: Label = find(friends, ^"%Code") as Label
	expect(code.text == session.join_code, "Invite friends shows the address: %s" % code.text)
	if DisplayServer.get_name() != "headless":  # a headless run has no clipboard (and no Copy)
		await click(find(friends, ^"%Copy") as Control)
		expect(DisplayServer.clipboard_get() == session.join_code, "Copy copies it")
	await shot("24_invite_friends")
	await click(find(friends, ^"%Stop") as Control)
	await wait_for(func() -> bool: return session.join_code == "", 3.0, "Stop inviting closes it")
	expect(value.text == "Closed to new players", "the panel says so: %s" % value.text)
	await click(find(friends, ^"%Lan") as Control)
	await wait_for(func() -> bool: return session.join_code != "", 3.0, "inviting again opens it")
	await press_key(KEY_ESCAPE)
	await click(_pause_control("Leave"))
	await click(find(overlay("Dialog"), ^"%Ok") as Control)
	await wait_for_scene("Menu", 5.0)
	step("a LAN host from the menus: the panel, Invite friends, Stop inviting, again")


## A single-player game opened to friends from the pause menu: Invite on this network while it is paused alone makes
## it a host, paused now for everyone (the menu says who), its address shown; Stop inviting closes it. Leave.
func _walk_open_to_friends() -> void:
	game.set(&"lan_port", _free_port())
	await click(title_control("Continue"))
	await _walk_hero_select_start("Continue your crypt")
	await wait_for(func() -> bool: return scene_is("Play") and local_hero() != null, 8.0, "a game alone")
	if failed():
		return
	await press_key(KEY_ESCAPE)
	await wait_for(func() -> bool: return session.paused, 2.0, "paused alone")
	await click(_pause_control("Friends"))
	var friends: Control = _pause_menu().call(&"top")
	await click(find(friends, ^"%Lan") as Control)
	await wait_for(func() -> bool: return session.mode == UnifiedSession.MODE_HOST_DIRECT and session.join_code != "",
		3.0, "opened to friends on this network")
	await wait_for(func() -> bool: return Unified.data.hud.paused, 3.0, "still paused: now for everyone")
	expect((find(friends, ^"%Code") as Label).text == session.join_code, "its address shown")
	await click(find(friends, ^"%Stop") as Control)
	await wait_for(func() -> bool: return session.join_code == "", 3.0, "Stop inviting closes it")
	await press_key(KEY_ESCAPE)
	var heading: String = (_pause_control("Heading") as Label).text
	expect(heading == "Paused by %s" % setting(&"player_name"), "the menu says who paused: %s" % heading)
	game.call(&"leave")
	await wait_for_scene("Menu", 5.0)
	await frames(3)
	step("a game alone opened to friends and closed, paused throughout")


## A join by address: something that isn't one keeps Join off and says so; an address nowhere fails at once, back on
## its screen with the address kept; Play together then offers to rejoin it.
func _walk_join_address() -> void:
	await click(title_control("PlayTogether"))
	await click(find(top_screen(), ^"%JoinAddress") as Control)
	var screen: Control = top_screen()
	var field: LineEdit = find(screen, ^"%Address") as LineEdit
	var join: Button = find(screen, ^"%Join") as Button
	await click(field)
	field.select_all()
	await type_text("not an address")
	expect(join.disabled and (find(screen, ^"%Problem") as Control).visible, "what isn't an address: no Join, a word")
	field.select_all()
	await type_text(NOWHERE)
	expect(not join.disabled, "an address: Join")
	await click(join)
	await _walk_hero_select_start("Join %s" % NOWHERE)
	var dialog: Control = overlay("Dialog")
	await wait_for(func() -> bool: return dialog.visible, 10.0, "the join fails: the dialog says why")
	await shot("25_join_failed")
	await press_key(KEY_ESCAPE)
	expect(top_screen() == screen and field.text == NOWHERE, "back on its screen, the address kept")
	await press_key(KEY_ESCAPE)
	var rejoin: Button = find(top_screen(), ^"%Rejoin") as Button
	expect(rejoin.visible and not rejoin.disabled and rejoin.text == "Rejoin %s" % NOWHERE,
		"Play together offers to rejoin it: %s" % rejoin.text)
	await press_key(KEY_ESCAPE)
	expect(top_screen() == title(), "Back: the title")
	title_focus().grab_focus()  # where the walk's next part expects it
	step("a join by address that fails, kept, then offered as Rejoin")


## Hero select under `heading`: the first seat (the keyboard and mouse) readies and starts.
func _walk_hero_select_start(heading: String) -> void:
	var screen: Control = _hero_select()
	if failed():
		return
	var shown: String = (find(screen, ^"%Heading") as Label).text
	expect(shown == heading, "hero select says what it starts: %s" % shown)
	var card: Control = screen.call(&"card", 0)
	await click(find(card, ^"%Act") as Control)
	await click(find(screen, ^"%Start") as Control)


## The characters a code field holds, the empty cells left out.
func _code_cells(field: Control) -> String:
	var out: String = ""
	for frame: Node in field.get_children():
		out += (frame.get_child(0).get_child(0) as Label).text
	return out
