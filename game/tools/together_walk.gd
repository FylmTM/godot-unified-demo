class_name TogetherWalk
extends SessionWalk
## The walk's parts about playing together (game/tools/ui_walk.gd extends this and runs them in its order), each from
## the title and back to it, in one process: Play together (online greyed with the library's sentence where it can't
## start, as in every suite run, else offered), the code field (typed, pasted through the run's own clipboard, Enter)
## and a join by code that fails back to its screen, a LAN host from the menus on the saved crypt (a new one asks first;
## the session panel; Invite friends: Copy, Stop inviting, "Closed", inviting again), a game alone whose opening fails
## (the reason on the screen) and then opens while paused (paused now for everyone, Resume for everyone focused and
## pressed), and a join by address (Enter, Esc in the field, an address the network can't find, back with it kept) and
## Rejoin pressed. Two processes (a joiner's panel, two players) are coop.gd's.

## An address no network has (`.invalid` never resolves): a join to it fails at once.
const NOWHERE: String = "nohost.invalid:7777"

## The library's words for the last start that failed (STATUS_FAILED's detail), heard from the walk's start on.
var _failed_detail: String = ""

## Play together: where online play can't start (every suite run) Host online and Join with a code are greyed and take
## no focus, the library's sentence under them, and the focus is on the first row that works; where it can, all are
## offered. Back to the title.
func _walk_play_together() -> void:
	session.status_changed.connect(func(status: UnifiedSession.Status, detail: String) -> void:
		if status == UnifiedSession.STATUS_FAILED:
			_failed_detail = detail)
	await click(title_control("PlayTogether"))
	var screen: Control = top_screen()
	expect(screen != null and screen.name == "PlayTogether", "Play together opens its screen")
	if failed():
		return
	var problem: String = session.online_problem
	for online: String in ["HostOnline", "JoinCode"]:
		var row: Button = find(screen, "%" + online) as Button
		expect(row.disabled == (problem != ""), "%s is %s" % [online, "greyed" if problem != "" else "offered"])
		expect((row.focus_mode == Control.FOCUS_NONE) == row.disabled, "and takes the focus only when offered")
	var said: String = (find(screen, ^"%OnlineProblem") as Label).text
	expect(said == problem, "the library's sentence says why: %s" % said)
	var first: Control = find(screen, ^"%HostLan" if problem != "" else ^"%HostOnline") as Control
	expect(root.gui_get_focus_owner() == first, "the first row that works has the focus")
	await frames(3)
	await shot("21_play_together")
	await press_key(KEY_ESCAPE)
	expect(top_screen() == title(), "Back to the title")
	step("Play together: %s" % ("online greyed, %s" % problem if problem != "" else "online offered"))


## The code field (its button enabled for the walk where online play can't start): letters typed go in upper case,
## one outside the alphabet is refused, Backspace takes one back, up steps a cell through the alphabet; pastes through
## the run's own clipboard: one with lower case, a dash and a line break is taken, one that is no code or too long is
## refused with a word. Enter in the field joins; the join fails (no online play here, or no such lobby), back on the
## code's screen with the code kept, the reason the library's sentence.
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
	expect(root.gui_get_focus_owner() == field and _code_cells(field) == "", "the code field, empty, has the focus")
	await type_text("ab0")
	expect(_code_cells(field) == "AB", "letters go in upper case, a 0 (not in the alphabet) is refused: %s"
		% _code_cells(field))
	await press_key(KEY_BACKSPACE)
	expect(_code_cells(field) == "A", "Backspace takes one back: %s" % _code_cells(field))
	await pad_button(JOY_BUTTON_DPAD_UP)
	var stepped: String = _code_cells(field)
	expect(stepped.length() == 2 and stepped[1] == session.join_code_alphabet[0],
		"up steps a cell through the alphabet: %s" % stepped)
	var problem: Label = find(screen, ^"%Problem") as Label
	for refused: String in ["hello", "K7M2QXZ"]:
		game.call(&"clipboard_set", refused)
		await click(find(screen, ^"%Paste") as Control)
		expect(problem.visible and _code_cells(field) == stepped, "a paste that is no code is refused: %s" % refused)
	game.call(&"clipboard_set", "k7m2-qx\n")
	await click(find(screen, ^"%Paste") as Control)
	var code: String = "K7M2QX"
	expect(_code_cells(field) == code, "a pasted code, lower case, a dash and a line break: %s" % _code_cells(field))
	await frames(3)
	await shot("23_join_code")
	await click(field)
	await press_key(KEY_ENTER)
	await _walk_hero_select_start("Join %s" % code)
	await _expect_failed_start(screen, 30.0)
	expect(_code_cells(field) == code, "the code kept")
	await press_key(KEY_ESCAPE)
	await press_key(KEY_ESCAPE)
	expect(top_screen() == title(), "Back, Back: the title")
	step("the code field; a join by code that fails comes back to it")


