## Autoload. Holds the character roster plus the local player's choices.
extends Node

const CHARACTER_DIR := "res://resources/characters"

var characters: Array[CharacterData] = []
var player_name: String = "Player"
var selected_character_id: String = ""


func _ready() -> void:
	reload_characters()
	player_name = "Player%d" % (randi() % 900 + 100)


## Rescans the character folder. Any `.tres` of type CharacterData is picked up,
## so importing a new character is just "save the resource in that folder".
func reload_characters() -> void:
	characters.clear()
	var dir := DirAccess.open(CHARACTER_DIR)
	if dir == null:
		push_warning("No character folder at %s" % CHARACTER_DIR)
		return
	var files := dir.get_files()
	files.sort()
	for file in files:
		# Exported builds rename resources to *.remap.
		var file_name := file.trim_suffix(".remap")
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var res: Resource = load(CHARACTER_DIR.path_join(file_name))
		if res is CharacterData:
			if res.id.is_empty():
				push_warning("Character %s has an empty id, skipping." % file_name)
				continue
			characters.append(res)
		else:
			push_warning("%s is not a CharacterData resource." % file_name)
	if characters.is_empty():
		push_warning("No characters found in %s" % CHARACTER_DIR)
	elif get_character(selected_character_id) == null:
		selected_character_id = characters[0].id


func get_character(character_id: String) -> CharacterData:
	for c in characters:
		if c.id == character_id:
			return c
	return null


## Never returns null once at least one character exists.
func get_character_or_default(character_id: String) -> CharacterData:
	var found := get_character(character_id)
	if found != null:
		return found
	return characters[0] if not characters.is_empty() else null
