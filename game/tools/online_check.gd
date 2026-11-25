extends TogetherWalk
## Online play from the menus, on a machine where it can start (`./uni tool online_check`): Play together, Host online,
## hero select, and the crypt hosted through the lobby service, its code (join_code_length characters of
## join_code_alphabet) on the session panel and in Invite friends; then it leaves. Where online play can't start
## (UnifiedSession.online_problem: no EOS SDK, no .env; every CI and suite run) it says why and passes without trying:
## the walk covers that state. Two processes over a real lobby are `./uni coop` (with `--menus`, through the menus).


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
	await _walk_hero_select_start("Host a crypt")
	await wait_for(func() -> bool: return scene_is("Play") and local_hero() != null, 30.0, "hosting online")
	await wait_for(func() -> bool: return session.join_code != "", 30.0, "a lobby code")
	if failed():
		return
	var code: String = session.join_code
	var readable: bool = code.length() == session.join_code_length
	for character: String in code:
		readable = readable and character in session.join_code_alphabet
	expect(readable, "the code reads as the lobby service's: %s" % code)
	var value: Label = find(current_scene, ^"Hud/SessionPanel/%Value") as Label
	expect(value.text == code, "the session panel shows it: %s" % value.text)
	await press_key(KEY_ESCAPE)
	await click(_pause_control("Friends"))
	var friends: Control = _pause_menu().call(&"top")
	expect((find(friends, ^"%Code") as Label).text == code, "and Invite friends")
	await shot("online_hosted")
	step("hosted online from the menus: code %s" % code)
	game.call(&"leave")
	await wait_for_scene("Menu", 10.0)
	step("left")
