class_name Saves
extends RefCounted
## The one save slot, `user://save.json`: the Setup that continues the party's crypt, as its JSON
## (UnifiedSetup.to_json) and nothing else, so a later build reads it back by field name. Game keeps one Saves: it writes
## each save the session hands over (save_changed) when this machine hosts or plays alone, and the title offers
## Continue from it. Written beside and moved over the old file, so a crash mid-write never leaves half a save.
##
## A save that doesn't read (json_problem), or that another version of the game made (its version isn't this build's
## Unified.constants.save_version), is never dropped: it is moved aside to `save.bad.json` and `problem` says why, once
## (the title tells the player). Under `--no-settings` (tool and drive runs) nothing is read or written: the slot lives
## in memory, so a check never touches the player's crypt.

## The slot's file, and where a save that doesn't read is kept.
const PATH: String = "user://save.json"
const BAD_PATH: String = "user://save.bad.json"

## The save in the slot (null: none): what Continue starts from.
var setup: UnifiedSetup = null
## When the slot was last written (Unix seconds; 0: never).
var saved_at: int = 0
## Why the file in the slot didn't read at load (""; it did, or there was none): the title tells the player once.
var problem: String = ""

## Nothing touches the file (`--no-settings`).
var _in_memory: bool = false


func _init(in_memory: bool) -> void:
	_in_memory = in_memory
	if not in_memory:
		_load()


## Keeps `save` in the slot (a host's or a single player's save_changed).
func keep(save: UnifiedSetup) -> void:
	setup = save
	saved_at = int(Time.get_unix_time_from_system())
	if _in_memory:
		return
	var temp: String = PATH + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_warning("Saves: can't write %s (%s)" % [temp, error_string(FileAccess.get_open_error())])
		return
	file.store_string(save.to_json() + "\n")
	file.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(PATH))


## What the slot holds, in a line: "Floor 1 · Surge 7 · 312 felled".
func summary() -> String:
	if setup == null:
		return ""
	var floor_name: String = EnumLevel.name(setup.floor).capitalize()
	return "%s · Surge %d · %d felled" % [floor_name, setup.surges, setup.kills]


## The file's save, unless it doesn't read or another version made it: then it goes aside, and `problem` says why.
func _load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var text: String = FileAccess.get_file_as_string(PATH)
	problem = UnifiedSetup.json_problem(text)
	if problem == "":
		var read: UnifiedSetup = UnifiedSetup.from_json(text)
		if read.version != Unified.constants.save_version:
			problem = "it is version %d, this game reads version %d" % [read.version, Unified.constants.save_version]
		else:
			setup = read
			saved_at = FileAccess.get_modified_time(PATH)
			return
	print("Saves: %s doesn't continue (%s): kept as %s" % [PATH, problem, BAD_PATH.get_file()])
	DirAccess.rename_absolute(ProjectSettings.globalize_path(PATH), ProjectSettings.globalize_path(BAD_PATH))
