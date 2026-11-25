class_name UserFile
extends RefCounted
## The player's text files under user:// (the settings, the save), written so a crash or a full disk never leaves half
## a file: the text goes to `<path>.tmp` first, is checked written, and only then replaces the file. Reading takes the
## `.tmp` when the file itself is missing (a crash between the two steps leaves only it). Failures are printed, not
## warned (uni fails a run on any warning of the game's, and the app checks fail a write on purpose): the caller keeps
## its copy in memory either way.


## Writes `text` to `path` (beside it first, then moved over it); false, the old file left as it was, when it fails.
static func write(path: String, text: String) -> bool:
	var temp: String = path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		print("UserFile: can't write %s (%s)" % [temp, error_string(FileAccess.get_open_error())])
		return false
	var stored: bool = file.store_string(text)
	var error: Error = file.get_error()
	file.close()
	if not stored or error != OK:
		print("UserFile: writing %s failed (%s)" % [temp, error_string(error)])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		return false
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path))
	if error != OK:
		print("UserFile: can't move %s over %s (%s)" % [temp, path, error_string(error)])
		return false
	return true


## The text of `path`, or of its `.tmp` when it is missing ("": neither is there).
static func read(path: String) -> String:
	for candidate: String in [path, path + ".tmp"]:
		if FileAccess.file_exists(candidate):
			return FileAccess.get_file_as_string(candidate)
	return ""


## Whether `path`, or its `.tmp`, is there.
static func exists(path: String) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".tmp")


## Moves `path` (or its `.tmp`) to `to`, keeping a file that doesn't read for the player.
static func set_aside(path: String, to: String) -> void:
	var from: String = path if FileAccess.file_exists(path) else path + ".tmp"
	DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))
