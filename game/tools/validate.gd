extends UnifiedValidate
## Crypt Crew's project check: unified's UnifiedValidate (every script compiles typed, every scene loads), plus the
## game's own contract, which today is its art: the rules docs/ART.md sets for assets, materials, characters, clips and
## kit parts (ArtChecks).


func _check_contract() -> String:
	var checks := ArtChecks.new(log_capture, root)
	checks.run()
	return "ok" if checks.problems == 0 else "%d art problem(s)" % checks.problems