## A LAN host from the menus on a free port, over a save: A new crypt asks first (Back keeps the save), Continue your
## crypt hosts it through hero select ("Host a crypt"), at its surge; the session panel shows the address and one player; Invite friends shows it, Copy copies it (to the run's own
## clipboard) and says "Copied"; Stop inviting: the panel says "Closed"; inviting again opens it. Leave asks first.
func _walk_lan_host() -> void:
	game.set(&"lan_port", _free_port())
	await click(title_control("PlayTogether"))
	await click(find(top_screen(), ^"%HostLan") as Control)
	await click(find(top_screen(), ^"%New") as Control)
	var dialog: Control = overlay("Dialog")
	expect(dialog.visible and (find(dialog, ^"%Heading") as Label).text == "Start a new crypt?",
		"a new crypt over a save asks first")
	await click(find(dialog, ^"%Other") as Control)
	expect(not dialog.visible and top_screen().name == "HostCrypt", "Back: the choice again")
	var saves: RefCounted = game.get(&"saves")
	var saved: UnifiedSetup = saves.get(&"setup")
	await click(find(top_screen(), ^"%Continue") as Control)
	await _walk_hero_select_start("Host a crypt")
	await wait_for(func() -> bool: return scene_is("Play") and local_hero() != null, 8.0, "hosting from the menus")
	if failed():
		return
	expect(session.mode == UnifiedSession.MODE_HOST_DIRECT, "on this network")
	expect(saved != null and Unified.data.hud.surges == saved.surges, "the saved crypt, at its surge %d"
		% Unified.data.hud.surges)
	await wait_for(func() -> bool: return session.join_code != "", 3.0, "its address")
	var panel: Control = find(current_scene, ^"Hud/SessionPanel") as Control
	var value: Label = find(panel, ^"%Value") as Label
	expect(panel.visible and value.text == session.join_code, "the session panel shows it: %s" % value.text)
	var players: Label = find(panel, ^"%Players") as Label
	await wait_for(func() -> bool: return players.text == "1 player", 2.0, "and how many play: %s" % players.text)
	await seconds(0.5)
	await shot("22_session_panel")
	await press_key(KEY_ESCAPE)
	await click(_pause_control("Friends"))
	var friends: Control = _pause_menu().call(&"top")
	expect((find(friends, ^"%Code") as Label).text == session.join_code, "Invite friends shows the address")
	var copy: Button = find(friends, ^"%Copy") as Button
	await click(copy)
	var copied: String = game.call(&"clipboard_get")
	expect(copied == session.join_code and copy.text == "Copied", "Copy copies it, and says so: %s" % copy.text)
	await shot("24_invite_friends")
	await click(find(friends, ^"%Stop") as Control)
	await wait_for(func() -> bool: return session.join_code == "", 3.0, "Stop inviting closes it")
	expect(value.text == "Closed", "the panel says so: %s" % value.text)
	await click(find(friends, ^"%Lan") as Control)
	await wait_for(func() -> bool: return session.join_code != "", 3.0, "inviting again opens it")
	await press_key(KEY_ESCAPE)
	await click(_pause_control("Leave"))
	await click(find(overlay("Dialog"), ^"%Ok") as Control)
	await wait_for_scene("Menu", 5.0)
	step("a LAN host from the menus on the saved crypt: the panel, Invite friends, Copy, Stop inviting, again")


## A game alone opened to friends from the pause menu: first online where online play can't start (the button enabled
## for the walk: it fails, the library's reason on Invite friends, the game alone), then on this network while paused
## alone: a host, paused now for everyone; back, Resume for everyone has the focus (alone: "Resume when you're
## ready"), and pressed, the game runs. Leave.
func _walk_open_to_friends() -> void:
	await click(title_control("Continue"))
	await _walk_hero_select_start("Continue your crypt")
	await wait_for(func() -> bool: return scene_is("Play") and local_hero() != null, 8.0, "a game alone")
	if failed():
		return
	await press_key(KEY_ESCAPE)
	await wait_for(func() -> bool: return session.paused, 2.0, "paused alone")
	await click(_pause_control("Friends"))
	var friends: Control = _pause_menu().call(&"top")
	var problem: Label = find(friends, ^"%Problem") as Label
	if session.online_problem != "":
		var online: Button = find(friends, ^"%Online") as Button
		online.disabled = false
		await click(online)
		await wait_for(func() -> bool: return problem.visible and problem.text == game.get(&"invite_problem"), 5.0,
			"an opening that fails says why on the screen")
		expect(session.mode == UnifiedSession.MODE_SINGLE, "and the game stays alone: %s" % problem.text)
		await shot("26_open_failed")
	game.set(&"lan_port", _free_port())
	await click(find(friends, ^"%Lan") as Control)
	await wait_for(func() -> bool: return session.mode == UnifiedSession.MODE_HOST_DIRECT and session.join_code != "",
		3.0, "opened to friends on this network")
	await wait_for(func() -> bool: return Unified.data.hud.paused, 3.0, "still paused: now for everyone")
	expect(not problem.visible, "the failure is gone")
	await press_key(KEY_ESCAPE)
	var resume_all: Button = _pause_control("PauseAll") as Button
	expect(root.gui_get_focus_owner() == resume_all, "back: Resume for everyone has the focus")
	var status: String = (_pause_control("Status") as Label).text
	expect(status == "Resume when you're ready.", "alone, the menu says so: %s" % status)
	await press_key(KEY_ENTER)
	await wait_for(func() -> bool: return not Unified.data.hud.paused, 3.0, "Resume for everyone: the game runs")
	game.call(&"leave")
	await wait_for_scene("Menu", 5.0)
	await frames(3)
	step("a game alone: an opening that failed, then opened while paused and resumed")


