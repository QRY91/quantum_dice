# res://scripts/resources/GlyphData.gd
class_name GlyphData
extends Resource

## Unique identifier for this glyph (e.g., "dice_1", "roman_x", "card_ace_hearts")
@export var id: String = "unknown_glyph"

## Name displayed to the player (e.g., "1", "X", "Ace of Hearts")
@export var display_name: String = "Unknown"

## Category of the glyph (e.g., "dice", "roman", "card", "superposition")
## Used for synergy checks and potentially other logic.
@export var type: String = "none"

## Base score value this glyph provides when rolled.
## For superposition glyphs, this value might be 0 or represent a base value before collapse.
@export var value: int = 0

## Texture used to visually represent this glyph in the game.
## For superposition glyphs, this is the "uncollapsed" state texture.
@export var texture: Texture2D

@export var suit: String = "" # e.g., "hearts", "diamonds", "clubs", "spades", or "" if not applicable

# --- Superposition Properties ---
## If true, this glyph is a superposition glyph and will collapse into one of its outcomes.
@export var is_superposition: bool = false

## Array of GlyphData resources that this superposition glyph can collapse into.
## Each element should be a valid GlyphData resource itself (e.g., a dice_1.tres, rune_fehu.tres).
## IMPORTANT: These outcome glyphs should NOT themselves be superposition glyphs to avoid infinite loops.
@export var superposition_outcomes: Array[GlyphData] = []

## Optional: Texture to use during the "collapse" animation, if different from the main texture.
# @export var collapse_animation_texture: Texture2D 


# Optional fields you might add later:
# @export var roll_sfx: AudioStream
# @export var description: String = ""
# @export var rarity: int = 1 # e.g., 1 for common, 5 for legendary

# Basic constructor (mainly for programmatic creation, less so for .tres files)
func _init(p_id: String = "", p_display_name: String = "", p_type: String = "", p_value: int = 0, p_texture: Texture2D = null, p_suit: String = "", p_is_superposition: bool = false, p_superposition_outcomes: Array[GlyphData] = []):
	if p_id != "": id = p_id
	if p_display_name != "": display_name = p_display_name
	if p_type != "": type = p_type
	value = p_value
	if p_texture != null: texture = p_texture
	if p_suit != "": suit = p_suit
	
	is_superposition = p_is_superposition
	if not p_superposition_outcomes.is_empty(): # Check if the passed array is not empty
		superposition_outcomes = p_superposition_outcomes.duplicate() # Make a copy
	else: # Ensure it's an empty array if nothing is passed
		superposition_outcomes = []


# Helper function for debugging or simple display
func get_tooltip_text() -> String:
	var base_text = "%s (Type: %s, Value: %d)" % [display_name, type, value]
	if is_superposition:
		base_text += " [Superposition: "
		if superposition_outcomes.is_empty():
			base_text += "No outcomes defined!"
		else:
			var outcome_names: Array[String] = []
			for outcome_glyph in superposition_outcomes:
				if is_instance_valid(outcome_glyph):
					outcome_names.append(outcome_glyph.display_name)
				else:
					outcome_names.append("Invalid Outcome")
			base_text += ", ".join(outcome_names)
		base_text += "]"
	return base_text

## Resolves the superposition by randomly picking one of its outcomes.
## Returns the chosen GlyphData resource.
## Returns self if not a superposition glyph or if no outcomes are defined.
func resolve_superposition() -> GlyphData:
	if not is_superposition or superposition_outcomes.is_empty():
		return self # Not a superposition glyph or no outcomes to choose from

	# Ensure outcomes are valid GlyphData instances
	var valid_outcomes: Array[GlyphData] = []
	for outcome in superposition_outcomes:
		if is_instance_valid(outcome) and outcome is GlyphData:
			if outcome.is_superposition: # Prevent nested superposition for now
				printerr("GlyphData Error: Superposition glyph '%s' has another superposition glyph '%s' as an outcome. This is not allowed." % [id, outcome.id])
				# Fallback: either return self, or filter this out. For now, filter out.
			else:
				valid_outcomes.append(outcome)
		else:
			printerr("GlyphData Error: Superposition glyph '%s' has an invalid outcome defined." % id)
	
	if valid_outcomes.is_empty():
		printerr("GlyphData Error: Superposition glyph '%s' has no valid outcomes after filtering. Returning self." % id)
		return self # No valid outcomes left

	var random_index = randi() % valid_outcomes.size()
	return valid_outcomes[random_index]
