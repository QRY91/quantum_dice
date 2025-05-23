# res://scripts/resources/GlyphData.gd
class_name GlyphData
extends Resource

## Unique identifier for this glyph (e.g., "dice_1", "roman_x", "card_ace_hearts")
@export var id: String = "unknown_glyph"

## Name displayed to the player (e.g., "1", "X", "Ace of Hearts")
@export var display_name: String = "Unknown"

## Category of the glyph (e.g., "dice", "roman", "card")
## Used for synergy checks and potentially other logic.
@export var type: String = "none"

## Base score value this glyph provides when rolled.
@export var value: int = 0

## Texture used to visually represent this glyph in the game.
@export var texture: Texture2D

# Optional fields you might add later:
# @export var roll_sfx: AudioStream
# @export var description: String = ""
# @export var rarity: int = 1 # e.g., 1 for common, 5 for legendary

# Basic constructor (mainly for programmatic creation, less so for .tres files)
func _init(p_id: String = "", p_display_name: String = "", p_type: String = "", p_value: int = 0, p_texture: Texture2D = null):
	if p_id != "": id = p_id
	if p_display_name != "": display_name = p_display_name
	if p_type != "": type = p_type
	# Allow 0 as a valid value, so don't check p_value != 0
	value = p_value
	if p_texture != null: texture = p_texture

# Helper function for debugging or simple display
func get_tooltip_text() -> String:
	return "%s (Type: %s, Value: %d)" % [display_name, type, value]
