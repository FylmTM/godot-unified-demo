extends UnifiedValidate
## Crypt Crew's project check: unified's UnifiedValidate (every script compiles typed, every scene loads, the main
## scene runs), plus the game's own contract: its art, the rules docs/ART.md sets for assets, materials, characters,
## clips and kit parts (ArtChecks), its app layer, the promises between the autoloads, the theme, the HUD and the
## menus (AppChecks), and its effects and light (FxChecks).


## The scene the game plays in: the main scene is the menu, so the play scene is named here for the checks that hold
## the play scene to what a background load needs (no preload()) and to its MultiMesh views.
func _play_scene() -> String:
	return "res://game/play/play.tscn"


func _check_contract() -> String:
	var art := ArtChecks.new(log_capture, root)
	art.run()
	var app := AppChecks.new(log_capture, root)
	app.run()
	var fx := FxChecks.new(log_capture, root)
	fx.run()
	var found: PackedStringArray = []
	if art.problems > 0:
		found.append("%d art problem(s)" % art.problems)
	if app.problems > 0:
		found.append("%d app problem(s)" % app.problems)
	if fx.problems > 0:
		found.append("%d effects problem(s)" % fx.problems)
	return "ok" if found.is_empty() else ", ".join(found)