## A join by address: the field opens with the last address selected; something that isn't one keeps Join off and says
## so; Enter in the field joins an address the network can't find: back on its screen, the address kept, the reason the
## app's ("Couldn't find ..."), the library's words under it; Esc in the field goes back. Rejoin (a last address set for
## the walk) joins through hero select and comes back to Play together when it fails.
func _walk_join_address() -> void:
	await click(title_control("PlayTogether"))
	await click(find(top_screen(), ^"%JoinAddress") as Control)
	var screen: Control = top_screen()
	var field: LineEdit = find(screen, ^"%Address") as LineEdit
	var join: Button = find(screen, ^"%Join") as Button
	await type_text("not an address")
	expect(join.disabled and (find(screen, ^"%Problem") as Control).visible, "what isn't an address: no Join, a word")
	field.select_all()
	await type_text(NOWHERE)
	await press_key(KEY_ENTER)
	await _walk_hero_select_start("Join %s" % NOWHERE)
	var dialog: Control = overlay("Dialog")
	await wait_for(func() -> bool: return dialog.visible, 10.0, "the join fails: the dialog says why")
	var reason: String = (find(dialog, ^"%Text") as Label).text
	expect(reason == "Couldn't find nohost.invalid on the network.", "the app's reason: %s" % reason)
	expect((find(dialog, ^"%Detail") as Label).visible, "the library's words under it")
	await shot("25_join_failed")
	await press_key(KEY_ESCAPE)
	expect(top_screen() == screen and field.text == NOWHERE, "back on its screen, the address kept")
	field.grab_focus()
	await press_key(KEY_ESCAPE)
	expect(top_screen().name == "PlayTogether", "Esc in the field goes back")
	await press_key(KEY_ESCAPE)
	root.get_node(^"Settings").set(&"last_join", NOWHERE)
	root.get_node(^"Settings").set(&"last_join_online", false)
	await click(title_control("PlayTogether"))
	var rejoin: Button = find(top_screen(), ^"%Rejoin") as Button
	expect(rejoin.visible and rejoin.text == "Rejoin %s" % NOWHERE, "Rejoin offers the last game: %s" % rejoin.text)
	await click(rejoin)
	await _walk_hero_select_start("Join %s" % NOWHERE)
	await wait_for(func() -> bool: return dialog.visible, 10.0, "the rejoin fails here: the dialog")
	await press_key(KEY_ESCAPE)
	expect(top_screen().name == "PlayTogether", "back to Play together")
	await press_key(KEY_ESCAPE)
	expect(top_screen() == title(), "Back: the title")
	title_focus().grab_focus()  # where the walk's next part expects it
	step("a join by address that fails, kept; Rejoin")


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


## A start that fails comes back to `screen` (hero select gone), the dialog over it with the library's sentence.
func _expect_failed_start(screen: Control, within_s: float) -> void:
	var dialog: Control = overlay("Dialog")
	await wait_for(func() -> bool: return dialog.visible, within_s, "the start fails: the dialog says why")
	var reason: String = (find(dialog, ^"%Text") as Label).text
	var expected: String = game.call(&"sentence", _failed_detail, "The game could not start.")
	expect(reason == expected, "the reason is the library's sentence: %s" % reason)
	await press_key(KEY_ESCAPE)
	expect(top_screen() == screen, "back on the screen it was asked from")


## The characters a code field holds, the empty cells left out.
func _code_cells(field: Control) -> String:
	var out: String = ""
	for frame: Node in field.get_children():
		out += (frame.get_child(0).get_child(0) as Label).text
	return out
