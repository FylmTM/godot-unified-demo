class_name Heroes
extends RefCounted
## The hero classes as the player meets them: each one's name, a line of what it does today, its portrait, and the
## Profile a player who picks it brings into a session. A pick is the sim's `Class` (EnumClass), Any included: Any is a
## real choice (a late joiner can't see the party before it arrives), which the sim resolves on arrival to a class
## nobody plays, or the one the player played before. Two players may pick the same class: the sim honours a wish
## without looking at who else has it.
##
## profile() is where a pick becomes what a player brings: milestone 7's unlocks and progress across runs join the
## Profile here.

## Where each class's portrait is (game/tools/render_portraits.gd renders them from the hero scenes).
const PORTRAITS: String = "res://game/ui/portraits/%s.png"


## The picks in the order a player steps through them: Any first, then the four classes.
static func choices() -> Array[int]:
	return [EnumClass.ANY, EnumClass.KNIGHT, EnumClass.BARBARIAN, EnumClass.MAGE, EnumClass.ROGUE]


## The four classes (every pick but Any).
static func classes() -> Array[int]:
	return [EnumClass.KNIGHT, EnumClass.BARBARIAN, EnumClass.MAGE, EnumClass.ROGUE]


## A pick's name as the player reads it ("Knight"; Any is "Any hero").
static func name_of(hero_class: int) -> String:
	return "Any hero" if hero_class == EnumClass.ANY else EnumClass.name(hero_class).capitalize()


## What a pick does today, in a line.
static func line_of(hero_class: int) -> String:
	match hero_class:
		EnumClass.KNIGHT:
			return "A quick sword arc, a shield on the arm."
		EnumClass.BARBARIAN:
			return "A wide, slow cleave that knocks skeletons back."
		EnumClass.MAGE:
			return "Bolts that burst among the skeletons."
		EnumClass.ROGUE:
			return "A crossbow that hits where you saw it."
	return "Whoever the party is missing."


## Player `player`'s class as the HUD's data says (Any while the HUD has no hero of theirs).
static func class_of(player: int) -> int:
	for hero: DataHudHero in Unified.data.hud.heroes:
		if hero.player == player:
			return hero.class
	return EnumClass.ANY


## A class's portrait (null for Any, and a class without one yet).
static func portrait(hero_class: int) -> Texture2D:
	if hero_class == EnumClass.ANY:
		return null
	var path: String = PORTRAITS % EnumClass.name(hero_class).to_lower()
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## The Profile a player who picked `hero_class` brings into a session.
static func profile(hero_class: int) -> UnifiedProfile:
	var made := UnifiedProfile.new()
	made.class = hero_class
	return made
