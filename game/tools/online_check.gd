extends TogetherWalk
## Online play from the menus, on a machine where it can start (`./uni tool online_check`): Play together, Host online,
## hero select, and the crypt up at once while "Getting a code..." shows, then hosted through the lobby service, its
## code (join_code_length characters of join_code_alphabet) on the session panel and in Invite friends, copied once (the
## run's own clipboard: Game.clipboard_get); Stop inviting closes it, Invite online opens it again, its code posted and
## copied again; then it leaves. Where online play can't start (UnifiedSession.online_problem: no EOS SDK, no .env;
## every CI and suite run) it says why and passes without trying: the walk covers that state. Two processes over a real
## lobby are `./uni coop` (with `--menus`, through the menus).


func _run() -> void:
	change_scene_to_file(str(ProjectSettings.get_setting("application/run/main_scene")))
	await wait_for_scene("Menu", 5.0)
	await frames(5)
	var problem: String = session.online_problem
	if problem != "":
		step("skipped: online play can't start here (%s)" % problem)
		return
	await click(title_control("PlayTogether"))
	await click(find(top_screen(), ^"%HostOnline") as Control)
	game.call(&"clipboard_set", "")
	await _walk_hero_select_start("Host a crypt")
	await wait_for(func() -> bool: return scene_is("Play") and local_hero() != null, 30.0, "the crypt up at once")
	if failed():
		return
	var value: Label = find(current_scene, ^"Hud/SessionPanel/%Value") as Label
	await wait_for(func() -> bool: return value.is_visible_in_tree() and value.text == "Getting a code...", 5.0,
		"the panel says the code is coming")
	await shot("online_pending")
	var code: String = await _lobby_code(value)
	if failed():
		return
	await press_key(KEY_ESCAPE)
	await click(_pause_control("Friends"))
	var friends: Control = _pause_menu().call(&"top")
	expect((find(friends, ^"%Code") as Label).text == code, "and Invite friends")
	await shot("online_hosted")
	step("hosted online from the menus: code %s" % code)
	await click(find(friends, ^"%Stop") as Control)
	await wait_for(func() -> bool: return session.join_code == "" and value.text == "Closed", 10.0,
		"Stop inviting closes it")
	step("stopped inviting: %s" % value.text)
	game.call(&"clipboard_set", "")
	await click(find(friends, ^"%Online") as Control)
	var again: String = await _lobby_code(value)
	if failed():
		return
	step("invited online again: code %s (was %s)" % [again, code])
	game.call(&"leave")
	await wait_for_scene("Menu", 10.0)
	step("left")


## The lobby code once it comes: as the lobby service's codes read, on the session panel's `value`, and copied once
## (another code put on the clipboard stays).
func _lobby_code(value: Label) -> String:
	await wait_for(func() -> bool: return session.join_code != "", 30.0, "a lobby code")
	var code: String = session.join_code
	if failed():
		return code
	var readable: bool = code.length() == session.join_code_length
	for character: String in code:
		readable = readable and character in session.join_code_alphabet
	expect(readable, "the code reads as the lobby service's: %s" % code)
	await frames(2)
	expect(value.text == code, "the session panel shows it: %s" % value.text)
	expect(str(game.call(&"clipboard_get")) == code, "it was copied")
	game.call(&"clipboard_set", "mine")
	await seconds(1.0)
	expect(str(game.call(&"clipboard_get")) == "mine", "once: what the player copied since stays")
	return code
