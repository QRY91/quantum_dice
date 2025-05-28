# res://scripts/resources/GlyphData.gd
class_name GlyphData
extends Resource

## Unique identifier for this glyph (e.g., "dice_1", "roman_x", "card_ace_hearts")
@export var id: String = "unknown_glyph"

## Name displayed to the player (e.g., "1", "X", "Ace of Hearts")
@export var display_name: String = "Unknown"

## Category of the glyph (e.g., "dice", "roman", "card", "superposition", "quantum_particle")
@export var type: String = "none"

## Base score value this glyph provides when rolled.
@export var value: int = 0

## Texture used to visually represent this glyph in the game.
@export var texture: Texture2D

@export var suit: String = ""

# --- Superposition Properties ---
@export var is_superposition: bool = false
@export var superposition_outcomes: Array[GlyphData] = []

# --- Entanglement Properties (Phase 1) ---
## If true, this glyph is part of an entangled set.
@export var is_entangled: bool = false

## Shared identifier for glyphs in the same entanglement set (e.g., &"photon_pair_01").
@export var entanglement_id: StringName = &"" # Use StringName for optimized string comparisons

## Defines the type of effect this entangled glyph participates in.
enum EntangledEffectType {
	NONE,
	SHARED_MOMENTUM_SCORE_BONUS, # For Photon Twins: partner on die adds its value
	# Future types:
	# SYNERGY_ECHO,
	# TRACK_PRESENCE_FIELD_INITIATOR,
	# TRACK_PRESENCE_FIELD_REACTOR
}
@export var entangled_effect_type: EntangledEffectType = EntangledEffectType.NONE

# Note: 'entangled_partner_bonus_value' is deferred as per spec,
# as Photon Twins use the partner's own base_value.

# Constructor (updated for new entanglement fields, though mostly for programmatic use)
func _init(p_id: String = "", p_display_name: String = "", p_type: String = "", p_value: int = 0, p_texture: Texture2D = null, p_suit: String = "",
			p_is_superposition: bool = false, p_superposition_outcomes: Array[GlyphData] = [],
			p_is_entangled: bool = false, p_entanglement_id: StringName = &"", p_entangled_effect_type: EntangledEffectType = EntangledEffectType.NONE):
	if p_id != "": id = p_id
	if p_display_name != "": display_name = p_display_name
	if p_type != "": type = p_type
	value = p_value
	if p_texture != null: texture = p_texture
	if p_suit != "": suit = p_suit
	
	is_superposition = p_is_superposition
	if not p_superposition_outcomes.is_empty():
		superposition_outcomes = p_superposition_outcomes.duplicate()
	else:
		superposition_outcomes = []
		
	is_entangled = p_is_entangled
	if p_entanglement_id != &"": entanglement_id = p_entanglement_id # Check against empty StringName
	entangled_effect_type = p_entangled_effect_type


func get_tooltip_text() -> String:
	var base_text = "%s (Type: %s, Value: %d)" % [display_name, type, value]
	if is_superposition:
		base_text += " [Superposition: "
		if superposition_outcomes.is_empty():
			base_text += "No outcomes defined!"
		else:
			var outcome_names: Array[String] = []
			for outcome_glyph in superposition_outcomes:
				if is_instance_valid(outcome_glyph): outcome_names.append(outcome_glyph.display_name)
				else: outcome_names.append("Invalid Outcome")
			base_text += ", ".join(outcome_names)
		base_text += "]"
	
	if is_entangled:
		base_text += " [Entangled: %s, Effect: %s]" % [str(entanglement_id).trim_prefix("&"), EntangledEffectType.keys()[entangled_effect_type]]
		# Example specific tooltip for Photon Twins (can be expanded or made more generic)
		if entangled_effect_type == EntangledEffectType.SHARED_MOMENTUM_SCORE_BONUS:
			if id == "photon_alpha": # Assuming IDs for Photon Twins
				base_text += " (If Photon Beta is on your dice, it adds its score.)"
			elif id == "photon_beta":
				base_text += " (If Photon Alpha is on your dice, it adds its score.)"
			else: # Generic message if IDs don't match expected Photon Twins
				base_text += " (Partner on dice contributes score.)"

	return base_text

func resolve_superposition() -> GlyphData:
	if not is_superposition or superposition_outcomes.is_empty():
		return self

	var valid_outcomes: Array[GlyphData] = []
	for outcome in superposition_outcomes:
		if is_instance_valid(outcome) and outcome is GlyphData:
			if outcome.is_superposition:
				printerr("GlyphData Error: Superposition glyph '%s' has another superposition glyph '%s' as an outcome." % [id, outcome.id])
			else:
				valid_outcomes.append(outcome)
		else:
			printerr("GlyphData Error: Superposition glyph '%s' has an invalid outcome defined." % id)
	
	if valid_outcomes.is_empty():
		printerr("GlyphData Error: Superposition glyph '%s' has no valid outcomes. Returning self." % id)
		return self

	var random_index = randi() % valid_outcomes.size()
	return valid_outcomes[random_index]
