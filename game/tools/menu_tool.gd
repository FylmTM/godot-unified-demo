class_name MenuTool
extends UnifiedTool
## The base of the tool scripts that drive Crypt Crew's own menus (ui_walk): its screens and their buttons by unique
## name, the app's overlays, and the app's flow. A tool script compiles before the autoloads exist, so it reaches
## the Game autoload through the tree, untyped (`game`), and reads what it needs into typed values here.


## The title screen, while the menu is the current scene (else null).
func title() -> Control:
	return current_scene.get_node_or_null(^"UI/Title") as Control if scene_is("Menu") else null


## Clicks a title screen button by its unique name (NewGame, Quit).
func click_title(unique_name: String) -> void:
	await click(find(title(), "%" + unique_name) as Control)


## The title screen's control `unique_name` (null, failing the run, when it isn't there).
func title_control(unique_name: String) -> Control:
	return find(title(), "%" + unique_name) as Control


## One of the app's overlays (game/app/game.tscn): Connecting, Dialog, Toasts.
func overlay(overlay_name: String) -> Control:
	return find(game, "Overlays/" + overlay_name) as Control


## The app's flow (Game.flow) by its name: MENU, STARTING, PLAYING, QUITTING.
func flow_name() -> String:
	var script: Script = game.get_script()
	var flows: Dictionary = script.get_script_constant_map()[&"Flow"]
	var flow: int = game.get(&"flow")
	return str(flows.find_key(flow))


## A player setting (the Settings autoload's property).
func setting(setting_name: StringName) -> Variant:
	return root.get_node(^"Settings").get(setting_name)


## Sets a player setting, as the settings screen will.
func set_setting(setting_name: StringName, value: Variant) -> void:
	root.get_node(^"Settings").set(setting_name, value)


## The local player's hero view (null until it has one).
func local_hero() -> Node3D:
	if session == null:
		return null
	return session.get_player_view(EnumView.HERO, session.local_player) as Node3D
