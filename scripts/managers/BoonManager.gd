# res://scripts/managers/BoonManager.gd
# TABS FOR INDENTATION
extends Node

signal boon_activated(boon_id: StringName, boon_display_name: String, boon_description: String)
# Optional: signal boon_effect_applied(effect_description: String)

# --- Data Structures ---
# RUNE_PHRASES could also be loaded from a JSON/CSV file for easier editing
# Using StringName for boon IDs to align with Game.gd constants
const SUN_POWER_BOON_ID: StringName = &"sun_power" 
const WATER_FLOW_BOON_ID: StringName = &"water_flow"

const RUNE_PHRASES: Dictionary = {
	SUN_POWER_BOON_ID: { 
		"id": SUN_POWER_BOON_ID, # Using StringName constant
		"display_name": "Sun's Radiance", 
		"runes_required": ["rune_sowilo", "rune_fehu"], # List of GlyphData IDs (these are still strings, assuming GlyphData.id is string)
		"boon_description": "All 'dice' type glyphs score +2 points for the rest of the run."
	},
	WATER_FLOW_BOON_ID: {
		"id": WATER_FLOW_BOON_ID, # Using StringName constant
		"display_name": "Water's Flow",
		"runes_required": ["rune_laguz", "rune_ansuz"], 
		"boon_description": "Gain +1 max roll per round for the rest of the run."
	}
	# Add more phrases here, using StringName constants as keys and for "id"
}

# --- State Variables ---
var active_boons: Dictionary = {} # Key: boon_id (StringName), Value: true 

# Boon effect modifiers (queried by other systems)
var run_score_multiplier: float = 1.0
var extra_points_per_dice_glyph: int = 0
var extra_max_rolls: int = 0
# Add more specific boon effect variables as new boons are designed

func _ready():
	print("BoonManager: Initialized.")
	# If RUNE_PHRASES were loaded from a file, do it here.

func reset_for_new_run():
	active_boons.clear()
	run_score_multiplier = 1.0
	extra_points_per_dice_glyph = 0
	extra_max_rolls = 0
	print("BoonManager: All boons and effects reset for new run.")

# Called by Game.gd (or a future SynergyManager)
# Takes the list of rune glyph IDs currently in the roll history for this turn's check
func check_and_activate_rune_phrases(current_runes_in_history_ids: Array[String]) -> Array[Dictionary]: # Returns array of activated boon info
	var newly_activated_boon_messages: Array[Dictionary] = []
	if current_runes_in_history_ids.is_empty():
		return newly_activated_boon_messages

	# print("BoonManager: Checking phrases with runes: ", current_runes_in_history_ids)
	for phrase_key_string_name in RUNE_PHRASES: # phrase_key is now StringName
		var phrase_data: Dictionary = RUNE_PHRASES[phrase_key_string_name]
		var phrase_id_string_name: StringName = phrase_data.id # This is already a StringName
		
		if not active_boons.has(phrase_id_string_name): # Only check if not already active
			var all_required_runes_found: bool = true
			for required_rune_id in phrase_data.runes_required: # required_rune_id is String
				if not required_rune_id in current_runes_in_history_ids:
					all_required_runes_found = false
					break # Missing a required rune for this phrase
			
			if all_required_runes_found:
				print("BoonManager: BOON ACTIVATED - ", phrase_data.display_name)
				active_boons[phrase_id_string_name] = true # Mark as active
				_apply_boon_effect(phrase_id_string_name)   # Apply its immediate/ongoing effects
				
				newly_activated_boon_messages.append({
					"name": phrase_data.display_name,
					"description": phrase_data.boon_description
					# "id": phrase_id_string_name # Game.gd doesn't seem to need the ID back here currently
				})
				emit_signal("boon_activated", phrase_id_string_name, phrase_data.display_name, phrase_data.boon_description)
	
	return newly_activated_boon_messages

func _apply_boon_effect(boon_id_string_name: StringName): # Parameter is now StringName
	# This function updates the manager's state variables based on the boon.
	# Other systems will query these variables.
	match boon_id_string_name:
		SUN_POWER_BOON_ID: # Match against StringName constant
			extra_points_per_dice_glyph = 2
			print("BoonManager: Sun's Radiance effect applied (+2 pts for dice glyphs).")
			# emit_signal("boon_effect_applied", "Dice glyphs +2 pts")
		WATER_FLOW_BOON_ID: # Match against StringName constant
			extra_max_rolls += 1 # This can stack if boon is somehow re-acquired
			print("BoonManager: Water's Flow effect applied (+1 max roll). Current extra max rolls: ", extra_max_rolls)
			# emit_signal("boon_effect_applied", "+1 max roll")
		_:
			printerr("BoonManager: Attempted to apply unknown boon effect for id: ", boon_id_string_name)

# --- Getters for other systems to query boon effects ---
func get_extra_points_for_dice_glyph() -> int:
	return extra_points_per_dice_glyph if active_boons.has(SUN_POWER_BOON_ID) else 0 # Ensure boon is active, using StringName

func get_extra_max_rolls() -> int:
	return extra_max_rolls # This value accumulates if Water's Flow can be activated multiple times (currently not)

func get_run_score_multiplier() -> float:
	return run_score_multiplier

func is_boon_active(boon_id_string_name: StringName) -> bool: # Parameter is now StringName
	return active_boons.has(boon_id_string_name)
