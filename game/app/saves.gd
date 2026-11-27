class_name Saves
extends RefCounted
## The one save slot, `user://save.json`: the Setup that continues the party's run, as its JSON (UnifiedSetup.to_json)
## and nothing else, so a later build reads it back by field name. Game keeps one Saves: it writes each save the session
## hands over (save_changed) when this machine hosts or plays alone, and the title offers Continue from it while it
## holds a run (has_run: a save of the hub's floor is a run that ended, or the Pit's, with nothing to continue). Written
## through UserFile: beside first, then moved over the old file, so a crash or a full disk never leaves half a save; a
## write that fails keeps the session's copy (`setup`) and says so in the log.
##
## A save that doesn't read (json_problem), or that another version of the game made (its version isn't this build's
## Unified.constants.save_version), is never dropped: it is moved aside to `save.bad.json` and `problem` says why, once
## (the title tells the player). Under `--no-settings` (tool and drive runs) nothing is read or written: the slot lives
## in memory, so a check never touches the player's crypt (the app checks name a file of their own).

## The slot's file.
const PATH: String = "user://save.json"

## The save in the slot (null: none): what Continue starts from, while it holds a run.
var setup: UnifiedSetup = null
## Why the file in the slot didn't read at load (""; it did, or there was none): the title tells the player once.
var problem: String = ""
## The slot's file, and where one that doesn't read is kept.
var path: String = PATH
var bad_path: String = ""

## Nothing touches the file (`--no-settings`).
var _in_memory: bool = false


## The slot in `slot_path` (the app checks name their own), or in memory only.
func _init(in_memory: bool, slot_path: String = PATH) -> void:
	_in_memory = in_memory
	path = slot_path
	bad_path = path.get_basename() + ".bad.json"
	if not in_memory:
		_load()


## Keeps `save` in the slot (a host's or a single player's save_changed); false when its file couldn't be written (the
## slot still holds it for this session).
func keep(save: UnifiedSetup) -> bool:
	setup = save
	return _in_memory or UserFile.write(path, save.to_json() + "\n")


## A new game's Setup: the session starts in the hub, where the party sets its run at the shrines.
static func new_game() -> UnifiedSetup:
	var fresh := UnifiedSetup.new()
	fresh.floor = EnumLevel.HUB
	return fresh


## Whether the slot holds a run to continue: a save on one of the run's floors, not the hub's.
func has_run() -> bool:
	return setup != null and setup.floor != EnumLevel.HUB


## What the slot holds, in a line: "Floor 2 · Hard · 2 lives · 340 gold" ("": no run).
func summary() -> String:
	if not has_run():
		return ""
	var floor_name: String = EnumLevel.name(setup.floor).capitalize()
	var lives: String = "1 life" if setup.lives == 1 else "%d lives" % setup.lives
	return "%s · %s · %s · %d gold" % [floor_name, EnumDifficulty.name(setup.difficulty).capitalize(), lives, setup.gold]


## The file's save, unless it doesn't read or another version made it: then it goes aside, and `problem` says why.
func _load() -> void:
	if not UserFile.exists(path):
		return
	var text: String = UserFile.read(path)
	problem = UnifiedSetup.json_problem(text)
	if problem == "":
		var read: UnifiedSetup = UnifiedSetup.from_json(text)
		if read.version == Unified.constants.save_version:
			setup = read
			return
		problem = "it is version %d, this game reads version %d" % [read.version, Unified.constants.save_version]
	print("Saves: %s doesn't continue (%s): kept as %s" % [path, problem, bad_path.get_file()])
	UserFile.set_aside(path, bad_path)
